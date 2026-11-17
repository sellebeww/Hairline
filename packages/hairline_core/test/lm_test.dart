// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

/// Linear regression y = a + b x as an LM problem.
LmResult fitLine(List<double> xs, List<double> ys, {List<double>? lower, List<double>? upper, int maxIter = 100}) {
  return levenbergMarquardt(
    p0: [0, 0],
    nResiduals: xs.length,
    residuals: (p, r) {
      for (var i = 0; i < xs.length; i++) {
        r[i] = ys[i] - (p[0] + p[1] * xs[i]);
      }
    },
    lower: lower,
    upper: upper,
    maxIter: maxIter,
  );
}

void main() {
  group('linear problem has a closed form', () {
    final xs = [for (var i = 0; i < 20; i++) i / 19.0];
    final rng = Random(11);
    final ys = [for (final x in xs) 2 + 3 * x + 0.05 * (rng.nextDouble() - 0.5)];

    test('parameters equal the OLS solution', () {
      final res = fitLine(xs, ys);
      // OLS by hand.
      final n = xs.length;
      final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
      var sxy = 0.0, sxx = 0.0;
      for (var i = 0; i < n; i++) {
        sxy += (xs[i] - mx) * (ys[i] - my);
        sxx += (xs[i] - mx) * (xs[i] - mx);
      }
      final b = sxy / sxx, a = my - b * mx;
      // Quadratic problem: LM converges to the optimum to solver tolerance (1e-9).
      expect(res.converged, isTrue);
      expect(res.params[0], closeTo(a, 1e-9));
      expect(res.params[1], closeTo(b, 1e-9));
    });

    test('covariance equals s2 (X^T X)^-1', () {
      final res = fitLine(xs, ys);
      final n = xs.length;
      final sx = xs.reduce((a, b) => a + b), sxx = xs.map((x) => x * x).reduce((a, b) => a + b);
      final det = n * sxx - sx * sx;
      final s2 = res.s2;
      expect(res.dof, n - 2);
      expect(s2, closeTo(res.rss / (n - 2), 1e-15));
      expect(res.covariance![0][0], closeTo(s2 * sxx / det, 1e-12));
      expect(res.covariance![1][1], closeTo(s2 * n / det, 1e-12));
      expect(res.covariance![0][1], closeTo(-s2 * sx / det, 1e-12));
      expect(res.stdErr(1), closeTo(sqrt(s2 * n / det), 1e-12));
    });

    test('reported condition number matches the analytic value (1+|rho|)/(1-|rho|)', () {
      final res = fitLine(xs, ys);
      final n = xs.length;
      final sx = xs.reduce((a, b) => a + b), sxx = xs.map((x) => x * x).reduce((a, b) => a + b);
      final rho = (sx / sqrt(n * sxx)).abs(); // correlation of the two columns [1, x]
      expect(res.conditionNumber, closeTo((1 + rho) / (1 - rho), 1e-6 * (1 + rho) / (1 - rho)));
      expect(res.unstable, isFalse);
    });
  });

  test('nonlinear exponential decay is recovered, numeric and analytic Jacobian agree', () {
    final xs = [for (var i = 0; i < 40; i++) i * 0.1];
    final ys = [for (final x in xs) 3.0 * exp(-0.7 * x) + 0.5];
    void res(List<double> p, List<double> r) {
      for (var i = 0; i < xs.length; i++) {
        r[i] = ys[i] - (p[0] * exp(-p[1] * xs[i]) + p[2]);
      }
    }

    final numeric = levenbergMarquardt(p0: [1, 0.3, 0], nResiduals: xs.length, residuals: res);
    final analytic = levenbergMarquardt(
      p0: [1, 0.3, 0],
      nResiduals: xs.length,
      residuals: res,
      jacobian: (p, j) {
        for (var i = 0; i < xs.length; i++) {
          final e = exp(-p[1] * xs[i]);
          j[i][0] = -e; // d r / d p, r = y - model
          j[i][1] = p[0] * xs[i] * e;
          j[i][2] = -1;
        }
      },
    );
    for (final r in [numeric, analytic]) {
      expect(r.converged, isTrue);
      // Noise-free: the minimum is exact; tolerance is the solver tolerance.
      expect(r.params[0], closeTo(3.0, 1e-6));
      expect(r.params[1], closeTo(0.7, 1e-6));
      expect(r.params[2], closeTo(0.5, 1e-6));
      expect(r.rss, lessThan(1e-12));
    }
  });

  group('bounds', () {
    final xs = [for (var i = 0; i < 10; i++) i.toDouble()];
    final ys = [for (final x in xs) 1 + 2 * x];
    test('active upper bound is reported and respected', () {
      final res = fitLine(xs, ys, upper: [double.infinity, 1.0]);
      expect(res.params[1], 1.0);
      expect(res.atUpper, [false, true]);
      expect(res.atLower, [false, false]);
      expect(res.converged, isTrue);
    });
    test('active lower bound is reported and respected', () {
      final res = fitLine(xs, ys, lower: [3.0, double.negativeInfinity]);
      expect(res.params[0], 3.0);
      expect(res.atLower, [true, false]);
    });
    test('start outside the bounds is projected inside', () {
      final res = levenbergMarquardt(
        p0: [10, 10],
        nResiduals: xs.length,
        residuals: (p, r) {
          for (var i = 0; i < xs.length; i++) {
            r[i] = ys[i] - (p[0] + p[1] * xs[i]);
          }
        },
        lower: [0, 0],
        upper: [2, 2],
      );
      expect(res.params[0], inInclusiveRange(0, 2));
      expect(res.params[1], inInclusiveRange(0, 2));
    });
  });

  group('failure detection', () {
    test('iteration budget exhausted is reported as not converged', () {
      final xs = [for (var i = 0; i < 40; i++) i * 0.1];
      final res = levenbergMarquardt(
        p0: [0.1, 5, 0],
        nResiduals: xs.length,
        maxIter: 1,
        residuals: (p, r) {
          for (var i = 0; i < xs.length; i++) {
            r[i] = 3 * exp(-0.7 * xs[i]) + 0.5 - (p[0] * exp(-p[1] * xs[i]) + p[2]);
          }
        },
      );
      expect(res.converged, isFalse);
      expect(res.stop, LmStop.maxIterations);
    });

    test('non-finite residuals at the start are reported', () {
      final res = levenbergMarquardt(
        p0: [1],
        nResiduals: 3,
        residuals: (p, r) {
          r.fillRange(0, 3, double.nan);
        },
      );
      expect(res.converged, isFalse);
      expect(res.stop, LmStop.nonFinite);
      expect(res.covariance, isNull);
    });

    test('a duplicated parameter (singular J^T J) is unstable with no covariance', () {
      final xs = [for (var i = 0; i < 10; i++) i.toDouble()];
      final res = levenbergMarquardt(
        p0: [0, 0, 0],
        nResiduals: xs.length,
        residuals: (p, r) {
          for (var i = 0; i < xs.length; i++) {
            r[i] = 4 + 0.001 * xs[i] * xs[i] - (p[0] + p[1] + p[2] * xs[i]);
          }
        },
      );
      expect(res.unstable, isTrue);
      expect(res.covariance, isNull);
      expect(res.stdErr(0), isNaN);
    });

    test('nearly collinear columns are flagged unstable above maxCondition', () {
      // x in [100, 100.01]: columns [1, x] differ by ~1e-4 relative: cond ~ 1e8.
      final xs = [for (var i = 0; i < 30; i++) 100 + i * 0.01 / 29];
      final ys = [for (final x in xs) 1 + 0.5 * x];
      final loose = levenbergMarquardt(
        p0: [0, 0],
        nResiduals: xs.length,
        residuals: (p, r) {
          for (var i = 0; i < xs.length; i++) {
            r[i] = ys[i] - (p[0] + p[1] * xs[i]);
          }
        },
        maxCondition: 1e6,
      );
      expect(loose.conditionNumber, greaterThan(1e6));
      expect(loose.unstable, isTrue);
    });

    test('no degrees of freedom: no covariance', () {
      final res = fitLine([0, 1], [1, 3]);
      expect(res.dof, 0);
      expect(res.covariance, isNull);
    });

    test('fewer residuals than parameters is a programming error', () {
      expect(() => fitLine([1], [1]), throwsArgumentError);
    });

    test('inconsistent bounds length is a programming error', () {
      expect(() => fitLine([0, 1, 2], [1, 2, 3], lower: [0]), throwsArgumentError);
    });
  });

  test('the solver is deterministic', () {
    final xs = [for (var i = 0; i < 20; i++) i / 19.0];
    final ys = [for (final x in xs) sin(3 * x)];
    final a = fitLine(xs, ys), b = fitLine(xs, ys);
    expect(a.params, b.params);
    expect(a.rss, b.rss);
  });
}
