// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

/// Sheet 0 seen at 0.2 mm/px (the whole 150 mm frame is ~800 px), blur and
/// camera as given. Markers are solid ink on paper 0.8.
final _cache = <String, GrayPatch>{};

/// Renders are the slow part (about 10 s each): identical requests are shared.
GrayPatch frame({
  double sigma = 1.0,
  double? sigmaY,
  double tilt = 0,
  double roll = 0,
  double noise = 0,
  double printScale = 1,
  int seed = 1,
  Scene? override,
}) {
  if (override != null) return _render(sigma, sigmaY, tilt, roll, noise, printScale, seed, override);
  return _cache.putIfAbsent(
    '$sigma/$sigmaY/$tilt/$roll/$noise/$printScale/$seed',
    () => _render(sigma, sigmaY, tilt, roll, noise, printScale, seed, null),
  );
}

GrayPatch _render(double sigma, double? sigmaY, double tilt, double roll, double noise, double printScale, int seed, Scene? override) {
  final cam = SyntheticCamera(
    image: const ImageSize(4000, 3000),
    fPx: 3000,
    distanceMm: 600, // 0.2 mm/px at the centre
    tiltDeg: tilt,
    tiltAzimuthDeg: 30,
    rollDeg: roll,
  );
  return renderCrackPatch(
    camera: cam,
    scene: override ?? sheetScene(sheetId: 0, printScale: printScale, paper: 0.8),
    halfSizeMm: 85,
    supersample: 2,
    psfSigmaPx: sigma,
    psfSigmaYPx: sigmaY,
    noiseSigma: noise,
    rng: Random(seed),
  );
}

Mat3 camH({double tilt = 0, double roll = 0}) => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 600,
      tiltDeg: tilt,
      tiltAzimuthDeg: 30,
      rollDeg: roll,
    ).h;

