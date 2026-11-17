// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'linalg_small.dart';
import 'lm.dart';
import 'patch.dart';
import 'point.dart';
import 'rejection.dart';
import 'special.dart';
import 'stats.dart';

// Sub-pixel crack width by a box-convolved-Gaussian profile model (CLAUDE.md 5.3).
//
//   I(s) = B + m s - D [Phi((s - c + w/2)/sigma) - Phi((s - c - w/2)/sigma)]
//
// Free: B, m (linear background), D >= 0, c, 0 <= w <= wMax. Fixed: sigma, the
// apparent kernel from the marker edges (psf.dart). Physical limit: only the
// area D*w is identifiable when w << sigma, so D and w become collinear; the
// covariance then blows up and the result is flagged, it is not hidden.

/// Outcome of the contrast gate and fit health.
enum FitStatus {
  terukur('TERUKUR'),
  tidakTerukur('TIDAK_TERUKUR');

  const FitStatus(this.code);
  final String code;
}

/// Why a fit is [FitStatus.tidakTerukur].
enum FitIssue {
  /// `dip / sigma_noise` below the gate (5.3: D / sigma_noise >= 3).
  lowContrast,

  /// The final fit did not converge.
  fitFailed,

  /// `J^T J` singular or condition number above the limit: no usable covariance.
  unstableFit,
}

/// Tunable settings of [fitCrackWidth]. Defaults follow CLAUDE.md 5.3.
final class ProfileFitConfig {
  const ProfileFitConfig({
    this.segmentMm = 4,
    this.profiles = 40,
    this.halfRangeMm = 3,
    this.rho = 1.0,
    this.rhoCalibrated = true,
    this.minContrastSnr = 3,
    this.maxWidthMm = 3,
    this.maxCondition = 1e12,
    this.alignWithSmoothedCenters = true,
  });

  /// Length of the measurement segment along the crack (the measurand, 5.3).
  final double segmentMm;

  /// Profiles along the segment.
  final int profiles;

  /// Profile half range across the crack.
  final double halfRangeMm;

  /// Variance inflation for correlated interpolated samples (5.3). 1.0 is the value
  /// supported by the full-chain synthetic coverage study (SINTETIS, docs/SYNTHETIC_VALIDATION.md:
  /// the interval coverage is at least 90 percent for every reported condition without
  /// inflation, and inflating further only chases the renderer's own resolution). Not
  /// validated on real devices.
  final double rho;
  final bool rhoCalibrated;

  /// Gate: fitted dip depth over noise sd must reach this (5.3).
  final double minContrastSnr;

  /// Upper bound on w; wider cracks are outside the design (profile range 3 mm).
  final double maxWidthMm;

  /// Largest tolerated condition number of the scaled `J^T J`.
  final double maxCondition;

  /// Pass 2 aligns profiles on a robust quadratic through the per-profile centres
  /// (true) or on each raw per-profile centre (false, the literal 5.3 reading).
  final bool alignWithSmoothedCenters;
}

/// Result of the two-pass profile fit.
final class ProfileFitResult {
  const ProfileFitResult({
    required this.status,
    required this.issue,
    required this.widthMm,
    required this.uWidthMm,
    required this.uWidthRawMm,
    required this.rho,
    required this.rhoCalibrated,
    required this.params,
    required this.covariance,
    required this.centerOffsetMm,
    required this.centerSlope,
    required this.centerSdMm,
    required this.residualRms,
    required this.sigmaNoise,
    required this.dipDepth,
    required this.contrastSnr,
    required this.widthsPerProfile,
    required this.wMedian,
    required this.alongSdMm,
    required this.dwDs,
    required this.dwDsSe,
    required this.goodProfiles,
    required this.conditionNumber,
    required this.boundsActive,
    required this.misfitRatio,
    required this.misfitRel,
    required this.uSigmaWMm,
    required this.sigmaMm,
    required this.alignmentFallback,
  });

  final FitStatus status;
  final FitIssue? issue;

  /// Final width (mm), from the aligned mean profile. Not meaningful unless
  /// [status] is [FitStatus.terukur] or the caller also shows [uWidthMm].
  final double widthMm;

  /// `sqrt(rho * Var(w))` (mm); infinity when there is no covariance.
  final double uWidthMm;

  /// Same without the inflation factor.
  final double uWidthRawMm;
  final double rho;
  final bool rhoCalibrated;

  /// `[B, m, D, c, w]` of the final fit.
  final List<double> params;

  /// `rho * s2 (J^T J)^-1` (5x5) or null.
  final List<List<double>>? covariance;

