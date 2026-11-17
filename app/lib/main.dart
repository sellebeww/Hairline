// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory(); // private to the app (5.8)
  runApp(ProviderScope(
    overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      // TODO(B1): override framePortsFactoryProvider with `openCvPorts` from
      // package:hairline_opencv once the app depends on it (DECISIONS D34).
    ],
    child: const HairlineApp(),
  ));
}

/// Root widget. Phase 1 shell only; no business features yet.
class HairlineApp extends ConsumerWidget {
  const HairlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(title: 'Hairline', routerConfig: ref.watch(routerProvider));
}
