// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

/// Width of the crack at abscissa [x] by scanning y at 0.001 mm.
double widthAt(Scene scene, double x, {double dark = 0.5}) {
  var n = 0;
  for (var i = -3000; i <= 3000; i++) {
    if (scene(x, i * 0.001) < dark) n++;
  }
  return n * 0.001;
}

void main() {
  group('roughEdgeCrackScene', () {
    test('amplitude 0 is the plain crack, mean width equals nominal', () {
      final r = roughEdgeCrackScene(widthMm: 0.5, amplitudeMm: 0);
      expect(r.meanWidthMm, closeTo(0.5, 1e-12));
      expect(widthAt(r.scene, 0.7), closeTo(0.5, 0.0015));
    });

    test('the reported mean width is the integral of the local width over 4 mm', () {
      final r = roughEdgeCrackScene(amplitudeMm: 0.15);
      final xs = [for (var i = 0; i < 200; i++) -2 + 4 * (i + 0.5) / 200];
      final scanned = xs.map((x) => widthAt(r.scene, x)).reduce((a, b) => a + b) / xs.length;
      // Quadrature of 200 stations of a width that varies on a 0.7 mm scale: 3 um.
      expect(r.meanWidthMm, closeTo(scanned, 0.003));
      // The local width does wander: more than +-0.1 mm around the mean for amplitude 0.15.
      final spread = xs.map((x) => widthAt(r.scene, x)).reduce(max) - xs.map((x) => widthAt(r.scene, x)).reduce(min);
      expect(spread, greaterThan(0.1));
    });

    test('same seed, same crack', () {
      expect(roughEdgeCrackScene(amplitudeMm: 0.1).meanWidthMm, roughEdgeCrackScene(amplitudeMm: 0.1).meanWidthMm);
    });
  });

  test('rotatedAboutOrigin turns a horizontal crack into one along the given direction', () {
    final s = rotatedAboutOrigin(crackScene(widthMm: 0.4, directionDeg: 0), 30);
    // A point on the 30 degree line through the origin is inside the crack; its normal offsets are not.
    final a = 30 * pi / 180;
    expect(s(2 * cos(a), 2 * sin(a)), lessThan(0.5)); // dark
    expect(s(2 * cos(a) - 0.3 * sin(a), 2 * sin(a) + 0.3 * cos(a)), closeTo(0.8, 1e-12)); // 0.3 mm off the line: background
    expect(s(2 * cos(a) - 0.15 * sin(a), 2 * sin(a) + 0.15 * cos(a)), lessThan(0.5)); // 0.15 mm off: still inside (half width 0.2)
  });

  test('withOneSidedShadow scales only y > 0', () {
    final s = withOneSidedShadow((x, y) => 0.8, 0.5);
    expect(s(1, -0.1), 0.8);
    expect(s(1, 0.1), closeTo(0.4, 1e-15));
  });

  test('withStain darkens by the amplitude at its centre and fades with distance', () {
    final s = withStain((x, y) => 0.8, 0.25, cx: 1, cy: 2);
    expect(s(1, 2), closeTo(0.8 * 0.75, 1e-15));
    expect(s(1 + 0.4, 2), closeTo(0.8 * (1 - 0.25 * exp(-0.5)), 1e-15));
    expect(s(10, 10), closeTo(0.8, 1e-12));
  });

  test('renderCrackPatch places the patch at the projected origin and is deterministic', () {
    final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 180, tiltDeg: 20, rollDeg: 10);
    GrayPatch make() => renderCrackPatch(
          camera: cam,
          scene: crackScene(widthMm: 0.5, directionDeg: 20),
          halfSizeMm: 5,
          noiseSigma: 0.01,
          rng: Random(4),
        );
    final a = make(), b = make();
    expect(a.data, b.data);
    // The sheet origin projects inside the patch, near its middle.
    final c = cam.project(const Pt(0, 0));
    expect(c.x - a.originX, inInclusiveRange(a.width * 0.4, a.width * 0.6));
    expect(c.y - a.originY, inInclusiveRange(a.height * 0.4, a.height * 0.6));
    // The darkest pixel of the centre column lies on the crack.
    expect(a.sampleCubic(c.x, c.y), lessThan(0.6));
  });

  test('anisotropic PSF blurs along one image axis only', () {
    // Vertical step edge, blur only along x: the edge widens; a horizontal edge is not affected.
    double spread(Scene scene, bool alongX) {
      final img = renderGray(
        width: 40,
        height: 40,
        toScene: pixelToSceneLinear(mmPerPx: 1, centerPx: const Pt(19.5, 19.5)),
        scene: scene,
        psfSigmaPx: 2.0,
        psfSigmaYPx: 0.0,
        quantize8bit: false,
      );
      // Transition width: count pixels with value strictly between 0.05 and 0.95.
      var n = 0;
      for (var k = 0; k < 40; k++) {
        final v = alongX ? img.at(k, 20) : img.at(20, k);
        if (v > 0.05 && v < 0.95) n++;
      }
      return n.toDouble();
    }

    final vertical = spread((x, y) => x < 0 ? 0.0 : 1.0, true);
    final horizontal = spread((x, y) => y < 0 ? 0.0 : 1.0, false);
    expect(vertical, greaterThan(5)); // sigma 2 px: 5 to 95 percent spans about 6.6 px
    expect(horizontal, lessThanOrEqualTo(1)); // no blur along y: a sharp (sampled) edge
  });
}
