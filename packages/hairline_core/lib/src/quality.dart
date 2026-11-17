// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Frame and visit acceptance thresholds (CLAUDE.md 5.4). Initial values, tunable,
/// NOT yet tuned on real devices. Every field is documented with its meaning.
final class QualityThresholds {
  const QualityThresholds({
    this.minMarkers = 3,
    this.recommendedMarkers = 4,
    this.maxRmsPx = 0.8,
    this.maxLooMm = 0.3,
    this.maxTiltDeg = 20,
    this.hardRejectTiltDeg = 30,
    this.maxMmPerPx = 0.20,
    this.targetMmPerPx = 0.10,
    this.maxSigmaPx = 2.5,
    this.maxBlurAnisotropy = 1.6,
    this.maxSaturatedFraction = 0.01,
    this.minAcceptedFrames = 3,
    this.maxStoredFrames = 5,
  });

  /// Fewer detected markers than this: homography is not estimated.
  final int minMarkers;

  /// 4 markers are recommended: only then `loo_mm` exists and accuracy is best.
  final int recommendedMarkers;

  /// Max reprojection RMS (px). Corner detection noise is ~0.1 to 0.3 px.
  final double maxRmsPx;

  /// Max leave-one-marker-out RMS (mm). Larger means non-planar sheet or distortion.
  final double maxLooMm;

  /// Max plane tilt (deg), approximate (intrinsics are not calibrated).
  final double maxTiltDeg;

  /// Tilt above this (deg) is a hard reject: the estimate is too uncertain to use.
  final double hardRejectTiltDeg;

  /// Max scale (mm per px) accepted; coarser frames cannot resolve sub-mm cracks.
  final double maxMmPerPx;

  /// Target scale (mm per px); between this and [maxMmPerPx] a warning is given.
  final double targetMmPerPx;

  /// Max PSF sigma (px) from marker edges (image-dependent, later phase).
  final double maxSigmaPx;

  /// Max blur anisotropy ratio (image-dependent, later phase).
  final double maxBlurAnisotropy;

  /// Max fraction of saturated pixels in the ROI (image-dependent, later phase).
  final double maxSaturatedFraction;

  /// Accepted frames needed for an accepted visit.
  final int minAcceptedFrames;

  /// Max accepted frames kept per visit.
  final int maxStoredFrames;

  static const QualityThresholds standard = QualityThresholds();
}

/// Geometry-only inputs of the frame gate (no image needed).
final class FrameGeometry {
  const FrameGeometry({
    required this.markerCount,
    required this.rmsPx,
    required this.looMm,
    required this.tiltDeg,
    required this.mmPerPx,
  });

  final int markerCount;
  final double rmsPx;

  /// Null when fewer than 4 markers were detected.
  final double? looMm;
  final double tiltDeg;
  final double mmPerPx;
}

/// Reasons a frame is rejected. UI maps [code] to a specific Indonesian message
/// ("penanda tertutup", "terlalu miring", ...).
enum FrameRejection {
  tooFewMarkers('TOO_FEW_MARKERS'),
  rmsTooHigh('RMS_TOO_HIGH'),
  looTooHigh('LOO_TOO_HIGH'),
  tiltTooHigh('TILT_TOO_HIGH'),
  tiltHardReject('TILT_HARD_REJECT'),
  resolutionTooCoarse('RESOLUTION_TOO_COARSE');

  const FrameRejection(this.code);
  final String code;
}

/// Non-blocking remarks on an accepted frame.
enum FrameWarning {
  onlyThreeMarkers('ONLY_THREE_MARKERS'),
  mmPerPxAboveTarget('MM_PER_PX_ABOVE_TARGET');

  const FrameWarning(this.code);
  final String code;
}

final class FrameGeometryVerdict {
  const FrameGeometryVerdict({required this.rejections, required this.warnings});

  final List<FrameRejection> rejections;
  final List<FrameWarning> warnings;

  bool get accepted => rejections.isEmpty;
}

/// Geometry part of the frame gate (5.4). A value exactly on a limit passes.
FrameGeometryVerdict evaluateFrameGeometry(
  FrameGeometry g, {
  QualityThresholds thresholds = QualityThresholds.standard,
}) {
  final t = thresholds;
  final rej = <FrameRejection>[];
  final warn = <FrameWarning>[];
  if (g.markerCount < t.minMarkers) {
    rej.add(FrameRejection.tooFewMarkers);
    return FrameGeometryVerdict(rejections: rej, warnings: warn);
  }
  if (g.markerCount < t.recommendedMarkers) warn.add(FrameWarning.onlyThreeMarkers);
  if (g.rmsPx > t.maxRmsPx) rej.add(FrameRejection.rmsTooHigh);
  final loo = g.looMm;
  if (loo != null && loo > t.maxLooMm) rej.add(FrameRejection.looTooHigh);
  if (g.tiltDeg > t.hardRejectTiltDeg) {
    rej.add(FrameRejection.tiltHardReject);
  } else if (g.tiltDeg > t.maxTiltDeg) {
    rej.add(FrameRejection.tiltTooHigh);
  }
  if (g.mmPerPx > t.maxMmPerPx) {
    rej.add(FrameRejection.resolutionTooCoarse);
  } else if (g.mmPerPx > t.targetMmPerPx) {
    warn.add(FrameWarning.mmPerPxAboveTarget);
  }
  return FrameGeometryVerdict(rejections: rej, warnings: warn);
}

/// A visit is accepted with at least [QualityThresholds.minAcceptedFrames] accepted frames.
bool isVisitAccepted(
  int acceptedFrames, {
  QualityThresholds thresholds = QualityThresholds.standard,
}) =>
    acceptedFrames >= thresholds.minAcceptedFrames;
