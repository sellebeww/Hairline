// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory(); // private to the app (5.8)
  final container = ProviderContainer(overrides: [
    appDirectoryProvider.overrideWithValue(dir),
    // TODO(B1): override framePortsFactoryProvider with `openCvPorts` and
    // grayDetectorFactoryProvider with `openCvGrayDetector` from package:hairline_opencv
    // once the app depends on it (DECISIONS D34, D40). Until then the capture screen
    // reports that no marker detector is available.
  ]);
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
      MaterialApp.router(title: 'Hairline', routerConfig: ref.watch(routerProvider));
}
