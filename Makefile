# Copyright (c) 2026 Vassel Goleyu. MIT License.
.PHONY: verify core-test app-test opencv-analyze opencv-test audit-docs audit-numeric apk-device

core-test:
	cd packages/hairline_core && dart pub get && dart analyze --fatal-infos && dart test --coverage=coverage

app-test:
	cd app && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test

# The OpenCV adapters are only analyzed here: their native build does not run on this host (B1).
opencv-analyze:
	cd packages/hairline_opencv && flutter pub get && flutter analyze

# Needs a host where the native OpenCV build works (Linux CI, or macOS with full Xcode).
opencv-test:
	cd packages/hairline_opencv && flutter pub get && flutter test

verify: core-test opencv-analyze app-test

# Text rules of CLAUDE.md over the tracked files (em dash, forbidden words, labelled numbers).
audit-docs:
	python3 tools/audit/doc_checks.py

# Independent recomputation (numpy/scipy, optional cv2) of core numbers; see docs/AUDIT.md.
# PY must be a Python with numpy and scipy (and opencv-contrib-python-headless for the real-detector cases).
PY ?= python3
audit-numeric:
	$(PY) tools/audit/independent_check.py gen build/audit_cases.json
	cd packages/hairline_core && dart run tool/audit_dump.dart ../../build/audit_cases.json ../../build/audit_out.json
	$(PY) tools/audit/independent_check.py cmp build/audit_cases.json build/audit_out.json

# Phone APK with the OpenCV detectors wired in (BLOCKERS B1); extra arguments go to flutter build apk.
apk-device:
	tools/build_device_apk.sh
