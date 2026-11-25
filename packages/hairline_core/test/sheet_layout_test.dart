// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

const _labels = SheetLabels(title: 'LEMBAR', cutHint: 'Potong', scaleBar: '100 mm', printNotes: ['Cetak 100 persen']);
const _ppm = 8; // raster pixels per mm

/// Rasterizes the filled rectangles (white page, black/white rects in paint order).
({Uint8List gray, int w, int h}) _raster(List<SheetPrimitive> prims, PaperSize paper) {
  final w = (paper.widthMm * _ppm).ceil(), h = (paper.heightMm * _ppm).ceil();
  final g = Uint8List(w * h)..fillRange(0, w * h, 255);
  for (final p in prims.whereType<SheetRect>()) {
    final x0 = (p.x * _ppm).round(), x1 = ((p.x + p.w) * _ppm).round(), y0 = (p.y * _ppm).round(), y1 = ((p.y + p.h) * _ppm).round();
    for (var y = y0; y < y1; y++) {
      g.fillRange(y * w + x0, y * w + x1, p.black ? 0 : 255);
    }
  }
  return (gray: g, w: w, h: h);
}

/// Reads the 6 x 6 cell grid of the marker whose top-left corner is at ([xMm], [yMm]) and
/// returns its inner 16 bits (the border ring must be black), or null if the ring is not.
int? _readMarker(({Uint8List gray, int w, int h}) r, double xMm, double yMm) {
  const cell = markerSideMm / markerGridCells;
  bool white(int row, int col) {
    final px = ((xMm + (col + 0.5) * cell) * _ppm).round(), py = ((yMm + (row + 0.5) * cell) * _ppm).round();
    return r.gray[py * r.w + px] > 127;
  }

  for (var i = 0; i < 6; i++) {
    if (white(0, i) || white(5, i) || white(i, 0) || white(i, 5)) return null;
  }
  var bits = 0;
  for (var row = 1; row <= 4; row++) {
    for (var col = 1; col <= 4; col++) {
      bits = (bits << 1) | (white(row, col) ? 1 : 0);
    }
  }
  return bits;
}

int _rotate90(int bits) {
  var out = 0;
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      final src = (bits >> (15 - (r * 4 + c))) & 1;
      // clockwise: new[c][3 - r] = old[r][c]
      out |= src << (15 - (c * 4 + (3 - r)));
    }
  }
  return out;
}

void main() {
  for (final paper in PaperSize.values) {
    group('sheet layout on ${paper.label}', () {
      for (final sheet in [0, 5, 11]) {
        test('sheet $sheet: the rasterized markers read back as ids 4s..4s+3 at the 5.1 positions', () {
          final prims = buildSheetLayout(sheet, paper, _labels);
          final raster = _raster(prims, paper);
          final cx = paper.widthMm / 2, cy = sheetCentreFromTopMm;
          for (final id in markerIdsForSheet(sheet)) {
            final c = markerCenterMm(id);
            final bits = _readMarker(raster, cx + c.x - 15, cy + c.y - 15);
            expect(bits, isNotNull, reason: 'marker $id has no black border at its 5.1 position');
            expect(bits, aruco4x4Bits[id], reason: 'marker $id');
            // The id is unambiguous: no other id of the dictionary matches in any of the 4 rotations.
            var rot = bits!;
            for (var k = 0; k < 4; k++) {
              final matches = [for (var j = 0; j < aruco4x4Bits.length; j++) if (aruco4x4Bits[j] == rot) j];
              expect(matches, k == 0 ? [id] : isEmpty, reason: 'marker $id rotated $k');
              rot = _rotate90(rot);
            }
          }
        });
      }

      test('vector dimensions are millimetres: markers 30, window 70, scale bar 100, ticks 6', () {
        final prims = buildSheetLayout(3, paper, _labels);
        final cx = paper.widthMm / 2, cy = sheetCentreFromTopMm;
        final blacks = prims.whereType<SheetRect>().where((r) => r.black).toList();
        expect(blacks, hasLength(4));
        for (final b in blacks) {
          expect(b.w, 30);
          expect(b.h, 30);
          final c = markerCenterMm(b.markerId!);
          expect(b.x + 15, closeTo(cx + c.x, 1e-9));
          expect(b.y + 15, closeTo(cy + c.y, 1e-9));
        }
        // Inner marker edge is 45 mm from the centre, the window edge 35 mm: a 10 mm white gap.
        final tl = blacks.firstWhere((b) => b.markerId == 12);
        expect(cx - (tl.x + tl.w), closeTo(45, 1e-9));

        final lines = prims.whereType<SheetLine>().toList();
        final dashed = lines.where((l) => l.dashed).toList();
        expect(dashed, hasLength(4));
        for (final l in dashed) {
          expect((l.x2 - l.x1).abs() + (l.y2 - l.y1).abs(), closeTo(70, 1e-9), reason: 'each cut side is 70 mm');
          for (final v in [l.x1 - cx, l.y1 - cy, l.x2 - cx, l.y2 - cy]) {
            expect(v.abs(), closeTo(35, 1e-9));
          }
        }
        final solid = lines.where((l) => !l.dashed).toList();
        expect(solid, hasLength(3), reason: 'bar and two end ticks');
        final bar = solid.firstWhere((l) => l.y1 == l.y2);
        expect(bar.x2 - bar.x1, closeTo(100, 1e-9));
        expect(bar.y1, cy + 90);
        expect((bar.x1 + bar.x2) / 2, closeTo(cx, 1e-9));
        final ticks = solid.where((l) => l.x1 == l.x2).toList();
        expect(ticks, hasLength(2));
        for (final t in ticks) {
          expect(t.y2 - t.y1, closeTo(6, 1e-9));
          expect(t.x1 == bar.x1 || t.x1 == bar.x2, isTrue);
        }
      });

      test('everything stays on the page with at least 15 mm margins (printable area)', () {
        final prims = buildSheetLayout(11, paper, _labels);
        for (final p in prims) {
          switch (p) {
            case SheetRect():
              expect(p.x, greaterThanOrEqualTo(15));
              expect(p.x + p.w, lessThanOrEqualTo(paper.widthMm - 15));
              expect(p.y, greaterThanOrEqualTo(15));
              expect(p.y + p.h, lessThanOrEqualTo(paper.heightMm - 15));
            case SheetLine():
              expect(p.y1 < paper.heightMm - 15 && p.y2 < paper.heightMm - 15, isTrue);
              expect(p.x1 >= 15 && p.x2 <= paper.widthMm - 15, isTrue);
            case SheetText():
              expect(p.y, inInclusiveRange(10, paper.heightMm - 10));
          }
        }
      });
    });
  }

  test('dictionary table: 48 distinct markers, every ring of 4 rotations unique (no ambiguous id)', () {
    expect(aruco4x4Bits, hasLength(48));
    expect(aruco4x4Bits.toSet(), hasLength(48));
    expect(aruco4x4Bits.first, 0xB532, reason: 'OpenCV DICT_4X4_50 id 0 is bytes 181, 50');
  });

  test('sheet ids outside 0..11 are refused', () {
    expect(() => buildSheetLayout(12, PaperSize.a4, _labels), throwsRangeError);
  });
}
