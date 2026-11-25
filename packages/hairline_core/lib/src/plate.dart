// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'aggregate.dart';
import 'point.dart';
import 'sheet_layout.dart';
import 'stats.dart';
import 'uncertainty.dart';
import 'validation.dart';

// The validation plate (CLAUDE.md phase 8): the marker layout of sheet [plateSheetId],
// and in the 70 x 70 mm window 32 straight black lines of known nominal width, as device
// independent primitives and as measurement points with known sheet coordinates.

/// Sheet number reserved for the validation plate (frame sheets for cracks use 0 to 10
/// in the UI; the markers are those of sheet 11: ids 44 to 47).
const int plateSheetId = 11;

/// Nominal widths (mm) of the plate lines.
const List<double> plateNominalWidthsMm = [0.1, 0.2, 0.3, 0.5, 0.8, 1.0, 1.5, 2.0];

/// Length of a printed line (mm). The measured segment is 4 mm long and centred.
const double plateLineLengthMm = 10;

/// Clear paper between the 3 mm profile range of a line and the edge of its neighbour (mm).
const double plateLineClearanceMm = 4;

/// One line of the plate: its sheet position and what the printed label says.
final class PlateLineSpec {
  const PlateLineSpec({
    required this.id,
    required this.setName,
    required this.index,
    required this.nominalMm,
    required this.centreMm,
    required this.directionDeg,
  });

  /// `V1-3`: set name and the 1-based index of the nominal width (the digit printed next to the line).
  final String id;

  /// `V1`, `V2` (vertical lines) or `H1`, `H2` (horizontal lines).
  final String setName;
  final int index;
  final double nominalMm;

  /// Centre of the line (sheet mm). Also the measurement point.
  final Pt centreMm;

  /// Crack direction convention of the core: angle of the line from the sheet x axis (y down).
  final double directionDeg;

  bool get vertical => setName.startsWith('V');
}

/// Position of each set: centre of the row (vertical sets: y; horizontal sets: x) and
/// the centre of the stack across it (vertical sets: x; horizontal sets: y).
const _sets = [
  (name: 'V1', vertical: true, along: -26.0, across: 0.0, ascending: true),
  (name: 'V2', vertical: true, along: -9.0, across: 0.0, ascending: false),
  (name: 'H1', vertical: false, along: -26.0, across: 16.0, ascending: true),
  (name: 'H2', vertical: false, along: 26.0, across: 16.0, ascending: false),
];

/// The 32 lines of the plate: 8 widths x 2 orientations x 2 positions. Within a set the
/// lines are spaced so that the clear paper between a line and the next one is
/// [plateLineClearanceMm] plus half the width of the narrower one: the 3 mm profile of
/// a line never reaches its neighbour. The second set of each orientation is in the
/// opposite order, so a gradient across the plate cannot hide in the width order.
List<PlateLineSpec> buildPlateLines() {
  final out = <PlateLineSpec>[];
  for (final s in _sets) {
    final order = [for (var i = 0; i < plateNominalWidthsMm.length; i++) i];
    if (!s.ascending) order.setAll(0, order.reversed.toList());
    var total = 0.0;
    for (var i = 0; i + 1 < order.length; i++) {
      total += plateLineClearanceMm + (plateNominalWidthsMm[order[i]] + plateNominalWidthsMm[order[i + 1]]) / 2;
    }
    var pos = s.across - total / 2;
    for (var i = 0; i < order.length; i++) {
      final idx = order[i];
      final c = s.vertical ? Pt(pos, s.along) : Pt(s.along, pos);
      out.add(PlateLineSpec(
        id: '${s.name}-${idx + 1}',
        setName: s.name,
        index: idx + 1,
        nominalMm: plateNominalWidthsMm[idx],
        centreMm: c,
        directionDeg: s.vertical ? 90 : 0,
      ));
      if (i + 1 < order.length) {
        pos += plateLineClearanceMm + (plateNominalWidthsMm[idx] + plateNominalWidthsMm[order[i + 1]]) / 2;
      }
    }
  }
  return out;
}

/// Text of the plate that is not part of the sheet labels: legend lines (Indonesian,
/// Latin-1 only), e.g. which digit means which nominal width.
final class PlateLabels {
  const PlateLabels({required this.legend});
  final List<String> legend;
}

