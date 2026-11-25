// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../router.dart';

/// App version, kept equal to `pubspec.yaml` (a test compares them).
const String appVersion = '1.0.0';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(Strings.aboutTitle)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Semantics(header: true, child: Text(Strings.appName, style: Theme.of(context).textTheme.headlineMedium)),
          Text(Strings.aboutVersion(appVersion)),
          Text(Strings.aboutCoreVersion(ref.watch(coreVersionProvider))),
          const SizedBox(height: 12),
          const Text(Strings.aboutPurpose),
          const SizedBox(height: 12),
          const Text(Strings.aboutOwner),
          const Text(Strings.aboutLicense),
          const SizedBox(height: 12),
          const Text(Strings.aboutPrivacy),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => showLicensePage(context: context, applicationName: Strings.appName, applicationVersion: appVersion),
            child: const Text(Strings.aboutThirdParty),
          ),
        ]),
      );
}
