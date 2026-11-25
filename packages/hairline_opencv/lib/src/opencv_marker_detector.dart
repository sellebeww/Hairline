// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'opencv_frame_image_source.dart';

/// `cv.ArucoDetectorParameters.cornerRefinementMethod` value for CORNER_REFINE_SUBPIX
/// (the Dart binding has no named constant; 0 none, 1 subpix, 2 contour, 3 apriltag).
const int cornerRefineSubpix = 1;

/// ArUco `DICT_4X4_50` detector with sub-pixel corner refinement.
///
/// Returns OpenCV's own corner order for each marker (TL, TR, BR, BL of the marker
/// itself, which the marker bits fix whatever the rotation of the phone, D2), keeps only
/// ids of the dictionary (0 to 49). A duplicated id (two copies of a sheet in view, or a false
/// positive) is passed on as it is: the core refuses the frame with `InvalidDetectionException`
/// instead of silently trusting whichever copy came first. The list order of
/// OpenCV is NOT id order; the core maps by id. Detector, parameters, dictionary and all
/// result vectors are created and released inside one [ResourceScope] per call.
final class OpenCvMarkerDetector implements MarkerDetector {
  const OpenCvMarkerDetector();

  @override
  List<MarkerDetection> detect(DecodedImage image) {
    if (image is! OpenCvDecodedImage) {
      throw ArgumentError.value(image, 'image', 'OpenCvMarkerDetector needs an OpenCvDecodedImage');
    }
    return ResourceScope.run((scope) => _detectMarkers(scope, image.gray));
  }
}

/// The same detector for the live preview: a raw 8-bit gray buffer (the decimated Y plane
/// of the camera stream) instead of a decoded photo. The `Mat` made from the buffer is
/// released inside the call, so the detection isolate holds no native object between frames.
final class OpenCvGrayMarkerDetector implements GrayMarkerDetector {
  const OpenCvGrayMarkerDetector();

  @override
  List<MarkerDetection> detectGray(Uint8List gray, int width, int height) {
    if (width < 1 || height < 1 || gray.length != width * height) {
      throw ArgumentError('gray buffer of ${gray.length} bytes is not ${width}x$height');
    }
    return ResourceScope.run((scope) {
      final mat = scope.add(cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, gray), (m) => m.dispose());
      return _detectMarkers(scope, mat);
    });
  }
}

List<MarkerDetection> _detectMarkers(ResourceScope scope, cv.Mat gray) {
  final params = scope.add(cv.ArucoDetectorParameters.empty(), (p) => p.dispose())..cornerRefinementMethod = cornerRefineSubpix;
  final dict = scope.add(cv.ArucoDictionary.predefined(cv.PredefinedDictionaryType.DICT_4X4_50), (d) => d.dispose());
  final detector = scope.add(cv.ArucoDetector.create(dict, params), (d) => d.dispose());
  final (corners, ids, rejected) = detector.detectMarkers(gray);
  scope.add(corners, (v) => v.dispose());
  scope.add(ids, (v) => v.dispose());
  scope.add(rejected, (v) => v.dispose());
  final out = <MarkerDetection>[];
  for (var k = 0; k < ids.length; k++) {
    final id = ids[k];
    if (id < 0 || id >= arucoDictionarySize) continue;
    final quad = scope.add(corners[k], (v) => v.dispose());
    if (quad.length != 4) continue;
    final pts = [for (var j = 0; j < 4; j++) scope.add(quad[j], (pt) => pt.dispose())];
    out.add(MarkerDetection(id: id, corners: [for (final pt in pts) Pt(pt.x, pt.y)]));
  }
  return out;
}
