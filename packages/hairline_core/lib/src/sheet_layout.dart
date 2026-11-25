// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'aruco_bits.dart';
import 'sheet.dart';

// Printable layout of the marker frame sheet (CLAUDE.md 5.1) as device independent
// primitives in page millimetres (origin top-left, y down). The PDF builder of the app
// only maps these to PDF operators, so the geometry is tested here without a PDF library.

/// Paper sizes the sheet can be printed on.
enum PaperSize {
  a4('A4', 210, 297),
  letter('Letter', 215.9, 279.4);

  const PaperSize(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm, heightMm;
}

/// Window centre on the page (mm from the top). The frame spans +-75 mm around it, the
/// scale bar sits 90 mm below it; both fit A4 and Letter with margins above 20 mm.
const double sheetCentreFromTopMm = 100;

/// Cells per marker side: 1 border + 4 data + 1 border (the marker is 30 mm: 5 mm cells).
const int markerGridCells = 6;

/// Stroke widths (mm).
const double cutLineStrokeMm = 0.3;
const double scaleBarStrokeMm = 0.5;

/// Dash pattern of the cut line (mm).
const double cutDashMm = 3, cutGapMm = 2;

sealed class SheetPrimitive {
  const SheetPrimitive();
}

/// A filled rectangle; [black] false draws white (marker data cells).
final class SheetRect extends SheetPrimitive {
  const SheetRect(this.x, this.y, this.w, this.h, {required this.black, this.markerId});
  final double x, y, w, h;
  final bool black;

  /// Marker this rectangle belongs to, if any (tests and diagnostics).
  final int? markerId;
}

/// A stroked line; [dashed] uses [cutDashMm] and [cutGapMm].
final class SheetLine extends SheetPrimitive {
  const SheetLine(this.x1, this.y1, this.x2, this.y2, {required this.strokeMm, this.dashed = false});
  final double x1, y1, x2, y2, strokeMm;
  final bool dashed;
}

enum SheetTextAlign { left, center }

final class SheetText extends SheetPrimitive {
  const SheetText(this.x, this.y, this.text, {required this.sizePt, this.bold = false, this.align = SheetTextAlign.center});

  /// Anchor: baseline y, and x per [align].
  final double x, y;
  final String text;
  final double sizePt;
  final bool bold;
  final SheetTextAlign align;
}

/// Text printed on the sheet (Indonesian, from the app catalog). Latin-1 characters only
/// (the PDF uses a standard font).
final class SheetLabels {
  const SheetLabels({
    required this.title,
    required this.cutHint,
    required this.scaleBar,
    required this.printNotes,
  });

  /// Heading with the sheet number, e.g. "LEMBAR 3".
  final String title;

  /// Short hint next to the cut line.
  final String cutHint;

  /// Caption of the scale bar, e.g. "Batang skala: tepat 100 mm saat dicetak 100 persen".
  final String scaleBar;

  /// Printing instructions below the frame, one line each.
  final List<String> printNotes;
}

/// Builds every primitive of sheet [sheetId] on [paper], at nominal size (print scale 1).
List<SheetPrimitive> buildSheetLayout(int sheetId, PaperSize paper, SheetLabels labels) {
  final ids = markerIdsForSheet(sheetId);
  final cx = paper.widthMm / 2, cy = sheetCentreFromTopMm;
  final out = <SheetPrimitive>[];

  const side = markerSideMm, cell = markerSideMm / markerGridCells;
  for (final id in ids) {
    final c = markerCenterMm(id);
    final x0 = cx + c.x - side / 2, y0 = cy + c.y - side / 2;
    out.add(SheetRect(x0, y0, side, side, black: true, markerId: id));
    final bits = aruco4x4Bits[id];
    for (var r = 0; r < 4; r++) {
      // One white rectangle per run of adjacent white cells in a row.
      var run = 0;
      for (var col = 0; col <= 4; col++) {
        final white = col < 4 && (bits >> (15 - (r * 4 + col))) & 1 == 1;
        if (white) {
          run++;
        } else if (run > 0) {
          out.add(SheetRect(x0 + cell * (1 + col - run), y0 + cell * (1 + r), cell * run, cell, black: false, markerId: id));
          run = 0;
        }
      }
    }
  }

  const h = windowHalfSizeMm;
  final corners = [(cx - h, cy - h), (cx + h, cy - h), (cx + h, cy + h), (cx - h, cy + h)];
  for (var i = 0; i < 4; i++) {
    final (ax, ay) = corners[i];
    final (bx, by) = corners[(i + 1) % 4];
    out.add(SheetLine(ax, ay, bx, by, strokeMm: cutLineStrokeMm, dashed: true));
  }

  final barY = cy + scaleBarCenterYMm;
  const half = scaleBarLengthMm / 2;
  out
    ..add(SheetLine(cx - half, barY, cx + half, barY, strokeMm: scaleBarStrokeMm))
    ..add(SheetLine(cx - half, barY - scaleBarTickHalfMm, cx - half, barY + scaleBarTickHalfMm, strokeMm: scaleBarStrokeMm))
    ..add(SheetLine(cx + half, barY - scaleBarTickHalfMm, cx + half, barY + scaleBarTickHalfMm, strokeMm: scaleBarStrokeMm));

  out
    ..add(SheetText(cx, cy - markerCenterOffsetMm + 2, labels.title, sizePt: 14, bold: true))
    ..add(SheetText(cx, cy - windowHalfSizeMm - 3, labels.cutHint, sizePt: 7))
    ..add(SheetText(cx, barY + scaleBarTickHalfMm + 5, labels.scaleBar, sizePt: 9));
  var y = barY + 22;
  for (final line in labels.printNotes) {
    out.add(SheetText(cx, y, line, sizePt: 9));
    y += 5;
  }
  return out;
}