/// Page primitives of the plate: the layout of sheet [plateSheetId] (identical markers,
/// scale bar and texts), the 32 lines drawn as black rectangles of the nominal width, the
/// digit and set labels, and the legend. Nominal size (print scale 1), like the frame sheet.
List<SheetPrimitive> buildPlateLayout(PaperSize paper, SheetLabels labels, PlateLabels plate) {
  final out = buildSheetLayout(plateSheetId, paper, labels);
  final cx = paper.widthMm / 2, cy = sheetCentreFromTopMm;
  for (final l in buildPlateLines()) {
    final w = l.nominalMm;
    final c = l.centreMm;
    if (l.vertical) {
      out.add(SheetRect(cx + c.x - w / 2, cy + c.y - plateLineLengthMm / 2, w, plateLineLengthMm, black: true));
      out.add(SheetText(cx + c.x, cy + c.y + plateLineLengthMm / 2 + 3.2, '${l.index}', sizePt: 5));
    } else {
      out.add(SheetRect(cx + c.x - plateLineLengthMm / 2, cy + c.y - w / 2, plateLineLengthMm, w, black: true));
      final side = c.x < 0 ? 1 : -1;
      out.add(SheetText(cx + c.x + side * (plateLineLengthMm / 2 + 1.8), cy + c.y + 0.7, '${l.index}', sizePt: 5));
    }
  }
  out
    ..add(SheetText(cx - 26, cy - 28, 'V1', sizePt: 6, bold: true))
    ..add(SheetText(cx - 26, cy - 11, 'V2', sizePt: 6, bold: true))
    ..add(SheetText(cx - 26, cy - 3.5, 'H1', sizePt: 6, bold: true))
    ..add(SheetText(cx + 26, cy - 3.5, 'H2', sizePt: 6, bold: true));
  var y = cy + 8;
  for (final line in plate.legend) {
    out.add(SheetText(cx, y, line, sizePt: 5.5));
    y += 3.6;
  }
  return out;
}

/// Where the truth widths of a plate come from.
enum PlateTruthSource {
  /// Widths characterised by a scanner or a loupe and imported from a CSV.
  characterized('KARAKTERISASI'),

  /// Nominal widths with a placeholder uncertainty: NOT a measured truth.
  nominal('NOMINAL');

  const PlateTruthSource(this.code);
  final String code;
}

/// Truth of one line: width and its standard uncertainty (mm).
typedef PlateLineTruth = ({double widthMm, double uMm});

/// Placeholder `u_truth` (mm) of nominal widths. NOT a measurement: printed line widths
/// differ from nominal by dot gain (several hundredths of a mm), so this is a starting
/// value the owner may change, and a nominal truth never validates a phone (D46).
const double defaultNominalUTruthMm = 0.05;

/// The CSV is rejected (message in Indonesian, with the row number when it applies).
final class PlateTruthException implements Exception {
  const PlateTruthException(this.message);
  final String message;

  @override
  String toString() => 'PlateTruthException: $message';
}

/// Limits of the CSV import (5.8: strict validation of size, rows and ranges).
const int plateCsvMaxChars = 8192;
const int plateCsvMaxRows = 64;
const double plateTruthMaxUMm = 1.0;

/// The measured truth widths of the plate lines.
final class PlateTruth {
  PlateTruth._(this.source, this.lines);

  /// Nominal widths of all 32 lines with `u = [uMm]` (a placeholder, see [defaultNominalUTruthMm]).
  factory PlateTruth.nominal({double uMm = defaultNominalUTruthMm}) {
    if (!(uMm >= 0) || !uMm.isFinite || uMm > plateTruthMaxUMm) {
      throw ArgumentError.value(uMm, 'uMm', 'must be within 0..1 mm');
    }
    return PlateTruth._(PlateTruthSource.nominal, {
      for (final l in buildPlateLines()) l.id: (widthMm: l.nominalMm, uMm: uMm),
    });
  }

