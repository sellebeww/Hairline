// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  group('solveLinear', () {
    test('solves a known 3x3 system', () {
      // x=1, y=-2, z=3; right-hand side by hand: 2-2-3=-3, -3+2+6=5, -2-2+6=2.
      final b = [-3.0, 5.0, 2.0];
      final sol = solveLinear([
        [2.0, 1, -1],
        [-3, -1, 2],
        [-2, 1, 2],
      ], b);
      expect(sol[0], closeTo(1, 1e-12));
      expect(sol[1], closeTo(-2, 1e-12));
      expect(sol[2], closeTo(3, 1e-12));
    });

    test('needs pivoting when the leading entry is zero', () {
      final sol = solveLinear([
        [0.0, 1],
        [1, 0],
      ], [2.0, 3]);
      expect(sol, [3.0, 2.0]);
    });

    test('nearly singular (cond ~1e10) still solves with small residual', () {
      // Tolerance 1e-5: relative error ~ cond * eps = 1e10 * 1e-16 = 1e-6.
      const e = 1e-10;
      final a = [
        [1.0, 1.0],
        [1.0, 1.0 + e],
      ];
      final sol = solveLinear(a, [2.0, 2.0 + e]);
      expect(sol[0], closeTo(1, 1e-5));
      expect(sol[1], closeTo(1, 1e-5));
    });

    test('Hilbert 6x6 solves to the known solution within cond*eps', () {
      // cond(H6) ~ 1.5e7, so error ~1e-9; tolerance 1e-7.
      const n = 6;
      final a = [
        for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) 1 / (i + j + 1)],
      ];
      final b = [
        for (var i = 0; i < n; i++)
          [for (var j = 0; j < n; j++) a[i][j]].reduce((p, q) => p + q),
      ];
      final sol = solveLinear(a, b);
      for (final v in sol) {
        expect(v, closeTo(1, 1e-7));
      }
    });

    test('exactly singular and zero matrices throw SingularMatrixException', () {
      expect(
        () => solveLinear([
          [1.0, 2],
          [2, 4],
        ], [1.0, 2]),
        throwsA(isA<SingularMatrixException>()),
      );
      expect(
        () => solveLinear([
          [0.0, 0],
          [0, 0],
        ], [1.0, 2]),
        throwsA(isA<SingularMatrixException>()),
      );
    });

    test('NaN or infinite entries throw instead of returning NaN', () {
      expect(
        () => solveLinear([
          [double.nan, 1.0],
          [1.0, 2.0],
        ], [1.0, 2.0]),
        throwsA(isA<SingularMatrixException>()),
      );
      expect(
        () => solveLinear([
          [1.0, 0.0],
          [0.0, double.infinity],
        ], [1.0, 2.0]),
        throwsA(isA<SingularMatrixException>()),
      );
    });

    test('rejects dimension mismatch', () {
      expect(() => solveLinear([[1.0, 2]], [1.0]), throwsArgumentError);
      expect(
        () => solveLinear([
          [1.0],
          [2.0],
        ], [1.0]),
        throwsArgumentError,
      );
    });
  });

  group('Mat3', () {
    test('inverse of a known matrix', () {
      final m = <double>[2, 0, 1, 1, 3, 2, 1, 1, 2];
      final inv = mat3Inverse(m);
      final id = mat3Mul(m, inv);
      const eye = [1.0, 0, 0, 0, 1, 0, 0, 0, 1];
      for (var i = 0; i < 9; i++) {
        expect(id[i], closeTo(eye[i], 1e-14));
      }
    });

    test('inverse of a nearly singular but legitimate matrix is accurate', () {
      // Scale-invariant test: tiny overall scale must not trigger singularity.
      final m = <double>[2e-8, 0, 1e-8, 1e-8, 3e-8, 2e-8, 1e-8, 1e-8, 2e-8];
      final id = mat3Mul(m, mat3Inverse(m));
      expect(id[0], closeTo(1, 1e-12));
      expect(id[4], closeTo(1, 1e-12));
      expect(id[1].abs(), lessThan(1e-12));
    });

    test('singular matrix throws', () {
      expect(
        () => mat3Inverse(<double>[1, 2, 3, 2, 4, 6, 1, 0, 1]),
        throwsA(isA<SingularMatrixException>()),
      );
      expect(
        () => mat3Inverse(List<double>.filled(9, 0)),
        throwsA(isA<SingularMatrixException>()),
      );
    });

    test('determinant of a known matrix', () {
      expect(mat3Det(<double>[2, 0, 1, 1, 3, 2, 1, 1, 2]), closeTo(2 * (6 - 2) + 1 * (1 - 3), 1e-14));
    });
  });

  group('small matrices', () {
    test('matMul and transpose', () {
      final a = <List<double>>[
        [1.0, 2, 3],
        [4.0, 5, 6],
      ];
      final p = matMul(a, transpose(a));
      expect(p, [
        [14.0, 32.0],
        [32.0, 77.0],
      ]);
    });

    test('matMul rejects incompatible shapes', () {
      expect(
        () => matMul([
          [1.0, 2]
        ], [
          [1.0, 2]
        ]),
        throwsArgumentError,
      );
    });
  });

  group('symmetricEigen', () {
    test('known 2x2 and sorted ascending', () {
      final e = symmetricEigen([
        [2.0, 1],
        [1, 2],
      ]);
      expect(e.values[0], closeTo(1, 1e-12));
      expect(e.values[1], closeTo(3, 1e-12));
      // Eigenvector of 1 is (1,-1)/sqrt2 up to sign.
      expect((e.vectors[0][0] + e.vectors[0][1]).abs(), lessThan(1e-12));
    });

    test('random SPD 9x9: A v = lambda v and orthonormal vectors', () {
      final rng = Random(7);
      final b = [
        for (var i = 0; i < 9; i++) [for (var j = 0; j < 9; j++) rng.nextDouble() - 0.5],
      ];
      final a = matMul(transpose(b), b);
      final e = symmetricEigen(a);
      for (var k = 0; k < 9; k++) {
        final v = e.vectors[k];
        for (var i = 0; i < 9; i++) {
          var av = 0.0;
          for (var j = 0; j < 9; j++) {
            av += a[i][j] * v[j];
          }
          expect(av, closeTo(e.values[k] * v[i], 1e-10));
        }
        expect(v.fold<double>(0, (s, x) => s + x * x), closeTo(1, 1e-12));
        if (k > 0) {
          expect(e.values[k], greaterThanOrEqualTo(e.values[k - 1]));
        }
      }
    });

    test('diagonal matrix returns immediately', () {
      final e = symmetricEigen([
        [3.0, 0],
        [0, 1],
      ]);
      expect(e.values, [1.0, 3.0]);
    });
  });
}
