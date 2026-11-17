// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

const _img = ImageSize(4000, 3000);

SyntheticCamera _cam({
  double tilt = 0,
  double azimuth = 0,
  double roll = 0,
  double z = 240,
  double ox = 0,
  double oy = 0,
  double f = 3000,
}) =>
    SyntheticCamera(
      image: _img,
      fPx: f,
      distanceMm: z,
      tiltDeg: tilt,
      tiltAzimuthDeg: azimuth,
      rollDeg: roll,
      offsetXmm: ox,
      offsetYmm: oy,
    );

Mat3 _h(SyntheticCamera c, {double noisePx = 0, int seed = 1}) => estimateSheetHomography(
      SyntheticDetector(noisePx: noisePx, rng: Random(seed)).detect(c, sheetId: 0),
      sheetId: 0,
    ).h;

PoseState _pose(SyntheticCamera c) => poseStateFromHomography(_h(c), c.intrinsics);

void main() {
  group('intrinsics (5.2)', () {
    test('default f_px = 0.75 * longest side, orientation independent', () {
      expect(CameraIntrinsics.fromImage(const ImageSize(4000, 3000)).fPx, 3000);
      expect(CameraIntrinsics.fromImage(const ImageSize(3000, 4000)).fPx, 3000);
    });

    test('f_px from metadata: focal/sensor_long * long side px', () {
      // 6.9 mm lens, 9.8 mm long sensor side, 4000 px: 6.9/9.8*4000 = 2816.3
      final k = CameraIntrinsics.fromImage(const ImageSize(4000, 3000), focalMm: 6.9, sensorLongSideMm: 9.8);
      expect(k.fPx, closeTo(2816.3265, 1e-3));
      final portrait = CameraIntrinsics.fromImage(const ImageSize(3000, 4000), focalMm: 6.9, sensorLongSideMm: 9.8);
      expect(portrait.fPx, k.fPx);
    });

    test('invalid metadata falls back to the default', () {
      for (final bad in [
        (0.0, 9.8),
        (6.9, 0.0),
        (double.nan, 9.8),
        (-1.0, 9.8),
      ]) {
        expect(
          CameraIntrinsics.fromImage(_img, focalMm: bad.$1, sensorLongSideMm: bad.$2).fPx,
          3000,
        );
      }
      expect(CameraIntrinsics.fromImage(_img, focalMm: 6.9).fPx, 3000);
    });

    test('principal point is the centre in the pixel-centre convention', () {
      final k = CameraIntrinsics.fromImage(_img);
      expect(k.cx, 1999.5);
      expect(k.cy, 1499.5);
    });
  });

  group('tilt (5.2) with exact f', () {
    for (final tilt in [0.0, 10.0, 20.0, 30.0]) {
      test('noiseless synthetic tilt $tilt deg recovered within 1e-4 deg', () {
        // acos is ill-conditioned at 0 (d tilt = sqrt(2 eps)); 1e-4 deg covers it.
        final c = _cam(tilt: tilt, azimuth: 70, roll: 15, ox: 5, oy: -4);
        final t = estimateTilt(_h(c), c.intrinsics);
        expect(t.tiltDeg, closeTo(tilt, 1e-4));
        expect(t.tiltIsApprox, isTrue);
      });
    }

    test('noisy detection (0.2 px) over random azimuths: tilt error documented bound', () {
      // Measured (seed 11, 40 trials per tilt, 0.2 px corner noise, exact f): RMS error
      // 0.012 to 0.019 deg. Corners are thousands of px apart, so noise barely matters
      // next to the f error below. Bound 0.1 deg (5x margin).
      final rng = Random(11);
      for (final tilt in [0.0, 10.0, 20.0, 30.0]) {
        var sq = 0.0;
        const n = 40;
        for (var i = 0; i < n; i++) {
          final c = _cam(tilt: tilt, azimuth: rng.nextDouble() * 360, roll: rng.nextDouble() * 30 - 15);
          final t = estimateTilt(_h(c, noisePx: 0.2, seed: i), c.intrinsics).tiltDeg;
          sq += (t - tilt) * (t - tilt);
        }
        expect(sqrt(sq / n), lessThan(0.1), reason: 'tilt $tilt');
      }
    });
  });

  group('tilt with f_px off by 20 percent (impact documented, not hidden)', () {
    // SINTETICO, measured (noiseless, mean over 12 azimuths, roll 15, true tilt ->
    // mean estimate at f x0.8 / x1.2; max |error| in deg):
    //   0 -> 0.00 / 0.00 (0.00)   10 -> 8.03 / 11.95 (1.97)
    //   20 -> 16.23 / 23.59 (3.77)   30 -> 24.79 / 34.72 (5.21)
    // So f too small underestimates the tilt and f too large overestimates it, by
    // about 0.2 x tilt per 20 percent of f error. Documented in DECISIONS D17.
    for (final tilt in [0.0, 10.0, 20.0, 30.0]) {
      for (final scale in [0.8, 1.2]) {
        test('true tilt $tilt, f x $scale: error within the measured envelope', () {
          final c = _cam(tilt: tilt, azimuth: 70, roll: 15);
          final est = estimateTilt(_h(c), c.intrinsics.withFocalScale(scale)).tiltDeg;
          // Envelope: |error| <= 0.22 * tilt + 0.05 deg (measured worst 0.197 * tilt).
          expect((est - tilt).abs(), lessThan(0.22 * tilt + 0.05), reason: 'est=$est');
          if (tilt > 0) {
            expect(est, scale < 1 ? lessThan(tilt) : greaterThan(tilt));
          }
        });
      }
    }

    test('consequence for the gates: a true 20 deg frame reads 16..24 deg with f off by 20 percent', () {
      for (final scale in [0.8, 1.2]) {
        final c = _cam(tilt: 20, azimuth: 70, roll: 15);
        final est = estimateTilt(_h(c), c.intrinsics.withFocalScale(scale)).tiltDeg;
        expect(est, inInclusiveRange(16, 24));
      }
    });
  });

  group('pose state', () {
    test('rotation, centre and area follow the synthetic camera', () {
      final c = _cam(roll: 12, z: 200);
      final s = _pose(c);
      expect(s.rotationDeg, closeTo(12, 1e-6));
      expect(s.centerPx.x, closeTo(1999.5, 1e-6));
      expect(s.centerPx.y, closeTo(1499.5, 1e-6));
      // Square of side 120 mm at 200/3000 mm/px: (120*3000/200)^2 px^2.
      expect(s.areaPx2, closeTo(pow(120 * 3000 / 200, 2), 1e-3));
      expect(s.tiltDeg, closeTo(0, 1e-4));
    });
  });

  group('pose instructions (5.2)', () {
    final ref = _pose(_cam());
    PoseDeviation dev(SyntheticCamera c, {PoseState? reference}) =>
        comparePose(_pose(c), reference ?? ref, _img);

    test('identical pose is ready with zero deviation', () {
      final d = dev(_cam());
      expect(d.isReady, isTrue);
      expect(d.primary, isNull);
      expect(d.translationFrac, closeTo(0, 1e-9));
      expect(d.scaleRatio, closeTo(1, 1e-9));
    });

    // Translation: image diagonal is 5000 px; 3 percent = 150 px = 12 mm at 0.08 mm/px.
    // A camera offset o (mm) shifts the sheet by -o in the image, so it moves the
    // phone by +o: dx > 0 (sheet appears right) means the phone must move right.
    test('sheet appears right: MOVE_RIGHT; left: MOVE_LEFT; below: MOVE_DOWN; above: MOVE_UP', () {
      // sheet centre offset +x by 16 mm = 200 px = 4.0 percent of the diagonal.
      expect(dev(_cam(ox: 16)).instructions, [PoseInstruction.moveRight]);
      expect(dev(_cam(ox: -16)).instructions, [PoseInstruction.moveLeft]);
      expect(dev(_cam(oy: 16)).instructions, [PoseInstruction.moveDown]);
      expect(dev(_cam(oy: -16)).instructions, [PoseInstruction.moveUp]);
    });

    test('translation just inside 3 percent is ready, just outside is not', () {
      // 11.9 mm = 148.75 px = 2.975 percent; 12.1 mm = 151.25 px = 3.025 percent.
      expect(dev(_cam(ox: 11.9)).isReady, isTrue);
      expect(dev(_cam(ox: 12.1)).isReady, isFalse);
    });

    test('dominant axis wins for a diagonal offset', () {
      expect(dev(_cam(ox: 14, oy: 6)).instructions, [PoseInstruction.moveRight]);
      expect(dev(_cam(ox: 6, oy: -14)).instructions, [PoseInstruction.moveUp]);
    });

    test('scale: sheet 10 percent larger (phone too close) -> FARTHER; smaller -> CLOSER', () {
      // ratio = Z_ref / Z. Z=240 reference.
      expect(dev(_cam(z: 240 / 1.12)).instructions, [PoseInstruction.farther]);
      expect(dev(_cam(z: 240 / 0.88)).instructions, [PoseInstruction.closer]);
      // Inside the 0.9..1.1 band: ready.
      expect(dev(_cam(z: 240 / 1.09)).isReady, isTrue);
      expect(dev(_cam(z: 240 / 0.91)).isReady, isTrue);
    });

    test('rotation: sheet turned clockwise -> ROTATE_CW; counter-clockwise -> ROTATE_CCW', () {
      expect(dev(_cam(roll: 6)).instructions, [PoseInstruction.rotateCw]);
      expect(dev(_cam(roll: -6)).instructions, [PoseInstruction.rotateCcw]);
      expect(dev(_cam(roll: 4.9)).isReady, isTrue);
      expect(dev(_cam(roll: -4.9)).isReady, isTrue);
    });

    test('rotation wraps across +-180 (reference 178, now -178 is a 4 degree difference)', () {
      final a = _pose(_cam(roll: 178));
      final b = _pose(_cam(roll: -178));
      final d = comparePose(b, a, _img);
      expect(d.rotationDeg, closeTo(4, 1e-6));
      expect(d.isReady, isTrue);
    });

    test('tilt: difference above 8 deg -> HOLD_FLAT, inside -> ready', () {
      expect(dev(_cam(tilt: 9, azimuth: 30)).instructions, [PoseInstruction.holdFlat]);
      expect(dev(_cam(tilt: 7, azimuth: 30)).isReady, isTrue);
    });

    test('tilt difference is relative to the reference tilt', () {
      final tilted = _pose(_cam(tilt: 12, azimuth: 30));
      final d = comparePose(_pose(_cam(tilt: 18, azimuth: 30)), tilted, _img);
      expect(d.tiltDeltaDeg, closeTo(6, 1e-3));
      expect(d.isReady, isTrue);
    });

    test('several deviations are reported, most important first', () {
      final d = dev(_cam(tilt: 12, z: 240 / 1.2, roll: -8, ox: 20));
      expect(d.instructions, [
        PoseInstruction.holdFlat,
        PoseInstruction.farther,
        PoseInstruction.rotateCcw,
        PoseInstruction.moveRight,
      ]);
      expect(d.primary, PoseInstruction.holdFlat);
    });

    test('instruction codes are the stable wire names', () {
      expect(PoseInstruction.moveLeft.code, 'MOVE_LEFT');
      expect(PoseInstruction.rotateCw.code, 'ROTATE_CW');
      expect(PoseInstruction.holdFlat.code, 'HOLD_FLAT');
      expect(PoseInstruction.closer.code, 'CLOSER');
      expect({for (final i in PoseInstruction.values) i.code}.length, PoseInstruction.values.length);
    });

    test('custom thresholds are honoured', () {
      const strict = PoseThresholds(maxRotationDeg: 1);
      final d = comparePose(_pose(_cam(roll: 2)), ref, _img, thresholds: strict);
      expect(d.instructions, [PoseInstruction.rotateCw]);
    });

    test('standard thresholds are the 5.2 values', () {
      const t = PoseThresholds.standard;
      expect(t.maxTranslationFrac, 0.03);
      expect(t.minScaleRatio, 0.9);
      expect(t.maxScaleRatio, 1.1);
      expect(t.maxRotationDeg, 5);
      expect(t.maxTiltDeltaDeg, 8);
    });
  });

  test('a homography that collapses the frame to a line is DegenerateConfigurationException', () {
    // Maps (x, y) -> (x, 0): zero area, no plane normal.
    final h = <double>[1, 0, 0, 0, 0, 0, 0, 0, 1];
    expect(
      () => poseStateFromHomography(h, CameraIntrinsics.fromImage(_img)),
      throwsA(isA<DegenerateConfigurationException>()),
    );
  });

  test('estimateTilt rejects a degenerate homography', () {
    expect(
      () => estimateTilt(<double>[0, 0, 0, 0, 0, 0, 0, 0, 1], CameraIntrinsics.fromImage(_img)),
      throwsA(isA<DegenerateConfigurationException>()),
    );
  });
}
