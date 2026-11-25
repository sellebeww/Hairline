// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/camera_service.dart';
import 'package:hairline/capture/capture_controller.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/capture/fake_camera_service.dart';
import 'package:hairline/debug/demo_seed.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/debug/fake_scenario.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline/providers.dart';

Future<void> _until(bool Function() cond, {String what = 'condition', int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeScenario flat;
  late Directory tmp;
  late FakeCameraService camera;
  late ProviderContainer c;
  late int crackId;
  final phases = <CapturePhase>[];

  setUpAll(() => flat = buildFakeScenario(renderCrack: false));

  Future<void> open(FakeScenario scenario, {FakeCameraService? cam, bool withDetector = true}) async {
    tmp = Directory.systemTemp.createTempSync('hairline_capture_');
    camera = cam ?? scenario.service(frameInterval: const Duration(milliseconds: 20), shotDelay: const Duration(milliseconds: 5));
    c = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(tmp),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      if (withDetector) grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
      cameraServiceProvider.overrideWith((ref) {
        ref.onDispose(camera.dispose);
        return camera;
      }),
    ]);
    crackId = await seedDemoCrack(c.read(hairlineRepositoryProvider), directionDeg: demoCrackDirectionDeg);
    phases.clear();
    c.listen(captureControllerProvider(crackId), (prev, next) {
      if (phases.isEmpty || phases.last != next.flow.phase) phases.add(next.flow.phase);
    }, fireImmediately: true);
  }

  CaptureUiState ui() => c.read(captureControllerProvider(crackId));
  CaptureController ctl() => c.read(captureControllerProvider(crackId).notifier);

  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('guided flow on the fake camera (flat stills: the quality gate must reject)', () {
    test('waiting, adjusting, ready; the shutter runs burst and processing; nothing is stored', () async {
      await open(flat);
      await _until(() => ui().flow.canShoot, what: 'ready');
      expect(phases.first, CapturePhase.waitingForMarkers);
      expect(phases, containsAllInOrder([CapturePhase.waitingForMarkers, CapturePhase.adjusting, CapturePhase.ready]));
      expect(ui().isBaseline, isTrue);

      await ctl().shutter();
      expect(phases, containsAllInOrder([CapturePhase.ready, CapturePhase.burst, CapturePhase.processing, CapturePhase.result]));
      final outcome = ui().flow.outcome!;
      expect(outcome, isA<VisitNotStored>());
      expect((outcome as VisitNotStored).reasons, isNotEmpty);
      expect(outcome.reasons.first, contains('foto diterima'));
      expect(ui().flow.processDone, 6);

      // A visit that failed the gate is never stored as a measurement (5.4).
      expect(await c.read(hairlineRepositoryProvider).visitsOfCrack(crackId), isEmpty);
      final frames = Directory('${tmp.path}/frames');
      expect(!frames.existsSync() || frames.listSync().isEmpty, isTrue);
      expect(camera.burstCalls, 1);
      expect(camera.isStreaming, isTrue, reason: 'the stream resumes after the burst');
    });

    test('the shutter does nothing before the pose is ready', () async {
      await open(flat);
      await ctl().shutter();
      expect(camera.burstCalls, 0);
      expect(ui().flow.phase, isNot(CapturePhase.burst));
    });

    test('retry after a rejected visit goes back to waiting and can reach ready again', () async {
      await open(flat);
      await _until(() => ui().flow.canShoot);
      await ctl().shutter();
      await ctl().retry();
      expect(ui().flow.phase, CapturePhase.waitingForMarkers);
      await _until(() => ui().flow.canShoot, what: 'ready again');
    });

    test('an interrupted burst (call, app switch) is an error with a specific message; retry recovers', () async {
      await open(flat);
      await _until(() => ui().flow.canShoot);
      camera.failNextBurst = const CameraFailure(CameraFailureKind.interrupted);
      await ctl().shutter();
      expect(ui().flow.phase, CapturePhase.error);
      expect(ui().flow.error, Strings.errCameraInterrupted);
      await ctl().retry();
      await _until(() => ui().flow.canShoot, what: 'ready after retry');
      await ctl().shutter();
      expect(ui().flow.phase, CapturePhase.result);
    });

    test('a denied camera permission shows its own message and never starts the flow', () async {
      await open(
        flat,
        cam: FakeCameraService(frames: flat.live, stills: flat.stills, initializeFailure: const CameraFailure(CameraFailureKind.permissionDenied)),
      );
      await _until(() => ui().flow.phase == CapturePhase.error);
      expect(ui().flow.error, Strings.errPermissionDenied);
      expect(ui().starting, isFalse);
    });

    test('without a live detector the error says so instead of failing silently', () async {
      await open(flat, withDetector: false);
      await _until(() => ui().flow.phase == CapturePhase.error);
      expect(ui().flow.error, Strings.errDetector);
    });

    test('a missing crack is reported in Indonesian', () async {
      await open(flat);
      const missing = 9999;
      c.listen(captureControllerProvider(missing), (_, _) {}, fireImmediately: true);
      await _until(() => c.read(captureControllerProvider(missing)).flow.phase == CapturePhase.error);
      expect(c.read(captureControllerProvider(missing)).flow.error, contains('Retak tidak ditemukan'));
    });

    test('app lifecycle: paused releases the camera and disarms the shutter; resumed reopens', () async {
      await open(flat);
      await _until(() => ui().flow.canShoot);
      await ctl().onLifecycle(AppLifecycleState.inactive);
      expect(camera.pauseCalls, 1);
      expect(camera.isOpen, isFalse);
      expect(ui().paused, isTrue, reason: 'the page must not build a preview of a released camera');
      expect(ui().flow.canShoot, isFalse);
      await ctl().onLifecycle(AppLifecycleState.paused); // a second event must not pause twice
      expect(camera.pauseCalls, 1);
      await ctl().onLifecycle(AppLifecycleState.resumed);
      expect(camera.resumeCalls, 1);
      expect(ui().paused, isFalse);
      await _until(() => ui().flow.canShoot, what: 'ready after resume');
    });

    test('closing the screen releases everything: stream stopped, camera disposed, no more frames', () async {
      await open(flat);
      await _until(() => ui().flow.phase == CapturePhase.adjusting || ui().flow.canShoot);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(camera.disposeCalls, 1);
      expect(camera.isStreaming, isFalse);
      final taken = camera.framesTaken;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(camera.framesTaken, taken);
      c = ProviderContainer(); // for tearDown
    });

    test('closing the screen during processing cancels the work without errors', () async {
      await open(flat);
      await _until(() => ui().flow.canShoot);
      final shot = ctl().shutter();
      await _until(() => ui().flow.phase == CapturePhase.processing, what: 'processing');
      c.dispose();
      await shot; // must complete, not throw
      c = ProviderContainer();
    });
  });
}
