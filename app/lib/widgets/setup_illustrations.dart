// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter/material.dart';

/// Simple drawings for the guided setup, made here with CustomPaint (no external assets).
enum SetupIllustrationKind { print, ruler, cut, mount, relief }

class SetupIllustration extends StatelessWidget {
  const SetupIllustration({super.key, required this.kind, required this.description});

  final SetupIllustrationKind kind;

  /// Text alternative read by screen readers.
  final String description;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: description,
        child: ExcludeSemantics(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CustomPaint(painter: SetupIllustrationPainter(kind, Theme.of(context).colorScheme.onSurface, Theme.of(context).colorScheme.primary)),
          ),
        ),
      );
}

class SetupIllustrationPainter extends CustomPainter {
  const SetupIllustrationPainter(this.kind, this.ink, this.accent);

  final SetupIllustrationKind kind;
  final Color ink, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = ink;
    final acc = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    switch (kind) {
      case SetupIllustrationKind.print:
        final sheet = Rect.fromCenter(center: size.center(Offset.zero), width: size.height * 0.75, height: size.height * 0.9);
        _sheet(canvas, sheet, line, fill);
        // Arrow pointing out of the printer: the sheet comes out at its original size.
        canvas.drawLine(Offset(sheet.right + 20, sheet.top + 10), Offset(sheet.right + 20, sheet.bottom - 10), acc);
        canvas.drawLine(Offset(sheet.right + 20, sheet.bottom - 10), Offset(sheet.right + 10, sheet.bottom - 24), acc);
        canvas.drawLine(Offset(sheet.right + 20, sheet.bottom - 10), Offset(sheet.right + 30, sheet.bottom - 24), acc);
      case SetupIllustrationKind.ruler:
        final y = size.height * 0.62;
        final x0 = size.width * 0.12, x1 = size.width * 0.88;
        canvas
          ..drawLine(Offset(x0, y), Offset(x1, y), line..strokeWidth = 3)
          ..drawLine(Offset(x0, y - 12), Offset(x0, y + 12), line)
          ..drawLine(Offset(x1, y - 12), Offset(x1, y + 12), line);
        final ruler = Rect.fromLTRB(x0 - 6, y - size.height * 0.4, x1 + 6, y - 14);
        canvas.drawRect(ruler, acc);
        for (var i = 0; i <= 20; i++) {
          final x = x0 + (x1 - x0) * i / 20;
          canvas.drawLine(Offset(x, ruler.bottom), Offset(x, ruler.bottom - (i % 5 == 0 ? 16 : 8)), acc);
        }
      case SetupIllustrationKind.cut:
        final sheet = Rect.fromCenter(center: size.center(Offset.zero), width: size.height * 0.9, height: size.height * 0.9);
        _sheet(canvas, sheet, line, fill);
        final c = Offset(sheet.right + 6, sheet.top + 10);
        canvas
          ..drawLine(c, c + const Offset(36, 36), acc)
          ..drawLine(c + const Offset(36, 0), c + const Offset(0, 36), acc)
          ..drawCircle(c + const Offset(40, 40), 8, acc)
          ..drawCircle(c + const Offset(-4, 40), 8, acc);
      case SetupIllustrationKind.mount:
        final wall = Rect.fromLTWH(size.width * 0.08, size.height * 0.05, size.width * 0.84, size.height * 0.9);
        canvas.drawRect(wall, line);
        final sheet = Rect.fromCenter(center: wall.center, width: wall.height * 0.85, height: wall.height * 0.85);
        _sheet(canvas, sheet, line, fill);
        final crack = Path()..moveTo(wall.center.dx - sheet.width * 0.22, wall.center.dy - sheet.height * 0.2);
        for (var i = 1; i <= 6; i++) {
          crack.lineTo(wall.center.dx - sheet.width * 0.22 + i * sheet.width * 0.075, wall.center.dy - sheet.height * 0.2 + i * sheet.height * 0.065 + (i.isEven ? 4 : -4));
        }
        canvas.drawPath(crack, acc);
        for (final dx in [-1.0, 1.0]) {
          for (final dy in [-1.0, 1.0]) {
            canvas.drawLine(sheet.center + Offset(dx * sheet.width / 2, dy * sheet.height / 2), sheet.center + Offset(dx * (sheet.width / 2 + 12), dy * (sheet.height / 2 + 12)), acc);
          }
        }
      case SetupIllustrationKind.relief:
        final y = size.height * 0.4;
        canvas.drawLine(Offset(size.width * 0.1, y), Offset(size.width * 0.9, y), line);
        final surface = Path()..moveTo(size.width * 0.1, size.height * 0.75);
        for (var i = 0; i <= 40; i++) {
          final x = size.width * (0.1 + 0.8 * i / 40);
          surface.lineTo(x, size.height * 0.75 + 6 * sin(i * 0.9) + (i > 18 && i < 24 ? 14 : 0));
        }
        canvas
          ..drawPath(surface, line)
          ..drawLine(Offset(size.width * 0.5, y + 4), Offset(size.width * 0.5, size.height * 0.75 + 12), acc)
          ..drawLine(Offset(size.width * 0.5, y + 4), Offset(size.width * 0.5 - 6, y + 14), acc)
          ..drawLine(Offset(size.width * 0.5, y + 4), Offset(size.width * 0.5 + 6, y + 14), acc);
    }
  }

  /// A mini marker frame sheet: paper, four black marker squares, a dashed window, the bar.
  void _sheet(Canvas canvas, Rect r, Paint line, Paint fill) {
    canvas.drawRect(r, line);
    final m = r.width * 0.17;
    for (final o in [r.topLeft + Offset(m * 0.3, m * 0.3), r.topRight + Offset(-m * 1.3, m * 0.3), r.bottomLeft + Offset(m * 0.3, -m * 2.1), r.bottomRight + Offset(-m * 1.3, -m * 2.1)]) {
      canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, m, m), fill);
    }
    final w = Rect.fromCenter(center: r.center + Offset(0, -m * 0.4), width: r.width * 0.4, height: r.width * 0.4);
    for (var i = 0; i < 8; i++) {
      final a = i / 8;
      canvas.drawLine(_along(w, a), _along(w, a + 0.5 / 8), line);
    }
    canvas.drawLine(Offset(r.left + r.width * 0.2, r.bottom - m * 0.5), Offset(r.right - r.width * 0.2, r.bottom - m * 0.5), line);
  }

  Offset _along(Rect w, double t) {
    final p = (t % 1) * 4;
    final side = p.floor() % 4, f = p - p.floor();
    return switch (side) {
      0 => Offset(w.left + w.width * f, w.top),
      1 => Offset(w.right, w.top + w.height * f),
      2 => Offset(w.right - w.width * f, w.bottom),
      _ => Offset(w.left, w.bottom - w.height * f),
    };
  }

  @override
  bool shouldRepaint(SetupIllustrationPainter old) => old.kind != kind || old.ink != ink || old.accent != accent;
}
