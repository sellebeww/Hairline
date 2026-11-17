// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'linalg_small.dart';

/// Why [levenbergMarquardt] stopped.
enum LmStop {
  /// Step, cost decrease or projected gradient fell below tolerance.
  converged,

  /// Iteration budget used up before any convergence test passed.
  maxIterations,

  /// Residuals or Jacobian were not finite at the start or damping could not
  /// find a finite, lower-cost step.
  nonFinite,

  /// Damping grew past its limit without finding a lower-cost step.
  noProgress,
}

/// Result of [levenbergMarquardt]. Residual convention: `r = data - model`.
final class LmResult {
  const LmResult({
    required this.params,
    required this.rss,
    required this.iterations,
    required this.stop,
    required this.covariance,
    required this.s2,
    required this.dof,
    required this.conditionNumber,
    required this.unstable,
    required this.atLower,
    required this.atUpper,
  });

  final List<double> params;

  /// Residual sum of squares at [params].
  final double rss;
  final int iterations;
  final LmStop stop;

  /// `s2 (J^T J)^-1`, or null when `J^T J` is singular, not finite, or `dof <= 0`.
  /// Computed from the full Jacobian (bound-active parameters included), so it is a
  /// conservative, unconstrained local estimate.
  final List<List<double>>? covariance;

  /// `RSS / (n - p)`; NaN when `dof <= 0`.
  final double s2;
  final int dof;

  /// Condition number of the correlation-scaled `J^T J` (ratio of extreme
  /// eigenvalues); infinity when singular or not finite. Independent of the
  /// parameter units.
  final double conditionNumber;

  /// Singular, not finite, or [conditionNumber] above the `maxCondition` given.
  final bool unstable;
  final List<bool> atLower;
  final List<bool> atUpper;

  bool get converged => stop == LmStop.converged;

  /// Standard error of parameter [i]; NaN when there is no covariance.
  double stdErr(int i) {
    final c = covariance;
    if (c == null) return double.nan;
    final v = c[i][i];
    return v < 0 ? double.nan : sqrt(v);
  }
}

/// Bounded Levenberg-Marquardt for `min sum r(p)^2`, no external dependencies.
///
/// [residuals] fills `r = data - model(p)` ([nResiduals] entries). [jacobian]
/// (optional) fills `j[i][k] = d r_i / d p_k`; without it a central difference is
/// used (one-sided at a bound). Marquardt scaling of the damping by `diag(J^T J)`;
/// bounds are handled by projection with an active set (a parameter at a bound
/// whose gradient pushes it outwards is frozen for that step).
///
/// Failure is reported, never thrown: [LmResult.stop], [LmResult.unstable].
/// Argument errors (fewer residuals than parameters, wrong bound length) throw.
LmResult levenbergMarquardt({
  required List<double> p0,
  required int nResiduals,
  required void Function(List<double> p, List<double> r) residuals,
  void Function(List<double> p, List<List<double>> j)? jacobian,
  List<double>? lower,
  List<double>? upper,
  int maxIter = 100,
  double tolStep = 1e-10,
  double tolCost = 1e-13,
  double maxCondition = 1e12,
}) {
  final k = p0.length;
  final n = nResiduals;
  if (n < k) throw ArgumentError('LM needs at least as many residuals ($n) as parameters ($k)');
  if ((lower != null && lower.length != k) || (upper != null && upper.length != k)) {
    throw ArgumentError('bounds must have one entry per parameter');
  }
  final lo = lower ?? List<double>.filled(k, double.negativeInfinity);
  final hi = upper ?? List<double>.filled(k, double.infinity);

  var p = [for (var i = 0; i < k; i++) p0[i].clamp(lo[i], hi[i]).toDouble()];
  final r = List<double>.filled(n, 0);
  final rTrial = List<double>.filled(n, 0);
  final jac = [for (var i = 0; i < n; i++) List<double>.filled(k, 0)];

  double rssOf(List<double> res) {
    var s = 0.0;
    for (final v in res) {
      s += v * v;
    }
    return s;
  }

  void evalJac(List<double> q) {
    if (jacobian != null) {
      jacobian(q, jac);
      return;
    }
    final rp = List<double>.filled(n, 0), rm = List<double>.filled(n, 0);
    for (var c = 0; c < k; c++) {
      final h = 1e-6 * max(q[c].abs(), 1e-2);
      final up = min(q[c] + h, hi[c]), dn = max(q[c] - h, lo[c]);
      final qp = List<double>.of(q)..[c] = up;
      final qm = List<double>.of(q)..[c] = dn;
      residuals(qp, rp);
      residuals(qm, rm);
      final span = up - dn;
      for (var i = 0; i < n; i++) {
        jac[i][c] = span > 0 ? (rp[i] - rm[i]) / span : 0.0;
      }
    }
  }

  residuals(p, r);
  var rss = rssOf(r);
  var stop = LmStop.maxIterations;
  var iterations = 0;
  if (!rss.isFinite) {
    stop = LmStop.nonFinite;
  } else {
    var lambda = 1e-3;
    for (; iterations < maxIter;) {
      iterations++;
      evalJac(p);
      final a = [for (var i = 0; i < k; i++) List<double>.filled(k, 0)];
      final g = List<double>.filled(k, 0);
      for (var row = 0; row < n; row++) {
        final jr = jac[row];
        for (var i = 0; i < k; i++) {
          g[i] += jr[i] * r[row];
          for (var j = i; j < k; j++) {
            a[i][j] += jr[i] * jr[j];
          }
        }
      }
      for (var i = 0; i < k; i++) {
        for (var j = 0; j < i; j++) {
          a[i][j] = a[j][i];
        }
      }
      if (!g.every((v) => v.isFinite) || !a.every((row) => row.every((v) => v.isFinite))) {
        stop = LmStop.nonFinite;
        break;
      }
      // g = J^T r (J = dr/dp) is half the gradient of rss; the Gauss-Newton step is
      // -(J^T J)^-1 g. A parameter at a bound whose descent direction -g points
      // outwards is frozen for this step.
      final free = <int>[
        for (var i = 0; i < k; i++)
          if (!((p[i] <= lo[i] && g[i] > 0) || (p[i] >= hi[i] && g[i] < 0))) i,
      ];
      if (free.isEmpty) {
        stop = LmStop.converged;
        break;
      }
      var maxDiag = 0.0;
      for (final i in free) {
        maxDiag = max(maxDiag, a[i][i]);
      }
      final diagFloor = max(maxDiag * 1e-12, 1e-300);

      var accepted = false;
      var stepRel = double.infinity;
      var costDrop = double.infinity;
      while (lambda <= 1e12) {
        final m = [
          for (final i in free)
            [
              for (final j in free) a[i][j] + (i == j ? lambda * max(a[i][i], diagFloor) : 0.0),
            ],
        ];
        final List<double> delta;
        try {
          delta = solveLinear(m, [for (final i in free) -g[i]]);
        } on SingularMatrixException {
          lambda *= 10;
          continue;
        }
        final trial = List<double>.of(p);
        for (var t = 0; t < free.length; t++) {
          final i = free[t];
          trial[i] = (p[i] + delta[t]).clamp(lo[i], hi[i]).toDouble();
        }
        residuals(trial, rTrial);
        final rssTrial = rssOf(rTrial);
        if (rssTrial.isFinite && rssTrial < rss) {
          stepRel = 0;
          for (final i in free) {
            stepRel = max(stepRel, (trial[i] - p[i]).abs() / (p[i].abs() + 1e-8));
          }
          costDrop = (rss - rssTrial) / max(rss, 1e-300);
          p = trial;
          r.setAll(0, rTrial);
          rss = rssTrial;
          lambda = max(lambda / 10, 1e-12);
          accepted = true;
          break;
        }
        lambda *= 10;
      }
      if (!accepted) {
        // No lower-cost step: at a (numerical) minimum or stuck.
        stop = rss < 1e-30 || _projectedGradientTiny(g, free, rss) ? LmStop.converged : LmStop.noProgress;
        break;
      }
      if (stepRel < tolStep || costDrop < tolCost) {
        stop = LmStop.converged;
        break;
      }
    }
  }

  return _finish(p, rss, iterations, stop, n, k, jac, evalJac, lo, hi, maxCondition);
}

