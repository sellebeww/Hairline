// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/live_analysis.dart';
import 'package:hairline/capture/reference_pose.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

const _image = ImageSize(1600, 1500);

SyntheticCamera _cam({double tilt = 4, double roll = 6, double dist = 0.12, double ox = 2, double oy = -1}) => SyntheticCamera(
      image: _image,
      fPx: 1280,
      distanceMm: dist * 1280,
      tiltDeg: tilt,
      tiltAzimuthDeg: 40,
      rollDeg: roll,
      offsetXmm: ox,
      offsetYmm: oy,
    );

List<MarkerDetection> _dets(SyntheticCamera c, {Set<int> omit = const {}, double noise = 0}) =>
    SyntheticDetector(noisePx: noise, rng: Random(1)).detect(c, sheetId: 0, omit: omit);

DetectionResult _result(List<MarkerDetection> dets, {int step = 1, int w = 1600, int h = 1500}) => DetectionResult(
      markers: dets,
      width: w,
      height: h,
      step: step,
      sourceWidth: 1600,
      sourceHeight: 1500,
      detectMicros: 0,
    );

LiveAnalyzer _analyzer({ReferencePose? reference, int quarterTurns = 0}) => LiveAnalyzer(
      sheetId: 0,
      printScale: 1,
      pointMm: const Pt(0, 0),
      quarterTurns: quarterTurns,
      reference: reference,
      focalMm: 5.4,
      sensorLongSideMm: 6.4, // f_px = 5.4 / 6.4 * 1600 = 1350, near the camera's 1280
    );

