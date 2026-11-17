// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// STATUS: written, NOT YET RUN. The native OpenCV build cannot run on the development
// host (macOS without full Xcode, BLOCKERS B1, DECISIONS D1). Run on Linux CI or with
// `flutter test` once Xcode is installed: `cd packages/hairline_opencv && flutter test`.
// Tolerances below are reasoned, not measured.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_opencv/hairline_opencv.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

const _n = 800; // square scene so that 90 degree rotations keep the size
const _side = 120;
// Top-left pixel of each marker of sheet 0 (ids 0..3 = TL, TR, BR, BL), white margin around.
const _origins = [(100, 100), (580, 100), (580, 580), (100, 580)];

/// White scene with the four markers (ids 0..3 plus [extra] id/origin pairs).
cv.Mat _scene({List<(int, int, int)> extra = const []}) {
  final img = cv.Mat.zeros(_n, _n, cv.MatType.CV_8UC1).setTo(cv.Scalar.all(255));
  void put(int id, int x, int y) {
    final m = cv.arucoGenerateImageMarker(cv.PredefinedDictionaryType.DICT_4X4_50, id, _side, 1);
    final dst = img.region(cv.Rect(x, y, _side, _side));
    m.copyTo(dst);
    dst.dispose();
    m.dispose();
  }

  for (var i = 0; i < 4; i++) {
    put(i, _origins[i].$1, _origins[i].$2);
  }
  for (final (id, x, y) in extra) {
    put(id, x, y);
  }
  return img;
}

/// Marker corners in the pixel-centre convention (D3): the edge of pixel 100 is at 99.5.
List<Pt> _cornersOf(int id) {
  final (x, y) = _origins[id];
  const e = _side - 1.0; // outer edge to outer edge: _side px wide => corner to corner _side
  final x0 = x - 0.5, y0 = y - 0.5;
  return [Pt(x0, y0), Pt(x0 + e + 1, y0), Pt(x0 + e + 1, y0 + e + 1), Pt(x0, y0 + e + 1)];
}

cv.Mat _warp(cv.Mat src, Mat3 h) {
  final m = cv.Mat.fromList(3, 3, cv.MatType.CV_64FC1, h);
  final out = cv.warpPerspective(src, m, (_n, _n), borderValue: cv.Scalar.all(255));
  m.dispose();
  return out;
}

Uint8List _jpeg(cv.Mat m, {int quality = 95}) {
  final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]);
  final (ok, bytes) = cv.imencode('.jpg', m, params: params);
  params.dispose();
  expect(ok, isTrue);
  return bytes;
}

List<MarkerDetection> _detect(Uint8List jpeg) {
  final image = const OpenCvFrameImageSource().decode(jpeg);
  try {
    return const OpenCvMarkerDetector().detect(image);
  } finally {
    image.dispose();
  }
}

