// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import '../aggregate.dart';
import '../stats.dart';
import '../uncertainty.dart';
import 'synthetic_study.dart';

/// Stored frames: condition index, then replication.
typedef StudyFrames = Map<int, Map<int, List<FrameInput>>>;

/// One condition with its coverage counted three ways, on the visits that the app would
/// report (default budget TERUKUR).
final class CellResult {
  const CellResult({required this.condition, required this.summary, required this.coveredFitOnly, required this.coveredFitOnlyStrict, required this.coveredFitOnlyHalf, required this.coveredRandom, required this.errorOverUFitStrict, required this.errorOverUDefault});

  final StudyCondition condition;

  /// Summary under the default budget (`u_dev = 0.5 mm/px`, BELUM_DIVALIDASI).
  final ConditionSummary summary;

  /// Reported visits whose error is within `k sqrt(u_stat^2 + u_sigma_w^2 + u_truth^2)`: the part of
  /// the budget that `rho` inflates (fit covariance, frame scatter, PSF). The synthetic
  /// world has no relief, print error or device bias, so this isolates whether the
  /// measurement's own statistical uncertainty is honest. Used to calibrate `rho`.
  final int coveredFitOnly;

  /// Same with `u_truth = 0` (the rendered width taken as exact).
  final int coveredFitOnlyStrict;

  /// Within half of that interval: if this is still high, the interval is more than twice
  /// as wide as needed (conservative).
  final int coveredFitOnlyHalf;

  /// Within `U` of the full random budget (`u_dev = 0`, `u_print = 0`): adds `u_pos`,
  /// `u_par` (assumes 0.3 mm relief that the synthetic scene does not have, so
  /// conservative by construction) and `u_geo`.
  final int coveredRandom;

  /// `|error| / U` per reported visit: fit-only interval with `u_truth = 0`, and the
  /// default budget with `u_truth`. Values far below 1 mean an over-wide (conservative)
  /// interval; the 95th percentile at or below 1 means 95 percent coverage.
  final List<double> errorOverUFitStrict;
  final List<double> errorOverUDefault;

  int get reported => summary.terukur;

  /// Within `U` of the default budget (adds the unvalidated `u_dev = 0.5 mm/px`).
  int get coveredDefault => summary.covered;
  double get coverageFitOnly => reported == 0 ? double.nan : coveredFitOnly / reported;
  double get coverageFitOnlyStrict => reported == 0 ? double.nan : coveredFitOnlyStrict / reported;
  double get coverageFitOnlyHalf => reported == 0 ? double.nan : coveredFitOnlyHalf / reported;
  double get coverageRandom => reported == 0 ? double.nan : coveredRandom / reported;
  double get coverageDefault => reported == 0 ? double.nan : coveredDefault / reported;
}

/// The whole study evaluated at one variance inflation factor.
final class Evaluation {
  const Evaluation({required this.rho, required this.cells});

  final double rho;
  final List<CellResult> cells;

  int get reported => cells.fold(0, (s, c) => s + c.reported);
  int get coveredFitOnly => cells.fold(0, (s, c) => s + c.coveredFitOnly);
  int get coveredFitOnlyStrict => cells.fold(0, (s, c) => s + c.coveredFitOnlyStrict);
  int get coveredFitOnlyHalf => cells.fold(0, (s, c) => s + c.coveredFitOnlyHalf);
  int get coveredRandom => cells.fold(0, (s, c) => s + c.coveredRandom);
  int get coveredDefault => cells.fold(0, (s, c) => s + c.coveredDefault);
  double get coverageFitOnly => reported == 0 ? double.nan : coveredFitOnly / reported;
  double get coverageFitOnlyStrict => reported == 0 ? double.nan : coveredFitOnlyStrict / reported;
  double get coverageFitOnlyHalf => reported == 0 ? double.nan : coveredFitOnlyHalf / reported;
  double get coverageRandom => reported == 0 ? double.nan : coveredRandom / reported;
  double get coverageDefault => reported == 0 ? double.nan : coveredDefault / reported;

  /// Cells with a reported visit whose fit-only coverage point estimate is below [target].
  int cellsBelowPoint(double target) => cells.where((c) => c.reported > 0 && c.coverageFitOnly < target).length;

