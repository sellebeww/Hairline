// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

import '../data/frame_storage.dart';
import '../data/repository.dart';
import 'frame_processor.dart';
import 'json_util.dart';

/// Cooperative cancellation of a burst.
final class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Registers [l]; returns the function that removes it.
  void Function() listen(void Function() l) {
    _listeners.add(l);
    return () => _listeners.remove(l);
  }
}

/// The burst was cancelled before anything was stored.
final class VisitCancelledException implements Exception {
  const VisitCancelledException();

  @override
  String toString() => 'VisitCancelledException';
}

/// Camera facts that go into the visit and into the intrinsics approximation (5.2).
final class CameraInfo {
  const CameraInfo({this.focalMm, this.sensorLongSideMm, this.flags = const []});
  final double? focalMm, sensorLongSideMm;

  /// Capture conditions worth keeping with the visit, e.g. `fokus_tidak_terkunci`.
  final List<String> flags;

  Map<String, Object?> toJson() =>
      {'v': 1, 'focal_mm': focalMm, 'sensor_long_side_mm': sensorLongSideMm, 'flags': flags};

  /// Reads `visits.camera_info_json`; anything unreadable gives an empty (default) info.
  factory CameraInfo.fromJsonString(String json) {
    try {
      final m = jsonDecode(json);
      if (m is! Map<String, Object?>) return const CameraInfo();
      final flags = m['flags'];
      return CameraInfo(
        focalMm: (m['focal_mm'] as num?)?.toDouble(),
        sensorLongSideMm: (m['sensor_long_side_mm'] as num?)?.toDouble(),
        flags: flags is List ? [for (final f in flags) '$f'] : const [],
      );
    } on FormatException {
      return const CameraInfo();
    }
  }
}

/// Result of processing a burst or a stored visit.
sealed class VisitOutcome {
  const VisitOutcome({required this.result, required this.frames});
  final VisitResult result;

  /// One outcome per processed photo, in order.
  final List<FrameOutcome> frames;
}

/// The visit was stored (also when the result is "di bawah batas ukur" or "tidak terukur").
final class VisitStored extends VisitOutcome {
  const VisitStored({required super.result, required super.frames, required this.visitId});
  final int visitId;
}

/// Fewer than 3 frames were accepted (5.4): nothing was stored. [reasons] are specific
/// messages (Indonesian) for the retake prompt.
final class VisitNotStored extends VisitOutcome {
  const VisitNotStored({required super.result, required super.frames, required this.reasons});
  final List<String> reasons;
}

/// A stored visit was measured again under a new algorithm version; old rows are intact.
final class VisitReprocessed extends VisitOutcome {
  const VisitReprocessed({required super.result, required super.frames, required this.visitId});
  final int visitId;
}

/// A baseline burst that passed the geometry gate but is not stored yet: the measurement
/// point does not exist until the user taps the crack on [bestIndex] (5.7: the point is
/// chosen on the baseline photo). Held in memory only; nothing is written until confirmed.
final class PendingBaseline {
  const PendingBaseline({
    required this.crackId,
    required this.photos,
    required this.bestIndex,
    required this.deviceModel,
    required this.camera,
    required this.referencePoseJson,
  });

  final int crackId;

  /// The photos whose geometry was accepted (the crack was not looked for yet).
  final List<Uint8List> photos;

  /// Lowest reprojection error of [photos]: the photo the user taps on.
  final int bestIndex;
  final String deviceModel;
  final CameraInfo camera;
  final String? referencePoseJson;

  Uint8List get bestPhoto => photos[bestIndex];
}

sealed class BaselineGate {
  const BaselineGate();
}

/// Enough frames passed the geometry gate: choose the measurement point next.
final class BaselineGateOpen extends BaselineGate {
  const BaselineGateOpen(this.pending);
  final PendingBaseline pending;
}

