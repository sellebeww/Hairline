// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_driver.dart';
import 'camera_service.dart';
import 'lens_info.dart';
import 'luma_frame.dart';

enum _Status { idle, open, paused, disposed }

/// Sequencing, lifecycle and race handling around a [CameraDriver].
///
/// Rules: (1) lifecycle operations (initialize, pause, resume, dispose) run one at a time
/// in call order; (2) `pause` and `dispose` bump a generation counter at once, so a burst
/// in progress notices after its current await and fails as interrupted instead of
/// touching a released camera; (3) the image stream is always stopped before the first
/// still and restarted after the last, and a stream callback from an old generation is
/// ignored; (4) at most one burst at a time.
final class DeviceCameraService implements CameraService {
  @override
  bool get isSimulated => false;

  DeviceCameraService({
    required this._driverFactory,
    required this._lensSource,
    this.lockSettle = const Duration(milliseconds: 300),
    this.inFlightTimeout = const Duration(seconds: 5),
  });

  final CameraDriverFactory _driverFactory;
  final LensInfoSource _lensSource;

  /// Wait between locking and the first shot, so that the lock has taken effect.
  final Duration lockSettle;

  /// How long `pause` waits for a still already being taken before it closes the camera.
  final Duration inFlightTimeout;

  CameraDriver? _driver;
  CameraSetup? _setup;
  _Status _status = _Status.idle;
  int _gen = 0; // bumped by pause and dispose
  int _streamGen = 0; // bumped whenever the stream stops or starts
  FrameOffer? _offer;
  bool _wantLive = false;
  bool _streaming = false;
  bool _busy = false;
  Future<void>? _inFlight;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;

  Future<T> _serial<T>(Future<T> Function() op) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await op());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  void _check(int gen) {
    if (gen != _gen || _status != _Status.open) throw const CameraFailure(CameraFailureKind.interrupted);
  }

  Future<CameraSetup> _open() async {
    final driver = _driverFactory();
    try {
      final info = await driver.open();
      final lens = await _lensSource.read(info.cameraId);
      final turns = ((lens.sensorOrientation ?? info.sensorOrientation ?? 90) ~/ 90) & 3;
      _driver = driver;
      _status = _Status.open;
      return _setup = CameraSetup(lens: lens, quarterTurns: turns);
    } catch (_) {
      await _closeQuietly(driver);
      rethrow;
    }
  }

  static Future<void> _closeQuietly(CameraDriver d) async {
    try {
      await d.close();
    } catch (_) {
      // Releasing a camera that failed to open must not hide the original failure.
    }
  }

  @override
  Future<CameraSetup> initialize() => _serial(() async {
        if (_status == _Status.disposed) throw const CameraFailure(CameraFailureKind.interrupted, 'disposed');
        if (_status == _Status.open) return _setup!;
        return _open();
      });

  @override
  Widget buildPreview(BuildContext context) => _driver?.preview() ?? const SizedBox.shrink();

  Future<void> _beginStream() async {
    final d = _driver;
    if (d == null || _offer == null || _streaming || _status != _Status.open) return;
    final g = ++_streamGen;
    _streaming = true;
    try {
      await d.startStream((raw) {
        if (g != _streamGen) return; // a callback that outlived stopStream
        _offer?.call(() => LumaFrame.fromYPlane(y: raw.y, width: raw.width, height: raw.height, rowStride: raw.rowStride));
      });
    } catch (e) {
      _streaming = false;
      throw CameraFailure(CameraFailureKind.openFailed, 'stream: $e');
    }
  }

  Future<void> _endStream() async {
    _streamGen++;
    if (!_streaming) return;
    _streaming = false;
    try {
      await _driver?.stopStream();
    } catch (_) {
      // The stream is already gone (camera lost): nothing left to stop.
    }
  }

  @override
  Future<void> startLiveFrames(FrameOffer offer) async {
    _offer = offer;
    _wantLive = true;
    if (_status == _Status.open && !_busy) await _beginStream();
  }

  @override
  Future<void> stopLiveFrames() async {
    _wantLive = false;
    await _endStream();
  }

  @override
  Future<BurstResult> captureBurst({
    int count = 6,
    Duration minGap = const Duration(milliseconds: 200),
    void Function(int taken)? onProgress,
  }) async {
    if (count < 1) throw ArgumentError.value(count, 'count', 'must be at least 1');
    if (_status != _Status.open) throw const CameraFailure(CameraFailureKind.interrupted);
    if (_busy) throw const CameraFailure(CameraFailureKind.busy);
    _busy = true;
    final gen = _gen;
    final driver = _driver!;
    final resumeLive = _wantLive;
    try {
      await _endStream();
      _check(gen);
      final locks = await driver.lock();
      _check(gen);
      await Future<void>.delayed(lockSettle);
      final photos = <Uint8List>[];
      for (var i = 0; i < count; i++) {
        _check(gen);
        if (i > 0) await Future<void>.delayed(minGap);
        _check(gen);
        final shot = driver.takePicture();
        _inFlight = shot.then<void>((_) {}, onError: (Object _) {});
        try {
          photos.add(await shot);
        } finally {
          _inFlight = null;
        }
        _check(gen);
        onProgress?.call(photos.length);
      }
      return BurstResult(photos: photos, locks: locks);
    } on CameraFailure {
      rethrow;
    } catch (e) {
      throw gen != _gen
          ? const CameraFailure(CameraFailureKind.interrupted)
          : CameraFailure(CameraFailureKind.captureFailed, '$e');
    } finally {
      _busy = false;
      if (gen == _gen && _status == _Status.open) {
        try {
          await driver.unlock();
          if (resumeLive) await _beginStream();
        } catch (_) {
          // Re-arming is best effort: the capture flow restarts the stream on retry.
        }
      }
    }
  }

  Future<void> _waitInFlight() async {
    final f = _inFlight;
    if (f != null) await f.timeout(inFlightTimeout, onTimeout: () {});
  }

  @override
  Future<void> pause() {
    _gen++; // synchronously: a running burst stops at its next check
    return _serial(() async {
      if (_status != _Status.open) return;
      _status = _Status.paused;
      await _endStream();
      await _waitInFlight();
      final d = _driver;
      _driver = null;
      if (d != null) await _closeQuietly(d);
    });
  }

  @override
  Future<void> resume() => _serial(() async {
        if (_status != _Status.paused) return;
        await _open();
        if (_wantLive) await _beginStream();
      });

  @override
  Future<void> dispose() {
    _gen++;
    _wantLive = false;
    _offer = null;
    return _disposing ??= _serial(() async {
      _status = _Status.disposed;
      await _endStream();
      await _waitInFlight();
      final d = _driver;
      _driver = null;
      if (d != null) await _closeQuietly(d);
    });
  }
}
