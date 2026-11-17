// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'linalg_small.dart';
import 'point.dart';
import 'sheet.dart';

/// One detected marker: ArUco id and its 4 corners in pixels, OpenCV order.
final class MarkerDetection {
  const MarkerDetection({required this.id, required this.corners});

  final int id;
  final List<Pt> corners;
}

/// Base of the typed errors of homography estimation.
sealed class HomographyException implements Exception {
  const HomographyException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Fewer than [minMarkers] usable markers of the expected sheet.
final class TooFewMarkersException extends HomographyException {
  const TooFewMarkersException(this.found) : super('Penanda terlalu sedikit.');

  static const int minMarkers = 3;
  final int found;
}

/// The geometry cannot determine a homography (collinear or coincident points,
/// inconsistent depth, point on the horizon line).
final class DegenerateConfigurationException extends HomographyException {
  const DegenerateConfigurationException(super.message);
}

/// Malformed input (duplicate ids, not 4 corners, non-finite coordinates).
final class InvalidDetectionException extends HomographyException {
  const InvalidDetectionException(super.message);
}

/// Smaller/larger eigenvalue ratio of the point covariance below which a point
/// set counts as collinear: 1e-6 means the spread across the line is 0.1 percent
/// of the spread along it.
const double _collinearEigenRatio = 1e-6;

/// Second smallest eigenvalue of the DLT normal matrix relative to the largest;
/// below this the null space is not one dimensional.
const double _dltRankRatio = 1e-10;

/// Maps [p] with the homography [h]. Throws [DegenerateConfigurationException]
/// if the point is on the line mapped to infinity: `|w|` below 1e-9 times the
/// magnitude of its terms, which is scale invariant (cancellation, not size).
Pt applyHomography(Mat3 h, Pt p) {
  final w = h[6] * p.x + h[7] * p.y + h[8];
  final mag = (h[6] * p.x).abs() + (h[7] * p.y).abs() + h[8].abs();
  if (!w.isFinite || w.abs() <= 1e-9 * mag) {
    throw const DegenerateConfigurationException('Titik berada di garis tak hingga homografi.');
  }
  return Pt((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w);
}

/// Hartley normalisation: translate the centroid to 0, scale the mean distance to sqrt2.
({Mat3 t, Mat3 tInv, List<Pt> pts}) _normalize(List<Pt> pts) {
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.x;
    cy += p.y;
  }
  cx /= pts.length;
  cy /= pts.length;
  var md = 0.0;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in pts) {
    final dx = p.x - cx, dy = p.y - cy;
    md += sqrt(dx * dx + dy * dy);
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  md /= pts.length;
  if (md <= 0 || !md.isFinite) {
    throw const DegenerateConfigurationException('Titik berimpit.');
  }
  final tr = sxx + syy;
  final disc = sqrt(max(0.0, (sxx - syy) * (sxx - syy) / 4 + sxy * sxy));
  final big = tr / 2 + disc, small = tr / 2 - disc;
  if (small <= _collinearEigenRatio * big) {
    throw const DegenerateConfigurationException('Titik hampir segaris.');
  }
  final s = sqrt2 / md;
  return (
    t: [s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1],
    tInv: [1 / s, 0, cx, 0, 1 / s, cy, 0, 0, 1],
    pts: [for (final p in pts) Pt(s * (p.x - cx), s * (p.y - cy))],
  );
}

/// Sum of squared reprojection residuals (normalised units) for the 8 parameters
/// `p` (h33 = 1); infinity if any point has non-positive depth.
double _cost(List<double> p, List<Pt> src, List<Pt> dst) {
  var c = 0.0;
  for (var i = 0; i < src.length; i++) {
    final x = src[i].x, y = src[i].y;
    final w = p[6] * x + p[7] * y + 1;
    if (w <= 1e-9) return double.infinity;
    final du = (p[0] * x + p[1] * y + p[2]) / w - dst[i].x;
    final dv = (p[3] * x + p[4] * y + p[5]) / w - dst[i].y;
    c += du * du + dv * dv;
  }
  return c;
}

/// Levenberg-Marquardt on the reprojection error, in Hartley-normalised
/// coordinates (a uniform scaling of the pixel error, so the same minimiser).
List<double> _refine(List<double> p0, List<Pt> src, List<Pt> dst) {
  var p = p0;
  var cost = _cost(p, src, dst);
  if (!cost.isFinite) {
    throw const DegenerateConfigurationException('Kedalaman tidak konsisten (titik di belakang kamera).');
  }
  var lambda = 1e-3;
  for (var iter = 0; iter < 100 && cost > 1e-28; iter++) {
    final jtj = List.generate(8, (_) => List<double>.filled(8, 0));
    final jtr = List<double>.filled(8, 0);
    for (var i = 0; i < src.length; i++) {
      final x = src[i].x, y = src[i].y;
      final w = p[6] * x + p[7] * y + 1;
      final u = (p[0] * x + p[1] * y + p[2]) / w;
      final v = (p[3] * x + p[4] * y + p[5]) / w;
      final ru = u - dst[i].x, rv = v - dst[i].y;
      final ju = [x / w, y / w, 1 / w, 0, 0, 0, -u * x / w, -u * y / w];
      final jv = [0, 0, 0, x / w, y / w, 1 / w, -v * x / w, -v * y / w];
      for (var a = 0; a < 8; a++) {
        jtr[a] += ju[a] * ru + jv[a] * rv;
        for (var b = 0; b < 8; b++) {
          jtj[a][b] += ju[a] * ju[b] + jv[a] * jv[b];
        }
      }
    }
    var accepted = false;
    var stepSize = 0.0;
    for (var attempt = 0; attempt < 20 && !accepted; attempt++) {
      final damped = [
        for (var a = 0; a < 8; a++)
          [for (var b = 0; b < 8; b++) a == b ? jtj[a][a] * (1 + lambda) + 1e-18 : jtj[a][b]],
      ];
      try {
        final delta = solveLinear(damped, [for (final g in jtr) -g]);
        final cand = [for (var k = 0; k < 8; k++) p[k] + delta[k]];
        final c2 = _cost(cand, src, dst);
        if (c2 < cost) {
          p = cand;
          cost = c2;
          stepSize = delta.fold<double>(0, (m, d) => max(m, d.abs()));
          lambda = max(lambda / 10, 1e-12);
          accepted = true;
        } else {
          lambda *= 10;
        }
      } on SingularMatrixException {
        lambda *= 10;
      }
    }
    if (!accepted || stepSize < 1e-14) break;
  }
  return p;
}

/// DLT (Hartley-normalised) followed by LM refinement. Returns the 3x3
/// homography `src -> dst` scaled so that `h33 = 1` (when possible) and
/// `w > 0` for all `src` points.
///
/// Throws [DegenerateConfigurationException] for < 4 correspondences, collinear or
/// coincident points, rank deficiency, inconsistent depth, or a mirrored
/// (orientation reversing) assignment.
Mat3 estimateHomographyFromPoints(List<Pt> src, List<Pt> dst) {
  if (src.length != dst.length) {
    throw ArgumentError('src and dst must have the same length');
  }
  if (src.length < 4) {
    throw const DegenerateConfigurationException('Perlu minimal 4 pasang titik.');
  }
  if (src.any((p) => !p.isFinite) || dst.any((p) => !p.isFinite)) {
    throw const InvalidDetectionException('Koordinat tidak berhingga.');
  }
  final ns = _normalize(src);
  final nd = _normalize(dst);

  final ata = List.generate(9, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < src.length; i++) {
    final x = ns.pts[i].x, y = ns.pts[i].y, u = nd.pts[i].x, v = nd.pts[i].y;
    final r1 = [-x, -y, -1, 0, 0, 0, u * x, u * y, u];
    final r2 = [0, 0, 0, -x, -y, -1, v * x, v * y, v];
    for (var a = 0; a < 9; a++) {
      for (var b = 0; b < 9; b++) {
        ata[a][b] += r1[a] * r1[b] + r2[a] * r2[b];
      }
    }
  }
  final e = symmetricEigen(ata);
  if (e.values[1] <= _dltRankRatio * e.values[8]) {
    throw const DegenerateConfigurationException('Konfigurasi titik degenerate (rank kurang).');
  }
  final h = e.vectors[0];
  if (h[8].abs() < 1e-12 * sqrt(h.fold<double>(0, (s, v) => s + v * v))) {
    throw const DegenerateConfigurationException('Homografi memetakan pusat ke tak hingga.');
  }
  final p0 = [for (var k = 0; k < 8; k++) h[k] / h[8]];
  final p = _refine(p0, ns.pts, nd.pts);

  // Denormalise: H = Td^-1 H' Ts.
  var full = mat3Mul(nd.tInv, mat3Mul([...p, 1.0], ns.t));
  // Depth sign must agree for all points; then orient so that w > 0.
  final w0 = [for (final q in src) full[6] * q.x + full[7] * q.y + full[8]];
  final sign = w0.first >= 0 ? 1.0 : -1.0;
  if (w0.any((w) => w * sign <= 0)) {
    throw const DegenerateConfigurationException('Kedalaman tidak konsisten.');
  }
  // With w > 0, sign(det H) is the orientation of the map. Viewing the front of the
  // sheet preserves it; a reversed corner order or a mirrored view flips it.
  if (mat3Det([for (final v in full) v * sign]) <= 0) {
    throw const DegenerateConfigurationException(
      'Orientasi terbalik (urutan sudut penanda salah atau lembar tercermin).',
    );
  }
  final norm = sqrt(full.fold<double>(0, (s, v) => s + v * v));
  final scale = full[8].abs() > 1e-9 * norm ? full[8] : sign * norm;
  full = [for (final v in full) v / scale];
  return full;
}

/// Local scale of the sheet-to-image map at one point.
final class LocalScale {
  const LocalScale({required this.mmPerPx, required this.anisotropy});