  /// Characterised truth from CSV text `posisi,lebar_mm,u_mm` (header required, dot
  /// decimals). Every row must name a known line once, the width must be within
  /// 0.3 to 3 times the nominal one (else it is most likely a typing error) and `u_mm`
  /// within 0 to 1 mm. At least 8 lines are needed. Throws [PlateTruthException].
  factory PlateTruth.fromCsv(String csv) {
    if (csv.length > plateCsvMaxChars) {
      throw const PlateTruthException('Berkas CSV terlalu besar (maksimal 8 KB).');
    }
    final rows = csv.split(RegExp(r'\r\n|\n|\r')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (rows.isEmpty || rows.first.replaceAll('﻿', '') != 'posisi,lebar_mm,u_mm') {
      throw const PlateTruthException('Baris pertama harus persis: posisi,lebar_mm,u_mm');
    }
    if (rows.length - 1 > plateCsvMaxRows) {
      throw const PlateTruthException('Terlalu banyak baris (maksimal 64 baris data).');
    }
    final known = {for (final l in buildPlateLines()) l.id: l};
    final out = <String, PlateLineTruth>{};
    for (var i = 1; i < rows.length; i++) {
      final n = i + 1; // line number in the file (the header is line 1)
      final cols = rows[i].split(',').map((c) => c.trim()).toList();
      if (cols.length != 3) throw PlateTruthException('Baris $n: harus ada tepat 3 kolom.');
      final spec = known[cols[0]];
      if (spec == null) throw PlateTruthException('Baris $n: posisi "${cols[0]}" tidak dikenal (contoh: V1-3, H2-5).');
      if (out.containsKey(spec.id)) throw PlateTruthException('Baris $n: posisi ${spec.id} muncul dua kali.');
      final w = _number(cols[1]), u = _number(cols[2]);
      if (w == null) throw PlateTruthException('Baris $n: lebar_mm bukan angka (pakai titik desimal).');
      if (u == null) throw PlateTruthException('Baris $n: u_mm bukan angka (pakai titik desimal).');
      if (w < 0.3 * spec.nominalMm || w > 3 * spec.nominalMm) {
        throw PlateTruthException('Baris $n: lebar ${cols[1]} mm di luar 0,3 sampai 3 kali nominal (${spec.nominalMm} mm). Periksa satuan.');
      }
      if (u > plateTruthMaxUMm) throw PlateTruthException('Baris $n: u_mm harus antara 0 dan 1 mm.');
      out[spec.id] = (widthMm: w, uMm: u);
    }
    if (out.length < 8) throw const PlateTruthException('Minimal 8 garis harus diisi.');
    return PlateTruth._(PlateTruthSource.characterized, out);
  }

  /// Reads [toJson]; throws [FormatException] for another shape.
  factory PlateTruth.fromJson(Map<String, Object?> json) {
    final source = PlateTruthSource.values.where((s) => s.code == json['source']).firstOrNull;
    final lines = json['lines'];
    if (json['v'] != 1 || source == null || lines is! Map<String, Object?>) {
      throw const FormatException('Unsupported plate truth JSON');
    }
    return PlateTruth._(source, {
      for (final e in lines.entries)
        e.key: (
          widthMm: ((e.value! as Map<String, Object?>)['w']! as num).toDouble(),
          uMm: ((e.value! as Map<String, Object?>)['u']! as num).toDouble(),
        ),
    });
  }

  static double? _number(String s) => RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(s) ? double.tryParse(s) : null;

  final PlateTruthSource source;

  /// By line id (`V1-3`).
  final Map<String, PlateLineTruth> lines;

  bool get characterized => source == PlateTruthSource.characterized;

  Map<String, Object?> toJson() => {
        'v': 1,
        'source': source.code,
        'lines': {for (final e in lines.entries) e.key: {'w': e.value.widthMm, 'u': e.value.uMm}},
      };
}

/// When a plate run counts as a validation of the phone (D46). Initial values, not tuned on devices.
final class PlateThresholds {
  const PlateThresholds({this.minReportedLines = 16, this.minCoverage = 0.9, this.minReportedWidths = 4});

  /// Lines with a reported width (of at most 32). With 16 lines and a true coverage of
  /// 95 percent a run passes the coverage test with probability 0.81; with 80 percent, 0.14.
  final int minReportedLines;

  /// Fraction of reported lines whose error is within the combined expanded uncertainty.
  final double minCoverage;

  /// Distinct tested widths with at least one reported line (the bias must be known at several widths).
  final int minReportedWidths;

  Map<String, Object?> toJson() =>
      {'min_reported_lines': minReportedLines, 'min_coverage': minCoverage, 'min_reported_widths': minReportedWidths};
}

/// One plate line after evaluation.
final class PlateLineEval {
  const PlateLineEval({
    required this.id,
    required this.nominalMm,
    required this.truthMm,
    required this.uTruthMm,
    required this.status,
    required this.acceptedFrames,
    this.measuredMm,
    this.uCMm,
    this.k,
    this.errorMm,
    this.covered,
    this.rejectionCounts = const {},
  });

