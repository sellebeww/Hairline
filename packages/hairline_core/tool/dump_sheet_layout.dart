// Copyright (c) 2026 Vassel Goleyu. MIT License.
// Prints the filled rectangles of every sheet layout as JSON for tools/verify_sheet_raster.py.
import 'dart:convert';

import 'package:hairline_core/hairline_core.dart';

void main() {
  const labels = SheetLabels(title: 'LEMBAR', cutHint: 'Potong', scaleBar: '100 mm', printNotes: []);
  final out = <Map<String, Object?>>[];
  for (final paper in PaperSize.values) {
    for (var s = 0; s < sheetIdCount; s++) {
      out.add({
        'paper': paper.label,
        'w': paper.widthMm,
        'h': paper.heightMm,
        'sheet': s,
        'rects': [
          for (final r in buildSheetLayout(s, paper, labels).whereType<SheetRect>()) [r.x, r.y, r.w, r.h, r.black ? 1 : 0],
        ],
      });
    }
  }
  print(jsonEncode(out));
}
