// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'homography.dart';
import 'linalg_small.dart';
import 'point.dart';
import 'sheet.dart';

/// Image dimensions in pixels.
final class ImageSize {
  const ImageSize(this.width, this.height);

  final int width;
  final int height;

  double get longSide => max(width, height).toDouble();
  double get diagonal => sqrt((width * width + height * height).toDouble());
}

/// Pinhole intrinsics with square pixels. Pixel (i,j) is centred on (i,j), so the
/// image centre is ((w-1)/2, (h-1)/2) (same convention as the patches, D4).
final class CameraIntrinsics {
  const CameraIntrinsics({required this.fPx, required this.cx, required this.cy});

  /// Approximate intrinsics (5.2): principal point at the centre, `f_px` from lens
  /// metadata when valid, else `0.75 * longest side`.
  ///
  /// [sensorLongSideMm] is the physical sensor dimension along the image's long
  /// side (the "sensor width" of a landscape frame). Using the long side makes the
  /// result independent of portrait or landscape orientation.
  factory CameraIntrinsics.fromImage(
    ImageSize size, {
    double? focalMm,
    double? sensorLongSideMm,
  }) {
    final valid = focalMm != null &&
        sensorLongSideMm != null &&
        focalMm.isFinite &&
        sensorLongSideMm.isFinite &&
        focalMm > 0 &&
        sensorLongSideMm > 0;
    final f = valid ? focalMm / sensorLongSideMm * size.longSide : defaultFocalFraction * size.longSide;
    return CameraIntrinsics(fPx: f, cx: (size.width - 1) / 2, cy: (size.height - 1) / 2);
  }

  /// Fallback `f_px / longest side` when no lens metadata is available.
  static const double defaultFocalFraction = 0.75;

  final double fPx;
  final double cx;
  final double cy;

  /// Same principal point, focal length scaled by [factor] (for sensitivity tests).
  CameraIntrinsics withFocalScale(double factor) => CameraIntrinsics(fPx: fPx * factor, cx: cx, cy: cy);
}

/// Plane tilt estimate. The intrinsics are never calibrated, so the value is
/// always approximate (5.2).
final class TiltEstimate {
  const TiltEstimate(this.tiltDeg);

  /// Angle between the optical axis and the plane normal, degrees in [0, 90].
  final double tiltDeg;

  /// Always true in the MVP: `f_px` comes from metadata or a default.
  bool get tiltIsApprox => true;
}

/// Tilt from the homography decomposition `H ~ K [r1 r2 t]`: with
/// `m_i = K^-1 h_i`, the plane normal in camera coordinates is `m1 x m2`. The
/// result does not need the scale factor and is insensitive to the sign of H.
TiltEstimate estimateTilt(Mat3 h, CameraIntrinsics k) {
  final m1 = [(h[0] - k.cx * h[6]) / k.fPx, (h[3] - k.cy * h[6]) / k.fPx, h[6]];
  final m2 = [(h[1] - k.cx * h[7]) / k.fPx, (h[4] - k.cy * h[7]) / k.fPx, h[7]];
  final n = [
    m1[1] * m2[2] - m1[2] * m2[1],
    m1[2] * m2[0] - m1[0] * m2[2],
    m1[0] * m2[1] - m1[1] * m2[0],
  ];
  final len = sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
  if (!len.isFinite || len < 1e-300) {
    throw const DegenerateConfigurationException('Homografi tidak dapat didekomposisi.');
  }
  return TiltEstimate(acos((n[2].abs() / len).clamp(0.0, 1.0)) * 180 / pi);
}

/// Pose of the sheet in the image, reduced to what 5.2 compares.
final class PoseState {
  const PoseState({
    required this.centerPx,
    required this.areaPx2,
    required this.rotationDeg,
    required this.tiltDeg,
  });

  /// Image position of the window centre (sheet origin).
  final Pt centerPx;

  /// Image area of the square through the four marker centres.
  final double areaPx2;

  /// In-plane rotation of the sheet x axis in the image, degrees, positive
  /// clockwise on screen (image y points down).
  final double rotationDeg;

  final double tiltDeg;

  bool get tiltIsApprox => true;
}

PoseState poseStateFromHomography(Mat3 h, CameraIntrinsics k) {
  const o = markerCenterOffsetMm;
  final corners = [
    applyHomography(h, const Pt(-o, -o)),
    applyHomography(h, const Pt(o, -o)),
    applyHomography(h, const Pt(o, o)),
    applyHomography(h, const Pt(-o, o)),
  ];
  var twice = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = corners[i], b = corners[(i + 1) % 4];
    twice += a.x * b.y - b.x * a.y;
  }
  final area = twice.abs() / 2;
  if (!area.isFinite || area <= 0) {
    throw const DegenerateConfigurationException('Homografi meruntuhkan bingkai menjadi garis.');
  }
  final axis = applyHomography(h, const Pt(o, 0)) - applyHomography(h, const Pt(-o, 0));
  return PoseState(
    centerPx: applyHomography(h, const Pt(0, 0)),
    areaPx2: area,
    rotationDeg: atan2(axis.y, axis.x) * 180 / pi,
    tiltDeg: estimateTilt(h, k).tiltDeg,
  );
}

