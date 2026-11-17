// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'stats.dart';

/// One plate line measured by the app, compared with its known truth.
final class PlateMeasurement {
  const PlateMeasurement({
    required this.lineId,
    required this.truthMm,
    required this.uTruthMm,
    required this.measuredMm,
    required this.uCMm,
    required this.k,
  });

  final String lineId;

  /// Certified width of the line (mm) and its standard uncertainty `u_truth`.
  final double truthMm;
  final double uTruthMm;

  /// Visit width reported by the app (mm); null when no number was reported (below
  /// the limit or not measurable).
  final double? measuredMm;

  /// Combined standard uncertainty `u_c` of the visit and its coverage factor.
  final double uCMm;
  final double k;

  bool get reported => measuredMm != null;

  /// `measured - truth` (mm); NaN when nothing was reported.
  double get errorMm => measuredMm == null ? double.nan : measuredMm! - truthMm;

  /// Expanded uncertainty of the comparison, `k sqrt(u_c^2 + u_truth^2)`.
  double get uCombinedMm => k * sqrt(uCMm * uCMm + uTruthMm * uTruthMm);

  bool get covered => reported && errorMm.abs() <= uCombinedMm;
}

/// Statistics of the lines of one truth width.
final class WidthGroupStats {
  const WidthGroupStats({
    required this.truthMm,
    required this.n,
    required this.reported,
    required this.biasMm,
    required this.rmseMm,
    required this.sdMm,
    required this.coverage,
    required this.uExpandedMedianMm,
    required this.reliable,
  });

  final double truthMm;
  final int n;
  final int reported;

  /// Mean of `measured - truth` over reported lines (NaN if none).
  final double biasMm;
  final double rmseMm;
  final double sdMm;

  /// Fraction of reported lines with `|error| <= U_combined`.
  final double coverage;
  final double uExpandedMedianMm;

  /// At least 90 percent reported, coverage at least 90 percent, and the median
  /// combined uncertainty smaller than the width (a number whose uncertainty exceeds
  /// itself says nothing).
  final bool reliable;
}

/// Plate statistics (5.5 `u_dev`, 5.6 trust, `validation_runs` in 5.7).
final class PlateStats {
  const PlateStats({
    required this.n,
    required this.reported,
    required this.biasMm,
    required this.rmseMm,
    required this.coverage,
    required this.lowerLimitMm,
    required this.groups,
  });

  final int n;
  final int reported;

  /// Mean error over all reported lines, RMSE over all reported lines, coverage
  /// (fraction covered by the combined uncertainty).
  final double biasMm;
  final double rmseMm;
  final double coverage;

  /// Empirical lower reporting limit: the smallest tested width such that it and every
  /// larger tested width are reliable; null if even the largest is not.
  final double? lowerLimitMm;

  /// Ordered by truth width.
  final List<WidthGroupStats> groups;

  /// Stable JSON; NaN is written as null.
  Map<String, Object?> toJson() {
    Object? f(double v) => v.isFinite ? v : null;
    return {
      'n': n,
      'reported': reported,
      'bias_mm': f(biasMm),
      'rmse_mm': f(rmseMm),
      'coverage': f(coverage),
      'lower_limit_mm': lowerLimitMm,
      'groups': [
        for (final g in groups)
          {
            'truth_mm': g.truthMm,
            'n': g.n,
            'reported': g.reported,
            'bias_mm': f(g.biasMm),
            'rmse_mm': f(g.rmseMm),
            'sd_mm': f(g.sdMm),
            'coverage': f(g.coverage),
            'u_expanded_median_mm': f(g.uExpandedMedianMm),
            'reliable': g.reliable,
          },
      ],
    };
  }
}

/// Statistics of a plate run: per line `error = measured - truth`, bias and RMSE per
/// width and overall, coverage of the combined uncertainty `k sqrt(u_c^2 + u_truth^2)`,
/// and the empirical lower reporting limit. Lines of equal truth width (to 1 nm) form a group.
PlateStats computePlateStats(List<PlateMeasurement> lines) {
  if (lines.isEmpty) throw ArgumentError('a plate run needs at least one line');
  for (final l in lines) {
    final m = l.measuredMm;
    if (!(l.truthMm > 0) || !l.truthMm.isFinite || !(l.uTruthMm >= 0) || !(l.uCMm >= 0) || !(l.k > 0) || (m != null && !m.isFinite)) {
      throw ArgumentError('invalid plate line ${l.lineId}');
    }
  }
  final byWidth = <int, List<PlateMeasurement>>{};
  for (final l in lines) {
    byWidth.putIfAbsent((l.truthMm * 1e6).round(), () => []).add(l);
  }
  final groups = <WidthGroupStats>[];
  for (final key in byWidth.keys.toList()..sort()) {
    final ls = byWidth[key]!;
    final rep = [for (final l in ls) if (l.reported) l];
    final err = [for (final l in rep) l.errorMm];
    final cov = rep.isEmpty ? double.nan : rep.where((l) => l.covered).length / rep.length;
    final u = median(ls.map((l) => l.uCombinedMm));
    final truth = ls.first.truthMm;
    groups.add(WidthGroupStats(
      truthMm: truth,
      n: ls.length,
      reported: rep.length,
      biasMm: err.isEmpty ? double.nan : mean(err),
      rmseMm: err.isEmpty ? double.nan : sqrt(mean(err.map((e) => e * e))),
      sdMm: sampleSd(err),
      coverage: cov,
      uExpandedMedianMm: u,
      reliable: rep.length >= 0.9 * ls.length && cov >= 0.9 && u < truth,
    ));
  }
  double? limit;
  for (var i = groups.length - 1; i >= 0 && groups[i].reliable; i--) {
    limit = groups[i].truthMm;
  }
  final rep = [for (final l in lines) if (l.reported) l];
  final err = [for (final l in rep) l.errorMm];
  return PlateStats(
    n: lines.length,
    reported: rep.length,
    biasMm: err.isEmpty ? double.nan : mean(err),
    rmseMm: err.isEmpty ? double.nan : sqrt(mean(err.map((e) => e * e))),
    coverage: rep.isEmpty ? double.nan : rep.where((l) => l.covered).length / rep.length,
    lowerLimitMm: limit,
    groups: groups,
  );
}

/// `u_dev` for the 5.5 budget from plate statistics: the RMS of the per-width biases of
/// the tested widths within a factor [ratio] of [widthMm] (default 2: 0.5 to 2 times).
/// Null when no tested width is comparable (the unvalidated default then stays in force).
({double uDevMm, int groups})? deriveUDev(PlateStats stats, double widthMm, {double ratio = 2}) {
  final b = [
    for (final g in stats.groups)
      if (g.biasMm.isFinite && g.truthMm >= widthMm / ratio - 1e-12 && g.truthMm <= widthMm * ratio + 1e-12) g.biasMm,
  ];
  if (b.isEmpty) return null;
  return (uDevMm: sqrt(mean(b.map((x) => x * x))), groups: b.length);
}
