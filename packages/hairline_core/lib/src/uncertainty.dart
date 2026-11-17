// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'measure.dart';
import 'stats.dart';
import 'student_t.dart';

/// Default `dz` (mm): surface relief out of the sheet plane (5.5). The user may pick 1.0.
const double defaultReliefMm = 0.3;

/// Starting `u_dev` as a fraction of `mm_per_px` when no device validation exists
/// (5.5): CONSERVATIVE and UNVALIDATED, the result is then flagged BELUM_DIVALIDASI.
const double defaultUDevPerMmPerPx = 0.5;

/// What the budget needs from one accepted frame (a [FrameMeasurement] plus the
/// geometry of its homography). `u_fit` is stored without the variance inflation
/// `rho` so that calibration can replay frames with another `rho` (5.3).
final class FrameRecord {
  const FrameRecord({
    required this.status,
    required this.widthMm,
    required this.uFitRawMm,
    required this.rho,
    required this.uSigmaWMm,
    required this.dwDs,
    required this.mmPerPx,
    required this.rmsPx,
    required this.looMm,
    required this.tiltDeg,
  });

  factory FrameRecord.fromMeasurement(
    FrameMeasurement m, {
    required double rmsPx,
    required double? looMm,
    required double tiltDeg,
  }) =>
      FrameRecord(
        status: m.status,
        widthMm: m.widthMm,
        uFitRawMm: m.fit.uWidthRawMm,
        rho: m.rho,
        uSigmaWMm: m.uSigmaWMm,
        dwDs: m.fit.dwDs,
        mmPerPx: m.mmPerPx,
        rmsPx: rmsPx,
        looMm: looMm,
        tiltDeg: tiltDeg,
      );

  final MeasureStatus status;
  final double widthMm;

  /// `sqrt(Var(w))` of the fit without inflation (mm).
  final double uFitRawMm;
  final double rho;
  final double uSigmaWMm;

  /// OLS slope of width along the crack (mm/mm); NaN if not estimable.
  final double dwDs;
  final double mmPerPx;
  final double rmsPx;

  /// Leave-one-marker-out RMS (mm), null with 3 markers.
  final double? looMm;
  final double tiltDeg;

  /// `u_fit = sqrt(rho Var(w))` (mm).
  double get uFitMm => sqrt(rho) * uFitRawMm;

  /// Same frame with another status (the pipeline demotes a MODEL_MISFIT frame).
  FrameRecord withStatus(MeasureStatus newStatus) => FrameRecord(
        status: newStatus,
        widthMm: widthMm,
        uFitRawMm: uFitRawMm,
        rho: rho,
        uSigmaWMm: uSigmaWMm,
        dwDs: dwDs,
        mmPerPx: mmPerPx,
        rmsPx: rmsPx,
        looMm: looMm,
        tiltDeg: tiltDeg,
      );

  /// Same frame with another variance inflation factor.
  FrameRecord withRho(double newRho) => FrameRecord(
        status: status,
        widthMm: widthMm,
        uFitRawMm: uFitRawMm,
        rho: newRho,
        uSigmaWMm: uSigmaWMm,
        dwDs: dwDs,
        mmPerPx: mmPerPx,
        rmsPx: rmsPx,
        looMm: looMm,
        tiltDeg: tiltDeg,
      );

  /// Position error of the sheet in mm (5.5 `rms_mm`): `loo_mm` when available,
  /// else `rms_px * mm_per_px`.
  double get rmsMm => looMm ?? rmsPx * mmPerPx;
}

/// Inputs of the budget that are not frame data.
final class UncertaintyOptions {
  const UncertaintyOptions({this.dzMm = defaultReliefMm, this.uPrintRel = 0, this.uDevMm});

  /// Surface relief `dz` (mm).
  final double dzMm;

  /// Relative standard uncertainty of the printed scale (`print_scale_u_rel`, 5.1).
  final double uPrintRel;

  /// `u_dev` from the latest PERANGKAT validation for this phone at a comparable
  /// width (validation.dart). Null: use the unvalidated default.
  final double? uDevMm;
}

/// The 5.5 uncertainty budget of one visit, every component explicit (mm, standard
/// uncertainties).
final class UncertaintyBudget {
  const UncertaintyBudget({
    required this.n,
    required this.widthMm,
    required this.uFitMean,
    required this.uRepeat,
    required this.uStat,
    required this.uSigmaW,
    required this.uPos,
    required this.uPar,
    required this.uGeo,
    required this.uPrint,
    required this.uDev,
    required this.uRand,
    required this.uSys,
    required this.uC,
    required this.dofEff,
    required this.k,
    required this.uExpanded,
    required this.floorMm,
    required this.mmPerPx,
    required this.belumDivalidasi,
    required this.dwDsUnknown,
  });

