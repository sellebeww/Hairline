// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// A JPEG decoded to one gray channel, owned natively as a [cv.Mat].
///
/// The `Mat` lives until [dispose] (called by `processFrame` in a `finally`).
/// Every temporary created by [extractPatch] is released inside a [ResourceScope].
final class OpenCvDecodedImage implements DecodedImage {
  OpenCvDecodedImage(this.gray);

  /// 8-bit, single channel. Read by [OpenCvMarkerDetector]; do not dispose it elsewhere.
  final cv.Mat gray;
  bool _disposed = false;

  @override
  int get width => gray.cols;

  @override
  int get height => gray.rows;

  @override
  GrayPatch extractPatch(int x, int y, int w, int h) {
    if (_disposed) throw StateError('image already disposed');
    if (x < 0 || y < 0 || w < 1 || h < 1 || x + w > width || y + h > height) {
      throw RangeError('patch $x,$y ${w}x$h is outside the ${width}x$height image');
    }
    return ResourceScope.run((scope) {
      final view = scope.add(gray.region(cv.Rect(x, y, w, h)), (m) => m.dispose());
      // A region is not contiguous: clone before reading `data` as one buffer.
      final copy = scope.add(view.clone(), (m) => m.dispose());
      final bytes = copy.data; // native view, valid until the scope releases `copy`
      final out = Float32List(w * h);
      for (var i = 0; i < out.length; i++) {
        out[i] = bytes[i] / 255;
      }
      return GrayPatch(originX: x, originY: y, width: w, height: h, data: out);
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    gray.dispose();
  }
}

/// Decodes JPEG with `cv.imdecode(IMREAD_GRAYSCALE)` (EXIF orientation is applied by
/// OpenCV; marker detection and the focal length from the long side do not depend on it).
final class OpenCvFrameImageSource implements FrameImageSource {
  const OpenCvFrameImageSource();

  @override
  DecodedImage decode(Uint8List encoded) {
    if (encoded.isEmpty) throw const FrameDecodeException('Foto kosong.');
    final mat = cv.imdecode(encoded, cv.IMREAD_GRAYSCALE);
    if (mat.isEmpty) {
      mat.dispose();
      throw const FrameDecodeException('Foto tidak dapat didekode.');
    }
    return OpenCvDecodedImage(mat);
  }
}
