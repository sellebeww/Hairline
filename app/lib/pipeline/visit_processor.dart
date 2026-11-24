// Copyright (c) 2026 Vassel Goleyu. MIT License.
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

  static VisitResult _aggregate(List<FrameOutcome> outcomes, CrackContext c) => aggregateVisit(
        [for (final o in outcomes) o.input],
        // u_dev stays the unvalidated default until a device validation exists (Phase 7).
        options: UncertaintyOptions(dzMm: c.crack.reliefMm, uPrintRel: c.crack.printScaleURel),
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
    final result = _aggregate(outcomes, crack);
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
        aggregate: _aggregateDraft(result, algorithmVersion),
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
    final result = _aggregate(outcomes, crack);
    if (!result.storable) {
      return VisitNotStored(result: result, frames: outcomes, reasons: _reasons(result, outcomes, photos.length));
    }
    await repository.addReprocessedMeasurements(
      visitId: visitId,
      algorithmVersion: algorithmVersion,
      aggregate: _aggregateDraft(result, algorithmVersion),
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

  static MeasurementDraft _aggregateDraft(VisitResult r, String version) {
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
        'accepted_frames': r.acceptedFrames,
        'excluded_unmeasurable_frames': r.excludedUnmeasurableFrames,
        'frame_rejections': [for (final x in r.frameRejections) {'frame': x.frame, 'code': x.code}],
      }),
    );
  }
}
