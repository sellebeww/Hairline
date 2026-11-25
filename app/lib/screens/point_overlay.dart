// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hairline_core/hairline_core.dart';

/// Half length of the averaged crack segment (the 4 mm of 5.3), in mm at print scale 1.
const double segmentHalfMm = 2;

/// Image pixel polygon of a square of half size [halfMm] (print scaled) around the window centre.
List<Pt> projectSquare(Mat3 h, double halfMm, double printScale) {
  final e = halfMm * printScale;
  return [for (final c in [Pt(-e, -e), Pt(e, -e), Pt(e, e), Pt(-e, e)]) applyHomography(h, c)];
}

/// Image pixel ends of the 4 mm segment through [pointMm] along [directionDeg].
(Pt, Pt) projectSegment(Mat3 h, Pt pointMm, double directionDeg, double printScale) {
  final a = directionDeg * pi / 180;
  final d = Pt(cos(a), sin(a)) * (segmentHalfMm * printScale);
  return (applyHomography(h, pointMm - d), applyHomography(h, pointMm + d));
}

/// Draws the window (solid), the 50 x 50 mm measurement zone (dashed), and the located
/// point with its 4 mm segment on the baseline photo. Coordinates are image pixels scaled
/// by [scale] to the canvas. Shapes differ (solid, dashed, segment, ring), not only colors.
final class PointOverlayPainter extends CustomPainter {
  const PointOverlayPainter({
    required this.h,
    required this.printScale,
    required this.scale,
    this.pointMm,
    this.directionDeg,
    this.windowColor = const Color(0xFFFFFFFF),
    this.pointColor = const Color(0xFFFFD600),
  });

  final Mat3 h;
  final double printScale;

  /// Canvas pixels per image pixel.
  final double scale;
  final Pt? pointMm;
  final double? directionDeg;
  final Color windowColor, pointColor;

  Offset _o(Pt p) => Offset(p.x * scale, p.y * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final window = Paint()
      ..color = windowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(Path()..addPolygon([for (final p in projectSquare(h, windowHalfSizeMm, printScale)) _o(p)], true), window);

    final zone = [for (final p in projectSquare(h, measurementZoneHalfMm, printScale)) _o(p)];
    final dashed = Paint()
      ..color = windowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 4; i++) {
      final a = zone[i], b = zone[(i + 1) % 4];
      final n = max(2, ((b - a).distance / 10).floor());
      for (var k = 0; k < n; k += 2) {
        canvas.drawLine(Offset.lerp(a, b, k / n)!, Offset.lerp(a, b, min(1, (k + 1) / n))!, dashed);
      }
    }

    final p = pointMm, d = directionDeg;
    if (p == null || d == null) return;
    final (s0, s1) = projectSegment(h, p, d, printScale);
    final halo = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final seg = Paint()
      ..color = pointColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(_o(s0), _o(s1), halo)
      ..drawLine(_o(s0), _o(s1), seg)
      ..drawCircle(_o(applyHomography(h, p)), 9, Paint()..color = const Color(0xFF000000)..style = PaintingStyle.stroke..strokeWidth = 5)
      ..drawCircle(_o(applyHomography(h, p)), 9, Paint()..color = pointColor..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(PointOverlayPainter old) =>
      old.h != h || old.scale != scale || old.pointMm != pointMm || old.directionDeg != directionDeg || old.printScale != printScale;
}
