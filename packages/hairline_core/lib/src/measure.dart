// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'homography.dart';
import 'linalg_small.dart';
import 'patch.dart';
import 'point.dart';
import 'profile_fit.dart';
import 'psf.dart';
import 'quality.dart';
import 'rejection.dart';
import 'ridge.dart';
import 'sheet.dart';

/// Identifies the measurement algorithm in stored results (CLAUDE.md 5.7). Bump when
/// any step of the single-frame measurement changes.
const String measurementAlgorithmVersion = 'p3-1';

/// Half size (mm) of the square around the point in which saturation is counted.
const double saturationRoiHalfMm = 5;

/// A pixel at or above this level, or at or below `1 - this`, counts as clipped.
const double _saturationLevel = 0.995;

/// `misfitRel` (systematic residual over dip depth) above this adds
/// [MeasureWarning.modelMisfit]. Empirical (SINTETIS, tool/measurement_sweep.dart): the
/// systematic part is at most 0.25 percent for correct models at every noise level, and
/// 1.2 percent or more for rough edges (amplitude 0.08 mm), a one-sided shadow or a stain.
const double misfitWarningRel = 0.01;

/// Distance (mm) between the stored measurement point and the crack ridge found at the
/// visit above which [MeasureWarning.trackingOffset] is added. A sheet that slipped or was
/// re-applied, or a point that was never on the crack, shows up as a ridge off the stored
/// point (the search radius is 1.5 mm). 0.5 mm is about ten times the sheet position
/// error of a good 4-marker frame; UNTUNED on real devices.
const double maxTrackingOffsetMm = 0.5;

/// Largest width covered by the synthetic validation (tool/measurement_sweep.dart:
/// `ideal`). Between this and the 3 mm model limit the SINTETIS error grows to
/// 68 +- 56 um at 2.6 mm while `u_frame` stays near 0.2 um, so the result carries
/// [MeasureWarning.widthBeyondValidated].
const double maxValidatedWidthMm = 2.0;

/// Relative uncertainty of the kernel sigma that is NOT visible in the scatter of
/// the marker edges: the true kernel is not exactly Gaussian (pixel aperture, ISP,
/// JPEG), and for cracks narrower than about 3 sigma that shape error moves the width
/// as a sigma error would (docs/MEASUREMENT_NOTES.md: SINTETIS, bias up to about 9 percent
/// of sigma in sigma-equivalent; 0.10 is the smallest tried value that reaches 90 percent
/// coverage at 2 u_frame for w/sigma about 1.25). Added in quadrature to `u_sigma_edge` for `u_sigma_w`.
/// UNVALIDATED on real devices.
const double defaultKernelShapeRelUncertainty = 0.10;

/// Status of a frame measurement (5.3 gate, 5.5 lower reporting limit).
enum MeasureStatus {
  /// A width is reported.
  terukur('TERUKUR'),

  /// Estimated but under the reporting floor `max(0.5 mm/px, 2 u)`: shown as
  /// "di bawah batas ukur", never as a width number.
  dibawahBatasUkur('DI_BAWAH_BATAS_UKUR'),

  /// Contrast gate or fit health failed: no number.
  tidakTerukur('TIDAK_TERUKUR');

  const MeasureStatus(this.code);
  final String code;
}

/// Non-blocking remarks on a measurement.
enum MeasureWarning {
  /// The fitted profile has structure the model cannot explain (rough edges,
  /// shadow, stain): the reported fit uncertainty is not to be trusted.
  modelMisfit('MODEL_MISFIT'),

  /// Too few usable profile centres: pass 2 ran without alignment.
  alignmentFallback('ALIGNMENT_FALLBACK'),

  /// A fit parameter (D, w, ...) sits on its bound.
  parameterAtBound('PARAMETER_AT_BOUND'),

  /// Fewer than 6 marker edges were usable for the PSF.
  fewPsfEdges('FEW_PSF_EDGES'),

  /// The width exceeds [maxValidatedWidthMm]: only validated up to there.
  widthBeyondValidated('WIDTH_BEYOND_VALIDATED'),

  /// The crack ridge lies more than [maxTrackingOffsetMm] from the stored point: the
  /// sheet may have moved since the baseline (the series would then be broken, 5.1).
  trackingOffset('TRACKING_OFFSET');

  const MeasureWarning(this.code);
  final String code;
}

/// Outcome of [measureFrame]: a structured measurement or a reasoned rejection.
sealed class MeasureOutcome {
  const MeasureOutcome();
}

final class MeasureAccepted extends MeasureOutcome {
  const MeasureAccepted(this.measurement);
  final FrameMeasurement measurement;
}

final class MeasureRejected extends MeasureOutcome {
  const MeasureRejected(this.reason, this.message);
  final RejectReason reason;

  /// Specific message for the user (Indonesian).
  final String message;
}

