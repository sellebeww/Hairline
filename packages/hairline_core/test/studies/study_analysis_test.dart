// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

/// Visit whose 5 frames all read `truth + error`, u_fit (rho = 1) 1 um, nothing else.
/// Fit-only interval: u = u_stat = sqrt(5) 1e-3 sqrt(rho) / 5, dof 4, k = 2.776,
/// so U = 1.2417e-3 sqrt(rho): an error of 4 um is covered once sqrt(rho) >= 3.22, rho >= 10.4.
List<FrameInput> visit(double truth, double error) => [
      for (var i = 0; i < 5; i++)
        FrameInput.accepted(FrameRecord(
          status: MeasureStatus.terukur,
          widthMm: truth + error,
          uFitRawMm: 0.001,
          rho: 1,
          uSigmaWMm: 0,
          dwDs: 0,
          mmPerPx: 0.04,
          rmsPx: 0,
          looMm: null,
          tiltDeg: 0,
        )),
    ];

/// Conditions 0..2 (0.1, 0.2, 0.3 mm at 0.04 mm/px), 8 replications each.
StudyFrames data({List<double> errorOfCell2 = const [0.004, 0.004, 0.004, 0.004, 0.004, 0.004, 0.004, 0.004]}) {
  final g = studyGrid();
  return {
    for (var c = 0; c < 3; c++)
      c: {
        for (var r = 0; r < 8; r++) r: visit(g[c].widthMm, c == 2 ? errorOfCell2[r] : 0.004 * (r.isEven ? 1 : -1)),
      },
  };
}

const exact = StudyConfig(renderTruthUncertaintyPx: 0);

void main() {
  test('evaluation counts reported visits and coverage under both budgets', () {
    final e = evaluateStudy(data(), 1, config: exact);
    expect(e.cells.length, 3);
    expect(e.reported, 24);
    expect(e.coverageFitOnly, 0); // rho 1: U = 1.24 um, errors 4 um
    expect(e.coverageDefault, 1); // u_dev default 0.5 * 0.04 = 20 um dominates: U ~ 40 um
  });

  test('renderer uncertainty u_truth widens the intervals: 4 um error is not covered at rho 1 without it, covered with it', () {
    // u_truth = 0.04 mm/px * 0.1021 px = 4.08 um; with u_fit 0.45 um: u = 4.1 um, k 1.96, U = 8.0 um
    expect(evaluateStudy(data(), 1, config: exact).coverageFitOnly, 0);
    expect(evaluateStudy(data(), 1).coverageFitOnly, 1);
    expect(evaluateStudy(data(), 1).coverageFitOnlyStrict, 0); // the strict count ignores u_truth
  });

  test('error over U ratios are kept per reported visit (hand value: 4 um over U = 1.2417 um sqrt(rho))', () {
    final e = evaluateStudy(data(), 16, config: exact);
    final r = e.cells[2].errorOverUFitStrict;
    expect(r.length, 8);
    expect(r.first, closeTo(0.004 / (1.2417e-3 * 4), 2e-3)); // 0.8053
    expect(e.cells[2].errorOverUDefault.every((x) => x < 0.2), isTrue); // default U ~ 40 um
  });

  test('rho replay: the same frames at rho = 16 are covered (sqrt(16) 1.2417 um = 4.97 um >= 4 um)', () {
    final e = evaluateStudy(data(), 16, config: exact);
    expect(e.coverageFitOnly, 1);
    expect(e.reported, 24);
  });

  test('half-width coverage measures conservatism: U/2 = 2.48 um misses 4 um at rho 16, U/2 = 4.97 um covers it at rho 64', () {
    expect(evaluateStudy(data(), 16, config: exact).coverageFitOnlyHalf, 0);
    expect(evaluateStudy(data(), 64, config: exact).coverageFitOnlyHalf, 1);
  });

  test('calibration returns the smallest candidate rho that satisfies the target', () {
    final r = calibrateRho(data(), config: exact, candidates: [1, 4, 8, 16, 64]);
    expect(r.rho, 16); // 8 is not enough (10.4 needed)
    expect(r.curve.map((e) => e.rho), [1, 4, 8, 16]); // stops at the first success
    expect(r.curve.first.coverageFitOnly, 0);
  });

  test('a cell significantly below the target (0 of 8) blocks calibration at every rho: null', () {
    final bad = data(errorOfCell2: List.filled(8, 0.5)); // 0.5 mm off, never covered
    final r = calibrateRho(bad, config: exact, candidates: [1, 16, 1000]);
    expect(r.rho, isNull);
    expect(r.curve.length, 3);
    expect(r.curve.last.cellsSignificantlyBelow(0.9), 1);
    expect(r.curve.last.unreliableCells(0.9).single.condition.index, 2);
    expect(r.curve.last.unreliableCellsStrict(0.9).single.condition.index, 2);
    expect(r.curve.last.coverageRandom, lessThan(1));
    expect(r.curve.last.cells[2].coverageDefault, 0); // 0.5 mm off: the default U (~40 um) does not cover either
  });

  test('one miss in 8 (87.5 percent) is within sampling error: not significant, calibration still succeeds', () {
    final oneMiss = data(errorOfCell2: [0.5, 0.004, 0.004, 0.004, 0.004, 0.004, 0.004, 0.004]);
    final r = calibrateRho(oneMiss, config: exact, candidates: [16, 1000]);
    expect(r.rho, 16);
    final e = r.curve.first;
    expect(e.cells[2].coverageFitOnly, 7 / 8);
    expect(e.cellsBelowPoint(0.9), 1);
    expect(e.cellsSignificantlyBelow(0.9), 0);
  });

  test('pooled coverage below the target also blocks (all cells fine individually is not enough)', () {
    // 3 cells at 87.5 percent each: none significant, pooled 87.5 percent < 90
    final g = studyGrid();
    final d = <int, Map<int, List<FrameInput>>>{
      for (var c = 0; c < 3; c++) c: {for (var r = 0; r < 8; r++) r: visit(g[c].widthMm, r == 0 ? 0.5 : 0.004)},
    };
    expect(calibrateRho(d, config: exact, candidates: [16, 1000]).rho, isNull);
  });
}
