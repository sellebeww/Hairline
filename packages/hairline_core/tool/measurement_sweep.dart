// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// Synthetic sweeps behind docs/MEASUREMENT_NOTES.md. Every number there comes from
// this program (fixed seeds, parameters printed). Usage:
//   dart run tool/measurement_sweep.dart [section ...]
// Sections: ideal subpixel blur noise tilt illum geometry violations violations2 psfmismatch misfit align
// coverage timing. No section: all.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

const double mmPerPx = 0.06;
const int seeds = 6;

SyntheticCamera cam({double tilt = 0, double roll = 0, double distance = 180}) => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: distance,
      tiltDeg: tilt,
      tiltAzimuthDeg: 40,
      rollDeg: roll,
    );

final _psfCache = <String, PsfEstimate>{};
final _patchCache = <String, GrayPatch>{};

/// PSF from a marker frame at 0.2 mm/px with the same blur and noise (seed 3).
PsfEstimate psfFor(double sigma, double noise, {double? sigmaY, bool gamma = false, bool linearize = false}) =>
    _psfCache.putIfAbsent('$sigma/$noise/$sigmaY/$gamma/$linearize', () {
      final c = cam(distance: 600);
      final p = renderCrackPatch(
        camera: c,
        scene: sheetScene(sheetId: 0, paper: 0.8),
        halfSizeMm: 85,
        supersample: 2,
        psfSigmaPx: sigma,
        psfSigmaYPx: sigmaY,
        noiseSigma: noise,
        rng: Random(3),
      );
      var q = p;
      if (gamma) {
        for (var i = 0; i < q.data.length; i++) {
          q.data[i] = pow(q.data[i], 1 / 2.2).toDouble();
        }
        if (linearize) q = q.linearizedFromSrgb();
      }
      return estimatePsf(patch: q, h: c.h, sheetId: 0);
    });

final class Run {
  Run(this.err, this.m, this.rejected);
  final double err; // width error, mm (NaN if rejected)
  final FrameMeasurement? m;
  final RejectReason? rejected;
}

Run run({
  required double w,
  double sigma = 1.0,
  double noise = 0.005,
  double depth = 0.6,
  double dir = 20,
  double curv = 0,
  double tilt = 0,
  double roll = 0,
  double illum = 0,
  double dirErr = 0,
  double trueWidth = double.nan,
  Scene? scene,
  int seed = 1,
  PsfEstimate? psf,
  ProfileFitConfig config = const ProfileFitConfig(),
  double shape = defaultKernelShapeRelUncertainty,
  GrayPatch Function(GrayPatch)? post,
  double hScale = 1,
  double offsetMm = 0,
  int supersample = 4,
}) {
  final c = cam(tilt: tilt, roll: roll);
  final key = scene == null && post == null ? '$w/$sigma/$noise/$depth/$dir/$curv/$tilt/$roll/$illum/$offsetMm/$supersample/$seed' : null;
  final patch = (key != null ? _patchCache[key] : null) ?? renderCrackPatch(
    camera: c,
    scene: scene ?? crackScene(widthMm: w, depth: depth, directionDeg: dir, curvaturePerMm: curv, centerMm: Pt(-sin(dir * pi / 180) * offsetMm, cos(dir * pi / 180) * offsetMm)),
    halfSizeMm: 10,
    supersample: supersample,
    psfSigmaPx: sigma,
    illumGradX: illum,
    illumGradY: illum * 0.5,
    noiseSigma: noise,
    rng: Random(seed),
  );
  if (key != null) _patchCache[key] = patch;
  final hUsed = hScale == 1 ? c.h : mat3Mul(c.h, [hScale, 0, 0, 0, hScale, 0, 0, 0, 1]);
  final o = measureFrame(
    patch: post != null ? post(patch) : patch,
    h: hUsed,
    pointMm: const Pt(0, 0),
    directionDeg: dir + dirErr,
    sheetId: 0,
    psf: psf ?? psfFor(sigma, noise),
    config: config,
    kernelShapeRelUncertainty: shape,
  );
  final truth = trueWidth.isNaN ? w : trueWidth;
  return switch (o) {
    MeasureAccepted(:final measurement) => Run(measurement.widthMm - truth, measurement, null),
    MeasureRejected(:final reason) => Run(double.nan, null, reason),
  };
}

