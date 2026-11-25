// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';

import '../domain/visit_view.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'queries.dart';

/// Result of one visit: width with its uncertainty, or why there is no number.
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key, required this.visitId});
  final int visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(Strings.resultTitle)),
        body: asyncBody(ref.watch(visitDetailProvider(visitId)), (d) {
          if (d == null) return const Center(child: Text(Strings.resultNotFound));
          final a = d.aggregate;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(Strings.date(d.visit.tsUtc), style: Theme.of(context).textTheme.labelLarge),
            Text(d.isBaseline ? Strings.visitBaseline : Strings.visitFollowup),
            const SizedBox(height: 12),
            _Headline(a),
            const SizedBox(height: 12),
            if (a != null) Text(Strings.resultFramesAccepted(a.acceptedFrames)),
            if (d.mmPerPx != null) Text(Strings.resultMmPerPx(d.mmPerPx!)),
            if (a != null) Text(Strings.resultAlgorithm(a.algorithmVersion)),
            Text(Strings.resultDevice(d.visit.deviceModel)),
            if (a == null || a.belumDivalidasi) ...[
              const SizedBox(height: 12),
              const StatusBadge(icon: Icons.science_outlined, text: Strings.notValidatedBadge, colors: StatusColors.caution),
              const Padding(padding: EdgeInsets.only(top: 6), child: Text(Strings.notValidatedMeaning)),
            ],
            if (d.cameraFlags.contains(Strings.flagFocusNotLocked)) const Padding(padding: EdgeInsets.only(top: 8), child: Text(Strings.warnFocusNotLocked)),
            if (d.cameraFlags.contains(Strings.flagExposureNotLocked)) const Padding(padding: EdgeInsets.only(top: 8), child: Text(Strings.warnExposureNotLocked)),
            if (a != null)
              for (final w in a.frameWarnings.entries)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(Strings.measureWarning(w.key, w.value))),
            if (d.isBaseline) const Padding(padding: EdgeInsets.only(top: 8), child: Text(Strings.resultBaselineNote)),
            const SectionTitle(Strings.resultPhotoTitle),
            if (d.photo == null)
              const Text(Strings.resultPhotoMissing)
            else
              Semantics(
                label: Strings.resultPhotoTitle,
                image: true,
                child: Image.file(File(d.photo!.path), height: 220, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Text(Strings.resultPhotoMissing)),
              ),
            if (a != null && a.budget.isNotEmpty) _Components(a),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => GoRouter.maybeOf(context)?.push('/trend/${d.crack.id}'),
              icon: const Icon(Icons.show_chart),
              label: const Text(Strings.viewTrend),
            ),
            const SizedBox(height: 12),
            const HonestyCard(),
          ]);
        }),
      );
}

class _Headline extends StatelessWidget {
  const _Headline(this.a);
  final AggregateView? a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = this.a;
    if (a != null && a.numeric) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(Strings.resultWidthHeadline(a.widthMm!, a.uExpandedMm!), style: t.headlineMedium)),
        if (a.k != null) Text(Strings.kFactor(a.k!)),
        const Text(Strings.resultWidthMeaning),
      ]);
    }
    if (a != null && a.status == VisitStatus.dibawahBatasUkur && a.floorMm != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(Strings.belowFloor(a.floorMm!), style: t.headlineSmall)),
        const Text(Strings.resultBelowFloorMeaning),
      ]);
    }
    final reasons = <String>[
      if (a?.issueCode == VisitIssue.mostlyUnmeasurable.code) Strings.reasonMostlyUnmeasurable,
      if (a?.issueCode == VisitIssue.tooFewAcceptedFrames.code) Strings.reasonTooFewFrames,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(Strings.statusNotMeasurable, style: t.headlineSmall)),
      const Text(Strings.resultNotMeasurableMeaning),
      for (final r in reasons) Text(r),
    ]);
  }
}

class _Components extends StatelessWidget {
  const _Components(this.a);
  final AggregateView a;

  static const _keys = [
    'u_fit_mean', 'u_repeat', 'u_stat', 'u_sigma_w', 'u_pos', 'u_par', 'u_geo', 'u_print', 'u_dev', 'u_rand', 'u_sys', 'u_c', 'u_expanded',
  ];

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(Strings.componentsTitle),
        children: [
          for (final k in _keys)
            if (a.budget[k] is num)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(Strings.componentLabel(k)),
                trailing: Text(Strings.num((a.budget[k]! as num).toDouble(), 4)),
              ),
          if (a.k != null) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(Strings.kFactor(a.k!))),
        ],
      );
}
