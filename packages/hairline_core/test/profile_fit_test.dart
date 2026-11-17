// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

const double mmPerPx = 0.06;

SyntheticCamera cam({double tilt = 0, double roll = 0}) => SyntheticCamera(
      image: const ImageSize(4000, 3000),
      fPx: 3000,
      distanceMm: 180,
      tiltDeg: tilt,
      tiltAzimuthDeg: 40,
      rollDeg: roll,
    );

/// Apparent kernel of the renderer for a Gaussian PSF of [sigmaPx]: the pixel
/// aperture adds 1/12 px^2 (see psf.dart).
double apparentSigmaMm(double sigmaPx) => sqrt(sigmaPx * sigmaPx + 1 / 12) * mmPerPx;

final _cache = <String, GrayPatch>{};

/// Renders dominate the run time: identical parameter sets are shared (tests never
/// mutate patches).
GrayPatch patchOf({
  double w = 0.5,
  double dir = 20,
  double curv = 0,
  double sigma = 1.0,
  double noise = 0.002,
  double depth = 0.6,
  double tilt = 0,
  double roll = 0,
  int seed = 7,
  Scene? scene,
}) {
  GrayPatch render() => renderCrackPatch(
        camera: cam(tilt: tilt, roll: roll),
        scene: scene ?? crackScene(widthMm: w, depth: depth, directionDeg: dir, curvaturePerMm: curv),
        halfSizeMm: 8,
        supersample: 4,
        psfSigmaPx: sigma,
        noiseSigma: noise,
        rng: Random(seed),
      );
  return scene != null ? render() : _cache.putIfAbsent('$w/$dir/$curv/$sigma/$noise/$depth/$tilt/$roll/$seed', render);
}

ProfileFitResult fit(
  GrayPatch p, {
  double dir = 20,
  double sigmaPx = 1.0,
  double uSigmaPx = 0,
  double? sigmaMmOverride,
  double uSigmaMmOverride = 0,
  double tilt = 0,
  double roll = 0,
  ProfileFitConfig config = const ProfileFitConfig(),
  Pt point = const Pt(0, 0),
}) =>
    fitCrackWidth(
      patch: p,
      h: cam(tilt: tilt, roll: roll).h,
      pointMm: point,
      directionDeg: dir,
      sigmaMm: sigmaMmOverride ?? apparentSigmaMm(sigmaPx),
      uSigmaMm: uSigmaMmOverride > 0 ? uSigmaMmOverride : uSigmaPx * mmPerPx,
      config: config,
    );

