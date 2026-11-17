// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import '../homography.dart';
import '../linalg_small.dart';
import '../point.dart';
import '../pose.dart';

/// Pinhole camera looking at the sheet plane, for tests. Ground truth is exact.
///
/// Sheet frame (mm, x right, y down, z=0) maps to the camera frame (x right, y
/// down, z forward) by `P_c = R [X Y 0]^T + t`, `t = (offsetX, offsetY, distance)`.
/// `R = Rz(roll) * Rodrigues(axis, tilt)` with the tilt axis in the sheet plane at
/// azimuth [tiltAzimuthDeg]. The plane normal then makes exactly [tiltDeg] with
/// the optical axis, so the true tilt is known.
///
/// Local scale on the optical axis (offsets 0): along the tilt direction the
/// plane is foreshortened by cos(tilt), across it it is not, hence
/// `mm_per_px = Z / (f sqrt(cos tilt))` and anisotropy `1 / cos(tilt)`.
final class SyntheticCamera {
  SyntheticCamera({
    required this.image,
    required this.fPx,
    required this.distanceMm,
    this.tiltDeg = 0,
    this.tiltAzimuthDeg = 0,
    this.rollDeg = 0,
    this.offsetXmm = 0,
    this.offsetYmm = 0,
  });

  /// Random realistic phone-over-wall setup: f = 0.7..0.9 of the long side,
  /// 0.09..0.15 mm/px at the centre (the 150 mm frame then spans 1000 to 1670 px,
  /// inside a 3000 px short side even when tilted and rotated), tilt
  /// 0..[maxTiltDeg], roll +-20 deg, the sheet centre within +-10 mm of the axis.
  factory SyntheticCamera.random(
    Random rng, {
    ImageSize image = const ImageSize(4000, 3000),
    double maxTiltDeg = 25,
  }) {
    double u(double a, double b) => a + (b - a) * rng.nextDouble();
    final f = u(0.7, 0.9) * image.longSide;
    return SyntheticCamera(
      image: image,
      fPx: f,
      distanceMm: u(0.09, 0.15) * f,
      tiltDeg: u(0, maxTiltDeg),
      tiltAzimuthDeg: u(0, 360),
      rollDeg: u(-20, 20),
      offsetXmm: u(-10, 10),
      offsetYmm: u(-10, 10),
    );
  }

  final ImageSize image;
  final double fPx;
  final double distanceMm;
  final double tiltDeg;
  final double tiltAzimuthDeg;
  final double rollDeg;
  final double offsetXmm;
  final double offsetYmm;

  CameraIntrinsics get intrinsics =>
      CameraIntrinsics(fPx: fPx, cx: (image.width - 1) / 2, cy: (image.height - 1) / 2);

  /// Nominal scale of a fronto-parallel view, mm per px.
  double get nominalMmPerPx => distanceMm / fPx;

  /// Exact sheet-to-image homography, `h33 = 1`.
  late final Mat3 h = _homography();

  Mat3 _homography() {
    final th = tiltDeg * pi / 180, ph = tiltAzimuthDeg * pi / 180, ro = rollDeg * pi / 180;
    final ax = cos(ph), ay = sin(ph);
    final c = cos(th), s = sin(th), k = 1 - c;
    final rt = <double>[
      c + ax * ax * k, ax * ay * k, ay * s, //
      ax * ay * k, c + ay * ay * k, -ax * s,
      -ay * s, ax * s, c,
    ];
    final rz = <double>[cos(ro), -sin(ro), 0, sin(ro), cos(ro), 0, 0, 0, 1];
    final r = mat3Mul(rz, rt);
    final m = <double>[r[0], r[1], offsetXmm, r[3], r[4], offsetYmm, r[6], r[7], distanceMm];
    final intr = intrinsics;
    final hm = mat3Mul([fPx, 0, intr.cx, 0, fPx, intr.cy, 0, 0, 1], m);
    return [for (final v in hm) v / hm[8]];
  }

  late final Mat3 hInv = () {
    final i = mat3Inverse(h);
    return [for (final v in i) v / i[8]];
  }();

  Pt project(Pt sheetMm) => applyHomography(h, sheetMm);
  Pt unproject(Pt px) => applyHomography(hInv, px);
}
