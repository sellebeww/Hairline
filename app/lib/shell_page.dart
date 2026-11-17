// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Placeholder home page. UI strings move to a central catalog in Phase 2.
class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Scaffold(body: Center(child: Text('Hairline core ${ref.watch(coreVersionProvider)}')));
}