void main() {
  group('defaults', () {
    test('rho is 1.0 and flagged as calibrated against the synthetic study (5.3, docs/SYNTHETIC_VALIDATION.md)', () {
      const c = ProfileFitConfig();
      expect(c.rho, 1.0);
      expect(c.rhoCalibrated, isTrue);
      expect(c.profiles, 40);
      expect(c.segmentMm, 4);
      expect(c.halfRangeMm, 3);
      expect(c.minContrastSnr, 3);
      final r = fit(patchOf());
      expect(r.rho, 1.0);
      expect(r.rhoCalibrated, isTrue);
    });
  });

  group('ideal case, 0.06 mm/px, tilt 0, sigma 1 px', () {
    for (final w in [0.3, 0.5, 1.0, 2.0]) {
      test('width $w mm: accurate, measurable, uncertainty small', () {
        final r = fit(patchOf(w: w));
        expect(r.status, FitStatus.terukur);
        // Tolerance from analysis: noise-free runs show a systematic error below 1 um
        // (Catmull-Rom smoothing, 8-bit quantisation, kernel shape; tool/measurement_sweep.dart);
        // statistical error is 3 u (u ~ 0.15 um here). 2 um + 3 u covers both with margin.
        expect(r.widthMm, closeTo(w, 0.002 + 3 * r.uWidthMm));
        expect(r.uWidthMm, lessThan(0.001));
        expect(r.goodProfiles, greaterThan(30));
        expect(r.centerOffsetMm.abs(), lessThan(0.05));
      });
    }
  });

  test('per-profile widths: median agrees with the final width, scatter is small and slope is nil', () {
    final r = fit(patchOf(w: 0.5));
    expect(r.widthsPerProfile.length, 40);
    expect(r.wMedian, closeTo(r.widthMm, 0.05));
    expect(r.alongSdMm, lessThan(0.05));
    expect(r.dwDs.abs(), lessThan(3 * r.dwDsSe + 0.01));
  });

  test('tapered crack: dw/ds is recovered and the width is the segment mean', () {
    // Half width varies linearly along the crack direction (x axis here).
    const k = 0.1; // dw/ds
    double scene(double x, double y) {
      final half = (0.6 + k * x) / 2;
      return y.abs() <= half ? 0.8 * 0.4 : 0.8;
    }

    final r = fit(patchOf(scene: scene, dir: 0), dir: 0);
    expect(r.dwDs, closeTo(k, 0.03));
    expect(r.widthMm, closeTo(0.6, 0.05));
  });

  group('contrast gate (D / sigma_noise >= 3)', () {
    test('a faint crack under noise is TIDAK_TERUKUR with a reason, no width', () {
      final r = fit(patchOf(w: 0.5, depth: 0.03, noise: 0.02));
      expect(r.status, FitStatus.tidakTerukur);
      expect(r.issue, FitIssue.lowContrast);
      expect(r.contrastSnr, lessThan(3));
    });

    test('no crack at all is TIDAK_TERUKUR', () {
      final r = fit(patchOf(scene: (x, y) => 0.8, noise: 0.01));
      expect(r.status, FitStatus.tidakTerukur);
    });

    test('the same crack with low noise passes the gate', () {
      final r = fit(patchOf(w: 0.5, depth: 0.03, noise: 0.0005));
      expect(r.status, FitStatus.terukur);
      expect(r.contrastSnr, greaterThan(3));
    });

    test('noiseFloor from the whole patch can only make the gate stricter', () {
      final p = patchOf(w: 0.5, depth: 0.1, noise: 0.002);
      final loose = fit(p);
      final strict = fitCrackWidth(
        patch: p,
        h: cam().h,
        pointMm: const Pt(0, 0),
        directionDeg: 20,
        sigmaMm: apparentSigmaMm(1),
        noiseFloor: 0.05,
      );
      expect(loose.status, FitStatus.terukur);
      expect(strict.status, FitStatus.tidakTerukur);
      expect(strict.sigmaNoise, greaterThanOrEqualTo(0.05));
    });
  });

  group('sub-pixel behaviour: the uncertainty must grow as w/sigma shrinks', () {
    // u_sigma = 5 percent of sigma: the scatter of the edge-based sigma (psf_test).
    List<double> medians(double w, double sigmaPx, {int seeds = 5}) {
      final cov = <double>[], total = <double>[];
      for (var s = 1; s <= seeds; s++) {
        final sg = apparentSigmaMm(sigmaPx);
        final r = fit(
          patchOf(w: w, sigma: sigmaPx, noise: 0.005, seed: s),
          sigmaPx: sigmaPx,
          uSigmaMmOverride: 0.05 * sg,
        );
        final u = r.uWidthMm.isFinite ? r.uWidthMm : double.infinity;
        cov.add(u);
        total.add(sqrt(u * u + r.uSigmaWMm * r.uSigmaWMm));
      }
      return [median(cov), median(total)];
    }

    test('fit covariance alone grows as w shrinks below ~2 sigma, and the total (with sigma) from 2 mm down', () {
      final ws = [2.0, 1.0, 0.5, 0.3, 0.2, 0.1, 0.05];
      final m = [for (final w in ws) medians(w, 1.0)];
      // Total: strictly increasing over the whole range.
      for (var i = 1; i < ws.length; i++) {
        expect(m[i][1], greaterThan(m[i - 1][1]), reason: 'total u: w=${ws[i]} ${m[i][1]} vs w=${ws[i - 1]} ${m[i - 1][1]}');
      }
      // Covariance alone is flat while the crack is wide (noise scatter of s2), then rises.
      for (var i = 3; i < ws.length; i++) {
        expect(m[i][0], greaterThan(m[i - 1][0]), reason: 'cov u: w=${ws[i]} ${m[i][0]} vs w=${ws[i - 1]} ${m[i - 1][0]}');
      }
      expect(m.last[0], greaterThan(8 * m[2][0])); // 0.05 mm vs 0.5 mm
      expect(m.last[1], greaterThan(50 * m.first[1])); // 0.05 mm vs 2 mm
    });

    test('total uncertainty grows as sigma grows (w fixed 0.3 mm)', () {
      final sigmas = [0.6, 1.0, 1.5, 2.0];
      final m = [for (final s in sigmas) medians(0.3, s)];
      for (var i = 1; i < sigmas.length; i++) {
        expect(m[i][1], greaterThan(m[i - 1][1]), reason: 'sigma=${sigmas[i]} ${m[i][1]} vs ${m[i - 1][1]}');
      }
    });

    test('no false precision: an estimate is covered by its total uncertainty and is never "tight"', () {
      for (final w in [0.1, 0.05]) {
        for (var s = 1; s <= 8; s++) {
          final sg = apparentSigmaMm(1);
          final r = fit(patchOf(w: w, noise: 0.005, seed: s), uSigmaMmOverride: 0.05 * sg);
          if (r.status == FitStatus.tidakTerukur) continue;
          final u = sqrt(r.uWidthMm * r.uWidthMm + r.uSigmaWMm * r.uSigmaWMm);
          expect((r.widthMm - w).abs(), lessThanOrEqualTo(3 * u), reason: 'w=$w seed=$s');
          // d ln w / d ln sigma is about 4 at w ~ 1.6 sigma (sweep), so 5 percent on sigma gives
          // about 0.2 w; 0.15 w leaves room for the scatter of s2.
          expect(u, greaterThan(0.15 * w), reason: 'false precision w=$w seed=$s');
        }
      }
    });

    test('the fit covariance alone IS tight for sub-pixel cracks (why u_sigma_w must be in the budget)', () {
      // Documents the finding: statistical u is ~1 um while a 5 percent sigma error moves w by ~20 um.
      final r = fit(patchOf(w: 0.1, noise: 0.005));
      final off = fit(patchOf(w: 0.1, noise: 0.005), sigmaPx: 1.05);
      expect((off.widthMm - r.widthMm).abs(), greaterThan(10 * r.uWidthMm));
    });
  });

  test('uncertainty scales with sqrt(rho)', () {
    final p = patchOf(w: 0.5);
    final a = fit(p);
    final b = fit(p, config: const ProfileFitConfig(rho: 4.0, rhoCalibrated: true));
    expect(b.uWidthMm, closeTo(2 * a.uWidthMm, 1e-12));
    expect(b.uWidthRawMm, closeTo(a.uWidthRawMm, 1e-15));
    expect(b.rhoCalibrated, isTrue);
  });

  test('u_sigma_w: the sigma uncertainty propagates by refitting at sigma +- u', () {
    final p = patchOf(w: 0.4);
    final sg = apparentSigmaMm(1.0);
    final r = fit(p, sigmaMmOverride: sg, uSigmaMmOverride: 0.1 * sg);
    final up = fit(p, sigmaMmOverride: 1.1 * sg).widthMm, dn = fit(p, sigmaMmOverride: 0.9 * sg).widthMm;
    expect(r.uSigmaWMm, greaterThan(0));
    // Same refit from a different start: agreement to the solver tolerance of the fit (0.5 um).
    expect(r.uSigmaWMm, closeTo((up - dn).abs() / 2, 0.0005));
    expect(fit(p).uSigmaWMm, 0);
  });

  test('a patch that does not cover the profiles is rejected, not extrapolated', () {
    final small = renderCrackPatch(camera: cam(), scene: crackScene(widthMm: 0.5, directionDeg: 20), halfSizeMm: 2.5, psfSigmaPx: 1);
    expect(
      () => fit(small),
      throwsA(isA<MeasurementException>().having((e) => e.reason, 'reason', RejectReason.patchTooSmall)),
    );
  });

  test('the fit is deterministic', () {
    final p = patchOf(w: 0.5);
    final a = fit(p), b = fit(p);
    expect(a.widthMm, b.widthMm);
    expect(a.uWidthMm, b.uWidthMm);
  });
}
