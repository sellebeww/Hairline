// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

FrameRecord rec(double w, {MeasureStatus status = MeasureStatus.terukur}) => FrameRecord(
      status: status,
      widthMm: w,
      uFitRawMm: 0.004,
      rho: 1,
      uSigmaWMm: 0.003,
      dwDs: 0.01,
      mmPerPx: 0.06,
      rmsPx: 0.3,
      looMm: null,
      tiltDeg: 5,
    );

FrameInput ok(double w, {MeasureStatus status = MeasureStatus.terukur}) => FrameInput.accepted(rec(w, status: status));
const bad = FrameInput.rejected(geometry: [FrameRejection.tiltTooHigh]);

void main() {
  test('5 accepted frames: median width, full budget, status TERUKUR', () {
    final r = aggregateVisit([ok(0.50), ok(0.52), ok(0.49), ok(0.51), ok(0.50)]);
    expect(r.status, VisitStatus.terukur);
    expect(r.budget!.n, 5);
    expect(r.budget!.widthMm, 0.50);
    expect(r.reportableWidthMm, 0.50);
    expect(r.storable, isTrue);
    expect(r.issue, isNull);
  });

  test('the median ignores one gross outlier frame', () {
    final r = aggregateVisit([ok(0.5), ok(0.5), ok(0.5), ok(0.5), ok(0.9)]);
    expect(r.budget!.widthMm, 0.5);
  });

  group('visit gate (5.4)', () {
    test('2 accepted of 5: DITOLAK, not storable, structured reasons per frame', () {
      final r = aggregateVisit([
        ok(0.5),
        bad,
        const FrameInput.rejected(measure: RejectReason.blurTooLarge),
        const FrameInput.rejected(geometry: [FrameRejection.rmsTooHigh, FrameRejection.looTooHigh]),
        ok(0.5),
      ]);
      expect(r.status, VisitStatus.ditolak);
      expect(r.issue, VisitIssue.tooFewAcceptedFrames);
      expect(r.storable, isFalse);
      expect(r.budget, isNull);
      expect(r.reportableWidthMm, isNull);
      expect(r.acceptedFrames, 2);
      expect(r.frameRejections, [
        (frame: 1, code: 'TILT_TOO_HIGH'),
        (frame: 2, code: 'BLUR_TOO_LARGE'),
        (frame: 3, code: 'RMS_TOO_HIGH'),
        (frame: 3, code: 'LOO_TOO_HIGH'),
      ]);
      expect(r.rejectionCounts, {'TILT_TOO_HIGH': 1, 'BLUR_TOO_LARGE': 1, 'RMS_TOO_HIGH': 1, 'LOO_TOO_HIGH': 1});
    });

    test('exactly 3 accepted frames is enough', () {
      final r = aggregateVisit([ok(0.5), bad, ok(0.51), bad, ok(0.49)]);
      expect(r.status, VisitStatus.terukur);
      expect(r.budget!.n, 3);
    });

    test('thresholds can raise the minimum', () {
      final r = aggregateVisit([ok(0.5), ok(0.5), ok(0.5)], thresholds: const QualityThresholds(minAcceptedFrames: 4));
      expect(r.status, VisitStatus.ditolak);
    });

    test('only maxStoredFrames (5) accepted frames are used', () {
      final r = aggregateVisit([for (var i = 0; i < 7; i++) ok(0.5 + 0.001 * i)]);
      expect(r.budget!.n, 5);
      expect(r.acceptedFrames, 5);
    });
  });

  group('TIDAK_TERUKUR and below the limit', () {
    test('3 accepted frames of which 1 is TIDAK_TERUKUR: only 2 usable -> TIDAK_TERUKUR, no number', () {
      final r = aggregateVisit([ok(0.5), ok(0.5), ok(0.1, status: MeasureStatus.tidakTerukur)]);
      expect(r.status, VisitStatus.tidakTerukur);
      expect(r.issue, VisitIssue.mostlyUnmeasurable);
      expect(r.reportableWidthMm, isNull);
      expect(r.budget, isNull);
      expect(r.storable, isTrue); // an accepted visit that could not be measured is still a visit
    });

    test('5 accepted with 1 TIDAK_TERUKUR: it is excluded, n = 4, and the count is reported', () {
      final r = aggregateVisit([ok(0.5), ok(0.5), ok(0.51), ok(0.49), ok(0.0, status: MeasureStatus.tidakTerukur)]);
      expect(r.status, VisitStatus.terukur);
      expect(r.budget!.n, 4);
      expect(r.excludedUnmeasurableFrames, 1);
    });

    test('5 accepted with 3 TIDAK_TERUKUR: not a majority of usable frames -> TIDAK_TERUKUR', () {
      final r = aggregateVisit([ok(0.5), ok(0.5), for (var i = 0; i < 3; i++) ok(0.0, status: MeasureStatus.tidakTerukur)]);
      expect(r.status, VisitStatus.tidakTerukur);
    });

    test('frame-level DI_BAWAH_BATAS_UKUR estimates still feed the median; the visit floor decides', () {
      final r = aggregateVisit([for (var i = 0; i < 5; i++) ok(0.5, status: MeasureStatus.dibawahBatasUkur)]);
      expect(r.status, VisitStatus.terukur); // 0.5 mm is far above the visit floor
    });

    test('width under the visit floor: DI_BAWAH_BATAS_UKUR, number withheld, floor available', () {
      final r = aggregateVisit([ok(0.05), ok(0.04), ok(0.06), ok(0.05), ok(0.05)]);
      expect(r.status, VisitStatus.dibawahBatasUkur);
      expect(r.reportableWidthMm, isNull);
      expect(r.budget!.floorMm, greaterThanOrEqualTo(0.03));
      expect(r.storable, isTrue);
    });
  });

  test('options flow into the budget (u_print, validated u_dev)', () {
    final r = aggregateVisit([ok(0.5), ok(0.5), ok(0.5)], options: const UncertaintyOptions(uPrintRel: 0.02, uDevMm: 0.003));
    expect(r.budget!.uPrint, closeTo(0.01, 1e-12));
    expect(r.budget!.belumDivalidasi, isFalse);
  });

  test('status codes are stable', () {
    expect(VisitStatus.values.map((s) => s.code), ['DITOLAK', 'TERUKUR', 'DI_BAWAH_BATAS_UKUR', 'TIDAK_TERUKUR']);
  });
}
