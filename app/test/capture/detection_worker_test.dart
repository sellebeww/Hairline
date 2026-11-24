// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/detection_worker.dart';
import 'package:hairline/capture/frame_throttle.dart';
import 'package:hairline/capture/live_analysis.dart';
import 'package:hairline/capture/luma_frame.dart';
import 'package:hairline_core/hairline_core.dart';

// Factories run inside the worker isolate, so they are top-level.
final class _Detector implements GrayMarkerDetector {
  const _Detector({this.delayMs = 0});
  final int delayMs;

  @override
  List<MarkerDetection> detectGray(Uint8List gray, int width, int height) {
    if (delayMs > 0) sleep(Duration(milliseconds: delayMs));
    if (gray.isNotEmpty && gray[0] == 255) throw StateError('detector failed on this frame');
    final id = gray.isEmpty ? 0 : gray[0];
    return [MarkerDetection(id: id, corners: const [Pt(1, 1), Pt(2, 1), Pt(2, 2), Pt(1, 2)])];
  }
}

GrayMarkerDetector _fast() => const _Detector();
GrayMarkerDetector _slow() => const _Detector(delayMs: 150);
GrayMarkerDetector _noDetector() => throw StateError('no detector library');

LumaFrame _frame(int id) => LumaFrame(bytes: Uint8List.fromList([id, 1, 2, 3, 4, 5]), width: 3, height: 2, step: 4, sourceWidth: 12, sourceHeight: 8);

Future<T> _next<T>(Stream<T> s) => s.first.timeout(const Duration(seconds: 10));

void main() {
  test('a frame goes through the isolate and comes back with its geometry', () async {
    final w = await DetectionWorker.start(_fast);
    addTearDown(w.dispose);
    final result = _next(w.results);
    expect(w.offer(() => _frame(7)), isTrue);
    final r = await result;
    expect(r.markers.single.id, 7);
    expect((r.width, r.height, r.step, r.sourceWidth, r.sourceHeight), (3, 2, 4, 12, 8));
    expect(r.detectMicros, greaterThanOrEqualTo(0));
  });

  test('a slow detector: frames offered meanwhile are dropped, never queued, and dropped frames are never even produced', () async {
    final throttle = FrameThrottle(minInterval: const Duration(milliseconds: 85));
    final w = await DetectionWorker.start(_slow, throttle: throttle);
    addTearDown(w.dispose);
    var produced = 0;
    var results = 0;
    final sub = w.results.listen((_) => results++);
    // 40 offers over 400 ms against a 150 ms detector.
    for (var i = 0; i < 40; i++) {
      w.offer(() {
        produced++;
        return _frame(1);
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400)); // let the in-flight frame finish
    await sub.cancel();
    expect(produced, throttle.admitted, reason: 'produce runs only for admitted frames');
    expect(throttle.admitted, inInclusiveRange(2, 4));
    expect(results, throttle.admitted, reason: 'every admitted frame was answered, none was queued behind another');
    expect(throttle.droppedBusy, greaterThan(20));
    expect(throttle.busy, isFalse);
  });

  test('a factory that fails inside the isolate makes start throw a specific error', () async {
    await expectLater(
      DetectionWorker.start(_noDetector),
      throwsA(isA<DetectionWorkerException>().having((e) => e.detail, 'detail', contains('no detector library'))),
    );
  });

  test('a detector failure on one frame is reported and the next frame still works', () async {
    final w = await DetectionWorker.start(_fast, throttle: FrameThrottle(minInterval: Duration.zero));
    addTearDown(w.dispose);
    final events = <Object>[];
    final sub = w.results.listen(events.add, onError: events.add);
    expect(w.offer(() => _frame(255)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(w.offer(() => _frame(5)), isTrue, reason: 'the throttle was released after the failure');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    expect(events.first, isA<DetectionWorkerException>());
    expect((events.last as DetectionResult).markers.single.id, 5);
  });

  test('a frame whose conversion throws is counted, the throttle is released, the worker lives on', () async {
    final w = await DetectionWorker.start(_fast, throttle: FrameThrottle(minInterval: Duration.zero));
    addTearDown(w.dispose);
    expect(w.offer(() => throw ArgumentError('bad plane')), isFalse);
    expect(w.produceFailures, 1);
    expect(w.throttle.busy, isFalse);
    final result = _next(w.results);
    expect(w.offer(() => _frame(3)), isTrue);
    expect((await result).markers.single.id, 3);
  });

  test('dispose stops the isolate, closes the stream, refuses frames and is idempotent', () async {
    final w = await DetectionWorker.start(_fast);
    final done = Completer<void>();
    w.results.listen((_) {}, onDone: done.complete);
    await w.dispose();
    await w.exited.timeout(const Duration(seconds: 5));
    await done.future.timeout(const Duration(seconds: 5));
    expect(w.offer(() => _frame(1)), isFalse);
    await w.dispose();
  });

  test('disposing while a slow frame is in flight does not hang and still ends the isolate', () async {
    final w = await DetectionWorker.start(_slow, throttle: FrameThrottle(minInterval: Duration.zero));
    expect(w.offer(() => _frame(1)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await w.dispose().timeout(const Duration(seconds: 10));
    await w.exited.timeout(const Duration(seconds: 10));
  });
}
