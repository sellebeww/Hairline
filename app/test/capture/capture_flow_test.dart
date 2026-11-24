// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/capture/live_analysis.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

final _estimate = estimateSheetHomography(
  SyntheticDetector(noisePx: 0, rng: Random(1)).detect(
    SyntheticCamera(image: const ImageSize(1600, 1500), fPx: 1280, distanceMm: 0.12 * 1280),
    sheetId: 0,
  ),
  sheetId: 0,
);

LiveAnalysis _analysis({bool ready = true, bool steady = true, int markers = 4}) => LiveAnalysis(
      size: const ImageSize(1600, 1500),
      markers: const [],
      markerCount: markers,
      geometryRejections: const [],
      instructions: ready ? const [] : const [PoseInstruction.closer],
      steady: steady,
      estimate: markers >= 3 ? _estimate : null,
    );

const _notStored = VisitNotStored(
  result: VisitResult(
    status: VisitStatus.ditolak,
    issue: null,
    budget: null,
    acceptedFrames: 0,
    excludedUnmeasurableFrames: 0,
    frameRejections: [],
  ),
  frames: [],
  reasons: ['Hanya 0 dari 6 foto diterima'],
);

Duration _t(int ms) => Duration(milliseconds: ms);

/// Feeds [n] good steady frames, 100 ms apart, starting at [from] ms.
CaptureState _steady(CaptureState s, int n, {int from = 0, FlowConfig config = const FlowConfig()}) {
  for (var i = 0; i < n; i++) {
    s = reduceCapture(s, AnalysisEvent(_analysis(), _t(from + 100 * i)), config: config);
  }
  return s;
}

CaptureState _ready() => _steady(const CaptureState(), 6);

