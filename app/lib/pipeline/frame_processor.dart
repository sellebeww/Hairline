// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

/// Builds the adapters inside the worker isolate. MUST be a top-level or static function
/// (it is sent to the isolate); native handles never cross isolates.
typedef FramePortsFactory = FramePorts Function();

/// The job was cancelled by the caller.
final class FrameCancelledException implements Exception {
  const FrameCancelledException();

  @override
  String toString() => 'FrameCancelledException';
}

/// The worker failed (adapter error, crash, unsendable result). [message] is for the user.
final class FrameProcessException implements Exception {
  const FrameProcessException(this.message, [this.detail]);
  final String message;
  final String? detail;

  @override
  String toString() => 'FrameProcessException: $message${detail == null ? '' : ' ($detail)'}';
}

/// Work done inside the worker on the photo bytes. A closure over sendable values only
/// (a context, a list of points, a top-level factory).
typedef _Work = Object Function(Uint8List photo);

final class _Request {
  const _Request(this.reply, this.photo, this.work);
  final SendPort reply;
  final TransferableTypedData photo;
  final _Work work;
}

final class _Failure {
  const _Failure(this.error, this.stack);
  final String error;
  final String stack;
}

/// Worker body: all native work (decode, detect, extract) happens here, off the UI isolate.
/// `processFrame` disposes the decoded image in a `finally`, so an error leaves nothing
/// behind; the error itself is sent back as data and the isolate then exits normally.
void _worker(_Request r) {
  Object reply;
  try {
    final bytes = r.photo.materialize().asUint8List();
    reply = r.work(bytes);
  } catch (e, st) {
    reply = _Failure('$e', '$st');
  }
  try {
    r.reply.send(reply);
  } catch (e) {
    r.reply.send(_Failure('Hasil tidak dapat dikirim antar isolate: $e', ''));
  }
}

/// A running frame job; [T] is the result of the work: one [FrameOutcome] for a crack
/// frame, one per measurement point for a plate frame.
final class FrameJob<T extends Object> {
  FrameJob._(this._onFinished) {
    // A cancelled or dropped job (provider disposal) must not raise an unhandled error.
    _done.future.ignore();
  }

  final void Function(FrameJob<Object>) _onFinished;
  final _done = Completer<T>();
  Isolate? _isolate;
  bool _cancelled = false;

  /// Completes with the outcome, or with [FrameCancelledException] / [FrameProcessException].
  Future<T> get result => _done.future;

  /// Cancels cooperatively: the caller gets [FrameCancelledException] at once and the
  /// result is dropped. The worker is killed with `beforeNextEvent`, i.e. only after its
  /// synchronous work finished, so its `finally` blocks have released every native object
  /// (an immediate kill could interrupt Dart code and skip them). Latency of the actual
  /// stop: at most one frame of processing.
  void cancel() {
    if (_cancelled || _done.isCompleted) return;
    _cancelled = true;
    _done.completeError(const FrameCancelledException());
    _isolate?.kill(priority: Isolate.beforeNextEvent);
  }

  Future<void> _start(Uint8List photo, _Work work) async {
    final reply = ReceivePort(), exit = ReceivePort(), errors = ReceivePort();
    void fail(String m, [String? d]) {
      if (!_done.isCompleted) _done.completeError(FrameProcessException(m, d));
    }

    reply.listen((m) {
      if (_done.isCompleted) return;
      switch (m) {
        case _Failure(:final error, :final stack):
          fail('Pemrosesan foto gagal. Ulangi pemotretan.', '$error\n$stack');
        case T():
          _done.complete(m);
        default:
          fail('Balasan pemrosesan tidak dikenal.');
      }
    });
    errors.listen((e) => fail('Pemrosesan foto gagal. Ulangi pemotretan.', '$e'));
    exit.listen((_) => fail('Pemrosesan foto berhenti tak terduga. Ulangi pemotretan.'));
    try {
      if (_cancelled) return;
      _isolate = await Isolate.spawn(
        _worker,
        _Request(reply.sendPort, TransferableTypedData.fromList([photo]), work),
        onExit: exit.sendPort,
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
      if (_cancelled) _isolate!.kill(priority: Isolate.beforeNextEvent);
      await _done.future.then<void>((_) {}, onError: (_) {});
    } catch (e) {
      fail('Tidak dapat memulai pemrosesan foto.', '$e');
    } finally {
      reply.close();
      exit.close();
      errors.close();
      _onFinished(this);
    }
  }
}

/// Runs `processFrame` in a worker isolate: async, cancellable, no native handle shared
/// with the UI isolate.
class FrameProcessor {
  FrameProcessor(this._factory);
  final FramePortsFactory _factory;
  final Set<FrameJob<Object>> _active = {};

  /// Number of jobs still running (tests, diagnostics).
  int get activeJobs => _active.length;

  FrameJob<FrameOutcome> start(Uint8List photo, FrameContext context) {
    final factory = _factory; // a local: the closure must not capture `this` (it crosses isolates)
    return _run<FrameOutcome>(photo, (bytes) => processFrame(encoded: bytes, ports: factory(), context: context));
  }

  /// One photo, several measurement [points] (the validation plate): a single decode and
  /// detection in the worker, one outcome per point in order.
  FrameJob<List<FrameOutcome>> startPoints(Uint8List photo, FrameContext context, List<FramePoint> points) {
    final factory = _factory;
    return _run<List<FrameOutcome>>(
      photo,
      (bytes) => processFramePoints(encoded: bytes, ports: factory(), context: context, points: points),
    );
  }

  FrameJob<T> _run<T extends Object>(Uint8List photo, _Work work) {
    final job = FrameJob<T>._(_active.remove);
    _active.add(job);
    unawaited(job._start(photo, work));
    return job;
  }

  Future<FrameOutcome> process(Uint8List photo, FrameContext context) => start(photo, context).result;

  /// Cancels every running job (provider disposal).
  void cancelAll() {
    for (final j in List.of(_active)) {
      j.cancel();
    }
  }
}
