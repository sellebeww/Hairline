// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import '../patch.dart';
import '../point.dart';
import '../sheet.dart';
import 'camera.dart';
import 'render.dart';

/// Renders the part of [scene] seen by [camera] over the sheet-space square of half
/// size [halfSizeMm] around [centerMm], as a [GrayPatch] with the right image
/// origin. The patch is the bounding box (in pixels) of the projected square, so a
/// tilted view yields a larger patch. Ground truth stays exact: the scene is
/// evaluated through the camera's exact inverse homography.
GrayPatch renderCrackPatch({
  required SyntheticCamera camera,
  required Scene scene,
  Pt centerMm = const Pt(0, 0),
  double halfSizeMm = 9,
  int supersample = 4,
  double psfSigmaPx = 0,
  double? psfSigmaYPx,
  double illumGradX = 0,
  double illumGradY = 0,
  double noiseSigma = 0,
  Random? rng,
  bool quantize8bit = true,
}) {
  final corners = [
    for (final sx in [-1.0, 1.0])
      for (final sy in [-1.0, 1.0]) camera.project(Pt(centerMm.x + sx * halfSizeMm, centerMm.y + sy * halfSizeMm)),
  ];
  final x0 = corners.map((c) => c.x).reduce(min).floor();
  final y0 = corners.map((c) => c.y).reduce(min).floor();
  final x1 = corners.map((c) => c.x).reduce(max).ceil();
  final y1 = corners.map((c) => c.y).reduce(max).ceil();
  final img = renderGray(
    width: x1 - x0 + 1,
    height: y1 - y0 + 1,
    toScene: (px, py) => camera.unproject(Pt(px + x0, py + y0)),
    scene: scene,
    supersample: supersample,
    psfSigmaPx: psfSigmaPx,
    psfSigmaYPx: psfSigmaYPx,
    illumGradX: illumGradX,
    illumGradY: illumGradY,
    noiseSigma: noiseSigma,
    rng: rng,
    quantize8bit: quantize8bit,
  );
  return GrayPatch(originX: x0, originY: y0, width: img.width, height: img.height, data: img.data);
}

/// Sheet markers (solid ink) over a crack scene: inside a marker square the ink
/// intensity, elsewhere [crack]. Paper is the crack scene's own background.
Scene sheetWithCrackScene({required int sheetId, required Scene crack, double printScale = 1, double ink = 0.05}) {
  final h = markerSideMm / 2 * printScale;
  final centers = [for (final id in markerIdsForSheet(sheetId)) markerCenterMm(id, printScale: printScale)];
  return (x, y) {
    for (final c in centers) {
      if ((x - c.x).abs() <= h && (y - c.y).abs() <= h) return ink;
    }
    return crack(x, y);
  };
}
