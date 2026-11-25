// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:hairline_core/hairline_core.dart';

import '../domain/visit_view.dart';
import '../l10n/strings.dart';

/// One line for a visit result: "w ± U mm", "di bawah batas ukur (< x mm)" or "tidak terukur".
String visitSummary(AggregateView? a) {
  if (a == null) return Strings.statusNotMeasurable;
  if (a.numeric) return Strings.resultWidthHeadline(a.widthMm!, a.uExpandedMm!);
  if (a.status == VisitStatus.dibawahBatasUkur && a.floorMm != null) return Strings.belowFloor(a.floorMm!);
  return Strings.statusNotMeasurable;
}

IconData visitStatusIcon(VisitStatus s) => switch (s) {
      VisitStatus.terukur => Icons.straighten,
      VisitStatus.dibawahBatasUkur => Icons.vertical_align_bottom,
      VisitStatus.tidakTerukur || VisitStatus.ditolak => Icons.help_outline,
    };
