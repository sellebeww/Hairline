// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_controller.dart';
import 'package:hairline/capture/capture_page.dart';
import 'package:hairline/debug/demo_seed.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/debug/fake_scenario.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/providers.dart';

/// Pumps real time (isolates and timers do not run inside the fake-async zone of `testWidgets`).
Future<void> _pumpUntil(WidgetTester tester, bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tester.pump();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the capture screen on the fake camera: guidance text, shutter locked until ready, then the quality-gate result', (tester) async {
    await tester.runAsync(() async {
      final scenario = buildFakeScenario(renderCrack: false);
      final tmp = Directory.systemTemp.createTempSync('hairline_page_');
      final camera = scenario.service(frameInterval: const Duration(milliseconds: 20), shotDelay: const Duration(milliseconds: 5));
      final container = ProviderContainer(overrides: [
        appDirectoryProvider.overrideWithValue(tmp),
        framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
        grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
        cameraServiceProvider.overrideWith((ref) {
          ref.onDispose(camera.dispose);
          return camera;
        }),
      ]);
      final id = await seedDemoCrack(container.read(hairlineRepositoryProvider), directionDeg: demoCrackDirectionDeg);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: CapturePage(crackId: id))));

      FilledButton shutter() => tester.widget<FilledButton>(find.byType(FilledButton));
      expect(find.text(Strings.captureTitle), findsOneWidget);
      expect(find.text(Strings.baselineHint), findsNothing, reason: 'hint appears once the camera is open');
      await _pumpUntil(tester, () => find.text(Strings.fakePreview).evaluate().isNotEmpty);
      expect(find.text(Strings.statusWaiting), findsOneWidget);
      expect(shutter().onPressed, isNull, reason: 'no markers, no shutter');
      expect(find.text(Strings.baselineHint), findsOneWidget);

      await _pumpUntil(tester, () => find.text(Strings.statusReady).evaluate().isNotEmpty);
      expect(shutter().onPressed, isNotNull);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(find.text(Strings.shutter));
      await _pumpUntil(tester, () => find.text(Strings.statusResultRejected).evaluate().isNotEmpty);
      expect(find.textContaining('foto diterima'), findsWidgets, reason: 'specific reason from the gate');
      expect(find.text(Strings.retry), findsOneWidget);

      await tester.tap(find.text(Strings.retry));
      await _pumpUntil(tester, () => find.text(Strings.statusReady).evaluate().isNotEmpty);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(camera.disposeCalls, 1);
      tmp.deleteSync(recursive: true);
    });
  });
}