bool _projectedGradientTiny(List<double> g, List<int> free, double rss) {
  var s = 0.0;
  for (final i in free) {
    s += g[i] * g[i];
  }
  return sqrt(s) <= 1e-9 * (1 + sqrt(rss));
}

LmResult _finish(
  List<double> p,
  double rss,
  int iterations,
  LmStop stop,
  int n,
  int k,
  List<List<double>> jac,
  void Function(List<double>) evalJac,
  List<double> lo,
  List<double> hi,
  double maxCondition,
) {
  final dof = n - k;
  List<List<double>>? cov;
  var cond = double.infinity;
  var unstable = true;
  if (stop != LmStop.nonFinite && rss.isFinite) {
    evalJac(p);
    final a = [for (var i = 0; i < k; i++) List<double>.filled(k, 0)];
    for (var row = 0; row < n; row++) {
      for (var i = 0; i < k; i++) {
        for (var j = i; j < k; j++) {
          a[i][j] += jac[row][i] * jac[row][j];
        }
      }
    }
    for (var i = 0; i < k; i++) {
      for (var j = 0; j < i; j++) {
        a[i][j] = a[j][i];
      }
    }
    final finite = a.every((row) => row.every((v) => v.isFinite));
    final scale = [for (var i = 0; i < k; i++) a[i][i] > 0 ? 1 / sqrt(a[i][i]) : double.nan];
    if (finite && scale.every((v) => v.isFinite)) {
      final corr = [
        for (var i = 0; i < k; i++) [for (var j = 0; j < k; j++) a[i][j] * scale[i] * scale[j]],
      ];
      final ev = symmetricEigen(corr).values;
      cond = ev.first > 1e-15 ? ev.last / ev.first : double.infinity;
      unstable = !(cond <= maxCondition);
      if (cond.isFinite && dof > 0) {
        try {
          final s2 = rss / dof;
          final inv = <List<double>>[];
          for (var c = 0; c < k; c++) {
            inv.add(solveLinear(a, [for (var i = 0; i < k; i++) i == c ? 1.0 : 0.0]));
          }
          cov = [
            for (var i = 0; i < k; i++) [for (var j = 0; j < k; j++) s2 * inv[j][i]],
          ];
          if (!cov.every((row) => row.every((v) => v.isFinite))) cov = null;
        } on SingularMatrixException {
          cov = null;
        }
      }
    }
  }
  return LmResult(
    params: p,
    rss: rss,
    iterations: iterations,
    stop: stop,
    covariance: cov,
    s2: dof > 0 ? rss / dof : double.nan,
    dof: dof,
    conditionNumber: cond,
    unstable: unstable,
    atLower: [for (var i = 0; i < k; i++) p[i] <= lo[i]],
    atUpper: [for (var i = 0; i < k; i++) p[i] >= hi[i]],
  );
}
