// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import '../frame_ports.dart';
import '../homography.dart';
import '../patch.dart';
import '../point.dart';
import 'camera.dart';
import 'patch_scene.dart';
import 'render.dart';

/// Linear light to the sRGB transfer curve: what a phone writes into a JPEG. The
/// renderer works in linear light; photos are encoded, and the pipeline linearizes.
double linearToSrgb(double v) => v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055;

/// 8-bit sRGB-encoded bytes of a linear-light render.
Uint8List srgbBytes(GrayImage img) => Uint8List.fromList([
      for (final v in img.data) (linearToSrgb(v.toDouble()) * 255).round().clamp(0, 255),
    ]);

/// Renders the whole photo of a sheet with one crack (markers as solid ink) as seen by
/// [camera]: linear light, PSF [psfSigmaPx], Gaussian [noiseSigma], 8-bit quantised.
/// [crackOverride] replaces the crack scene (violation scenes).
GrayImage renderSheetPhoto({
  required SyntheticCamera camera,
  required double crackWidthMm,
  required double crackDirectionDeg,
  int sheetId = 0,
  double printScale = 1,
  double psfSigmaPx = 1,
  double noiseSigma = 0.005,
  double depth = 0.6,
  double background = 0.8,
  int supersample = 2,
  Random? rng,
  Scene? crackOverride,
}) =>
    renderGray(
      width: camera.image.width,
      height: camera.image.height,
      toScene: (px, py) => camera.unproject(Pt(px, py)),
      scene: sheetWithCrackScene(
        sheetId: sheetId,
        printScale: printScale,
        crack: crackOverride ??
            crackScene(widthMm: crackWidthMm, depth: depth, directionDeg: crackDirectionDeg, background: background),
      ),
      supersample: supersample,
      psfSigmaPx: psfSigmaPx,
      noiseSigma: noiseSigma,
      rng: rng,
    );

/// Test-only "photo" container (not JPEG): raw 8-bit gray plus the marker detections a
/// real detector would find, so isolate and storage tests need no native code.
///
/// Layout: magic `HLSY`, u32 width, u32 height, u32 marker count, then per marker i32 id
/// and 8 float64 corner coordinates, then width*height bytes.
abstract final class SyntheticPhotoCodec {
  static const _magic = [0x48, 0x4C, 0x53, 0x59];

  static Uint8List encode(Uint8List gray, int width, int height, List<MarkerDetection> detections) {
    final headLen = 16 + detections.length * (4 + 64);
    final out = Uint8List(headLen + gray.length);
    final bd = ByteData.sublistView(out);
    out.setRange(0, 4, _magic);
    bd.setUint32(4, width);
    bd.setUint32(8, height);
    bd.setUint32(12, detections.length);
    var o = 16;
    for (final d in detections) {
      bd.setInt32(o, d.id);
      o += 4;
      for (final c in d.corners) {
        bd.setFloat64(o, c.x);
        bd.setFloat64(o + 8, c.y);
        o += 16;
      }
    }
    out.setRange(headLen, out.length, gray);
    return out;
  }

  /// Throws [FrameDecodeException] when [bytes] are not in this format.
  static ({int width, int height, List<MarkerDetection> detections, Uint8List gray}) decode(Uint8List bytes) {
    if (bytes.length < 16 || bytes[0] != _magic[0] || bytes[1] != _magic[1] || bytes[2] != _magic[2] || bytes[3] != _magic[3]) {
      throw const FrameDecodeException('Bukan foto sintetis.');
    }
    final bd = ByteData.sublistView(bytes);
    final w = bd.getUint32(4), h = bd.getUint32(8), n = bd.getUint32(12);
    final headLen = 16 + n * 68;
    if (bytes.length != headLen + w * h) throw const FrameDecodeException('Ukuran foto sintetis tidak cocok.');
    var o = 16;
    final dets = <MarkerDetection>[];
    for (var i = 0; i < n; i++) {
      final id = bd.getInt32(o);
      o += 4;
      final corners = <Pt>[];
      for (var k = 0; k < 4; k++) {
        corners.add(Pt(bd.getFloat64(o), bd.getFloat64(o + 8)));
        o += 16;
      }
      dets.add(MarkerDetection(id: id, corners: corners));
    }
    return (width: w, height: h, detections: dets, gray: Uint8List.sublistView(bytes, headLen));
  }
}

/// A [DecodedImage] over a Dart byte buffer. [onDispose] lets tests observe disposal.
class MemoryDecodedImage implements DecodedImage {
  MemoryDecodedImage(this.width, this.height, this.gray, {this.detections = const [], this.onDispose});

  @override
  final int width;
  @override
  final int height;
  final Uint8List gray;
  final List<MarkerDetection> detections;
  final void Function()? onDispose;

  @override
  GrayPatch extractPatch(int x, int y, int w, int h) {
    if (x < 0 || y < 0 || x + w > width || y + h > height) throw RangeError('patch outside the image');
    final data = Float32List(w * h);
    for (var j = 0; j < h; j++) {
      final row = (y + j) * width + x;
      for (var i = 0; i < w; i++) {
        data[j * w + i] = gray[row + i] / 255;
      }
    }
    return GrayPatch(originX: x, originY: y, width: w, height: h, data: data);
  }

  @override
  void dispose() => onDispose?.call();
}

/// Reads [SyntheticPhotoCodec] bytes. [trace] receives `open` and `close` events.
final class SyntheticPhotoSource implements FrameImageSource {
  const SyntheticPhotoSource({this.trace});
  final void Function(String event)? trace;

  @override
  DecodedImage decode(Uint8List encoded) {
    final p = SyntheticPhotoCodec.decode(encoded);
    trace?.call('open');
    return MemoryDecodedImage(p.width, p.height, p.gray, detections: p.detections, onDispose: () => trace?.call('close'));
  }
}

/// Returns the detections embedded in a [MemoryDecodedImage] (stands in for ArUco).
final class EmbeddedMarkerDetector implements MarkerDetector {
  const EmbeddedMarkerDetector();

  @override
  List<MarkerDetection> detect(DecodedImage image) =>
      image is MemoryDecodedImage ? image.detections : throw ArgumentError('needs a MemoryDecodedImage');
}

/// Encodes a rendered photo and its (noisy) detections as a [SyntheticPhotoCodec] "photo".
Uint8List syntheticPhoto(GrayImage linear, List<MarkerDetection> detections) =>
    SyntheticPhotoCodec.encode(srgbBytes(linear), linear.width, linear.height, detections);
