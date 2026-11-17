// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'shell_page.dart';

part 'router.g.dart';

/// Core version, exposed through a generated provider to prove codegen works.
@riverpod
String coreVersion(Ref ref) => hairlineCoreVersion;

@riverpod
GoRouter router(Ref ref) =>
    GoRouter(routes: [GoRoute(path: '/', builder: (context, state) => const ShellPage())]);
