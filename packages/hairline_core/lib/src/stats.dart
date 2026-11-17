// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

/// Median (mean of the two middle values for an even count). Throws on empty input.
double median(Iterable<double> values) {
  final v = values.toList()..sort();
  if (v.isEmpty) throw ArgumentError('median of an empty list');
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

double mean(Iterable<double> values) {
  var s = 0.0, n = 0;
  for (final x in values) {
    s += x;
    n++;
  }
  if (n == 0) throw ArgumentError('mean of an empty list');
  return s / n;
}

/// Sample standard deviation (n - 1); 0 for fewer than two values.
double sampleSd(Iterable<double> values) {
  final v = values.toList();
  if (v.length < 2) return 0;
  final m = mean(v);
  var s = 0.0;
  for (final x in v) {
    s += (x - m) * (x - m);
  }
  return sqrt(s / (v.length - 1));
}

/// Median absolute deviation scaled to a normal standard deviation (x 1.4826).
double madSigma(Iterable<double> values) {
  final v = values.toList();
  final m = median(v);
  return 1.4826 * median([for (final x in v) (x - m).abs()]);
}

/// Ordinary least squares `y = a + b x`; returns intercept, slope and the standard
/// error of the slope (NaN for fewer than 3 points or no spread in x).
({double a, double b, double seB}) ols(List<double> x, List<double> y) {
  final n = x.length;
  if (n != y.length || n < 2) throw ArgumentError('ols needs >= 2 matching points');
  final mx = mean(x), my = mean(y);
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (x[i] - mx) * (x[i] - mx);
    sxy += (x[i] - mx) * (y[i] - my);
  }
  if (sxx == 0) return (a: my, b: 0, seB: double.nan);
  final b = sxy / sxx, a = my - b * mx;
  var rss = 0.0;
  for (var i = 0; i < n; i++) {
    final r = y[i] - (a + b * x[i]);
    rss += r * r;
  }
  return (a: a, b: b, seB: n < 3 ? double.nan : sqrt(rss / (n - 2) / sxx));
}

/// Wilson score interval for a binomial proportion ([successes] of [n]) at 95 percent
/// (z = 1.96). Unlike the normal approximation it stays inside 0..1 and is informative
/// at 0 and n; n = 0 gives (0, 1).
({double lower, double upper}) wilsonInterval(int successes, int n, {double z = 1.959964}) {
  if (successes < 0 || successes > n) throw ArgumentError('successes must be in 0..n');
  if (n == 0) return (lower: 0.0, upper: 1.0);
  final p = successes / n, z2 = z * z;
  final denom = 1 + z2 / n;
  final centre = (p + z2 / (2 * n)) / denom;
  final half = z * sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / denom;
  return (lower: max(0.0, centre - half), upper: min(1.0, centre + half));
}
