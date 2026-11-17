// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'linalg_small.dart';
import 'lm.dart';
import 'patch.dart';
import 'point.dart';
import 'rejection.dart';
import 'sheet.dart';
import 'special.dart';
import 'stats.dart';

// PSF estimation from the outer marker edges (CLAUDE.md 5.3a).
//
// Model: an ideal step edge seen through a Gaussian kernel gives
// `I(s) = a + b Phi((s - s0) / sigma)`. The fitted sigma is the APPARENT kernel of
// the whole imaging chain (lens PSF, ISP, and the pixel aperture of variance
// 1/12 px^2), which is exactly the kernel a crack is seen through, so it is the
// right sigma for the crack model. For a Gaussian PSF of sigma_g it equals about
// `sqrt(sigma_g^2 + 1/12)` px.

/// Minimum step height (intensity units 0..1) for an edge profile to be trusted.
const double minEdgeContrast = 0.1;

/// Result of an edge step-response fit.
final class EdgeFit {
  const EdgeFit({
    required this.low,
    required this.step,
    required this.edgeMm,
    required this.sigmaMm,
    required this.rms,
  });

  /// Intensity far on the negative-s side.
  final double low;

  /// Height of the step (signed).
  final double step;

  /// Fitted edge location along the profile normal (mm).
  final double edgeMm;
  final double sigmaMm;

  /// RMS of the fit residual.
  final double rms;
}

/// Fits `a + b Phi((s - s0) / sigma)` to a profile. Null if the fit fails, the
/// step is below [minEdgeContrast], or sigma lands on its bound.
EdgeFit? fitEdgeProfile(MetricProfile profile, {required double sigmaGuessMm}) {
  final n = profile.n;
  final v = profile.values;
  final k = max(3, n ~/ 10);
  var lowSum = 0.0, highSum = 0.0;
  for (var i = 0; i < k; i++) {
    lowSum += v[i];
    highSum += v[n - 1 - i];
  }
  final low = lowSum / k, high = highSum / k;
  final step = high - low;
  if (step.abs() < minEdgeContrast) return null;
  final mid = low + step / 2;
  var s0 = profile.sAt(n ~/ 2);
  for (var i = 1; i < n; i++) {
    if ((v[i - 1] - mid) * (v[i] - mid) <= 0 && v[i] != v[i - 1]) {
      s0 = profile.sAt(i - 1) + profile.ds * (mid - v[i - 1]) / (v[i] - v[i - 1]);
      break;
    }
  }
  final half = profile.ds * (n - 1) / 2;
  final sMin = sigmaGuessMm / 10, sMax = sigmaGuessMm * 8;
  final res = levenbergMarquardt(
    p0: [low, step, s0, sigmaGuessMm],
    nResiduals: n,
    lower: [double.negativeInfinity, double.negativeInfinity, -half, sMin],
    upper: [double.infinity, double.infinity, half, sMax],
    residuals: (p, r) {
      for (var i = 0; i < n; i++) {
        r[i] = v[i] - (p[0] + p[1] * normalCdf((profile.sAt(i) - p[2]) / p[3]));
      }
    },
    jacobian: (p, j) {
      for (var i = 0; i < n; i++) {
        final z = (profile.sAt(i) - p[2]) / p[3];
        final pdf = normalPdf(z);
        j[i][0] = -1;
        j[i][1] = -normalCdf(z);
        j[i][2] = p[1] * pdf / p[3];
        j[i][3] = p[1] * pdf * z / p[3];
      }
    },
  );
  if (!res.converged || res.atLower[3] || res.atUpper[3]) return null;
  if (res.params[1].abs() < minEdgeContrast) return null;
  return EdgeFit(
    low: res.params[0],
    step: res.params[1],
    edgeMm: res.params[2],
    sigmaMm: res.params[3],
    rms: sqrt(res.rss / n),
  );
}

/// Which family an edge belongs to: normal along the sheet x axis (vertical edges)
/// or along y (horizontal edges).
enum EdgeAxis { normalX, normalY }

/// Sigma of one marker edge (median over its profiles).
final class EdgeSigma {
  const EdgeSigma({
    required this.markerId,
    required this.axis,
    required this.sigmaPx,
    required this.sigmaMm,
    required this.profiles,
  });

  final int markerId;
  final EdgeAxis axis;
  final double sigmaPx;
  final double sigmaMm;

  /// Number of successful profile fits (of 8 attempted).
  final int profiles;
}

/// PSF estimate of a frame (5.3a).
final class PsfEstimate {
  const PsfEstimate({
    required this.edges,
    required this.sigmaPx,
    required this.uSigmaPx,
    required this.sigmaMm,
    required this.uSigmaMm,
    required this.anisotropy,
  });

  final List<EdgeSigma> edges;

  /// Median apparent sigma over edges, in image pixels (isotropic image blur gives
  /// the same value for every edge orientation, whatever the tilt).
  final double sigmaPx;

  /// Sample standard deviation of the per-edge sigmas (px): `u_sigma_edge`.
  final double uSigmaPx;

  /// Median over edges of the per-edge sigma in mm (the 5.3a definition). Under tilt
  /// the mm value depends on direction: use [sigmaMmAlong] for a crack.
  final double sigmaMm;
  final double uSigmaMm;

