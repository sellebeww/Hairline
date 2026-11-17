// Copyright (c) 2026 Vassel Goleyu. MIT License.
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
/// ids of the dictionary (0 to 49) and drops duplicates of an id. The list order of
/// OpenCV is NOT id order; the core maps by id. Detector, parameters, dictionary and all
/// result vectors are created and released inside one [ResourceScope] per call.
final class OpenCvMarkerDetector implements MarkerDetector {
  const OpenCvMarkerDetector();

  @override
  List<MarkerDetection> detect(DecodedImage image) {
    if (image is! OpenCvDecodedImage) {
      throw ArgumentError.value(image, 'image', 'OpenCvMarkerDetector needs an OpenCvDecodedImage');
    }
    return ResourceScope.run((scope) {
      final params = scope.add(cv.ArucoDetectorParameters.empty(), (p) => p.dispose())..cornerRefinementMethod = cornerRefineSubpix;
      final dict = scope.add(cv.ArucoDictionary.predefined(cv.PredefinedDictionaryType.DICT_4X4_50), (d) => d.dispose());
      final detector = scope.add(cv.ArucoDetector.create(dict, params), (d) => d.dispose());
      final (corners, ids, rejected) = detector.detectMarkers(image.gray);
      scope.add(corners, (v) => v.dispose());
      scope.add(ids, (v) => v.dispose());
      scope.add(rejected, (v) => v.dispose());
      final seen = <int>{};
      final out = <MarkerDetection>[];
      for (var k = 0; k < ids.length; k++) {
        final id = ids[k];
        if (id < 0 || id >= arucoDictionarySize || !seen.add(id)) continue;
        final quad = scope.add(corners[k], (v) => v.dispose());
        if (quad.length != 4) continue;
        final pts = [for (var j = 0; j < 4; j++) scope.add(quad[j], (pt) => pt.dispose())];
        out.add(MarkerDetection(id: id, corners: [for (final pt in pts) Pt(pt.x, pt.y)]));
      }
      return out;
    });
  }
}
