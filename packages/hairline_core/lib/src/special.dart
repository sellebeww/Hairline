// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

const double _sqrt2 = 1.4142135623730951;
const double _twoOverSqrtPi = 1.1283791670955126;
const double _invSqrt2Pi = 0.3989422804014327;

/// Standard normal probability density.
double normalPdf(double z) => _invSqrt2Pi * exp(-0.5 * z * z);

/// Standard normal CDF, accurate to about 1e-16 absolute.
///
/// Uses `erf(x) = 2/sqrt(pi) e^(-x^2) sum_n 2^n x^(2n+1) / (2n+1)!!`, a series with
/// all positive terms (no cancellation), which converges for every x. Beyond
/// |x| = 6 (|z| > 8.5) the result is 0 or 1 to double precision.
double normalCdf(double z) {
  if (z.isNaN) return double.nan;
  final x = z.abs() / _sqrt2;
  if (x > 6) return z > 0 ? 1.0 : 0.0;
  final x2 = x * x;
  var term = x, sum = x;
  for (var n = 0; n < 200; n++) {
    term *= 2 * x2 / (2 * n + 3);
    sum += term;
    if (term < 1e-17 * sum) break;
  }
  final erf = _twoOverSqrtPi * exp(-x2) * sum;
  return z >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
}
