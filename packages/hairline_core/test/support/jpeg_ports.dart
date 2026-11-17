// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:image/image.dart' as img;

/// Real baseline JPEG of an 8-bit gray image (R=G=B), at [quality] (0..100).
Uint8List encodeGrayJpeg(Uint8List gray, int width, int height, int quality) {
  final rgb = Uint8List(width * height * 3);
  for (var i = 0; i < gray.length; i++) {
    rgb[3 * i] = rgb[3 * i + 1] = rgb[3 * i + 2] = gray[i];
  }
  final image = img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// Decodes JPEG with the `image` package and keeps the luma, like OpenCV's
/// IMREAD_GRAYSCALE. Stands in for the OpenCV source in tests that must run anywhere.
final class DartJpegSource implements FrameImageSource {
  DartJpegSource({this.onDispose});
  final void Function()? onDispose;

  @override
  DecodedImage decode(Uint8List encoded) {
    final image = img.decodeJpg(encoded);
    if (image == null) throw const FrameDecodeException('JPEG rusak.');
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final gray = Uint8List(image.width * image.height);
    for (var i = 0; i < gray.length; i++) {
      gray[i] = (0.299 * rgb[3 * i] + 0.587 * rgb[3 * i + 1] + 0.114 * rgb[3 * i + 2]).round();
    }
    return MemoryDecodedImage(image.width, image.height, gray, onDispose: onDispose);
  }
}

/// Returns the next prepared detection list on every call (one per frame of a burst).
final class QueueDetector implements MarkerDetector {
  QueueDetector(Iterable<List<MarkerDetection>> queue) : _queue = queue.toList();
  final List<List<MarkerDetection>> _queue;
  int calls = 0;

  @override
  List<MarkerDetection> detect(DecodedImage image) => _queue[calls++ % _queue.length];
}
