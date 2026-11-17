// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// Phase 1 spike: proves opencv_dart can (a) generate DICT_4X4_50 markers,
// (b) detect them with sub-pixel corner refinement, (c) decode JPEG to gray
// and extract an ROI patch. Findings are recorded in docs/SPIKE_OPENCV.md.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

const _side = 120;
const _origins = [(100, 100), (580, 100), (580, 580), (100, 580)];

cv.Mat _scene() {
  final img = cv.Mat.zeros(800, 800, cv.MatType.CV_8UC1).setTo(cv.Scalar.all(255));
  for (var i = 0; i < _origins.length; i++) {
    final m = cv.arucoGenerateImageMarker(cv.PredefinedDictionaryType.DICT_4X4_50, i, _side, 1);
    final (x, y) = _origins[i];
    final dst = img.region(cv.Rect(x, y, _side, _side));
    m.copyTo(dst);
    dst.dispose();
    m.dispose();
  }
  return img;
}

double _maxCornerErr(cv.VecVecPoint2f corners, cv.VecI32 ids) {
  var worst = 0.0;
  for (var k = 0; k < ids.length; k++) {
    final (x, y) = _origins[ids[k]];
    final truth = [(x, y), (x + _side, y), (x + _side, y + _side), (x, y + _side)];
    for (var j = 0; j < 4; j++) {
      final p = corners[k][j];
      final dx = p.x - (truth[j].$1 - 0.5);
      final dy = p.y - (truth[j].$2 - 0.5);
      final e = dx * dx + dy * dy;
      if (e > worst) worst = e;
    }
  }
  return worst;
}

({int n, double err}) _detect(cv.Mat img, int refine) {
  final params = cv.ArucoDetectorParameters.empty()..cornerRefinementMethod = refine;
  final det = cv.ArucoDetector.create(
    cv.ArucoDictionary.predefined(cv.PredefinedDictionaryType.DICT_4X4_50),
    params,
  );
  final (corners, ids, rejected) = det.detectMarkers(img);
  final r = (n: ids.length, err: _maxCornerErr(corners, ids));
  corners.dispose();
  ids.dispose();
  rejected.dispose();
  det.dispose();
  params.dispose();
  return r;
}

void main() {
  test('aruco generate + detect with and without sub-pixel refinement', () {
    final img = _scene();
    final none = _detect(img, 0);
    final sub = _detect(img, 1);
    // ignore: avoid_print
    print('SPIKE none: n=${none.n} maxErr^2=${none.err}; subpix: n=${sub.n} maxErr^2=${sub.err}');
    expect(sub.n, 4);
    expect(sub.err, lessThan(1.0));
    img.dispose();
  });

  test('JPEG decode to gray and ROI patch extraction', () {
    final img = _scene();
    final (ok, jpg) = cv.imencode('.jpg', img);
    expect(ok, isTrue);
    final gray = cv.imdecode(Uint8List.fromList(jpg), cv.IMREAD_GRAYSCALE);
    expect(gray.channels, 1);
    final roi = gray.region(cv.Rect(300, 300, 64, 48));
    final patch = Float32List.fromList(roi.clone().data.map((v) => v / 255).toList());
    expect(patch.length, 64 * 48);
    // Scene is white in the middle; JPEG keeps it near 1.0.
    expect(patch.reduce((a, b) => a < b ? a : b), greaterThan(0.95));
    roi.dispose();
    gray.dispose();
    img.dispose();
  });
}