  /// Crack centre at the measurement point, relative to the input line (mm).
  final double centerOffsetMm;

  /// Slope of the centre line against the along coordinate (tan of the angle error).
  final double centerSlope;

  /// Scatter of per-profile centres about the smoothed line (mm).
  final double centerSdMm;

  /// RMS residual of the final fit (intensity).
  final double residualRms;

  /// Per-profile noise sd used by the gate: `max(median per-profile residual rms,
  /// noiseFloor)`.
  final double sigmaNoise;

  /// Peak intensity dip of the fitted model: `D (2 Phi(w / 2 sigma) - 1)`. Equals
  /// D for wide cracks; it is what the data constrain for narrow ones.
  final double dipDepth;
  final double contrastSnr;

  /// Pass-1 width per profile; null where that profile's fit was not usable.
  final List<double?> widthsPerProfile;
  final double wMedian;

  /// Sample sd of the usable per-profile widths (includes per-profile noise).
  final double alongSdMm;

  /// OLS slope of per-profile width along the crack (mm/mm) and its standard error;
  /// NaN when fewer than 8 profiles are usable.
  final double dwDs;
  final double dwDsSe;
  final int goodProfiles;

  /// Condition number of the scaled `J^T J` of the final fit.
  final double conditionNumber;

  /// Names of final-fit parameters sitting on a bound.
  final List<String> boundsActive;

  /// Final residual rms over the rms expected from pure noise (per-profile noise
  /// over sqrt(profiles)). Near 1 when the model is right; much above 1 when the
  /// profile has structure the model cannot explain.
  final double misfitRatio;

  /// Systematic part of the final residual as a fraction of the dip depth:
  /// `sqrt(max(0, rms^2 - noise^2 / profiles)) / dip`, with the per-profile noise
  /// taken from pass 1. Unlike [misfitRatio] it does not grow when the image is very
  /// clean (SINTETIS: at most 0.25 percent for correct models at any noise, 1.2 percent
  /// and up for rough edges, shadows and stains).
  final double misfitRel;

  /// Half the difference of widths refitted at `sigma +- u_sigma` (mm).
  final double uSigmaWMm;
  final double sigmaMm;

  /// True if too few profile centres were usable and pass 2 used no alignment.
  final bool alignmentFallback;
}

const List<String> _paramNames = ['B', 'm', 'D', 'c', 'w'];

/// Cache-sharing evaluation of the model and its Jacobian.
final class _BoxModel {
  _BoxModel(this.s, this.sigma)
      : _pa = Float64List(s.length),
        _pb = Float64List(s.length),
        _fa = Float64List(s.length),
        _fb = Float64List(s.length);

  final Float64List s;
  final double sigma;
  final Float64List _pa, _pb, _fa, _fb;
  List<double>? _last;

  void _ensure(List<double> p) {
    final l = _last;
    if (l != null && l[0] == p[0] && l[1] == p[1] && l[2] == p[2] && l[3] == p[3] && l[4] == p[4]) return;
    _last = List<double>.of(p);
    final c = p[3], w2 = p[4] / 2;
    for (var i = 0; i < s.length; i++) {
      final a = (s[i] - c + w2) / sigma, b = (s[i] - c - w2) / sigma;
      _pa[i] = normalCdf(a);
      _pb[i] = normalCdf(b);
      _fa[i] = normalPdf(a);
      _fb[i] = normalPdf(b);
    }
  }

  void residuals(Float64List data, List<double> p, List<double> r) {
    _ensure(p);
    for (var i = 0; i < s.length; i++) {
      r[i] = data[i] - (p[0] + p[1] * s[i] - p[2] * (_pa[i] - _pb[i]));
    }
  }

  void jacobian(List<double> p, List<List<double>> j) {
    _ensure(p);
    final d = p[2];
    for (var i = 0; i < s.length; i++) {
      j[i][0] = -1;
      j[i][1] = -s[i];
      j[i][2] = _pa[i] - _pb[i];
      j[i][3] = -d * (_fa[i] - _fb[i]) / sigma;
      j[i][4] = d * (_fa[i] + _fb[i]) / (2 * sigma);
    }
  }
}

LmResult _lmFit(
  Float64List s,
  Float64List data,
  double sigma,
  List<double> p0,
  List<double> lo,
  List<double> hi,
  double maxCondition,
) {
  final model = _BoxModel(s, sigma);
  return levenbergMarquardt(
    p0: p0,
    nResiduals: s.length,
    residuals: (p, r) => model.residuals(data, p, r),
    jacobian: model.jacobian,
    lower: lo,
    upper: hi,
    maxCondition: maxCondition,
    maxIter: 80,
  );
}