void main() {
  group('edge step response fit', () {
    test('recovers sigma and edge location from an ideal erf profile', () {
      const sigmaMm = 0.13, s0 = 0.02, a = 0.1, b = 0.7;
      final n = 201;
      final values = [for (var i = 0; i < n; i++) a + b * normalCdf((-1 + 2 * i / (n - 1) - s0) / sigmaMm)];
      final fit = fitEdgeProfile(MetricProfile(s0: -1, ds: 2 / (n - 1), values: Float64List.fromList(values)), sigmaGuessMm: 0.2)!;
      // Noise-free: solver tolerance only.
      expect(fit.sigmaMm, closeTo(sigmaMm, 1e-7));
      expect(fit.edgeMm, closeTo(s0, 1e-7));
      expect(fit.low, closeTo(a, 1e-7));
      expect(fit.step, closeTo(b, 1e-7));
    });

    test('a flat profile (no edge) is rejected', () {
      final fit = fitEdgeProfile(
        MetricProfile(s0: -1, ds: 0.01, values: Float64List.fromList(List<double>.filled(201, 0.5))),
        sigmaGuessMm: 0.2,
      );
      expect(fit, isNull);
    });
  });

  group('sigma from marker edges (5.3a), SINTETIS', () {
    // Expected apparent sigma: the renderer applies the Gaussian PSF, then integrates
    // over the pixel (box of 1 px, variance 1/12 px^2). The crack seen through the
    // same chain has the same kernel, so the apparent sigma is the right one to use
    // and equals sqrt(sigma^2 + 1/12). Remaining differences: the box is not Gaussian
    // and Catmull-Rom smooths slightly; measured below, tolerance 0.04 px + 3 percent.
    for (final sigma in [0.6, 1.0, 1.5, 2.0]) {
      test('generator sigma $sigma px (tilt 0, noise 0.005)', () {
        final p = frame(sigma: sigma, noise: 0.005);
        final est = estimatePsf(patch: p, h: camH(), sheetId: 0);
        final expected = sqrt(sigma * sigma + 1 / 12);
        expect(est.edges.length, 8);
        expect(est.sigmaPx, closeTo(expected, 0.04 + 0.03 * expected));
        // sigma in mm uses 0.2 mm/px at tilt 0.
        expect(est.sigmaMm, closeTo(est.sigmaPx * 0.2, 0.02 * est.sigmaMm));
        expect(est.anisotropy, closeTo(1, 0.08));
        expect(est.uSigmaPx, lessThan(0.05 * expected));
      });
    }

    test('tilt 25 deg and roll 15 deg: sigma in px is unchanged, mm differs by direction', () {
      final h = camH(tilt: 25, roll: 15);
      final p = frame(sigma: 1.0, tilt: 25, roll: 15, noise: 0.005);
      final est = estimatePsf(patch: p, h: h, sheetId: 0);
      final expected = sqrt(1 + 1 / 12);
      expect(est.sigmaPx, closeTo(expected, 0.04 + 0.03 * expected));
      expect(est.anisotropy, closeTo(1, 0.1)); // isotropic blur must not look like motion
      final mmX = est.sigmaMmAlong(h, const Pt(0, 0), 0).sigmaMm;
      final mmY = est.sigmaMmAlong(h, const Pt(0, 0), 90).sigmaMm;
      expect(max(mmX, mmY) / min(mmX, mmY), greaterThan(1.03)); // foreshortening is real
    });

    test('print scale 1.02 is honoured (edges are located at scaled positions)', () {
      final p = frame(sigma: 1.0, printScale: 1.02, noise: 0.005);
      final est = estimatePsf(patch: p, h: camH(), sheetId: 0, printScale: 1.02);
      expect(est.edges.length, 8);
      expect(est.sigmaPx, closeTo(sqrt(1 + 1 / 12), 0.07));
    });

    test('three markers give 6 edges', () {
      final p = frame(sigma: 1.0, noise: 0.005);
      final est = estimatePsf(patch: p, h: camH(), sheetId: 0, markerIds: const [0, 1, 2]);
      expect(est.edges.length, 6);
    });

    test('u_sigma_edge grows when one edge disagrees', () {
      // Marker 0 blurred more than the rest: build the frame from two renders.
      final good = frame(sigma: 1.0, noise: 0.005);
      final est0 = estimatePsf(patch: good, h: camH(), sheetId: 0);
      final bad = frame(sigma: 1.0, noise: 0.005, override: (x, y) {
        // Smear marker 0 (top-left) outer edges with a soft ramp instead of a step.
        final m = sheetScene(sheetId: 0, paper: 0.8)(x, y);
        if (x < -45 && y < -45) {
          const ramp = 1.2;
          final dx = (x + 75) / ramp, dy = (y + 75) / ramp;
          final f = min(1.0, max(0.0, min(dx, dy)));
          return 0.8 + (0.05 - 0.8) * f;
        }
        return m;
      });
      final est1 = estimatePsf(patch: bad, h: camH(), sheetId: 0);
      expect(est1.uSigmaPx, greaterThan(3 * est0.uSigmaPx));
      // The median is robust to one bad marker (2 of 8 edges).
      expect(est1.sigmaPx, closeTo(est0.sigmaPx, 0.1));
    });
  });

  group('anisotropic blur (hand motion)', () {
    test('sigma 1 along x, 2 along y: ratio detected, near the analytic value', () {
      final p = frame(sigma: 1.0, sigmaY: 2.0, noise: 0.005);
      final est = estimatePsf(patch: p, h: camH(), sheetId: 0);
      final analytic = sqrt((4 + 1 / 12) / (1 + 1 / 12));
      expect(est.anisotropy, closeTo(analytic, 0.15));
      expect(est.anisotropy, greaterThan(QualityThresholds.standard.maxBlurAnisotropy));
    });

    test('KNOWN LIMIT: the same blur seen with the sheet rotated 45 deg is NOT detected', () {
      // Both edge families make 45 deg with the blur axes and see the same sigma.
      final p = frame(sigma: 1.0, sigmaY: 2.0, roll: 45, noise: 0.005);
      final est = estimatePsf(patch: p, h: camH(roll: 45), sheetId: 0);
      expect(est.anisotropy, lessThan(1.15));
      // ...but the larger apparent sigma is still visible: sqrt((1+4)/2 + 1/12).
      expect(est.sigmaPx, closeTo(sqrt(2.5 + 1 / 12), 0.15));
    });
  });

  group('failures', () {
    test('patch without markers: no edges available', () {
      final p = frame(sigma: 1.0, override: (x, y) => 0.8);
      expect(
        () => estimatePsf(patch: p, h: camH(), sheetId: 0),
        throwsA(isA<MeasurementException>().having((e) => e.reason, 'reason', RejectReason.psfEdgesUnavailable)),
      );
    });

    test('a patch that does not reach the markers: no edges available', () {
      final cam = SyntheticCamera(image: const ImageSize(4000, 3000), fPx: 3000, distanceMm: 600);
      final small = renderCrackPatch(camera: cam, scene: sheetScene(sheetId: 0, paper: 0.8), halfSizeMm: 20, psfSigmaPx: 1);
      expect(
        () => estimatePsf(patch: small, h: cam.h, sheetId: 0),
        throwsA(isA<MeasurementException>()),
      );
    });

    test('unknown sheet id or a single marker is rejected', () {
      final p = frame(sigma: 1.0);
      expect(() => estimatePsf(patch: p, h: camH(), sheetId: 99), throwsRangeError);
      expect(
        () => estimatePsf(patch: p, h: camH(), sheetId: 0, markerIds: const [0]),
        throwsA(isA<MeasurementException>()),
      );
    });
  });
}