  /// Cells whose fit-only coverage is statistically below [target]: the upper end of
  /// the 95 percent Wilson interval is under it (a cell with 7 of 8 is not).
  List<CellResult> unreliableCells(double target) => [
        for (final c in cells)
          if (c.reported > 0 && wilsonInterval(c.coveredFitOnly, c.reported).upper < target) c,
      ];

  int cellsSignificantlyBelow(double target) => unreliableCells(target).length;

  /// Same test with `u_truth = 0`: cells where the fit interval alone, against an exact
  /// truth, is statistically below [target].
  List<CellResult> unreliableCellsStrict(double target) => [
        for (final c in cells)
          if (c.reported > 0 && wilsonInterval(c.coveredFitOnlyStrict, c.reported).upper < target) c,
      ];
}

/// Evaluates all stored visits with inflation [rho].
Evaluation evaluateStudy(StudyFrames data, double rho, {StudyConfig config = const StudyConfig()}) {
  final grid = studyGrid();
  const randomOnly = UncertaintyOptions(uDevMm: 0);
  final cells = <CellResult>[];
  for (final ci in data.keys.toList()..sort()) {
    final c = grid[ci];
    final reps = data[ci]!;
    final visits = [for (final r in reps.keys.toList()..sort()) replayVisit(c, r, reps[r]!, rho: rho, config: config)];
    var fitOnly = 0, fitStrict = 0, fitHalf = 0, random = 0;
    final ratioFit = <double>[], ratioDefault = <double>[];
    for (final v in visits) {
      if (v.errorMm == null) continue;
      final b = v.result.budget!;
      final e = v.errorMm!.abs();
      final uFit = sqrt(b.uStat * b.uStat + b.uSigmaW * b.uSigmaW);
      double u(double uc, double ut) => expandedWithTruth(uC: uc, uStat: b.uStat, n: b.n, uTruth: ut);
      final expanded = u(uFit, v.uTruthMm);
      if (e <= expanded) fitOnly++;
      if (e <= expanded / 2) fitHalf++;
      if (e <= u(uFit, 0)) fitStrict++;
      ratioFit.add(e / u(uFit, 0));
      ratioDefault.add(e / u(b.uC, v.uTruthMm));
      final rb = replayVisit(c, v.rep, reps[v.rep]!, rho: rho, options: randomOnly, config: config).result.budget!;
      if (e <= expandedWithTruth(uC: rb.uC, uStat: rb.uStat, n: rb.n, uTruth: v.uTruthMm)) random++;
    }
    cells.add(CellResult(condition: c, summary: summarizeCondition(c, visits), coveredFitOnly: fitOnly, coveredFitOnlyStrict: fitStrict, coveredFitOnlyHalf: fitHalf, coveredRandom: random, errorOverUFitStrict: ratioFit, errorOverUDefault: ratioDefault));
  }
  return Evaluation(rho: rho, cells: cells);
}

/// Outcome of [calibrateRho].
final class RhoCalibration {
  const RhoCalibration({required this.rho, required this.curve});

  /// The smallest candidate reaching the target, or null if none does.
  final double? rho;

  /// Evaluations in candidate order, up to and including the chosen one (all if null).
  final List<Evaluation> curve;
}

/// Smallest `rho` among [candidates] (ascending) for which the fit-only coverage of
/// the reported visits is at least [target] pooled AND no cell is statistically below
/// [target] (Wilson). A null result means the model cannot be made honest by inflating
/// `u_fit` alone: some condition must be rejected by the gate or the floor instead.
RhoCalibration calibrateRho(StudyFrames data, {required List<double> candidates, double target = 0.9, StudyConfig config = const StudyConfig()}) {
  final curve = <Evaluation>[];
  for (final rho in candidates) {
    final e = evaluateStudy(data, rho, config: config);
    curve.add(e);
    if (e.coverageFitOnly >= target && e.cellsSignificantlyBelow(target) == 0) {
      return RhoCalibration(rho: rho, curve: curve);
    }
  }
  return RhoCalibration(rho: null, curve: curve);
}
