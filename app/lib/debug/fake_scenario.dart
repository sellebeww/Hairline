// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

import '../capture/fake_camera_service.dart';
import '../capture/luma_frame.dart';

/// Debug and test only: a scripted "recording" for `FakeCameraService`. Live frames walk
/// from "no marker" through "two markers" and "far, rotated, tilted" to the target pose;
/// the stills are renderer photos of the same pose (or flat gray ones that the quality
/// gate must reject). Everything is synthetic (SINTETIS), nothing comes from a phone.
final class FakeScenario {
  const FakeScenario({required this.live, required this.stills});

  final List<LumaFrame> live;
  final List<Uint8List> stills;

  FakeCameraService service({Duration frameInterval = const Duration(milliseconds: 100), Duration shotDelay = const Duration(milliseconds: 20)}) =>
      FakeCameraService(frames: live, stills: stills, frameInterval: frameInterval, shotDelay: shotDelay);
}

/// Photo geometry of the simulation: 0.12 mm/px, sheet 0, crack at the window centre.
const demoImage = ImageSize(1600, 1500);
const demoCrackDirectionDeg = 25.0;
const demoCrackWidthMm = 0.6;
const _step = 40;

SyntheticCamera _camera({double t = 1}) {
  double lerp(double from, double to) => from + (to - from) * t;
  return SyntheticCamera(
    image: demoImage,
    fPx: 1280,
    distanceMm: lerp(0.17, 0.12) * 1280,
    tiltDeg: lerp(16, 4),
    tiltAzimuthDeg: 40,
    rollDeg: lerp(24, 6),
    offsetXmm: lerp(-22, 2),
    offsetYmm: lerp(16, -1),
  );
}

/// The pose the script ends on (and the baseline reference of a first visit).
SyntheticCamera demoTargetCamera() => _camera();

LumaFrame _liveFrame(SyntheticCamera cam, Random rng, {Set<int> omit = const {}, bool blind = false}) {
  const w = 40, h = 37; // 1600 x 1500 decimated by 40 (offset 20)
  final dets = blind
      ? const <MarkerDetection>[]
      : SyntheticDetector(noisePx: 0.2, rng: rng).detect(cam, sheetId: 0, omit: omit);
  final small = [
    for (final d in dets) MarkerDetection(id: d.id, corners: [for (final c in d.corners) Pt((c.x - _step ~/ 2) / _step, (c.y - _step ~/ 2) / _step)]),
  ];
  return LumaFrame(
    bytes: SyntheticPhotoCodec.encode(Uint8List(w * h), w, h, small),
    width: w,
    height: h,
    step: _step,
    sourceWidth: demoImage.width,
    sourceHeight: demoImage.height,
  );
}

/// Builds the recording. With [renderCrack] the stills carry a rendered crack of
/// [demoCrackWidthMm] (about 15 s of CPU: run it in an isolate); without, they are flat
/// gray and the quality gate rejects them ("retak tidak ditemukan").
FakeScenario buildFakeScenario({bool renderCrack = true, int seed = 11, int stills = 6}) {
  final rng = Random(seed);
  final target = demoTargetCamera();
  final live = <LumaFrame>[
    for (var i = 0; i < 6; i++) _liveFrame(target, rng, blind: true),
    for (var i = 0; i < 6; i++) _liveFrame(_camera(t: 0.2), rng, omit: const {0, 1}),
    for (var i = 0; i < 20; i++) _liveFrame(_camera(t: 0.2 + 0.8 * i / 19), rng),
    for (var i = 0; i < 40; i++) _liveFrame(target, rng),
  ];
  final gray = renderCrack
      ? srgbBytes(renderSheetPhoto(
          camera: target,
          crackWidthMm: demoCrackWidthMm,
          crackDirectionDeg: demoCrackDirectionDeg,
          noiseSigma: 0.004,
          rng: Random(seed),
        ))
      : (Uint8List(demoImage.width * demoImage.height)..fillRange(0, demoImage.width * demoImage.height, 128));
  return FakeScenario(
    live: live,
    stills: [
      for (var i = 0; i < stills; i++)
        SyntheticPhotoCodec.encode(
          gray,
          demoImage.width,
          demoImage.height,
          SyntheticDetector(noisePx: 0.2, rng: Random(seed + 100 + i)).detect(target, sheetId: 0),
        ),
    ],
  );
}
