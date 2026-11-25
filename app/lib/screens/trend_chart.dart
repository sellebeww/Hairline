// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hairline_core/hairline_core.dart';

import '../l10n/strings.dart';

/// One visit on the chart. [widthMm] and [uMm] are null when there is no number.
final class ChartPoint {
  const ChartPoint({required this.time, required this.widthMm, required this.uMm, required this.classification});
  final DateTime time;
  final double? widthMm, uMm;

  /// Comparison with the baseline (null for the baseline itself).
  final TrendClass? classification;
}

/// Pure geometry of the chart: where each point and uncertainty bar lies. Tested apart
/// from painting. y grows downward; value 0 is at [bottom], [maxValue] at [top].
final class TrendChartLayout {
  TrendChartLayout({required this.points, required this.plot}) {
    var m = 0.0;
    for (final p in points) {
      if (p.widthMm != null) m = max(m, p.widthMm! + (p.uMm ?? 0));
    }
    maxValue = m <= 0 ? 1 : m * 1.15;
    t0 = points.isEmpty ? 0 : points.map((p) => p.time.millisecondsSinceEpoch).reduce(min).toDouble();
    t1 = points.isEmpty ? 0 : points.map((p) => p.time.millisecondsSinceEpoch).reduce(max).toDouble();
  }

  final List<ChartPoint> points;

  /// The plotting rectangle (axes inside the canvas).
  final Rect plot;
  late final double maxValue, t0, t1;

  double get bottom => plot.bottom;
  double get top => plot.top;

  double xOf(int i) {
    if (t1 == t0) return plot.center.dx;
    return plot.left + (points[i].time.millisecondsSinceEpoch - t0) / (t1 - t0) * plot.width;
  }

  double yOf(double mm) => bottom - mm / maxValue * (bottom - top);

  /// Top and bottom of the uncertainty bar of point [i] (null without a number).
  ({double top, double bottom, double center})? barOf(int i) {
    final w = points[i].widthMm;
    if (w == null) return null;
    final u = points[i].uMm ?? 0;
    return (top: yOf(w + u), bottom: yOf(max(0, w - u)), center: yOf(w));
  }

  /// y of the baseline line (the first visit's width), null if it has no number.
  double? get baselineY => points.isEmpty || points.first.widthMm == null ? null : yOf(points.first.widthMm!);

  /// A readable step (1, 2 or 5 times a power of ten) giving about 4 ticks.
  double get tickStep {
    final raw = maxValue / 4;
    final p = pow(10, (log(raw) / ln10).floor()).toDouble();
    final f = raw / p;
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p;
  }
}

/// Draws axes, the baseline, uncertainty bars with caps and a marker whose SHAPE tells the
/// classification (circle, triangle up or down, cross), so color is never the only cue.
final class TrendChartPainter extends CustomPainter {
  const TrendChartPainter({required this.points, required this.ink, required this.accent});
  final List<ChartPoint> points;
  final Color ink, accent;

  static const EdgeInsets padding = EdgeInsets.fromLTRB(56, 12, 16, 28);

  TrendChartLayout layoutFor(Size size) => TrendChartLayout(points: points, plot: padding.deflateRect(Offset.zero & size));

  @override
  void paint(Canvas canvas, Size size) {
    final l = layoutFor(size);
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(l.plot.bottomLeft, l.plot.bottomRight, axis)
      ..drawLine(l.plot.topLeft, l.plot.bottomLeft, axis);
    for (var v = 0.0; v <= l.maxValue; v += l.tickStep) {
      final y = l.yOf(v);
      canvas.drawLine(Offset(l.plot.left - 4, y), Offset(l.plot.left, y), axis);
      _text(canvas, Strings.trendYAxisLabel(v), Offset(l.plot.left - 6, y), alignRight: true);
    }
    final by = l.baselineY;
    if (by != null) {
      for (var x = l.plot.left; x < l.plot.right; x += 12) {
        canvas.drawLine(Offset(x, by), Offset(min(x + 6, l.plot.right), by), axis..strokeWidth = 1);
      }
    }
    final bar = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final x = l.xOf(i);
      _text(canvas, Strings.trendXAxisLabel(points[i].time), Offset(x, l.bottom + 4), center: true);
      final b = l.barOf(i);
      if (b == null) {
        _cross(canvas, Offset(x, l.bottom - 10), ink);
        continue;
      }
      canvas
        ..drawLine(Offset(x, b.top), Offset(x, b.bottom), bar)
        ..drawLine(Offset(x - 6, b.top), Offset(x + 6, b.top), bar)
        ..drawLine(Offset(x - 6, b.bottom), Offset(x + 6, b.bottom), bar);
      _marker(canvas, Offset(x, b.center), points[i].classification);
    }
  }

  void _marker(Canvas canvas, Offset c, TrendClass? cls) {
    final fill = Paint()..color = ink;
    switch (cls) {
      case TrendClass.kemungkinanBertambahLebar:
        canvas.drawPath(Path()..addPolygon([c + const Offset(0, -9), c + const Offset(8, 7), c + const Offset(-8, 7)], true), fill);
      case TrendClass.kemungkinanMenyempit:
        canvas.drawPath(Path()..addPolygon([c + const Offset(0, 9), c + const Offset(8, -7), c + const Offset(-8, -7)], true), fill);
      case TrendClass.tidakTerukur:
        _cross(canvas, c, ink);
      case TrendClass.tidakAdaPerubahanTerdeteksi || null:
        canvas.drawCircle(c, 6, fill);
    }
  }

  void _cross(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    canvas
      ..drawLine(c + const Offset(-6, -6), c + const Offset(6, 6), p)
      ..drawLine(c + const Offset(-6, 6), c + const Offset(6, -6), p);
  }

  void _text(Canvas canvas, String s, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: ink, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
    final dx = alignRight ? -tp.width : (center ? -tp.width / 2 : 0.0);
    tp.paint(canvas, at + Offset(dx, alignRight ? -tp.height / 2 : 0));
  }

  @override
  bool shouldRepaint(TrendChartPainter old) => old.points != points || old.ink != ink || old.accent != accent;
}

/// The chart with a text alternative listing every visit.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, required this.semanticItems});
  final List<ChartPoint> points;
  final List<String> semanticItems;

  @override
  Widget build(BuildContext context) => Semantics(
        label: Strings.trendChartSemantics(semanticItems),
        image: true,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: CustomPaint(painter: TrendChartPainter(points: points, ink: Theme.of(context).colorScheme.onSurface, accent: Theme.of(context).colorScheme.primary)),
          ),
        ),
      );
}