/// Fewer than 3 frames passed: retake (nothing is kept).
final class BaselineGateClosed extends BaselineGate {
  const BaselineGateClosed(this.outcome);
  final VisitNotStored outcome;
}

/// Turns a burst into a stored visit: frames through the isolate pipeline, `aggregateVisit`
/// from the core, then one transaction. No measurement logic: everything numeric is the core's.
class VisitProcessor {
  VisitProcessor({
    required this.frames,
    required this.repository,
    required this.storage,
    this.algorithmVersion = measurementAlgorithmVersion,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final FrameProcessor frames;
  final HairlineRepository repository;
  final FrameStorage storage;
  final DateTime Function() _now;

  /// Stored in `measurements.algorithm_version`.
  final String algorithmVersion;

  Future<List<FrameOutcome>> _processAll(
    List<Uint8List> photos,
    FrameContext ctx,
    CancelToken? cancel, [
    void Function(int done, int total)? onProgress,
  ]) async {
    final out = <FrameOutcome>[];
    for (final photo in photos) {
      // Sequential on purpose: a 12 MP photo and its decoded copy are big.
      if (cancel?.isCancelled ?? false) throw const VisitCancelledException();
      final job = frames.start(photo, ctx);
      final unlisten = cancel?.listen(job.cancel);
      try {
        out.add(await job.result);
        onProgress?.call(out.length, photos.length);
      } on FrameCancelledException {
        throw const VisitCancelledException();
      } finally {
        unlisten?.call();
      }
    }
    return out;
  }

  static FrameContext _context(CrackContext c, CameraInfo camera) => FrameContext(
        sheetId: c.crack.sheetId,
        pointMm: Pt(c.point.xMm, c.point.yMm),
        directionDeg: c.point.directionDeg,
        printScale: c.crack.printScale,
        focalMm: camera.focalMm,
        sensorLongSideMm: camera.sensorLongSideMm,
      );

  /// `u_dev` comes from the latest PERANGKAT plate run of this phone model, if it validated
  /// the phone; otherwise the unvalidated default stays and the result says BELUM_DIVALIDASI.
  static VisitResult _aggregate(List<FrameOutcome> outcomes, CrackContext c, StoredValidation? validation) => aggregateVisitWithDevice(
        [for (final o in outcomes) o.input],
        options: UncertaintyOptions(dzMm: c.crack.reliefMm, uPrintRel: c.crack.printScaleURel),
        validation: validation?.validation,
      );

  /// Processes the [photos] of one burst for [crackId]. Stores the visit only when the
  /// core accepts it; accepted photos (at most 5) are written to private storage, all
  /// others are dropped. Files are removed again if the database transaction fails.
  Future<VisitOutcome> processBurst({
    required int crackId,
    required List<Uint8List> photos,
    required String deviceModel,
    CameraInfo camera = const CameraInfo(),
    String kind = 'followup',
    String? referencePoseJson,
    CancelToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    final crack = await repository.crackContext(crackId);
    final outcomes = await _processAll(photos, _context(crack, camera), cancel, onProgress);
    final validation = await repository.latestDeviceValidation(deviceModel);
    final result = _aggregate(outcomes, crack, validation);
    if (!result.storable) {
      return VisitNotStored(result: result, frames: outcomes, reasons: _reasons(result, outcomes, photos.length));
    }
    if (cancel?.isCancelled ?? false) throw const VisitCancelledException();

    // The frames the aggregation used: the first accepted ones, at most 5.
    final kept = <int>[
      for (var i = 0; i < outcomes.length; i++)
        if (outcomes[i].accepted) i,
    ].take(QualityThresholds.standard.maxStoredFrames).toList();
    final files = await storage.saveVisitFrames([for (final i in kept) photos[i]]);
    try {
      final visitId = await repository.saveVisit(VisitDraft(
        crackId: crackId,
        tsUtc: _now(),
        kind: kind,
        deviceModel: deviceModel,
        cameraInfoJson: encodeJson(camera.toJson()),
        referencePoseJson: referencePoseJson,
        algorithmVersion: algorithmVersion,
        frames: [for (var n = 0; n < kept.length; n++) _frameDraft(outcomes[kept[n]], files[n])],
        aggregate: _aggregateDraft(result, algorithmVersion, validation),
      ));
      return VisitStored(result: result, frames: outcomes, visitId: visitId);
    } catch (_) {
      // Best effort: a failing cleanup must not hide the original error. Leftovers are
      // swept by FrameStorage.deleteUnreferenced at the next start.
      try {
        await storage.deleteAll([for (final f in files) f.name]);
      } catch (_) {}
      rethrow;
    }
  }

  /// Gate of a baseline burst, before the measurement point exists. Every photo is run
  /// through the pipeline at the window centre; a photo counts when its geometry passes
  /// and the only thing missing is the crack there ("crack not found" is expected: the
  /// user has not tapped it yet). Blur, saturation or geometry failures still reject.
  Future<BaselineGate> gateBaseline({
    required int crackId,
    required List<Uint8List> photos,
    required String deviceModel,
    CameraInfo camera = const CameraInfo(),
    String? referencePoseJson,
    CancelToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    final crack = await repository.crackContext(crackId);
    final outcomes = await _processAll(photos, _context(crack, camera), cancel, onProgress);
    final ok = [
      for (var i = 0; i < outcomes.length; i++)
        if (outcomes[i].accepted || outcomes[i].input.measureRejection == RejectReason.crackNotFound) i,
    ];
    if (ok.length < QualityThresholds.standard.minAcceptedFrames) {
      final result = _aggregate(outcomes, crack, null);
      return BaselineGateClosed(VisitNotStored(result: result, frames: outcomes, reasons: _reasons(result, outcomes, photos.length)));
    }
    var best = ok.first;
    for (final i in ok) {
      if (outcomes[i].homography!.rmsPx < outcomes[best].homography!.rmsPx) best = i;
    }
    return BaselineGateOpen(PendingBaseline(
      crackId: crackId,
      photos: [for (final i in ok) photos[i]],
      bestIndex: ok.indexOf(best),
      deviceModel: deviceModel,
      camera: camera,
      referencePoseJson: referencePoseJson,
    ));
  }

  /// Fixes the measurement point of a crack without visits, then stores the baseline
  /// visit through the full gate and aggregation (the same path as any other visit).
  Future<VisitOutcome> storeBaseline(
    PendingBaseline pending, {
    required Pt pointMm,
    required double directionDeg,
    CancelToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    await repository.updateCrackPoint(crackId: pending.crackId, pointMm: pointMm, directionDeg: directionDeg);
    return processBurst(
      crackId: pending.crackId,
      photos: pending.photos,
      deviceModel: pending.deviceModel,
      camera: pending.camera,
      kind: 'baseline',
      referencePoseJson: pending.referencePoseJson,
      cancel: cancel,
      onProgress: onProgress,
    );
  }

  /// Measures a stored visit again from its photos (new algorithm version, new detection,
  /// new aggregation) and ADDS measurement rows. Rows of earlier versions are untouched.
  Future<VisitOutcome> reprocess(int visitId, {CameraInfo? camera, CancelToken? cancel}) async {
    final visit = await repository.visit(visitId);
    if (visit == null) throw const RepositoryException('Kunjungan tidak ditemukan.');
    final crack = await repository.crackContext(visit.crackId);
    final stored = await repository.framesOfVisit(visitId);
    final photos = <Uint8List>[];
    for (final f in stored) {
      if (!await storage.verify(f.path, f.sha256)) {
        throw const RepositoryException('Berkas foto rusak atau berubah (hash tidak cocok); kunjungan tidak dapat diproses ulang.');
      }
      photos.add(await storage.read(f.path));
    }
    final outcomes = await _processAll(photos, _context(crack, camera ?? const CameraInfo()), cancel);
    final validation = await repository.latestDeviceValidation(visit.deviceModel);
    final result = _aggregate(outcomes, crack, validation);
    if (!result.storable) {
      return VisitNotStored(result: result, frames: outcomes, reasons: _reasons(result, outcomes, photos.length));
    }
    await repository.addReprocessedMeasurements(
      visitId: visitId,
      algorithmVersion: algorithmVersion,
      aggregate: _aggregateDraft(result, algorithmVersion, validation),
      perFrame: {
        for (var i = 0; i < outcomes.length; i++)
          if (outcomes[i].accepted) stored[i].id: _frameMeasurementDraft(outcomes[i]),
      },
    );
    return VisitReprocessed(result: result, frames: outcomes, visitId: visitId);
  }

  static List<String> _reasons(VisitResult r, List<FrameOutcome> outcomes, int total) => [
        'Hanya ${r.acceptedFrames} dari $total foto diterima; dibutuhkan minimal ${QualityThresholds.standard.minAcceptedFrames}. Ulangi pemotretan.',
        ...{for (final o in outcomes) ...o.messages},
      ];

  static FrameDraft _frameDraft(FrameOutcome o, StoredFrame file) {
    final est = o.homography!, m = o.measurement!;
    return FrameDraft(
      path: file.name,
      sha256: file.sha256,
      homographyJson: encodeJson(homographyToJson(est.h, o.size!)),
      rmsPx: est.rmsPx,
      looMm: est.looMm,
      sigmaMm: m.sigmaMm,
      tiltDeg: o.tiltDeg!,
      mmPerPx: o.mmPerPx!,
      qualityJson: encodeJson(o.qualityJson()),
      measurement: _frameMeasurementDraft(o),
    );
  }

  static MeasurementDraft _frameMeasurementDraft(FrameOutcome o) {
    final m = o.measurement!;
    final status = o.input.record!.status; // after the MODEL_MISFIT demotion
    return MeasurementDraft(
      isAggregate: false,
      status: status.code,
      widthMm: status == MeasureStatus.terukur ? m.widthMm : null,
      uRand: m.uFrameMm,
      componentsJson: encodeJson({
        ...m.components,
        'width_estimate_mm': m.widthMm,
        'u_fit_raw': m.fit.uWidthRawMm,
        'rho': m.rho,
        'rho_calibrated': m.rhoCalibrated,
        'floor_mm': m.floorMm,
        'rms_px': o.homography!.rmsPx,
        'loo_mm': o.homography!.looMm,
        'tilt_deg': o.tiltDeg,
        'warnings': [for (final w in m.warnings) w.code],
        'demoted_for_misfit': o.demotedForMisfit,
        'frame_status': m.status.code,
      }),
    );
  }

  static MeasurementDraft _aggregateDraft(VisitResult r, String version, StoredValidation? validation) {
    final b = r.budget;
    final numeric = r.status == VisitStatus.terukur && b != null;
    return MeasurementDraft(
      isAggregate: true,
      status: r.status.code,
      widthMm: numeric ? b.widthMm : null,
      uRand: numeric ? b.uRand : null,
      uSys: numeric ? b.uSys : null,
      uExpanded: numeric ? b.uExpanded : null,
      k: numeric ? b.k : null,
      componentsJson: encodeJson({
        'algorithm_version': version,
        'budget': b?.toJson(),
        'issue': r.issue?.code,
        // The plate run that set u_dev (null: the unvalidated default was used).
        'validation_run_id': b != null && !b.belumDivalidasi ? validation?.id : null,
        'accepted_frames': r.acceptedFrames,
        'excluded_unmeasurable_frames': r.excludedUnmeasurableFrames,
        'frame_rejections': [for (final x in r.frameRejections) {'frame': x.frame, 'code': x.code}],
      }),
    );
  }
}