/// `(2 Phi(w / 2 sigma) - 1) / w`: peak dip per unit area of a box of width w.
double _peakPerArea(double w, double sigma) => (2 * normalCdf(w / (2 * sigma)) - 1) / w;

/// Initial guess of `[B, m, D, c, w]` and the upper bound of D from a profile.
({List<double> p0, double dMax}) _initialGuess(Float64List s, Float64List v, double sigma, double wMax) {
  final n = s.length;
  // Background from the outer parts (|s| > 1.8 mm).
  final xs = <double>[], ys = <double>[];
  for (var i = 0; i < n; i++) {
    if (s[i].abs() > 1.8) {
      xs.add(s[i]);
      ys.add(v[i]);
    }
  }
  var b0 = mean(v), m0 = 0.0;
  if (xs.length >= 4) {
    final f = ols(xs, ys);
    b0 = f.a;
    m0 = f.b;
  }
  final ds = s[1] - s[0];
  // Darkness d = baseline - I inside; area and peak (3-sample running mean).
  final dk = [for (var i = 0; i < n; i++) b0 + m0 * s[i] - v[i]];
  var area = 0.0, peak = 0.0, num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    if (s[i].abs() > 1.8) continue;
    area += dk[i] * ds;
    final sm = (dk[max(0, i - 1)] + dk[i] + dk[min(n - 1, i + 1)]) / 3;
    peak = max(peak, sm);
    if (dk[i] > 0) {
      num += s[i] * dk[i];
      den += dk[i];
    }
  }
  final c0 = den > 0 ? num / den : 0.0;
  final base = max(b0 + m0 * c0, 0.05);
  var w0 = 0.2 * sigma;
  if (area > 0 && peak > 0) {
    final ratio = peak / area;
    if (ratio < _peakPerArea(1e-6, sigma) * 0.999) {
      // peakPerArea falls from its w->0 limit to 1/w: bisect for the match.
      var lo = 1e-6, hi = wMax;
      if (_peakPerArea(hi, sigma) > ratio) {
        w0 = hi;
      } else {
        for (var it = 0; it < 60; it++) {
          final mid = (lo + hi) / 2;
          if (_peakPerArea(mid, sigma) > ratio) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        w0 = (lo + hi) / 2;
      }
    }
  }
  w0 = w0.clamp(0.02 * sigma, wMax);
  final d0 = (area > 0 ? area / w0 : 0.05 * base).clamp(0.005, base);
  return (p0: [b0, m0, d0, c0.clamp(-1.5, 1.5), w0], dMax: base);
}

/// Least-squares polynomial of degree [deg] with iterative outlier rejection (3
/// robust sd). Returns coefficients `c0 + c1 x + c2 x^2`.
List<double> _robustPoly(List<double> x, List<double> y, int deg) {
  var keep = List<bool>.filled(x.length, true);
  var coef = List<double>.filled(deg + 1, 0);
  for (var iter = 0; iter < 3; iter++) {
    final xs = [for (var i = 0; i < x.length; i++) if (keep[i]) x[i]];
    final ys = [for (var i = 0; i < x.length; i++) if (keep[i]) y[i]];
    if (xs.length < deg + 2) break;
    final a = [for (var r = 0; r <= deg; r++) List<double>.filled(deg + 1, 0)];
    final b = List<double>.filled(deg + 1, 0);
    for (var i = 0; i < xs.length; i++) {
      for (var r = 0; r <= deg; r++) {
        b[r] += ys[i] * pow(xs[i], r);
        for (var c = 0; c <= deg; c++) {
          a[r][c] += pow(xs[i], r + c);
        }
      }
    }
    try {
      coef = solveLinear(a, b);
    } on SingularMatrixException {
      break;
    }
    double eval(double v) => coef.asMap().entries.fold<double>(0, (s, e) => s + e.value * pow(v, e.key));
    final res = [for (var i = 0; i < x.length; i++) y[i] - eval(x[i])];
    final sd = max(madSigma([for (var i = 0; i < x.length; i++) if (keep[i]) res[i]]), 0.005);
    keep = [for (final r in res) r.abs() <= 3 * sd];
  }
  return coef;
}

