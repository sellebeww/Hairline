// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

// Same synthetic geometry as frame_pipeline_test: 0.12 mm/px, crack through the window
// centre at 25 degrees. Everything here is SINTETIS (a rendered photo, no phone).
const _image = ImageSize(1600, 1500);
const _dir = 25.0;
const _ports = FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector());

void main() {
  late final SyntheticCamera cam;
  late final Uint8List photo;
  setUpAll(() {
    cam = SyntheticCamera(
      image: _image,
      fPx: 1280,
      distanceMm: 0.12 * 1280,
      tiltDeg: 8,
      tiltAzimuthDeg: 40,
      rollDeg: 12,
      offsetXmm: 3,
      offsetYmm: -2,
    );
    final gray = srgbBytes(renderSheetPhoto(camera: cam, crackWidthMm: 0.6, crackDirectionDeg: _dir, noiseSigma: 0.004, rng: Random(5)));
    photo = SyntheticPhotoCodec.encode(gray, _image.width, _image.height, SyntheticDetector(noisePx: 0.2, rng: Random(6)).detect(cam, sheetId: 0));
  });

  PointLocation locate(Pt? tapMm, {Uint8List? bytes}) => locateCrackPoint(
        encoded: bytes ?? photo,
        ports: _ports,
        sheetId: 0,
        printScale: 1,
        tapPx: tapMm == null ? null : applyHomography(cam.h, tapMm),
      );

  /// Distance of a sheet point from the true crack line (through the origin at 25 degrees).
  double offLine(Pt p) {
    final a = _dir * pi / 180;
    return (p.x * -sin(a) + p.y * cos(a)).abs();
  }

  test('without a tap only the homography is returned (for the overlay)', () {
    final r = locate(null);
    expect(r.h, isNotNull);
    expect(r.markerCount, 4);
    expect(r.located, isFalse);
    expect(r.size.width, 1600);
  });

  test('a tap 1.5 mm beside the crack snaps to the centreline with the right direction', () {
    const a = _dir * pi / 180;
    final along = Pt(cos(a), sin(a)), normal = Pt(-sin(a), cos(a));
    for (final (s, n) in [(0.0, 1.5), (8.0, -1.5), (-10.0, 1.0)]) {
      final tap = along * s + normal * n;
      final r = locate(tap);
      expect(r.located, isTrue, reason: '${r.message}');
      // tolerance: 0.05 mm is under half a pixel (0.12 mm/px) of the true line
      expect(offLine(r.pointMm!), lessThan(0.05), reason: 'tap $tap -> ${r.pointMm}');
      expect((r.directionDeg! - _dir).abs(), lessThan(2.0), reason: '${r.directionDeg}');
      expect(isInsideMeasurementZone(r.pointMm!), isTrue);
    }
  });

  test('a tap far from the crack is refused with a specific message', () {
    final r = locate(const Pt(20, 20)); // 9.7 mm from the line
    expect(r.located, isFalse);
    expect(r.message, contains('Retak tidak ditemukan'));
  });

  test('a tap outside the 50 x 50 mm zone is refused', () {
    final r = locate(const Pt(30, 0));
    expect(r.located, isFalse);
    expect(r.message, contains('di luar area ukur'));
  });

  test('a photo with fewer than 3 markers is refused; unreadable bytes too', () {
    final gray = Uint8List(_image.width * _image.height)..fillRange(0, _image.width * _image.height, 128);
    final two = SyntheticPhotoCodec.encode(gray, _image.width, _image.height, SyntheticDetector(rng: Random(1)).detect(cam, sheetId: 0, omit: {0, 1}));
    expect(locate(const Pt(0, 0), bytes: two).message, contains('Penanda tertutup'));
    expect(locate(const Pt(0, 0), bytes: Uint8List.fromList([1, 2])).message, isNotNull);
  });
}
