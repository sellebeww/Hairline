// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Pure Dart core of Hairline: sheet geometry, homography, pose, quality gates.
/// The synthetic test harness lives in `package:hairline_core/synthetic.dart`.
library;

export 'src/homography.dart';
export 'src/linalg_small.dart';
export 'src/point.dart';
export 'src/pose.dart';
export 'src/quality.dart';
export 'src/sheet.dart';

/// Version of the core package, bumped with algorithm changes.
const String hairlineCoreVersion = '0.1.0';