String um(double mm) => (mm * 1000).toStringAsFixed(1);

/// Summary row: bias, sd, rms (um), median u_frame, coverage at k=2, statuses.
String summarize(List<Run> rs) {
  final ok = rs.where((r) => r.m != null).toList();
  final rej = rs.length - ok.length;
  if (ok.isEmpty) return '| - | - | - | - | - | - | rejected $rej/${rs.length} |';
  final e = [for (final r in ok) r.err];
  final bias = mean(e), sd = sampleSd(e), rms = sqrt(mean([for (final x in e) x * x]));
  final u = median([for (final r in ok) r.m!.uFrameMm]);
  final misfit = median([for (final r in ok) r.m!.fit.misfitRel.isFinite ? 100 * r.m!.fit.misfitRel : 999.0]);
  final cov = ok.where((r) => r.err.abs() <= 2 * r.m!.uFrameMm).length / ok.length;
  final st = <String, int>{};
  for (final r in ok) {
    st[r.m!.status.code] = (st[r.m!.status.code] ?? 0) + 1;
  }
  final warns = {for (final r in ok) ...r.m!.warnings.map((w) => w.code)};
  return '| ${um(bias)} | ${um(sd)} | ${um(rms)} | ${um(u)} | ${(cov * 100).toStringAsFixed(0)}% | ${misfit.toStringAsFixed(2)} | '
      '${st.entries.map((x) => '${x.key} ${x.value}').join(', ')}${rej > 0 ? ', rejected $rej' : ''}${warns.isEmpty ? '' : ' [${warns.join(',')}]'} |';
}

const header = '| bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |\n|---|---|---|---|---|---|---|';

List<Run> many(Run Function(int seed) f) => [for (var s = 1; s <= seeds; s++) f(s)];

void section(String name, void Function() body, Set<String> want) {
  if (want.isNotEmpty && !want.contains(name)) return;
  print('\n### $name\n');
  body();
}

