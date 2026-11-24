// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_controller.dart';
import 'capture/capture_page.dart';
import 'debug/demo_seed.dart';
import 'debug/embedded_ports.dart';
import 'debug/fake_scenario.dart';
import 'l10n/strings.dart';
import 'providers.dart';

/// Debug entry point: the whole capture flow on a scripted fake camera and synthetic
/// photos, no camera and no OpenCV needed. Run with `flutter run -t lib/main_fake.dart`.
/// The first shot is the baseline visit; after "Ulangi" the next one is a follow-up
/// guided by the ghost outline of the stored pose.
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
    child: const _SimApp(),
  ));
}

class _SimApp extends ConsumerStatefulWidget {
  const _SimApp();

  @override
  ConsumerState<_SimApp> createState() => _SimAppState();
}

class _SimAppState extends ConsumerState<_SimApp> {
  late final Future<int> _crack = seedDemoCrack(ref.read(hairlineRepositoryProvider), directionDeg: demoCrackDirectionDeg);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hairline (simulasi)',
        home: FutureBuilder<int>(
          future: _crack,
          builder: (context, snap) =>
              snap.hasData ? CapturePage(crackId: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
      );
}
