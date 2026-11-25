// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'queries.dart';

Map<String, Object?>? _results(ValidationRun r) {
  try {
    final j = jsonDecode(r.resultsJson);
    return j is Map<String, Object?> ? j : null;
  } on FormatException {
    return null;
  }
}

String _pct(num? v) => v == null ? '-' : '${Strings.num(v * 100, 0)} persen';
String _mm(num? v, [int d = 3]) => v == null ? '-' : Strings.num(v.toDouble(), d);

/// One line for the list of runs: source, truth and verdict.
String describeRun(ValidationRun r) {
  final j = _results(r);
  return Strings.validationRunSubtitle(r.source, j?['truth_source'] == 'KARAKTERISASI' ? 'KARAKTERISASI' : Strings.truthNominal, j?['validated'] == true);
}

/// The result of one plate run: honest wording, per width errors, empirical lower limit,
/// the effect on `u_dev`, and what to do next.
class ValidationRunPage extends ConsumerWidget {
  const ValidationRunPage({super.key, required this.runId});
  final int runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(Strings.validationResultTitle)),
        body: asyncBody(ref.watch(validationRunProvider(runId)), (run) {
          final j = run == null ? null : _results(run);
          if (run == null || j == null) return const Center(child: Text(Strings.errLoad));
          return _Body(run: run, json: j);
        }),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.run, required this.json});
  final ValidationRun run;
  final Map<String, Object?> json;

  @override
  Widget build(BuildContext context) {
    final stats = json['stats']! as Map<String, Object?>;
    final lines = (json['lines']! as List).cast<Map<String, Object?>>();
    final groups = (stats['groups']! as List).cast<Map<String, Object?>>();
    final validated = json['validated'] == true, characterized = json['truth_source'] == 'KARAKTERISASI';
    final simulated = run.source == 'SINTETIS';
    final reasons = (json['reasons']! as List).cast<String>();
    final lower = stats['lower_limit_mm'] as num?;
    final codes = {for (final l in lines) ...((l['rejections'] as Map<String, Object?>?)?.keys ?? const <String>[])};
    final lowStatus = lines.any((l) => l['status'] != 'TERUKUR');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        StatusBadge(
          icon: simulated ? Icons.science_outlined : Icons.smartphone,
          text: run.source,
          colors: simulated ? StatusColors.caution : StatusColors.neutral,
        ),
        StatusBadge(
          icon: characterized ? Icons.straighten : Icons.warning_amber_rounded,
          text: characterized ? 'KARAKTERISASI' : Strings.truthNominal,
          colors: characterized ? StatusColors.neutral : StatusColors.caution,
        ),
      ]),
      const SizedBox(height: 8),
      Text(simulated ? Strings.sourceSintetisNote : Strings.sourcePerangkatNote),
      Text(Strings.validationTruthSource(characterized)),
      const SizedBox(height: 12),
      StatusBadge(
        icon: validated && !simulated ? Icons.check_circle_outline : Icons.info_outline,
        text: validated && !simulated ? Strings.verdictValidated : Strings.verdictNotValidated,
        colors: validated && !simulated ? StatusColors.neutral : StatusColors.caution,
      ),
      if (reasons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: BulletList(reasons)),
      if (simulated) const Padding(padding: EdgeInsets.only(top: 8), child: Text(Strings.verdictNotValidated)),
      const SectionTitle(Strings.validationResultTitle),
      Text(Strings.validationOverall(
        (stats['reported']! as num).toInt(),
        (stats['n']! as num).toInt(),
        _mm(stats['bias_mm'] as num?),
        _mm(stats['rmse_mm'] as num?),
        _pct(stats['coverage'] as num?),
      )),
      const SizedBox(height: 4),
      Text(lower == null ? Strings.validationNoLowerLimit : Strings.validationLowerLimit(_mm(lower, 2))),
      const SizedBox(height: 4),
      Text(Strings.validationScope),
      const SectionTitle(Strings.validationGroupsTitle),
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(Strings.validationGroupRow(
            _mm(g['truth_mm'] as num?),
            (g['reported']! as num).toInt(),
            (g['n']! as num).toInt(),
            _mm(g['bias_mm'] as num?),
            _mm(g['rmse_mm'] as num?),
            _pct(g['coverage'] as num?),
          )),
        ),
      ExpansionTile(
        title: const Text(Strings.validationLinesTitle),
        children: [
          for (final l in lines)
            ListTile(
              dense: true,
              title: Text(Strings.validationLineRow(
                '${l['id']}',
                _mm(l['truth_mm'] as num?),
                l['measured_mm'] == null ? '-' : '${_mm(l['measured_mm'] as num?)} mm',
                '${l['status']}',
              )),
            ),
        ],
      ),
      const SectionTitle(Strings.validationRecommendTitle),
      BulletList([
        if (lowStatus || (stats['reported']! as num) < 32) Strings.recCloser,
        if (codes.contains('SATURATED') || lowStatus) Strings.recLight,
        if (codes.contains('BLUR_TOO_LARGE') || codes.contains('BLUR_ANISOTROPIC')) Strings.recSteady,
        if (!characterized) Strings.recUseCsv,
        Strings.recRepeat,
      ]),
      const SizedBox(height: 12),
      const HonestyCard(),
    ]);
  }
}
