// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'homography.dart';
import 'linalg_small.dart';
import 'point.dart';
import 'stats.dart';

/// Grayscale patch extracted by the platform adapter (CLAUDE.md 5.3). Values are
/// `0..1` (D4). [originX], [originY] are the image-pixel coordinates of patch pixel
/// (0, 0); pixel (i, j) is centred on integer image coordinates (D15).
final class GrayPatch {
  GrayPatch({
    required this.originX,
    required this.originY,
    required this.width,
    required this.height,
    required this.data,
  }) {
    if (width < 4 || height < 4) throw ArgumentError('patch must be at least 4x4 pixels');
    if (data.length != width * height) {
      throw ArgumentError('data length ${data.length} != width*height ${width * height}');
    }
  }

  final int originX;
  final int originY;
  final int width;
  final int height;
  final Float32List data;

  /// A copy with values converted from sRGB-encoded to linear light (IEC 61966-2-1).
  ///
  /// The width model is linear in intensity: a dip is a mix of crack and background
  /// light. JPEG gray values are gamma encoded, which bends sub-pixel profiles
  /// (SINTETIS bias about -3.6 percent at w 0.5 mm, sigma 1 px; MEASUREMENT_NOTES).
  /// The adapter should call this before measuring. Whether a phone's tone curve is
  /// close enough to sRGB can only be checked on a device.
  GrayPatch linearizedFromSrgb() => GrayPatch(
        originX: originX,
        originY: originY,
        width: width,
        height: height,
        data: Float32List.fromList([for (final v in data) srgbToLinear(v.toDouble())]),
      );

  /// Pixel at patch indices (i, j).
  double at(int i, int j) => data[j * width + i];

  /// True when the full 4x4 Catmull-Rom support of image coordinates ([x], [y])
  /// lies inside the patch, i.e. `x` in `[originX+1, originX+width-2]` (same for y).
  bool containsForCubic(double x, double y) {
    final u = x - originX, v = y - originY;
    return u >= 1 && u <= width - 2 && v >= 1 && v <= height - 2;
  }

  /// Bicubic Catmull-Rom sample at fractional image coordinates ([x], [y]).
  ///
  /// Boundary policy: no clamping or extrapolation. If the 4x4 support is not fully
  /// inside the patch (see [containsForCubic]) or an input is not finite the result
  /// is NaN, so callers cannot silently measure on invented pixels.
  double sampleCubic(double x, double y) {
    if (!containsForCubic(x, y)) return double.nan; // also false for NaN input
    final u = x - originX, v = y - originY;
    final i0 = min(u.floor(), width - 3), j0 = min(v.floor(), height - 3);
    final wx = _catmullRom(u - i0), wy = _catmullRom(v - j0);
    var acc = 0.0;
    for (var b = 0; b < 4; b++) {
      final row = (j0 - 1 + b) * width + (i0 - 1);
      final rowSum = wx[0] * data[row] + wx[1] * data[row + 1] + wx[2] * data[row + 2] + wx[3] * data[row + 3];
      acc += wy[b] * rowSum;
    }
    return acc;
  }
}

/// Catmull-Rom weights for the four taps at fractional position [t] in `[0, 1]`.
List<double> _catmullRom(double t) {
  final t2 = t * t, t3 = t2 * t;
  return [
    (-t3 + 2 * t2 - t) / 2,
    (3 * t3 - 5 * t2 + 2) / 2,
    (-3 * t3 + 4 * t2 + t) / 2,
    (t3 - t2) / 2,
  ];
}

/// Profile spacing in mm (5.3): `min(0.02 mm, 0.25 mm/px)`.
double profileStepMm(double mmPerPx) => min(0.02, 0.25 * mmPerPx);

/// Intensity samples on a line perpendicular to a direction, uniform in mm.
final class MetricProfile {
  const MetricProfile({required this.s0, required this.ds, required this.values});

  /// Offset (mm) of the first sample along the normal, relative to the line centre.
  final double s0;

  /// Spacing (mm).
  final double ds;
  final Float64List values;

  int get n => values.length;
  double sAt(int i) => s0 + i * ds;
}

