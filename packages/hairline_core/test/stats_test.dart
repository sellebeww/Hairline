// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  wilsonTests();
  test('median odd, even, unsorted; errors on empty', () {
    expect(median([3.0, 1.0, 2.0]), 2.0);
    expect(median([4.0, 1.0, 2.0, 3.0]), 2.5);
    expect(() => median(<double>[]), throwsArgumentError);
  });

  test('mean and sample sd', () {
    expect(mean([1.0, 2.0, 3.0, 4.0]), 2.5);
    expect(sampleSd([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]), closeTo(sqrt(32 / 7), 1e-15));
    expect(sampleSd([5.0]), 0);
    expect(() => mean(<double>[]), throwsArgumentError);
  });

  test('madSigma ignores a gross outlier that wrecks the sd', () {
    final v = [for (var i = 0; i < 50; i++) sin(i * 1.7), 1000.0];
    expect(madSigma(v), lessThan(2));
    expect(sampleSd(v), greaterThan(100));
  });

  test('ols recovers a line and its slope standard error', () {
    final x = [for (var i = 0; i < 10; i++) i.toDouble()];
    final exact = ols(x, [for (final v in x) 1 + 2 * v]);
    expect(exact.a, closeTo(1, 1e-12));
    expect(exact.b, closeTo(2, 1e-12));
    expect(exact.seB, closeTo(0, 1e-12));
    // Hand case: y = [0, 1, 1]: slope 0.5, rss = 1/6, se = sqrt(rss/(n-2)/sxx) = sqrt(1/12).
    final r = ols([0.0, 1.0, 2.0], [0.0, 1.0, 1.0]);
    expect(r.b, closeTo(0.5, 1e-15));
    expect(r.seB, closeTo(sqrt(1 / 12), 1e-15));
    expect(ols([1.0, 1.0], [0.0, 1.0]).seB, isNaN);
    expect(ols([0.0, 1.0], [0.0, 1.0]).seB, isNaN);
    expect(() => ols([1.0], [1.0]), throwsArgumentError);
  });
}

void wilsonTests() {
  group('wilsonInterval (95 percent)', () {
    test('9 of 10 -> (0.596, 0.982), the textbook Wilson values', () {
      final w = wilsonInterval(9, 10);
      expect(w.lower, closeTo(0.5958, 5e-4));
      expect(w.upper, closeTo(0.9821, 5e-4));
    });
    test('0 of 10 -> upper 0.2775, 10 of 10 -> lower 0.7225 (never degenerate at the edges)', () {
      expect(wilsonInterval(0, 10).lower, closeTo(0, 1e-12));
      expect(wilsonInterval(0, 10).upper, closeTo(0.2775, 5e-4));
      expect(wilsonInterval(10, 10).lower, closeTo(0.7225, 5e-4));
      expect(wilsonInterval(10, 10).upper, closeTo(1, 1e-12));
    });
    test('n = 0 gives the uninformative interval and bad arguments throw', () {
      expect(wilsonInterval(0, 0).lower, 0);
      expect(wilsonInterval(0, 0).upper, 1);
      expect(() => wilsonInterval(5, 4), throwsArgumentError);
    });
  });
}
