// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'aggregate.dart';
import 'frame_ports.dart';
import 'homography.dart';
import 'linalg_small.dart';
import 'measure.dart';
import 'patch.dart';
import 'point.dart';
import 'pose.dart';
import 'psf.dart';
import 'quality.dart';
import 'rejection.dart';
import 'ridge.dart';
import 'sheet.dart';
import 'uncertainty.dart';

/// Everything about the crack and the camera that one frame needs.
final class FrameContext {
  const FrameContext({
    required this.sheetId,
    required this.pointMm,
    required this.directionDeg,
    this.printScale = 1,
    this.focalMm,
    this.sensorLongSideMm,
    this.thresholds = QualityThresholds.standard,
  });

  final int sheetId;

  /// Stored measurement point (sheet mm) and crack direction (degrees).
  final Pt pointMm;
  final double directionDeg;
  final double printScale;

  /// Lens metadata for the approximate intrinsics (5.2); null falls back to a default.
  final double? focalMm;
  final double? sensorLongSideMm;
  final QualityThresholds thresholds;
}

/// Half size (mm at print scale 1) of the crack patch: covers the profile range (3 mm),
/// the segment (2 mm), the tracking radius (1.5 mm) and the saturation box (5 mm).
const double crackPatchHalfMm = 8;

/// A marker patch extends this many pixels beyond the marker outline: the edge profiles
/// reach 10 px past the edge, plus the bicubic support.
const int markerPatchMarginPx = 14;

const int _rectPadPx = 3;

/// Result of [processFrame]: the aggregation input plus everything worth storing.
final class FrameOutcome {
  const FrameOutcome({
    required this.input,
    this.size,
    this.homography,
    this.tiltDeg,
    this.mmPerPx,
    this.geometry,
    this.measurement,
    this.messages = const [],
    this.demotedForMisfit = false,
  });

  /// For `aggregateVisit`.
  final FrameInput input;
  final ImageSize? size;

  /// Null when no homography could be estimated.
  final HomographyEstimate? homography;
  final double? tiltDeg;
  final double? mmPerPx;
  final FrameGeometryVerdict? geometry;

  /// Null unless `measureFrame` ran and accepted the frame.
  final FrameMeasurement? measurement;

  /// Specific user messages (Indonesian) for each rejection.
  final List<String> messages;

  /// The frame measured but showed MODEL_MISFIT, so it is treated as TIDAK_TERUKUR
  /// (D36).
  final bool demotedForMisfit;

  bool get accepted => input.accepted;

  /// JSON for `frames.quality_json` (units: px, mm, degrees).
  Map<String, Object?> qualityJson() {
    final m = measurement;
    return {
      'v': 1,
      'accepted': accepted,
      'markers': homography?.markerCount,
      'tilt_is_approx': true,
      'geometry_warnings': [for (final w in geometry?.warnings ?? const <FrameWarning>[]) w.code],
      'rejections': input.rejectionCodes,
      if (m != null) ...{
        'status': m.status.code,
        'sigma_px': m.psf.sigmaPx,
        'u_sigma_px': m.psf.uSigmaPx,
        'blur_anisotropy': m.psf.anisotropy,
        'saturated_fraction': m.saturatedFraction,
        'patch_noise': m.patchNoise,
        'tracking_offset_mm': m.trackingOffsetMm,
        'warnings': [for (final w in m.warnings) w.code],
        'demoted_for_misfit': demotedForMisfit,
      },
    };
  }
}

/// Serialises a sheet-to-image homography (D5).
Map<String, Object?> homographyToJson(Mat3 h, ImageSize size) => {
      'v': 1,
      'dir': 'sheet_to_image',
      'h': [for (final v in h) v],
      'image': {'w': size.width, 'h': size.height},
    };

/// Inverse of [homographyToJson]; throws [FormatException] for another version or shape.
({Mat3 h, ImageSize size}) homographyFromJson(Map<String, Object?> json) {
  final h = json['h'];
  final image = json['image'];
  if (json['v'] != 1 || json['dir'] != 'sheet_to_image' || h is! List || h.length != 9 || image is! Map) {
    throw const FormatException('Unsupported homography JSON');
  }
  return (h: [for (final v in h) (v as num).toDouble()], size: ImageSize(image['w'] as int, image['h'] as int));
}

/// Processes one photo: decode, detect, homography, geometry gate, patches (marker
/// edges for the PSF and the crack ROI, linearized from sRGB, D26), `measureFrame`.
///
/// Synchronous and free of Flutter, so a worker isolate can run it. Rejections are
/// returned; programming errors and adapter failures propagate. The decoded image is
/// disposed on every path (CLAUDE.md rule 10).
FrameOutcome processFrame({
  required Uint8List encoded,
  required FramePorts ports,
  required FrameContext context,
}) {
  final DecodedImage image;
  try {
    image = ports.source.decode(encoded);
  } on FrameDecodeException {
    return _rejected(FrameRejection.imageUnreadable);
  }
  try {
    return _process(image, ports.detector, context);
  } finally {
    image.dispose();
  }
}

