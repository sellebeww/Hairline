// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'linalg_small.dart';
import 'patch.dart';
import 'point.dart';
import 'rejection.dart';
import 'stats.dart';

// Local crack ridge detection and tracking (CLAUDE.md 5.3 "Penjejakan").
//
// A crack is a dark ridge: the second derivative of the intensity ACROSS it is
// positive. The nn component of the Hessian is evaluated with an elongated kernel:
// the profile across the crack is first averaged along the crack (about 4 mm), then
// differentiated with a Gaussian second-derivative kernel of scale sigma (a
// scale-space search, because a 2 mm crack has no single-scale centre peak). The
// search is metric (profiles are uniform in mm on the sheet).

/// Search radius around the stored point (5.3).
const double ridgeSearchRadiusMm = 1.5;

/// Minimum normalised response (signal over noise sd) to accept a ridge candidate
/// in the global search. Noise-only responses are Gaussian with unit sd after
/// normalisation; with about 8 scales x 50 positions of correlated trials, 5 sd
/// leaves a false-alarm probability well below 1e-3 per call (tested on 6 seeds).
const double ridgeMinSnr = 5;

/// A section centre is accepted at a lower level: its position is already known.
const double _sectionMinSnr = 3;

const double _alongHalfMm = 2; // the 4 mm segment
const int _globalProfiles = 9;
const double _maxScaleMm = 1.0;
const double _extraMm = 1.0;
const double _scaleRatio = 1.5;

/// Result of [findRidge].
final class RidgeResult {
  const RidgeResult({
    required this.centerMm,
    required this.directionDeg,
    required this.offsetMm,
    required this.snr,
    required this.lineRmsMm,
    required this.sections,
    required this.scaleMm,
  });

  /// Point of the crack centreline nearest to the stored point's normal (mm).
  final Pt centerMm;

  /// Crack direction (degrees from the sheet x axis, y down), in `(-90, 90]` relative to
  /// the stored direction.
  final double directionDeg;

  /// Distance between the stored point and [centerMm].
  final double offsetMm;

  /// Normalised strength of the ridge in the global search.
  final double snr;

  /// RMS (mm) of the section centres about the fitted line; NaN if fewer than 3.
  final double lineRmsMm;
  final int sections;

  /// Gaussian scale (mm) at which the ridge responded most strongly.
  final double scaleMm;
}

