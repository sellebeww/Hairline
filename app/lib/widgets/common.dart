// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// Loading, error and data states of an async provider in one place.
Widget asyncBody<T>(AsyncValue<T> value, Widget Function(T data) builder) => value.when(
      data: builder,
      loading: () => Center(child: Semantics(label: Strings.loading, child: const CircularProgressIndicator())),
      error: (e, st) => const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(Strings.errLoad))),
    );

/// A label with an icon on a colored background: status is never conveyed by color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.icon, required this.text, required this.colors});

  final IconData icon;
  final String text;
  final ColorPair colors;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: colors.fg),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(color: colors.fg, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// The honest statements of CLAUDE.md section 1 that must appear on the result, help screens.
class HonestyCard extends StatelessWidget {
  const HonestyCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(Strings.honestyTitle, style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 8),
            for (final t in const [
              Strings.honestyIndicative,
              Strings.honestyEngineer,
              Strings.honestyNoChange,
              Strings.honestyAccuracy,
              Strings.honestyCoplanar,
            ])
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t)),
          ]),
        ),
      );
}

/// A section heading.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      );
}

/// Bullet list of plain texts.
class BulletList extends StatelessWidget {
  const BulletList(this.items, {super.key});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.circle, size: 8)),
              const SizedBox(width: 10),
              Expanded(child: Text(t)),
            ]),
          ),
      ]);
}
