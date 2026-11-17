// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import '../aggregate.dart';
import '../homography.dart';
import '../measure.dart';
import '../patch.dart';
import '../point.dart';
import '../pose.dart';
import '../psf.dart';
import '../quality.dart';
import '../rejection.dart';
import '../synthetic/camera.dart';
import '../synthetic/detector.dart';
import '../synthetic/noise.dart';
import '../synthetic/patch_scene.dart';
import '../synthetic/render.dart';
import '../uncertainty.dart';
import '../student_t.dart';
import '../validation.dart';

/// One cell of the synthetic study grid.
final class StudyCondition {
  const StudyCondition({
    required this.index,
    required this.widthMm,
    required this.mmPerPx,
    required this.sigmaPx,
    required this.noise,
    required this.tiltDeg,
  });

  /// Position in [studyGrid]; seeds are derived from it.
  final int index;
  final double widthMm;

  /// Geometric-mean scale at the measurement point (mm per px).
  final double mmPerPx;

  /// Gaussian blur of the generator (px, before the pixel aperture).
  final double sigmaPx;

  /// Pixel noise sd in 8-bit grey levels (0..255).
  final double noise;
  final double tiltDeg;

  /// Key of the condition without its width (a "plate" of lines at one setting).
  String get settingKey => 's${mmPerPx}_b${sigmaPx}_n${noise}_t$tiltDeg';
}

const List<double> studyWidthsMm = [0.1, 0.2, 0.3, 0.5, 1.0, 2.0];
const List<double> studyMmPerPx = [0.04, 0.06, 0.10, 0.15];
const List<double> studySigmasPx = [0.6, 1.0, 1.5, 2.0];
const List<double> studyNoises = [1, 3, 6];
const List<double> studyTiltsDeg = [0, 10, 20];

/// The full grid (6 x 4 x 4 x 3 x 3 = 864 conditions), width varying fastest.
List<StudyCondition> studyGrid() {
  final out = <StudyCondition>[];
  for (final t in studyTiltsDeg) {
    for (final n in studyNoises) {
      for (final s in studySigmasPx) {
        for (final m in studyMmPerPx) {
          for (final w in studyWidthsMm) {
            out.add(StudyCondition(index: out.length, widthMm: w, mmPerPx: m, sigmaPx: s, noise: n, tiltDeg: t));
          }
        }
      }
    }
  }
  return out;
}

/// Fixed settings of the simulation (everything not in the grid).
final class StudyConfig {
  const StudyConfig({
    this.seed = 20261117,
    this.frames = 5,
    this.cornerNoisePx = 0.2,
    this.depth = 0.4,
    this.background = 0.8,
    this.directionErrorDeg = 3,
    this.lateralOffsetMm = 0.3,
    this.supersample = 4,
    this.psfMmPerPx = 0.25,
    this.psfSupersample = 2,
    this.renderTruthUncertaintyPx = _quadraturePx,
  });

  /// Standard uncertainty of the rendered "true" width (px): each edge sample of the
  /// renderer is off by at most `0.5 / S` px (D18), taken as uniform (sd `0.5 / (S sqrt 3)`),
  /// two edges per width. The renderer, not the algorithm, limits the truth at this level;
  /// it enters the study as `u_truth` exactly as a plate's certified uncertainty would.
  final double renderTruthUncertaintyPx;

  final int seed;

  /// Burst size per visit (CLAUDE.md 5.4: up to 5 stored frames).
  final int frames;

  /// Marker corner detection noise, px per axis.
  final double cornerNoisePx;

  /// Crack darkness: intensity `background (1 - depth)` inside (0.4 gives 82 grey levels).
  final double depth;
  final double background;

  /// The stored crack direction differs from the truth by U(-e, e) degrees and the crack
  /// passes U(-o, o) mm beside the stored point (ridge tracking must find it).
  final double directionErrorDeg;
  final double lateralOffsetMm;
  final int supersample;

  /// Scale (mm/px) of the separate marker patch used for the PSF, and its supersampling.
  final double psfMmPerPx;
  final int psfSupersample;
}

/// `sqrt(2) x 0.5 / (4 sqrt 3)` px for the default supersample 4.
const double _quadraturePx = 0.10206207261596575;

