// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart' show gaussian;
import 'package:test/test.dart';

TrendVisit v(
  double? w,
  double? uRand, {
  VisitStatus status = VisitStatus.terukur,
  String device = 'Pixel 7',
  String algo = 'p4-1',
  int sheet = 0,
}) =>
    TrendVisit(status: status, widthMm: w, uRand: uRand, deviceModel: device, algorithmVersion: algo, sheetId: sheet);

void main() {
  group('delta, u_delta, z, MDC (5.6, hand values)', () {
    // w0 0.30 (u_rand 0.01), w1 0.36 (u_rand 0.02), u_print_rel 0.01:
    // delta 0.06; u_delta = sqrt(0.01^2 + 0.02^2 + (0.06 * 0.01)^2) = sqrt(5.0036e-4) = 0.0223687282; z = 2.6823161
    final t = computeTrend([v(0.30, 0.01), v(0.36, 0.02)], uPrintRel: 0.01);
    final c = t[1].vsBaseline!;

    test('delta = w_i - w_0', () => expect(c.delta, closeTo(0.06, 1e-15)));
    test('u_delta = sqrt(u_rand_i^2 + u_rand_0^2 + (delta u_print_rel)^2)', () => expect(c.uDelta, closeTo(0.0223687282, 1e-9)));
    test('z = delta / u_delta', () => expect(c.z, closeTo(2.6823161130, 1e-8)));
    test('MDC = 2 u_delta', () => expect(c.mdc, closeTo(2 * 0.0223687282, 1e-9)));
    test('z >= 2 -> kemungkinan bertambah lebar', () => expect(c.classification, TrendClass.kemungkinanBertambahLebar));
    test('the baseline has no comparison with itself', () {
      expect(t[0].vsBaseline, isNull);
      expect(t[0].vsPrevious, isNull);
    });
    test('with two visits, "previous" equals "baseline"', () => expect(t[1].vsPrevious!.delta, c.delta));
  });

  group('classification boundaries (|z| < 2, z >= 2, z <= -2)', () {
    TrendClass cls(double w1) => computeTrend([v(1.0, 0.5), v(w1, 0.0)], uPrintRel: 0)[1].vsBaseline!.classification;
    // u_delta = 0.5 exactly, so delta = +-1 is z = +-2 exactly.
    test('z = +2 exactly -> bertambah lebar', () => expect(cls(2.0), TrendClass.kemungkinanBertambahLebar));
    test('z = -2 exactly -> menyempit', () => expect(cls(0.0), TrendClass.kemungkinanMenyempit));
    test('just inside +-2 -> tidak ada perubahan terdeteksi', () {
      expect(cls(1.99), TrendClass.tidakAdaPerubahanTerdeteksi);
      expect(cls(0.01), TrendClass.tidakAdaPerubahanTerdeteksi);
    });
    test('zero change: z = 0', () {
      final c = computeTrend([v(0.5, 0.01), v(0.5, 0.01)], uPrintRel: 0.01)[1].vsBaseline!;
      expect(c.z, 0);
      expect(c.classification, TrendClass.tidakAdaPerubahanTerdeteksi);
    });
  });

  group('systematic parts cancel (5.6)', () {
    VisitResult visit(double w, UncertaintyOptions o) {
      FrameRecord f(double x) => FrameRecord(status: MeasureStatus.terukur, widthMm: x, uFitRawMm: 0.004, rho: 1, uSigmaWMm: 0.003, dwDs: 0.01, mmPerPx: 0.06, rmsPx: 0.3, looMm: null, tiltDeg: 5);
      return aggregateVisit([for (final d in [0.0, 0.004, -0.004, 0.002, -0.002]) FrameInput.accepted(f(w + d))], options: o);
    }

    test('changing u_print and u_dev of the visits does not change u_delta (they are not inputs)', () {
      final lo = [visit(0.30, const UncertaintyOptions(uPrintRel: 0.0, uDevMm: 0.001)), visit(0.34, const UncertaintyOptions(uPrintRel: 0.0, uDevMm: 0.001))];
      final hi = [visit(0.30, const UncertaintyOptions(uPrintRel: 0.05, uDevMm: 0.05)), visit(0.34, const UncertaintyOptions(uPrintRel: 0.05, uDevMm: 0.05))];
      // the hi visits have a far larger u_c and U ...
      expect(hi[1].budget!.uC, greaterThan(2 * lo[1].budget!.uC));
      // ... but the trend between them has the same u_delta (the widths and u_rand are identical)
      final a = computeTrend([for (final r in lo) TrendVisit.fromVisit(r, deviceModel: 'X', algorithmVersion: 'p4-1', sheetId: 0)], uPrintRel: 0.01)[1].vsBaseline!;
      final b = computeTrend([for (final r in hi) TrendVisit.fromVisit(r, deviceModel: 'X', algorithmVersion: 'p4-1', sheetId: 0)], uPrintRel: 0.01)[1].vsBaseline!;
      expect(b.uDelta, a.uDelta);
      expect(b.z, a.z);
      expect(b.mdc, a.mdc);
    });

    test('the print-scale term enters only as (delta u_print_rel)^2: absent at delta = 0, present otherwise', () {
      double ud(double w1, double rel) => computeTrend([v(0.5, 0.01), v(w1, 0.01)], uPrintRel: rel)[1].vsBaseline!.uDelta!;
      expect(ud(0.5, 0.0), ud(0.5, 0.2)); // no change: relative scale error cancels completely
      expect(ud(0.6, 0.1), closeTo(sqrt(2 * 0.01 * 0.01 + pow(0.1 * 0.1, 2)), 1e-15));
    });
  });

  group('non-numeric visits form no delta', () {
    test('TIDAK_TERUKUR and DI_BAWAH_BATAS_UKUR are shown as tidak terukur, in both directions', () {
      final t = computeTrend([
        v(0.3, 0.01),
        v(null, null, status: VisitStatus.tidakTerukur),
        v(null, null, status: VisitStatus.dibawahBatasUkur),
        v(0.32, 0.01),
      ], uPrintRel: 0.01);
      expect(t[1].vsBaseline!.classification, TrendClass.tidakTerukur);
      expect(t[1].vsBaseline!.delta, isNull);
      expect(t[1].vsBaseline!.mdc, isNull);
      expect(t[2].vsBaseline!.classification, TrendClass.tidakTerukur);
      expect(t[2].vsPrevious!.classification, TrendClass.tidakTerukur);
      expect(t[3].vsPrevious!.classification, TrendClass.tidakTerukur); // previous visit has no number
      expect(t[3].vsBaseline!.classification, TrendClass.tidakAdaPerubahanTerdeteksi); // baseline is fine
    });

    test('an unmeasurable baseline gives no numeric delta for any visit', () {
      final t = computeTrend([v(null, null, status: VisitStatus.tidakTerukur), v(0.3, 0.01), v(0.5, 0.01)], uPrintRel: 0);
      expect(t[1].vsBaseline!.classification, TrendClass.tidakTerukur);
      expect(t[2].vsBaseline!.classification, TrendClass.tidakTerukur);
      expect(t[2].vsPrevious!.delta, closeTo(0.2, 1e-15)); // 0.3 -> 0.5 is numeric
    });
  });

  group('context warnings', () {
    test('different phone model, algorithm version or sheet each warn, per compared pair', () {
      final t = computeTrend([
        v(0.3, 0.01),
        v(0.3, 0.01, device: 'Galaxy S21'),
        v(0.3, 0.01, device: 'Galaxy S21', algo: 'p4-2'),
        v(0.3, 0.01, device: 'Galaxy S21', algo: 'p4-2', sheet: 3),
      ], uPrintRel: 0);
      expect(t[1].vsBaseline!.warnings, {ContextWarning.deviceModelDiffers});
      expect(t[2].vsBaseline!.warnings, {ContextWarning.deviceModelDiffers, ContextWarning.algorithmVersionDiffers});
      expect(t[2].vsPrevious!.warnings, {ContextWarning.algorithmVersionDiffers});
      expect(t[3].vsPrevious!.warnings, {ContextWarning.sheetDiffers});
      expect(t[3].vsBaseline!.warnings, {ContextWarning.deviceModelDiffers, ContextWarning.algorithmVersionDiffers, ContextWarning.sheetDiffers});
    });

    test('same context: no warnings', () => expect(computeTrend([v(0.3, 0.01), v(0.3, 0.01)], uPrintRel: 0)[1].vsBaseline!.warnings, isEmpty));

    test('a warning does not change the numbers', () {
      final a = computeTrend([v(0.3, 0.01), v(0.4, 0.01)], uPrintRel: 0.01)[1].vsBaseline!;
      final b = computeTrend([v(0.3, 0.01), v(0.4, 0.01, device: 'other')], uPrintRel: 0.01)[1].vsBaseline!;
      expect(b.z, a.z);
    });
  });

  test('no regression or extrapolation: a comparison depends only on its two visits', () {
    final a = computeTrend([v(0.30, 0.01), v(0.32, 0.01), v(0.34, 0.01)], uPrintRel: 0.01);
    final b = computeTrend([v(0.30, 0.01), v(0.32, 0.01), v(0.90, 0.01)], uPrintRel: 0.01);
    expect(b[1].vsBaseline!.z, a[1].vsBaseline!.z);
    expect(b[1].vsPrevious!.z, a[1].vsPrevious!.z);
    expect(a.length, 3); // one point per visit, nothing appended beyond the data
  });

  test('empty and single-visit series are handled', () {
    expect(computeTrend(const [], uPrintRel: 0), isEmpty);
    expect(computeTrend([v(0.3, 0.01)], uPrintRel: 0).single.vsBaseline, isNull);
  });

  group('statistics on synthetic series (seed 20261117, 20000 replications)', () {
    const reps = 20000;

    TrendComparison compare(double w0, double w1, double u) =>
        computeTrend([v(w0, u), v(w1, u)], uPrintRel: 0)[1].vsBaseline!;

    test('no real change, k=2: false positive rate matches the normal expectation P(|z| >= 2) = 4.55 percent', () {
      final rng = Random(20261117);
      const u = 0.01;
      var fp = 0;
      for (var i = 0; i < reps; i++) {
        final c = compare(0.5 + u * gaussian(rng), 0.5 + u * gaussian(rng), u);
        if (c.classification != TrendClass.tidakAdaPerubahanTerdeteksi) fp++;
      }
      final rate = fp / reps;
      // ignore: avoid_print
      print('false positive rate, no change, k=2: ${(100 * rate).toStringAsFixed(2)} percent of $reps (expected 4.55)');
      expect(rate, closeTo(0.0455, 0.0045)); // 3 sigma of the Monte Carlo error
    });

    test('a real change of exactly MDC is detected about half the time, 2 MDC about 97.7 percent', () {
      final rng = Random(7);
      const u = 0.01;
      final mdc = compare(0.5, 0.5, u).mdc!; // 2 sqrt(2) u
      double power(double change) {
        var hit = 0;
        for (var i = 0; i < reps; i++) {
          final c = compare(0.5 + u * gaussian(rng), 0.5 + change + u * gaussian(rng), u);
          if (c.classification == TrendClass.kemungkinanBertambahLebar) hit++;
        }
        return hit / reps;
      }

      final p1 = power(mdc), p2 = power(2 * mdc);
      // ignore: avoid_print
      print('detection rate: change = MDC ${(100 * p1).toStringAsFixed(1)} percent (expected 50), 2 MDC ${(100 * p2).toStringAsFixed(1)} percent (expected 97.7)');
      expect(p1, closeTo(0.5, 0.02));
      expect(p2, closeTo(0.977, 0.006));
    });

    test('a narrowing of 2 MDC is classified as narrowing, never as widening', () {
      final rng = Random(8);
      const u = 0.01;
      final mdc = compare(0.5, 0.5, u).mdc!;
      var narrow = 0, wide = 0;
      for (var i = 0; i < 5000; i++) {
        final c = compare(0.5 + u * gaussian(rng), 0.5 - 2 * mdc + u * gaussian(rng), u);
        if (c.classification == TrendClass.kemungkinanMenyempit) narrow++;
        if (c.classification == TrendClass.kemungkinanBertambahLebar) wide++;
      }
      expect(wide, 0);
      expect(narrow / 5000, closeTo(0.977, 0.01));
    });
  });
}
