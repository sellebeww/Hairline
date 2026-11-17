// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalCdf matches tabulated values to 1e-14', () {
    // Reference values from standard normal tables (15 significant digits).
    final ref = {
      0.0: 0.5,
      1.0: 0.841344746068543,
      2.0: 0.977249868051821,
      3.0: 0.998650101968370,
      1.96: 0.975002104851780,
      -3.0: 0.00134989803163009,
    };
    ref.forEach((z, v) => expect(normalCdf(z), closeTo(v, 1e-14), reason: 'z=$z'));
  });

  test('symmetry, monotonicity, limits, NaN', () {
    var prev = -1.0;
    for (var z = -9.0; z <= 9.0; z += 0.05) {
      final v = normalCdf(z);
      expect(v + normalCdf(-z), closeTo(1, 1e-15));
      expect(v, greaterThanOrEqualTo(prev - 1e-15)); // rounding noise of 1-erf in the tails
      prev = v;
    }
    expect(normalCdf(40), 1.0);
    expect(normalCdf(-40), 0.0);
    expect(normalCdf(double.nan), isNaN);
  });

  test('normalPdf is the derivative of normalCdf', () {
    for (final z in [-2.5, -0.3, 0.0, 1.1, 3.2]) {
      const h = 1e-5;
      final num = (normalCdf(z + h) - normalCdf(z - h)) / (2 * h);
      expect(normalPdf(z), closeTo(num, 1e-9));
    }
    expect(normalPdf(0), closeTo(1 / sqrt(2 * pi), 1e-16));
  });
}