  final String id;
  final double nominalMm, truthMm, uTruthMm;

  /// `TERUKUR`, `DI_BAWAH_BATAS_UKUR`, `TIDAK_TERUKUR` or `DITOLAK`.
  final String status;
  final int acceptedFrames;
  final double? measuredMm, uCMm, k, errorMm;
  final bool? covered;
  final Map<String, int> rejectionCounts;

  Map<String, Object?> toJson() => {
        'id': id,
        'nominal_mm': nominalMm,
        'truth_mm': truthMm,
        'u_truth_mm': uTruthMm,
        'status': status,
        'accepted_frames': acceptedFrames,
        'measured_mm': measuredMm,
        'u_c_mm': uCMm,
        'k': k,
        'error_mm': errorMm,
        'covered': covered,
        if (rejectionCounts.isNotEmpty) 'rejections': rejectionCounts,
      };
}

/// Result of evaluating a plate run.
final class PlateEvaluation {
  const PlateEvaluation({
    required this.lines,
    required this.stats,
    required this.truthSource,
    required this.uTruthMedianMm,
    required this.validated,
    required this.reasons,
    required this.thresholds,
  });

  final List<PlateLineEval> lines;

  /// Statistics with the budget that applies after validation (`u_dev` from the biases).
  final PlateStats stats;
  final PlateTruthSource truthSource;

  /// Median `u_truth` of the evaluated lines: the floor of `u_dev` (a bias cannot be
  /// resolved below the uncertainty of the truth).
  final double uTruthMedianMm;

  /// The run qualifies as a validation of the phone: removes `BELUM_DIVALIDASI`, sets `u_dev`.
  final bool validated;

  /// Why [validated] is false (Indonesian, specific); empty when it is true.
  final List<String> reasons;
  final PlateThresholds thresholds;

  /// `validation_runs.results_json`.
  Map<String, Object?> toJson() => {
        'v': 1,
        'truth_source': truthSource.code,
        'validated': validated,
        'reasons': reasons,
        'u_truth_median_mm': uTruthMedianMm,
        'thresholds': thresholds.toJson(),
        'stats': stats.toJson(),
        'lines': [for (final l in lines) l.toJson()],
      };
}

/// Evaluates a plate run (CLAUDE.md 5.5, 5.6, 5.7).
///
/// [frames] holds the burst frames of each line id (all lines measured on the same
/// photos). Per line: `aggregateVisit` with the unvalidated budget gives the width; the
/// bias per tested width gives `u_dev` ([deriveUDev], floored at the median `u_truth`);
/// the budget is then recomputed with that `u_dev`, which is the budget the app reports
/// after the validation, and the statistics (bias, RMSE, coverage of
/// `k sqrt(u_c^2 + u_truth^2)`, empirical lower limit) are computed on it. The coverage is
/// therefore measured in-sample (D46). The run is [PlateEvaluation.validated] only if the
/// truth is characterised and the [thresholds] are met. Throws [ArgumentError] when no
/// line of [truth] has frames.
PlateEvaluation evaluatePlate({
  required PlateTruth truth,
  required Map<String, List<FrameInput>> frames,
  UncertaintyOptions options = const UncertaintyOptions(),
  PlateThresholds thresholds = const PlateThresholds(),
}) {
  final specs = {for (final l in buildPlateLines()) l.id: l};
  final ids = [for (final id in specs.keys) if (truth.lines.containsKey(id) && frames.containsKey(id)) id];
  if (ids.isEmpty) throw ArgumentError('no plate line has both a truth and frames');

  List<PlateMeasurement> measurements(Map<String, VisitResult> visits) => [
        for (final id in ids)
          PlateMeasurement(
            lineId: id,
            truthMm: truth.lines[id]!.widthMm,
            uTruthMm: truth.lines[id]!.uMm,
            measuredMm: visits[id]!.reportableWidthMm,
            uCMm: visits[id]!.budget?.uC ?? 0,
            k: visits[id]!.budget?.k ?? 2,
          ),
      ];

  final first = {for (final id in ids) id: aggregateVisit(frames[id]!, options: options)};
  final stats1 = computePlateStats(measurements(first));
  final uTruthMedian = median(ids.map((id) => truth.lines[id]!.uMm));

  final second = <String, VisitResult>{};
  for (final id in ids) {
    final d = deriveUDev(stats1, truth.lines[id]!.widthMm);
    second[id] = d == null ? first[id]! : aggregateVisit(frames[id]!, options: options.withUDev(max(d.uDevMm, uTruthMedian)));
  }
  final ms = measurements(second);
  final stats = computePlateStats(ms);

  final lines = <PlateLineEval>[];
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i], v = second[id]!, m = ms[i];
    lines.add(PlateLineEval(
      id: id,
      nominalMm: specs[id]!.nominalMm,
      truthMm: m.truthMm,
      uTruthMm: m.uTruthMm,
      status: v.status.code,
      acceptedFrames: v.acceptedFrames,
      measuredMm: m.measuredMm,
      uCMm: v.budget?.uC,
      k: v.budget?.k,
      errorMm: m.reported ? m.errorMm : null,
      covered: m.reported ? m.covered : null,
      rejectionCounts: v.rejectionCounts,
    ));
  }

  final reasons = <String>[];
  if (!truth.characterized) {
    reasons.add('Kebenaran dasar masih NOMINAL (tidak dikarakterisasi): lebar cetak berbeda dari nominal, jadi bias tidak dapat dipercaya.');
  }
  if (stats.reported < thresholds.minReportedLines) {
    reasons.add('Hanya ${stats.reported} garis terukur (minimal ${thresholds.minReportedLines}). Dekatkan ponsel atau perbaiki cahaya.');
  }
  final widthsReported = stats.groups.where((g) => g.reported > 0).length;
  if (widthsReported < thresholds.minReportedWidths) {
    reasons.add('Hanya $widthsReported lebar berbeda yang terukur (minimal ${thresholds.minReportedWidths}).');
  }
  if (stats.reported > 0 && !(stats.coverage >= thresholds.minCoverage)) {
    reasons.add('Cakupan ${(stats.coverage * 100).toStringAsFixed(0)} persen di bawah ${(thresholds.minCoverage * 100).toStringAsFixed(0)} persen.');
  }
  return PlateEvaluation(
    lines: lines,
    stats: stats,
    truthSource: truth.source,
    uTruthMedianMm: uTruthMedian,
    validated: reasons.isEmpty,
    reasons: reasons,
    thresholds: thresholds,
  );
}

