// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:isolate';

import 'package:hairline_core/hairline_core.dart';

import 'frame_throttle.dart';
import 'live_analysis.dart';
import 'luma_frame.dart';

/// The detection isolate could not start or died.
final class DetectionWorkerException implements Exception {
  const DetectionWorkerException(this.message, [this.detail]);
  final String message;
  final String? detail;

  @override
  String toString() => 'DetectionWorkerException: $message${detail == null ? '' : ' ($detail)'}';
}

final class _Init {
  const _Init(this.toMain, this.factory);
  final SendPort toMain;
  final GrayDetectorFactory factory;
}

final class _Job {
  const _Job(this.gray, this.width, this.height, this.step, this.sourceWidth, this.sourceHeight);
  final TransferableTypedData gray;
  final int width, height, step, sourceWidth, sourceHeight;
}

final class _Failure {
  const _Failure(this.error);
  final String error;
}

/// Worker body: builds the detector once, then handles one job at a time. A thrown
/// error is reported as data; the loop goes on with the next frame. `null` ends it.
void _entry(_Init init) {
  final inbox = ReceivePort();
  GrayMarkerDetector detector;
  try {
    detector = init.factory();
  } catch (e) {
    init.toMain.send(_Failure('$e'));
    inbox.close();
    return;
  }
  init.toMain.send(inbox.sendPort);
  inbox.listen((Object? m) {
    if (m is! _Job) {
      inbox.close();
      return;
    }
    try {
      final clock = Stopwatch()..start();
      final markers = detector.detectGray(m.gray.materialize().asUint8List(), m.width, m.height);
      init.toMain.send(DetectionResult(
        markers: markers,
        width: m.width,
        height: m.height,
        step: m.step,
        sourceWidth: m.sourceWidth,
        sourceHeight: m.sourceHeight,
        detectMicros: clock.elapsedMicroseconds,
      ));
    } catch (e) {
      init.toMain.send(_Failure('$e'));
    }
  });
}

/// A long-lived isolate running the live marker detector, fed through a [FrameThrottle]:
/// at most one frame is in flight, frames offered meanwhile are dropped (no queue, so
/// memory stays bounded however slow the detector is).
final class DetectionWorker {
  DetectionWorker._(this._isolate, this._toWorker, this._fromWorker, this._exit, this._throttle);

  /// Starts the isolate and waits until the detector exists inside it. Throws
  /// [DetectionWorkerException] when the factory fails there or the isolate dies first.
  static Future<DetectionWorker> start(GrayDetectorFactory factory, {FrameThrottle? throttle}) async {
    final fromWorker = ReceivePort(), exit = ReceivePort();
    final ready = Completer<SendPort>();
    DetectionWorker? worker;
    fromWorker.listen((Object? m) {
      if (worker != null) return worker._onMessage(m);
      if (ready.isCompleted) return;
      if (m is SendPort) {
        ready.complete(m);
      } else {
        ready.completeError(DetectionWorkerException('Detektor penanda tidak dapat dibuat.', m is _Failure ? m.error : '$m'));
      }
    });
    exit.listen((_) {
      if (worker != null) return worker._onExit();
      if (!ready.isCompleted) ready.completeError(const DetectionWorkerException('Pendeteksi penanda berhenti saat dimulai.'));
    });
    final isolate = await Isolate.spawn(_entry, _Init(fromWorker.sendPort, factory), onExit: exit.sendPort, errorsAreFatal: true);
    try {
      final to = await ready.future;
      return worker = DetectionWorker._(isolate, to, fromWorker, exit, throttle ?? FrameThrottle());
    } catch (_) {
      isolate.kill(priority: Isolate.beforeNextEvent);
      fromWorker.close();
      exit.close();
      rethrow;
    }
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final ReceivePort _exit;
  final FrameThrottle _throttle;
  final _results = StreamController<DetectionResult>.broadcast();
  final _exited = Completer<void>();
  bool _closed = false;
  bool _dead = false;

  /// Frames whose conversion failed (the camera layer's problem, counted not thrown).
  int produceFailures = 0;

  Stream<DetectionResult> get results => _results.stream;
  FrameThrottle get throttle => _throttle;

  /// Completes when the isolate has exited (tests, shutdown).
  Future<void> get exited => _exited.future;

  /// Offers a frame. [produce] runs only when the frame is taken, so a dropped frame
  /// costs nothing. Returns false when the frame was dropped or the worker is gone.
  bool offer(LumaFrame Function() produce) {
    if (_closed || _dead || !_throttle.tryAcquire()) return false;
    try {
      final f = produce();
      _toWorker.send(_Job(TransferableTypedData.fromList([f.bytes]), f.width, f.height, f.step, f.sourceWidth, f.sourceHeight));
      return true;
    } catch (_) {
      produceFailures++;
      _throttle.release();
      return false;
    }
  }

  void _onExit() {
    _dead = true;
    if (!_exited.isCompleted) _exited.complete();
    if (!_closed) _results.addError(const DetectionWorkerException('Pendeteksi penanda berhenti tak terduga.'));
  }

  void _onMessage(Object? m) {
    if (_closed) return;
    _throttle.release();
    switch (m) {
      case DetectionResult():
        _results.add(m);
      case _Failure(:final error):
        _results.addError(DetectionWorkerException('Pendeteksi penanda gagal pada satu frame.', error));
      default:
        break;
    }
  }

  /// Stops the isolate after its current frame (so the native objects of that frame are
  /// released first, as in D37) and closes every port. Idempotent.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _fromWorker.close();
    await _results.close();
    if (!_dead) await _exited.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    _exit.close();
  }
}
