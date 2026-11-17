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

final class _Request {
  const _Request(this.reply, this.photo, this.context, this.factory);
  final SendPort reply;
  final TransferableTypedData photo;
  final FrameContext context;
  final FramePortsFactory factory;
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
    reply = processFrame(encoded: bytes, ports: r.factory(), context: r.context);
  } catch (e, st) {
    reply = _Failure('$e', '$st');
  }
  try {
    r.reply.send(reply);
  } catch (e) {
    r.reply.send(_Failure('Hasil tidak dapat dikirim antar isolate: $e', ''));
  }
}

/// A running frame job.
final class FrameJob {
  FrameJob._(this._onFinished) {
    // A cancelled or dropped job (provider disposal) must not raise an unhandled error.
    _done.future.ignore();
  }

  final void Function(FrameJob) _onFinished;
  final _done = Completer<FrameOutcome>();
  Isolate? _isolate;
  bool _cancelled = false;

  /// Completes with the outcome, or with [FrameCancelledException] / [FrameProcessException].
  Future<FrameOutcome> get result => _done.future;

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

  Future<void> _start(Uint8List photo, FrameContext context, FramePortsFactory factory) async {
    final reply = ReceivePort(), exit = ReceivePort(), errors = ReceivePort();
    void fail(String m, [String? d]) {
      if (!_done.isCompleted) _done.completeError(FrameProcessException(m, d));
    }

    reply.listen((m) {
      if (_done.isCompleted) return;
      switch (m) {
        case FrameOutcome():
          _done.complete(m);
        case _Failure(:final error, :final stack):
          fail('Pemrosesan foto gagal. Ulangi pemotretan.', '$error\n$stack');
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
        _Request(reply.sendPort, TransferableTypedData.fromList([photo]), context, factory),
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
  final Set<FrameJob> _active = {};

  /// Number of jobs still running (tests, diagnostics).
  int get activeJobs => _active.length;

  FrameJob start(Uint8List photo, FrameContext context) {
    final job = FrameJob._(_active.remove);
    _active.add(job);
    unawaited(job._start(photo, context, _factory));
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
