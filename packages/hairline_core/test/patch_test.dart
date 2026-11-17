// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

GrayPatch fromFn(int w, int h, double Function(int, int) f, {int ox = 0, int oy = 0}) {
  final d = Float32List(w * h);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      d[j * w + i] = f(i, j);
    }
  }
  return GrayPatch(originX: ox, originY: oy, width: w, height: h, data: d);
}

void main() {
  group('GrayPatch', () {
    test('rejects inconsistent data length and tiny sizes', () {
      expect(() => GrayPatch(originX: 0, originY: 0, width: 4, height: 4, data: Float32List(15)), throwsArgumentError);
      expect(() => GrayPatch(originX: 0, originY: 0, width: 3, height: 8, data: Float32List(24)), throwsArgumentError);
    });

    test('at() is indexed in patch pixels, origin is in image pixels', () {
      final p = fromFn(8, 6, (i, j) => (10 * j + i) / 100, ox: 100, oy: 200);
      expect(p.at(3, 2), closeTo(0.23, 1e-6));
      expect(p.sampleCubic(103.0, 202.0), closeTo(0.23, 1e-6));
    });
  });

  group('Catmull-Rom sampler', () {
    test('reproduces pixel values exactly at integer coordinates', () {
      final rng = Random(3);
      final p = fromFn(12, 12, (i, j) => rng.nextDouble());
      for (var j = 1; j <= 10; j++) {
        for (var i = 1; i <= 10; i++) {
          expect(p.sampleCubic(i.toDouble(), j.toDouble()), closeTo(p.at(i, j), 1e-7));
        }
      }
    });

    test('reproduces a linear image exactly at fractional coordinates', () {
      // Weights of Catmull-Rom sum to 1 and have zero first moment: linear is exact.
      final p = fromFn(16, 16, (i, j) => 0.1 + 0.02 * i - 0.01 * j, ox: 40, oy: 7);
      for (final (x, y) in [(41.3, 9.7), (47.5, 15.25), (50.999, 20.001)]) {
        expect(p.sampleCubic(x, y), closeTo(0.1 + 0.02 * (x - 40) - 0.01 * (y - 7), 1e-6));
      }
    });

    test('error on a smooth signal stays below 0.05 |f\'\'\'| (tangent error bound)', () {
      // Hermite form with central-difference tangents: slope error f''' h^2 / 6, and
      // |h10|+|h11| = t(1-t) <= 1/4, so the error is below f''' h^3 / 24 ~ 0.05 f''' (h=1).
      const period = 32.0;
      final k = 2 * pi / period;
      final p = fromFn(64, 8, (i, j) => 0.5 + 0.4 * sin(k * i));
      final f3 = 0.4 * k * k * k;
      var worst = 0.0;
      for (var x = 2.0; x < 60; x += 0.137) {
        worst = max(worst, (p.sampleCubic(x, 4.0) - (0.5 + 0.4 * sin(k * x))).abs());
      }
      expect(worst, lessThan(0.05 * f3));
      expect(worst, greaterThan(0)); // not exact: it is an interpolant, not the function
    });

    test('boundary policy: NaN unless the full 4x4 support is inside the patch', () {
      final p = fromFn(10, 10, (i, j) => 0.5);
      expect(p.sampleCubic(1.0, 1.0), closeTo(0.5, 1e-7)); // first valid
      expect(p.sampleCubic(8.0, 8.0), closeTo(0.5, 1e-7)); // last valid (w-2)
      expect(p.sampleCubic(0.99, 5), isNaN);
      expect(p.sampleCubic(8.01, 5), isNaN);
      expect(p.sampleCubic(5, 0.5), isNaN);
      expect(p.sampleCubic(5, 9), isNaN);
      expect(p.sampleCubic(double.nan, 5), isNaN);
      expect(p.containsForCubic(1.0, 1.0), isTrue);
      expect(p.containsForCubic(0.5, 4), isFalse);
    });
  });

  group('metric profile sampler', () {
    // Tilt 0 and roll 30: H is a similarity, so a scene linear in mm is linear in px.
    final cam = SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 180, // 0.06 mm/px
      rollDeg: 30,
    );
    double lin(double x, double y) => 0.3 + 0.02 * x + 0.05 * y;
    final patch = renderCrackPatch(camera: cam, scene: lin, halfSizeMm: 6, quantize8bit: false);

    test('step is min(0.02 mm, 0.25 mm/px)', () {
      expect(profileStepMm(0.06), closeTo(0.015, 1e-15));
      expect(profileStepMm(0.2), 0.02);
    });

    test('samples a linear scene exactly at metric positions (perpendicular to the direction)', () {
      const dir = 20.0;
      final prof = sampleProfile(
        patch: patch,
        h: cam.h,
        centerMm: const Pt(0.4, -0.3),
        directionDeg: dir,
        halfRangeMm: 3,
        stepMm: 0.015,
        alongMm: 0.7,
      )!;
      expect(prof.n, (2 * 3 / 0.015).round() + 1);
      final a = dir * pi / 180;
      final tx = cos(a), ty = sin(a), nx = -ty, ny = tx;
      for (final i in [0, 17, prof.n ~/ 2, prof.n - 1]) {
        final s = prof.sAt(i);
        final x = 0.4 + 0.7 * tx + s * nx, y = -0.3 + 0.7 * ty + s * ny;
        // Image intensities are float32: tolerance 1e-6.
        expect(prof.values[i], closeTo(lin(x, y), 1e-6));
      }
      expect(prof.sAt(0), closeTo(-3, 1e-12));
      expect(prof.sAt(prof.n - 1), closeTo(3, 1e-9));
    });

    test('a profile running off the patch returns null', () {
      final prof = sampleProfile(
        patch: patch,
        h: cam.h,
        centerMm: const Pt(0, 0),
        directionDeg: 0,
        halfRangeMm: 10,
        stepMm: 0.05,
      );
      expect(prof, isNull);
    });

    test('directionalMmPerPx: isotropic at tilt 0, foreshortened along the tilt direction', () {
      expect(directionalMmPerPx(cam.h, const Pt(0, 0), const Pt(1, 0)), closeTo(0.06, 1e-9));
      final tilted = SyntheticCamera(
        image: const ImageSize(4000, 3000),
        fPx: 3000,
        distanceMm: 180,
        tiltDeg: 30,
      );
      final along = directionalMmPerPx(tilted.h, const Pt(0, 0), const Pt(1, 0));
      final across = directionalMmPerPx(tilted.h, const Pt(0, 0), const Pt(0, 1));
      // Tilt axis azimuth 0: the plane is foreshortened along y (rotation about x? see camera.dart).
      expect(max(along, across) / min(along, across), closeTo(1 / cos(30 * pi / 180), 5e-3));
    });
  });

  test('localMmPerPx equals the geometric mean of the principal scales (LocalScale)', () {
    for (final tilt in [0.0, 20.0]) {
      final cam = SyntheticCamera(
        image: const ImageSize(4000, 3000),
        fPx: 3000,
        distanceMm: 180,
        tiltDeg: tilt,
        rollDeg: 10,
      );
      final est = estimateSheetHomography(
        [for (final id in markerIdsForSheet(0)) MarkerDetection(id: id, corners: [for (final c in markerCornersMm(id)) cam.project(c)])],
        sheetId: 0,
      );
      expect(localMmPerPx(cam.h, const Pt(3, -2)), closeTo(est.localScale(const Pt(3, -2)).mmPerPx, 1e-4));
    }
  });

  group('sRGB linearisation', () {
    test('known values and continuity at the knee', () {
      expect(srgbToLinear(0), 0);
      expect(srgbToLinear(1), closeTo(1, 1e-12));
      expect(srgbToLinear(0.5), closeTo(0.21404114048223, 1e-12)); // standard reference value
      expect(srgbToLinear(0.04045), closeTo(0.04045 / 12.92, 1e-12));
      // The standard's rounded constants leave a jump of about 2e-9 at the knee.
      expect(srgbToLinear(0.0404500001), closeTo(srgbToLinear(0.04045), 1e-7));
    });

    test('patch copy keeps geometry, converts values, leaves the original untouched', () {
      final p = fromFn(6, 5, (i, j) => (i + 6 * j) / 29, ox: 7, oy: 9);
      final q = p.linearizedFromSrgb();
      expect((q.originX, q.originY, q.width, q.height), (7, 9, 6, 5));
      expect(q.at(3, 2), closeTo(srgbToLinear((3 + 12) / 29), 1e-6));
      expect(p.at(3, 2), closeTo(15 / 29, 1e-6));
    });
  });
}