  /// Geometric mean of the two principal scales, mm per image pixel.
  final double mmPerPx;

  /// Ratio of the larger to the smaller principal scale (>= 1; 1 means isotropic).
  final double anisotropy;
}

/// Result of [estimateSheetHomography].
final class HomographyEstimate {
  HomographyEstimate._({
    required this.h,
    required this.hInv,
    required this.rmsPx,
    required this.looMm,
    required this.markerCount,
  });

  /// Sheet (mm) to image (px), row-major, `h33 = 1`.
  final Mat3 h;

  /// Image (px) to sheet (mm).
  final Mat3 hInv;

  /// RMS of the Euclidean reprojection error over all corner points (px).
  final double rmsPx;

  /// Leave-one-marker-out RMS error in mm; null unless 4 markers were used.
  final double? looMm;

  final int markerCount;

  Pt project(Pt sheetMm) => applyHomography(h, sheetMm);
  Pt unproject(Pt imagePx) => applyHomography(hInv, imagePx);

  /// Local scale at the image of [sheetPoint] (default: window centre), from a
  /// central-difference Jacobian of `H_inv` with a 0.5 px step.
  LocalScale localScale([Pt sheetPoint = const Pt(0, 0)]) {
    const step = 0.5;
    final c = project(sheetPoint);
    final dx = (unproject(Pt(c.x + step, c.y)) - unproject(Pt(c.x - step, c.y))) * (1 / (2 * step));
    final dy = (unproject(Pt(c.x, c.y + step)) - unproject(Pt(c.x, c.y - step))) * (1 / (2 * step));
    final det = dx.x * dy.y - dy.x * dx.y;
    final a = dx.x * dx.x + dx.y * dx.y;
    final d = dy.x * dy.x + dy.y * dy.y;
    final half = (a + d) / 2;
    final disc = sqrt(max(0.0, half * half - det * det));
    final s1 = sqrt(half + disc);
    final s2 = sqrt(max(0.0, half - disc));
    return LocalScale(
      mmPerPx: sqrt(det.abs()),
      anisotropy: s2 == 0 ? double.infinity : s1 / s2,
    );
  }
}

/// Estimates the sheet-to-image homography from marker detections.
///
/// Markers whose id is not one of the four ids of [sheetId] are ignored. At least
/// 3 valid markers (12 points) are needed. [printScale] scales the sheet
/// coordinates so that "mm" are physical millimetres (5.1).
///
/// Diagnostics: `rms_px`; `loo_mm` only with 4 markers: each marker is left out,
/// H is re-fitted on the other three, the observed corners of the omitted marker
/// are mapped to the sheet with that H and compared to their known positions;
/// the RMS Euclidean error over the 16 corners is reported in mm.
HomographyEstimate estimateSheetHomography(
  List<MarkerDetection> detections, {
  required int sheetId,
  double printScale = 1,
}) {
  final ids = markerIdsForSheet(sheetId);
  final seen = <int>{};
  final used = <MarkerDetection>[];
  for (final d in detections) {
    if (!ids.contains(d.id)) continue;
    if (!seen.add(d.id)) {
      throw InvalidDetectionException('Penanda ${d.id} terdeteksi ganda.');
    }
    if (d.corners.length != 4 || d.corners.any((c) => !c.isFinite)) {
      throw InvalidDetectionException('Penanda ${d.id} tidak punya 4 sudut valid.');
    }
    used.add(d);
  }
  if (used.length < TooFewMarkersException.minMarkers) {
    throw TooFewMarkersException(used.length);
  }
  List<Pt> srcOf(Iterable<MarkerDetection> m) =>
      [for (final d in m) ...markerCornersMm(d.id, printScale: printScale)];
  List<Pt> dstOf(Iterable<MarkerDetection> m) => [for (final d in m) ...d.corners];

  final src = srcOf(used), dst = dstOf(used);
  final h = estimateHomographyFromPoints(src, dst);
  final hInv = _invertNormalized(h);

  var sq = 0.0;
  for (var i = 0; i < src.length; i++) {
    final e = applyHomography(h, src[i]).distanceTo(dst[i]);
    sq += e * e;
  }

  double? loo;
  if (used.length == 4) {
    var sum = 0.0;
    for (final omit in used) {
      final rest = used.where((d) => d != omit);
      final hk = estimateHomographyFromPoints(srcOf(rest), dstOf(rest));
      final hkInv = _invertNormalized(hk);
      final truth = markerCornersMm(omit.id, printScale: printScale);
      for (var i = 0; i < 4; i++) {
        final e = applyHomography(hkInv, omit.corners[i]).distanceTo(truth[i]);
        sum += e * e;
      }
    }
    loo = sqrt(sum / 16);
  }
  return HomographyEstimate._(
    h: h,
    hInv: hInv,
    rmsPx: sqrt(sq / src.length),
    looMm: loo,
    markerCount: used.length,
  );
}

Mat3 _invertNormalized(Mat3 h) {
  try {
    final inv = mat3Inverse(h);
    return inv[8].abs() > 1e-12 ? [for (final v in inv) v / inv[8]] : inv;
  } on SingularMatrixException {
    throw const DegenerateConfigurationException('Homografi singular.');
  }
}