/// Samples the patch along the normal of a line in sheet space.
///
/// The line passes through `centerMm + alongMm * t` with unit direction
/// `t = (cos a, sin a)` ([directionDeg] = `a`); samples are taken at normal offsets
/// `s = -halfRangeMm + i * stepMm` along `n = (-sin a, cos a)`, so the profile is
/// uniform in mm on the sheet plane regardless of perspective. [h] maps sheet mm to
/// image px (sampling needs the sheet-to-image direction); `H_inv` is only needed
/// for scale. Returns null when any sample falls outside the patch (see
/// [GrayPatch.sampleCubic]) or projects to infinity.
MetricProfile? sampleProfile({
  required GrayPatch patch,
  required Mat3 h,
  required Pt centerMm,
  required double directionDeg,
  required double halfRangeMm,
  required double stepMm,
  double alongMm = 0,
  double offsetMm = 0,
}) {
  final a = directionDeg * pi / 180;
  final tx = cos(a), ty = sin(a), nx = -ty, ny = tx;
  final n = (2 * halfRangeMm / stepMm).round() + 1;
  final out = Float64List(n);
  final bx = centerMm.x + alongMm * tx, by = centerMm.y + alongMm * ty;
  for (var i = 0; i < n; i++) {
    final s = offsetMm - halfRangeMm + i * stepMm;
    final Pt img;
    try {
      img = applyHomography(h, Pt(bx + s * nx, by + s * ny));
    } on DegenerateConfigurationException {
      return null;
    }
    final v = patch.sampleCubic(img.x, img.y);
    if (v.isNaN) return null;
    out[i] = v;
  }
  return MetricProfile(s0: offsetMm - halfRangeMm, ds: stepMm, values: out);
}

/// Millimetres per image pixel measured along the sheet direction [dirUnit] at
/// [pointMm] (central difference of the projection, 0.05 mm). Differs between
/// directions under tilt (foreshortening), unlike `LocalScale.mmPerPx` which is the
/// geometric mean.
double directionalMmPerPx(Mat3 h, Pt pointMm, Pt dirUnit) {
  const d = 0.05;
  final p1 = applyHomography(h, pointMm + dirUnit * d);
  final p0 = applyHomography(h, pointMm - dirUnit * d);
  return 2 * d / p1.distanceTo(p0);
}

/// Robust estimate of the pixel noise standard deviation of a patch.
///
/// For iid noise, `I - mean(4 neighbours)` has variance `1.25 sigma^2`; the MAD of
/// that residual ignores the sparse pixels that sit on edges and cracks. Assumes
/// spatially independent noise: real ISP output is correlated, so this tends to
/// UNDER-estimate it (documented limit). At most about 200k pixels are used.
double estimatePatchNoise(GrayPatch patch) {
  final w = patch.width, h = patch.height;
  final stride = max(1, sqrt((w - 2) * (h - 2) / 200000).ceil());
  final res = <double>[];
  for (var j = 1; j < h - 1; j += stride) {
    for (var i = 1; i < w - 1; i += stride) {
      final c = patch.data[j * w + i];
      final nb = patch.data[j * w + i - 1] + patch.data[j * w + i + 1] + patch.data[(j - 1) * w + i] + patch.data[(j + 1) * w + i];
      res.add(c - nb / 4);
    }
  }
  return madSigma(res) / sqrt(1.25);
}

/// Geometric-mean scale (mm per pixel) at [pointMm]: `1 / sqrt|det J|` with `J` the
/// numerical Jacobian of the sheet-to-image map (central difference, 0.05 mm). Same
/// quantity as `LocalScale.mmPerPx`, from `H` alone.
double localMmPerPx(Mat3 h, Pt pointMm) {
  const d = 0.05;
  final ex = (applyHomography(h, pointMm + const Pt(d, 0)) - applyHomography(h, pointMm - const Pt(d, 0))) * (1 / (2 * d));
  final ey = (applyHomography(h, pointMm + const Pt(0, d)) - applyHomography(h, pointMm - const Pt(0, d))) * (1 / (2 * d));
  return 1 / sqrt((ex.x * ey.y - ex.y * ey.x).abs());
}

/// sRGB electro-optical transfer: encoded value 0..1 to linear light 0..1.
double srgbToLinear(double v) => v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
