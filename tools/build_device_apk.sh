#!/usr/bin/env bash
# Copyright (c) 2026 Vassel Goleyu. MIT License.
# Builds the phone APK with the OpenCV marker detectors wired in (app/lib/main_device.dart).
#
# Why a script: `app/` must not depend on `hairline_opencv` in the checked-in tree, because the
# native OpenCV build runs on every `flutter test` and fails on hosts without full Xcode
# (docs/BLOCKERS.md B1). This script adds the dependency and the dartcv4 module list to
# app/pubspec.yaml for the duration of the build, then restores both pubspec files.
# Usage: tools/build_device_apk.sh [extra flutter build apk args, e.g. --split-per-abi]
set -euo pipefail

cd "$(dirname "$0")/../app"
backup="$(mktemp -d)"
cp pubspec.yaml pubspec.lock "$backup/"
restore() {
  cp "$backup/pubspec.yaml" "$backup/pubspec.lock" .
  rm -rf "$backup"
  flutter pub get --offline >/dev/null 2>&1 || flutter pub get >/dev/null
}
trap restore EXIT

python3 - <<'PY'
s = open("pubspec.yaml").read()
dep = "  hairline_core:\n    path: ../packages/hairline_core\n"
assert dep in s, "hairline_core dependency block not found"
s = s.replace(dep, dep + "  hairline_opencv:\n    path: ../packages/hairline_opencv\n", 1)
assert "\nhooks:" not in s
s += """
# Added by tools/build_device_apk.sh: native OpenCV modules (DECISIONS D10).
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

flutter pub get
flutter build apk --release -t lib/main_device.dart "$@"