void main(List<String> args) {
  final want = args.toSet();
  print('Synthetic sweeps (SINTETIS). 0.06 mm/px at tilt 0, seeds 1..$seeds, patch seed per run; '
      'PSF from a marker frame (0.2 mm/px, seed 3) with the same blur and noise. Algorithm $measurementAlgorithmVersion.');

  section('ideal', () {
    print('Low noise 0.002, sigma 1 px, depth 0.6.\n\n| w (mm) $header');
    for (final w in [0.3, 0.5, 1.0, 2.0]) {
      print('| $w ${summarize(many((s) => run(w: w, noise: 0.002, seed: s)))}');
    }
  }, want);

  section('subpixel', () {
    print('Realistic contrast: depth 0.3, noise 0.02. Rows: w; columns of the table per sigma.\n');
    for (final sg in [0.6, 1.0, 1.5, 2.0]) {
      print('\n**sigma = $sg px generator** (apparent ${(sqrt(sg * sg + 1 / 12)).toStringAsFixed(3)} px)\n\n| w (mm) | w/sigma_app $header');
      for (final w in [1.0, 0.5, 0.3, 0.2, 0.1, 0.05]) {
        final app = sqrt(sg * sg + 1 / 12) * mmPerPx;
        print('| $w | ${(w / app).toStringAsFixed(2)} ${summarize(many((s) => run(w: w, sigma: sg, noise: 0.02, depth: 0.3, seed: s)))}');
      }
    }
  }, want);

  section('blur', () {
    print('w = 0.3 and 1.0 mm, noise 0.005, depth 0.6.\n\n| sigma (px) | w $header');
    for (final sg in [0.6, 0.8, 1.0, 1.5, 2.0, 2.5]) {
      for (final w in [0.3, 1.0]) {
        print('| $sg | $w ${summarize(many((s) => run(w: w, sigma: sg, seed: s)))}');
      }
    }
  }, want);

  section('noise', () {
    print('w = 0.3 and 1.0 mm, sigma 1 px, depth 0.3 (contrast 0.24).\n\n| noise sd | w $header');
    for (final n in [0.002, 0.005, 0.01, 0.02, 0.04, 0.08]) {
      for (final w in [0.3, 1.0]) {
        print('| $n | $w ${summarize(many((s) => run(w: w, noise: n, depth: 0.3, seed: s)))}');
      }
    }
  }, want);

  section('tilt', () {
    print('w = 0.5 mm, sigma 1 px, noise 0.005. Roll 15 deg for tilt > 0. PSF is the same in px.\n\n| tilt (deg) | w $header');
    for (final t in [0.0, 10.0, 20.0, 30.0]) {
      for (final w in [0.3, 0.5]) {
        print('| $t | $w ${summarize(many((s) => run(w: w, tilt: t, roll: t > 0 ? 15 : 0, seed: s)))}');
      }
    }
  }, want);

  section('illum', () {
    print('w = 0.5 mm, sigma 1 px, noise 0.005. Gradient across the patch (relative change, +-g/2).\n\n| gradient | w $header');
    for (final g in [0.0, 0.2, 0.5, 1.0]) {
      for (final w in [0.3, 0.5]) {
        print('| $g | $w ${summarize(many((s) => run(w: w, illum: g, seed: s)))}');
      }
    }
  }, want);

  section('geometry', () {
    print('Crack orientation (true direction; stored direction exact), w = 0.5 mm.\n\n| direction (deg) $header');
    for (final d in [0.0, 20.0, 45.0, 70.0, 90.0]) {
      print('| $d ${summarize(many((s) => run(w: 0.5, dir: d, seed: s)))}');
    }
    print('\nAxis-aligned cracks: the +10 um is the renderer (supersampling S=4 quantises every edge sample the same way). '
        'Exact grid arithmetic: 0.5 mm = 8.333 px; S=4 counts 8.5 px (+10 um), S=8 counts 8.25 px (-5 um).\n\n| direction (deg), supersample S $header');
    for (final (d, ss) in [(0.0, 4), (0.0, 8), (20.0, 8)]) {
      print('| $d, S=$ss ${summarize(many((s) => run(w: 0.5, dir: d, supersample: ss, seed: s)))}');
    }
    print('\nStored direction error (ridge must refine it), true direction 20 deg, w = 0.5 mm.\n\n| stored dir error (deg) $header');
    for (final e in [0.0, 3.0, 6.0, 10.0, 15.0]) {
      print('| $e ${summarize(many((s) => run(w: 0.5, dirErr: e, seed: s)))}');
    }
    print('\nCurved crack (circular arc), w = 0.5 mm, direction 20.\n\n| curvature (1/mm) | radius (mm) $header');
    for (final k in [0.0, 0.02, 0.05, 0.1, 0.2]) {
      print('| $k | ${k == 0 ? '-' : (1 / k).toStringAsFixed(0)} ${summarize(many((s) => run(w: 0.5, curv: k, seed: s)))}');
    }
    print('\nCurved, alignment on raw per-profile centres instead of the smoothed curve (config).\n\n| curvature (1/mm) | radius (mm) $header');
    for (final k in [0.05, 0.1, 0.2]) {
      print('| $k | ${(1 / k).toStringAsFixed(0)} ${summarize(many((s) => run(w: 0.5, curv: k, seed: s, config: const ProfileFitConfig(alignWithSmoothedCenters: false))))}');
    }
  }, want);

  section('violations', () {
    print('Assumption violations (comparison only). w = 0.5 mm nominal, sigma 1 px, noise 0.005, depth 0.6.\n');
    print('| case | what is the truth $header');
    // Rough edges: edge position wanders by a smooth random function (amplitude a, mm).
    for (final a in [0.03, 0.08, 0.15]) {
      final r = roughEdgeCrackScene(amplitudeMm: a);
      final sc = rotatedAboutOrigin(r.scene, 20);
      print('| rough edges, amplitude $a mm | mean width over 4 mm = ${r.meanWidthMm.toStringAsFixed(4)} ${summarize(many((s) => run(w: 0.5, scene: sc, trueWidth: r.meanWidthMm, seed: s)))}');
    }
    // Shadow on one side: the background on one side of the crack is scaled.
    for (final f in [0.9, 0.7, 0.5]) {
      final scene = rotatedAboutOrigin(withOneSidedShadow(crackScene(widthMm: 0.5, directionDeg: 0), f), 20);
      print('| shadow, one side x$f | 0.5 ${summarize(many((s) => run(w: 0.5, trueWidth: 0.5, scene: scene, seed: s)))}');
    }
    // Stain: dark Gaussian blob next to the crack.
    for (final amp in [0.1, 0.25, 0.4]) {
      final scene = rotatedAboutOrigin(withStain(crackScene(widthMm: 0.5, directionDeg: 0), amp), 20);
      print('| stain 0.9 mm beside, amp $amp | 0.5 ${summarize(many((s) => run(w: 0.5, trueWidth: 0.5, scene: scene, seed: s)))}');
    }
  }, want);

  section('violations2', () {
    print('More assumption violations. w = 0.5 mm, sigma 1 px, depth 0.6 unless noted.\n');
    print('| case | what is the truth $header');
    // Spatially correlated noise (demosaicing/JPEG-like): iid noise smoothed by [1 2 1]/4 twice, rescaled to sd 0.02.
    GrayPatch correlated(GrayPatch p) {
      final rng = Random(77);
      final w = p.width, h = p.height;
      var f = List<double>.generate(w * h, (_) => gaussian(rng));
      for (var pass = 0; pass < 2; pass++) {
        final g = List<double>.filled(w * h, 0);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final l = f[y * w + (x == 0 ? 0 : x - 1)], r = f[y * w + (x == w - 1 ? w - 1 : x + 1)];
            g[y * w + x] = 0.25 * l + 0.5 * f[y * w + x] + 0.25 * r;
          }
        }
        final k = List<double>.filled(w * h, 0);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final u = g[(y == 0 ? 0 : y - 1) * w + x], d = g[(y == h - 1 ? h - 1 : y + 1) * w + x];
            k[y * w + x] = 0.25 * u + 0.5 * g[y * w + x] + 0.25 * d;
          }
        }
        f = k;
      }
      final sd = sqrt(mean([for (final v in f) v * v]));
      final out = p.data;
      for (var i = 0; i < out.length; i++) {
        out[i] = (out[i] + 0.02 * f[i] / sd).clamp(0.0, 1.0);
      }
      return p;
    }

    print('| correlated noise sd 0.02 (iid estimate is blind to it) | 0.5 ${summarize(many((s) => run(w: 0.5, noise: 0, post: correlated, seed: s, psf: psfFor(1.0, 0.005))))}');
    // sRGB-like gamma encoding of the intensity (the adapter hands over JPEG values). PSF measured
    // from equally encoded markers; then the same with the adapter linearising first.
    GrayPatch gamma(GrayPatch p) {
      for (var i = 0; i < p.data.length; i++) {
        p.data[i] = pow(p.data[i], 1 / 2.2).toDouble();
      }
      return p;
    }

    GrayPatch gammaThenLinear(GrayPatch p) => gamma(p).linearizedFromSrgb();
    for (final w in [0.5, 0.2, 0.1]) {
      print('| gamma-encoded, w $w | $w ${summarize(many((s) => run(w: w, post: gamma, seed: s, psf: psfFor(1.0, 0.005, gamma: true))))}');
      print('| gamma-encoded then linearised, w $w | $w ${summarize(many((s) => run(w: w, post: gammaThenLinear, seed: s, psf: psfFor(1.0, 0.005, gamma: true, linearize: true))))}');
    }
    // A second parallel crack 2.5 mm away (inside the +-3 mm profile).
    for (final d in [2.5, 4.0]) {
      final base = crackScene(widthMm: 0.5, directionDeg: 0);
      final other = crackScene(widthMm: 0.5, directionDeg: 0, centerMm: Pt(0, d));
      final sc = rotatedAboutOrigin((x, y) => min(base(x, y), other(x, y)), 20);
      print('| second crack $d mm away | 0.5 ${summarize(many((s) => run(w: 0.5, trueWidth: 0.5, scene: sc, seed: s)))}');
    }
    // A bright (light) line instead of a dark crack.
    print('| bright line (efflorescence), depth -0.15 | - ${summarize(many((s) => run(w: 0.5, depth: -0.15, seed: s)))}');
    // Very wide crack: beyond the +-3 mm profile design.
    for (final w in [2.6, 3.4]) {
      print('| wide crack $w mm | $w ${summarize(many((s) => run(w: w, seed: s)))}');
    }
    // Homography scale error: the sheet frame is 1 percent too large/small.
    for (final k in [1.01, 0.99]) {
      print('| H scale x$k (mm wrong by 1 percent) | 0.5 ${summarize(many((s) => run(w: 0.5, hScale: k, seed: s)))}');
    }
  }, want);

  section('psfmismatch', () {
    print('The crack is blurred more than the marker edges (processing differs by contrast, 5.3a note). '
        'sigma_crack = f * sigma_edge (generator, px). w = 0.3 mm and 1.0 mm.\n\n| f | w $header');
    for (final f in [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]) {
      for (final w in [0.3, 1.0]) {
        print('| $f | $w ${summarize(many((s) => run(w: w, sigma: f, noise: 0.005, psf: psfFor(1.0, 0.005), seed: s)))}');
      }
    }
  }, want);

  section('coverage', () {
    print('Coverage over 30 noise realisations, sigma 1 px and 0.6 px, depth 0.3, noise 0.02. '
        'eps = kernel shape relative uncertainty added to u_sigma_w.\n');
    print('| sigma | w (mm) | eps | n | bias (um) | rms err (um) | mean u_fit (um) | mean u_frame (um) | rms/u_frame | frac abs(err)<=2u_fit | frac abs(err)<=2u_frame | below-limit |\n|---|---|---|---|---|---|---|---|---|---|---|---|');
    for (final sg in [0.6, 1.0]) {
      for (final w in [1.0, 0.5, 0.3, 0.2, 0.1, 0.05]) {
        for (final eps in [0.0, 0.05, 0.10]) {
          final all = [for (var s = 1; s <= 30; s++) run(w: w, sigma: sg, noise: 0.02, depth: 0.3, seed: s, shape: eps)];
          final rs = all.where((r) => r.m != null && r.m!.status != MeasureStatus.tidakTerukur).toList();
          if (rs.isEmpty) continue;
          final below = rs.where((r) => r.m!.status == MeasureStatus.dibawahBatasUkur).length;
          final rms = sqrt(mean([for (final r in rs) r.err * r.err]));
          final uf = mean([for (final r in rs) r.m!.uFitMm]);
          final ut = mean([for (final r in rs) r.m!.uFrameMm]);
          final c1 = rs.where((r) => r.err.abs() <= 2 * r.m!.uFitMm).length / rs.length;
          final c2 = rs.where((r) => r.err.abs() <= 2 * r.m!.uFrameMm).length / rs.length;
          print('| $sg | $w | $eps | ${rs.length} | ${um(mean([for (final r in rs) r.err]))} | ${um(rms)} | ${um(uf)} | ${um(ut)} | ${(rms / ut).toStringAsFixed(2)} | ${(c1 * 100).toStringAsFixed(0)}% | ${(c2 * 100).toStringAsFixed(0)}% | $below |');
        }
      }
    }
  }, want);

  section('misfit', () {
    print('Model-misfit diagnostics: ratio = final residual rms / noise-only expectation, rel = residual rms / dip depth. 3 seeds per row.\n');
    print('| case | ratio min..max | rel (percent) min..max | abs err (um) max |\n|---|---|---|---|');
    void row(String name, Run Function(int) f) {
      final rs = [for (var s = 1; s <= 3; s++) f(s)].where((r) => r.m != null).toList();
      if (rs.isEmpty) return;
      final ra = [for (final r in rs) r.m!.fit.misfitRatio];
      final rl = [for (final r in rs) 100 * r.m!.fit.residualRms / r.m!.fit.dipDepth];
      print('| $name | ${ra.reduce(min).toStringAsFixed(1)}..${ra.reduce(max).toStringAsFixed(1)} | ${rl.reduce(min).toStringAsFixed(2)}..${rl.reduce(max).toStringAsFixed(2)} | ${um(rs.map((r) => r.err.abs()).reduce(max))} |');
    }

    for (final sg in [0.6, 1.0, 2.0]) {
      for (final n in [0.002, 0.01, 0.04]) {
        for (final dp in [0.6, 0.3]) {
          for (final w in [0.2, 1.0, 2.0]) {
            row('CLEAN sigma $sg noise $n depth $dp w $w', (s) => run(w: w, sigma: sg, noise: n, depth: dp, seed: s));
          }
        }
      }
    }
    for (final a in [0.03, 0.08, 0.15]) {
      final r = roughEdgeCrackScene(amplitudeMm: a);
      final sc = rotatedAboutOrigin(r.scene, 20);
      row('VIOL rough edges $a', (s) => run(w: 0.5, scene: sc, trueWidth: 0.5, seed: s));
    }
    for (final f in [0.9, 0.7, 0.5]) {
      final sc = rotatedAboutOrigin(withOneSidedShadow(crackScene(widthMm: 0.5, directionDeg: 0), f), 20);
      row('VIOL shadow x$f', (s) => run(w: 0.5, trueWidth: 0.5, scene: sc, seed: s));
    }
    for (final amp in [0.1, 0.25, 0.4]) {
      final sc = rotatedAboutOrigin(withStain(crackScene(widthMm: 0.5, directionDeg: 0), amp), 20);
      row('VIOL stain $amp', (s) => run(w: 0.5, trueWidth: 0.5, scene: sc, seed: s));
    }
    GrayPatch gamma(GrayPatch p) {
      for (var i = 0; i < p.data.length; i++) {
        p.data[i] = pow(p.data[i], 1 / 2.2).toDouble();
      }
      return p;
    }

    row('VIOL gamma w 0.5', (s) => run(w: 0.5, post: gamma, seed: s, psf: psfFor(1.0, 0.005, gamma: true)));
    row('VIOL curved 0.2/mm', (s) => run(w: 0.5, curv: 0.2, seed: s));
    row('VIOL axis aligned 0 deg', (s) => run(w: 0.5, dir: 0, seed: s));
    row('VIOL psf mismatch x1.25 (w 0.3)', (s) => run(w: 0.3, sigma: 1.25, psf: psfFor(1.0, 0.005), seed: s));
  }, want);

  section('align', () {
    print('Pass-2 alignment: smoothed curve (default) versus the raw per-profile centres (literal 5.3). Low SNR: depth 0.3, noise 0.04, sigma 1 px; and a curved crack.\n');
    print('| case | alignment $header');
    for (final (label, w, k) in [('w 0.3, straight', 0.3, 0.0), ('w 0.15, straight', 0.15, 0.0), ('w 0.3, curvature 0.1/mm', 0.3, 0.1)]) {
      for (final smooth in [true, false]) {
        print('| $label | ${smooth ? 'smoothed' : 'raw c_j'} ${summarize([for (var s = 1; s <= 12; s++) run(w: w, curv: k, noise: 0.04, depth: 0.3, seed: s, config: ProfileFitConfig(alignWithSmoothedCenters: smooth))])}');
      }
    }
  }, want);

  section('timing', () {
    final c = cam(distance: 300);
    final frame = renderCrackPatch(
      camera: c,
      scene: sheetWithCrackScene(sheetId: 0, crack: crackScene(widthMm: 0.5, directionDeg: 20, background: 0.8)),
      halfSizeMm: 85,
      supersample: 2,
      psfSigmaPx: 1.0,
      noiseSigma: 0.005,
      rng: Random(9),
    );
    final times = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      measureFrame(patch: frame, h: c.h, pointMm: const Pt(0, 0), directionDeg: 20, sheetId: 0);
      times.add(sw.elapsedMilliseconds);
    }
    final small = renderCrackPatch(camera: cam(), scene: crackScene(widthMm: 0.5, directionDeg: 20), halfSizeMm: 10, psfSigmaPx: 1.0, noiseSigma: 0.005, rng: Random(9));
    final psf = psfFor(1.0, 0.005);
    final t2 = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      measureFrame(patch: small, h: cam().h, pointMm: const Pt(0, 0), directionDeg: 20, sheetId: 0, psf: psf);
      t2.add(sw.elapsedMilliseconds);
    }
    print('Full frame (markers + crack, patch ${frame.width}x${frame.height}, 0.1 mm/px) measureFrame ms over 5 runs: $times');
    print('Crack patch only (${small.width}x${small.height}, 0.06 mm/px, PSF given) measureFrame ms over 10 runs: $t2');
  }, want);
}
