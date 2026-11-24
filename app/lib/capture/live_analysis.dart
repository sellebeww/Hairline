// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';

import 'reference_pose.dart';

/// Markers found in one live frame, as the detection isolate reports them: corners in
/// the pixel grid of the decimated buffer.
final class DetectionResult {
  const DetectionResult({
    required this.markers,
    required this.width,
    required this.height,
    required this.step,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.detectMicros,
  });

  final List<MarkerDetection> markers;
  final int width;
  final int height;
  final int step;
  final int sourceWidth;
  final int sourceHeight;

  /// Time spent in the detector (diagnostics).
  final int detectMicros;

  /// A point of the decimated grid in source pixels (see `LumaFrame.toSource`).
  Pt toSource(Pt p) => Pt(p.x * step + step ~/ 2, p.y * step + step ~/ 2);
}

/// Clockwise quarter turns that bring a sensor-oriented image upright (`sensorOrientation / 90`).
Pt rotateUpright(Pt p, int sourceWidth, int sourceHeight, int quarterTurns) => switch (quarterTurns & 3) {
      0 => p,
      1 => Pt(sourceHeight - 1 - p.y, p.x),
      2 => Pt(sourceWidth - 1 - p.x, sourceHeight - 1 - p.y),
      _ => Pt(p.y, sourceWidth - 1 - p.x),
    };

ImageSize uprightSize(int sourceWidth, int sourceHeight, int quarterTurns) =>
    quarterTurns.isOdd ? ImageSize(sourceHeight, sourceWidth) : ImageSize(sourceWidth, sourceHeight);

/// What the overlay and the capture gate know about one live frame. Coordinates are in
/// the upright live frame ([size]).
final class LiveAnalysis {
  const LiveAnalysis({
    required this.size,
    required this.markers,
    required this.markerCount,
    required this.geometryRejections,
    required this.instructions,
    required this.steady,
    this.estimate,
    this.pose,
    this.deviation,
    this.tiltDeg,
    this.mmPerPx,
    this.windowQuad,
    this.pointPx,
    this.ghost = const [],
  });

  final ImageSize size;

  /// Sheet markers found (corner quads), for the outline.
  final List<List<Pt>> markers;
  final int markerCount;

  /// The geometry gate of 5.4 applied to this frame; empty means it would pass.
  final List<FrameRejection> geometryRejections;

  /// What to do next, most important first; empty with a passing gate means ready.
  final List<PoseInstruction> instructions;

  /// The pose is within the stability thresholds of the previous frame.
  final bool steady;

  final HomographyEstimate? estimate;
  final PoseState? pose;

  /// Null on the baseline visit (no reference).
  final PoseDeviation? deviation;
  final double? tiltDeg;
  final double? mmPerPx;

  /// Cut-out window and the measurement point in the image.
  final List<Pt>? windowQuad;
  final Pt? pointPx;

  /// The markers where the reference visit had them (empty without a reference).
  final List<List<Pt>> ghost;

  bool get geometryOk => geometryRejections.isEmpty && estimate != null;

  /// The frame itself is good to shoot: gate passes and the pose matches the reference.
  bool get ready => geometryOk && instructions.isEmpty;
}

/// Turns detections into pose guidance, per frame. Stateful only through the previous
/// pose (stability). Runs on the UI isolate: a 4-marker homography with leave-one-out
/// costs well under a millisecond in Dart, far below the frame interval.
final class LiveAnalyzer {
  LiveAnalyzer({
    required this.sheetId,
    required this.printScale,
    required this.pointMm,
    required this.quarterTurns,
    this.reference,
    this.focalMm,
    this.sensorLongSideMm,
    this.thresholds = QualityThresholds.standard,
    this.poseThresholds = PoseThresholds.standard,
    this.stabilityThresholds = defaultStability,
  });

  /// Frame-to-frame limits for "the phone is still" (starting values, not tuned on a
  /// device): about 1 percent of the diagonal per frame is a slow drift at 10 fps.
  static const PoseThresholds defaultStability = PoseThresholds(
    maxTranslationFrac: 0.01,
    minScaleRatio: 0.97,
    maxScaleRatio: 1.03,
    maxRotationDeg: 2,
    maxTiltDeltaDeg: 3,
  );

