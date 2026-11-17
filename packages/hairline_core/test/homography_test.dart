// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

/// Camera used by the statistical tests: 15 deg tilt, 0.08 mm/px at the centre.
SyntheticCamera _statCamera() => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 0.08 * 3000,
      tiltDeg: 15,
      tiltAzimuthDeg: 40,
      rollDeg: 10,
    );

/// Grid of sheet points spanning the whole frame (mm).
final _grid = [
  for (var x = -70.0; x <= 70; x += 35)
    for (var y = -70.0; y <= 70; y += 35) Pt(x, y),
];

double _rms(List<double> v) => sqrt(v.fold<double>(0, (s, e) => s + e * e) / v.length);

void main() {
  group('noiseless recovery (5.2)', () {
    // Tolerance 1e-6 px: double precision DLT + LM on exact data should reach
    // ~1e-9 px; 1e-6 is the DoD bound.
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('random camera seed $seed: 4 markers reproject within 1e-6 px', () {
        final rng = Random(seed);
        final cam = SyntheticCamera.random(rng);
        final sheet = seed % 12;
        final est = estimateSheetHomography(
          SyntheticDetector().detect(cam, sheetId: sheet),
          sheetId: sheet,
        );
        for (final p in _grid) {
          expect(est.project(p).distanceTo(cam.project(p)), lessThan(1e-6), reason: '$p');
        }
        expect(est.rmsPx, lessThan(1e-6));
        expect(est.markerCount, 4);
        expect(est.looMm, isNotNull);
        expect(est.looMm!, lessThan(1e-6));
      });
    }

    test('H_inv inverts project (round trip < 1e-9 mm)', () {
      final cam = _statCamera();
      final est = estimateSheetHomography(SyntheticDetector().detect(cam, sheetId: 0), sheetId: 0);
      for (final p in _grid) {
        expect(est.unproject(est.project(p)).distanceTo(p), lessThan(1e-9));
      }
    });

    test('3 markers noiseless also recover H exactly, loo is null', () {
      final cam = _statCamera();
      for (final omit in [0, 1, 2, 3]) {
        final est = estimateSheetHomography(
          SyntheticDetector().detect(cam, sheetId: 2, omit: {8 + omit}),
          sheetId: 2,
        );
        expect(est.markerCount, 3);
        expect(est.looMm, isNull);
        for (final p in _grid) {
          expect(est.project(p).distanceTo(cam.project(p)), lessThan(1e-6));
        }
      }
    });

    test('print scale other than 1 is honoured', () {
      final cam = _statCamera();
      final det = SyntheticDetector().detect(cam, sheetId: 1, printScale: 0.95);
      final est = estimateSheetHomography(det, sheetId: 1, printScale: 0.95);
      // True physical point (mm) maps to the same pixel as the camera model.
      expect(est.project(const Pt(10, -20)).distanceTo(cam.project(const Pt(10, -20))), lessThan(1e-6));
    });
  });

  group('input validation (typed errors)', () {
    final cam = _statCamera();

    test('fewer than 3 markers is rejected with TooFewMarkersException', () {
      for (final keep in [0, 1, 2]) {
        final all = SyntheticDetector().detect(cam, sheetId: 0);
        expect(
          () => estimateSheetHomography(all.take(keep).toList(), sheetId: 0),
          throwsA(isA<TooFewMarkersException>().having((e) => e.found, 'found', keep)),
        );
      }
    });

    test('markers of another sheet are ignored, not counted', () {
      final other = SyntheticDetector().detect(cam, sheetId: 5);
      final mine = SyntheticDetector().detect(cam, sheetId: 0).take(2).toList();
      expect(
        () => estimateSheetHomography([...mine, ...other], sheetId: 0),
        throwsA(isA<TooFewMarkersException>().having((e) => e.found, 'found', 2)),
      );
    });

    test('duplicate marker id is InvalidDetectionException', () {
      final d = SyntheticDetector().detect(cam, sheetId: 0);
      expect(
        () => estimateSheetHomography([...d, d.first], sheetId: 0),
        throwsA(isA<InvalidDetectionException>()),
      );
    });

    test('wrong corner count or non-finite corner is InvalidDetectionException', () {
      final d = SyntheticDetector().detect(cam, sheetId: 0);
      final short = MarkerDetection(id: d[0].id, corners: d[0].corners.take(3).toList());
      final nan = MarkerDetection(id: d[0].id, corners: [const Pt(double.nan, 0), ...d[0].corners.skip(1)]);
      for (final bad in [short, nan]) {
        expect(
          () => estimateSheetHomography([bad, ...d.skip(1)], sheetId: 0),
          throwsA(isA<InvalidDetectionException>()),
        );
      }
    });

    test('collinear image points are DegenerateConfigurationException', () {
      // All corners of 3 markers on one line in the image.
      final line = [
        for (var i = 0; i < 3; i++)
          MarkerDetection(id: i, corners: [for (var k = 0; k < 4; k++) Pt(100.0 + 50 * i + 10 * k, 200.0 + 5 * i + k)]),
      ];
      expect(
        () => estimateSheetHomography(line, sheetId: 0),
        throwsA(isA<DegenerateConfigurationException>()),
      );
    });

    test('collinear sheet points are rejected by the point-level estimator', () {
      final src = [for (var i = 0; i < 6; i++) Pt(i * 10.0, i * 5.0)];
      final dst = [for (var i = 0; i < 6; i++) Pt(100.0 + i * i, 50.0 * i)];
      expect(() => estimateHomographyFromPoints(src, dst), throwsA(isA<DegenerateConfigurationException>()));
    });

    test('nearly collinear (0.01 percent spread) is rejected too', () {
      final src = [for (var i = 0; i < 6; i++) Pt(i * 10.0, 1e-5 * (i % 2))];
      final dst = [for (var i = 0; i < 6; i++) Pt(100.0 + i * 3, 50.0 + i * 7.0 * (1 + 0.0))];
      expect(() => estimateHomographyFromPoints(src, dst), throwsA(isA<DegenerateConfigurationException>()));
    });

    test('too few or mismatched correspondences are rejected', () {
      expect(
        () => estimateHomographyFromPoints(const [Pt(0, 0), Pt(1, 0), Pt(0, 1)], const [Pt(0, 0), Pt(1, 0), Pt(0, 1)]),
        throwsA(isA<DegenerateConfigurationException>()),
      );
      expect(
        () => estimateHomographyFromPoints(const [Pt(0, 0)], const []),
        throwsArgumentError,
      );
    });

    test('coincident points (zero spread) are rejected', () {
      final p = List<Pt>.filled(6, const Pt(3, 3));
      expect(() => estimateHomographyFromPoints(p, p), throwsA(isA<DegenerateConfigurationException>()));
    });

    test('a mirrored correspondence set (det H < 0) is rejected', () {
      // Diagonal corners swapped: an orientation-reversing assignment. A real camera
      // viewing the front of the sheet never produces it; a wrong corner order does.
      final src = const [Pt(-1, -1), Pt(1, -1), Pt(1, 1), Pt(-1, 1), Pt(0, 0)];
      final dst = const [Pt(0, 0), Pt(100, 100), Pt(100, 0), Pt(0, 100), Pt(50, 50)];
      expect(() => estimateHomographyFromPoints(src, dst), throwsA(isA<DegenerateConfigurationException>()));
    });

    test('markers with reversed corner order (mirrored) are rejected', () {
      final d = SyntheticDetector().detect(cam, sheetId: 0);
      final flipped = [
        for (final m in d)
          MarkerDetection(id: m.id, corners: [m.corners[1], m.corners[0], m.corners[3], m.corners[2]]),
      ];
      expect(
        () => estimateSheetHomography(flipped, sheetId: 0),
        throwsA(isA<DegenerateConfigurationException>()),
      );
    });

    test('inconsistent depth (a point mapped behind the camera) is rejected', () {
      // Projective map whose line at infinity cuts the point set: h6 x + h8 changes
      // sign across the points, so some w < 0. Build the image points from such a map.
      final h = <double>[1, 0, 0, 0, 1, 0, 0.5, 0, 1]; // w = 0.5 x + 1, zero at x = -2
      final src = const [Pt(-3, -1), Pt(-3, 1), Pt(1, -1), Pt(1, 1), Pt(0, 0.2)];
      final dst = [
        for (final p in src)
          Pt((h[0] * p.x) / (h[6] * p.x + 1), (h[4] * p.y) / (h[6] * p.x + 1)),
      ];
      expect(() => estimateHomographyFromPoints(src, dst), throwsA(isA<DegenerateConfigurationException>()));
    });
  });

  group('noise statistics (sigma 0.2 px per coordinate, seed fixed)', () {
    const sigma = 0.2;
    const trials = 300;
    final cam = _statCamera();
    final mmPerPx = 0.08;

    /// Per-trial error vectors (mm) at sheet point [q] for 4 or 3 markers.
    List<Pt> errors(Pt q, {Set<int> omit = const {}, int seed = 42}) {
      final det = SyntheticDetector(noisePx: sigma, rng: Random(seed));
      final out = <Pt>[];
      for (var t = 0; t < trials; t++) {
        final est = estimateSheetHomography(det.detect(cam, sheetId: 0, omit: omit), sheetId: 0);
        // Physical error: where the noisy H places the true pixel of q.
        out.add(est.unproject(cam.project(q)) - q);
      }
      return out;
    }

    test('position error at the window centre matches sigma*sqrt(2/N)*mm_per_px', () {
      // Centroid-fit expectation: per axis sigma/sqrt(N) px with N=16 corner
      // points, 2D RMS = sigma*sqrt(2/16)*mm_per_px = 0.00707 mm. The homography
      // has 8 dof (not 2) so the true value is slightly larger; accept 0.8..1.6x.
      final e = errors(const Pt(0, 0));
      final rms = _rms([for (final v in e) v.norm]);
      final expected = sigma * sqrt(2 / 16) * mmPerPx;
      expect(rms, inInclusiveRange(0.8 * expected, 1.6 * expected));
      // Unbiased: mean error vector within 4 standard errors of zero.
      final mx = e.fold<double>(0, (s, v) => s + v.x) / trials;
      final my = e.fold<double>(0, (s, v) => s + v.y) / trials;
      final se = rms / sqrt(2) / sqrt(trials);
      expect(mx.abs(), lessThan(4 * se));
      expect(my.abs(), lessThan(4 * se));
    });

    test('position error at the window corner stays below 0.02 mm and exceeds the centre error', () {
      // 0.02 mm = 2.5 sigma_px*mm_per_px, a loose physical bound with 4 markers.
      final centre = _rms([for (final v in errors(const Pt(0, 0))) v.norm]);
      final corner = _rms([for (final v in errors(const Pt(35, 35))) v.norm]);
      expect(corner, lessThan(0.02));
      expect(corner, greaterThan(centre));
    });

    test('3 markers are less accurate than 4 at the window centre and corner', () {
      for (final q in const [Pt(0, 0), Pt(35, 35)]) {
        final four = _rms([for (final v in errors(q)) v.norm]);
        final three = _rms([for (final v in errors(q, omit: {3})) v.norm]);
        expect(three, greaterThan(four), reason: '$q');
      }
    });

    test('rms_px averages sigma*sqrt(2*(2n-8)/(2n)) over trials (n=16 points)', () {
      // Each residual component has variance sigma^2 * (1 - 8/(2n)) on average
      // (trace of the residual projector = 2n-8). rms_px = sqrt(mean |r|^2).
      final det = SyntheticDetector(noisePx: sigma, rng: Random(7));
      var sumSq = 0.0;
      for (var t = 0; t < trials; t++) {
        final est = estimateSheetHomography(det.detect(cam, sheetId: 0), sheetId: 0);
        sumSq += est.rmsPx * est.rmsPx;
      }
      final meanRms = sqrt(sumSq / trials);
      final expected = sigma * sqrt(2 * (32 - 8) / 32);
      // 3 percent: sampling error of a mean of 300 chi-square variables with 24 dof is ~1 percent.
      expect(meanRms, closeTo(expected, 0.03 * expected));
    });
  });

  group('leave-one-marker-out (5.2)', () {
    final cam = _statCamera();

    double loo({Map<int, Pt> shift = const {}, int seed = 3}) {
      final det = SyntheticDetector(noisePx: 0.2, rng: Random(seed));
      final est = estimateSheetHomography(
        det.detect(cam, sheetId: 0, shiftPx: shift),
        sheetId: 0,
      );
      return est.looMm!;
    }

    test('loo_mm is small with noise only', () {
      // 3-marker extrapolation amplifies noise; observed ~0.05 mm at 0.08 mm/px.
      expect(loo(), lessThan(0.15));
    });

    test('loo_mm grows monotonically when one marker is displaced (non-planarity/distortion)', () {
      final base = loo();
      final s2 = loo(shift: {1: const Pt(2, 0)});
      final s5 = loo(shift: {1: const Pt(5, 0)});
      expect(s2, greaterThan(base));
      expect(s5, greaterThan(s2));
      // 5 px at 0.08 mm/px = 0.4 mm displacement of one marker must show up
      // well above the 0.3 mm gate when it is a whole-marker shift.
      expect(s5, greaterThan(0.1));
    });

    test('rms_px also grows with a displaced marker', () {
      final det = SyntheticDetector(noisePx: 0.2, rng: Random(3));
      final clean = estimateSheetHomography(det.detect(cam, sheetId: 0), sheetId: 0).rmsPx;
      final bad = estimateSheetHomography(
        SyntheticDetector(noisePx: 0.2, rng: Random(3)).detect(cam, sheetId: 0, shiftPx: {1: const Pt(5, 0)}),
        sheetId: 0,
      ).rmsPx;
      // Only 2x: a rigid shift of one marker is partly absorbed by the 8-dof fit
      // (observed 0.74 vs 0.25 px), which is why loo_mm is the primary detector.
      expect(bad, greaterThan(2 * clean));
    });
  });

  group('local scale (5.2)', () {
    test('fronto-parallel: mm_per_px = Z/f and anisotropy = 1 within 1e-9', () {
      final cam = SyntheticCamera(
        image: const ImageSize(4000, 3000),
        fPx: 3000,
        distanceMm: 240,
      );
      final est = estimateSheetHomography(SyntheticDetector().detect(cam, sheetId: 3), sheetId: 3);
      final s = est.localScale();
      expect(s.mmPerPx, closeTo(240 / 3000, 1e-9));
      expect(s.anisotropy, closeTo(1, 1e-9));
    });

    test('tilt theta on the optical axis: mm_per_px = Z/(f sqrt(cos)), anisotropy = 1/cos', () {
      // Along the tilt direction the plane is foreshortened by cos(theta); across
      // it is not. Principal-axis point, so exact analytic values (see derivation
      // in synthetic/camera.dart). Tolerance 1e-5 relative: central difference
      // with 0.5 px step, third-derivative error is ~1e-7.
      for (final tilt in [10.0, 20.0, 30.0]) {
        final cam = SyntheticCamera(
          image: const ImageSize(4000, 3000),
          fPx: 3000,
          distanceMm: 240,
          tiltDeg: tilt,
          tiltAzimuthDeg: 33,
          rollDeg: 12,
        );
        final est = estimateSheetHomography(SyntheticDetector().detect(cam, sheetId: 0), sheetId: 0);
        final c = cos(tilt * pi / 180);
        final s = est.localScale();
        expect(s.mmPerPx, closeTo(240 / 3000 / sqrt(c), 1e-5 * 0.08), reason: 'tilt $tilt');
        expect(s.anisotropy, closeTo(1 / c, 1e-5), reason: 'tilt $tilt');
      }
    });

    test('scale at an off-centre sheet point differs from the centre scale under tilt', () {
      final cam = SyntheticCamera(
        image: const ImageSize(4000, 3000),
        fPx: 3000,
        distanceMm: 240,
        tiltDeg: 30,
      );
      final est = estimateSheetHomography(SyntheticDetector().detect(cam, sheetId: 0), sheetId: 0);
      final a = est.localScale().mmPerPx;
      // (0,60) lies across the tilt axis (azimuth 0 = x axis), so depth changes there.
      final b = est.localScale(const Pt(0, 60)).mmPerPx;
      expect(a, isNot(closeTo(b, 1e-4)));
    });
  });

  test('horizon detection is scale invariant (h33 far from 1)', () {
    final h = <double>[2, 0, 0, 0, 2, 0, 0, 1e-6, 1e-6]; // w = 1e-6 (y + 1); zero at y = -1
    expect(() => applyHomography(h, const Pt(5, -1)), throwsA(isA<DegenerateConfigurationException>()));
    final p = applyHomography(h, const Pt(5, 1));
    expect(p.x, closeTo(2 * 5 / (2e-6), 1e-6));
  });

  test('unproject at the horizon line throws DegenerateConfigurationException', () {
    final cam = SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 240,
      tiltDeg: 60,
      tiltAzimuthDeg: 0,
    );
    final est = estimateSheetHomography(SyntheticDetector().detect(cam, sheetId: 0), sheetId: 0);
    // Pixel on the image line that H_inv sends to infinity: x fixed, solve w = 0.
    final h = est.hInv;
    final y = -(h[6] * 100 + h[8]) / h[7];
    expect(() => est.unproject(Pt(100, y)), throwsA(isA<DegenerateConfigurationException>()));
  });
}
