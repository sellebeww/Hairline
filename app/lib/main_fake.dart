// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_controller.dart';
import 'debug/embedded_ports.dart';
import 'debug/fake_scenario.dart';
import 'l10n/strings.dart';
import 'main.dart';
import 'providers.dart';

/// Debug entry point: the whole app on a scripted fake camera and synthetic photos, no
/// camera and no OpenCV needed. Run with `flutter run -t lib/main_fake.dart`. Add a site and
/// a crack (any ruler reading), then take the baseline: the first shot becomes the baseline
/// photo, tap the crack near the window centre (the simulated crack runs through it at
/// 25 degrees); every next visit is a follow-up guided by the ghost outline. All photos are
/// the same simulated 0.6 mm crack, so the trend will read "no change detected".
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text(Strings.demoPreparing)))),
  ));
  final scenario = await Isolate.run(buildFakeScenario);
  final dir = await Directory.systemTemp.createTemp('hairline_sim_');
  runApp(ProviderScope(
    overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      grayDetectorFactoryProvider.overrideWithValue(embeddedGrayDetector),
      cameraServiceProvider.overrideWith((ref) {
        final camera = scenario.service();
        ref.onDispose(camera.dispose);
        return camera;
      }),
    ],
    child: const HairlineApp(),
  ));
}
