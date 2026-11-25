// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';

import 'l10n/strings.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

/// Release entry point of the checked-in tree: no marker detector is wired (the app does not
/// depend on `hairline_opencv`, so that `flutter test` runs on hosts that cannot build OpenCV,
/// BLOCKERS B1). A phone build uses `lib/main_device.dart` through `tools/build_device_apk.sh`.
Future<void> main() => runHairline();

/// Starts the app with the given provider [overrides] (the OpenCV factories on a phone).
Future<void> runHairline({List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory(); // private to the app (5.8)
  final container = ProviderContainer(overrides: [appDirectoryProvider.overrideWithValue(dir), ...overrides]);
  try {
    await sweepOrphanFrames(container.read(hairlineRepositoryProvider), container.read(frameStorageProvider));
  } on FileSystemException {
    // A leftover that cannot be deleted now is retried at the next start.
  }
  runApp(UncontrolledProviderScope(container: container, child: const HairlineApp()));
}

/// Root widget.
class HairlineApp extends ConsumerWidget {
  const HairlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(title: Strings.appName, theme: buildTheme(), routerConfig: ref.watch(routerProvider));
}