FrameOutcome _rejected(FrameRejection r, {ImageSize? size, HomographyEstimate? est, double? tilt, double? mmPerPx}) =>
    FrameOutcome(
      input: FrameInput.rejected(geometry: [r]),
      size: size,
      homography: est,
      tiltDeg: tilt,
      mmPerPx: mmPerPx,
      messages: [r.message],
    );

FrameOutcome _process(DecodedImage image, MarkerDetector detector, FrameContext ctx) {
  final size = ImageSize(image.width, image.height);
  final detections = detector.detect(image);
  final sheetIds = markerIdsForSheet(ctx.sheetId);
  final usedIds = [for (final d in detections) if (sheetIds.contains(d.id)) d.id];

  final HomographyEstimate est;
  final double tilt;
  final double mmPerPx;
  try {
    est = estimateSheetHomography(detections, sheetId: ctx.sheetId, printScale: ctx.printScale);
    final k = CameraIntrinsics.fromImage(size, focalMm: ctx.focalMm, sensorLongSideMm: ctx.sensorLongSideMm);
    tilt = estimateTilt(est.h, k).tiltDeg;
    mmPerPx = est.localScale(ctx.pointMm).mmPerPx;
  } on TooFewMarkersException {
    return _rejected(FrameRejection.tooFewMarkers, size: size);
  } on HomographyException {
    return _rejected(FrameRejection.homographyFailed, size: size);
  }

  final verdict = evaluateFrameGeometry(
    FrameGeometry(markerCount: est.markerCount, rmsPx: est.rmsPx, looMm: est.looMm, tiltDeg: tilt, mmPerPx: mmPerPx),
    thresholds: ctx.thresholds,
  );
  FrameOutcome withMeasure(FrameInput input, {FrameMeasurement? m, List<String> messages = const [], bool demoted = false}) =>
      FrameOutcome(
        input: input,
        size: size,
        homography: est,
        tiltDeg: tilt,
        mmPerPx: mmPerPx,
        geometry: verdict,
        measurement: m,
        messages: messages,
        demotedForMisfit: demoted,
      );
  if (!verdict.accepted) {
    return withMeasure(
      FrameInput.rejected(geometry: verdict.rejections),
      messages: [for (final r in verdict.rejections) r.message],
    );
  }

  MeasureOutcome outcome;
  try {
    outcome = _measure(image, size, est, usedIds, ctx);
  } on MeasurementException catch (e) {
    outcome = MeasureRejected(e.reason, e.message);
  }
  switch (outcome) {
    case MeasureRejected(:final reason, :final message):
      return withMeasure(FrameInput.rejected(measure: reason), messages: [message]);
    case MeasureAccepted(:final measurement):
      final record = FrameRecord.fromMeasurement(measurement, rmsPx: est.rmsPx, looMm: est.looMm, tiltDeg: tilt);
      final misfit = measurement.warnings.contains(MeasureWarning.modelMisfit) && measurement.status != MeasureStatus.tidakTerukur;
      return withMeasure(
        FrameInput.accepted(misfit ? record.withStatus(MeasureStatus.tidakTerukur) : record),
        m: measurement,
        demoted: misfit,
      );
  }
}

MeasureOutcome _measure(DecodedImage image, ImageSize size, HomographyEstimate est, List<int> usedIds, FrameContext ctx) {
  final markerPatches = <int, GrayPatch>{};
  for (final id in usedIds) {
    final c = markerCenterMm(id, printScale: ctx.printScale);
    final half = markerSideMm / 2 * ctx.printScale + markerPatchMarginPx * est.localScale(c).mmPerPx;
    final p = _extract(image, size, est.h, c, half);
    if (p != null) markerPatches[id] = p;
  }
  final PsfEstimate psf = estimatePsfFromPatches(patches: markerPatches, h: est.h, printScale: ctx.printScale);
  final crack = _extract(image, size, est.h, ctx.pointMm, crackPatchHalfMm * ctx.printScale);
  if (crack == null) {
    return const MeasureRejected(RejectReason.patchTooSmall, 'Titik ukur berada di luar foto. Arahkan kamera ke jendela lembar.');
  }
  return measureFrame(
    patch: crack,
    h: est.h,
    pointMm: ctx.pointMm,
    directionDeg: ctx.directionDeg,
    sheetId: ctx.sheetId,
    printScale: ctx.printScale,
    markerIds: usedIds,
    psf: psf,
    thresholds: ctx.thresholds,
  );
}

/// Linearized patch of the square of half size [halfMm] around [centerMm], clipped to
/// the image; null when fewer than 4 pixels remain in either direction.
GrayPatch? _extract(DecodedImage image, ImageSize size, Mat3 h, Pt centerMm, double halfMm) {
  final xs = <double>[], ys = <double>[];
  try {
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final p = applyHomography(h, Pt(centerMm.x + sx * halfMm, centerMm.y + sy * halfMm));
        xs.add(p.x);
        ys.add(p.y);
      }
    }
  } on DegenerateConfigurationException {
    return null;
  }
  final x0 = max(0, xs.reduce(min).floor() - _rectPadPx), x1 = min(size.width - 1, xs.reduce(max).ceil() + _rectPadPx);
  final y0 = max(0, ys.reduce(min).floor() - _rectPadPx), y1 = min(size.height - 1, ys.reduce(max).ceil() + _rectPadPx);
  if (x1 - x0 + 1 < 4 || y1 - y0 + 1 < 4) return null;
  return image.extractPatch(x0, y0, x1 - x0 + 1, y1 - y0 + 1).linearizedFromSrgb();
}

