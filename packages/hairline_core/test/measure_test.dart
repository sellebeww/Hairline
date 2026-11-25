// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

const double mmPerPx = 0.06;

SyntheticCamera cam({double tilt = 0, double roll = 0, double distance = 180}) => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: distance,
      tiltDeg: tilt,
      tiltAzimuthDeg: 40,
      rollDeg: roll,
    );

final _patches = <String, GrayPatch>{};

GrayPatch crackPatch({
  double w = 0.5,
  double dir = 20,
  double curv = 0,
  double sigma = 1.0,
  double sigmaY = double.nan,
  double noise = 0.005,
  double depth = 0.6,
  double tilt = 0,
  double roll = 0,
  double halfSize = 10,
  double satScale = 1,
  double illum = 0,
  int seed = 7,
  Scene? scene,
}) =>
    _patches.putIfAbsent(scene != null ? 'scene${scene.hashCode}/$sigma/$noise/$seed' : '$w/$dir/$curv/$sigma/$sigmaY/$noise/$depth/$tilt/$roll/$halfSize/$satScale/$illum/$seed', () {
      return renderCrackPatch(
        camera: cam(tilt: tilt, roll: roll),
        scene: scene ?? (x, y) => min(1.0, satScale * crackScene(widthMm: w, depth: depth, directionDeg: dir, curvaturePerMm: curv)(x, y)),
        illumGradX: illum,
        illumGradY: illum * 0.5,
        halfSizeMm: halfSize,
        supersample: 4,
        psfSigmaPx: sigma,
        psfSigmaYPx: sigmaY.isNaN ? null : sigmaY,
        noiseSigma: noise,
        rng: Random(seed),
      );
    });

/// PSF from a full marker frame at 0.2 mm/px (blur is in image pixels, so it also
/// describes the 0.06 mm/px crack views with the same generator sigma).
PsfEstimate framePsf({double sigma = 1.0, double? sigmaY, double noise = 0.005}) {
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
  return estimatePsf(patch: p, h: c.h, sheetId: 0);
}

final PsfEstimate psf1 = framePsf();

FrameMeasurement accepted(MeasureOutcome o) {
  expect(o, isA<MeasureAccepted>(), reason: o is MeasureRejected ? '${o.reason.code}: ${o.message}' : null);
  return (o as MeasureAccepted).measurement;
}

MeasureOutcome measure(
  GrayPatch p, {
  PsfEstimate? psf,
  Pt point = const Pt(0, 0),
  double dir = 20,
  double tilt = 0,
  double roll = 0,
  ProfileFitConfig config = const ProfileFitConfig(),
}) =>
    measureFrame(
      patch: p,
      h: cam(tilt: tilt, roll: roll).h,
      pointMm: point,
      directionDeg: dir,
      sheetId: 0,
      psf: psf ?? psf1,
      config: config,
    );