/// Finds the crack ridge nearest to [pointMm] within [ridgeSearchRadiusMm] and
/// refines its position and direction by a line fit through section centres.
///
/// [directionDeg] is the stored crack direction (the normal is searched). [noiseSigma]
/// is the pixel noise (default: [estimatePatchNoise]); [sigmaPx] the PSF sigma in px
/// (smallest scale searched). Throws [MeasurementException] with
/// [RejectReason.crackNotFound] if no ridge reaches [ridgeMinSnr] within the radius
/// and [RejectReason.patchTooSmall] if the patch does not cover the profiles (about
/// +-7 mm around the point, plus the along-crack span).
RidgeResult findRidge({
  required GrayPatch patch,
  required Mat3 h,
  required Pt pointMm,
  required double directionDeg,
  double? noiseSigma,
  double sigmaPx = 1.0,
  double searchRadiusMm = ridgeSearchRadiusMm,
}) {
  final noise = noiseSigma ?? estimatePatchNoise(patch);
  final a0 = directionDeg * pi / 180;
  final n0 = Pt(-sin(a0), cos(a0));
  final mmPerPx = directionalMmPerPx(h, pointMm, n0);
  final ds = mmPerPx; // 1 px steps: enough for sigma >= 1 px kernels
  final scales = <double>[];
  for (var s = max(sigmaPx, 1.0) * mmPerPx; s <= _maxScaleMm; s *= _scaleRatio) {
    scales.add(s);
  }

  // Global search on the along-averaged profile.
  // The response is evaluated 1 mm beyond the radius so that a ridge just outside it
  // shows as a rising slope (not a false peak on the window border).
  final halfRange = searchRadiusMm + _extraMm + 3 * _maxScaleMm + 2 * ds; // 2 samples: kernel radius rounds up
  final prof = _averagedProfile(patch, h, pointMm, directionDeg, -_alongHalfMm, _alongHalfMm, _globalProfiles, 0, halfRange, ds);
  final sd = noise / sqrt(_globalProfiles);
  final n = prof.length;
  final nWin = ((searchRadiusMm + _extraMm) / ds).floor();
  final nAccept = (searchRadiusMm / ds).floor();
  final mid = (n - 1) ~/ 2; // index of s = 0
  final best = List<double>.filled(2 * nWin + 1, 0);
  final bestScale = List<double>.filled(2 * nWin + 1, 0);
  for (final sigma in scales) {
    final k = _kernel(sigma, ds);
    for (var t = -nWin; t <= nWin; t++) {
      final snr = _response(prof, k, mid + t) / (sd * k.noiseGain);
      if (snr > best[t + nWin]) {
        best[t + nWin] = snr;
        bestScale[t + nWin] = sigma;
      }
    }
  }
  int? pick;
  for (var t = 0; t < best.length; t++) {
    final left = t > 0 ? best[t - 1] : -1.0, right = t < best.length - 1 ? best[t + 1] : -1.0;
    if (best[t] >= ridgeMinSnr && best[t] >= left && best[t] >= right) {
      if ((t - nWin).abs() <= nAccept && (pick == null || (t - nWin).abs() < (pick - nWin).abs())) pick = t;
    }
  }
  if (pick == null) {
    throw MeasurementException(
      RejectReason.crackNotFound,
      'Retak tidak ditemukan dalam radius ${searchRadiusMm.toStringAsFixed(1).replaceAll('.', ',')} mm dari titik ukur. '
      'Geser ponsel agar titik ukur tepat di atas retak, atau lembar mungkin bergeser.',
    );
  }
  final left = pick > 0 ? best[pick - 1] : best[pick], right = pick < best.length - 1 ? best[pick + 1] : best[pick];
  final denom = left - 2 * best[pick] + right;
  final sub = denom < 0 ? 0.5 * (left - right) / denom : 0.0;
  final sStar = ((pick - nWin) + sub.clamp(-0.5, 0.5)) * ds;
  final scale = bestScale[pick];

  // Line fit through section centres, two passes.
  var base = pointMm;
  var dir = directionDeg;
  var offset = sStar;
  var slope = 0.0;
  var rms = double.nan;
  var used = 0;
  for (var pass = 0; pass < 2; pass++) {
    final aRad = dir * pi / 180;
    final nrm = Pt(-sin(aRad), cos(aRad));
    final xs = <double>[], ys = <double>[];
    for (var sec = 0; sec < 4; sec++) {
      final lo = -_alongHalfMm + sec, hi = lo + 1;
      final aMid = (lo + hi) / 2;
      final pred = offset + slope * aMid;
      final win = max(0.5, 2 * scale);
      final rangeSec = win + 3 * scale + 2 * ds;
      final p = _averagedProfile(patch, h, base, dir, lo, hi, 5, pred, rangeSec, ds);
      final k = _kernel(scale, ds);
      final m = (p.length - 1) ~/ 2;
      final nw = (win / ds).floor();
      var bestSnr = -1.0, bestI = 0;
      final snrs = <double>[];
      for (var t = -nw; t <= nw; t++) {
        final snr = _response(p, k, m + t) / (noise / sqrt(5) * k.noiseGain);
        snrs.add(snr);
        if (snr > bestSnr) {
          bestSnr = snr;
          bestI = t + nw;
        }
      }
      if (bestSnr < _sectionMinSnr) continue;
      final l = bestI > 0 ? snrs[bestI - 1] : snrs[bestI], r = bestI < snrs.length - 1 ? snrs[bestI + 1] : snrs[bestI];
      final den = l - 2 * snrs[bestI] + r;
      final sb = den < 0 ? 0.5 * (l - r) / den : 0.0;
      xs.add(aMid);
      ys.add(pred + (bestI - nw + sb.clamp(-0.5, 0.5)) * ds);
    }
    used = xs.length;
    if (used < 3) break;
    final fit = ols(xs, ys);
    var ss = 0.0;
    for (var i = 0; i < used; i++) {
      final e = ys[i] - (fit.a + fit.b * xs[i]);
      ss += e * e;
    }
    rms = sqrt(ss / used);
    final newBase = base + nrm * fit.a;
    dir += atan(fit.b) * 180 / pi;
    base = newBase;
    offset = 0;
    slope = 0;
  }
  if (used < 3) {
    // Not enough sections: keep the stored direction, centre from the global peak.
    base = pointMm + n0 * sStar;
    dir = directionDeg;
  }
  var dd = (dir - directionDeg) % 180;
  if (dd > 90) dd -= 180;
  if (dd < -90) dd += 180;
  return RidgeResult(
    centerMm: base,
    directionDeg: directionDeg + dd,
    offsetMm: base.distanceTo(pointMm),
    snr: best[pick],
    lineRmsMm: rms,
    sections: used,
    scaleMm: scale,
  );
}

