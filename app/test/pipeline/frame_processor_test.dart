// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/pipeline/frame_processor.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

import '../support/synthetic_ports.dart';

const _ctx = FrameContext(sheetId: 0, pointMm: Pt(0, 0), directionDeg: crackDirectionDeg);

Future<void> _until(bool Function() cond, {int ms = 8000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $ms ms');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

FramePorts _dyingFactory() {
  Isolate.current.kill(priority: Isolate.immediate); // stands in for a native crash
  sleep(const Duration(seconds: 5));
  return syntheticPorts();
}

void main() {
  final cam = testCamera();
  late Directory tmp;
  late String tracePath;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hairline_iso_');
    tracePath = '${tmp.path}/trace.log';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('processes a frame in a worker isolate and returns the core outcome (sendable result)', () async {
    final processor = FrameProcessor(tracingFactory(tracePath));
    // Two markers only: a quick, complete round trip through the isolate boundary.
    final o = await processor.process(blankPhoto(detections(cam, omit: {0, 1})), _ctx);
    expect(o.accepted, isFalse);
    expect(o.input.geometryRejections, [FrameRejection.tooFewMarkers]);
    expect(readTrace(tracePath), ['open', 'close']);
    await _until(() => processor.activeJobs == 0); // the job leaves the set once its ports are closed
  });

  test('a geometry-rejected frame with a homography keeps its numbers across the isolate', () async {
    final tilted = SyntheticCamera(image: testImage, fPx: 1280, distanceMm: 0.12 * 1280, tiltDeg: 40);
    final o = await FrameProcessor(tracingFactory(tracePath)).process(blankPhoto(detections(tilted)), _ctx);
    expect(o.input.geometryRejections, contains(FrameRejection.tiltHardReject));
    expect(o.homography!.markerCount, 4);
    expect(o.tiltDeg, closeTo(40, 3));
  });

  test('an adapter error becomes a FrameProcessException and the image is still released', () async {
    final processor = FrameProcessor(tracingFactory(tracePath, failInDetect: true));
    await expectLater(
      processor.process(blankPhoto(detections(cam)), _ctx),
      throwsA(isA<FrameProcessException>().having((e) => e.message, 'message', contains('gagal'))),
    );
    expect(readTrace(tracePath), ['open', 'close']);
    await _until(() => processor.activeJobs == 0); // the job leaves the set once its ports are closed
  });

  test('an unreadable photo is a rejection, not an exception, and opens nothing', () async {
    final o = await FrameProcessor(tracingFactory(tracePath)).process(Uint8List.fromList([1, 2, 3]), _ctx);
    expect(o.input.geometryRejections, [FrameRejection.imageUnreadable]);
    expect(readTrace(tracePath), isEmpty);
  });

  test('cancel returns at once, and the worker still releases its image before it ends', () async {
    final processor = FrameProcessor(tracingFactory(tracePath, detectDelayMs: 1200));
    final job = processor.start(blankPhoto(detections(cam)), _ctx);
    final result = job.result.then<Object>((v) => v, onError: (Object e) => e);
    await _until(() => readTrace(tracePath).contains('open')); // the worker is inside the slow detector
    final sw = Stopwatch()..start();
    job.cancel();
    expect(await result, isA<FrameCancelledException>());
    expect(sw.elapsedMilliseconds, lessThan(600), reason: 'the caller must not wait for the worker');
    // The synchronous pipeline finishes in the worker and disposes the image in `finally`.
    await _until(() => readTrace(tracePath).contains('close'));
    expect(readTrace(tracePath), ['open', 'close']);
    await _until(() => processor.activeJobs == 0);
  });

  test('cancel before the isolate has started completes cleanly and nothing is opened', () async {
    final processor = FrameProcessor(tracingFactory(tracePath));
    final job = processor.start(blankPhoto(detections(cam)), _ctx);
    job.cancel();
    await expectLater(job.result, throwsA(isA<FrameCancelledException>()));
    await _until(() => processor.activeJobs == 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // The isolate may have started before the kill took effect; if it opened an image it closed it.
    final t = readTrace(tracePath);
    expect(t.where((e) => e == 'open').length, t.where((e) => e == 'close').length);
  });

  test('cancelAll cancels every running job; a second cancel is harmless', () async {
    final processor = FrameProcessor(tracingFactory(tracePath, detectDelayMs: 400));
    final jobs = [for (var i = 0; i < 3; i++) processor.start(blankPhoto(detections(cam, seed: i)), _ctx)];
    final results = [for (final j in jobs) j.result.then<Object>((v) => v, onError: (Object e) => e)];
    processor.cancelAll();
    processor.cancelAll();
    for (final r in await Future.wait(results)) {
      expect(r, isA<FrameCancelledException>());
    }
    await _until(() => processor.activeJobs == 0);
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // let started workers finish
    final t = readTrace(tracePath);
    expect(t.where((e) => e == 'open').length, t.where((e) => e == 'close').length, reason: '$t');
  });

  test('a worker that dies without a reply is reported as an error, not a hang', () async {
    final processor = FrameProcessor(_dyingFactory);
    await expectLater(
      processor.process(blankPhoto(detections(cam)), _ctx),
      throwsA(isA<FrameProcessException>().having((e) => e.message, 'message', contains('berhenti'))),
    );
    await _until(() => processor.activeJobs == 0);
  });

  test('jobs are independent: one failing job does not affect another', () async {
    final good = FrameProcessor(tracingFactory(tracePath));
    final bad = FrameProcessor(tracingFactory(tracePath, failInDetect: true));
    final results = await Future.wait([
      good.process(blankPhoto(detections(cam, omit: {0, 1})), _ctx),
      bad.process(blankPhoto(detections(cam)), _ctx).then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect((results[0] as FrameOutcome).accepted, isFalse);
    expect(results[1], isA<FrameProcessException>());
  });
}