const ImageSize _image = ImageSize(4000, 3000);

double _u(Random r, double a, double b) => a + (b - a) * r.nextDouble();

/// Same order as the renderer's last steps: noise, clip to 0..1, quantise to 8 bits.
GrayPatch _noisy(GrayPatch clean, double sigma, Random rng) {
  final d = Float32List(clean.data.length);
  for (var i = 0; i < d.length; i++) {
    d[i] = ((clean.data[i] + sigma * gaussian(rng)).clamp(0.0, 1.0) * 255).round() / 255;
  }
  return GrayPatch(originX: clean.originX, originY: clean.originY, width: clean.width, height: clean.height, data: d);
}

/// Simulates one visit (a burst of [StudyConfig.frames] frames) of condition [c],
/// replication [rep], through the real chain: random pose, noisy marker detection,
/// homography, geometry gate, rendered crack patch, PSF from marker edges,
/// [measureFrame]. Deterministic in (seed, condition, replication).
///
/// Simplifications (SINTETIS, to be read with the results):
/// - the burst shares one pose and one noise-free rendering; frames differ by marker
///   detection noise, pixel noise and the PSF estimate. Hand tremor (sub-pixel phase of
///   the crack changing between frames) is NOT simulated, so `u_repeat` may understate a
///   real burst; the pose differs between visits, so the coverage over visits still sees
///   the phase effect;
/// - the PSF comes from a separate marker patch at [StudyConfig.psfMmPerPx] with the same
///   blur, noise and view, its marker edges located with that patch's true homography;
/// - the tilt estimate uses the default `f_px = 0.75 x long side`, the true `f` is 0.7 to
///   0.9 x.
List<FrameInput> simulateVisit(StudyCondition c, int rep, {StudyConfig config = const StudyConfig()}) {
  final rng = Random(config.seed * 1000003 + c.index * 7919 + rep);
  final f = _u(rng, 0.7, 0.9) * _image.longSide;
  final cosT = sqrt(cos(c.tiltDeg * pi / 180));
  final cam = SyntheticCamera(
    image: _image,
    fPx: f,
    distanceMm: c.mmPerPx * f * cosT,
    tiltDeg: c.tiltDeg,
    tiltAzimuthDeg: _u(rng, 0, 360),
    rollDeg: _u(rng, -20, 20),
    offsetXmm: _u(rng, -10, 10),
    offsetYmm: _u(rng, -10, 10),
  );
  final dir = (rng.nextBool() ? 5.0 : 95.0) + _u(rng, 0, 80); // keeps off the pixel axes (D27)
  final lateral = _u(rng, -config.lateralOffsetMm, config.lateralOffsetMm);
  final a = dir * pi / 180;
  final noise = c.noise / 255;
  final intrinsics = CameraIntrinsics.fromImage(_image);
  GrayPatch? cleanCrack, cleanPsf;
  SyntheticCamera? psfCam;
  final out = <FrameInput>[];
  for (var i = 0; i < config.frames; i++) {
    final detections = SyntheticDetector(noisePx: config.cornerNoisePx, rng: rng).detect(cam, sheetId: 0);
    final est = estimateSheetHomography(detections, sheetId: 0);
    final tiltEst = estimateTilt(est.h, intrinsics).tiltDeg;
    final verdict = evaluateFrameGeometry(
      FrameGeometry(markerCount: est.markerCount, rmsPx: est.rmsPx, looMm: est.looMm, tiltDeg: tiltEst, mmPerPx: est.localScale().mmPerPx),
    );
    if (!verdict.accepted) {
      out.add(FrameInput.rejected(geometry: verdict.rejections));
      continue;
    }
    cleanCrack ??= renderCrackPatch(
      camera: cam,
      scene: crackScene(
        widthMm: c.widthMm,
        depth: config.depth,
        background: config.background,
        directionDeg: dir,
        centerMm: Pt(-sin(a) * lateral, cos(a) * lateral),
      ),
      halfSizeMm: 10,
      supersample: config.supersample,
      psfSigmaPx: c.sigmaPx,
      quantize8bit: false,
    );
    psfCam ??= SyntheticCamera(
      image: _image,
      fPx: f,
      distanceMm: config.psfMmPerPx * f * cosT,
      tiltDeg: c.tiltDeg,
      tiltAzimuthDeg: cam.tiltAzimuthDeg,
      rollDeg: cam.rollDeg,
      offsetXmm: cam.offsetXmm,
      offsetYmm: cam.offsetYmm,
    );
    cleanPsf ??= renderCrackPatch(
      camera: psfCam,
      scene: sheetScene(sheetId: 0, paper: config.background),
      halfSizeMm: 85,
      supersample: config.psfSupersample,
      psfSigmaPx: c.sigmaPx,
      quantize8bit: false,
    );
    final PsfEstimate psf;
    try {
      psf = estimatePsf(patch: _noisy(cleanPsf, noise, rng), h: psfCam.h, sheetId: 0);
    } on MeasurementException catch (e) {
      out.add(FrameInput.rejected(measure: e.reason));
      continue;
    }
    final outcome = measureFrame(
      patch: _noisy(cleanCrack, noise, rng),
      h: est.h,
      pointMm: const Pt(0, 0),
      directionDeg: dir + _u(rng, -config.directionErrorDeg, config.directionErrorDeg),
      sheetId: 0,
      psf: psf,
    );
    switch (outcome) {
      case MeasureAccepted(:final measurement):
        out.add(FrameInput.accepted(FrameRecord.fromMeasurement(measurement, rmsPx: est.rmsPx, looMm: est.looMm, tiltDeg: tiltEst)));
      case MeasureRejected(:final reason):
        out.add(FrameInput.rejected(measure: reason));
    }
  }
  return out;
}

