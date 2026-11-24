// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/capture_flow.dart';
import 'package:hairline/capture/capture_overlay.dart';
import 'package:hairline/capture/live_analysis.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

const _size = ImageSize(1600, 1500);
// Built from the code point so that this file itself stays free of the character (CLAUDE.md section 2).
final _emDash = String.fromCharCode(0x2014);
final _cam = SyntheticCamera(image: _size, fPx: 1280, distanceMm: 0.12 * 1280, tiltDeg: 4, rollDeg: 6);
final _dets = SyntheticDetector(noisePx: 0, rng: Random(1)).detect(_cam, sheetId: 0);
final _estimate = estimateSheetHomography(_dets, sheetId: 0);

PoseDeviation _deviation(List<PoseInstruction> instr) => PoseDeviation(
      dxFrac: 0.08,
      dyFrac: 0,
      scaleRatio: 1.0,
      rotationDeg: 0,
      tiltDeltaDeg: 0,
      instructions: instr,
    );

LiveAnalysis _analysis({
  List<PoseInstruction> instructions = const [],
  List<FrameRejection> rejections = const [],
  bool withGhost = true,
}) =>
    LiveAnalysis(
      size: _size,
      markers: [for (final d in _dets) d.corners],
      markerCount: 4,
      geometryRejections: rejections,
      instructions: instructions,
      steady: true,
      estimate: _estimate,
      deviation: _deviation(instructions),
      tiltDeg: 5.4,
      mmPerPx: 0.1234,
      windowQuad: const [Pt(400, 400), Pt(1200, 400), Pt(1200, 1100), Pt(400, 1100)],
      pointPx: const Pt(800, 750),
      ghost: withGhost ? [for (final d in _dets) [for (final c in d.corners) c + const Pt(60, 0)]] : const [],
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

VisitResult _result(VisitStatus s, {int accepted = 4}) => VisitResult(
      status: s,
      issue: null,
      budget: null,
      acceptedFrames: accepted,
      excludedUnmeasurableFrames: 0,
      frameRejections: const [],
    );

void main() {
  group('GuidanceBanner: every state says it in text and icon, not by color alone', () {
    testWidgets('waiting for markers: error icon and the plain reason', (tester) async {
      await tester.pumpWidget(_host(const GuidanceBanner(state: CaptureState())));
      expect(find.text(Strings.statusWaiting), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('each pose instruction shows its Indonesian text and its own icon', (tester) async {
      for (final i in PoseInstruction.values) {
        await tester.pumpWidget(_host(GuidanceBanner(
          state: CaptureState(phase: CapturePhase.adjusting, analysis: _analysis(instructions: [i])),
        )));
        expect(find.text(Strings.instruction(i)), findsOneWidget, reason: i.code);
        expect(find.byIcon(instructionIcon(i)), findsOneWidget, reason: i.code);
      }
    });

    testWidgets('adjusting with deviation data shows tilt and scale as approximations plus the marker count', (tester) async {
      await tester.pumpWidget(_host(GuidanceBanner(
        state: CaptureState(phase: CapturePhase.adjusting, analysis: _analysis(instructions: [PoseInstruction.moveLeft])),
      )));
      expect(find.text(Strings.instruction(PoseInstruction.moveLeft)), findsOneWidget);
      expect(find.text(Strings.markersSeen(4)), findsOneWidget);
      expect(find.textContaining('perkiraan'), findsWidgets);
      expect(find.textContaining('perkiraan: 5 derajat'), findsOneWidget);
      expect(find.textContaining('0,123 mm per piksel'), findsOneWidget);
    });

    testWidgets('a rejection from the 5.4 gate is shown specifically ("terlalu miring")', (tester) async {
      await tester.pumpWidget(_host(GuidanceBanner(
        state: CaptureState(phase: CapturePhase.adjusting, analysis: _analysis(rejections: [FrameRejection.tiltTooHigh])),
      )));
      expect(find.text('Terlalu miring'), findsOneWidget);
    });

    testWidgets('ready: check icon and "siap diambil"', (tester) async {
      await tester.pumpWidget(_host(GuidanceBanner(state: CaptureState(phase: CapturePhase.ready, analysis: _analysis()))));
      expect(find.text(Strings.statusReady), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('the banner is a live region so screen readers announce changes', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(GuidanceBanner(state: CaptureState(phase: CapturePhase.ready, analysis: _analysis()))));
      expect(tester.getSemantics(find.byType(GuidanceBanner)).label, contains(Strings.statusReady));
      handle.dispose();
    });
  });

  group('guide level', () {
    test('mapping of phases to green, yellow and red (with icons)', () {
      expect(guideLevelOf(const CaptureState()), GuideLevel.blocked);
      expect(guideLevelOf(CaptureState(phase: CapturePhase.adjusting, analysis: _analysis())), GuideLevel.adjust);
      expect(guideLevelOf(CaptureState(phase: CapturePhase.ready, analysis: _analysis())), GuideLevel.ok);
      expect(guideLevelOf(const CaptureState(phase: CapturePhase.error)), GuideLevel.blocked);
      for (final l in GuideLevel.values) {
        expect(guideIcon(l), isNotNull);
      }
      expect({for (final l in GuideLevel.values) guideIcon(l)}, hasLength(3), reason: 'three distinct icons');
      expect({for (final l in GuideLevel.values) guideColor(l)}, hasLength(3));
    });
  });

  group('CaptureOverlayPainter', () {
    testWidgets('paints outlines, ghost, window and point without errors at any canvas size', (tester) async {
      for (final size in const [Size(300, 400), Size(1080, 1440), Size(10, 10)]) {
        await tester.pumpWidget(_host(SizedBox.fromSize(
          size: size,
          child: CustomPaint(painter: CaptureOverlayPainter(analysis: _analysis(), level: GuideLevel.adjust)),
        )));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('draws nothing and does not fail without an analysis', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 100,
        height: 100,
        child: CustomPaint(painter: CaptureOverlayPainter(analysis: null, level: GuideLevel.blocked)),
      )));
      expect(tester.takeException(), isNull);
    });

    test('repaints only when the analysis or the level changes', () {
      final a = _analysis();
      final p = CaptureOverlayPainter(analysis: a, level: GuideLevel.ok);
      expect(p.shouldRepaint(CaptureOverlayPainter(analysis: a, level: GuideLevel.ok)), isFalse);
      expect(p.shouldRepaint(CaptureOverlayPainter(analysis: a, level: GuideLevel.adjust)), isTrue);
      expect(p.shouldRepaint(CaptureOverlayPainter(analysis: _analysis(), level: GuideLevel.ok)), isTrue);
    });
  });

  group('result card', () {
    test('a visit that failed the gate lists the specific reasons and no measurement', () {
      final lines = outcomeLines(
        VisitNotStored(result: _result(VisitStatus.ditolak, accepted: 1), frames: const [], reasons: const ['Hanya 1 dari 6 foto diterima', 'Foto terlalu buram']),
        const [],
      );
      expect(lines, ['Hanya 1 dari 6 foto diterima', 'Foto terlalu buram']);
    });

    test('a stored but not measurable visit shows no number, the honest statement, and never says "aman"', () {
      final lines = outcomeLines(VisitStored(result: _result(VisitStatus.tidakTerukur), frames: const [], visitId: 1), const []);
      expect(lines, contains(Strings.statusNotMeasurable));
      expect(lines, contains(Strings.resultIndicative));
      expect(lines.join(' ').toLowerCase(), isNot(contains('aman')));
      expect(lines.join(' '), isNot(matches(RegExp(r'Lebar \d'))));
    });

    test('capture flags become explicit warnings about focus and exposure', () {
      final lines = outcomeLines(
        VisitStored(result: _result(VisitStatus.tidakTerukur), frames: const [], visitId: 1),
        const [Strings.flagFocusNotLocked, Strings.flagExposureNotLocked],
      );
      expect(lines, containsAll([Strings.warnFocusNotLocked, Strings.warnExposureNotLocked]));
    });

    testWidgets('the card renders every line', (tester) async {
      await tester.pumpWidget(_host(OutcomeSummary(
        outcome: VisitNotStored(result: _result(VisitStatus.ditolak), frames: const [], reasons: const ['Alasan satu', 'Alasan dua']),
        flags: const [],
      )));
      expect(find.text('Alasan satu'), findsOneWidget);
      expect(find.text('Alasan dua'), findsOneWidget);
    });
  });

  group('catalog', () {
    test('every instruction and rejection has a non-empty Indonesian text without an em dash', () {
      for (final i in PoseInstruction.values) {
        expect(Strings.instruction(i), isNotEmpty);
        expect(Strings.instruction(i), isNot(contains(_emDash)));
      }
      for (final r in FrameRejection.values) {
        expect(Strings.rejection(r), isNotEmpty);
        expect(Strings.rejection(r), isNot(contains(_emDash)));
      }
    });
  });
}
