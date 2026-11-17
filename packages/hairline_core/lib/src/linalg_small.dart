// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

/// Row-major 3x3 matrix stored as 9 doubles.
typedef Mat3 = List<double>;

/// Thrown when a matrix is singular to working precision.
final class SingularMatrixException implements Exception {
  const SingularMatrixException(this.message);
  final String message;

  @override
  String toString() => 'SingularMatrixException: $message';
}

/// Solves `a x = b` by Gaussian elimination with partial pivoting.
///
/// A pivot smaller than `relTol` times the largest entry of `a` is treated as
/// singular. 1e-13 is about 1000 machine epsilons: it rejects exactly rank
/// deficient systems yet still solves ones with condition number up to ~1e12.
List<double> solveLinear(List<List<double>> a, List<double> b, {double relTol = 1e-13}) {
  final n = b.length;
  if (a.length != n || a.any((r) => r.length != n)) {
    throw ArgumentError('solveLinear needs a square ${n}x$n matrix');
  }
  final m = [
    for (var i = 0; i < n; i++) [...a[i], b[i]],
  ];
  var scale = 0.0;
  for (final r in a) {
    for (final v in r) {
      scale = max(scale, v.abs());
    }
  }
  if (scale == 0) throw const SingularMatrixException('zero matrix');
  if (!scale.isFinite) throw const SingularMatrixException('matrix has non-finite entries');
  for (var c = 0; c < n; c++) {
    var p = c;
    for (var r = c + 1; r < n; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    // Negated comparison so that NaN and infinite pivots also throw.
    if (!(m[p][c].abs() > relTol * scale)) {
      throw const SingularMatrixException('pivot below tolerance or not finite');
    }
    final t = m[p];
    m[p] = m[c];
    m[c] = t;
    for (var r = c + 1; r < n; r++) {
      final f = m[r][c] / m[c][c];
      for (var k = c; k <= n; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = m[i][n];
    for (var j = i + 1; j < n; j++) {
      s -= m[i][j] * x[j];
    }
    x[i] = s / m[i][i];
  }
  return x;
}

/// Product of two row-major 3x3 matrices.
Mat3 mat3Mul(Mat3 a, Mat3 b) {
  final r = List<double>.filled(9, 0);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    }
  }
  return r;
}

double mat3Det(Mat3 m) =>
    m[0] * (m[4] * m[8] - m[5] * m[7]) -
    m[1] * (m[3] * m[8] - m[5] * m[6]) +
    m[2] * (m[3] * m[7] - m[4] * m[6]);

/// Inverse via the adjugate. The singularity test is scale invariant:
/// `|det| <= 1e-13 * (max|entry|)^3` (a permissive bound, matches [solveLinear]).
Mat3 mat3Inverse(Mat3 m) {
  final d = mat3Det(m);
  final s = m.fold<double>(0, (p, v) => max(p, v.abs()));
  if (s == 0 || d.abs() <= 1e-13 * s * s * s) {
    throw const SingularMatrixException('3x3 matrix is singular');
  }
  return [
    (m[4] * m[8] - m[5] * m[7]) / d,
    (m[2] * m[7] - m[1] * m[8]) / d,
    (m[1] * m[5] - m[2] * m[4]) / d,
    (m[5] * m[6] - m[3] * m[8]) / d,
    (m[0] * m[8] - m[2] * m[6]) / d,
    (m[2] * m[3] - m[0] * m[5]) / d,
    (m[3] * m[7] - m[4] * m[6]) / d,
    (m[1] * m[6] - m[0] * m[7]) / d,
    (m[0] * m[4] - m[1] * m[3]) / d,
  ];
}

List<List<double>> transpose(List<List<double>> a) => [
      for (var j = 0; j < a[0].length; j++) [for (final row in a) row[j]],
    ];

List<List<double>> matMul(List<List<double>> a, List<List<double>> b) {
  if (a[0].length != b.length) throw ArgumentError('matMul shape mismatch');
  return [
    for (final row in a)
      [
        for (var j = 0; j < b[0].length; j++)
          [for (var k = 0; k < b.length; k++) row[k] * b[k][j]].fold<double>(0, (s, v) => s + v),
      ],
  ];
}

/// Eigen-decomposition of a symmetric matrix (cyclic Jacobi). Eigenvalues are
/// ascending; `vectors[k]` is the unit eigenvector of `values[k]`.
({List<double> values, List<List<double>> vectors}) symmetricEigen(
  List<List<double>> a, {
  int maxSweeps = 60,
}) {
  final n = a.length;
  final m = [for (final r in a) List<double>.of(r)];
  final v = [
    for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0],
  ];
  var frob = 0.0;
  for (final r in m) {
    for (final x in r) {
      frob += x * x;
    }
  }
  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    var off = 0.0;
    for (var p = 0; p < n; p++) {
      for (var q = p + 1; q < n; q++) {
        off += m[p][q] * m[p][q];
      }
    }
    if (off <= 1e-32 * frob) break;
    for (var p = 0; p < n; p++) {
      for (var q = p + 1; q < n; q++) {
        if (m[p][q] == 0) continue;
        final theta = (m[q][q] - m[p][p]) / (2 * m[p][q]);
        final t = (theta >= 0 ? 1 : -1) / (theta.abs() + sqrt(theta * theta + 1));
        final c = 1 / sqrt(t * t + 1);
        final s = t * c;
        for (var k = 0; k < n; k++) {
          final kp = m[k][p], kq = m[k][q];
          m[k][p] = c * kp - s * kq;
          m[k][q] = s * kp + c * kq;
        }
        for (var k = 0; k < n; k++) {
          final pk = m[p][k], qk = m[q][k];
          m[p][k] = c * pk - s * qk;
          m[q][k] = s * pk + c * qk;
        }
        for (var k = 0; k < n; k++) {
          final kp = v[k][p], kq = v[k][q];
          v[k][p] = c * kp - s * kq;
          v[k][q] = s * kp + c * kq;
        }
      }
    }
  }
  final order = List<int>.generate(n, (i) => i)..sort((i, j) => m[i][i].compareTo(m[j][j]));
  return (
    values: [for (final i in order) m[i][i]],
    vectors: [
      for (final i in order) [for (var k = 0; k < n; k++) v[k][i]],
    ],
  );
}
