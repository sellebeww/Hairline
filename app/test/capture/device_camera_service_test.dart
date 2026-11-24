// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/camera_driver.dart';
import 'package:hairline/capture/camera_service.dart';
import 'package:hairline/capture/device_camera_service.dart';
import 'package:hairline/capture/lens_info.dart';
import 'package:hairline/capture/luma_frame.dart';

final class _FakeDriver implements CameraDriver {
  _FakeDriver(this.log, this.id);

  final List<String> log;
  final int id;
  CameraFailure? openFails;
  LockResult lockResult = const LockResult(focusLocked: true, exposureLocked: true);
  Completer<void>? shotGate; // when set, takePicture waits for it
  Object? shotError;
  Duration shotTime = Duration.zero;
  int shots = 0;
  void Function(RawYFrame)? onFrame;
  bool closed = false;

  void _l(String e) => log.add('$id:$e');

  @override
  Future<DriverInfo> open() async {
    _l('open');
    final f = openFails;
    if (f != null) throw f;
    return const DriverInfo(cameraId: '0', sensorOrientation: 90);
  }

  @override
  Widget preview() => const SizedBox();

  @override
  Future<void> startStream(void Function(RawYFrame frame) onFrame) async {
    _l('startStream');
    this.onFrame = onFrame;
  }

  @override
  Future<void> stopStream() async => _l('stopStream');

  @override
  Future<LockResult> lock() async {
    _l('lock');
    return lockResult;
  }

  @override
  Future<void> unlock() async => _l('unlock');

  @override
  Future<Uint8List> takePicture() async {
    final n = ++shots;
    _l('shot$n');
    await shotGate?.future;
    if (shotTime > Duration.zero) await Future<void>.delayed(shotTime);
    final e = shotError;
    if (e != null) throw e;
    return Uint8List.fromList([n]);
  }

  @override
  Future<void> close() async {
    _l('close');
    closed = true;
  }

  void emit() => onFrame?.call(RawYFrame(y: Uint8List(16 * 12), width: 16, height: 12, rowStride: 16));
}

final class _Lens implements LensInfoSource {
  @override
  Future<LensInfo> read(String cameraId) async => LensInfo(cameraId: cameraId, focalLengthMm: 5, sensorWidthMm: 6, sensorHeightMm: 4.5);
}