  /// Ratio of the larger to the smaller median sigma (px) of the two edge families;
  /// null if one family has no edge. Detects hand-motion blur only when the motion
  /// axis is not at 45 degrees to the marker edges (documented limit).
  final double? anisotropy;

  /// Sigma and `u_sigma_edge` in mm for a crack with direction [directionDeg] at
  /// [pointMm]: the px sigma times the mm per px along the crack normal.
  ({double sigmaMm, double uSigmaMm}) sigmaMmAlong(Mat3 h, Pt pointMm, double directionDeg) {
    final a = directionDeg * pi / 180;
    final k = directionalMmPerPx(h, pointMm, Pt(-sin(a), cos(a)));
    return (sigmaMm: sigmaPx * k, uSigmaMm: uSigmaPx * k);
  }
}

/// Number of profiles per marker edge (5.3a).
const int profilesPerEdge = 8;

/// Half length (mm at print scale 1) of the part of each 30 mm edge that is sampled;
/// stays 5 mm clear of the corners.
const double _edgeHalfSpanMm = 10;

/// Half range of an edge profile in image pixels (about 4 sigma at 2.5 px).
const double _edgeHalfRangePx = 10;

const int _minEdges = 3;

/// Estimates the PSF sigma from the outer edges of the markers of [sheetId] (the
/// two edges of each marker that face away from the window), 8 profiles per edge.
///
/// [markerIds] limits the markers to those detected (default: all 4). Edges that
/// leave the patch or fail to fit are skipped; fewer than 3 usable edges throws a
/// [MeasurementException] with [RejectReason.psfEdgesUnavailable].
PsfEstimate estimatePsf({
  required GrayPatch patch,
  required Mat3 h,
  required int sheetId,
  double printScale = 1,
  List<int>? markerIds,
}) {
  final ids = markerIdsForSheet(sheetId);
  final use = markerIds == null ? ids : [for (final id in ids) if (markerIds.contains(id)) id];
  final edges = <EdgeSigma>[];
  for (final id in use) {
    final c = markerCenterMm(id, printScale: printScale);
    final hs = markerSideMm / 2 * printScale;
    final pos = markerPositionOfId(id);
    final left = pos == MarkerPosition.topLeft || pos == MarkerPosition.bottomLeft;
    final top = pos == MarkerPosition.topLeft || pos == MarkerPosition.topRight;
    final specs = [
      // (midpoint, along-edge angle, axis): vertical edge -> along y (90 deg).
      (Pt(c.x + (left ? -hs : hs), c.y), 90.0, EdgeAxis.normalX),
      (Pt(c.x, c.y + (top ? -hs : hs)), 0.0, EdgeAxis.normalY),
    ];
    for (final (mid, angle, axis) in specs) {
      final e = _edgeSigma(patch, h, id, mid, angle, axis, printScale);
      if (e != null) edges.add(e);
    }
  }
  if (edges.length < _minEdges) {
    throw const MeasurementException(
      RejectReason.psfEdgesUnavailable,
      'Tepi penanda tidak cukup terlihat untuk menaksir keburaman. Pastikan penanda tidak tertutup.',
    );
  }
  final sPx = [for (final e in edges) e.sigmaPx];
  final sMm = [for (final e in edges) e.sigmaMm];
  double? family(EdgeAxis a) {
    final v = [for (final e in edges) if (e.axis == a) e.sigmaPx];
    return v.isEmpty ? null : median(v);
  }

  final fx = family(EdgeAxis.normalX), fy = family(EdgeAxis.normalY);
  return PsfEstimate(
    edges: edges,
    sigmaPx: median(sPx),
    uSigmaPx: sampleSd(sPx),
    sigmaMm: median(sMm),
    uSigmaMm: sampleSd(sMm),
    anisotropy: fx == null || fy == null ? null : max(fx, fy) / min(fx, fy),
  );
}

EdgeSigma? _edgeSigma(GrayPatch patch, Mat3 h, int id, Pt mid, double angleDeg, EdgeAxis axis, double printScale) {
  final a = angleDeg * pi / 180;
  final normal = Pt(-sin(a), cos(a));
  final mmPerPx = directionalMmPerPx(h, mid, normal);
  final range = _edgeHalfRangePx * mmPerPx;
  final step = profileStepMm(mmPerPx);
  final fits = <double>[];
  for (var k = 0; k < profilesPerEdge; k++) {
    final along = (-1 + 2 * (k + 0.5) / profilesPerEdge) * _edgeHalfSpanMm * printScale;
    final prof = sampleProfile(
      patch: patch,
      h: h,
      centerMm: mid,
      directionDeg: angleDeg,
      halfRangeMm: range,
      stepMm: step,
      alongMm: along,
    );
    if (prof == null) continue;
    final fit = fitEdgeProfile(prof, sigmaGuessMm: mmPerPx);
    if (fit != null) fits.add(fit.sigmaMm);
  }
  if (fits.length < profilesPerEdge ~/ 2) return null;
  final sigmaMm = median(fits);
  return EdgeSigma(markerId: id, axis: axis, sigmaPx: sigmaMm / mmPerPx, sigmaMm: sigmaMm, profiles: fits.length);
}