/// One frame's measurement with everything the 5.5 uncertainty budget needs.
final class FrameMeasurement {
  const FrameMeasurement({
    required this.status,
    required this.issue,
    required this.widthMm,
    required this.uFitMm,
    required this.uSigmaWMm,
    required this.uFrameMm,
    required this.floorMm,
    required this.centerPointMm,
    required this.directionDeg,
    required this.trackingOffsetMm,
    required this.mmPerPx,
    required this.sigmaMm,
    required this.uSigmaEdgeMm,
    required this.rho,
    required this.rhoCalibrated,
    required this.patchNoise,
    required this.saturatedFraction,
    required this.warnings,
    required this.psf,
    required this.ridge,
    required this.fit,
    required this.algorithmVersion,
  });

  final MeasureStatus status;

  /// Set when [status] is [MeasureStatus.tidakTerukur] because of the fit.
  final FitIssue? issue;

  /// Estimated width (mm). Display only [reportableWidthMm].
  final double widthMm;

  /// Fit uncertainty `sqrt(rho Var(w))` (5.3), mm.
  final double uFitMm;

  /// `u_sigma_w` (5.3a): half the width change at `sigma +- u_sigma`, mm.
  final double uSigmaWMm;

  /// `sqrt(u_fit^2 + u_sigma_w^2)`: the part of the budget this phase can compute.
  /// Position, parallax, geometry and systematic parts (5.5) are added later.
  final double uFrameMm;

  /// Frame-level reporting floor `max(0.5 mm/px, 2 u_frame)`.
  final double floorMm;

  /// Where the width was measured (the crack centre nearest to the stored point).
  final Pt centerPointMm;
  final double directionDeg;

  /// Distance from the stored point to [centerPointMm].
  final double trackingOffsetMm;

  /// Geometric mean scale at the point (mm per pixel).
  final double mmPerPx;

  /// Apparent kernel sigma used for the crack, along its normal (mm), and its
  /// uncertainty `u_sigma_edge` (mm).
  final double sigmaMm;
  final double uSigmaEdgeMm;
  final double rho;
  final bool rhoCalibrated;

  /// Robust estimate of the pixel noise sd of the patch.
  final double patchNoise;
  final double saturatedFraction;
  final List<MeasureWarning> warnings;
  final PsfEstimate psf;
  final RidgeResult ridge;
  final ProfileFitResult fit;
  final String algorithmVersion;

  /// The width to show, or null unless [status] is [MeasureStatus.terukur].
  double? get reportableWidthMm => status == MeasureStatus.terukur ? widthMm : null;

  /// Components for the 5.5 budget, by their documented names (mm unless noted).
  Map<String, double> get components => {
        'u_fit': uFitMm,
        'u_sigma_w': uSigmaWMm,
        'dw_ds': fit.dwDs, // mm/mm, NaN if not estimable
        'along_sd': fit.alongSdMm,
        'mm_per_px': mmPerPx,
        'sigma_mm': sigmaMm,
        'u_sigma_edge_mm': uSigmaEdgeMm,
      };
}

