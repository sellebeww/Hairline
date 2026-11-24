// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

/// Debug and test only: stands in for ArUco by reading the detections that the fake
/// camera embedded in a live frame (`SyntheticPhotoCodec`). Same call path as production.
final class EmbeddedGrayMarkerDetector implements GrayMarkerDetector {
  const EmbeddedGrayMarkerDetector();

  @override
  List<MarkerDetection> detectGray(Uint8List gray, int width, int height) => SyntheticPhotoCodec.decode(gray).detections;
}

/// Top-level so that it can be sent to the detection isolate.
GrayMarkerDetector embeddedGrayDetector() => const EmbeddedGrayMarkerDetector();

/// Top-level ports for the photo pipeline over the same embedded container.
FramePorts embeddedFramePorts() => const FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector());
