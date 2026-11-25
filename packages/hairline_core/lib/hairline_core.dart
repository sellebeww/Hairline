// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Pure Dart core of Hairline: sheet geometry, homography, pose, quality gates.
/// The synthetic test harness lives in `package:hairline_core/synthetic.dart`.
library;

export 'src/aruco_bits.dart';
export 'src/frame_pipeline.dart';
export 'src/frame_ports.dart';
export 'src/homography.dart';
export 'src/linalg_small.dart';
export 'src/lm.dart';
export 'src/measure.dart';
export 'src/patch.dart';
export 'src/plate.dart';
export 'src/point.dart';
export 'src/pose.dart';
export 'src/profile_fit.dart';
export 'src/psf.dart';
export 'src/quality.dart';
export 'src/rejection.dart';
export 'src/resource_scope.dart';
export 'src/ridge.dart';
export 'src/scan_measure.dart';
export 'src/sheet.dart';
export 'src/sheet_layout.dart';
export 'src/special.dart';
export 'src/stats.dart';
export 'src/student_t.dart';
export 'src/uncertainty.dart';
export 'src/aggregate.dart';
export 'src/trend.dart';
export 'src/validation.dart';

/// Version of the core package, bumped with algorithm changes.
const String hairlineCoreVersion = '0.5.0';
