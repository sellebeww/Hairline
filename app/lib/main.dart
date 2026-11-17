// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

void main() => runApp(const ProviderScope(child: HairlineApp()));

/// Root widget. Phase 1 shell only; no business features yet.
class HairlineApp extends ConsumerWidget {
  const HairlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(title: 'Hairline', routerConfig: ref.watch(routerProvider));
}
