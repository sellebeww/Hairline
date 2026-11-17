// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

import 'support/jpeg_ports.dart';

// 0.12 mm/px, 1600 x 1500 photo: the 150 mm frame spans 1250 px. Not a phone-sized
// image (the real chain is 12 MP) but the same physics; keeps the test around a minute.
const _image = ImageSize(1600, 1500);
const _trueWidth = 0.6;
const _dir = 25.0;
const _frames = 4;

SyntheticCamera _camera() => SyntheticCamera(
      image: _image,
      fPx: 1280,
      distanceMm: 0.12 * 1280,
      tiltDeg: 8,
      tiltAzimuthDeg: 40,
      rollDeg: 12,
      offsetXmm: 3,
      offsetYmm: -2,
    );

const _context = FrameContext(sheetId: 0, pointMm: Pt(0, 0), directionDeg: _dir);

FrameOutcome _run(Uint8List bytes, FramePorts ports, [FrameContext ctx = _context]) =>
    processFrame(encoded: bytes, ports: ports, context: ctx);

void main() {
  group('processFrame rejections and resource handling', () {
    final cam = _camera();
    final blank = Uint8List(_image.width * _image.height)..fillRange(0, _image.width * _image.height, 128);
    Uint8List photo(List<MarkerDetection> d) => SyntheticPhotoCodec.encode(blank, _image.width, _image.height, d);
    List<MarkerDetection> detections({Set<int> omit = const {}, SyntheticCamera? camera}) =>
        SyntheticDetector(noisePx: 0.2, rng: Random(1)).detect(camera ?? cam, sheetId: 0, omit: omit);

    test('fewer than 3 markers: rejected with a specific message, image disposed', () {
      final events = <String>[];
      final o = _run(
        photo(detections(omit: {0, 1})),
        FramePorts(source: SyntheticPhotoSource(trace: events.add), detector: const EmbeddedMarkerDetector()),
      );
      expect(o.accepted, isFalse);
      expect(o.input.geometryRejections, [FrameRejection.tooFewMarkers]);
      expect(o.messages.single, contains('Penanda tertutup'));
      expect(events, ['open', 'close']);
    });

    test('unreadable bytes: imageUnreadable and nothing was opened', () {
      final events = <String>[];
      final o = _run(
        Uint8List.fromList([1, 2, 3]),
        FramePorts(source: SyntheticPhotoSource(trace: events.add), detector: const EmbeddedMarkerDetector()),
      );
      expect(o.input.geometryRejections, [FrameRejection.imageUnreadable]);
      expect(events, isEmpty);
    });

    test('a hard tilt is rejected before any patch is extracted', () {
      final tilted = SyntheticCamera(image: _image, fPx: 1280, distanceMm: 0.12 * 1280, tiltDeg: 40, tiltAzimuthDeg: 10);
      final o = _run(
        photo(detections(camera: tilted)),
        const FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector()),
      );
      expect(o.input.geometryRejections, contains(FrameRejection.tiltHardReject));
      expect(o.measurement, isNull);
      expect(o.tiltDeg, closeTo(40, 3));
    });

    test('a detector that throws still disposes the image and the error propagates', () {
      final events = <String>[];
      expect(
        () => _run(photo(detections()), FramePorts(source: SyntheticPhotoSource(trace: events.add), detector: _ThrowingDetector())),
        throwsStateError,
      );
      expect(events, ['open', 'close']);
    });

    test('markers of another sheet are ignored: treated as missing', () {
      final other = SyntheticDetector(rng: Random(2)).detect(cam, sheetId: 1);
      final o = _run(
        photo(other),
        const FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector()),
      );
      expect(o.input.geometryRejections, [FrameRejection.tooFewMarkers]);
    });
  });

  group('memory: no whole-frame patches', () {
    test('the patches taken from a photo cover a small fraction of it (4 marker edges + the crack ROI)', () {
      final cam = _camera();
      final gray = Uint8List(_image.width * _image.height)..fillRange(0, _image.width * _image.height, 128);
      final rects = <(int, int)>[];
      final image = _RecordingImage(_image.width, _image.height, gray, rects);
      final detections = SyntheticDetector(noisePx: 0.2, rng: Random(1)).detect(cam, sheetId: 0);
      final o = processFrame(
        encoded: Uint8List(0),
        ports: FramePorts(source: _FixedSource(image), detector: _FixedDetector(detections)),
        context: _context,
      );
      expect(o.tiltDeg, isNotNull); // reached the patch stage (a flat gray photo then has no marker edges, so no crack ROI is cut)
      expect(rects, hasLength(4)); // one patch per marker, none for the whole frame
      final area = rects.fold<int>(0, (a, r) => a + r.$1 * r.$2);
      // Fraction, not bytes: the ratio holds at 12 MP (patch sizes scale with the image like the image does).
      expect(area / (_image.width * _image.height), lessThan(0.25), reason: '$rects');
      expect(rects.every((r) => r.$1 * r.$2 < 0.06 * _image.width * _image.height), isTrue, reason: '$rects');
      expect(image.disposed, isTrue);
    });
  });

  group('homography JSON (D5)', () {
    test('round trips and refuses another version', () {
      final cam = _camera();
      final json = homographyToJson(cam.h, _image);
      final back = homographyFromJson(json);
      expect(back.h, cam.h);
      expect(back.size.width, 1600);
      expect(() => homographyFromJson({...json, 'v': 2}), throwsFormatException);
    });
  });

  group('end to end: rendered photo -> JPEG -> pipeline -> visit', () {
    late final SyntheticCamera cam;
    late final GrayImage clean;
    setUpAll(() {
      cam = _camera();
      clean = renderSheetPhoto(camera: cam, crackWidthMm: _trueWidth, crackDirectionDeg: _dir, psfSigmaPx: 1, noiseSigma: 0);
    });

    /// One burst: per-frame noise, per-frame corner noise, encoded by [encode].
    VisitResult visit(Uint8List Function(Uint8List gray) encode, FrameImageSource source, {int seed = 7}) {
      final rng = Random(seed);
      final photos = <Uint8List>[];
      final dets = <List<MarkerDetection>>[];
      for (var i = 0; i < _frames; i++) {
        final noisy = GrayImage(clean.width, clean.height, Float32List.fromList([
          for (final v in clean.data) (v + 0.004 * gaussian(rng)).clamp(0.0, 1.0).toDouble(),
        ]));
        photos.add(encode(srgbBytes(noisy)));
        dets.add(SyntheticDetector(noisePx: 0.2, rng: rng).detect(cam, sheetId: 0));
      }
      final ports = FramePorts(source: source, detector: QueueDetector(dets));
      final inputs = [for (final p in photos) _run(p, ports).input];
      return aggregateVisit(inputs);
    }

    test('width within the reported uncertainty at JPEG quality 85 and 95; the JPEG effect is recorded', () {
      final raw = visit((g) => SyntheticPhotoCodec.encode(g, _image.width, _image.height, const []), const _RawSource());
      final q95 = visit((g) => encodeGrayJpeg(g, _image.width, _image.height, 95), DartJpegSource());
      final q85 = visit((g) => encodeGrayJpeg(g, _image.width, _image.height, 85), DartJpegSource());
      final lines = <String>[];
      for (final (name, v) in [('raw', raw), ('q95', q95), ('q85', q85)]) {
        expect(v.status, VisitStatus.terukur, reason: '$name: ${v.rejectionCounts} ${v.status}');
        final b = v.budget!;
        final err = b.widthMm - _trueWidth;
        lines.add('$name: w=${(b.widthMm * 1000).toStringAsFixed(1)} um err=${(err * 1000).toStringAsFixed(1)} um '
            'U=${(b.uExpanded * 1000).toStringAsFixed(1)} um u_c=${(b.uC * 1000).toStringAsFixed(1)} um n=${b.n}');
        expect(err.abs(), lessThanOrEqualTo(b.uExpanded), reason: name);
      }
      final shift95 = q95.budget!.widthMm - raw.budget!.widthMm;
      final shift85 = q85.budget!.widthMm - raw.budget!.widthMm;
      lines.add('JPEG shift vs raw: q95 ${(shift95 * 1000).toStringAsFixed(1)} um, q85 ${(shift85 * 1000).toStringAsFixed(1)} um');
      // ignore: avoid_print
      print(lines.join('\n'));
      // The budget has no JPEG term, so the shift must be small against it. Measured 0.2 and
      // 0.5 um (seed 7); 5 um leaves a 10x margin for platform differences. A codec-only
      // effect on gray synthetic images: a phone's ISP sharpening is not covered.
      expect(shift95.abs(), lessThan(0.005));
      expect(shift85.abs(), lessThan(0.005));
      expect(shift95.abs(), lessThan(q95.budget!.uExpanded / 10));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a one-sided shadow gives MODEL_MISFIT and the frame is demoted to TIDAK_TERUKUR (D36)', () {
      final shadowed = renderSheetPhoto(
        camera: cam,
        crackWidthMm: _trueWidth,
        crackDirectionDeg: _dir,
        noiseSigma: 0.002,
        rng: Random(3),
        crackOverride: rotatedAboutOrigin(withOneSidedShadow(crackScene(widthMm: _trueWidth, background: 0.8), 0.9), _dir),
      );
      final detections = SyntheticDetector(noisePx: 0.2, rng: Random(4)).detect(cam, sheetId: 0);
      final o = _run(
        SyntheticPhotoCodec.encode(srgbBytes(shadowed), _image.width, _image.height, detections),
        const FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector()),
      );
      expect(o.accepted, isTrue, reason: '${o.messages}');
      expect(o.measurement!.warnings, contains(MeasureWarning.modelMisfit));
      expect(o.demotedForMisfit, isTrue);
      expect(o.input.record!.status, MeasureStatus.tidakTerukur);
      expect(o.qualityJson()['demoted_for_misfit'], isTrue);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// Gray photo that records the size of every patch requested from it.
final class _RecordingImage extends MemoryDecodedImage {
  _RecordingImage(super.width, super.height, super.gray, this.rects);
  final List<(int, int)> rects;
  bool disposed = false;

  @override
  GrayPatch extractPatch(int x, int y, int w, int h) {
    rects.add((w, h));
    return super.extractPatch(x, y, w, h);
  }

  @override
  void dispose() => disposed = true;
}

final class _FixedSource implements FrameImageSource {
  const _FixedSource(this.image);
  final DecodedImage image;

  @override
  DecodedImage decode(Uint8List encoded) => image;
}

final class _FixedDetector implements MarkerDetector {
  const _FixedDetector(this.detections);
  final List<MarkerDetection> detections;

  @override
  List<MarkerDetection> detect(DecodedImage image) => detections;
}

final class _ThrowingDetector implements MarkerDetector {
  @override
  List<MarkerDetection> detect(DecodedImage image) => throw StateError('native failure');
}

/// Raw bytes in the synthetic container, detections come from the queue detector.
final class _RawSource implements FrameImageSource {
  const _RawSource();

  @override
  DecodedImage decode(Uint8List encoded) {
    final p = SyntheticPhotoCodec.decode(encoded);
    return MemoryDecodedImage(p.width, p.height, p.gray);
  }
}
