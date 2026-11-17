// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'point.dart';

// Sheet geometry, CLAUDE.md 5.1. Sheet frame: mm, origin at the window centre,
// x to the right, y down. All functions take `printScale` (true size / nominal
// size) and multiply every dimension by it.

/// Number of distinct sheets (ids 0..11), 4 markers each, ArUco DICT_4X4_50.
const int sheetIdCount = 12;

/// Marker side including its black border (mm).
const double markerSideMm = 30;

/// Marker centres sit at (+-60, +-60) mm.
const double markerCenterOffsetMm = 60;

/// Distance from the window centre to the inner marker edge: 60 - 30/2 = 45 mm.
const double markerInnerEdgeOffsetMm = markerCenterOffsetMm - markerSideMm / 2;

/// The cut-out window is 70 x 70 mm (half size 35 mm), leaving a 10 mm white gap.
const double windowHalfSizeMm = 35;

/// Measurement point must lie in the central 50 x 50 mm of the window.
const double measurementZoneHalfMm = 25;

/// Scale bar length for print verification (mm).
const double scaleBarLengthMm = 100;

/// Scale bar centre line, below the frame (bottom marker edge is at y=75 mm).
/// Layout choice for Phase 3, see DECISIONS.md.
const double scaleBarCenterYMm = 90;

/// Half height of the scale bar end ticks.
const double scaleBarTickHalfMm = 3;

/// Ruler reading uncertainty half-width (mm), uniform distribution.
const double rulerReadingHalfWidthMm = 0.5;

/// Accepted range of a ruler reading of the 100 mm bar. Outside it the user most
/// likely typed cm instead of mm or measured the wrong thing.
const double minRulerReadingMm = 80;
const double maxRulerReadingMm = 120;

/// Marker slot on the sheet, in id order (4s+index).
enum MarkerPosition { topLeft, topRight, bottomRight, bottomLeft }

/// Thrown for an implausible ruler reading.
final class PrintScaleException implements Exception {
  const PrintScaleException(this.message);
  final String message;

  @override
  String toString() => 'PrintScaleException: $message';
}

/// Result of a ruler reading of the scale bar.
final class PrintScaleReading {
  const PrintScaleReading({
    required this.printScale,
    required this.uPrintRel,
    required this.uReadingMm,
  });

  /// `L_ukur / 100`.
  final double printScale;

  /// Relative standard uncertainty `(0.5/sqrt3) / L_ukur`.
  final double uPrintRel;

  /// Absolute standard uncertainty of the reading (mm).
  final double uReadingMm;
}

PrintScaleReading printScaleFromRuler(double measuredMm) {
  if (!measuredMm.isFinite || measuredMm < minRulerReadingMm || measuredMm > maxRulerReadingMm) {
    throw const PrintScaleException(
      'Pembacaan penggaris di luar rentang $minRulerReadingMm sampai $maxRulerReadingMm mm.',
    );
  }
  final u = rulerReadingHalfWidthMm / sqrt(3);
  return PrintScaleReading(
    printScale: measuredMm / scaleBarLengthMm,
    uPrintRel: u / measuredMm,
    uReadingMm: u,
  );
}

List<int> markerIdsForSheet(int sheetId) {
  if (sheetId < 0 || sheetId >= sheetIdCount) {
    throw RangeError.range(sheetId, 0, sheetIdCount - 1, 'sheetId');
  }
  return [for (var i = 0; i < 4; i++) 4 * sheetId + i];
}

void _checkMarkerId(int id) {
  if (id < 0 || id >= 4 * sheetIdCount) {
    throw RangeError.range(id, 0, 4 * sheetIdCount - 1, 'markerId');
  }
}

int sheetIdOfMarker(int markerId) {
  _checkMarkerId(markerId);
  return markerId ~/ 4;
}

MarkerPosition markerPositionOfId(int markerId) {
  _checkMarkerId(markerId);
  return MarkerPosition.values[markerId % 4];
}

Pt markerCenterMm(int markerId, {double printScale = 1}) {
  const o = markerCenterOffsetMm;
  final c = switch (markerPositionOfId(markerId)) {
    MarkerPosition.topLeft => const Pt(-o, -o),
    MarkerPosition.topRight => const Pt(o, -o),
    MarkerPosition.bottomRight => const Pt(o, o),
    MarkerPosition.bottomLeft => const Pt(-o, o),
  };
  return c * printScale;
}

/// Corners in OpenCV order (TL, TR, BR, BL of the marker itself).
List<Pt> markerCornersMm(int markerId, {double printScale = 1}) {
  final c = markerCenterMm(markerId, printScale: printScale);
  final h = markerSideMm / 2 * printScale;
  return [Pt(c.x - h, c.y - h), Pt(c.x + h, c.y - h), Pt(c.x + h, c.y + h), Pt(c.x - h, c.y + h)];
}

bool isInsideWindow(Pt p, {double printScale = 1}) =>
    p.x.abs() <= windowHalfSizeMm * printScale && p.y.abs() <= windowHalfSizeMm * printScale;

bool isInsideMeasurementZone(Pt p, {double printScale = 1}) =>
    p.x.abs() <= measurementZoneHalfMm * printScale && p.y.abs() <= measurementZoneHalfMm * printScale;

/// Left and right end of the scale bar centre line.
(Pt, Pt) scaleBarEndpointsMm({double printScale = 1}) {
  final h = scaleBarLengthMm / 2 * printScale;
  final y = scaleBarCenterYMm * printScale;
  return (Pt(-h, y), Pt(h, y));
}
