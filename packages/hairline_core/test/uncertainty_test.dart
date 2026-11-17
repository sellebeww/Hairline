// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

FrameRecord frame(
  double w, {
  double uFitRaw = 0.004,
  double rho = 1,
  double uSigmaW = 0.003,
  double dwDs = 0.02,
  double mmPerPx = 0.06,
  double rmsPx = 0.3,
  double? loo,
  double tilt = 10,
  MeasureStatus status = MeasureStatus.terukur,
}) =>
    FrameRecord(
      status: status,
      widthMm: w,
      uFitRawMm: uFitRaw,
      rho: rho,
      uSigmaWMm: uSigmaW,
      dwDs: dwDs,
      mmPerPx: mmPerPx,
      rmsPx: rmsPx,
      looMm: loo,
      tiltDeg: tilt,
    );

List<FrameRecord> burst([List<double> w = const [0.50, 0.51, 0.49, 0.50, 0.52], double? loo]) => [for (final x in w) frame(x, loo: loo)];

void main() {
  group('components (hand values, 5 frames: 0.50 0.51 0.49 0.50 0.52 mm, u_fit 4 um, tilt 10 deg, 0.06 mm/px)', () {
    final b = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(uPrintRel: 0.01));

    test('w is the median and n is the frame count', () {
      expect(b.widthMm, 0.50);
      expect(b.n, 5);
    });

    test('u_fit_mean = sqrt(sum u_fit_i^2)/n = 0.004 sqrt(5)/5', () => expect(b.uFitMean, closeTo(0.0017888544, 1e-9)));

    test('u_repeat = s_w/sqrt(n): s_w = 0.011401754 -> 0.005099020', () => expect(b.uRepeat, closeTo(0.0050990195, 1e-9)));

    test('u_stat = max(u_fit_mean, u_repeat)', () => expect(b.uStat, closeTo(0.0050990195, 1e-9)));

    test('u_sigma_w is the frame mean of the PSF-driven width uncertainty', () => expect(b.uSigmaW, closeTo(0.003, 1e-12)));

    test('u_pos = |dw/ds| max(rms_mm, 0.05): rms_mm 0.018 is below 0.05 -> 0.02 * 0.05', () => expect(b.uPos, closeTo(0.001, 1e-12)));

    test('u_par = dz |tan tilt| / sqrt(3) with dz 0.3: 0.030540729', () => expect(b.uPar, closeTo(0.0305407289, 1e-9)));

    test('u_geo = w sqrt(rms_mm^2 + loo_mm^2)/120 with no loo: 0.5 * 0.018 / 120', () => expect(b.uGeo, closeTo(7.5e-5, 1e-12)));

    test('u_print = w u_print_rel = 0.5 * 0.01', () => expect(b.uPrint, closeTo(0.005, 1e-12)));

    test('no validation: u_dev = 0.5 mm/px = 0.03 and BELUM_DIVALIDASI', () {
      expect(b.uDev, closeTo(0.03, 1e-12));
      expect(b.belumDivalidasi, isTrue);
    });

    test('u_rand, u_sys, u_c compose in quadrature', () {
      expect(b.uRand, closeTo(0.0311246164, 1e-9));
      expect(b.uSys, closeTo(0.0304138127, 1e-9));
      expect(b.uC, closeTo(0.0435171432, 1e-9));
      expect(b.uC * b.uC, closeTo(b.uRand * b.uRand + b.uSys * b.uSys, 1e-15));
    });

    test('dof_eff by Welch-Satterthwaite (u_stat has n-1 dof) and k, U = k u_c', () {
      expect(b.dofEff, closeTo(21220.46, 0.5)); // uc^4 / (u_stat^4 / 4)
      expect(b.k, closeTo(normalQuantile975, 3e-4)); // dof is huge: the normal limit (1/dof interpolation leaves 1.1e-4)
      expect(b.uExpanded, closeTo(b.k * b.uC, 1e-15));
    });

    test('floor = max(0.5 mm/px, 2 u_c) = 0.087034; w 0.5 is above it', () {
      expect(b.floorMm, closeTo(0.0870342863, 1e-9));
      expect(b.belowFloor, isFalse);
    });
  });

  test('u_stat takes u_fit_mean when frames agree exactly (s_w = 0)', () {
    final b = UncertaintyBudget.fromFrames([for (var i = 0; i < 4; i++) frame(0.3, uFitRaw: 0.01)], const UncertaintyOptions());
    expect(b.uRepeat, 0);
    expect(b.uFitMean, closeTo(0.01 * 2 / 4, 1e-15)); // sqrt(4 * 1e-4)/4 = 0.005
    expect(b.uStat, b.uFitMean);
  });

  test('with loo_mm: rms_mm = loo_mm for u_pos and u_geo gets sqrt(rms_mm^2 + loo_mm^2) (5.5 literally)', () {
    final b = UncertaintyBudget.fromFrames(burst(const [0.5, 0.5, 0.5], 0.2), const UncertaintyOptions());
    expect(b.uPos, closeTo(0.02 * 0.2, 1e-12));
    expect(b.uGeo, closeTo(0.5 * sqrt(0.2 * 0.2 * 2) / 120, 1e-12));
  });

  test('rho inflates u_fit by sqrt(rho) through the frame record', () {
    final a = frame(0.5, uFitRaw: 0.01, rho: 1).uFitMm, b = frame(0.5, uFitRaw: 0.01, rho: 4).uFitMm;
    expect(b, closeTo(2 * a, 1e-15));
    expect(frame(0.5, uFitRaw: 0.01, rho: 1).withRho(9).uFitMm, closeTo(0.03, 1e-15));
  });

  test('validated u_dev replaces the default and clears BELUM_DIVALIDASI', () {
    final b = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(uDevMm: 0.004));
    expect(b.uDev, 0.004);
    expect(b.belumDivalidasi, isFalse);
  });

  test('dz option: 1.0 mm relief gives u_par = 1.0 tan(10 deg)/sqrt(3)', () {
    final b = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(dzMm: 1.0));
    expect(b.uPar, closeTo(tan(10 * pi / 180) / sqrt(3), 1e-12));
  });

  test('k is the t factor with 4 dof when u_stat alone makes up u_c (n = 5)', () {
    final fr = [for (final w in [0.50, 0.52, 0.48, 0.51, 0.49]) frame(w, uSigmaW: 0, dwDs: 0, tilt: 0, rmsPx: 0, uFitRaw: 0)];
    final b = UncertaintyBudget.fromFrames(fr, const UncertaintyOptions(uDevMm: 0));
    expect(b.uC, closeTo(b.uStat, 1e-15));
    expect(b.dofEff, closeTo(4, 1e-9));
    expect(b.k, studentT975(4));
  });

  group('random vs systematic separation (5.5)', () {
    test('u_print and u_dev change u_sys and u_c but never u_rand or u_stat', () {
      final base = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(uPrintRel: 0.0, uDevMm: 0.001));
      final more = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(uPrintRel: 0.05, uDevMm: 0.02));
      expect(more.uRand, base.uRand);
      expect(more.uStat, base.uStat);
      expect(more.uSys, greaterThan(base.uSys));
      expect(more.uC, greaterThan(base.uC));
    });

    test('u_par, u_geo, u_pos, u_sigma_w are random components (they enter u_rand)', () {
      final a = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(dzMm: 0.3));
      final b = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(dzMm: 1.0));
      expect(b.uRand, greaterThan(a.uRand));
      expect(b.uSys, a.uSys);
    });
  });

  test('below the floor: w smaller than max(0.5 mm/px, 2 u_c) is flagged', () {
    final b = UncertaintyBudget.fromFrames(burst(const [0.04, 0.05, 0.045, 0.05, 0.04]), const UncertaintyOptions());
    expect(b.belowFloor, isTrue);
    expect(b.floorMm, greaterThanOrEqualTo(0.5 * 0.06));
  });

  test('needs at least 3 frames', () {
    expect(() => UncertaintyBudget.fromFrames([frame(0.5), frame(0.5)], const UncertaintyOptions()), throwsArgumentError);
  });

  test('unknown dw/ds on every frame: u_pos is 0 and the budget says so', () {
    final b = UncertaintyBudget.fromFrames([for (var i = 0; i < 3; i++) frame(0.5, dwDs: double.nan)], const UncertaintyOptions());
    expect(b.uPos, 0);
    expect(b.dwDsUnknown, isTrue);
  });

  test('toJson has the documented stable key order and values in mm', () {
    final b = UncertaintyBudget.fromFrames(burst(), const UncertaintyOptions(uPrintRel: 0.01));
    final j = b.toJson();
    expect(j.keys.toList(), [
      'n', 'width_mm', 'u_fit_mean', 'u_repeat', 'u_stat', 'u_sigma_w', 'u_pos', 'u_par', 'u_geo', 'u_print', 'u_dev', //
      'u_rand', 'u_sys', 'u_c', 'dof_eff', 'k', 'u_expanded', 'floor_mm', 'mm_per_px', 'belum_divalidasi', 'dw_ds_unknown',
    ]);
    expect(j['belum_divalidasi'], isTrue);
    expect(j['u_expanded'], closeTo(b.uExpanded, 1e-15));
  });
}
