# Copyright (c) 2026 Vassel Goleyu. MIT License.
.PHONY: verify core-test app-test opencv-analyze opencv-test

core-test:
	cd packages/hairline_core && dart pub get && dart analyze --fatal-infos && dart test --coverage=coverage

app-test:
	cd app && flutter pub get && dart run build_runner build && flutter analyze && flutter test

# The OpenCV adapters are only analyzed here: their native build does not run on this host (B1).
opencv-analyze:
	cd packages/hairline_opencv && flutter pub get && flutter analyze

# Needs a host where the native OpenCV build works (Linux CI, or macOS with full Xcode).
opencv-test:
	cd packages/hairline_opencv && flutter pub get && flutter test

verify: core-test opencv-analyze app-test
