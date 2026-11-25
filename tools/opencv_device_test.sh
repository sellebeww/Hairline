#!/usr/bin/env bash
# Copyright (c) 2026 Vassel Goleyu. MIT License.
# Runs packages/hairline_opencv/test/opencv_adapters_test.dart ON AN ANDROID DEVICE OR EMULATOR
# (the native OpenCV build cannot run on hosts without full Xcode, docs/BLOCKERS.md B1).
# The same test file is wrapped as an integration test inside app/ for the duration of the run;
# app/pubspec.yaml, pubspec.lock and app/integration_test are restored or removed afterwards.
# Usage: tools/opencv_device_test.sh [device id, default: the only connected device]
set -euo pipefail

export PATH="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools:$PATH"
cd "$(dirname "$0")/../app"
device="${1:-}"
backup="$(mktemp -d)"
cp pubspec.yaml pubspec.lock "$backup/"
restore() {
  cp "$backup/pubspec.yaml" "$backup/pubspec.lock" .
  rm -rf "$backup" integration_test
  flutter pub get --offline >/dev/null 2>&1 || flutter pub get >/dev/null
}
trap restore EXIT

python3 - <<'PY'
s = open("pubspec.yaml").read()
dep = "  hairline_core:\n    path: ../packages/hairline_core\n"
assert dep in s, "hairline_core dependency block not found"
s = s.replace(dep, dep + "  hairline_opencv:\n    path: ../packages/hairline_opencv\n  opencv_dart: ^2.2.2\n", 1)
dev = "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n"
assert dev in s, "dev_dependencies block not found"
s = s.replace(dev, dev + "  integration_test:\n    sdk: flutter\n", 1)
assert "\nhooks:" not in s
s += """
hooks:
  user_defines:
    dartcv4:
      include_modules:
        - imgproc
        - imgcodecs
        - calib3d
        - objdetect
        - aruco
"""
open("pubspec.yaml", "w").write(s)
PY

mkdir -p integration_test
cat > integration_test/opencv_adapters_it.dart <<'DART'
import 'package:integration_test/integration_test.dart';

import '../../packages/hairline_opencv/test/opencv_adapters_test.dart' as adapters;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  adapters.main();
}
DART
flutter pub get
args=()
[ -n "$device" ] && args=(-d "$device")
flutter test integration_test/opencv_adapters_it.dart "${args[@]}"
