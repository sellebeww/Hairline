// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../widgets/common.dart';
import 'queries.dart';

/// Home: the list of sites.
class SitesPage extends ConsumerWidget {
  const SitesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(Strings.sitesTitle), actions: [
          IconButton(icon: const Icon(Icons.fact_check_outlined), tooltip: Strings.validationEntry, onPressed: () => context.push('/validation')),
          IconButton(icon: const Icon(Icons.help_outline), tooltip: Strings.menuHelp, onPressed: () => context.push('/help')),
          IconButton(icon: const Icon(Icons.info_outline), tooltip: Strings.menuAbout, onPressed: () => context.push('/about')),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/sites/new'),
          icon: const Icon(Icons.add),
          label: const Text(Strings.addSite),
        ),
        body: asyncBody(ref.watch(sitesProvider), (sites) {
          if (sites.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(Strings.sitesEmpty)));
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final s in sites)
              ListTile(
                leading: const Icon(Icons.apartment),
                title: Text(s.name),
                subtitle: s.notes.isEmpty ? null : Text(s.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/sites/${s.id}'),
              ),
          ]);
        }),
      );
}