  /// Median width over [frames] (5.5), its uncertainty budget and the reporting floor.
  ///
  /// [frames] are the accepted, measurable frames of one visit (at least 3, the caller
  /// applies the visit gate). Geometry terms (`tilt`, `rms_mm`, `loo_mm`, `dw/ds`,
  /// `mm_per_px`) use the median over frames; `u_sigma_w` the mean.
  factory UncertaintyBudget.fromFrames(List<FrameRecord> frames, UncertaintyOptions options) {
    final n = frames.length;
    if (n < 3) throw ArgumentError.value(n, 'frames', 'the budget needs n >= 3 frames (5.5)');
    final w = median(frames.map((f) => f.widthMm));
    final uFitMean = sqrt(frames.fold<double>(0, (s, f) => s + f.uFitMm * f.uFitMm)) / n;
    final uRepeat = sampleSd(frames.map((f) => f.widthMm)) / sqrt(n);
    final uStat = max(uFitMean, uRepeat);
    final uSigmaW = mean(frames.map((f) => f.uSigmaWMm));
    final mmPerPx = median(frames.map((f) => f.mmPerPx));
    final rmsMm = median(frames.map((f) => f.rmsMm));
    final looMm = median(frames.map((f) => f.looMm ?? 0.0));
    final tilt = median(frames.map((f) => f.tiltDeg));
    final slopes = [for (final f in frames) if (f.dwDs.isFinite) f.dwDs.abs()];
    final dwDsUnknown = slopes.isEmpty;
    final uPos = dwDsUnknown ? 0.0 : median(slopes) * max(rmsMm, 0.05);
    final uPar = options.dzMm * tan(tilt * pi / 180).abs() / sqrt(3);
    final uGeo = w * sqrt(rmsMm * rmsMm + looMm * looMm) / 120;
    final uPrint = w * options.uPrintRel;
    final uDev = options.uDevMm ?? defaultUDevPerMmPerPx * mmPerPx;
    final uRand = sqrt(uStat * uStat + uSigmaW * uSigmaW + uPos * uPos + uPar * uPar + uGeo * uGeo);
    final uSys = sqrt(uPrint * uPrint + uDev * uDev);
    final uC = sqrt(uRand * uRand + uSys * uSys);
    final dof = uC > 0 ? welchSatterthwaite(uC: uC, finite: [(u: uStat, dof: (n - 1).toDouble())]) : double.infinity;
    final k = coverageFactor(dof);
    return UncertaintyBudget(
      n: n,
      widthMm: w,
      uFitMean: uFitMean,
      uRepeat: uRepeat,
      uStat: uStat,
      uSigmaW: uSigmaW,
      uPos: uPos,
      uPar: uPar,
      uGeo: uGeo,
      uPrint: uPrint,
      uDev: uDev,
      uRand: uRand,
      uSys: uSys,
      uC: uC,
      dofEff: dof,
      k: k,
      uExpanded: k * uC,
      floorMm: max(0.5 * mmPerPx, 2 * uC),
      mmPerPx: mmPerPx,
      belumDivalidasi: options.uDevMm == null,
      dwDsUnknown: dwDsUnknown,
    );
  }

  final int n;
  final double widthMm;
  final double uFitMean, uRepeat, uStat, uSigmaW, uPos, uPar, uGeo;

  /// Systematic, common to all visits of a crack with the same sheet and phone.
  final double uPrint, uDev;
  final double uRand, uSys, uC;

  /// Welch-Satterthwaite effective dof (u_stat has n-1, the rest infinite).
  final double dofEff;
  final double k;

  /// `U = k u_c`.
  final double uExpanded;

  /// Reporting floor `max(0.5 mm/px, 2 u_c)`.
  final double floorMm;
  final double mmPerPx;

  /// `u_dev` came from the unvalidated default (5.5): the result must say so.
  final bool belumDivalidasi;

  /// No frame had an estimable `dw/ds`; `u_pos` is 0 for lack of information.
  final bool dwDsUnknown;

  bool get belowFloor => widthMm < floorMm;

  /// Stable JSON (mm). Infinite dof is written as null.
  Map<String, Object?> toJson() => {
        'n': n,
        'width_mm': widthMm,
        'u_fit_mean': uFitMean,
        'u_repeat': uRepeat,
        'u_stat': uStat,
        'u_sigma_w': uSigmaW,
        'u_pos': uPos,
        'u_par': uPar,
        'u_geo': uGeo,
        'u_print': uPrint,
        'u_dev': uDev,
        'u_rand': uRand,
        'u_sys': uSys,
        'u_c': uC,
        'dof_eff': dofEff.isInfinite ? null : dofEff,
        'k': k,
        'u_expanded': uExpanded,
        'floor_mm': floorMm,
        'mm_per_px': mmPerPx,
        'belum_divalidasi': belumDivalidasi,
        'dw_ds_unknown': dwDsUnknown,
      };
}
