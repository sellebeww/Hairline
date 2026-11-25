// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../widgets/common.dart';
import 'queries.dart';

/// The cracks of one site.
class CracksPage extends ConsumerWidget {
  const CracksPage({super.key, required this.siteId});
  final int siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteProvider(siteId));
    return Scaffold(
      appBar: AppBar(title: Text(site.value == null ? Strings.sitesTitle : Strings.cracksTitle(site.value!.name))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sites/$siteId/cracks/new'),
        icon: const Icon(Icons.add),
        label: const Text(Strings.addCrack),
      ),
      body: asyncBody(ref.watch(cracksOfSiteProvider(siteId)), (cracks) {
        if (cracks.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(Strings.cracksEmpty)));
        return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final c in cracks)
            ListTile(
              leading: const Icon(Icons.straighten),
              title: Text(c.crack.label),
              subtitle: Text(c.hasBaseline ? Strings.crackVisitCount(c.visitCount) : Strings.crackNoBaseline),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/cracks/${c.crack.id}'),
            ),
        ]);
      }),
    );
  }
}