/// Result of one visit of a study condition under a given budget configuration.
final class StudyVisit {
  const StudyVisit({required this.condition, required this.rep, required this.result, this.uTruthMm = 0});

  final StudyCondition condition;
  final int rep;
  final VisitResult result;

  /// Standard uncertainty of the truth (mm), see [StudyConfig.renderTruthUncertaintyPx].
  final double uTruthMm;

  /// `measured - truth` (mm) when a width is reported.
  double? get errorMm => result.reportableWidthMm == null ? null : result.reportableWidthMm! - condition.widthMm;

  /// True width within the combined interval `k sqrt(u_c^2 + u_truth^2)` (k by
  /// Welch-Satterthwaite with u_stat the only finite-dof part).
  bool get covered {
    final b = result.budget;
    return errorMm != null && errorMm!.abs() <= expandedWithTruth(uC: b!.uC, uStat: b.uStat, n: b.n, uTruth: uTruthMm);
  }
}

/// `k sqrt(uC^2 + uTruth^2)` with `k` from the Welch-Satterthwaite dof (only [uStat], with
/// `n - 1` dof, is finite; the truth uncertainty is treated as infinite dof).
double expandedWithTruth({required double uC, required double uStat, required int n, required double uTruth}) {
  final u = sqrt(uC * uC + uTruth * uTruth);
  final dof = u > 0 ? welchSatterthwaite(uC: u, finite: [(u: uStat, dof: (n - 1).toDouble())]) : double.infinity;
  return coverageFactor(dof) * u;
}

/// Replays stored frames of a visit with variance inflation [rho] and [options]; the truth
/// uncertainty follows [config].
StudyVisit replayVisit(
  StudyCondition c,
  int rep,
  List<FrameInput> frames, {
  required double rho,
  UncertaintyOptions options = const UncertaintyOptions(),
  StudyConfig config = const StudyConfig(),
}) {
  final scaled = [
    for (final fr in frames) fr.accepted ? FrameInput.accepted(fr.record!.withRho(rho)) : fr,
  ];
  return StudyVisit(condition: c, rep: rep, result: aggregateVisit(scaled, options: options), uTruthMm: c.mmPerPx * config.renderTruthUncertaintyPx);
}

/// Summary of the visits of one condition.
final class ConditionSummary {
  const ConditionSummary({
    required this.condition,
    required this.visits,
    required this.terukur,
    required this.dibawahBatas,
    required this.tidakTerukur,
    required this.ditolak,
    required this.biasMm,
    required this.rmseMm,
    required this.covered,
    required this.coverage,
    required this.medianUExpandedMm,
    required this.medianFloorMm,
  });

