// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline/pipeline/frame_processor.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

/// Photo geometry shared by the app tests: 0.12 mm/px, 1600 x 1500 px, sheet 0.
const testImage = ImageSize(1600, 1500);
const crackDirectionDeg = 25.0;
const trueWidthMm = 0.6;

SyntheticCamera testCamera() => SyntheticCamera(
      image: testImage,
      fPx: 1280,
      distanceMm: 0.12 * 1280,
      tiltDeg: 8,
      tiltAzimuthDeg: 40,
      rollDeg: 12,
      offsetXmm: 3,
      offsetYmm: -2,
    );

/// Ports that read the synthetic container: no native code, same code path as production.
FramePorts syntheticPorts() => const FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector());

/// A gray photo (no crack) with the given detections: cheap, enough for rejection paths.
Uint8List blankPhoto(List<MarkerDetection> detections) {
  final gray = Uint8List(testImage.width * testImage.height)..fillRange(0, testImage.width * testImage.height, 128);
  return SyntheticPhotoCodec.encode(gray, testImage.width, testImage.height, detections);
}

List<MarkerDetection> detections(SyntheticCamera cam, {int seed = 1, Set<int> omit = const {}}) =>
    SyntheticDetector(noisePx: 0.2, rng: Random(seed)).detect(cam, sheetId: 0, omit: omit);

/// Appends `event` lines to [path] (a file is the only thing a worker isolate and the test share).
void trace(String path, String event) => File(path).writeAsStringSync('$event\n', mode: FileMode.append, flush: true);

List<String> readTrace(String path) => File(path).existsSync() ? File(path).readAsLinesSync() : const [];

/// A factory (sent to the worker isolate) whose adapters report `open` / `close` to
/// [tracePath], and whose detector sleeps [detectDelayMs] or throws.
FramePortsFactory tracingFactory(String tracePath, {int detectDelayMs = 0, bool failInDetect = false}) =>
    () => FramePorts(
          source: _TracingSource(tracePath),
          detector: _SlowDetector(detectDelayMs, failInDetect),
        );

final class _TracingSource implements FrameImageSource {
  const _TracingSource(this.path);
  final String path;

  @override
  DecodedImage decode(Uint8List encoded) {
    final p = SyntheticPhotoCodec.decode(encoded);
    trace(path, 'open');
    return MemoryDecodedImage(p.width, p.height, p.gray, detections: p.detections, onDispose: () => trace(path, 'close'));
  }
}

final class _SlowDetector implements MarkerDetector {
  const _SlowDetector(this.delayMs, this.fail);
  final int delayMs;
  final bool fail;

  @override
  List<MarkerDetection> detect(DecodedImage image) {
    if (delayMs > 0) sleep(Duration(milliseconds: delayMs));
    if (fail) throw StateError('native detector failed');
    return const EmbeddedMarkerDetector().detect(image);
  }
}
