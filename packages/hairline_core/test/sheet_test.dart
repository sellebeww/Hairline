// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  group('5.1 marker ids and corners', () {
    test('sheet s has ids 4s+0..3 in TL, TR, BR, BL order', () {
      for (var s = 0; s < 12; s++) {
        expect(markerIdsForSheet(s), [4 * s, 4 * s + 1, 4 * s + 2, 4 * s + 3]);
        expect(sheetIdOfMarker(4 * s + 3), s);
        expect(markerPositionOfId(4 * s + 2), MarkerPosition.bottomRight);
      }
    });

    test('sheet ids outside 0..11 and marker ids outside 0..47 are rejected', () {
      expect(() => markerIdsForSheet(-1), throwsRangeError);
      expect(() => markerIdsForSheet(12), throwsRangeError);
      expect(() => markerCenterMm(48), throwsRangeError);
      expect(() => markerCenterMm(-1), throwsRangeError);
    });

    test('centres are at (+-60, +-60) mm', () {
      expect(markerCenterMm(0), const Pt(-60, -60));
      expect(markerCenterMm(1), const Pt(60, -60));
      expect(markerCenterMm(2), const Pt(60, 60));
      expect(markerCenterMm(3), const Pt(-60, 60));
      // Same position for the same index on another sheet.
      expect(markerCenterMm(4 * 7 + 2), const Pt(60, 60));
    });

    test('corners are in OpenCV order TL, TR, BR, BL about the centre, side 30', () {
      final c = markerCornersMm(1); // centre (60,-60)
      expect(c, const [Pt(45, -75), Pt(75, -75), Pt(75, -45), Pt(45, -45)]);
    });

    test('print scale multiplies every coordinate', () {
      final c = markerCornersMm(2, printScale: 0.95);
      expect(c[0].x, closeTo(45 * 0.95, 1e-12));
      expect(c[2].y, closeTo(75 * 0.95, 1e-12));
    });

    test('inner marker edge is 45 mm from centre, leaving a 10 mm gap to the cut line', () {
      expect(markerInnerEdgeOffsetMm, 45);
      expect(markerInnerEdgeOffsetMm - windowHalfSizeMm, 10);
      final tl = markerCornersMm(0);
      // BR corner of TL marker is its innermost corner at (-45,-45).
      expect(tl[2], const Pt(-45, -45));
    });
  });

  group('5.1 window and scale bar', () {
    test('window is 70 mm square, measurement zone 50 mm square', () {
      expect(windowHalfSizeMm * 2, 70);
      expect(measurementZoneHalfMm * 2, 50);
      expect(isInsideWindow(const Pt(35, -35)), isTrue);
      expect(isInsideWindow(const Pt(35.01, 0)), isFalse);
      expect(isInsideMeasurementZone(const Pt(25, 25)), isTrue);
      expect(isInsideMeasurementZone(const Pt(0, 25.5)), isFalse);
    });

    test('window bounds scale with print scale', () {
      expect(isInsideWindow(const Pt(36, 0), printScale: 1.05), isTrue);
      expect(isInsideWindow(const Pt(36, 0), printScale: 1.0), isFalse);
    });

    test('scale bar is 100 mm long, below the frame', () {
      final (a, b) = scaleBarEndpointsMm();
      expect(b.x - a.x, 100);
      expect(a.y, b.y);
      expect(a.y, greaterThan(75)); // below bottom marker edge (60 + 15)
    });
  });

  group('5.1 print scale from ruler', () {
    test('L=100 gives scale 1 and u_rel = (0.5/sqrt3)/100', () {
      final r = printScaleFromRuler(100);
      expect(r.printScale, 1.0);
      expect(r.uPrintRel, closeTo(0.5 / sqrt(3) / 100, 1e-15));
      expect(r.uReadingMm, closeTo(0.5 / sqrt(3), 1e-15));
    });

    test('L=95.2 gives scale 0.952 and u_rel = (0.5/sqrt3)/95.2', () {
      final r = printScaleFromRuler(95.2);
      expect(r.printScale, closeTo(0.952, 1e-15));
      expect(r.uPrintRel, closeTo(0.5 / sqrt(3) / 95.2, 1e-15));
      // Magnitude sanity: about 0.30 percent.
      expect(r.uPrintRel, closeTo(0.003032, 1e-6));
    });

    test('implausible readings (cm typed as mm, zero, NaN) are rejected', () {
      for (final v in [0.0, -5.0, 10.0, 79.9, 120.1, 1000.0, double.nan, double.infinity]) {
        expect(() => printScaleFromRuler(v), throwsA(isA<PrintScaleException>()), reason: '$v');
      }
    });

    test('range limits are accepted', () {
      expect(printScaleFromRuler(80).printScale, 0.8);
      expect(printScaleFromRuler(120).printScale, 1.2);
    });
  });
}
