// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_controller.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/capture/pending_baseline.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/debug/fake_scenario.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/screens/point_controller.dart';
import 'package:hairline/screens/queries.dart';
import 'package:hairline_core/hairline_core.dart';

Future<void> _until(bool Function() cond, {String what = 'condition', int seconds = 40}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The whole MVP chain on synthetic photos (SINTETIS, no camera, no phone): crack created,
/// baseline captured, measurement point tapped and snapped, two follow-up visits with a
/// widening crack, trend flags "kemungkinan bertambah lebar".
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const widths = [0.5, 1.0, 1.6]; // mm, baseline then two follow-ups
  late List<FakeScenario> scenarios;
  late Directory dir;

  setUpAll(() => scenarios = [for (final w in widths) buildFakeScenario(crackWidthMm: w)]);

  ProviderContainer open(FakeScenario s) {
    final camera = s.service(frameInterval: const Duration(milliseconds: 20), shotDelay: const Duration(milliseconds: 5));
    return ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
      cameraServiceProvider.overrideWith((ref) {
        ref.onDispose(camera.dispose);
        return camera;
      }),
    ]);
  }

  test('baseline -> measurement point -> two wider follow-ups -> trend', () async {
    dir = Directory.systemTemp.createTempSync('hairline_e2e_');
    addTearDown(() => dir.deleteSync(recursive: true));

    // Crack creation (what the guided setup saves): provisional point, scale from a 100.0 mm reading.
    var c = open(scenarios[0]);
    final reading = printScaleFromRuler(100);
    final repo = c.read(hairlineRepositoryProvider);
    final site = await repo.createSite(name: 'Situs uji');
    final crackId = await repo.createCrack(
      siteId: site,
      label: 'Retak uji',
      sheetId: 0,
      printScale: reading.printScale,
      printScaleURel: reading.uPrintRel,
      pointMm: const Pt(0, 0),
      directionDeg: 0,
      createdAt: DateTime.now().toUtc(),
    );

    // Baseline capture: only the geometry is gated, nothing is stored yet.
    c.listen(captureControllerProvider(crackId), (_, _) {}, fireImmediately: true);
    await _until(() => c.read(captureControllerProvider(crackId)).flow.canShoot, what: 'baseline ready');
    await c.read(captureControllerProvider(crackId).notifier).shutter();
    expect(c.read(captureControllerProvider(crackId)).flow.phase, CapturePhase.baselineCaptured);
    expect(await repo.visitsOfCrack(crackId), isEmpty, reason: 'no visit before the point exists');
    expect(c.read(pendingBaselinesProvider)[crackId], isNotNull);

    // Measurement point: tap 1 mm beside the true crack (through the origin), then confirm.
    c.listen(pointControllerProvider(crackId), (_, _) {}, fireImmediately: true);
    await _until(() => c.read(pointControllerProvider(crackId)).phase == PointPhase.ready, what: 'point screen ready');
    final h = c.read(pointControllerProvider(crackId)).base!.h!;
    await c.read(pointControllerProvider(crackId).notifier).tap(applyHomography(h, const Pt(0.3, 0.9)));
    await _until(() => c.read(pointControllerProvider(crackId)).phase == PointPhase.ready && c.read(pointControllerProvider(crackId)).located != null, what: 'point located');
    final located = c.read(pointControllerProvider(crackId)).located!;
    final a = demoCrackDirectionDeg * pi / 180;
    final offLine = (located.pointMm!.x * -sin(a) + located.pointMm!.y * cos(a)).abs();
    expect(offLine, lessThan(0.1), reason: 'the snapped point lies on the crack line through the origin');
    expect((located.directionDeg! - demoCrackDirectionDeg).abs(), lessThan(3));
    await c.read(pointControllerProvider(crackId).notifier).confirm();
    await _until(() => c.read(pointControllerProvider(crackId)).phase == PointPhase.saved, what: 'baseline stored');
    final ctx = await repo.crackContext(crackId);
    expect(ctx.point.xMm, closeTo(located.pointMm!.x, 1e-9));
    expect((await repo.visitsOfCrack(crackId)).single.kind, 'baseline');
    expect(c.read(pendingBaselinesProvider), isEmpty);
    c.dispose();

    // Two follow-ups, each on a new screen session.
    for (final s in scenarios.skip(1)) {
      c = open(s);
      c.listen(captureControllerProvider(crackId), (_, _) {}, fireImmediately: true);
      await _until(() => c.read(captureControllerProvider(crackId)).flow.canShoot, what: 'follow-up ready');
      expect(c.read(captureControllerProvider(crackId)).flow.analysis!.ghost, hasLength(4));
      await c.read(captureControllerProvider(crackId).notifier).shutter();
      expect(c.read(captureControllerProvider(crackId)).flow.outcome, isA<VisitStored>());
      c.dispose();
    }

    // Trend.
    c = open(scenarios[0]);
    addTearDown(c.dispose);
    final trend = (await c.read(trendProvider(crackId).future))!;
    expect(trend.entries, hasLength(3));
    final widths3 = [for (final e in trend.entries) e.entry.aggregate!.widthMm];
    expect(widths3.every((w) => w != null), isTrue, reason: 'all three visits measured: $widths3');
    expect(widths3[0]!, lessThan(widths3[1]!));
    expect(widths3[1]!, lessThan(widths3[2]!));
    final last = trend.entries.last.point.vsBaseline!;
    expect(last.classification, TrendClass.kemungkinanBertambahLebar, reason: 'delta ${last.delta} u_delta ${last.uDelta} z ${last.z}');
    expect(Strings.trendClass(last.classification), 'Kemungkinan bertambah lebar');
    expect(trend.outdatedVisitIds, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
