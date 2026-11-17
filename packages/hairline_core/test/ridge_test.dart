// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

SyntheticCamera cam({double tilt = 0, double roll = 0}) => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 180, // 0.06 mm/px at tilt 0
      tiltDeg: tilt,
      tiltAzimuthDeg: 40,
      rollDeg: roll,
    );

GrayPatch crackPatch({
  double w = 0.5,
  double dir = 20,
  double curv = 0,
  double sigma = 1.0,
  double noise = 0.005,
  double tilt = 0,
  double roll = 0,
  int seed = 5,
  Scene? scene,
}) =>
    renderCrackPatch(
      camera: cam(tilt: tilt, roll: roll),
      scene: scene ?? crackScene(widthMm: w, directionDeg: dir, curvaturePerMm: curv),
      halfSizeMm: 10,
      supersample: 4,
      psfSigmaPx: sigma,
      noiseSigma: noise,
      rng: Random(seed),
    );

/// Perpendicular distance (mm) from [p] to the true crack line through the origin.
double distToLine(Pt p, double dirDeg) {
  final a = dirDeg * pi / 180;
  return (p.x * -sin(a) + p.y * cos(a)).abs();
}

double angleDiffDeg(double a, double b) {
  var d = (a - b) % 180;
  if (d > 90) d -= 180;
  if (d < -90) d += 180;
  return d.abs();
}

void main() {
  group('patch noise estimate', () {
    test('recovers iid noise sigma on a flat patch within 5 percent (floats, no quantisation)', () {
      const sn = 0.02;
      final img = renderGray(
        width: 200,
        height: 200,
        toScene: pixelToSceneLinear(mmPerPx: 0.06),
        scene: (x, y) => 0.5,
        noiseSigma: sn,
        rng: Random(1),
        quantize8bit: false,
      );
      final p = GrayPatch(originX: 0, originY: 0, width: 200, height: 200, data: img.data);
      // 40000 samples: relative sd of a robust (MAD) estimate ~ 1.2/sqrt(n) ~ 0.6 percent; 5 percent is generous.
      expect(estimatePatchNoise(p), closeTo(sn, 0.05 * sn));
    });

    test('is not wrecked by a sharp crack in the patch', () {
      final p = crackPatch(w: 0.5, noise: 0.01);
      expect(estimatePatchNoise(p), closeTo(0.01, 0.002));
    });
  });

  group('crack ridge tracking (5.3 tracking)', () {
    final h = cam().h;

    test('stored point on the crack: centre and direction are precise', () {
      final r = findRidge(patch: crackPatch(), h: h, pointMm: const Pt(0, 0), directionDeg: 20);
      // Tolerances: the width fit re-centres exactly; the ridge only has to be within
      // a fraction of the +-3 mm profile range and below 2 degrees (cos 2 deg error
      // on the width is 6e-4).
      expect(distToLine(r.centerMm, 20), lessThan(0.03));
      expect(angleDiffDeg(r.directionDeg, 20), lessThan(1.0));
      expect(r.offsetMm, lessThan(0.05));
      expect(r.snr, greaterThan(10));
    });

    test('stored point 1 mm off the crack and direction 6 deg off: recovered', () {
      final a = 20 * pi / 180;
      final stored = Pt(-sin(a) * 1.0, cos(a) * 1.0); // 1 mm along the normal
      final r = findRidge(patch: crackPatch(), h: h, pointMm: stored, directionDeg: 26);
      expect(distToLine(r.centerMm, 20), lessThan(0.05));
      expect(angleDiffDeg(r.directionDeg, 20), lessThan(2.0));
      expect(r.offsetMm, closeTo(1.0, 0.06));
    });

    test('stored point 2 mm off (outside the 1.5 mm radius): rejected', () {
      final a = 20 * pi / 180;
      final stored = Pt(-sin(a) * 2.0, cos(a) * 2.0);
      expect(
        () => findRidge(patch: crackPatch(), h: h, pointMm: stored, directionDeg: 20),
        throwsA(isA<MeasurementException>().having((e) => e.reason, 'reason', RejectReason.crackNotFound)),
      );
    });

    test('no crack: rejected for 6 noise seeds (no false ridge from noise)', () {
      for (var seed = 1; seed <= 6; seed++) {
        final p = crackPatch(scene: (x, y) => 0.8, noise: 0.01, seed: seed);
        expect(
          () => findRidge(patch: p, h: h, pointMm: const Pt(0, 0), directionDeg: 20),
          throwsA(isA<MeasurementException>()),
          reason: 'seed $seed',
        );
      }
    });

    test('a 2 mm wide crack is centred (scale selection), not mistaken for two edges', () {
      final r = findRidge(patch: crackPatch(w: 2.0), h: h, pointMm: const Pt(0, 0), directionDeg: 20);
      expect(distToLine(r.centerMm, 20), lessThan(0.1));
    });

    test('tilted and rolled view: geometry is metric, not pixel', () {
      final c = cam(tilt: 25, roll: 15);
      final p = crackPatch(tilt: 25, roll: 15);
      final r = findRidge(patch: p, h: c.h, pointMm: const Pt(0, 0.7), directionDeg: 17);
      expect(distToLine(r.centerMm, 20), lessThan(0.05));
      expect(angleDiffDeg(r.directionDeg, 20), lessThan(2.0));
    });

    test('curved crack: direction follows the tangent at the point, line residual is larger', () {
      final straight = findRidge(patch: crackPatch(), h: h, pointMm: const Pt(0, 0), directionDeg: 20);
      final curved = findRidge(patch: crackPatch(curv: 0.1), h: h, pointMm: const Pt(0, 0), directionDeg: 20);
      expect(angleDiffDeg(curved.directionDeg, 20), lessThan(3.0));
      expect(curved.lineRmsMm, greaterThan(straight.lineRmsMm));
    });

    test('a faint sub-pixel crack is either located correctly or rejected, never mislocated', () {
      for (var seed = 1; seed <= 6; seed++) {
        final p = crackPatch(w: 0.05, noise: 0.01, seed: seed);
        try {
          final r = findRidge(patch: p, h: h, pointMm: const Pt(0, 0), directionDeg: 20);
          expect(distToLine(r.centerMm, 20), lessThan(0.1), reason: 'seed $seed');
        } on MeasurementException catch (e) {
          expect(e.reason, RejectReason.crackNotFound);
        }
      }
    });

    test('coarser sampling (0.1 mm/px): kernel support stays inside the profile', () {
      final c = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 300);
      final p = renderCrackPatch(
        camera: c,
        scene: crackScene(widthMm: 1.0, directionDeg: 20),
        halfSizeMm: 12,
        supersample: 2,
        psfSigmaPx: 1,
        noiseSigma: 0.005,
        rng: Random(2),
      );
      final r = findRidge(patch: p, h: c.h, pointMm: const Pt(0, 0.4), directionDeg: 15);
      expect(distToLine(r.centerMm, 20), lessThan(0.05));
    });

    test('profile running off the patch: patch too small', () {
      final small = renderCrackPatch(
        camera: cam(),
        scene: crackScene(widthMm: 0.5, directionDeg: 20),
        halfSizeMm: 2,
        psfSigmaPx: 1,
      );
      expect(
        () => findRidge(patch: small, h: h, pointMm: const Pt(0, 0), directionDeg: 20),
        throwsA(isA<MeasurementException>().having((e) => e.reason, 'reason', RejectReason.patchTooSmall)),
      );
    });
  });
}