/// "Ready to capture" thresholds (5.2). A deviation exactly on a limit is still ready.
final class PoseThresholds {
  const PoseThresholds({
    this.maxTranslationFrac = 0.03,
    this.minScaleRatio = 0.9,
    this.maxScaleRatio = 1.1,
    this.maxRotationDeg = 5,
    this.maxTiltDeltaDeg = 8,
  });

  /// Max distance between window centres as a fraction of the image diagonal.
  final double maxTranslationFrac;

  /// Allowed `sqrt(area_now / area_reference)` range (distance change of +-10 percent).
  final double minScaleRatio;
  final double maxScaleRatio;

  /// Max in-plane rotation difference (degrees).
  final double maxRotationDeg;

  /// Max difference of the tilt angles (degrees).
  final double maxTiltDeltaDeg;

  static const PoseThresholds standard = PoseThresholds();
}

/// Guidance actions, expressed as what the user does with the phone. UI maps
/// [code] to Indonesian text.
enum PoseInstruction {
  holdFlat('HOLD_FLAT'),
  closer('CLOSER'),
  farther('FARTHER'),
  rotateCw('ROTATE_CW'),
  rotateCcw('ROTATE_CCW'),
  moveLeft('MOVE_LEFT'),
  moveRight('MOVE_RIGHT'),
  moveUp('MOVE_UP'),
  moveDown('MOVE_DOWN');

  const PoseInstruction(this.code);
  final String code;
}

final class PoseDeviation {
  const PoseDeviation({
    required this.dxFrac,
    required this.dyFrac,
    required this.scaleRatio,
    required this.rotationDeg,
    required this.tiltDeltaDeg,
    required this.instructions,
  });

  /// Signed window-centre offset current minus reference, fraction of the image diagonal.
  final double dxFrac;
  final double dyFrac;
  double get translationFrac => sqrt(dxFrac * dxFrac + dyFrac * dyFrac);

  /// `sqrt(area_now / area_ref)`; above 1 means the phone is closer than the reference.
  final double scaleRatio;

  /// Current minus reference in-plane rotation, wrapped to (-180, 180].
  final double rotationDeg;

  /// `|tilt_now - tilt_ref|`.
  final double tiltDeltaDeg;

  /// Triggered instructions, most important first. Empty means ready to capture.
  final List<PoseInstruction> instructions;

  bool get isReady => instructions.isEmpty;
  PoseInstruction? get primary => instructions.isEmpty ? null : instructions.first;
}

double _wrap180(double d) {
  var x = d % 360;
  if (x > 180) x -= 360;
  if (x <= -180) x += 360;
  return x;
}

/// Compares the current pose with the reference (baseline visit) pose.
///
/// Sign conventions follow "move the phone": the sheet appearing right of the
/// reference means the phone must move right; a sheet rotated clockwise means
/// the phone must rotate clockwise; a sheet larger than the reference means the
/// phone is too close. Only the dominant translation axis is reported at a time.
PoseDeviation comparePose(
  PoseState current,
  PoseState reference,
  ImageSize image, {
  PoseThresholds thresholds = PoseThresholds.standard,
}) {
  final d = image.diagonal;
  final dx = (current.centerPx.x - reference.centerPx.x) / d;
  final dy = (current.centerPx.y - reference.centerPx.y) / d;
  final ratio = sqrt(current.areaPx2 / reference.areaPx2);
  final rot = _wrap180(current.rotationDeg - reference.rotationDeg);
  final tilt = (current.tiltDeg - reference.tiltDeg).abs();
  final out = <PoseInstruction>[];
  if (tilt > thresholds.maxTiltDeltaDeg) out.add(PoseInstruction.holdFlat);
  if (ratio > thresholds.maxScaleRatio) out.add(PoseInstruction.farther);
  if (ratio < thresholds.minScaleRatio) out.add(PoseInstruction.closer);
  if (rot > thresholds.maxRotationDeg) out.add(PoseInstruction.rotateCw);
  if (rot < -thresholds.maxRotationDeg) out.add(PoseInstruction.rotateCcw);
  if (sqrt(dx * dx + dy * dy) > thresholds.maxTranslationFrac) {
    if (dx.abs() >= dy.abs()) {
      out.add(dx > 0 ? PoseInstruction.moveRight : PoseInstruction.moveLeft);
    } else {
      out.add(dy > 0 ? PoseInstruction.moveDown : PoseInstruction.moveUp);
    }
  }
  return PoseDeviation(
    dxFrac: dx,
    dyFrac: dy,
    scaleRatio: ratio,
    rotationDeg: rot,
    tiltDeltaDeg: tilt,
    instructions: out,
  );
}