/// Measures the crack width in one frame (5.3).
///
/// [patch] is the grey patch extracted by the adapter; it must contain the markers
/// used for the PSF (unless [psf] is given) and about +-8 mm around the point.
/// [h] maps sheet mm to image px (`HomographyEstimate.h`); [pointMm] and
/// [directionDeg] are the stored measurement point and crack direction; [markerIds]
/// the detected markers (default: all four of [sheetId]).
///
/// Order: validate input, PSF (5.3a) and blur gates, saturation gate, ridge tracking
/// within 1.5 mm, two-pass profile fit, status. Rejections are returned, not thrown.
/// `u_sigma_w` refits at `sigma +- sqrt(u_sigma_edge^2 + (kernelShapeRelUncertainty sigma)^2)`.
MeasureOutcome measureFrame({
  required GrayPatch patch,
  required Mat3 h,
  required Pt pointMm,
  required double directionDeg,
  required int sheetId,
  double printScale = 1,
  List<int>? markerIds,
  PsfEstimate? psf,
  QualityThresholds thresholds = QualityThresholds.standard,
  ProfileFitConfig config = const ProfileFitConfig(),
  double kernelShapeRelUncertainty = defaultKernelShapeRelUncertainty,
}) {
  if (h.length != 9 || !h.every((v) => v.isFinite)) {
    return const MeasureRejected(RejectReason.invalidInput, 'Homografi tidak valid.');
  }
  if (!pointMm.isFinite || !directionDeg.isFinite || !isInsideWindow(pointMm, printScale: printScale)) {
    return const MeasureRejected(
      RejectReason.invalidInput,
      'Titik ukur berada di luar jendela lembar atau tidak valid.',
    );
  }
  try {
    final estimate = psf ?? estimatePsf(patch: patch, h: h, sheetId: sheetId, printScale: printScale, markerIds: markerIds);
    if (estimate.sigmaPx > thresholds.maxSigmaPx) {
      return MeasureRejected(
        RejectReason.blurTooLarge,
        'Foto terlalu buram (sigma ${estimate.sigmaPx.toStringAsFixed(1).replaceAll('.', ',')} px). Pegang ponsel lebih stabil dan pastikan fokus.',
      );
    }
    final aniso = estimate.anisotropy;
    if (aniso != null && aniso > thresholds.maxBlurAnisotropy) {
      return const MeasureRejected(
        RejectReason.blurAnisotropic,
        'Foto buram ke satu arah (ponsel bergerak). Tahan ponsel diam saat memotret.',
      );
    }
    final satFraction = _saturatedFraction(patch, h, pointMm);
    if (satFraction > thresholds.maxSaturatedFraction) {
      return const MeasureRejected(
        RejectReason.saturated,
        'Terlalu banyak piksel jenuh di sekitar titik ukur. Kurangi cahaya langsung atau silau.',
      );
    }
    final noise = estimatePatchNoise(patch);
    final ridge = findRidge(
      patch: patch,
      h: h,
      pointMm: pointMm,
      directionDeg: directionDeg,
      noiseSigma: noise,
      sigmaPx: estimate.sigmaPx,
    );
    final kernel = estimate.sigmaMmAlong(h, ridge.centerMm, ridge.directionDeg);
    final fit = fitCrackWidth(
      patch: patch,
      h: h,
      pointMm: ridge.centerMm,
      directionDeg: ridge.directionDeg,
      sigmaMm: kernel.sigmaMm,
      uSigmaMm: sqrt(kernel.uSigmaMm * kernel.uSigmaMm + pow(kernelShapeRelUncertainty * kernel.sigmaMm, 2)),
      noiseFloor: noise,
      config: config,
    );
    final mmPerPx = localMmPerPx(h, ridge.centerMm);
    final uFrame = sqrt(fit.uWidthMm * fit.uWidthMm + fit.uSigmaWMm * fit.uSigmaWMm);
    final floor = max(0.5 * mmPerPx, 2 * uFrame);
    final status = fit.status == FitStatus.tidakTerukur
        ? MeasureStatus.tidakTerukur
        : (fit.widthMm < floor ? MeasureStatus.dibawahBatasUkur : MeasureStatus.terukur);
    return MeasureAccepted(
      FrameMeasurement(
        status: status,
        issue: fit.issue,
        widthMm: fit.widthMm,
        uFitMm: fit.uWidthMm,
        uSigmaWMm: fit.uSigmaWMm,
        uFrameMm: uFrame,
        floorMm: floor,
        centerPointMm: ridge.centerMm,
        directionDeg: ridge.directionDeg,
        trackingOffsetMm: ridge.offsetMm,
        mmPerPx: mmPerPx,
        sigmaMm: kernel.sigmaMm,
        uSigmaEdgeMm: kernel.uSigmaMm,
        rho: fit.rho,
        rhoCalibrated: fit.rhoCalibrated,
        patchNoise: noise,
        saturatedFraction: satFraction,
        warnings: [
          if (fit.misfitRel > misfitWarningRel) MeasureWarning.modelMisfit,
          if (fit.alignmentFallback) MeasureWarning.alignmentFallback,
          if (fit.boundsActive.contains('D') || fit.boundsActive.contains('w')) MeasureWarning.parameterAtBound,
          if (estimate.edges.length < 6) MeasureWarning.fewPsfEdges,
          if (ridge.offsetMm > maxTrackingOffsetMm) MeasureWarning.trackingOffset,
          if (fit.widthMm > 1.05 * maxValidatedWidthMm) MeasureWarning.widthBeyondValidated, // 5 percent: a 2.0 mm crack measures 2.000 to 2.001
        ],
        psf: estimate,
        ridge: ridge,
        fit: fit,
        algorithmVersion: measurementAlgorithmVersion,
      ),
    );
  } on MeasurementException catch (e) {
    return MeasureRejected(e.reason, e.message);
  } on HomographyException {
    // A homography that sends a needed point to infinity (degenerate view).
    return const MeasureRejected(RejectReason.invalidInput, 'Homografi tidak valid untuk titik ukur ini.');
  }
}

bool _isSaturated(double v) => v >= _saturationLevel || v <= 1 - _saturationLevel;

/// Fraction of patch pixels inside the image of the square of half size
/// [saturationRoiHalfMm] around [pointMm] that are clipped (white or black).
double _saturatedFraction(GrayPatch patch, Mat3 h, Pt pointMm) {
  final xs = <double>[], ys = <double>[];
  for (final sx in [-1.0, 1.0]) {
    for (final sy in [-1.0, 1.0]) {
      final p = applyHomography(h, Pt(pointMm.x + sx * saturationRoiHalfMm, pointMm.y + sy * saturationRoiHalfMm));
      xs.add(p.x);
      ys.add(p.y);
    }
  }
  final x0 = max(0, xs.reduce(min).floor() - patch.originX), x1 = min(patch.width - 1, xs.reduce(max).ceil() - patch.originX);
  final y0 = max(0, ys.reduce(min).floor() - patch.originY), y1 = min(patch.height - 1, ys.reduce(max).ceil() - patch.originY);
  var total = 0, sat = 0;
  for (var j = y0; j <= y1; j++) {
    for (var i = x0; i <= x1; i++) {
      total++;
      if (_isSaturated(patch.at(i, j))) sat++;
    }
  }
  return total == 0 ? 0 : sat / total;
}