  final StudyCondition condition;
  final int visits;
  final int terukur, dibawahBatas, tidakTerukur, ditolak;

  /// Over visits that reported a width (NaN if none).
  final double biasMm, rmseMm;

  /// Reported visits with `|error| <= U`, and their fraction (NaN if none reported).
  final int covered;
  final double coverage;
  final double medianUExpandedMm;

  /// Median visit floor over visits that built a budget (NaN if none).
  final double medianFloorMm;

}

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

ConditionSummary summarizeCondition(StudyCondition c, List<StudyVisit> visits) {
  final rep = [for (final v in visits) if (v.errorMm != null) v];
  final err = [for (final v in rep) v.errorMm!];
  int count(VisitStatus s) => visits.where((v) => v.result.status == s).length;
  return ConditionSummary(
    condition: c,
    visits: visits.length,
    terukur: rep.length,
    dibawahBatas: count(VisitStatus.dibawahBatasUkur),
    tidakTerukur: count(VisitStatus.tidakTerukur),
    ditolak: count(VisitStatus.ditolak),
    biasMm: err.isEmpty ? double.nan : err.reduce((a, b) => a + b) / err.length,
    rmseMm: err.isEmpty ? double.nan : sqrt(err.fold<double>(0, (s, e) => s + e * e) / err.length),
    covered: rep.where((v) => v.covered).length,
    coverage: rep.isEmpty ? double.nan : rep.where((v) => v.covered).length / rep.length,
    medianUExpandedMm: _median([for (final v in rep) v.result.budget!.uExpanded]),
    medianFloorMm: _median([for (final v in visits) if (v.result.budget != null) v.result.budget!.floorMm]),
  );
}

/// Empirical lower reporting limit of a setting (same blur, noise, scale, tilt): the
/// plate statistics of [validation.dart] over the widths of that setting, where a visit
/// that reported no number counts as not reported. Visits rejected by the visit gate
/// are left out: the user is asked to retake them, they are neither a number nor a
/// withheld number.
double? settingLowerLimit(List<StudyVisit> visitsOfSetting) => computePlateStats([
      for (final v in visitsOfSetting)
        if (v.result.storable)
        PlateMeasurement(
          lineId: '${v.condition.index}-${v.rep}',
          truthMm: v.condition.widthMm,
          uTruthMm: 0,
          measuredMm: v.result.reportableWidthMm,
          uCMm: v.result.budget?.uC ?? 0,
          k: v.result.budget?.k ?? 2,
        ),
    ]).lowerLimitMm;

/// JSON of a frame input for the study cache (NaN `dw/ds` is written as null).
Map<String, Object?> frameInputToJson(FrameInput f) {
  final r = f.record;
  if (r == null) return {'a': 0, 'x': f.rejectionCodes};
  return {
    'a': 1,
    'st': r.status.code,
    'w': r.widthMm,
    'uf': r.uFitRawMm,
    'rho': r.rho,
    'us': r.uSigmaWMm,
    'dw': r.dwDs.isNaN ? null : r.dwDs,
    'mpp': r.mmPerPx,
    'rms': r.rmsPx,
    'loo': r.looMm,
    't': r.tiltDeg,
  };
}

FrameInput frameInputFromJson(Map<String, Object?> j) {
  if (j['a'] == 0) {
    final codes = (j['x']! as List<Object?>).cast<String>();
    final geometry = [for (final c in codes) ...FrameRejection.values.where((v) => v.code == c)];
    final measure = [for (final c in codes) ...RejectReason.values.where((v) => v.code == c)];
    return FrameInput.rejected(geometry: geometry, measure: measure.isEmpty ? null : measure.single);
  }
  double d(String k) => (j[k]! as num).toDouble();
  return FrameInput.accepted(FrameRecord(
    status: MeasureStatus.values.firstWhere((s) => s.code == j['st']),
    widthMm: d('w'),
    uFitRawMm: d('uf'),
    rho: d('rho'),
    uSigmaWMm: d('us'),
    dwDs: j['dw'] == null ? double.nan : d('dw'),
    mmPerPx: d('mpp'),
    rmsPx: d('rms'),
    looMm: j['loo'] == null ? null : d('loo'),
    tiltDeg: d('t'),
  ));
}