void main() {
  late List<String> log;
  late List<_FakeDriver> drivers;
  late DeviceCameraService svc;
  late int offered;
  late int taken;

  /// The offer a worker would give: counts frames and takes them all.
  bool offer(LumaFrame Function() produce) {
    offered++;
    produce();
    taken++;
    return true;
  }

  setUp(() {
    log = [];
    drivers = [];
    offered = taken = 0;
    svc = DeviceCameraService(
      driverFactory: () {
        final d = _FakeDriver(log, drivers.length + 1);
        drivers.add(d);
        return d;
      },
      lensSource: _Lens(),
      lockSettle: Duration.zero,
      inFlightTimeout: const Duration(seconds: 2),
    );
  });

  test('initialize opens once, reads the lens and derives the rotation from the sensor orientation', () async {
    final setup = await svc.initialize();
    expect(setup.quarterTurns, 1); // sensor orientation 90
    expect(setup.lens.sensorLongSideMm, 6);
    await svc.initialize();
    expect(log, ['1:open']);
  });

  test('an open failure keeps its kind and releases the driver it created', () async {
    final failing = DeviceCameraService(
      driverFactory: () => _FakeDriver(log, 1)..openFails = const CameraFailure(CameraFailureKind.permissionDeniedForever),
      lensSource: _Lens(),
    );
    await expectLater(failing.initialize(), throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.permissionDeniedForever)));
    expect(log, ['1:open', '1:close']);
  });

  test('frames are decimated and offered; a callback that outlives stopLiveFrames is ignored', () async {
    await svc.initialize();
    await svc.startLiveFrames(offer);
    final d = drivers.single;
    d.emit();
    expect((offered, taken), (1, 1));
    final stale = d.onFrame!;
    await svc.stopLiveFrames();
    stale(RawYFrame(y: Uint8List(16 * 12), width: 16, height: 12, rowStride: 16));
    expect(offered, 1);
    await svc.startLiveFrames(offer);
    d.emit();
    expect(offered, 2);
  });

  test('burst order: stream stopped, locked, shots spaced by minGap, unlocked, stream resumed', () async {
    await svc.initialize();
    await svc.startLiveFrames(offer);
    log.clear();
    final progress = <int>[];
    final sw = Stopwatch()..start();
    final burst = await svc.captureBurst(count: 3, minGap: const Duration(milliseconds: 60), onProgress: progress.add);
    expect(log, ['1:stopStream', '1:lock', '1:shot1', '1:shot2', '1:shot3', '1:unlock', '1:startStream']);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(2 * 60 - 5), reason: 'two gaps between three shots');
    expect(burst.photos.map((p) => p.single), [1, 2, 3]);
    expect(progress, [1, 2, 3]);
    expect(burst.locks.flags, isEmpty);
  });

  test('a burst does not restart a stream that nobody asked for', () async {
    await svc.initialize();
    log.clear();
    await svc.captureBurst(count: 1);
    expect(log, ['1:lock', '1:shot1', '1:unlock']);
  });

  test('a device that cannot lock focus still shoots; the burst carries the flag', () async {
    await svc.initialize();
    drivers.single.lockResult = const LockResult(focusLocked: false, exposureLocked: true);
    final burst = await svc.captureBurst(count: 1);
    expect(burst.photos, hasLength(1));
    expect(burst.locks.flags, ['fokus_tidak_terkunci']);
  });

  test('a failing shot becomes captureFailed and the camera is still unlocked and streaming again', () async {
    await svc.initialize();
    await svc.startLiveFrames(offer);
    final d = drivers.single..shotError = StateError('sensor busy');
    log.clear();
    await expectLater(svc.captureBurst(count: 3), throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.captureFailed)));
    expect(log, ['1:stopStream', '1:lock', '1:shot1', '1:unlock', '1:startStream']);
    expect(d.closed, isFalse);
  });

  test('a second burst while one runs is refused as busy', () async {
    await svc.initialize();
    drivers.single.shotGate = Completer<void>();
    final first = svc.captureBurst(count: 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await expectLater(svc.captureBurst(count: 1), throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.busy)));
    drivers.single.shotGate!.complete();
    expect((await first).photos, hasLength(1));
  });

  group('lifecycle', () {
    test('pause during a burst: the burst ends as interrupted, the camera is closed, nothing touches the closed driver', () async {
      await svc.initialize();
      await svc.startLiveFrames(offer);
      final d = drivers.single..shotTime = const Duration(milliseconds: 40);
      log.clear();
      final burst = svc.captureBurst(count: 6, minGap: const Duration(milliseconds: 20));
      final outcome = expectLater(burst, throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.interrupted)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await svc.pause();
      await outcome;
      expect(d.closed, isTrue);
      expect(d.shots, lessThan(6));
      final closeAt = log.indexOf('1:close');
      expect(log.sublist(closeAt + 1), isEmpty, reason: 'no unlock, no stream restart after the driver was closed: $log');
    });

    test('pause waits for a still that is being taken before it closes the camera', () async {
      await svc.initialize();
      final d = drivers.single..shotGate = Completer<void>();
      final burst = svc.captureBurst(count: 2);
      final outcome = expectLater(burst, throwsA(isA<CameraFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final paused = svc.pause();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(d.closed, isFalse, reason: 'the in-flight shot has not returned yet');
      d.shotGate!.complete();
      await paused;
      await outcome;
      expect(d.closed, isTrue);
    });

    test('resume reopens a new driver and restarts the stream; resume when not paused does nothing', () async {
      await svc.initialize();
      await svc.startLiveFrames(offer);
      await svc.resume();
      expect(drivers, hasLength(1));
      await svc.pause();
      log.clear();
      await svc.resume();
      expect(drivers, hasLength(2));
      expect(log, ['2:open', '2:startStream']);
      drivers.last.emit();
      expect(offered, 1);
      expect(drivers.first.closed, isTrue);
    });

    test('a burst on a paused camera is interrupted at once', () async {
      await svc.initialize();
      await svc.pause();
      await expectLater(svc.captureBurst(count: 1), throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.interrupted)));
    });

    test('lifecycle calls issued without awaiting run in order', () async {
      final a = svc.initialize();
      final b = svc.pause();
      final c = svc.resume();
      await Future.wait([a, b, c]);
      expect(log, ['1:open', '1:close', '2:open']);
    });

    test('dispose releases once, even when called twice; later use is refused and late frames are ignored', () async {
      await svc.initialize();
      await svc.startLiveFrames(offer);
      final d = drivers.single;
      final late = d.onFrame!;
      await Future.wait([svc.dispose(), svc.dispose()]);
      await svc.dispose();
      expect(log.where((e) => e.endsWith('close')), hasLength(1));
      late(RawYFrame(y: Uint8List(16 * 12), width: 16, height: 12, rowStride: 16));
      expect(offered, 0);
      await expectLater(svc.initialize(), throwsA(isA<CameraFailure>()));
      await expectLater(svc.captureBurst(count: 1), throwsA(isA<CameraFailure>()));
    });

    test('dispose during a burst ends it as interrupted', () async {
      await svc.initialize();
      final d = drivers.single..shotTime = const Duration(milliseconds: 40);
      final burst = svc.captureBurst(count: 6, minGap: const Duration(milliseconds: 20));
      final outcome = expectLater(burst, throwsA(isA<CameraFailure>().having((e) => e.kind, 'kind', CameraFailureKind.interrupted)));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await svc.dispose();
      await outcome;
      expect(d.closed, isTrue);
    });
  });
}
