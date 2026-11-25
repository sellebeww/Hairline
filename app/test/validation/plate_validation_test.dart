// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_controller.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/data/database.dart';
import 'package:hairline/data/frame_storage.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/debug/fake_scenario.dart';
import 'package:hairline/pipeline/frame_processor.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/validation/plate_validator.dart';
import 'package:hairline/validation/validation_providers.dart';
import 'package:hairline_core/hairline_core.dart';

import '../support/synthetic_ports.dart';

PlateTruth _characterized(double extra, {double u = 0.01}) => PlateTruth.fromCsv(
    'posisi,lebar_mm,u_mm\n${[for (final l in buildPlateLines()) '${l.id},${(l.nominalMm + extra).toStringAsFixed(4)},$u'].join('\n')}\n');

Future<void> _until(bool Function() cond, {String what = 'condition', int seconds = 60}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeScenario plate, crack;
  // The plate is printed 0.03 mm wider than nominal (the TRUE widths a characterisation would find).
  setUpAll(() {
    plate = buildPlateScenario();
    crack = buildFakeScenario(crackWidthMm: 0.6);
  });

  late AppDatabase db;
  late HairlineRepository repo;
  late Directory root;
  late FrameProcessor frames;
  late PlateValidator validator;
  late VisitProcessor processor;
  final now = DateTime.utc(2026, 11, 25, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = HairlineRepository(db);
    root = Directory.systemTemp.createTempSync('hairline_plate_');
    frames = FrameProcessor(syntheticPorts);
    validator = PlateValidator(frames: frames, repository: repo, algorithmVersion: measurementAlgorithmVersion, now: () => now);
    processor = VisitProcessor(frames: frames, repository: repo, storage: FrameStorage(root), now: () => now);
  });
  tearDown(() async {
    frames.cancelAll();
    await db.close();
    root.deleteSync(recursive: true);
  });

  PlateSetup setup(PlateTruth t) => PlateSetup(truth: t, printScale: 1, printScaleURel: 0.003);

  Future<PlateOutcome> run(PlateTruth t, ValidationSource source, {String model = 'Pixel Uji'}) =>
      validator.run(photos: plate.stills, setup: setup(t), deviceModel: model, source: source);

  /// A visit of the 0.6 mm simulated crack through the window centre, on [model].
  Future<VisitStored> visit(String model) async {
    final site = await repo.createSite(name: 'Uji');
    final id = await repo.createCrack(
      siteId: site,
      label: 'Retak',
      sheetId: 0,
      printScale: 1,
      printScaleURel: 0.003,
      pointMm: const Pt(0, 0),
      directionDeg: demoCrackDirectionDeg,
      createdAt: DateTime.utc(2026, 11, 1),
    );
    final out = await processor.processBurst(crackId: id, photos: crack.stills, deviceModel: model);
    return out as VisitStored;
  }

  test('a PERANGKAT run with a characterized truth is stored, validates, and sets u_dev of the next visit of that model', () async {
    final out = await run(_characterized(0.03), ValidationSource.perangkat) as PlateStored;
    final e = out.evaluation;
    expect(e.stats.reported, greaterThanOrEqualTo(20), reason: 'narrow lines are below the limit at 0.12 mm/px, the rest is measured');
    expect(e.validated, isTrue, reason: e.reasons.join(' | '));
    expect(e.stats.biasMm.abs(), lessThan(0.03));

    final row = (await repo.validationRun(out.runId))!;
    expect((row.source, row.deviceModel, row.tsUtc.toUtc()), ('PERANGKAT', 'Pixel Uji', now));
    expect(row.rmseMm, closeTo(e.stats.rmseMm, 1e-12));

    final before = (await visit('Model Lain')).result.budget!;
    expect(before.belumDivalidasi, isTrue, reason: 'another phone model is not validated');
    final after = (await visit('Pixel Uji')).result.budget!;
    expect(after.belumDivalidasi, isFalse);
    expect(after.uDev, lessThan(before.uDev), reason: 'the measured bias replaces the conservative 0.5 mm/px default');
    expect(after.uDev, greaterThanOrEqualTo(0.01 - 1e-9), reason: 'floored at the median u_truth');
    final agg = (await repo.aggregatesOfVisit((await repo.visitsOfCrack(2)).single.id)).single;
    expect(agg.componentsJson, contains('"validation_run_id":${out.runId}'));
  });

  test('a SINTETIS run is stored with its label and never changes any budget', () async {
    final out = await run(_characterized(0.03), ValidationSource.sintetis) as PlateStored;
    expect((await repo.validationRun(out.runId))!.source, 'SINTETIS');
    expect(await repo.latestDeviceValidation('Pixel Uji'), isNull);
    expect((await visit('Pixel Uji')).result.budget!.belumDivalidasi, isTrue);
  });

  test('NOMINAL truth is stored but never validates: BELUM_DIVALIDASI stays', () async {
    final out = await run(PlateTruth.nominal(), ValidationSource.perangkat) as PlateStored;
    expect(out.evaluation.validated, isFalse);
    expect(out.evaluation.reasons.join(), contains('NOMINAL'));
    expect((await repo.latestDeviceValidation('Pixel Uji'))!.validation.validated, isFalse);
    expect((await visit('Pixel Uji')).result.budget!.belumDivalidasi, isTrue);
  });

  test('the latest PERANGKAT run wins: a newer failed run takes the validation away', () async {
    await run(_characterized(0.03), ValidationSource.perangkat);
    expect((await repo.latestDeviceValidation('Pixel Uji'))!.validation.validated, isTrue);
    final later = PlateValidator(frames: frames, repository: repo, algorithmVersion: measurementAlgorithmVersion, now: () => now.add(const Duration(days: 1)));
    await later.run(photos: plate.stills, setup: setup(PlateTruth.nominal()), deviceModel: 'Pixel Uji', source: ValidationSource.perangkat);
    expect((await repo.latestDeviceValidation('Pixel Uji'))!.validation.validated, isFalse);
  });

  test('photos without markers measure nothing: not stored, specific reasons', () async {
    final out = await validator.run(
      photos: [for (var i = 0; i < 3; i++) blankPhoto(const [])],
      setup: setup(PlateTruth.nominal()),
      deviceModel: 'Pixel Uji',
      source: ValidationSource.perangkat,
    );
    expect(out, isA<PlateNotStored>());
    expect((out as PlateNotStored).reasons.join(' '), contains('Penanda'));
    expect(await repo.validationRuns(), isEmpty);
  });

  test('progress is reported per photo and a cancelled run stores nothing', () async {
    final seen = <int>[];
    await validator.run(photos: plate.stills.take(3).toList(), setup: setup(PlateTruth.nominal()), deviceModel: 'X', source: ValidationSource.sintetis, onProgress: (d, t) => seen.add(d));
    expect(seen, [1, 2, 3]);
    final cancel = CancelToken()..cancel();
    await expectLater(
      validator.run(photos: plate.stills, setup: setup(PlateTruth.nominal()), deviceModel: 'X', source: ValidationSource.sintetis, cancel: cancel),
      throwsA(isA<VisitCancelledException>()),
    );
    expect(await repo.validationRuns(), hasLength(1));
  });

  test('the capture flow in validation mode (FakeCameraService): ends in "validated", stored as SINTETIS', () async {
    final camera = plate.service(frameInterval: const Duration(milliseconds: 20), shotDelay: const Duration(milliseconds: 5));
    final dir = Directory.systemTemp.createTempSync('hairline_plate_flow_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
      cameraServiceProvider.overrideWith((ref) {
        ref.onDispose(camera.dispose);
        return camera;
      }),
    ]);
    addTearDown(c.dispose);
    c.read(validationSetupProvider.notifier).use(setup(_characterized(0.03)));
    c.listen(captureControllerProvider(validationCaptureId), (_, _) {}, fireImmediately: true);
    await _until(() => c.read(captureControllerProvider(validationCaptureId)).flow.canShoot, what: 'plate ready');
    await c.read(captureControllerProvider(validationCaptureId).notifier).shutter();
    final flow = c.read(captureControllerProvider(validationCaptureId)).flow;
    expect(flow.phase, CapturePhase.validated);
    final r = c.read(hairlineRepositoryProvider);
    final row = (await r.validationRun(flow.validationRunId!))!;
    expect(row.source, 'SINTETIS', reason: 'a simulated camera can never store PERANGKAT');
    expect(row.deviceModel, 'Simulasi');
    expect(await r.latestDeviceValidation('Simulasi'), isNull);
  });

  test('without a setup the validation capture fails with a specific message instead of crashing', () async {
    final camera = plate.service();
    final dir = Directory.systemTemp.createTempSync('hairline_plate_flow2_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
      cameraServiceProvider.overrideWith((ref) {
        ref.onDispose(camera.dispose);
        return camera;
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(captureControllerProvider(validationCaptureId), (_, _) {}, fireImmediately: true);
    await _until(() => c.read(captureControllerProvider(validationCaptureId)).flow.phase == CapturePhase.error, what: 'error');
  });
}