void main() {
  group('baseline (no reference)', () {
    test('a flat, near sheet is ready: gate passes, no instruction, no ghost, window and point drawn', () {
      final a = _analyzer().analyze(_result(_dets(_cam())));
      expect(a.markerCount, 4);
      expect(a.geometryRejections, isEmpty);
      expect(a.instructions, isEmpty);
      expect(a.ready, isTrue);
      expect(a.deviation, isNull);
      expect(a.ghost, isEmpty);
      expect(a.windowQuad, hasLength(4));
      expect(a.mmPerPx, closeTo(0.12, 0.01));
      expect(a.tiltDeg, closeTo(4, 2.5)); // approximate intrinsics (5.2)
    });

    test('a tilt above the 8 degree guide limit asks to hold flat although the 20 degree gate still passes', () {
      final a = _analyzer().analyze(_result(_dets(_cam(tilt: 15))));
      expect(a.geometryRejections, isEmpty);
      expect(a.instructions, [PoseInstruction.holdFlat]);
      expect(a.ready, isFalse);
    });

    test('a sheet too far for 0.20 mm/px is rejected and the guide says come closer', () {
      final a = _analyzer().analyze(_result(_dets(_cam(dist: 0.25))));
      expect(a.geometryRejections, contains(FrameRejection.resolutionTooCoarse));
      expect(a.instructions, contains(PoseInstruction.closer));
      expect(a.ready, isFalse);
    });

    test('two markers: "penanda tertutup", no pose, outlines still available for the overlay', () {
      final a = _analyzer().analyze(_result(_dets(_cam(), omit: {0, 3})));
      expect(a.markerCount, 2);
      expect(a.markers, hasLength(2));
      expect(a.geometryRejections, [FrameRejection.tooFewMarkers]);
      expect(a.estimate, isNull);
      expect(a.ready, isFalse);
    });

    test('markers of another sheet are ignored', () {
      final other = [for (final d in _dets(_cam())) MarkerDetection(id: d.id + 4, corners: d.corners)];
      final a = _analyzer().analyze(_result(other));
      expect(a.markerCount, 0);
      expect(a.geometryRejections, [FrameRejection.tooFewMarkers]);
    });
  });

  group('with a reference (follow-up visit)', () {
    ReferencePose referenceOf(SyntheticCamera c) =>
        LiveAnalyzer.referenceFrom(_analyzer().analyze(_result(_dets(c))))!;

    test('the same pose is ready and the ghost sits on the live markers', () {
      final ref = referenceOf(_cam());
      final a = _analyzer(reference: ref).analyze(_result(_dets(_cam())));
      expect(a.deviation, isNotNull);
      expect(a.ready, isTrue);
      expect(a.ghost, hasLength(4));
      for (var m = 0; m < 4; m++) {
        final live = a.markers[m];
        final ghost = a.ghost[m];
        // Marker order of both lists follows the sheet ids 0..3 (all four are present).
        for (var k = 0; k < 4; k++) {
          expect(ghost[k].distanceTo(live[k]), lessThan(0.01), reason: 'marker $m corner $k');
        }
      }
    });

    test('a displaced and closer phone gets instructions; the ghost stays where the reference was', () {
      final ref = referenceOf(_cam());
      final far = _analyzer(reference: ref).analyze(_result(_dets(_cam(ox: 20, oy: 10, dist: 0.09))));
      expect(far.ready, isFalse);
      expect(far.instructions, isNotEmpty);
      expect(far.instructions, contains(PoseInstruction.farther)); // 0.09 mm/px is closer than the reference
      expect(far.deviation!.translationFrac, greaterThan(0.03));
      final steadyGhost = _analyzer(reference: ref).analyze(_result(_dets(_cam())));
      expect(far.ghost.first.first.distanceTo(steadyGhost.ghost.first.first), lessThan(1e-6));
    });

    test('a reference of another aspect ratio is not comparable: generic rules apply and there is no ghost', () {
      final ref = referenceOf(_cam());
      final wide = ReferencePose(size: const ImageSize(1600, 900), h: ref.h, pose: ref.pose);
      final a = _analyzer(reference: wide).analyze(_result(_dets(_cam())));
      expect(a.deviation, isNull);
      expect(a.ghost, isEmpty);
      expect(a.ready, isTrue);
    });

    test('a reference taken at another live resolution is rescaled', () {
      final ref = referenceOf(_cam());
      expect(ref.size.longSide, referenceLongSide);
      final half = DetectionResult(
        markers: [
          for (final d in _dets(_cam())) MarkerDetection(id: d.id, corners: [for (final c in d.corners) c * 0.5]),
        ],
        width: 800,
        height: 750,
        step: 1,
        sourceWidth: 800,
        sourceHeight: 750,
        detectMicros: 0,
      );
      final a = LiveAnalyzer(sheetId: 0, printScale: 1, pointMm: const Pt(0, 0), quarterTurns: 0, reference: ref).analyze(half);
      expect(a.deviation!.scaleRatio, closeTo(1, 0.01));
      expect(a.deviation!.translationFrac, lessThan(0.005));
    });
  });

  group('geometry of the live frame', () {
    test('decimated detections are mapped back to source pixels', () {
      final exact = _dets(_cam());
      final small = [
        for (final d in exact)
          MarkerDetection(id: d.id, corners: [for (final c in d.corners) Pt((c.x - 20) / 40, (c.y - 20) / 40)]),
      ];
      final a = _analyzer().analyze(_result(small, step: 40, w: 40, h: 37));
      for (var m = 0; m < 4; m++) {
        for (var k = 0; k < 4; k++) {
          expect(a.markers[m][k].distanceTo(exact[m].corners[k]), lessThan(1e-9));
        }
      }
    });

    test('a sensor rotated by 90 degrees gives the same upright analysis (guidance in screen directions)', () {
      final upright = _analyzer().analyze(_result(_dets(_cam(ox: 20, oy: 10, dist: 0.09))));
      // Raw sensor frame is 1600 wide, 1500 high. Upright = 90 deg CW of raw: (x, y) -> (H-1-y, x).
      // So raw = (v, H-1-u) of an upright point (u, v) in a frame that is 1500 wide, 1600 high.
      const rawW = 1600, rawH = 1500;
      final uprightCam = SyntheticCamera(
        image: const ImageSize(rawH, rawW),
        fPx: 1280,
        distanceMm: 0.09 * 1280,
        tiltDeg: 4,
        tiltAzimuthDeg: 40,
        rollDeg: 6,
        offsetXmm: 20,
        offsetYmm: 10,
      );
      final uprightDets = SyntheticDetector(noisePx: 0, rng: Random(1)).detect(uprightCam, sheetId: 0);
      final raw = [
        for (final d in uprightDets) MarkerDetection(id: d.id, corners: [for (final c in d.corners) Pt(c.y, rawH - 1 - c.x)]),
      ];
      final a = _analyzer(quarterTurns: 1).analyze(DetectionResult(
        markers: raw,
        width: rawW,
        height: rawH,
        step: 1,
        sourceWidth: rawW,
        sourceHeight: rawH,
        detectMicros: 0,
      ));
      expect(a.size.width, rawH);
      expect(a.size.height, rawW);
      for (var m = 0; m < 4; m++) {
        for (var k = 0; k < 4; k++) {
          expect(a.markers[m][k].distanceTo(uprightDets[m].corners[k]), lessThan(1e-9));
        }
      }
      expect(upright.size.width, 1600, reason: 'sanity: quarterTurns 0 keeps the source size');
    });

    test('rotateUpright is a proper rotation: four turns are the identity', () {
      var p = const Pt(37, 11);
      var w = 100, h = 60;
      for (var i = 0; i < 4; i++) {
        p = rotateUpright(p, w, h, 1);
        (w, h) = (h, w);
      }
      expect(p, const Pt(37, 11));
      expect(rotateUpright(const Pt(0, 0), 100, 60, 2), const Pt(99, 59));
    });
  });

  group('stability', () {
    test('steady only when the pose matches the previous frame; a jump or reset breaks it', () {
      final an = _analyzer();
      expect(an.analyze(_result(_dets(_cam()))).steady, isFalse, reason: 'no previous frame');
      expect(an.analyze(_result(_dets(_cam()))).steady, isTrue);
      expect(an.analyze(_result(_dets(_cam(ox: 12)))).steady, isFalse, reason: 'moved');
      expect(an.analyze(_result(_dets(_cam(ox: 12)))).steady, isTrue);
      an.reset();
      expect(an.analyze(_result(_dets(_cam(ox: 12)))).steady, isFalse);
    });

    test('losing the markers forgets the previous pose', () {
      final an = _analyzer();
      an.analyze(_result(_dets(_cam())));
      an.analyze(_result(_dets(_cam(), omit: {0, 1})));
      expect(an.analyze(_result(_dets(_cam()))).steady, isFalse);
    });
  });

  group('ReferencePose', () {
    test('JSON round trip keeps pose and homography; malformed input gives null', () {
      final ref = LiveAnalyzer.referenceFrom(_analyzer().analyze(_result(_dets(_cam()))))!;
      final back = ReferencePose.tryParse(ref.toJsonString())!;
      expect(back.size.width, ref.size.width);
      expect(back.pose.tiltDeg, ref.pose.tiltDeg);
      expect(back.h, ref.h);
      for (final bad in [null, '', 'not json', '{}', '{"v":2}', '{"v":1,"image":{"w":1,"h":1},"h":[1],"pose":{}}']) {
        expect(ReferencePose.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('normalised to 1000 px and scaled back to the live frame', () {
      final a = _analyzer().analyze(_result(_dets(_cam())));
      final ref = LiveAnalyzer.referenceFrom(a)!;
      expect(ref.size.longSide, 1000);
      final at = ref.poseAt(_image);
      expect(at.centerPx.distanceTo(a.pose!.centerPx), lessThan(1e-9));
      expect(at.areaPx2 / a.pose!.areaPx2, closeTo(1, 1e-12));
    });
  });
}
