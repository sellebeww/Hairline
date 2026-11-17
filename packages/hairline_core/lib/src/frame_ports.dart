// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'homography.dart';
import 'patch.dart';

/// A decoded photo held by a platform adapter (for OpenCV: a native grayscale `Mat`).
/// The holder MUST call [dispose] exactly once; [processFrame] does so in a `finally`.
abstract interface class DecodedImage {
  int get width;
  int get height;

  /// Grayscale patch with values `0..1` (`byte/255`, D4) of the pixel rectangle
  /// `[x, x+w) x [y, y+h)`, which must lie inside the image. The values are the
  /// encoded (gamma) ones; the pipeline linearizes them.
  GrayPatch extractPatch(int x, int y, int w, int h);

  void dispose();
}

/// Thrown by [FrameImageSource.decode] when the bytes are not a readable photo.
final class FrameDecodeException implements Exception {
  const FrameDecodeException(this.message);
  final String message;

  @override
  String toString() => 'FrameDecodeException: $message';
}

/// Decodes a JPEG into a [DecodedImage] (no measurement logic).
abstract interface class FrameImageSource {
  /// Throws [FrameDecodeException] for unreadable input.
  DecodedImage decode(Uint8List encoded);
}

/// Detects the ArUco markers (`DICT_4X4_50`) of a decoded photo.
///
/// Contract (CLAUDE.md 5.1, D2, D3): only ids of the valid dictionary range are
/// returned, each with 4 corners in OpenCV order (TL, TR, BR, BL of the marker itself,
/// whatever the rotation of the phone), sub-pixel refined, in the pixel-centre
/// convention (pixel k is centred on coordinate k).
abstract interface class MarkerDetector {
  List<MarkerDetection> detect(DecodedImage image);
}

/// The two adapters a frame needs. Built inside the worker isolate by a factory.
final class FramePorts {
  const FramePorts({required this.source, required this.detector});
  final FrameImageSource source;
  final MarkerDetector detector;
}

/// Number of markers of the `DICT_4X4_50` dictionary: valid ids are `0..49`.
const int arucoDictionarySize = 50;
