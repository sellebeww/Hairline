// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:hairline_core/hairline_core.dart';

import '../data/database.dart';

/// One aggregate measurement row read back for display: status, width, uncertainty and
/// the components that `VisitProcessor` stored in `components_json`.
final class AggregateView {
  const AggregateView({
    required this.measurementId,
    required this.algorithmVersion,
    required this.status,
    required this.widthMm,
    required this.uExpandedMm,
    required this.uRandMm,
    required this.k,
    required this.floorMm,
    required this.mmPerPx,
    required this.belumDivalidasi,
    required this.budget,
    required this.acceptedFrames,
    required this.issueCode,
    required this.frameRejectionCodes,
    required this.frameWarnings,
  });

  factory AggregateView.fromRow(Measurement m) {
    final c = _asMap(_decode(m.componentsJson));
    final budget = _asMap(c['budget']);
    final rejections = c['frame_rejections'];
    return AggregateView(
      measurementId: m.id,
      algorithmVersion: m.algorithmVersion,
      status: VisitStatus.values.firstWhere((s) => s.code == m.status, orElse: () => VisitStatus.tidakTerukur),
      widthMm: m.widthMm,
      uExpandedMm: m.uExpanded,
      uRandMm: m.uRand,
      k: m.k,
      floorMm: (budget['floor_mm'] as num?)?.toDouble(),
      mmPerPx: (budget['mm_per_px'] as num?)?.toDouble(),
      // A stored result without the flag is treated as unvalidated: the label must never be dropped by accident.
      belumDivalidasi: budget['belum_divalidasi'] as bool? ?? true,
      budget: budget,
      acceptedFrames: (c['accepted_frames'] as num?)?.toInt() ?? 0,
      issueCode: c['issue'] as String?,
      frameRejectionCodes: [
        if (rejections is List) for (final r in rejections) if (r is Map && r['code'] is String) r['code'] as String,
      ],
      frameWarnings: {
        for (final e in _asMap(c['frame_warnings']).entries)
          if (e.value is num && (e.value as num) > 0) e.key: (e.value as num).toInt(),
      },
    );
  }

  final int measurementId;
  final String algorithmVersion;
  final VisitStatus status;

  /// Null unless [status] is [VisitStatus.terukur].
  final double? widthMm, uExpandedMm, uRandMm, k;

  /// Reporting floor, present when a budget exists (terukur and di bawah batas ukur).
  final double? floorMm, mmPerPx;
  final bool belumDivalidasi;

  /// The stored 5.5 budget (mm), empty when none exists.
  final Map<String, Object?> budget;
  final int acceptedFrames;
  final String? issueCode;
  final List<String> frameRejectionCodes;

  /// Measurement warning code to the number of kept frames that raised it (empty for rows stored before phase 9).
  final Map<String, int> frameWarnings;

  bool get numeric => status == VisitStatus.terukur && widthMm != null && uRandMm != null;
}

Object? _decode(String json) {
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

Map<String, Object?> _asMap(Object? v) => v is Map<String, Object?> ? v : const {};

/// The aggregate to show for a visit: the one of [preferredVersion] if there is one (newest
/// of that version), else simply the newest. [rows] must be ordered oldest first.
AggregateView? pickAggregate(List<Measurement> rows, String preferredVersion) {
  if (rows.isEmpty) return null;
  final preferred = rows.where((r) => r.algorithmVersion == preferredVersion);
  return AggregateView.fromRow(preferred.isNotEmpty ? preferred.last : rows.last);
}
