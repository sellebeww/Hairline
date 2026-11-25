// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/sheet/sheet_pdf.dart';
import 'package:hairline_core/hairline_core.dart';

/// The `x y w h re` rectangles of the (uncompressed) content stream, in points.
List<List<double>> _rects(String pdf) => [
      for (final m in RegExp(r'(-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) re').allMatches(pdf))
        [for (var i = 1; i <= 4; i++) double.parse(m.group(i)!)],
    ];

void main() {
  for (final paper in PaperSize.values) {
    test('${paper.label}: one page of the paper size; marker squares are 30 mm, 4 per sheet', () async {
      final bytes = await buildSheetPdf(7, paper, compress: false);
      final text = latin1.decode(bytes);
      expect(text, startsWith('%PDF'));
      final box = RegExp(r'/MediaBox ?\[([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)\]').firstMatch(text)!;
      expect(double.parse(box.group(3)!), closeTo(paper.widthMm * ptPerMm, 0.01));
      expect(double.parse(box.group(4)!), closeTo(paper.heightMm * ptPerMm, 0.01));
      expect(RegExp(r'/Type ?/Page[^s]').allMatches(text), hasLength(1), reason: 'one page');

      // Vector dimensions in millimetres: the four big squares measure exactly 30 mm.
      final big = _rects(text).where((r) => (r[2] / ptPerMm - 30).abs() < 0.01 && (r[3] / ptPerMm - 30).abs() < 0.01).toList();
      expect(big, hasLength(4));
      // Their centres are 120 mm apart horizontally (markers at +-60 mm).
      final xs = big.map((r) => r[0] + r[2] / 2).toList()..sort();
      expect((xs.last - xs.first) / ptPerMm, closeTo(120, 0.01));
      // Marker cells are 5 mm or runs of them.
      final cells = _rects(text).where((r) => (r[3] / ptPerMm - 5).abs() < 0.01);
      expect(cells, isNotEmpty);
    });
  }

  test('the compressed (default) PDF is a valid, smaller file', () async {
    final a = await buildSheetPdf(0, PaperSize.a4);
    final b = await buildSheetPdf(0, PaperSize.a4, compress: false);
    expect(latin1.decode(a.sublist(0, 4)), '%PDF');
    expect(a.length, lessThan(b.length));
  });

  test('every sheet id builds; ids outside 0..11 are refused', () async {
    for (var s = 0; s < sheetIdCount; s++) {
      expect((await buildSheetPdf(s, PaperSize.letter)).length, greaterThan(500));
    }
    expect(buildSheetPdf(12, PaperSize.a4), throwsRangeError);
  });
}