/// Mean of [count] profiles at evenly spaced along offsets in `[aLo, aHi]`.
List<double> _averagedProfile(
  GrayPatch patch,
  Mat3 h,
  Pt center,
  double dirDeg,
  double aLo,
  double aHi,
  int count,
  double offsetMm,
  double halfRange,
  double ds,
) {
  List<double>? acc;
  for (var i = 0; i < count; i++) {
    final along = count == 1 ? (aLo + aHi) / 2 : aLo + (aHi - aLo) * i / (count - 1);
    final p = sampleProfile(
      patch: patch,
      h: h,
      centerMm: center,
      directionDeg: dirDeg,
      halfRangeMm: halfRange,
      stepMm: ds,
      alongMm: along,
      offsetMm: offsetMm,
    );
    if (p == null) {
      throw const MeasurementException(
        RejectReason.patchTooSmall,
        'Potongan citra terlalu kecil untuk mencari retak di sekitar titik ukur.',
      );
    }
    acc ??= List<double>.filled(p.n, 0);
    for (var j = 0; j < p.n; j++) {
      acc[j] += p.values[j] / count;
    }
  }
  return acc!;
}

/// Zero-mean Gaussian second-derivative kernel of scale [sigma] (mm) sampled every
/// [ds] mm, in intensity per mm^2.
final class _Kernel {
  _Kernel(this.w, this.radius, this.noiseGain);
  final List<double> w;
  final int radius;

  /// `sqrt(sum w^2)`: noise sd of the response for white noise of sd 1.
  final double noiseGain;
}

_Kernel _kernel(double sigma, double ds) {
  final r = max(2, (3 * sigma / ds).ceil());
  final w = [
    for (var j = -r; j <= r; j++)
      ((j * ds) * (j * ds) / (sigma * sigma * sigma * sigma) - 1 / (sigma * sigma)) *
          exp(-(j * ds) * (j * ds) / (2 * sigma * sigma)) /
          (sigma * sqrt(2 * pi)),
  ];
  final m = w.reduce((a, b) => a + b) / w.length;
  for (var i = 0; i < w.length; i++) {
    w[i] -= m; // exact zero response to a constant background
  }
  // Scale normalisation sigma^2 cancels in the ratio with the noise gain.
  final gain = sqrt(w.fold<double>(0, (s, v) => s + v * v));
  return _Kernel(w, r, gain);
}

double _response(List<double> p, _Kernel k, int i) {
  var acc = 0.0;
  for (var j = -k.radius; j <= k.radius; j++) {
    acc += k.w[j + k.radius] * p[i + j];
  }
  return acc;
}
