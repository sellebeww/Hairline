// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
double _std(List<double> v) {
  final m = _mean(v);
  return sqrt(v.fold<double>(0, (s, x) => s + (x - m) * (x - m)) / (v.length - 1));
}

void main() {
  group('gaussian / detector noise', () {
    test('gaussian: mean 0, std 1 over 20000 draws (seed 1)', () {
      final rng = Random(1);
      final v = [for (var i = 0; i < 20000; i++) gaussian(rng)];
      // Standard error of the mean is 1/sqrt(20000)=0.007; 5 sigma = 0.035.
      expect(_mean(v).abs(), lessThan(0.035));
      expect(_std(v), closeTo(1, 0.03));
    });

    test('detector with noise 0.2 px: per-coordinate std 0.2, mean 0', () {
      final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 240);
      final det = SyntheticDetector(noisePx: 0.2, rng: Random(5));
      final errs = <double>[];
      for (var t = 0; t < 500; t++) {
        for (final d in det.detect(cam, sheetId: 0)) {
          final truth = markerCornersMm(d.id).map(cam.project).toList();
          for (var k = 0; k < 4; k++) {
            errs
              ..add(d.corners[k].x - truth[k].x)
              ..add(d.corners[k].y - truth[k].y);
          }
        }
      }
      expect(_mean(errs).abs(), lessThan(0.005)); // 5 sigma of 0.2/sqrt(16000)
      expect(_std(errs), closeTo(0.2, 0.006));
    });

    test('same seed gives identical detections; zero noise is exact', () {
      final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 240, tiltDeg: 12);
      final a = SyntheticDetector(noisePx: 0.3, rng: Random(9)).detect(cam, sheetId: 2);
      final b = SyntheticDetector(noisePx: 0.3, rng: Random(9)).detect(cam, sheetId: 2);
      expect(a.first.corners, b.first.corners);
      final exact = SyntheticDetector().detect(cam, sheetId: 2);
      expect(exact.first.corners.first, cam.project(markerCornersMm(8).first));
    });

    test('omit and shiftPx behave as documented', () {
      final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 240);
      final det = SyntheticDetector();
      expect(det.detect(cam, sheetId: 0, omit: {1, 2}).map((d) => d.id), [0, 3]);
      final moved = det.detect(cam, sheetId: 0, shiftPx: {0: const Pt(3, -2)});
      final base = det.detect(cam, sheetId: 0);
      expect(moved[0].corners[0] - base[0].corners[0], const Pt(3, -2));
      expect(moved[1].corners, base[1].corners);
    });
  });

  group('SyntheticCamera', () {
    test('H maps the sheet origin to the principal point plus offset projection', () {
      final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 240);
      final p = cam.project(const Pt(0, 0));
      expect(p.x, closeTo(1999.5, 1e-9));
      expect(p.y, closeTo(1499.5, 1e-9));
      // 12 mm along x at 0.08 mm/px: 150 px.
      expect(cam.project(const Pt(12, 0)).x, closeTo(1999.5 + 150, 1e-9));
    });

    test('unproject inverts project for random cameras', () {
      final rng = Random(3);
      for (var i = 0; i < 20; i++) {
        final cam = SyntheticCamera.random(rng);
        const p = Pt(17, -23);
        expect(cam.unproject(cam.project(p)).distanceTo(p), lessThan(1e-9));
      }
    });

    test('random cameras are realistic: whole frame inside the image, tilt within the bound', () {
      final rng = Random(4);
      for (var i = 0; i < 200; i++) {
        final cam = SyntheticCamera.random(rng, maxTiltDeg: 25);
        expect(cam.tiltDeg, inInclusiveRange(0, 25));
        for (final id in markerIdsForSheet(0)) {
          for (final c in markerCornersMm(id)) {
            final p = cam.project(c);
            expect(p.x, inInclusiveRange(0, 4000), reason: '$i $c');
            expect(p.y, inInclusiveRange(0, 3000), reason: '$i $c');
          }
        }
        expect(cam.nominalMmPerPx, inInclusiveRange(0.09, 0.15));
      }
    });

    test('same seed gives the same random camera', () {
      final a = SyntheticCamera.random(Random(8));
      final b = SyntheticCamera.random(Random(8));
      expect(a.h, b.h);
    });

    test('true tilt equals the plane normal angle (checked via 3D normal)', () {
      final cam = SyntheticCamera(
        image: const ImageSize(4000, 3000),
        fPx: 3000,
        distanceMm: 240,
        tiltDeg: 25,
        tiltAzimuthDeg: 123,
        rollDeg: 40,
      );
      expect(estimateTilt(cam.h, cam.intrinsics).tiltDeg, closeTo(25, 1e-4));
    });
  });

  group('renderer basics', () {
    test('flat scene renders flat and 8-bit quantised', () {
      final img = renderGray(
        width: 16,
        height: 12,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.5,
      );
      for (final v in img.data) {
        expect(v, closeTo(128 / 255, 1e-6)); // round(0.5*255)=128
      }
      expect(img.width, 16);
      expect(img.at(3, 4), closeTo(128 / 255, 1e-6));
    });

    test('quantisation: every value is k/255; disabled keeps the exact value', () {
      final q = renderGray(
        width: 10,
        height: 10,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.123456,
      );
      for (final v in q.data) {
        expect((v * 255 - (v * 255).round()).abs(), lessThan(1e-4));
      }
      final f = renderGray(
        width: 10,
        height: 10,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.123456,
        quantize8bit: false,
      );
      expect(f.data.first, closeTo(0.123456, 1e-6));
    });

    test('anti-aliasing: an edge pixel gets the fractional coverage within 1/supersample', () {
      // Pixel i is centred on i and covers [i-0.5, i+0.5). Black for x_px > 10.3
      // so pixel 10 is 20 percent black. Axis-aligned edges quantise coverage to
      // 1/S, so the error bound is 0.5/S (here S = 8: 0.0625).
      final img = renderGray(
        width: 21,
        height: 4,
        toScene: (px, py) => Pt(px, py),
        scene: (x, y) => x > 10.3 ? 0.0 : 1.0,
        supersample: 8,
        quantize8bit: false,
      );
      expect(img.at(10, 1), closeTo(0.8, 0.5 / 8));
      expect(img.at(9, 1), 1.0);
      expect(img.at(11, 1), 0.0);
    });

    test('Gaussian PSF: a step edge becomes the normal CDF with the requested sigma', () {
      const sigma = 1.5;
      final img = renderGray(
        width: 61,
        height: 3,
        toScene: (px, py) => Pt(px, py),
        scene: (x, y) => x > 30.0 ? 0.0 : 1.0, // edge at x=30.0 (pixel 30 is half black)
        supersample: 8,
        psfSigmaPx: sigma,
        quantize8bit: false,
      );
      // I(i) = 1 - integral over the pixel of Phi((x-30)/sigma); sample at pixel
      // centres i=27..33 and compare to the pixel-integrated CDF (erf), tolerance
      // 0.01 for the 1/8 px quadrature.
      double phi(double z) => 0.5 * (1 + _erf(z / sqrt2));
      for (var i = 26; i <= 34; i++) {
        var expected = 0.0;
        for (var k = 0; k < 1000; k++) {
          expected += 1 - phi((i - 0.5 + (k + 0.5) / 1000 - 30) / sigma);
        }
        expected /= 1000;
        expect(img.at(i, 1), closeTo(expected, 0.01), reason: 'pixel $i');
      }
    });

    test('PSF keeps a flat image flat (edge replicate)', () {
      final img = renderGray(
        width: 20,
        height: 20,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.7,
        psfSigmaPx: 2,
        quantize8bit: false,
      );
      for (final v in img.data) {
        expect(v, closeTo(0.7, 1e-6));
      }
    });

    test('Gaussian noise: std matches sigma, mean unbiased, seeded and clipped', () {
      img(int seed) => renderGray(
            width: 100,
            height: 100,
            toScene: pixelToSceneLinear(mmPerPx: 0.1),
            scene: (x, y) => 0.5,
            noiseSigma: 0.02,
            rng: Random(seed),
            quantize8bit: false,
          );
      final a = img(1);
      final v = [for (final x in a.data) x.toDouble()];
      expect(_mean(v), closeTo(0.5, 0.002)); // 5 sigma = 5*0.02/100
      expect(_std(v), closeTo(0.02, 0.001));
      expect(img(1).data, a.data);
      expect(img(2).data, isNot(a.data));
      final bright = renderGray(
        width: 50,
        height: 50,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.99,
        noiseSigma: 0.1,
        rng: Random(3),
        quantize8bit: false,
      );
      expect(bright.data.every((x) => x >= 0 && x <= 1), isTrue);
    });

    test('illumination gradient: multiplicative, +-10 percent across the width', () {
      final img = renderGray(
        width: 100,
        height: 10,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.5,
        illumGradX: 0.2,
        quantize8bit: false,
      );
      expect(img.at(0, 5), closeTo(0.5 * (1 + 0.2 * (0.5 / 100 - 0.5)), 1e-6));
      expect(img.at(99, 5) / img.at(0, 5), closeTo((1 + 0.2 * (99.5 / 100 - 0.5)) / (1 + 0.2 * (0.5 / 100 - 0.5)), 1e-6));
      // Vertical gradient leaves a row constant.
      final v = renderGray(
        width: 10,
        height: 100,
        toScene: pixelToSceneLinear(mmPerPx: 0.1),
        scene: (x, y) => 0.5,
        illumGradY: -0.2,
        quantize8bit: false,
      );
      expect(v.at(0, 3), v.at(9, 3));
      expect(v.at(0, 0), greaterThan(v.at(0, 99)));
    });

    test('bilinear sample interpolates and clamps at the border', () {
      final img = renderGray(
        width: 4,
        height: 1,
        toScene: (px, py) => Pt(px, py),
        scene: (x, y) => x < 1.5 ? 0.2 : 0.8,
        supersample: 1,
        quantize8bit: false,
      );
      // Pixel centres at 0,1,2,3 sample the scene at those points: 0.2,0.2,0.8,0.8.
      expect(img.sample(1.5, 0), closeTo(0.5, 1e-6));
      expect(img.sample(-5, 0), closeTo(0.2, 1e-6));
      expect(img.sample(10, 3), closeTo(0.8, 1e-6));
    });
  });

  group('renderer validation: effective crack width equals nominal', () {
    // The integral of the darkness across the crack equals depth * width for any
    // PSF (convolution preserves area). Quadrature error: each edge is placed to
    // within 0.5/S px by an S x S sub-sample grid, so |w_eff - w| <= 1/S px.
    const mmPerPx = 0.01; // "high resolution": 10 um per pixel
    const ss = 8;
    const bg = 0.8, depth = 0.6;

    GrayImage crack(double w, double dir, {double sigma = 0, int s = ss}) => renderGray(
          width: 130,
          height: 130,
          toScene: pixelToSceneLinear(mmPerPx: mmPerPx, centerPx: const Pt(64.5, 64.5)),
          scene: crackScene(widthMm: w, depth: depth, directionDeg: dir, background: bg),
          supersample: s,
          psfSigmaPx: sigma,
          quantize8bit: false,
        );
    double eff(GrayImage img, double dir) => effectiveWidthMm(
          img,
          mmPerPx: mmPerPx,
          directionDeg: dir,
          background: bg,
          depth: depth,
          halfRangeMm: 0.6,
        );

    for (final w in [0.1, 0.3, 1.0]) {
      for (final dir in [0.0, 90.0, 30.0, 117.0]) {
        test('width $w mm, direction $dir deg, no PSF', () {
          final tol = mmPerPx / ss + 1e-6; // 1/S pixel, in mm
          expect(eff(crack(w, dir), dir), closeTo(w, tol));
        });
      }
    }

    for (final w in [0.1, 0.3, 0.8]) {
      test('width $w mm with a Gaussian PSF (sigma 1.5 px, 30 deg)', () {
        // Supersample 4 keeps the blur affordable: bound 1/4 px.
        expect(eff(crack(w, 30, sigma: 1.5, s: 4), 30), closeTo(w, mmPerPx / 4 + 1e-6));
      });
    }

    test('8-bit quantisation and 1 percent noise keep the width within 1 percent', () {
      const w = 0.3;
      final img = renderGray(
        width: 130,
        height: 130,
        toScene: pixelToSceneLinear(mmPerPx: mmPerPx, centerPx: const Pt(64.5, 64.5)),
        scene: crackScene(widthMm: w, depth: depth, directionDeg: 20, background: bg),
        supersample: 4,
        psfSigmaPx: 1.5,
        noiseSigma: 0.01,
        rng: Random(21),
      );
      expect(eff(img, 20), closeTo(w, 0.01 * w));
    });

    test('curved crack (R = 50 mm) has the nominal width along its local normal', () {
      const w = 0.3;
      final scene = crackScene(widthMm: w, depth: depth, directionDeg: 0, curvaturePerMm: 1 / 50, background: bg);
      final img = renderGray(
        width: 130,
        height: 130,
        toScene: pixelToSceneLinear(mmPerPx: mmPerPx, centerPx: const Pt(64.5, 64.5)),
        scene: scene,
        supersample: ss,
        quantize8bit: false,
      );
      // At the arc apex (t = 0) the normal is the y axis (direction 0 deg).
      expect(eff(img, 0), closeTo(w, mmPerPx / ss + 1e-6));
    });

    test('strongly curved crack (R = 2 mm): nominal width along the local normal off the apex', () {
      // Arc through the origin, centre of curvature (0, R). At angle a from the apex
      // the centreline point is (R sin a, R (1 - cos a)) and the local normal has
      // direction angle a (the radial line through the centre of curvature).
      const w = 0.1, r = 2.0, alpha = 0.25;
      final img = renderGray(
        width: 130,
        height: 130,
        toScene: pixelToSceneLinear(mmPerPx: mmPerPx, centerPx: const Pt(64.5, 64.5)),
        scene: crackScene(widthMm: w, depth: depth, curvaturePerMm: 1 / r, background: bg),
        supersample: ss,
        quantize8bit: false,
      );
      final p = Pt(64.5 + r * sin(alpha) / mmPerPx, 64.5 + r * (1 - cos(alpha)) / mmPerPx);
      final e = effectiveWidthMm(
        img,
        mmPerPx: mmPerPx,
        directionDeg: alpha * 180 / pi,
        background: bg,
        depth: depth,
        halfRangeMm: 0.3,
        centerPx: p,
      );
      expect(e, closeTo(w, mmPerPx / ss + 1e-6));
      // Measuring along the wrong (apex) normal would overestimate by 1/cos(a).
      final wrong = effectiveWidthMm(img,
          mmPerPx: mmPerPx, directionDeg: 0, background: bg, depth: depth, halfRangeMm: 0.3, centerPx: p);
      expect(wrong, closeTo(w / cos(alpha), 0.01 * w));
    });

    test('negative curvature bends to the other side', () {
      final pos = crackScene(widthMm: 0.2, curvaturePerMm: 1 / 20);
      final neg = crackScene(widthMm: 0.2, curvaturePerMm: -1 / 20);
      // At t = 3 mm the centreline is offset by 3^2/(2*20) = 0.225 mm to +y or -y.
      expect(pos(3, 0.225), lessThan(0.5)); // dark (inside the crack)
      expect(pos(3, -0.225), greaterThan(0.7));
      expect(neg(3, -0.225), lessThan(0.5));
      expect(neg(3, 0.225), greaterThan(0.7));
    });

    test('crack centre point can be moved', () {
      final s = crackScene(widthMm: 0.3, centerMm: const Pt(5, 5), directionDeg: 0);
      expect(s(0, 5), lessThan(0.5));
      expect(s(0, 0), greaterThan(0.7));
    });
  });

  group('renderer validation: sheet', () {
    test('fronto-parallel marker area equals 4 x 30 mm squares', () {
      const mmPerPx = 0.25;
      final cam = SyntheticCamera(image: const ImageSize(800, 800), fPx: 4000, distanceMm: mmPerPx * 4000);
      final img = renderGray(
        width: 800,
        height: 800,
        toScene: (x, y) => cam.unproject(Pt(x, y)),
        scene: sheetScene(sheetId: 0, paper: 1.0, ink: 0.0),
        supersample: 4,
        quantize8bit: false,
      );
      var dark = 0.0;
      for (final v in img.data) {
        dark += 1 - v;
      }
      // Expected black area in px: 4 * 900 mm^2 / (0.25 mm)^2 = 57600. Quadrature
      // bound per edge 0.5/S px over 4 markers * 4 edges * 120 px = 1920 px of edge
      // length: <= 240 px, i.e. 0.42 percent; observed is far smaller, allow 0.5 percent.
      expect(dark, closeTo(57600, 0.005 * 57600));
    });

    test('tilted sheet: rendered marker area equals the projected polygon area', () {
      final cam = SyntheticCamera(
        image: const ImageSize(900, 700),
        fPx: 3600,
        distanceMm: 0.25 * 3600,
        tiltDeg: 30,
        tiltAzimuthDeg: 20,
        rollDeg: 10,
      );
      final img = renderGray(
        width: 900,
        height: 700,
        toScene: (x, y) => cam.unproject(Pt(x, y)),
        scene: sheetScene(sheetId: 3, paper: 1.0, ink: 0.0),
        supersample: 4,
        quantize8bit: false,
      );
      var dark = 0.0;
      for (final v in img.data) {
        dark += 1 - v;
      }
      var expected = 0.0;
      for (final id in markerIdsForSheet(3)) {
        final q = markerCornersMm(id).map(cam.project).toList();
        var twice = 0.0;
        for (var i = 0; i < 4; i++) {
          twice += q[i].x * q[(i + 1) % 4].y - q[(i + 1) % 4].x * q[i].y;
        }
        expected += twice.abs() / 2;
      }
      expect(dark, closeTo(expected, 0.005 * expected));
    });

    test('print scale shrinks the markers', () {
      final s1 = sheetScene(sheetId: 0, paper: 1.0, ink: 0.0);
      final s9 = sheetScene(sheetId: 0, printScale: 0.9, paper: 1.0, ink: 0.0);
      // Point at 74 mm inside marker 2 (TR is id 1: centre (60,-60), spans 45..75).
      expect(s1(74, -60), 0.0);
      expect(s9(74, -60), 1.0); // 0.9 scale: marker spans 40.5..67.5
      expect(s9(66, -54), 0.0);
    });

    test('white window: nothing is drawn between the markers', () {
      final s = sheetScene(sheetId: 0, paper: 0.9, ink: 0.05);
      expect(s(0, 0), 0.9);
      expect(s(-35, 35), 0.9);
      expect(s(-60, -60), 0.05);
    });
  });
}

/// erf via Abramowitz-Stegun 7.1.26 would be too coarse (1.5e-7 is fine here).
double _erf(double x) {
  final s = x < 0 ? -1.0 : 1.0;
  final ax = x.abs();
  final t = 1 / (1 + 0.3275911 * ax);
  final y = 1 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) *
          t *
          exp(-ax * ax);
  return s * y;
}
