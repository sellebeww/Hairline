// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import '../homography.dart';
import '../point.dart';
import '../sheet.dart';
import 'camera.dart';
import 'noise.dart';

/// Stands in for the OpenCV ArUco detector: returns the exact projected marker
/// corners plus independent Gaussian noise of [noisePx] (std dev, px, per axis).
final class SyntheticDetector {
  SyntheticDetector({this.noisePx = 0, Random? rng}) : _rng = rng ?? Random(0);

  final double noisePx;
  final Random _rng;

  /// Detections for the four markers of [sheetId] as seen by [camera]. [omit]
  /// drops markers by id (occlusion); [shiftPx] displaces all corners of a marker
  /// (a non-planar or distorted marker). The sheet is printed at [printScale].
  List<MarkerDetection> detect(
    SyntheticCamera camera, {
    required int sheetId,
    double printScale = 1,
    Set<int> omit = const {},
    Map<int, Pt> shiftPx = const {},
  }) {
    return [
      for (final id in markerIdsForSheet(sheetId))
        if (!omit.contains(id))
          MarkerDetection(
            id: id,
            corners: [
              for (final c in markerCornersMm(id, printScale: printScale))
                camera.project(c) +
                    (shiftPx[id] ?? const Pt(0, 0)) +
                    (noisePx == 0 ? const Pt(0, 0) : Pt(gaussian(_rng), gaussian(_rng)) * noisePx),
            ],
          ),
    ];
  }
}
