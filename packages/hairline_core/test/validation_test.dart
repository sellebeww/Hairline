// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

/// 4 widths x 5 lines. Group bias b_w, zero-mean offsets [-2 -1 0 1 2] mm * 1e-3.
/// Every line: u_c 0.002, k 2, u_truth 0.001 -> U_comb = 2 sqrt(4e-6 + 1e-6) = 0.0044721.
const offsets = [-0.002, -0.001, 0.0, 0.001, 0.002];
final biases = {0.1: 0.010, 0.2: 0.004, 0.5: -0.003, 1.0: 0.001};

List<PlateMeasurement> plate({Map<double, double>? bias, double uC = 0.002, double? missingAt}) => [
      for (final e in (bias ?? biases).entries)
        for (var i = 0; i < 5; i++)
          PlateMeasurement(
            lineId: '${e.key}-$i',
            truthMm: e.key,
            uTruthMm: 0.001,
            measuredMm: e.key == missingAt ? null : e.key + e.value + offsets[i],
            uCMm: uC,
            k: 2,
          ),
    ];

void main() {
  group('plate statistics on artificial data with known bias', () {
    final s = computePlateStats(plate());

    test('error = measured - truth: per-width bias equals the planted bias', () {
      expect(s.groups.map((g) => g.truthMm), [0.1, 0.2, 0.5, 1.0]);
      for (final g in s.groups) {
        expect(g.biasMm, closeTo(biases[g.truthMm]!, 1e-12), reason: '${g.truthMm}');
        expect(g.n, 5);
      }
    });

    test('per-width RMSE = sqrt(bias^2 + mean offset^2), mean offset^2 = 2e-6', () {
      for (final g in s.groups) {
        final b = biases[g.truthMm]!;
        expect(g.rmseMm, closeTo(sqrt(b * b + 2e-6), 1e-12));
        expect(g.sdMm, closeTo(sqrt(10e-6 / 4), 1e-12)); // sample sd of the offsets
      }
    });

    test('overall bias 0.003 and RMSE sqrt(3.35e-5) = 0.0057879', () {
      expect(s.n, 20);
      expect(s.biasMm, closeTo(0.003, 1e-12));
      expect(s.rmseMm, closeTo(0.0057879185, 1e-9));
    });

    test('coverage is the fraction with |error| <= k sqrt(u_c^2 + u_truth^2): 0 + 3 + 4 + 5 of 20 = 0.6', () {
      expect(s.groups.map((g) => g.coverage), [0.0, 0.6, 0.8, 1.0]);
      expect(s.coverage, closeTo(0.6, 1e-12));
    });

    test('the error sign convention: a reading that is too small gives a negative bias', () {
      final g = s.groups.firstWhere((g) => g.truthMm == 0.5);
      expect(g.biasMm, lessThan(0));
    });
  });

  group('empirical lower reporting limit', () {
    test('smallest width such that it and every larger width are reliable: only 1.0 here', () {
      expect(computePlateStats(plate()).lowerLimitMm, 1.0);
    });

    test('all widths reliable: the smallest tested width', () {
      expect(computePlateStats(plate(bias: {0.1: 0.0, 0.2: 0.0, 0.5: 0.0, 1.0: 0.0})).lowerLimitMm, 0.1);
    });

    test('a failing middle width pushes the limit above it (no cherry-picking the narrow one)', () {
      final s = computePlateStats(plate(bias: {0.1: 0.0, 0.2: 0.0, 0.5: 0.02, 1.0: 0.0}));
      expect(s.lowerLimitMm, 1.0);
    });

    test('nothing reliable: null (the plate does not support any reporting limit)', () {
      expect(computePlateStats(plate(bias: {0.1: 0.02, 0.2: 0.02, 0.5: 0.02, 1.0: 0.02})).lowerLimitMm, isNull);
    });

    test('a width whose uncertainty exceeds the width itself is not reliable even if it covers the truth', () {
      final s = computePlateStats(plate(bias: {0.1: 0.0, 1.0: 0.0}, uC: 0.1)); // U_comb = 0.2 > 0.1
      expect(s.lowerLimitMm, 1.0);
    });

    test('lines with no reported number (below the limit) make that width unreliable', () {
      final s = computePlateStats(plate(bias: {0.1: 0.0, 0.2: 0.0, 0.5: 0.0, 1.0: 0.0}, missingAt: 0.2));
      expect(s.lowerLimitMm, 0.5);
      expect(s.groups.firstWhere((g) => g.truthMm == 0.2).reported, 0);
    });
  });

  group('u_dev derivation (RMS of the per-width bias at comparable widths)', () {
    final s = computePlateStats(plate());

    test('at 0.5 mm, comparable = 0.25..1.0 (widths 0.5 and 1.0): sqrt((9e-6 + 1e-6)/2)', () {
      final d = deriveUDev(s, 0.5)!;
      expect(d.uDevMm, closeTo(sqrt(5e-6), 1e-12));
      expect(d.groups, 2);
    });

    test('at 0.1 mm, widths 0.1 and 0.2: sqrt((1e-4 + 1.6e-5)/2)', () {
      expect(deriveUDev(s, 0.1)!.uDevMm, closeTo(sqrt(5.8e-5), 1e-12));
    });

    test('no comparable width: null, so the unvalidated default stays in force', () {
      expect(deriveUDev(s, 5.0), isNull);
    });

    test('a smaller ratio narrows the comparable set', () {
      expect(deriveUDev(s, 0.5, ratio: 1.2)!.groups, 1);
      expect(deriveUDev(s, 0.5, ratio: 1.2)!.uDevMm, closeTo(0.003, 1e-12));
    });

    test('feeds the budget: validated u_dev clears BELUM_DIVALIDASI', () {
      final d = deriveUDev(s, 0.5)!;
      final b = UncertaintyBudget.fromFrames([
        for (final w in [0.5, 0.51, 0.49])
          FrameRecord(status: MeasureStatus.terukur, widthMm: w, uFitRawMm: 0.004, rho: 1, uSigmaWMm: 0.003, dwDs: 0.01, mmPerPx: 0.06, rmsPx: 0.3, looMm: null, tiltDeg: 5),
      ], UncertaintyOptions(uDevMm: d.uDevMm));
      expect(b.belumDivalidasi, isFalse);
      expect(b.uDev, d.uDevMm);
    });
  });

  group('stable JSON', () {
    test('keys, order and values are deterministic and survive a round trip', () {
      final a = jsonEncode(computePlateStats(plate()).toJson());
      final b = jsonEncode(computePlateStats(plate()).toJson());
      expect(a, b);
      final m = jsonDecode(a) as Map<String, Object?>;
      expect(m.keys.toList(), ['n', 'reported', 'bias_mm', 'rmse_mm', 'coverage', 'lower_limit_mm', 'groups']);
      final g = (m['groups']! as List<Object?>).first! as Map<String, Object?>;
      expect(g.keys.toList(), ['truth_mm', 'n', 'reported', 'bias_mm', 'rmse_mm', 'sd_mm', 'coverage', 'u_expanded_median_mm', 'reliable']);
      expect(m['lower_limit_mm'], 1.0);
    });

    test('a null lower limit is written as null and NaN never appears', () {
      final s = computePlateStats(plate(bias: {0.1: 0.02, 1.0: 0.02}));
      final text = jsonEncode(s.toJson());
      expect(text, contains('"lower_limit_mm":null'));
      expect(text, isNot(contains('NaN')));
    });
  });

  test('input validation: empty plate, negative or non-finite values', () {
    expect(() => computePlateStats(const []), throwsArgumentError);
    expect(() => computePlateStats([const PlateMeasurement(lineId: 'a', truthMm: -1, uTruthMm: 0, measuredMm: 1, uCMm: 0, k: 2)]), throwsArgumentError);
    expect(() => computePlateStats([const PlateMeasurement(lineId: 'a', truthMm: 1, uTruthMm: 0, measuredMm: double.nan, uCMm: 0, k: 2)]), throwsArgumentError);
  });
}
