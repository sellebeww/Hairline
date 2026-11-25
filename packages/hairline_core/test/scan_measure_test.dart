// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

Uint8List _pgm(int w, int h, List<int> samples, {int maxval = 255, String comment = ''}) {
  final head = utf8.encode('P5\n$comment$w $h\n$maxval\n');
  final body = maxval > 255
      ? [for (final v in samples) ...[v >> 8, v & 255]]
      : samples;
  return Uint8List.fromList([...head, ...body]);
}

/// A flatbed scan of the plate: similarity map (dpi, rotation, origin), Gaussian PSF, gamma encoded.
Uint8List _scan({required double dpi, required int w, required int h, required Pt origin, required double angleDeg, required double sigmaPx, required Scene scene, int seed = 3}) {
  final s = dpi / 25.4, a = angleDeg * pi / 180, c = cos(a), sn = sin(a);
  final img = renderGray(
    width: w,
    height: h,
    toScene: (px, py) {
      final dx = (px - origin.x) / s, dy = (py - origin.y) / s;
      return Pt(c * dx + sn * dy, -sn * dx + c * dy);
    },
    scene: scene,
    supersample: 2,
    psfSigmaPx: sigmaPx,
    noiseSigma: 0.003,
    rng: Random(seed),
  );
  return _pgm(w, h, srgbBytes(img).toList());
}

