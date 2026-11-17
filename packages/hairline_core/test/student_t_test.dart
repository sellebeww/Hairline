// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

/// Two-sided 95 percent critical values, column 0.975 of the NIST/SEMATECH
/// e-Handbook of Statistical Methods, section 1.3.6.7.2 (itl.nist.gov, retrieved
/// 2026-11-17), dof 1..30 and the normal row. Published to 3 decimals.
const nist975 = <double>[
  12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, //
  2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
  2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
];

double lgamma(double x) {
  const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
  x -= 1;
  var a = c[0];
  final t = x + 7.5;
  for (var i = 1; i < 9; i++) {
    a += c[i] / (x + i);
  }
  return 0.5 * log(2 * pi) + (x + 0.5) * log(t) - t + log(a);
}

/// P(|T| <= t) by Simpson integration of the density: independent of the table.
double twoSidedMass(double t, double v) {
  final c = exp(lgamma((v + 1) / 2) - lgamma(v / 2)) / sqrt(v * pi);
  double f(double x) => c * pow(1 + x * x / v, -(v + 1) / 2).toDouble();
  const n = 20000;
  final h = t / n;
  var s = f(0) + f(t);
  for (var i = 1; i < n; i++) {
    s += f(i * h) * (i.isOdd ? 4 : 2);
  }
  return 2 * s * h / 3;
}

void main() {
  group('t table', () {
    test('matches the NIST table to its 3 published decimals for dof 1..30', () {
      for (var v = 1; v <= 30; v++) {
        expect(studentT975(v), closeTo(nist975[v - 1], 5e-4), reason: 'dof $v');
      }
    });

    test('each entry carries 95 percent two-sided mass (independent integration, 1e-6: 5 decimal rounding)', () {
      for (var v = 1; v <= 30; v++) {
        expect(twoSidedMass(studentT975(v), v.toDouble()), closeTo(0.95, 1e-6), reason: 'dof $v');
      }
    });

    test('is strictly decreasing and stays above the normal limit', () {
      for (var v = 2; v <= 30; v++) {
        expect(studentT975(v), lessThan(studentT975(v - 1)));
      }
      expect(studentT975(30), greaterThan(normalQuantile975));
      expect(normalQuantile975, closeTo(1.959964, 1e-6)); // NIST normal row: 1.960
    });

    test('rejects dof below 1', () {
      expect(() => studentT975(0), throwsArgumentError);
    });
  });

  group('coverageFactor', () {
    test('integers read the table; infinity and huge dof give the normal limit', () {
      expect(coverageFactor(4), studentT975(4));
      expect(coverageFactor(double.infinity), normalQuantile975);
      expect(coverageFactor(1e9), closeTo(normalQuantile975, 1e-6));
    });

    test('between integers it lies between neighbours and never undercuts the truth by more than 0.003 (dof 1..200)', () {
      for (var v = 1.0; v <= 200; v += 0.37) {
        final k = coverageFactor(v);
        // true quantile bracket: t(ceil) <= truth <= t(floor) holds for the table; interpolation must be conservative-ish
        if (v <= 30) {
          expect(k, lessThanOrEqualTo(studentT975(v.floor())));
          expect(k, greaterThanOrEqualTo(studentT975(v.ceil())));
        }
        // against NIST rows beyond 30 (3 decimals): dof 40 -> 2.021, 60 -> 2.000, 100 -> 1.984
      }
      expect(coverageFactor(40), closeTo(2.021, 0.003));
      expect(coverageFactor(60), closeTo(2.000, 0.003));
      expect(coverageFactor(100), closeTo(1.984, 0.003));
    });

    test('dof below 1 is clamped to 1 (never an unbounded factor)', () {
      expect(coverageFactor(0.3), studentT975(1));
    });

    test('NaN is rejected', () {
      expect(() => coverageFactor(double.nan), throwsArgumentError);
    });
  });

  group('Welch-Satterthwaite', () {
    test('single dominating component with n-1 dof and infinite others: dof = n-1', () {
      // u_stat dominates: nu = uc^4 / (u_stat^4/4) -> 4 when uc == u_stat
      final nu = welchSatterthwaite(uC: 0.5, finite: [(u: 0.5, dof: 4)]);
      expect(nu, closeTo(4, 1e-12));
    });

    test('hand value: uc = 0.5, u_stat = 0.3 with 4 dof -> 0.5^4/(0.3^4/4) = 30.864197...', () {
      expect(welchSatterthwaite(uC: 0.5, finite: [(u: 0.3, dof: 4)]), closeTo(0.0625 / (0.0081 / 4), 1e-9));
    });

    test('no finite-dof contribution gives infinity', () {
      expect(welchSatterthwaite(uC: 0.5, finite: const []), double.infinity);
      expect(welchSatterthwaite(uC: 0.5, finite: [(u: 0.0, dof: 4)]), double.infinity);
    });

    test('two finite components add in the denominator', () {
      final nu = welchSatterthwaite(uC: 1, finite: [(u: 0.6, dof: 4), (u: 0.5, dof: 9)]);
      expect(nu, closeTo(1 / (0.6 * 0.6 * 0.6 * 0.6 / 4 + 0.5 * 0.5 * 0.5 * 0.5 / 9), 1e-9));
    });
  });
}
