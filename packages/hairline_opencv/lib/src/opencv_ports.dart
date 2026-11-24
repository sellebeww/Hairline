// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';

import 'opencv_frame_image_source.dart';
import 'opencv_marker_detector.dart';

/// Factory for the worker isolate: top-level so that it can be passed across isolates.
FramePorts openCvPorts() => const FramePorts(source: OpenCvFrameImageSource(), detector: OpenCvMarkerDetector());

/// Factory of the live detector for the detection isolate (top-level, so it can be sent).
GrayMarkerDetector openCvGrayDetector() => const OpenCvGrayMarkerDetector();