/// Two-pass profile fit around the line through [pointMm] with direction
/// [directionDeg] (5.3).
///
/// Pass 1: each of [ProfileFitConfig.profiles] profiles over the segment is fitted
/// for its own centre `c_j` and width `w_j`. Pass 2: profiles are re-sampled aligned
/// on the centre line and averaged (parallel average), and the mean profile is
/// fitted once for the final width, centre and covariance `rho * s2 (J^T J)^-1`.
/// [sigmaMm] is the fixed kernel sigma (psf.dart) and [uSigmaMm] its uncertainty
/// (the width is refitted at `sigma +- u`). [noiseFloor] is the pixel noise sd of the
/// whole patch: the gate's noise is at least that.
///
/// Throws [MeasurementException] ([RejectReason.patchTooSmall]) if any profile leaves
/// the patch.
ProfileFitResult fitCrackWidth({
  required GrayPatch patch,
  required Mat3 h,
  required Pt pointMm,
  required double directionDeg,
  required double sigmaMm,
  double uSigmaMm = 0,
  double noiseFloor = 0,
  ProfileFitConfig config = const ProfileFitConfig(),
}) {
  final a = directionDeg * pi / 180;
  final normal = Pt(-sin(a), cos(a));
  final step = profileStepMm(directionalMmPerPx(h, pointMm, normal));
  final nProf = config.profiles;
  final alongs = [for (var j = 0; j < nProf; j++) -config.segmentMm / 2 + config.segmentMm * (j + 0.5) / nProf];

  MetricProfile sample(double along, double offset) {
    final p = sampleProfile(
      patch: patch,
      h: h,
      centerMm: pointMm,
      directionDeg: directionDeg,
      halfRangeMm: config.halfRangeMm,
      stepMm: step,
      alongMm: along,
      offsetMm: offset,
    );
    if (p == null) {
      throw const MeasurementException(
        RejectReason.patchTooSmall,
        'Potongan citra terlalu kecil untuk profil retak. Ambil ulang dengan titik ukur lebih di tengah.',
      );
    }
    return p;
  }

  // ---- Pass 1: per-profile fits.
  final first = sample(alongs[0], 0);
  final n = first.n;
  final sGrid = Float64List.fromList([for (var i = 0; i < n; i++) first.sAt(i)]);
  final centers = <double?>[];
  final widths = <double?>[];
  final rmsList = <double>[];
  for (final along in alongs) {
    final prof = along == alongs[0] ? first : sample(along, 0);
    final g = _initialGuess(sGrid, prof.values, sigmaMm, config.maxWidthMm);
    final res = _lmFit(
      sGrid,
      prof.values,
      sigmaMm,
      g.p0,
      [-1, -5, 0, -1.5, 0],
      [2, 5, g.dMax, 1.5, config.maxWidthMm],
      config.maxCondition,
    );
    final goodC = res.converged && !res.atLower[3] && !res.atUpper[3] && res.params[2] > 1e-3;
    final goodW = goodC && !res.atLower[4] && !res.atUpper[4] && !res.atUpper[2] && !res.unstable;
    centers.add(goodC ? res.params[3] : null);
    widths.add(goodW ? res.params[4] : null);
    if (res.converged && res.dof > 0) rmsList.add(sqrt(res.rss / res.dof));
  }

  // ---- Alignment curve.
  final cIdx = [for (var j = 0; j < nProf; j++) if (centers[j] != null) j];
  var poly = <double>[0, 0, 0];
  var fallback = false;
  var centerSd = double.nan;
  if (cIdx.length >= 8) {
    poly = _robustPoly([for (final j in cIdx) alongs[j]], [for (final j in cIdx) centers[j]!], 2);
  } else if (cIdx.length >= 4) {
    poly = [..._robustPoly([for (final j in cIdx) alongs[j]], [for (final j in cIdx) centers[j]!], 1), 0.0];
  } else {
    fallback = true;
  }
  double polyAt(double x) => poly[0] + poly[1] * x + poly[2] * x * x;
  if (!fallback) {
    centerSd = sampleSd([for (final j in cIdx) centers[j]! - polyAt(alongs[j])]);
  }
  final align = [
    for (var j = 0; j < nProf; j++)
      (!config.alignWithSmoothedCenters && centers[j] != null) ? centers[j]! : polyAt(alongs[j]),
  ];

  // ---- Pass 2: aligned parallel average.
  final avg = Float64List(n);
  for (var j = 0; j < nProf; j++) {
    final p = sample(alongs[j], align[j]);
    for (var i = 0; i < n; i++) {
      avg[i] += p.values[i] / nProf;
    }
  }
  final uGrid = Float64List.fromList([for (var i = 0; i < n; i++) first.sAt(i)]);
  final g2 = _initialGuess(uGrid, avg, sigmaMm, config.maxWidthMm);
  final lo2 = <double>[-1, -5, 0, -1.5, 0], hi2 = <double>[2, 5, g2.dMax, 1.5, config.maxWidthMm];
  var res = _lmFit(uGrid, avg, sigmaMm, g2.p0, lo2, hi2, config.maxCondition);
  if (!res.converged) {
    // Second attempt from a different, narrow start.
    final alt = List<double>.of(g2.p0)
      ..[4] = 0.5 * sigmaMm
      ..[2] = g2.p0[2].clamp(0.01, g2.dMax);
    final retry = _lmFit(uGrid, avg, sigmaMm, alt, lo2, hi2, config.maxCondition);
    if (retry.converged || retry.rss < res.rss) res = retry;
  }

  final p = res.params;
  final width = p[4];
  final cov = res.covariance;
  final varW = cov == null ? double.infinity : cov[4][4];
  final uRaw = cov == null ? double.infinity : sqrt(max(varW, 0));
  final u = cov == null ? double.infinity : sqrt(max(config.rho * varW, 0));
  final dip = p[2] * (2 * normalCdf(width / (2 * sigmaMm)) - 1);
  final noiseRaw = rmsList.isEmpty ? 0.0 : median(rmsList);
  final noise = max(noiseRaw, noiseFloor);
  final snr = noise > 0 ? dip / noise : (dip > 0 ? double.infinity : 0.0);
  FitIssue? issue;
  if (!res.converged) {
    issue = FitIssue.fitFailed;
  } else if (res.unstable || cov == null) {
    issue = FitIssue.unstableFit;
  } else if (snr < config.minContrastSnr) {
    issue = FitIssue.lowContrast;
  }

  // ---- Width statistics along the crack.
  final gw = [for (var j = 0; j < nProf; j++) if (widths[j] != null) j];
  var alongSd = double.nan, dwDs = double.nan, dwDsSe = double.nan, wMed = double.nan;
  if (gw.length >= 8) {
    final wv = [for (final j in gw) widths[j]!];
    wMed = median(wv);
    alongSd = sampleSd(wv);
    final f = ols([for (final j in gw) alongs[j]], wv);
    dwDs = f.b;
    dwDsSe = f.seB;
  }

  // ---- Propagation of the sigma uncertainty.
  var uSigmaW = 0.0;
  if (uSigmaMm > 0 && res.converged) {
    double wAt(double sg) {
      final r = _lmFit(uGrid, avg, sg, p, lo2, hi2, config.maxCondition);
      return r.params[4];
    }

    uSigmaW = (wAt(sigmaMm + uSigmaMm) - wAt(max(sigmaMm - uSigmaMm, 0.02 * sigmaMm))).abs() / 2;
  }

  final expectedNoise = noiseRaw / sqrt(nProf);
  final rms2 = res.dof > 0 ? sqrt(res.rss / res.dof) : double.nan;
  final systematic = sqrt(max(0.0, rms2 * rms2 - expectedNoise * expectedNoise));
  return ProfileFitResult(
    status: issue == null ? FitStatus.terukur : FitStatus.tidakTerukur,
    issue: issue,
    widthMm: width,
    uWidthMm: u,
    uWidthRawMm: uRaw,
    rho: config.rho,
    rhoCalibrated: config.rhoCalibrated,
    params: p,
    covariance: cov == null
        ? null
        : [
            for (final row in cov) [for (final v in row) v * config.rho],
          ],
    centerOffsetMm: polyAt(0) + p[3],
    centerSlope: poly[1],
    centerSdMm: centerSd,
    residualRms: res.dof > 0 ? sqrt(res.rss / res.dof) : double.nan,
    sigmaNoise: noise,
    dipDepth: dip,
    contrastSnr: snr,
    widthsPerProfile: widths,
    wMedian: wMed,
    alongSdMm: alongSd,
    dwDs: dwDs,
    dwDsSe: dwDsSe,
    goodProfiles: gw.length,
    conditionNumber: res.conditionNumber,
    boundsActive: [
      for (var i = 0; i < 5; i++)
        if (res.atLower[i] || res.atUpper[i]) _paramNames[i],
    ],
    misfitRatio: expectedNoise > 0 && res.dof > 0 ? rms2 / expectedNoise : double.nan,
    misfitRel: dip > 0 ? systematic / dip : double.nan,
    uSigmaWMm: uSigmaW,
    sigmaMm: sigmaMm,
    alignmentFallback: fallback,
  );
}
