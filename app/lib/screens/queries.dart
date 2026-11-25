// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../domain/visit_view.dart';
import '../pipeline/visit_processor.dart';
import '../providers.dart';

// Plain providers (no code generation): their signatures use drift row classes, which
// exist only after drift's own generation step.

final sitesProvider = FutureProvider.autoDispose<List<Site>>((ref) => ref.watch(hairlineRepositoryProvider).allSites());

final siteProvider = FutureProvider.autoDispose.family<Site?, int>((ref, siteId) => ref.watch(hairlineRepositoryProvider).site(siteId));

/// A crack with what the list needs to show.
final class CrackSummary {
  const CrackSummary({required this.crack, required this.visitCount, required this.hasBaseline});
  final Crack crack;
  final int visitCount;
  final bool hasBaseline;
}

final cracksOfSiteProvider = FutureProvider.autoDispose.family<List<CrackSummary>, int>((ref, siteId) async {
  final repo = ref.watch(hairlineRepositoryProvider);
  final out = <CrackSummary>[];
  for (final c in await repo.cracksOfSite(siteId)) {
    final visits = await repo.visitsOfCrack(c.id);
    out.add(CrackSummary(crack: c, visitCount: visits.length, hasBaseline: visits.any((v) => v.kind == 'baseline')));
  }
  return out;
});

/// One visit of a crack with its aggregate result (null if a visit somehow has none).
final class VisitEntry {
  const VisitEntry({required this.visit, required this.aggregate});
  final Visit visit;
  final AggregateView? aggregate;
}

final class CrackDetail {
  const CrackDetail({required this.crack, required this.visits});
  final Crack crack;
  final List<VisitEntry> visits;

  bool get hasBaseline => visits.any((v) => v.visit.kind == 'baseline');
}

// Takes what it needs instead of a Ref: a Ref must not be used after an await (auto-dispose).
Future<List<VisitEntry>> _entries(HairlineRepository repo, String version, int crackId) async {
  return [
    for (final v in await repo.visitsOfCrack(crackId))
      VisitEntry(visit: v, aggregate: pickAggregate(await repo.aggregatesOfVisit(v.id), version)),
  ];
}

final crackDetailProvider = FutureProvider.autoDispose.family<CrackDetail?, int>((ref, crackId) async {
  final repo = ref.watch(hairlineRepositoryProvider);
  final version = ref.watch(currentAlgorithmVersionProvider);
  final crack = await repo.crack(crackId);
  return crack == null ? null : CrackDetail(crack: crack, visits: await _entries(repo, version, crackId));
});

/// Everything the result screen shows about one visit.
final class VisitDetail {
  const VisitDetail({
    required this.visit,
    required this.crack,
    required this.aggregate,
    required this.bestFrame,
    required this.photo,
    required this.mmPerPx,
    required this.cameraFlags,
    required this.isBaseline,
  });

  final Visit visit;
  final Crack crack;
  final AggregateView? aggregate;

  /// The stored frame with the lowest reprojection error, and its photo file.
  final Frame? bestFrame;
  final FrameFile? photo;

  /// From the budget, else the median of the stored frames (a result without a budget has none).
  final double? mmPerPx;
  final List<String> cameraFlags;
  final bool isBaseline;
}

/// A stored photo: its file is read by the widget (`Image.file`).
typedef FrameFile = ({String path});

final visitDetailProvider = FutureProvider.autoDispose.family<VisitDetail?, int>((ref, visitId) async {
  final repo = ref.watch(hairlineRepositoryProvider);
  final storage = ref.watch(frameStorageProvider);
  final version = ref.watch(currentAlgorithmVersionProvider);
  final visit = await repo.visit(visitId);
  if (visit == null) return null;
  final crack = await repo.crack(visit.crackId);
  if (crack == null) return null;
  final aggregate = pickAggregate(await repo.aggregatesOfVisit(visitId), version);
  final frames = await repo.framesOfVisit(visitId);
  Frame? best;
  for (final f in frames) {
    if (best == null || f.rmsPx < best.rmsPx) best = f;
  }
  final scales = [for (final f in frames) f.mmPerPx]..sort();
  return VisitDetail(
    visit: visit,
    crack: crack,
    aggregate: aggregate,
    bestFrame: best,
    photo: best == null ? null : (path: storage.fileOf(best.path).path),
    mmPerPx: aggregate?.mmPerPx ?? (scales.isEmpty ? null : scales[scales.length ~/ 2]),
    cameraFlags: CameraInfo.fromJsonString(visit.cameraInfoJson).flags,
    isBaseline: visit.kind == 'baseline',
  );
});

/// One visit on the trend screen: its result and its comparisons (null for the first visit).
final class TrendEntry {
  const TrendEntry({required this.entry, required this.point});
  final VisitEntry entry;
  final TrendPoint point;
}

final class TrendData {
  const TrendData({required this.crack, required this.entries, required this.outdatedVisitIds, required this.currentVersion});
  final Crack crack;
  final List<TrendEntry> entries;

  /// Visits that have no result of [currentVersion] yet (offered for reprocessing).
  final List<int> outdatedVisitIds;
  final String currentVersion;
}

/// Trend of 5.6: every visit against the baseline and the previous visit, pairwise only.
final trendProvider = FutureProvider.autoDispose.family<TrendData?, int>((ref, crackId) async {
  final repo = ref.watch(hairlineRepositoryProvider);
  final version = ref.watch(currentAlgorithmVersionProvider);
  final crack = await repo.crack(crackId);
  if (crack == null) return null;
  final entries = await _entries(repo, version, crackId);
  final visits = [
    for (final e in entries)
      TrendVisit(
        status: e.aggregate?.status ?? VisitStatus.tidakTerukur,
        widthMm: e.aggregate?.widthMm,
        uRand: e.aggregate?.uRandMm,
        deviceModel: e.visit.deviceModel,
        algorithmVersion: e.aggregate?.algorithmVersion ?? '',
        sheetId: crack.sheetId,
      ),
  ];
  final points = computeTrend(visits, uPrintRel: crack.printScaleURel);
  return TrendData(
    crack: crack,
    entries: [for (var i = 0; i < entries.length; i++) TrendEntry(entry: entries[i], point: points[i])],
    outdatedVisitIds: [for (final e in entries) if (e.aggregate?.algorithmVersion != version) e.visit.id],
    currentVersion: version,
  );
});
