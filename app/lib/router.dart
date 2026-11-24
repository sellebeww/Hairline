// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'capture/capture_page.dart';
import 'shell_page.dart';

part 'router.g.dart';

/// Core version, exposed through a generated provider to prove codegen works.
@riverpod
String coreVersion(Ref ref) => hairlineCoreVersion;

@riverpod
GoRouter router(Ref ref) => GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ShellPage()),
      GoRoute(
        path: '/capture/:crackId',
        builder: (context, state) => CapturePage(crackId: int.tryParse(state.pathParameters['crackId'] ?? '') ?? -1),
      ),
    ]);