void main() {
  const rotations = <String, Mat3>{
    '0': [1, 0, 0, 0, 1, 0, 0, 0, 1],
    '90 cw': [0, -1, _n - 1, 1, 0, 0, 0, 0, 1],
    '180': [-1, 0, _n - 1, 0, -1, _n - 1, 0, 0, 1],
    '270 cw': [0, 1, 0, -1, 0, _n - 1, 0, 0, 1],
  };
  // A homography with perspective: mild tilt about both axes plus scale and shift.
  const perspective = <double>[0.92, 0.08, 40, -0.05, 0.95, 30, 0.00012, 0.00008, 1];

  group('OpenCvMarkerDetector: ids and corner order under rotation and perspective', () {
    for (final entry in {...rotations, 'perspective': perspective}.entries) {
      test('rotation/view ${entry.key}', () {
        final scene = _scene();
        final warped = _warp(scene, entry.value);
        scene.dispose();
        final dets = _detect(_jpeg(warped));
        warped.dispose();
        expect(dets.map((d) => d.id).toSet(), {0, 1, 2, 3});
        for (final d in dets) {
          expect(d.corners, hasLength(4));
          // The marker bits fix the corner order (TL, TR, BR, BL of the marker itself),
          // so corner j must sit where the warp sent original corner j (D2).
          final expected = [for (final c in _cornersOf(d.id)) applyHomography(entry.value, c)];
          for (var j = 0; j < 4; j++) {
            expect(d.corners[j].distanceTo(expected[j]), lessThan(0.8), reason: 'marker ${d.id} corner $j');
          }
        }
      });
    }
  });

  test('ids outside the sheet are returned (the core ignores them), ids are unique', () {
    final scene = _scene(extra: [(20, 340, 340)]);
    final dets = _detect(_jpeg(scene));
    scene.dispose();
    expect(dets.map((d) => d.id), containsAll([0, 1, 2, 3, 20]));
    expect(dets.map((d) => d.id).toSet().length, dets.length);
    expect(dets.every((d) => d.id >= 0 && d.id < arucoDictionarySize), isTrue);
  });

  test('an image without markers gives an empty list', () {
    final blank = cv.Mat.zeros(200, 200, cv.MatType.CV_8UC1).setTo(cv.Scalar.all(255));
    expect(_detect(_jpeg(blank)), isEmpty);
    blank.dispose();
  });

  test('the detector refuses an image that is not an OpenCvDecodedImage', () {
    expect(() => const OpenCvMarkerDetector().detect(_Foreign()), throwsArgumentError);
  });

  group('OpenCvFrameImageSource and OpenCvDecodedImage', () {
    test('decodes to gray with the right size; garbage and empty input throw FrameDecodeException', () {
      final scene = _scene();
      final image = const OpenCvFrameImageSource().decode(_jpeg(scene));
      scene.dispose();
      expect((image.width, image.height), (_n, _n));
      image.dispose();
      expect(() => const OpenCvFrameImageSource().decode(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<FrameDecodeException>()));
      expect(() => const OpenCvFrameImageSource().decode(Uint8List(0)), throwsA(isA<FrameDecodeException>()));
    });

    test('extractPatch returns 0..1 values, the right origin and size; outside rectangles are refused', () {
      final scene = _scene();
      final image = const OpenCvFrameImageSource().decode(_jpeg(scene, quality: 100));
      scene.dispose();
      final white = image.extractPatch(300, 300, 64, 48); // white paper
      expect((white.originX, white.originY, white.width, white.height), (300, 300, 64, 48));
      expect(white.data.reduce((a, b) => a < b ? a : b), greaterThan(0.95));
      final marker = image.extractPatch(100, 100, 120, 120); // the marker: black border
      expect(marker.data.reduce((a, b) => a < b ? a : b), lessThan(0.1));
      expect(() => image.extractPatch(780, 780, 64, 48), throwsRangeError);
      expect(() => image.extractPatch(-1, 0, 10, 10), throwsRangeError);
      image.dispose();
    });

    test('dispose is idempotent and extractPatch after dispose fails loudly', () {
      final scene = _scene();
      final image = const OpenCvFrameImageSource().decode(_jpeg(scene));
      scene.dispose();
      image.dispose();
      image.dispose();
      expect(() => image.extractPatch(0, 0, 10, 10), throwsStateError);
    });

    test('no native leak: 12 MP decode, detect, extract and dispose, repeated', () {
      final big = cv.Mat.zeros(3000, 4000, cv.MatType.CV_8UC1).setTo(cv.Scalar.all(200));
      final jpeg = _jpeg(big, quality: 90);
      big.dispose();
      final before = ProcessInfo.currentRss;
      for (var i = 0; i < 30; i++) {
        final image = const OpenCvFrameImageSource().decode(jpeg);
        const OpenCvMarkerDetector().detect(image);
        image.extractPatch(1000, 1000, 600, 600);
        image.dispose();
      }
      // A leak of one 12 MB Mat per round would add 360 MB. Allow allocator slack.
      expect(ProcessInfo.currentRss - before, lessThan(150 * 1024 * 1024));
    });
  });
}

final class _Foreign implements DecodedImage {
  @override
  int get width => 1;
  @override
  int get height => 1;
  @override
  GrayPatch extractPatch(int x, int y, int w, int h) => throw UnimplementedError();
  @override
  void dispose() {}
}
