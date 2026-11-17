// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

FrameGeometry _g({
  int markers = 4,
  double rms = 0.3,
  double? loo = 0.1,
  double tilt = 5,
  double mmPerPx = 0.08,
}) =>
    FrameGeometry(markerCount: markers, rmsPx: rms, looMm: loo, tiltDeg: tilt, mmPerPx: mmPerPx);

void main() {
  group('QualityThresholds values (5.4)', () {
    test('defaults equal the CLAUDE.md 5.4 numbers', () {
      const t = QualityThresholds.standard;
      expect(t.minMarkers, 3);
      expect(t.recommendedMarkers, 4);
      expect(t.maxRmsPx, 0.8);
      expect(t.maxLooMm, 0.3);
      expect(t.maxTiltDeg, 20);
      expect(t.hardRejectTiltDeg, 30);
      expect(t.maxMmPerPx, 0.20);
      expect(t.targetMmPerPx, 0.10);
      expect(t.maxSigmaPx, 2.5);
      expect(t.maxBlurAnisotropy, 1.6);
      expect(t.maxSaturatedFraction, 0.01);
      expect(t.minAcceptedFrames, 3);
      expect(t.maxStoredFrames, 5);
    });
  });

  group('frame geometry gate', () {
    test('a good 4-marker frame is accepted without issues', () {
      final v = evaluateFrameGeometry(_g());
      expect(v.accepted, isTrue);
      expect(v.rejections, isEmpty);
      expect(v.warnings, isEmpty);
    });

    test('3 markers are accepted with a warning (4 recommended)', () {
      final v = evaluateFrameGeometry(_g(markers: 3, loo: null));
      expect(v.accepted, isTrue);
      expect(v.warnings, [FrameWarning.onlyThreeMarkers]);
    });

    test('fewer than 3 markers: rejected, markers hidden', () {
      final v = evaluateFrameGeometry(_g(markers: 2, loo: null));
      expect(v.accepted, isFalse);
      expect(v.rejections, [FrameRejection.tooFewMarkers]);
    });

    test('rms_px: 0.8 accepted, above rejected', () {
      expect(evaluateFrameGeometry(_g(rms: 0.8)).accepted, isTrue);
      expect(evaluateFrameGeometry(_g(rms: 0.81)).rejections, [FrameRejection.rmsTooHigh]);
    });

    test('loo_mm: 0.3 accepted, above rejected, absent ignored', () {
      expect(evaluateFrameGeometry(_g(loo: 0.3)).accepted, isTrue);
      expect(evaluateFrameGeometry(_g(loo: 0.31)).rejections, [FrameRejection.looTooHigh]);
      expect(evaluateFrameGeometry(_g(markers: 3, loo: null)).rejections, isEmpty);
    });

    test('tilt: 20 accepted; 20..30 soft reject; above 30 hard reject only', () {
      expect(evaluateFrameGeometry(_g(tilt: 20)).accepted, isTrue);
      expect(evaluateFrameGeometry(_g(tilt: 25)).rejections, [FrameRejection.tiltTooHigh]);
      expect(evaluateFrameGeometry(_g(tilt: 30)).rejections, [FrameRejection.tiltTooHigh]);
      expect(evaluateFrameGeometry(_g(tilt: 30.1)).rejections, [FrameRejection.tiltHardReject]);
    });

    test('mm_per_px: 0.20 accepted, above rejected; above 0.10 warns', () {
      expect(evaluateFrameGeometry(_g(mmPerPx: 0.10)).warnings, isEmpty);
      final a = evaluateFrameGeometry(_g(mmPerPx: 0.15));
      expect(a.accepted, isTrue);
      expect(a.warnings, [FrameWarning.mmPerPxAboveTarget]);
      expect(evaluateFrameGeometry(_g(mmPerPx: 0.20)).accepted, isTrue);
      expect(evaluateFrameGeometry(_g(mmPerPx: 0.21)).rejections, [FrameRejection.resolutionTooCoarse]);
    });

    test('multiple failures are all reported, in a fixed order', () {
      final v = evaluateFrameGeometry(_g(rms: 2, loo: 1, tilt: 40, mmPerPx: 0.5));
      expect(v.rejections, [
        FrameRejection.rmsTooHigh,
        FrameRejection.looTooHigh,
        FrameRejection.tiltHardReject,
        FrameRejection.resolutionTooCoarse,
      ]);
    });

    test('custom thresholds apply', () {
      const t = QualityThresholds(maxRmsPx: 0.2);
      expect(evaluateFrameGeometry(_g(rms: 0.3), thresholds: t).rejections, [FrameRejection.rmsTooHigh]);
    });

    test('rejection and warning codes are unique upper snake case (UI maps them to Indonesian text)', () {
      for (final r in FrameRejection.values) {
        expect(r.code, matches(RegExp(r'^[A-Z_]+$')));
      }
      expect({for (final r in FrameRejection.values) r.code}.length, FrameRejection.values.length);
      expect({for (final w in FrameWarning.values) w.code}.length, FrameWarning.values.length);
    });
  });

  group('visit gate', () {
    test('needs >= 3 accepted frames', () {
      expect(isVisitAccepted(3), isTrue);
      expect(isVisitAccepted(5), isTrue);
      expect(isVisitAccepted(2), isFalse);
      expect(isVisitAccepted(0), isFalse);
    });

    test('custom minimum', () {
      expect(isVisitAccepted(4, thresholds: const QualityThresholds(minAcceptedFrames: 5)), isFalse);
    });
  });
}