void main() {
  group('ideal case, 0.06 mm/px, tilt 0, sigma 1 px, low noise (PSF from marker edges)', () {
    for (final w in [0.3, 0.5, 1.0, 2.0]) {
      test('width $w mm', () {
        final m = accepted(measure(crackPatch(w: w, noise: 0.002)));
        expect(m.status, MeasureStatus.terukur);
        expect(m.reportableWidthMm, isNotNull);
        // Tolerance from analysis: the PSF edge estimate has a scatter of 0.05 sigma (psf_test),
        // which moves w by u_sigma_w (reported); fit noise adds u_fit; kernel-shape and
        // interpolation bias is < 1 um (profile_fit_test). So |err| <= 3 u_frame + 1.5 um.
        expect((m.widthMm - w).abs(), lessThanOrEqualTo(3 * m.uFrameMm + 0.0015), reason: 'err=${m.widthMm - w} u=${m.uFrameMm}');
        // ...and the absolute accuracy is good in practice:
        expect((m.widthMm - w).abs(), lessThan(0.006));
        expect(m.mmPerPx, closeTo(0.06, 1e-3));
      });
    }
  });

  group('sub-pixel widths: honest (realistic contrast: depth 0.3, noise 0.02)', () {
    final widths = [1.0, 0.3, 0.1, 0.05];

    FrameMeasurement run(double w, int seed) =>
        accepted(measure(crackPatch(w: w, depth: 0.3, noise: 0.02, seed: seed)));

    test('every sub-pixel result is covered by its uncertainty or is not reported as a number', () {
      for (final w in [0.1, 0.05]) {
        for (var seed = 1; seed <= 8; seed++) {
          final m = run(w, seed);
          if (m.status == MeasureStatus.terukur) {
            // Coverage at 3 u_frame (SINTETIS coverage at 2 u is 97 percent at w/sigma 1.25 to 2.5, see notes).
            expect((m.widthMm - w).abs(), lessThanOrEqualTo(3 * m.uFrameMm), reason: 'w=$w seed=$seed err=${m.widthMm - w} u=${m.uFrameMm}');
          } else {
            expect(m.reportableWidthMm, isNull, reason: 'no width number when not TERUKUR');
          }
        }
      }
    });

    test('u_frame and u_frame / w grow monotonically as w/sigma shrinks (median over 5 seeds)', () {
      final u = <double>[], rel = <double>[];
      for (final w in widths) {
        final us = [for (var s = 1; s <= 5; s++) run(w, s).uFrameMm];
        u.add(median(us));
        rel.add(median(us) / w);
      }
      for (var i = 1; i < widths.length; i++) {
        expect(u[i], greaterThan(u[i - 1] * 0.9), reason: 'u: w=${widths[i]} ${u[i]} vs w=${widths[i - 1]} ${u[i - 1]}');
        expect(rel[i], greaterThan(rel[i - 1]), reason: 'u/w: w=${widths[i]} ${rel[i]} vs ${rel[i - 1]}');
      }
      expect(u.last, greaterThan(3 * u.first));
      expect(rel.last, greaterThan(20 * rel.first)); // 5 percent of 1 mm vs 0.05 mm
    });

    test('the floor is max(0.5 mm/px, 2 u_frame)', () {
      final m = run(0.05, 1);
      expect(m.floorMm, closeTo(max(0.5 * m.mmPerPx, 2 * m.uFrameMm), 1e-12));
    });

    test('a wide crack is TERUKUR and the floor is below it', () {
      final m = run(1.0, 1);
      expect(m.status, MeasureStatus.terukur);
      expect(m.floorMm, lessThan(m.widthMm));
      expect(m.floorMm, greaterThanOrEqualTo(0.5 * m.mmPerPx));
    });

    test('a crack below the floor is DI_BAWAH_BATAS_UKUR and shows no width', () {
      // A very noisy, blurred, narrow crack: u_frame is large, floor above w.
      final psf = framePsf(sigma: 2.0, noise: 0.005);
      final o = measure(crackPatch(w: 0.05, sigma: 2.0, depth: 0.6, noise: 0.005), psf: psf);
      final m = accepted(o);
      expect(m.status, MeasureStatus.dibawahBatasUkur);
      expect(m.reportableWidthMm, isNull);
      expect(m.floorMm, greaterThan(m.widthMm));
    });
  });

  group('tracking from the stored point', () {
    final a = 20 * pi / 180;
    Pt shifted(double d) => Pt(-sin(a) * d, cos(a) * d);

    test('stored point 1 mm off the crack: the same width is recovered', () {
      final p = crackPatch(w: 0.5);
      final base = accepted(measure(p));
      final off = accepted(measure(p, point: shifted(1.0), dir: 24));
      expect(off.trackingOffsetMm, closeTo(1.0, 0.06));
      expect(off.widthMm, closeTo(base.widthMm, 0.003));
      expect(off.directionDeg, closeTo(20, 2.0));
    });

    test('stored point 2 mm off: rejected, not measured on the wrong spot', () {
      final o = measure(crackPatch(w: 0.5), point: shifted(2.0));
      expect(o, isA<MeasureRejected>());
      expect((o as MeasureRejected).reason, RejectReason.crackNotFound);
      expect(o.message, contains('radius'));
    });
  });

  group('rejections have a specific reason', () {
    test('blur above the gate (sigma 3.2 px)', () {
      final psf = framePsf(sigma: 3.2);
      final o = measure(crackPatch(w: 1.0, sigma: 3.2), psf: psf);
      expect((o as MeasureRejected).reason, RejectReason.blurTooLarge);
    });

    test('anisotropic blur above the gate (sigma 1 x 2.5 px)', () {
      final psf = framePsf(sigma: 1.0, sigmaY: 2.5);
      expect(psf.anisotropy, greaterThan(1.6));
      final o = measure(crackPatch(w: 1.0, sigma: 1.0, sigmaY: 2.5), psf: psf);
      expect((o as MeasureRejected).reason, RejectReason.blurAnisotropic);
    });

    test('saturated ROI (bright background clipped)', () {
      final o = measure(crackPatch(w: 1.0, satScale: 1.4));
      expect((o as MeasureRejected).reason, RejectReason.saturated);
    });

    test('patch too small', () {
      final o = measure(crackPatch(w: 0.5, halfSize: 3));
      expect((o as MeasureRejected).reason, RejectReason.patchTooSmall);
    });

    test('point outside the cut-out window or not finite', () {
      expect((measure(crackPatch(), point: const Pt(40, 0)) as MeasureRejected).reason, RejectReason.invalidInput);
      expect((measure(crackPatch(), point: const Pt(double.nan, 0)) as MeasureRejected).reason, RejectReason.invalidInput);
    });

    test('a degenerate or non-finite homography is a rejection, not an exception', () {
      final p = crackPatch(w: 0.5);
      for (final h in [
        <double>[1, 0, 0, 0, 1, 0, 0, 0, 0], // maps every point to infinity
        <double>[double.nan, 0, 0, 0, 1, 0, 0, 0, 1],
        <double>[1, 0, 0, 0, 1], // wrong length
      ]) {
        final o = measureFrame(patch: p, h: h, pointMm: const Pt(0, 0), directionDeg: 20, sheetId: 0, psf: psf1);
        expect((o as MeasureRejected).reason, RejectReason.invalidInput, reason: '$h');
      }
    });

    test('no markers in the patch and no PSF given: PSF unavailable', () {
      final o = measureFrame(
        patch: crackPatch(),
        h: cam().h,
        pointMm: const Pt(0, 0),
        directionDeg: 20,
        sheetId: 0,
      );
      expect((o as MeasureRejected).reason, RejectReason.psfEdgesUnavailable);
    });

    test('no crack: crack not found', () {
      final o = measure(crackPatch(w: 0.5, depth: 0.0));
      expect((o as MeasureRejected).reason, RejectReason.crackNotFound);
    });
  });

  group('result structure for the uncertainty budget (5.5)', () {
    test('components, calibration flags and diagnostics are exposed', () {
      final m = accepted(measure(crackPatch(w: 0.5)));
      expect(m.rho, 1.0);
      expect(m.rhoCalibrated, isTrue);
      expect(m.algorithmVersion, startsWith('p3-'));
      expect(m.components.keys, containsAll(['u_fit', 'u_sigma_w', 'dw_ds', 'along_sd', 'mm_per_px', 'sigma_mm', 'u_sigma_edge_mm']));
      expect(m.components['u_fit'], m.uFitMm);
      expect(m.components['u_sigma_w'], m.uSigmaWMm);
      expect(m.psf.sigmaPx, closeTo(sqrt(1 + 1 / 12), 0.1));
      expect(m.uFrameMm, closeTo(sqrt(m.uFitMm * m.uFitMm + m.uSigmaWMm * m.uSigmaWMm), 1e-15));
      expect(m.fit.status, FitStatus.terukur);
      expect(m.ridge.snr, greaterThan(5));
      expect(m.patchNoise, closeTo(0.005, 0.002));
    });

    test('a faint crack is TIDAK_TERUKUR with the reason, not a number', () {
      final m = accepted(measure(crackPatch(w: 0.5, depth: 0.03, noise: 0.02)));
      expect(m.status, MeasureStatus.tidakTerukur);
      expect(m.reportableWidthMm, isNull);
      expect(m.issue, FitIssue.lowContrast);
    });
  });

  test('determinism: the same inputs give identical results', () {
    final p = crackPatch(w: 0.5);
    final a = accepted(measure(p)), b = accepted(measure(p));
    expect(a.widthMm, b.widthMm);
    expect(a.uFrameMm, b.uFrameMm);
    expect(a.centerPointMm, b.centerPointMm);
  });

  group('sensitivity (SINTETIS; numbers in docs/MEASUREMENT_NOTES.md, tool/measurement_sweep.dart)', () {
    // Bounds are the worst case of the sweep rounded up, not guesses: see the notes for the tables.
    double err(FrameMeasurement m, double w) => (m.widthMm - w).abs();

    test('blur: sigma 0.6 to 2.0 px (w 0.5 mm) stays within 2 um + 3 u_frame', () {
      for (final sg in [0.6, 1.0, 1.5, 2.0]) {
        final psf = framePsf(sigma: sg);
        final m = accepted(measure(crackPatch(w: 0.5, sigma: sg), psf: psf));
        expect(err(m, 0.5), lessThanOrEqualTo(0.002 + 3 * m.uFrameMm), reason: 'sigma $sg err ${m.widthMm - 0.5}');
      }
    });

    test('noise: sd 0.002 to 0.04 at depth 0.3 (w 1.0 mm): within 3 um + 3 u_frame, u_frame grows with noise', () {
      final us = <double>[];
      for (final n in [0.002, 0.01, 0.04]) {
        final m = accepted(measure(crackPatch(w: 1.0, depth: 0.3, noise: n), psf: framePsf(noise: n)));
        expect(err(m, 1.0), lessThanOrEqualTo(0.003 + 3 * m.uFrameMm), reason: 'noise $n');
        us.add(m.uFitMm);
      }
      expect(us[2], greaterThan(us[0]));
    });

    test('tilt 0 to 30 deg with roll 15 (w 0.5 mm): within 3 um + 3 u_frame', () {
      for (final t in [0.0, 20.0, 30.0]) {
        final m = accepted(measure(crackPatch(w: 0.5, tilt: t, roll: t > 0 ? 15 : 0), tilt: t, roll: t > 0 ? 15 : 0));
        expect(err(m, 0.5), lessThanOrEqualTo(0.003 + 3 * m.uFrameMm), reason: 'tilt $t err ${m.widthMm - 0.5}');
      }
    });

    test('illumination gradient up to 50 percent across the patch (w 0.5 mm); 100 percent clips and is rejected', () {
      expect((measure(crackPatch(w: 0.5, illum: 1.0)) as MeasureRejected).reason, RejectReason.saturated);
      for (final g in [0.0, 0.5]) {
        final m = accepted(measure(crackPatch(w: 0.5, illum: g)));
        expect(err(m, 0.5), lessThanOrEqualTo(0.003 + 3 * m.uFrameMm), reason: 'gradient $g err ${m.widthMm - 0.5}');
      }
    });

    test('oblique cracks (45 and 70 deg) and a stored direction 10 deg off', () {
      for (final d in [45.0, 70.0]) {
        final m = accepted(measure(crackPatch(w: 0.5, dir: d), dir: d));
        expect(err(m, 0.5), lessThanOrEqualTo(0.003 + 3 * m.uFrameMm), reason: 'direction $d');
      }
      final m = accepted(measure(crackPatch(w: 0.5), dir: 30));
      expect(err(m, 0.5), lessThanOrEqualTo(0.003 + 3 * m.uFrameMm));
      expect(m.directionDeg, closeTo(20, 1.5));
    });

    test('curved crack: radius 20 mm (0.05/mm) and 10 mm (0.1/mm)', () {
      for (final k in [0.05, 0.1]) {
        final m = accepted(measure(crackPatch(w: 0.5, curv: k)));
        expect(err(m, 0.5), lessThanOrEqualTo(0.004 + 3 * m.uFrameMm), reason: 'curvature $k err ${m.widthMm - 0.5}');
      }
    });

    test('axis-aligned cracks: the +10 um bias is the sub-sample grid of the renderer (exact arithmetic), not the algorithm', () {
      // Sub-samples sit at odd multiples of 1/(2S) px from the crack centre (the centre is half a pixel off the grid).
      // A 0.5 mm crack is 8.333 px wide: S=4 counts 17 samples of 0.25 px per side = 8.5 px (+0.167 px = +10 um);
      // S=8 counts 33 of 0.125 px per side = 8.25 px (-0.083 px = -5 um). Oblique edges average this out
      // (bias 0.3 um at 20 deg). So the bias is the harness, and it follows exact grid arithmetic.
      GrayPatch aligned(int ss) => renderCrackPatch(
            camera: cam(),
            scene: crackScene(widthMm: 0.5, directionDeg: 0),
            halfSizeMm: 10,
            supersample: ss,
            psfSigmaPx: 1.0,
            noiseSigma: 0.005,
            rng: Random(7),
          );
      final b4 = accepted(measure(aligned(4), dir: 0)).widthMm - 0.5;
      final b8 = accepted(measure(aligned(8), dir: 0)).widthMm - 0.5;
      expect(b4, closeTo(0.0100, 0.002));
      expect(b8, closeTo(-0.0050, 0.002));
    });

    test('H scale error of 1 percent gives a 1 percent width error (u_geo, later phase, must carry it)', () {
      final p = crackPatch(w: 0.5);
      final h = cam().h;
      final scaled = mat3Mul(h, [1.01, 0, 0, 0, 1.01, 0, 0, 0, 1]);
      final m = accepted(measureFrame(patch: p, h: scaled, pointMm: const Pt(0, 0), directionDeg: 20, sheetId: 0, psf: psf1));
      expect((m.widthMm / 0.5 - 1).abs(), closeTo(0.01, 0.004));
    });
  });

  group('assumption violations: comparison, not repair (notes list every weakness)', () {
    test('clean images (even very low noise) raise no MODEL_MISFIT', () {
      for (final n in [0.002, 0.005, 0.02]) {
        for (final w in [0.3, 1.0]) {
          final m = accepted(measure(crackPatch(w: w, noise: n), psf: framePsf(noise: n)));
          expect(m.warnings, isNot(contains(MeasureWarning.modelMisfit)), reason: 'noise $n w $w rel ${m.fit.misfitRel}');
        }
      }
    });

    test('rough edges (0.08 mm wander): the residual flags it, though u_frame is far too small', () {
      final r = roughEdgeCrackScene(amplitudeMm: 0.08);
      final m = accepted(measure(crackPatch(scene: rotatedAboutOrigin(r.scene, 20))));
      expect(m.warnings, contains(MeasureWarning.modelMisfit));
      // KNOWN LIMIT: the flag is the only protection; the number itself is off by more than 2 u.
      expect((m.widthMm - r.meanWidthMm).abs(), greaterThan(2 * m.uFrameMm));
    });

    test('mild roughness (0.03 mm) is harmless and unflagged', () {
      final r = roughEdgeCrackScene(amplitudeMm: 0.03);
      final m = accepted(measure(crackPatch(scene: rotatedAboutOrigin(r.scene, 20))));
      expect((m.widthMm - r.meanWidthMm).abs(), lessThan(0.004));
      expect(m.warnings, isNot(contains(MeasureWarning.modelMisfit)));
    });

    test('a shadow on one side and a stain beside the crack are flagged', () {
      final base = crackScene(widthMm: 0.5, directionDeg: 0);
      final shadow = accepted(measure(crackPatch(scene: rotatedAboutOrigin(withOneSidedShadow(base, 0.9), 20))));
      expect(shadow.warnings, contains(MeasureWarning.modelMisfit));
      final stain = accepted(measure(crackPatch(scene: rotatedAboutOrigin(withStain(base, 0.25), 20))));
      expect(stain.warnings, contains(MeasureWarning.modelMisfit));
    });

    test('a strong one-sided shadow (x0.5) is never reported as a clean TERUKUR result', () {
      final o = measure(crackPatch(scene: rotatedAboutOrigin(withOneSidedShadow(crackScene(widthMm: 0.5, directionDeg: 0), 0.5), 20)));
      if (o is MeasureAccepted) {
        final m = o.measurement;
        expect(m.status == MeasureStatus.tidakTerukur || m.warnings.contains(MeasureWarning.modelMisfit), isTrue);
      }
    });

    test('a second parallel crack 2.5 mm away inside the profile range: not measurable, flagged', () {
      final a = crackScene(widthMm: 0.5, directionDeg: 0);
      final b = crackScene(widthMm: 0.5, directionDeg: 0, centerMm: const Pt(0, 2.5));
      final m = accepted(measure(crackPatch(scene: rotatedAboutOrigin((x, y) => min(a(x, y), b(x, y)), 20))));
      expect(m.status, MeasureStatus.tidakTerukur);
      expect(m.warnings, contains(MeasureWarning.parameterAtBound)); // w runs to its bound, sweep: u_frame infinite
    });

    test('a bright line (efflorescence, negative contrast) is not measured as a crack', () {
      final o = measure(crackPatch(w: 0.5, depth: -0.15));
      expect(o is MeasureRejected || (o as MeasureAccepted).measurement.status == MeasureStatus.tidakTerukur, isTrue);
    });

    test('a 2.6 mm crack (inside the 3 mm design limit, beyond the validated 2 mm) carries a warning', () {
      // SINTETIS sweep: error 68 +- 56 um with u_frame 0.2 um: the number is not trustworthy.
      final m = accepted(measure(crackPatch(w: 2.6)));
      expect(m.warnings, contains(MeasureWarning.widthBeyondValidated));
      final ok = accepted(measure(crackPatch(w: 2.0)));
      expect(ok.warnings, isNot(contains(MeasureWarning.widthBeyondValidated)));
    });

    test('sheet slipped between visits: a ridge 0.9 mm off the stored point is found but flagged TRACKING_OFFSET (phase 9 audit)', () {
      final a = 20 * pi / 180;
      final slipped = accepted(measure(crackPatch(w: 0.5), point: Pt(-0.9 * sin(a), 0.9 * cos(a))));
      expect(slipped.trackingOffsetMm, closeTo(0.9, 0.05));
      expect(slipped.warnings, contains(MeasureWarning.trackingOffset));
      // within tolerance (0.3 mm: the spread of the synthetic study) no flag
      final ok = accepted(measure(crackPatch(w: 0.5), point: Pt(-0.3 * sin(a), 0.3 * cos(a))));
      expect(ok.warnings, isNot(contains(MeasureWarning.trackingOffset)));
      // beyond the 1.5 mm search radius the crack is not found: rejected, never a number
      expect(measure(crackPatch(w: 0.5), point: Pt(-2.2 * sin(a), 2.2 * cos(a))), isA<MeasureRejected>());
    });

    test('a crack wider than the 3 mm design limit is flagged at the bound', () {
      final o = measure(crackPatch(w: 3.4));
      if (o is MeasureAccepted) {
        expect(
          o.measurement.warnings.contains(MeasureWarning.parameterAtBound) || o.measurement.status == MeasureStatus.tidakTerukur,
          isTrue,
        );
      } else {
        expect(o, isA<MeasureRejected>());
      }
    });

    test('KNOWN LIMIT: gamma-encoded intensity gives a silent negative bias; linearising first removes it', () {
      GrayPatch gamma(GrayPatch p) => GrayPatch(
            originX: p.originX,
            originY: p.originY,
            width: p.width,
            height: p.height,
            data: Float32List.fromList([for (final v in p.data) pow(v, 1 / 2.2).toDouble()]),
          );
      final raw = crackPatch(w: 0.5);
      final c = cam(distance: 600);
      final markers = renderCrackPatch(
        camera: c,
        scene: sheetScene(sheetId: 0, paper: 0.8),
        halfSizeMm: 85,
        supersample: 2,
        psfSigmaPx: 1.0,
        noiseSigma: 0.005,
        rng: Random(3),
      );
      final psfGamma = estimatePsf(patch: gamma(markers), h: c.h, sheetId: 0);
      final psfLin = estimatePsf(patch: gamma(markers).linearizedFromSrgb(), h: c.h, sheetId: 0);
      final bad = accepted(measure(gamma(raw), psf: psfGamma));
      final good = accepted(measure(gamma(raw).linearizedFromSrgb(), psf: psfLin));
      expect(bad.widthMm - 0.5, lessThan(-0.010)); // about -18 um in the sweep
      expect(bad.warnings, isNot(contains(MeasureWarning.modelMisfit))); // silent
      expect((good.widthMm - 0.5).abs(), lessThan(0.004));
    });

    test('KNOWN LIMIT: a crack blurred 25 percent more than the marker edges is biased beyond u_frame', () {
      final m = accepted(measure(crackPatch(w: 0.3, sigma: 1.25)));
      expect((m.widthMm - 0.3).abs(), greaterThan(0.010)); // about 18 um in the sweep
      expect((m.widthMm - 0.3).abs(), greaterThan(2 * m.uFrameMm));
    });

    test('KNOWN LIMIT: spatially correlated noise makes the iid noise estimate too small', () {
      final p = renderCrackPatch(camera: cam(), scene: (x, y) => 0.5, halfSizeMm: 8, noiseSigma: 0.02, rng: Random(8), quantize8bit: false);
      // [1 2 1]/4 smoothing along x and y: correlated noise of sd 0.02 * 9/16... measured via the estimator below.
      final d = Float32List.fromList(p.data);
      final w = p.width, h = p.height;
      final t = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 1; x < w - 1; x++) {
          t[y * w + x] = 0.25 * d[y * w + x - 1] + 0.5 * d[y * w + x] + 0.25 * d[y * w + x + 1];
        }
      }
      final s2 = Float32List(w * h);
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          s2[y * w + x] = 0.25 * t[(y - 1) * w + x] + 0.5 * t[y * w + x] + 0.25 * t[(y + 1) * w + x];
        }
      }
      final smooth = GrayPatch(originX: p.originX, originY: p.originY, width: w, height: h, data: s2);
      var sum = 0.0, sumSq = 0.0, n = 0;
      for (var y = 2; y < h - 2; y++) {
        for (var x = 2; x < w - 2; x++) {
          sum += s2[y * w + x];
          sumSq += s2[y * w + x] * s2[y * w + x];
          n++;
        }
      }
      final trueSd = sqrt(sumSq / n - pow(sum / n, 2));
      // The estimator assumes iid noise: for correlated noise it reports well under the true sd.
      expect(estimatePatchNoise(smooth), lessThan(0.6 * trueSd));
    });
  });

  group('full frame pipeline (markers and crack in one patch)', () {
    // 0.1 mm/px, the whole 170 mm frame, PSF measured from the markers of the same patch.
    late final GrayPatch frame;
    late final SyntheticCamera c;
    setUpAll(() {
      c = cam(distance: 300);
      frame = renderCrackPatch(
        camera: c,
        scene: sheetWithCrackScene(sheetId: 0, crack: crackScene(widthMm: 0.5, directionDeg: 20, background: 0.8)),
        halfSizeMm: 85,
        supersample: 2,
        psfSigmaPx: 1.0,
        noiseSigma: 0.005,
        rng: Random(9),
      );
    });

    test('accepted, accurate, and one frame is processed in a reasonable time', () {
      final sw = Stopwatch()..start();
      final o = measureFrame(patch: frame, h: c.h, pointMm: const Pt(0, 0), directionDeg: 20, sheetId: 0);
      sw.stop();
      final m = accepted(o);
      // 5 px wide crack at 0.1 mm/px; allow 3 u_frame + 3 um.
      expect((m.widthMm - 0.5).abs(), lessThanOrEqualTo(3 * m.uFrameMm + 0.003), reason: 'err=${m.widthMm - 0.5}');
      // Dart VM on the development machine (JIT, not AOT). Generous bound; real figure in MEASUREMENT_NOTES.
      expect(sw.elapsedMilliseconds, lessThan(3000));
      // ignore: avoid_print
      print('full-frame measureFrame: ${sw.elapsedMilliseconds} ms (patch ${frame.width}x${frame.height})');
    });
  });
}