  final int sheetId;
  final double printScale;
  final Pt pointMm;
  final int quarterTurns;
  final ReferencePose? reference;
  final double? focalMm;
  final double? sensorLongSideMm;
  final QualityThresholds thresholds;
  final PoseThresholds poseThresholds;
  final PoseThresholds stabilityThresholds;

  PoseState? _previous;

  /// The baseline reference built from [a] (call with the analysis that was ready).
  static ReferencePose? referenceFrom(LiveAnalysis a) {
    final e = a.estimate, p = a.pose;
    return e == null || p == null ? null : ReferencePose.fromEstimate(h: e.h, pose: p, size: a.size);
  }

  LiveAnalysis analyze(DetectionResult r) {
    final size = uprightSize(r.sourceWidth, r.sourceHeight, quarterTurns);
    final ids = markerIdsForSheet(sheetId);
    final detections = <MarkerDetection>[];
    for (final d in r.markers) {
      if (!ids.contains(d.id)) continue;
      detections.add(MarkerDetection(
        id: d.id,
        corners: [for (final c in d.corners) rotateUpright(r.toSource(c), r.sourceWidth, r.sourceHeight, quarterTurns)],
      ));
    }
    final quads = [for (final d in detections) d.corners];

    LiveAnalysis lost(List<FrameRejection> why) {
      _previous = null;
      return LiveAnalysis(
        size: size,
        markers: quads,
        markerCount: detections.length,
        geometryRejections: why,
        instructions: const [],
        steady: false,
      );
    }

    final HomographyEstimate est;
    final PoseState pose;
    final double tilt, mmPerPx;
    try {
      est = estimateSheetHomography(detections, sheetId: sheetId, printScale: printScale);
      final k = CameraIntrinsics.fromImage(size, focalMm: focalMm, sensorLongSideMm: sensorLongSideMm);
      pose = poseStateFromHomography(est.h, k);
      tilt = pose.tiltDeg;
      mmPerPx = est.localScale(pointMm).mmPerPx;
    } on TooFewMarkersException {
      return lost(const [FrameRejection.tooFewMarkers]);
    } on HomographyException {
      return lost(const [FrameRejection.homographyFailed]);
    }

    final verdict = evaluateFrameGeometry(
      FrameGeometry(markerCount: est.markerCount, rmsPx: est.rmsPx, looMm: est.looMm, tiltDeg: tilt, mmPerPx: mmPerPx),
      thresholds: thresholds,
    );

    final ref = reference;
    final comparable = ref != null && ref.isCompatibleWith(size);
    final PoseDeviation? deviation = comparable ? comparePose(pose, ref.poseAt(size), size, thresholds: poseThresholds) : null;
    final instructions = <PoseInstruction>[
      if (deviation != null) ...deviation.instructions else if (tilt > poseThresholds.maxTiltDeltaDeg) PoseInstruction.holdFlat,
      if (verdict.rejections.contains(FrameRejection.resolutionTooCoarse) && !(deviation?.instructions.contains(PoseInstruction.closer) ?? false))
        PoseInstruction.closer,
    ];

    final prev = _previous;
    final steady = prev != null && comparePose(pose, prev, size, thresholds: stabilityThresholds).isReady;
    _previous = pose;

    const o = windowHalfSizeMm;
    return LiveAnalysis(
      size: size,
      markers: quads,
      markerCount: detections.length,
      geometryRejections: verdict.rejections,
      instructions: instructions,
      steady: steady,
      estimate: est,
      pose: pose,
      deviation: deviation,
      tiltDeg: tilt,
      mmPerPx: mmPerPx,
      windowQuad: [
        for (final c in const [Pt(-o, -o), Pt(o, -o), Pt(o, o), Pt(-o, o)]) est.project(c * printScale),
      ],
      pointPx: est.project(pointMm),
      ghost: comparable ? ref.ghostMarkers(size, sheetId: sheetId, printScale: printScale) : const [],
    );
  }

  /// Forgets the previous pose (after a pause or a retake).
  void reset() => _previous = null;
}