/// What a stored plate run says about a phone, for later visits (5.5 `u_dev`).
final class DeviceValidation {
  const DeviceValidation({required this.stats, required this.uTruthMedianMm, required this.validated});

  /// Reads `validation_runs.results_json`; throws [FormatException] for another shape.
  factory DeviceValidation.fromResultsJson(Map<String, Object?> json) {
    final stats = json['stats'], u = json['u_truth_median_mm'], v = json['validated'];
    if (json['v'] != 1 || stats is! Map<String, Object?> || u is! num || v is! bool) {
      throw const FormatException('Unsupported validation results JSON');
    }
    return DeviceValidation(stats: PlateStats.fromJson(stats), uTruthMedianMm: u.toDouble(), validated: v);
  }

  final PlateStats stats;
  final double uTruthMedianMm;

  /// Only a validated run replaces the unvalidated default.
  final bool validated;

  /// `u_dev` for a visit of width [widthMm]; null when the run did not validate the phone
  /// or tested no comparable width (the unvalidated default then stays in force).
  double? uDevFor(double widthMm) {
    if (!validated) return null;
    final d = deriveUDev(stats, widthMm);
    return d == null ? null : max(d.uDevMm, uTruthMedianMm);
  }
}

/// [aggregateVisit] with the `u_dev` of a validation of this phone, if there is one: the
/// width comes from the first pass, `u_dev` is taken at that width, and the budget is
/// recomputed. Without a usable validation this is exactly [aggregateVisit] (and the
/// result keeps `BELUM_DIVALIDASI`).
VisitResult aggregateVisitWithDevice(
  List<FrameInput> frames, {
  UncertaintyOptions options = const UncertaintyOptions(),
  DeviceValidation? validation,
}) {
  final first = aggregateVisit(frames, options: options);
  final budget = first.budget;
  if (validation == null || budget == null) return first;
  final u = validation.uDevFor(budget.widthMm);
  return u == null ? first : aggregateVisit(frames, options: options.withUDev(u));
}
