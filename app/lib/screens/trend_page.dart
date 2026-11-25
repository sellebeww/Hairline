// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hairline_core/hairline_core.dart';

import '../l10n/strings.dart';
import '../pipeline/visit_processor.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'queries.dart';
import 'trend_chart.dart';
import 'visit_text.dart';

ColorPair _colorsOf(TrendClass? c) => switch (c) {
      TrendClass.kemungkinanBertambahLebar => StatusColors.wider,
      TrendClass.kemungkinanMenyempit => StatusColors.narrower,
      _ => StatusColors.neutral,
    };

IconData _iconOf(TrendClass? c) => switch (c) {
      TrendClass.kemungkinanBertambahLebar => Icons.trending_up,
      TrendClass.kemungkinanMenyempit => Icons.trending_down,
      TrendClass.tidakTerukur => Icons.help_outline,
      _ => Icons.horizontal_rule,
    };

/// Trend of a crack: chart, per-visit classification, MDC, context warnings, reprocessing.
class TrendPage extends ConsumerStatefulWidget {
  const TrendPage({super.key, required this.crackId});
  final int crackId;

  @override
  ConsumerState<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends ConsumerState<TrendPage> {
  String? _status;
  bool _busy = false;

  Future<void> _reprocess(TrendData data) async {
    final processor = ref.read(visitProcessorProvider);
    final repo = ref.read(hairlineRepositoryProvider);
    setState(() {
      _busy = true;
      _status = null;
    });
    var ok = 0, failed = 0;
    try {
      for (var i = 0; i < data.outdatedVisitIds.length; i++) {
        if (mounted) setState(() => _status = Strings.reprocessProgress(i + 1, data.outdatedVisitIds.length));
        final id = data.outdatedVisitIds[i];
        try {
          final visit = await repo.visit(id);
          final out = await processor.reprocess(id, camera: visit == null ? null : CameraInfo.fromJsonString(visit.cameraInfoJson));
          out is VisitReprocessed ? ok++ : failed++;
        } on Object {
          failed++;
        }
      }
      ref.invalidate(trendProvider(widget.crackId));
      ref.invalidate(crackDetailProvider(widget.crackId));
      if (mounted) _status = Strings.reprocessDone(ok, failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Strings.trendTitle)),
        body: asyncBody(ref.watch(trendProvider(widget.crackId)), (data) {
          if (data == null) return const Center(child: Text(Strings.crackNotFound));
          final entries = data.entries;
          final points = [
            for (final e in entries)
              ChartPoint(
                time: e.entry.visit.tsUtc,
                widthMm: e.entry.aggregate?.numeric ?? false ? e.entry.aggregate!.widthMm : null,
                uMm: e.entry.aggregate?.uExpandedMm,
                classification: e.point.vsBaseline?.classification,
              ),
          ];
          final items = [
            for (var i = 0; i < entries.length; i++)
              Strings.trendChartItem(
                i + 1,
                Strings.date(entries[i].entry.visit.tsUtc),
                '${visitSummary(entries[i].entry.aggregate)}${entries[i].point.vsBaseline == null ? '' : ', ${Strings.trendClass(entries[i].point.vsBaseline!.classification)}'}',
              ),
          ];
          final warnings = <ContextWarning>{for (final e in entries) ...?e.point.vsBaseline?.warnings, for (final e in entries) ...?e.point.vsPrevious?.warnings};
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (entries.length < 2) const Text(Strings.trendNeedTwo) else ...[
              TrendChart(points: points, semanticItems: items),
              const Text(Strings.trendBaselineLine),
              const Text(Strings.trendChartNote, style: TextStyle(fontSize: 12)),
            ],
            if (warnings.isNotEmpty) ...[
              const SectionTitle(Strings.trendWarningsTitle),
              for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: 6), child: StatusBadge(icon: Icons.warning_amber_rounded, text: Strings.contextWarning(w), colors: StatusColors.caution)),
            ],
            const SectionTitle(Strings.visitsTitle),
            for (var i = 0; i < entries.length; i++) _VisitTile(index: i, entry: entries[i]),
            const SizedBox(height: 8),
            const Text(Strings.trendNoForecast),
            const SectionTitle(Strings.reprocess),
            if (data.outdatedVisitIds.isEmpty)
              Text(Strings.reprocessUpToDate(data.currentVersion))
            else ...[
              const Text(Strings.reprocessBody),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: _busy ? null : () => _reprocess(data), icon: const Icon(Icons.refresh), label: const Text(Strings.reprocess)),
            ],
            if (_status != null) Semantics(liveRegion: true, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!))),
            const SizedBox(height: 12),
            const HonestyCard(),
          ]);
        }),
      );
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.index, required this.entry});
  final int index;
  final TrendEntry entry;

  @override
  Widget build(BuildContext context) {
    final a = entry.entry.aggregate;
    final b = entry.point.vsBaseline, p = entry.point.vsPrevious;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${index + 1}. ${Strings.date(entry.entry.visit.tsUtc)}', style: Theme.of(context).textTheme.titleSmall),
          Text(a != null && a.numeric ? Strings.trendVisitWidth(a.widthMm!, a.uExpandedMm!) : '${visitSummary(a)} (${Strings.trendNoNumber})'),
          const SizedBox(height: 6),
          if (b == null)
            const Text(Strings.trendBaselineTag)
          else ...[
            const Text(Strings.trendVsBaseline, style: TextStyle(fontWeight: FontWeight.w600)),
            _Comparison(b),
            if (index >= 2) ...[
              const SizedBox(height: 6),
              const Text(Strings.trendVsPrevious, style: TextStyle(fontWeight: FontWeight.w600)),
              if (p != null) _Comparison(p),
            ],
          ],
        ]),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison(this.c);
  final TrendComparison c;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatusBadge(icon: _iconOf(c.classification), text: Strings.trendClass(c.classification), colors: _colorsOf(c.classification)),
        if (c.classification == TrendClass.tidakAdaPerubahanTerdeteksi) const Text(Strings.trendClassNoneNote),
        if (c.delta != null) Text(Strings.trendDelta(c.delta!, c.uDelta!)),
        if (c.mdc != null) Text(Strings.trendMdc(c.mdc!)),
      ]);
}
