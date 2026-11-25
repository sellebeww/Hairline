// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

import 'frame_processor.dart';

/// Runs `locateCrackPoint` in a short-lived isolate: decoding a 12 MP photo and searching
/// the ridge must not block the UI isolate, and native handles stay inside the worker.
class PointLocator {
  const PointLocator(this._factory);
  final FramePortsFactory _factory;

  /// Without [tapPx] only the homography of the photo is computed (for the overlay).
  Future<PointLocation> locate({
    required Uint8List photo,
    required int sheetId,
    required double printScale,
    Pt? tapPx,
  }) =>
      _run(_factory, photo, sheetId, printScale, tapPx);

  static Future<PointLocation> _run(FramePortsFactory factory, Uint8List photo, int sheetId, double printScale, Pt? tapPx) =>
      Isolate.run(() => locateCrackPoint(encoded: photo, ports: factory(), sheetId: sheetId, printScale: printScale, tapPx: tapPx));
}
