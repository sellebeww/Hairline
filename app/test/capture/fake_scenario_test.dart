// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/capture/live_analysis.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/debug/fake_scenario.dart';
import 'package:hairline_core/hairline_core.dart';

void main() {
  test('the simulation entry point builds its scenario in an isolate (everything is sendable)', () async {
    final s = await Isolate.run(() => buildFakeScenario(renderCrack: false));
    expect(s.live, isNotEmpty);
    expect(s.stills, hasLength(6));
  });

  test('the script goes from no markers, to two, to a pose that is ready after enough steady frames', () {
    final s = buildFakeScenario(renderCrack: false);
    const detector = EmbeddedGrayMarkerDetector();
    final analyzer = LiveAnalyzer(sheetId: 0, printScale: 1, pointMm: const Pt(0, 0), quarterTurns: 0);
    var state = const CaptureState();
    final counts = <int>[];
    final phases = <CapturePhase>[];
    for (var i = 0; i < s.live.length; i++) {
      final f = s.live[i];
      final dets = detector.detectGray(f.bytes, f.width, f.height);
      counts.add(dets.length);
      final a = analyzer.analyze(DetectionResult(
        markers: dets,
        width: f.width,
        height: f.height,
        step: f.step,
        sourceWidth: f.sourceWidth,
        sourceHeight: f.sourceHeight,
        detectMicros: 0,
      ));
      state = reduceCapture(state, AnalysisEvent(a, Duration(milliseconds: 100 * i)));
      phases.add(state.phase);
    }
    expect(counts.take(6), everyElement(0));
    expect(counts.skip(6).take(6), everyElement(2));
    expect(counts.skip(12), everyElement(4));
    expect(phases.take(12), everyElement(CapturePhase.waitingForMarkers));
    expect(phases, contains(CapturePhase.adjusting), reason: 'the approach shows instructions first');
    expect(phases.last, CapturePhase.ready);
    expect(state.canShoot, isTrue);
  });

  test('the live frames carry the geometry that maps them back to the 1600 x 1500 photo', () {
    final f = buildFakeScenario(renderCrack: false).live.first;
    expect((f.sourceWidth, f.sourceHeight, f.step), (1600, 1500, 40));
    expect(f.toSource(const Pt(0, 0)), const Pt(20, 20));
  });
}
