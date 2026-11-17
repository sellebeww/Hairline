// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'aggregate.dart';

/// Reading of one comparison (5.6). Wording for the UI comes from the code, and
/// "tidak ada perubahan terdeteksi" never means "unchanged".
enum TrendClass {
  tidakAdaPerubahanTerdeteksi('TIDAK_ADA_PERUBAHAN_TERDETEKSI'),
  kemungkinanBertambahLebar('KEMUNGKINAN_BERTAMBAH_LEBAR'),
  kemungkinanMenyempit('KEMUNGKINAN_MENYEMPIT'),

  /// One of the two visits has no number (TIDAK_TERUKUR or below the limit).
  tidakTerukur('TIDAK_TERUKUR');

  const TrendClass(this.code);
  final String code;
}

/// Context differences between the two compared visits that weaken the
/// cancellation of common systematic parts.
enum ContextWarning {
  deviceModelDiffers('DEVICE_MODEL_DIFFERS'),
  algorithmVersionDiffers('ALGORITHM_VERSION_DIFFERS'),
  sheetDiffers('SHEET_DIFFERS');

  const ContextWarning(this.code);
  final String code;
}

/// What the trend needs from a stored visit.
final class TrendVisit {
  const TrendVisit({
    required this.status,
    required this.widthMm,
    required this.uRand,
    required this.deviceModel,
    required this.algorithmVersion,
    required this.sheetId,
  });

  factory TrendVisit.fromVisit(
    VisitResult r, {
    required String deviceModel,
    required String algorithmVersion,
    required int sheetId,
  }) =>
      TrendVisit(
        status: r.status,
        widthMm: r.budget?.widthMm,
        uRand: r.budget?.uRand,
        deviceModel: deviceModel,
        algorithmVersion: algorithmVersion,
        sheetId: sheetId,
      );

  final VisitStatus status;

  /// Visit width (mm); only used when [status] is [VisitStatus.terukur].
  final double? widthMm;

  /// `u_rand` of the visit (mm); the systematic parts are deliberately not an input.
  final double? uRand;
  final String deviceModel;
  final String algorithmVersion;
  final int sheetId;

  bool get numeric => status == VisitStatus.terukur && widthMm != null && uRand != null;
}

/// One comparison of a visit with an earlier one.
final class TrendComparison {
  const TrendComparison({
    required this.classification,
    required this.delta,
    required this.uDelta,
    required this.z,
    required this.mdc,
    required this.warnings,
  });

  final TrendClass classification;

  /// `w_i - w_ref` (mm); null unless both visits have numbers.
  final double? delta;
  final double? uDelta;
  final double? z;

  /// Minimum detectable change `2 u_delta` (mm).
  final double? mdc;
  final Set<ContextWarning> warnings;
}

/// Comparisons of visit [index] (null for the first visit).
final class TrendPoint {
  const TrendPoint({required this.index, required this.vsBaseline, required this.vsPrevious});

  final int index;
  final TrendComparison? vsBaseline;
  final TrendComparison? vsPrevious;
}

TrendComparison _compare(TrendVisit ref, TrendVisit cur, double uPrintRel) {
  final warnings = <ContextWarning>{
    if (ref.deviceModel != cur.deviceModel) ContextWarning.deviceModelDiffers,
    if (ref.algorithmVersion != cur.algorithmVersion) ContextWarning.algorithmVersionDiffers,
    if (ref.sheetId != cur.sheetId) ContextWarning.sheetDiffers,
  };
  if (!ref.numeric || !cur.numeric) {
    return TrendComparison(classification: TrendClass.tidakTerukur, delta: null, uDelta: null, z: null, mdc: null, warnings: warnings);
  }
  final delta = cur.widthMm! - ref.widthMm!;
  // u_print and u_dev are common to both visits and cancel; only the relative scale
  // error acting on the change itself remains: (delta * u_print_rel).
  final uDelta = sqrt(cur.uRand! * cur.uRand! + ref.uRand! * ref.uRand! + pow(delta * uPrintRel, 2));
  final z = delta == 0 ? 0.0 : delta / uDelta;
  final cls = z >= 2
      ? TrendClass.kemungkinanBertambahLebar
      : z <= -2
          ? TrendClass.kemungkinanMenyempit
          : TrendClass.tidakAdaPerubahanTerdeteksi;
  return TrendComparison(classification: cls, delta: delta, uDelta: uDelta, z: z, mdc: 2 * uDelta, warnings: warnings);
}

/// Trend of a crack (5.6): each visit against the baseline (the first visit) and
/// against the previous one. Only pairwise differences are computed: no regression and
/// no extrapolation, however many visits exist. [uPrintRel] is `print_scale_u_rel`.
List<TrendPoint> computeTrend(List<TrendVisit> visits, {required double uPrintRel}) => [
      for (var i = 0; i < visits.length; i++)
        TrendPoint(
          index: i,
          vsBaseline: i == 0 ? null : _compare(visits[0], visits[i], uPrintRel),
          vsPrevious: i == 0 ? null : _compare(visits[i - 1], visits[i], uPrintRel),
        ),
    ];
