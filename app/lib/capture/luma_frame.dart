// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

/// A decimated grayscale frame for the live detector (the Y plane of a YUV420 image).
///
/// Small pixel `(i, j)` is source pixel `(i * step + offset, j * step + offset)`: plain
/// decimation, no averaging (markers are 100 px or more across, so aliasing is harmless
/// for pose guidance). Measurement never uses these frames; it uses the still photos.
final class LumaFrame {
  const LumaFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.step,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  /// Longest side the live detector works on.
  static const int defaultMaxLongSide = 800;

  /// Decimates a Y plane. [rowStride] is the distance between rows in [y] (>= [width]).
  factory LumaFrame.fromYPlane({
    required Uint8List y,
    required int width,
    required int height,
    required int rowStride,
    int maxLongSide = defaultMaxLongSide,
  }) {
    if (width < 1 || height < 1 || rowStride < width || y.length < rowStride * (height - 1) + width) {
      throw ArgumentError('Y plane of ${y.length} bytes does not fit ${width}x$height with stride $rowStride');
    }
    final longSide = width > height ? width : height;
    final step = (longSide + maxLongSide - 1) ~/ maxLongSide;
    final offset = step ~/ 2;
    final w = (width - offset - 1) ~/ step + 1, h = (height - offset - 1) ~/ step + 1;
    final out = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      final row = (j * step + offset) * rowStride + offset;
      for (var i = 0; i < w; i++) {
        out[j * w + i] = y[row + i * step];
      }
    }
    return LumaFrame(bytes: out, width: w, height: h, step: step, sourceWidth: width, sourceHeight: height);
  }

  final Uint8List bytes;
  final int width;
  final int height;
  final int step;
  final int sourceWidth;
  final int sourceHeight;

  double get _offset => (step ~/ 2).toDouble();

  /// A point of the small grid expressed in source pixels.
  Pt toSource(Pt p) => Pt(p.x * step + _offset, p.y * step + _offset);
}