void main() {
  group('PgmImage', () {
    test('reads 8 bit samples and comments', () {
      final p = PgmImage.parse(_pgm(5, 4, [for (var i = 0; i < 20; i++) i * 10], comment: '# made by a test\n'));
      expect((p.width, p.height), (5, 4));
      final patch = p.extractPatch(1, 0, 4, 4);
      expect(patch.data.map((v) => (v * 255).round()).take(4).toList(), [10, 20, 30, 40]);
      expect((patch.data[4 * 3 + 3] * 255).round(), 190);
    });

    test('reads 16 bit big endian samples', () {
      final p = PgmImage.parse(_pgm(4, 4, [0, 65535, 32768, ...List.filled(13, 1)], maxval: 65535));
      final patch = p.extractPatch(0, 0, 4, 4);
      expect(patch.data[0], 0);
      expect(patch.data[1], closeTo(1, 1e-6));
      expect(patch.data[2], closeTo(0.5, 1e-4));
    });

    test('rejects other formats, bad headers and truncated data', () {
      expect(() => PgmImage.parse(Uint8List.fromList(utf8.encode('P6\n1 1\n255\n123'))), throwsFormatException);
      expect(() => PgmImage.parse(Uint8List.fromList(utf8.encode('P5\n0 5\n255\n'))), throwsFormatException);
      expect(() => PgmImage.parse(Uint8List.fromList(utf8.encode('P5\n50000 5\n255\n'))), throwsFormatException);
      expect(() => PgmImage.parse(Uint8List.fromList(utf8.encode('P5\n3 3\n255\n12345'))), throwsFormatException);
      expect(() => PgmImage.parse(Uint8List(0)), throwsFormatException);
    });

    test('a patch outside the image is a RangeError', () {
      final p = PgmImage.parse(_pgm(4, 4, List.filled(16, 1)));
      expect(() => p.extractPatch(1, 1, 4, 4), throwsRangeError);
    });
  });

  group('measurePlateScan', () {
    final trueW = {for (final l in buildPlateLines()) l.id: l.nominalMm + 0.03};

    test('600 dpi window scan, rotated 1.5 degrees, origin 0.8 mm off: every line within its uncertainty of the true width', () {
      const dpi = 600.0;
      const size = 2000;
      const origin = Pt(1000, 1000);
      final bytes = _scan(
        dpi: dpi,
        w: size,
        h: size,
        origin: origin,
        angleDeg: 1.5,
        sigmaPx: 1.2,
        scene: plateScene(widthsMm: trueW),
      );
      // The owner reads the origin by eye: here 20 px (0.85 mm) to the right and 15 px up.
      final out = measurePlateScan(image: PgmImage.parse(bytes), dpi: dpi, originPx: const Pt(1020, 985), angleDeg: 1.5, sigmaPx: 1.2);
      expect(out, hasLength(32));
      var measured = 0;
      for (final m in out) {
        if (m.status != 'TERUKUR') {
          expect(m.nominalMm, lessThanOrEqualTo(0.2), reason: '${m.id}: ${m.status} ${m.message}');
          continue;
        }
        measured++;
        final err = m.widthMm! - trueW[m.id]!;
        // 0.01 mm = a quarter of a pixel (0.042 mm/px) plus the 0.5 percent scale term.
        expect(err.abs(), lessThan(0.012), reason: m.id);
        expect(m.uMm!, greaterThan(0), reason: m.id);
      }
      expect(measured, greaterThanOrEqualTo(24));
      // The CSV re-imports as a characterized truth with the same ids.
      final truth = PlateTruth.fromCsv(scanMeasurementsToCsv(out));
      expect(truth.characterized, isTrue);
      expect(truth.lines, hasLength(measured));
    });

    test('150 dpi full plate scan: the PSF comes from the marker edges (no sigmaPx needed)', () {
      const dpi = 150.0;
      const size = 1000;
      final bytes = _scan(
        dpi: dpi,
        w: size,
        h: size,
        origin: const Pt(500, 500),
        angleDeg: 0,
        sigmaPx: 1,
        scene: plateScene(widthsMm: trueW),
      );
      final out = measurePlateScan(image: PgmImage.parse(bytes), dpi: dpi, originPx: const Pt(500, 500));
      final wide = out.where((m) => m.nominalMm >= 0.8).toList();
      expect(wide, hasLength(16));
      for (final m in wide) {
        expect(m.status, 'TERUKUR', reason: '${m.id} ${m.message}');
        expect((m.widthMm! - trueW[m.id]!).abs(), lessThan(0.03), reason: m.id); // 0.17 mm/px: 0.03 mm = 0.18 px
      }
    });

    test('without the markers in the scan and without sigmaPx it refuses with a clear error', () {
      final bytes = _scan(dpi: 300, w: 900, h: 900, origin: const Pt(450, 450), angleDeg: 0, sigmaPx: 1, scene: plateScene());
      expect(() => measurePlateScan(image: PgmImage.parse(bytes), dpi: 300, originPx: const Pt(450, 450)), throwsA(isA<ArgumentError>().having((e) => '$e', 'm', contains('sigmaPx'))));
    });

    test('a wrong origin puts lines outside the scan: reported, not measured', () {
      final bytes = _scan(dpi: 300, w: 900, h: 900, origin: const Pt(450, 450), angleDeg: 0, sigmaPx: 1, scene: plateScene());
      final out = measurePlateScan(image: PgmImage.parse(bytes), dpi: 300, originPx: const Pt(5000, 5000), sigmaPx: 1);
      expect(out.every((m) => m.status == 'DI_LUAR_PINDAIAN'), isTrue);
      expect(() => scanMeasurementsToCsv(out), throwsA(isA<PlateTruthException>()));
    });

    test('invalid parameters are rejected', () {
      final img = PgmImage.parse(_pgm(4, 4, List.filled(16, 1)));
      expect(() => measurePlateScan(image: img, dpi: 10, originPx: const Pt(0, 0), sigmaPx: 1), throwsArgumentError);
      expect(() => measurePlateScan(image: img, dpi: 600, originPx: const Pt(double.nan, 0), sigmaPx: 1), throwsArgumentError);
      expect(() => measurePlateScan(image: img, dpi: 600, originPx: const Pt(0, 0), sigmaPx: 0), throwsArgumentError);
      expect(() => measurePlateScan(image: img, dpi: 600, originPx: const Pt(0, 0), sigmaPx: 1, scaleURel: 0.5), throwsArgumentError);
    });
  });
}
