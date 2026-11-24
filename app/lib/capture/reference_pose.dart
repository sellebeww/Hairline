// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:hairline_core/hairline_core.dart';

import '../pipeline/json_util.dart';

/// Longest image side the stored reference is normalised to, so that a reference taken
/// at one live resolution can be compared at another of the same aspect ratio.
const double referenceLongSide = 1000;

/// The pose of the baseline visit (5.2), stored in `visits.reference_pose_json`.
///
/// Everything is in the upright live frame (the stream rotated to the way the user holds
/// the phone), normalised to [referenceLongSide]. [h] maps sheet mm to those pixels and is
/// used to draw the target (ghost) outline; [pose] feeds `comparePose`.
final class ReferencePose {
  const ReferencePose({required this.size, required this.h, required this.pose});

  /// Normalises an estimate made on an upright live frame of [size].
  factory ReferencePose.fromEstimate({required Mat3 h, required PoseState pose, required ImageSize size}) {
    final k = referenceLongSide / size.longSide;
    return ReferencePose(
      size: ImageSize((size.width * k).round(), (size.height * k).round()),
      h: [for (var i = 0; i < 9; i++) i < 6 ? h[i] * k : h[i]],
      pose: PoseState(
        centerPx: pose.centerPx * k,
        areaPx2: pose.areaPx2 * k * k,
        rotationDeg: pose.rotationDeg,
        tiltDeg: pose.tiltDeg,
      ),
    );
  }

  final ImageSize size;
  final Mat3 h;
  final PoseState pose;

  String toJsonString() => encodeJson({
        'v': 1,
        'image': {'w': size.width, 'h': size.height},
        'h': h,
        'pose': {
          'cx': pose.centerPx.x,
          'cy': pose.centerPx.y,
          'area': pose.areaPx2,
          'rot_deg': pose.rotationDeg,
          'tilt_deg': pose.tiltDeg,
        },
      });

  /// Null for missing or malformed JSON (the guidance then falls back to the generic rules).
  static ReferencePose? tryParse(String? source) {
    if (source == null) return null;
    try {
      final j = jsonDecode(source);
      if (j is! Map<String, Object?> || j['v'] != 1) return null;
      final image = j['image'], h = j['h'], pose = j['pose'];
      if (image is! Map<String, Object?> || h is! List<Object?> || h.length != 9 || pose is! Map<String, Object?>) return null;
      double n(Object? v) => (v! as num).toDouble();
      final values = [for (final v in h) n(v)];
      final p = PoseState(
        centerPx: Pt(n(pose['cx']), n(pose['cy'])),
        areaPx2: n(pose['area']),
        rotationDeg: n(pose['rot_deg']),
        tiltDeg: n(pose['tilt_deg']),
      );
      final w = (image['w']! as num).toInt(), hh = (image['h']! as num).toInt();
      final finite = values.every((v) => v.isFinite) && p.centerPx.isFinite && p.areaPx2.isFinite && p.areaPx2 > 0;
      if (!finite || w < 1 || hh < 1) return null;
      return ReferencePose(size: ImageSize(w, hh), h: values, pose: p);
    } on Object {
      return null; // bad JSON, missing keys or wrong types
    }
  }

  /// Same orientation and aspect ratio (within 3 percent): a reference from another
  /// camera, crop or phone orientation is not comparable.
  bool isCompatibleWith(ImageSize live) {
    final a = size.width / size.height, b = live.width / live.height;
    return (a - b).abs() / a <= 0.03;
  }

  double _scaleTo(ImageSize live) => live.longSide / referenceLongSide;

  /// The reference pose in the pixels of a live frame of size [live].
  PoseState poseAt(ImageSize live) {
    final k = _scaleTo(live);
    return PoseState(
      centerPx: pose.centerPx * k,
      areaPx2: pose.areaPx2 * k * k,
      rotationDeg: pose.rotationDeg,
      tiltDeg: pose.tiltDeg,
    );
  }

  /// The four markers of [sheetId] where the reference had them, in pixels of [live].
  List<List<Pt>> ghostMarkers(ImageSize live, {required int sheetId, double printScale = 1}) {
    final k = _scaleTo(live);
    return [
      for (final id in markerIdsForSheet(sheetId))
        [for (final c in markerCornersMm(id, printScale: printScale)) applyHomography(h, c) * k],
    ];
  }
}
