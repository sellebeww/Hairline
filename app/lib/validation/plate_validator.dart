// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

import '../data/repository.dart';
import '../pipeline/frame_processor.dart';
import '../pipeline/json_util.dart';
import '../pipeline/visit_processor.dart';

/// What the owner set up before a validation: the plate truth and its print scale.
final class PlateSetup {
  const PlateSetup({required this.truth, required this.printScale, required this.printScaleURel});
  final PlateTruth truth;
  final double printScale, printScaleURel;
}

sealed class PlateOutcome {
  const PlateOutcome();
}

/// The run was stored; [evaluation] holds the statistics and the verdict.
final class PlateStored extends PlateOutcome {
  const PlateStored({required this.runId, required this.evaluation});
  final int runId;
  final PlateEvaluation evaluation;
}

/// Nothing was stored: no line could be measured. [reasons] are specific (Indonesian).
final class PlateNotStored extends PlateOutcome {
  const PlateNotStored(this.reasons);
  final List<String> reasons;
}

/// Measures every line of the validation plate on the photos of a burst and stores the run.
/// All numbers come from the core (`processFramePoints`, `evaluatePlate`).
class PlateValidator {
  PlateValidator({
    required this.frames,
    required this.repository,
    required this.algorithmVersion,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final FrameProcessor frames;
  final HairlineRepository repository;
  final String algorithmVersion;
  final DateTime Function() _now;

  Future<PlateOutcome> run({
    required List<Uint8List> photos,
    required PlateSetup setup,
    required String deviceModel,
    required ValidationSource source,
    CameraInfo camera = const CameraInfo(),
    CancelToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    final lines = [for (final l in buildPlateLines()) if (setup.truth.lines.containsKey(l.id)) l];
    final ctx = FrameContext(
      sheetId: plateSheetId,
      pointMm: const Pt(0, 0),
      directionDeg: 0,
      printScale: setup.printScale,
      focalMm: camera.focalMm,
      sensorLongSideMm: camera.sensorLongSideMm,
    );
    final points = [for (final l in lines) FramePoint(l.centreMm, l.directionDeg)];
    final perLine = {for (final l in lines) l.id: <FrameInput>[]};
    final messages = <String>{};
    var done = 0;
    for (final photo in photos) {
      // Sequential on purpose: a 12 MP photo and its decoded copy are big.
      if (cancel?.isCancelled ?? false) throw const VisitCancelledException();
      final job = frames.startPoints(photo, ctx, points);
      final unlisten = cancel?.listen(job.cancel);
      try {
        final outcomes = await job.result;
        for (var i = 0; i < lines.length; i++) {
          perLine[lines[i].id]!.add(outcomes[i].input);
          messages.addAll(outcomes[i].messages);
        }
        onProgress?.call(++done, photos.length);
      } on FrameCancelledException {
        throw const VisitCancelledException();
      } finally {
        unlisten?.call();
      }
    }
    final evaluation = evaluatePlate(
      truth: setup.truth,
      frames: perLine,
      options: UncertaintyOptions(uPrintRel: setup.printScaleURel),
    );
    if (evaluation.stats.reported == 0) {
      return PlateNotStored([
        'Tidak satu pun garis pelat dapat diukur dari ${photos.length} foto. Ulangi pemotretan.',
        ...messages,
      ]);
    }
    final runId = await repository.saveValidationRun(
      deviceModel: deviceModel,
      tsUtc: _now(),
      plateTruthJson: encodeJson({
        'v': 1,
        'truth': setup.truth.toJson(),
        'print_scale': setup.printScale,
        'print_scale_u_rel': setup.printScaleURel,
        'camera': camera.toJson(),
      }),
      resultsJson: encodeJson(evaluation.toJson()),
      biasMm: evaluation.stats.biasMm,
      rmseMm: evaluation.stats.rmseMm,
      coverage: evaluation.stats.coverage,
      algorithmVersion: algorithmVersion,
      source: source,
    );
    return PlateStored(runId: runId, evaluation: evaluation);
  }
}
