// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hairline_core/hairline_core.dart' show VisitStatus;

import '../l10n/strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'queries.dart';
import 'visit_text.dart';

/// One crack: the list of its visits and the button for a new visit.
class CrackDetailPage extends ConsumerWidget {
  const CrackDetailPage({super.key, required this.crackId});
  final int crackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(Strings.crackDetailTitle)),
        body: asyncBody(ref.watch(crackDetailProvider(crackId)), (detail) {
          if (detail == null) return const Center(child: Text(Strings.crackNotFound));
          final c = detail.crack;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Semantics(header: true, child: Text(c.label, style: Theme.of(context).textTheme.headlineSmall)),
            const SizedBox(height: 4),
            Text(Strings.crackInfo(c.sheetId, c.printScale)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.push('/capture/${c.id}'),
              icon: const Icon(Icons.camera_alt),
              label: Text(detail.hasBaseline ? Strings.newFollowupVisit : Strings.newBaselineVisit),
            ),
            if (detail.visits.length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/trend/${c.id}'),
                  icon: const Icon(Icons.show_chart),
                  label: const Text(Strings.viewTrend),
                ),
              ),
            const SectionTitle(Strings.visitsTitle),
            if (detail.visits.isEmpty)
              const Text(Strings.noVisits)
            else
              for (final e in detail.visits)
                Card(
                  child: ListTile(
                    leading: Icon(visitStatusIcon(e.aggregate?.status ?? VisitStatus.tidakTerukur)),
                    title: Text(e.visit.kind == 'baseline' ? Strings.visitBaseline : Strings.visitFollowup),
                    subtitle: Text('${Strings.date(e.visit.tsUtc)}\n${visitSummary(e.aggregate)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/result/${e.visit.id}'),
                  ),
                ),
            const SizedBox(height: 16),
            const StatusBadge(icon: Icons.link_off, text: Strings.seriesBrokenNote, colors: StatusColors.neutral),
          ]);
        }),
      );
}