void main() {
  group('aiming', () {
    test('starts waiting for markers', () {
      expect(const CaptureState().phase, CapturePhase.waitingForMarkers);
      expect(const CaptureState().canShoot, isFalse);
    });

    test('fewer than 3 markers or no analysis keeps waiting (and keeps the partial outlines)', () {
      var s = reduceCapture(const CaptureState(), AnalysisEvent(_analysis(markers: 2), _t(0)));
      expect(s.phase, CapturePhase.waitingForMarkers);
      expect(s.analysis!.markerCount, 2);
      s = reduceCapture(s, AnalysisEvent(null, _t(100)));
      expect(s.phase, CapturePhase.waitingForMarkers);
      expect(s.analysis, isNull);
    });

    test('a pose that is not ready is "adjusting" and resets the stability count', () {
      var s = _steady(const CaptureState(), 3);
      expect(s.stableCount, 3);
      s = reduceCapture(s, AnalysisEvent(_analysis(ready: false), _t(400)));
      expect(s.phase, CapturePhase.adjusting);
      expect(s.stableCount, 0);
    });

    test('needs the configured number of consecutive steady frames before ready', () {
      var s = const CaptureState();
      for (var i = 1; i <= 4; i++) {
        s = reduceCapture(s, AnalysisEvent(_analysis(), _t(100 * i)));
        expect(s.phase, CapturePhase.adjusting, reason: 'frame $i');
        expect(s.canShoot, isFalse);
      }
      s = reduceCapture(s, AnalysisEvent(_analysis(), _t(500)));
      expect(s.phase, CapturePhase.ready);
      expect(s.canShoot, isTrue);
    });

    test('a frame that is good but not steady restarts the count at 1', () {
      var s = _steady(const CaptureState(), 4);
      s = reduceCapture(s, AnalysisEvent(_analysis(steady: false), _t(500)));
      expect(s.stableCount, 1);
      expect(s.phase, CapturePhase.adjusting);
    });

    test('ready drops back to adjusting as soon as one frame is off', () {
      var s = _ready();
      expect(s.phase, CapturePhase.ready);
      s = reduceCapture(s, AnalysisEvent(_analysis(ready: false), _t(700)));
      expect(s.phase, CapturePhase.adjusting);
      expect(s.canShoot, isFalse);
    });

    test('a custom stability requirement is honoured', () {
      const cfg = FlowConfig(stableFramesRequired: 2);
      expect(_steady(const CaptureState(), 2, config: cfg).phase, CapturePhase.ready);
    });
  });

  group('stale detector', () {
    test('no analysis for longer than staleAfter disarms the shutter', () {
      final s = _ready();
      final at = s.lastAnalysisAt!;
      expect(reduceCapture(s, TickEvent(at + const Duration(milliseconds: 900))), same(s));
      final stale = reduceCapture(s, TickEvent(at + const Duration(milliseconds: 1100)));
      expect(stale.phase, CapturePhase.waitingForMarkers);
      expect(stale.canShoot, isFalse);
      expect(stale.stableCount, 0);
    });

    test('ticks never disturb burst, processing or result', () {
      var s = reduceCapture(_ready(), const ShutterEvent(6));
      expect(reduceCapture(s, const TickEvent(Duration(minutes: 5))), same(s));
    });
  });

  group('shutter and burst', () {
    test('the shutter works only when ready; otherwise the very same state is returned', () {
      for (final s in [
        const CaptureState(),
        reduceCapture(const CaptureState(), AnalysisEvent(_analysis(ready: false), _t(0))),
        _steady(const CaptureState(), 3),
      ]) {
        expect(reduceCapture(s, const ShutterEvent(6)), same(s));
      }
      final shot = reduceCapture(_ready(), const ShutterEvent(6));
      expect(shot.phase, CapturePhase.burst);
      expect(shot.burstTotal, 6);
      expect(shot.burstTaken, 0);
    });

    test('live frames are ignored during burst, processing, result and error', () {
      final states = <CaptureState>[];
      var s = reduceCapture(_ready(), const ShutterEvent(6));
      states.add(s);
      s = reduceCapture(s, const BurstDoneEvent(photoCount: 6, flags: []));
      states.add(s);
      s = reduceCapture(s, const ProcessedEvent(_notStored));
      states.add(s);
      states.add(reduceCapture(const CaptureState(), const FailedEvent('x')));
      for (final st in states) {
        expect(reduceCapture(st, AnalysisEvent(_analysis(), _t(9000))), same(st), reason: '${st.phase}');
        expect(reduceCapture(st, const ShutterEvent(6)), same(st), reason: '${st.phase}');
      }
    });

    test('burst progress, then processing progress, then result, carrying the capture flags', () {
      var s = reduceCapture(_ready(), const ShutterEvent(6));
      s = reduceCapture(s, const BurstProgressEvent(3));
      expect((s.phase, s.burstTaken, s.burstTotal), (CapturePhase.burst, 3, 6));
      s = reduceCapture(s, const BurstDoneEvent(photoCount: 6, flags: ['fokus_tidak_terkunci']));
      expect((s.phase, s.processTotal), (CapturePhase.processing, 6));
      expect(s.flags, ['fokus_tidak_terkunci']);
      s = reduceCapture(s, const ProcessProgressEvent(2, 6));
      expect((s.processDone, s.processTotal), (2, 6));
      s = reduceCapture(s, const ProcessedEvent(_notStored));
      expect(s.phase, CapturePhase.result);
      expect(s.outcome, same(_notStored));
      expect(s.flags, ['fokus_tidak_terkunci']);
    });

    test('progress events out of phase are ignored', () {
      final s = _ready();
      expect(reduceCapture(s, const BurstProgressEvent(2)), same(s));
      expect(reduceCapture(s, const BurstDoneEvent(photoCount: 6, flags: [])), same(s));
      expect(reduceCapture(s, const ProcessProgressEvent(1, 6)), same(s));
      expect(reduceCapture(s, const ProcessedEvent(_notStored)), same(s));
    });
  });

  group('errors and retry', () {
    test('a failure in any phase becomes the error phase with a specific message; the first message wins', () {
      for (final s in [const CaptureState(), _ready(), reduceCapture(_ready(), const ShutterEvent(6))]) {
        final e = reduceCapture(s, const FailedEvent('Kamera terputus'));
        expect(e.phase, CapturePhase.error);
        expect(e.error, 'Kamera terputus');
        expect(reduceCapture(e, const FailedEvent('lain')), same(e));
      }
    });

    test('retry returns to waiting from result and from error, and nowhere else', () {
      final result = reduceCapture(
        reduceCapture(reduceCapture(_ready(), const ShutterEvent(6)), const BurstDoneEvent(photoCount: 6, flags: [])),
        const ProcessedEvent(_notStored),
      );
      for (final s in [result, reduceCapture(_ready(), const FailedEvent('x'))]) {
        final r = reduceCapture(s, const RetryEvent());
        expect(r.phase, CapturePhase.waitingForMarkers);
        expect(r.analysis, isNull);
        expect(r.outcome, isNull);
        expect(r.error, isNull);
      }
      final ready = _ready();
      expect(reduceCapture(ready, const RetryEvent()), same(ready));
    });
  });
}
