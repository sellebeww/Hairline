// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'debug/demo_seed.dart';
import 'l10n/strings.dart';
import 'providers.dart';
import 'router.dart';

/// Placeholder home page. The real screens (cracks, trend, validation) come in later phases.
class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Hairline core ${ref.watch(coreVersionProvider)}'),
            if (kDebugMode)
              TextButton(
                onPressed: () async {
                  // Debug only: the screens that create cracks do not exist yet.
                  final id = await seedDemoCrack(ref.read(hairlineRepositoryProvider));
                  if (context.mounted) unawaited(context.push('/capture/$id'));
                },
                child: const Text(Strings.debugOpenCapture),
              ),
          ]),
        ),
      );
}
