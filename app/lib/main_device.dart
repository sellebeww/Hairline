// Copyright (c) 2026 Vassel Goleyu. MIT License.
// Phone entry point with the OpenCV marker detectors wired in. Not analyzed or compiled by
// `flutter analyze` / `flutter test` (excluded in analysis_options.yaml): the dependency on
// `hairline_opencv` is added only by `tools/build_device_apk.sh`, because the native OpenCV
// build cannot run on hosts without full Xcode (BLOCKERS B1).
import 'package:hairline_opencv/hairline_opencv.dart';

import 'capture/capture_controller.dart';
import 'main.dart';
import 'providers.dart';

Future<void> main() => runHairline(overrides: [
      framePortsFactoryProvider.overrideWithValue(openCvPorts),
      grayDetectorFactoryProvider.overrideWithValue(openCvGrayDetector),
    ]);
