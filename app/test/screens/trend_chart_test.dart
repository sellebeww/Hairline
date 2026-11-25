// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/screens/trend_chart.dart';
import 'package:hairline_core/hairline_core.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  ChartPoint p(int days, double? w, double? u, [TrendClass? c]) =>
      ChartPoint(time: t0.add(Duration(days: days)), widthMm: w, uMm: u, classification: c);
  const plot = Rect.fromLTRB(50, 10, 350, 210); // 300 x 200

  test('x is proportional to time, y is linear in mm, bars are w +- U', () {
    final l = TrendChartLayout(points: [p(0, 0.5, 0.1), p(10, 1.0, 0.2), p(30, 1.5, 0.1)], plot: plot);
    expect(l.xOf(0), 50);
    expect(l.xOf(1), closeTo(50 + 300 / 3, 1e-9));
    expect(l.xOf(2), 350);
    // max value = (1.5 + 0.1) * 1.15
    expect(l.maxValue, closeTo(1.6 * 1.15, 1e-12));
    expect(l.yOf(0), 210);
    expect(l.yOf(l.maxValue), 10);
    final bar = l.barOf(1)!;
    expect(bar.center, closeTo(l.yOf(1.0), 1e-9));
    expect(bar.top, closeTo(l.yOf(1.2), 1e-9));
    expect(bar.bottom, closeTo(l.yOf(0.8), 1e-9));
    expect(bar.top, lessThan(bar.center));
    expect(bar.bottom, greaterThan(bar.center));
    // The bar height equals 2U in value units.
    expect((bar.bottom - bar.top) / (200 / l.maxValue), closeTo(0.4, 1e-9));
    expect(l.baselineY, closeTo(l.yOf(0.5), 1e-9));
  });

  test('a bar never goes below zero; a visit without a number has no bar; one visit sits in the middle', () {
    final l = TrendChartLayout(points: [p(0, 0.1, 0.3), p(5, null, null, TrendClass.tidakTerukur)], plot: plot);
    expect(l.barOf(0)!.bottom, l.yOf(0));
    expect(l.barOf(1), isNull);
    final single = TrendChartLayout(points: [p(0, 0.4, 0.05)], plot: plot);
    expect(single.xOf(0), plot.center.dx);
    expect(TrendChartLayout(points: [p(0, null, null), p(3, null, null)], plot: plot).baselineY, isNull);
  });

  test('tick step is 1, 2 or 5 times a power of ten', () {
    for (final w in [0.07, 0.3, 0.9, 2.4, 11.0]) {
      final l = TrendChartLayout(points: [p(0, w, 0)], plot: plot);
      final f = l.tickStep / _pow10(l.tickStep);
      expect([1.0, 2.0, 5.0].any((v) => (f - v).abs() < 1e-9), isTrue, reason: 'w=$w step=${l.tickStep}');
    }
  });

  test('the painter lays out in the same plot rectangle the layout uses', () {
    final painter = TrendChartPainter(points: [p(0, 0.5, 0.1)], ink: const Color(0xFF000000), accent: const Color(0xFF0000FF));
    final l = painter.layoutFor(const Size(400, 240));
    expect(l.plot, TrendChartPainter.padding.deflateRect(const Rect.fromLTWH(0, 0, 400, 240)));
  });
}

double _pow10(double v) {
  var p = 1.0;
  while (p * 10 <= v + 1e-12) {
    p *= 10;
  }
  while (p > v + 1e-12) {
    p /= 10;
  }
  return p;
}
