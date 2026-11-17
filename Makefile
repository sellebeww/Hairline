# Copyright (c) 2026 Vassel Goleyu. MIT License.
.PHONY: verify core-test app-test

core-test:
	cd packages/hairline_core && dart pub get && dart analyze --fatal-infos && dart test --coverage=coverage

app-test:
	cd app && flutter pub get && dart run build_runner build && flutter analyze && flutter test

verify: core-test app-test