/// Outcome of [locateCrackPoint]: the sheet-to-image homography of the photo (for the
/// overlay) and, when a tap was given and a crack ridge was found near it, the snapped
/// measurement point and its direction.
final class PointLocation {
  const PointLocation({
    required this.size,
    this.h,
    this.markerCount = 0,
    this.pointMm,
    this.directionDeg,
    this.snr,
    this.message,
  });

  final ImageSize size;

  /// Sheet to image; null when no homography could be estimated (see [message]).
  final Mat3? h;
  final int markerCount;

  /// Snapped point on the crack centreline (sheet mm), and crack direction in `(-90, 90]`.
  final Pt? pointMm;
  final double? directionDeg;

  /// Ridge strength (signal over noise); larger is clearer.
  final double? snr;

  /// Specific user message (Indonesian) when [h] or [pointMm] is missing.
  final String? message;

  bool get located => pointMm != null;
}

/// Radius (mm) around a tap in which the crack ridge is searched. A fingertip is far less
/// exact than the 1.5 mm tracking radius of later visits.
const double tapSearchRadiusMm = 3;

const int _directionTrials = 12;

/// Places the measurement point from a tap (CLAUDE.md 5.3 "Penjejakan", baseline visit).
///
/// Decodes [encoded], estimates the homography, converts [tapPx] (pixels of the decoded
/// photo) to sheet mm, tries 12 crack directions with `findRidge` within
/// [tapSearchRadiusMm], keeps the strongest ridge and refines its centre and direction
/// once more with the usual 1.5 mm radius. Without [tapPx] only the homography is
/// returned (for drawing the overlay). The point must end up inside the central 50 x 50 mm.
PointLocation locateCrackPoint({
  required Uint8List encoded,
  required FramePorts ports,
  required int sheetId,
  required double printScale,
  Pt? tapPx,
}) {
  final DecodedImage image;
  try {
    image = ports.source.decode(encoded);
  } on FrameDecodeException {
    return PointLocation(size: const ImageSize(0, 0), message: FrameRejection.imageUnreadable.message);
  }
  try {
    final size = ImageSize(image.width, image.height);
    final detections = ports.detector.detect(image);
    final HomographyEstimate est;
    try {
      est = estimateSheetHomography(detections, sheetId: sheetId, printScale: printScale);
    } on TooFewMarkersException {
      return PointLocation(size: size, message: FrameRejection.tooFewMarkers.message);
    } on HomographyException {
      return PointLocation(size: size, message: FrameRejection.homographyFailed.message);
    }
    PointLocation fail(String m) => PointLocation(size: size, h: est.h, markerCount: est.markerCount, message: m);
    if (tapPx == null) return PointLocation(size: size, h: est.h, markerCount: est.markerCount);

    final tapMm = est.unproject(tapPx);
    if (!isInsideMeasurementZone(tapMm, printScale: printScale)) {
      return fail('Ketukan berada di luar area ukur. Ketuk retak di dalam jendela, dekat bagian tengah.');
    }
    final patch = _extract(image, size, est.h, tapMm, crackPatchHalfMm * printScale);
    if (patch == null) return fail('Titik yang diketuk berada di luar foto.');

    RidgeResult? first;
    for (var i = 0; i < _directionTrials; i++) {
      try {
        final r = findRidge(
          patch: patch,
          h: est.h,
          pointMm: tapMm,
          directionDeg: i * 180.0 / _directionTrials,
          searchRadiusMm: tapSearchRadiusMm * printScale,
        );
        if (first == null || r.snr > first.snr) first = r;
      } on MeasurementException catch (e) {
        if (e.reason != RejectReason.crackNotFound) rethrow;
      }
    }
    if (first == null) {
      return fail('Retak tidak ditemukan di dekat ketukan. Ketuk tepat di atas retak, atau foto kurang jelas.');
    }
    // Second pass: the direction is now known, so the search is the usual one.
    var best = first;
    try {
      best = findRidge(patch: patch, h: est.h, pointMm: first.centerMm, directionDeg: first.directionDeg);
    } on MeasurementException catch (e) {
      if (e.reason != RejectReason.crackNotFound) rethrow;
    }
    if (!isInsideMeasurementZone(best.centerMm, printScale: printScale)) {
      return fail('Retak terdeteksi, tetapi di luar area ukur 50 x 50 mm. Pilih bagian retak yang lebih dekat ke tengah jendela.');
    }
    var dir = best.directionDeg % 180;
    if (dir > 90) dir -= 180;
    return PointLocation(
      size: size,
      h: est.h,
      markerCount: est.markerCount,
      pointMm: best.centerMm,
      directionDeg: dir,
      snr: best.snr,
    );
  } finally {
    image.dispose();
  }
}
