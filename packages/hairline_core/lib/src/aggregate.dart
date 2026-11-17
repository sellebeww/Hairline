// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'measure.dart';
import 'quality.dart';
import 'rejection.dart';
import 'uncertainty.dart';

/// Outcome of a visit (5.4 visit gate, 5.5 reporting floor).
enum VisitStatus {
  /// Fewer than `minAcceptedFrames` accepted frames: ask for a retake, store nothing.
  ditolak('DITOLAK'),

  /// A width and its uncertainty are reported.
  terukur('TERUKUR'),

  /// Estimated but under the visit floor: shown as "di bawah batas ukur", no number.
  dibawahBatasUkur('DI_BAWAH_BATAS_UKUR'),

  /// Accepted frames, but too few of them measurable: no number.
  tidakTerukur('TIDAK_TERUKUR');

  const VisitStatus(this.code);
  final String code;
}

enum VisitIssue {
  tooFewAcceptedFrames('TOO_FEW_ACCEPTED_FRAMES'),
  mostlyUnmeasurable('MOSTLY_UNMEASURABLE');

  const VisitIssue(this.code);
  final String code;
}

/// One burst frame after the frame gate and [measureFrame]: either accepted (with its
/// record) or rejected with structured reasons.
final class FrameInput {
  const FrameInput.accepted(FrameRecord this.record)
      : geometryRejections = const [],
        measureRejection = null;

  const FrameInput.rejected({List<FrameRejection> geometry = const [], RejectReason? measure})
      : record = null,
        geometryRejections = geometry,
        measureRejection = measure;

  final FrameRecord? record;

  /// Geometry gate reasons (5.4).
  final List<FrameRejection> geometryRejections;

  /// Why [measureFrame] refused the frame (blur, saturation, crack not found, ...).
  final RejectReason? measureRejection;

  bool get accepted => record != null;

  List<String> get rejectionCodes => [
        for (final g in geometryRejections) g.code,
        if (measureRejection != null) measureRejection!.code,
      ];
}

/// Aggregated visit.
final class VisitResult {
  const VisitResult({
    required this.status,
    required this.issue,
    required this.budget,
    required this.acceptedFrames,
    required this.excludedUnmeasurableFrames,
    required this.frameRejections,
  });

  final VisitStatus status;
  final VisitIssue? issue;

  /// Present for [VisitStatus.terukur] and [VisitStatus.dibawahBatasUkur].
  final UncertaintyBudget? budget;

  /// Accepted frames considered (at most `maxStoredFrames`).
  final int acceptedFrames;

  /// Accepted frames left out of the median because they were TIDAK_TERUKUR.
  final int excludedUnmeasurableFrames;

  /// One entry per rejection reason per rejected frame (0-based frame index).
  final List<({int frame, String code})> frameRejections;

  Map<String, int> get rejectionCounts {
    final m = <String, int>{};
    for (final r in frameRejections) {
      m[r.code] = (m[r.code] ?? 0) + 1;
    }
    return m;
  }

  /// The width to show; null unless [status] is [VisitStatus.terukur].
  double? get reportableWidthMm => status == VisitStatus.terukur ? budget!.widthMm : null;

  /// A rejected visit is never stored as a measurement (5.4).
  bool get storable => status != VisitStatus.ditolak;
}

/// Aggregates the frames of one visit (5.4 gate, 5.5 median and budget).
///
/// Rules: at least `minAcceptedFrames` accepted frames, else [VisitStatus.ditolak].
/// Only the first `maxStoredFrames` accepted frames are used. Accepted frames whose
/// status is TIDAK_TERUKUR are excluded from the median; if fewer than
/// `minAcceptedFrames` usable frames remain, or they are not a strict majority of the
/// accepted ones, the visit is TIDAK_TERUKUR (dropping the hard frames of a faint crack
/// must not leave a confident number). Otherwise the budget is built and the width is
/// compared with the visit floor `max(0.5 mm/px, 2 u_c)`.
VisitResult aggregateVisit(
  List<FrameInput> frames, {
  UncertaintyOptions options = const UncertaintyOptions(),
  QualityThresholds thresholds = QualityThresholds.standard,
}) {
  final rejections = <({int frame, String code})>[
    for (var i = 0; i < frames.length; i++)
      if (!frames[i].accepted)
        for (final c in frames[i].rejectionCodes) (frame: i, code: c),
  ];
  final accepted = [for (final f in frames) if (f.accepted) f.record!].take(thresholds.maxStoredFrames).toList();
  if (accepted.length < thresholds.minAcceptedFrames) {
    return VisitResult(
      status: VisitStatus.ditolak,
      issue: VisitIssue.tooFewAcceptedFrames,
      budget: null,
      acceptedFrames: accepted.length,
      excludedUnmeasurableFrames: 0,
      frameRejections: rejections,
    );
  }
  final usable = [for (final r in accepted) if (r.status != MeasureStatus.tidakTerukur) r];
  final excluded = accepted.length - usable.length;
  if (usable.length < thresholds.minAcceptedFrames || usable.length * 2 <= accepted.length) {
    return VisitResult(
      status: VisitStatus.tidakTerukur,
      issue: VisitIssue.mostlyUnmeasurable,
      budget: null,
      acceptedFrames: accepted.length,
      excludedUnmeasurableFrames: excluded,
      frameRejections: rejections,
    );
  }
  final budget = UncertaintyBudget.fromFrames(usable, options);
  return VisitResult(
    status: budget.belowFloor ? VisitStatus.dibawahBatasUkur : VisitStatus.terukur,
    issue: null,
    budget: budget,
    acceptedFrames: accepted.length,
    excludedUnmeasurableFrames: excluded,
    frameRejections: rejections,
  );
}
