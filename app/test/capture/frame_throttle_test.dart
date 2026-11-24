// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/frame_throttle.dart';

void main() {
  late Duration now;
  late FrameThrottle t;
  setUp(() {
    now = Duration.zero;
    t = FrameThrottle(minInterval: const Duration(milliseconds: 100), clock: () => now);
  });

  test('admits one frame, drops while busy, admits again after release and the interval', () {
    expect(t.tryAcquire(), isTrue);
    now += const Duration(milliseconds: 500);
    expect(t.tryAcquire(), isFalse, reason: 'still busy');
    expect(t.droppedBusy, 1);
    t.release();
    expect(t.tryAcquire(), isTrue);
    expect(t.admitted, 2);
  });

  test('keeps the rate at or below the target even when the detector is fast', () {
    var admitted = 0;
    // A camera delivering 60 fps for 2 s, detector instantaneous.
    for (var i = 0; i < 120; i++) {
      now = Duration(microseconds: i * 16667);
      if (t.tryAcquire()) {
        admitted++;
        t.release();
      }
    }
    expect(admitted, inInclusiveRange(8 * 2, 12 * 2)); // 8 to 12 fps over 2 s
    expect(t.skippedRate, greaterThan(0));
  });

  test('a slow detector lowers the rate by itself and never builds a queue', () {
    var processed = 0;
    Duration? busyUntil;
    for (var i = 0; i < 300; i++) {
      now = Duration(milliseconds: i * 10); // 100 fps source for 3 s
      if (busyUntil != null && now >= busyUntil) {
        t.release();
        busyUntil = null;
      }
      if (t.tryAcquire()) {
        processed++;
        busyUntil = now + const Duration(milliseconds: 400); // 2.5 fps detector
      }
      expect(t.busy ? 1 : 0, lessThanOrEqualTo(1));
    }
    expect(processed, inInclusiveRange(7, 8));
    expect(t.droppedBusy, greaterThan(200));
  });

  test('release without a running frame is harmless', () {
    t.release();
    expect(t.busy, isFalse);
    expect(t.tryAcquire(), isTrue);
  });
}
