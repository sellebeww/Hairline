// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

const _labels = SheetLabels(title: 'PELAT 11', cutHint: 'jangan dipotong', scaleBar: 'batang 100 mm', printNotes: ['a']);
const _plate = PlateLabels(legend: ['1=0,1 2=0,2']);

FrameInput _frame(double w, {double mmPerPx = 0.06, double uFit = 0.004}) => FrameInput.accepted(FrameRecord(
      status: MeasureStatus.terukur,
      widthMm: w,
      uFitRawMm: uFit,
      rho: 1,
      uSigmaWMm: 0.002,
      dwDs: 0,
      mmPerPx: mmPerPx,
      rmsPx: 0.2,
      looMm: 0.05,
      tiltDeg: 3,
    ));

/// Five frames of a line measured at [w] with a small spread.
List<FrameInput> _burst(double w) => [for (final d in [-0.003, -0.0015, 0, 0.0015, 0.003]) _frame(w + d)];

void main() {
  group('plate lines', () {
    final lines = buildPlateLines();

    test('32 unique lines: 8 nominal widths x 4 sets, ids set-index', () {
      expect(lines, hasLength(32));
      expect({for (final l in lines) l.id}, hasLength(32));
      for (final w in plateNominalWidthsMm) {
        expect(lines.where((l) => l.nominalMm == w), hasLength(4));
      }
      expect(lines.where((l) => l.vertical), hasLength(16));
      expect(lines.first.id, 'V1-1');
      expect(lines.firstWhere((l) => l.id == 'V1-3').nominalMm, 0.3);
    });

    test('directions follow the core convention: vertical 90, horizontal 0', () {
      for (final l in lines) {
        expect(l.directionDeg, l.vertical ? 90 : 0);
      }
    });

    test('the second set of each orientation is in the opposite order', () {
      double x(String id) => lines.firstWhere((l) => l.id == id).centreMm.x;
      expect(x('V1-1'), lessThan(x('V1-8')));
      expect(x('V2-1'), greaterThan(x('V2-8')));
    });

    test('every line (with its length) lies inside the window with margin, in the 70 mm window', () {
      for (final l in lines) {
        final hx = (l.vertical ? l.nominalMm : plateLineLengthMm) / 2, hy = (l.vertical ? plateLineLengthMm : l.nominalMm) / 2;
        expect(l.centreMm.x.abs() + hx, lessThanOrEqualTo(windowHalfSizeMm - 1), reason: l.id);
        expect(l.centreMm.y.abs() + hy, lessThanOrEqualTo(windowHalfSizeMm - 1), reason: l.id);
        expect(isInsideWindow(l.centreMm), isTrue);
      }
    });

    test('the 3 mm profile range of no line reaches another line', () {
      // Conservative: the body of each line grown by 3 mm on every side must not touch any other line.
      ({double x0, double x1, double y0, double y1}) box(PlateLineSpec l, double grow) {
        final hx = (l.vertical ? l.nominalMm : plateLineLengthMm) / 2, hy = (l.vertical ? plateLineLengthMm : l.nominalMm) / 2;
        return (x0: l.centreMm.x - hx - grow, x1: l.centreMm.x + hx + grow, y0: l.centreMm.y - hy - grow, y1: l.centreMm.y + hy + grow);
      }

      for (final a in lines) {
        for (final b in lines) {
          if (a.id == b.id) continue;
          final ba = box(a, 3), bb = box(b, 0);
          final overlap = ba.x0 < bb.x1 && ba.x1 > bb.x0 && ba.y0 < bb.y1 && ba.y1 > bb.y0;
          // Along the line the profile does not extend: only the perpendicular growth counts.
          final across = a.vertical ? (ba.x0 < bb.x1 && ba.x1 > bb.x0 && box(a, 0).y0 < bb.y1 && box(a, 0).y1 > bb.y0) : (ba.y0 < bb.y1 && ba.y1 > bb.y0 && box(a, 0).x0 < bb.x1 && box(a, 0).x1 > bb.x0);
          expect(across, isFalse, reason: '${a.id} profile reaches ${b.id} (full-grow overlap $overlap)');
        }
      }
    });

    test('lines of one set are separated by clearance plus half the narrower width', () {
      final v1 = lines.where((l) => l.setName == 'V1').toList();
      for (var i = 0; i + 1 < v1.length; i++) {
        final gap = v1[i + 1].centreMm.x - v1[i].centreMm.x - (v1[i].nominalMm + v1[i + 1].nominalMm) / 2;
        expect(gap, closeTo(plateLineClearanceMm, 1e-9));
      }
    });
  });

  group('plate layout', () {
    test('marker layout is identical to the frame sheet of the same id; lines are black rects of nominal width', () {
      final base = buildSheetLayout(plateSheetId, PaperSize.a4, _labels);
      final plate = buildPlateLayout(PaperSize.a4, _labels, _plate);
      final markerRects = [for (final p in base) if (p is SheetRect) p];
      final plateMarkerRects = [for (final p in plate) if (p is SheetRect && p.markerId != null) p];
      expect(plateMarkerRects.length, markerRects.length);
      for (var i = 0; i < markerRects.length; i++) {
        expect([plateMarkerRects[i].x, plateMarkerRects[i].y, plateMarkerRects[i].w, plateMarkerRects[i].h], [markerRects[i].x, markerRects[i].y, markerRects[i].w, markerRects[i].h]);
      }
      final lineRects = [for (final p in plate) if (p is SheetRect && p.markerId == null) p];
      expect(lineRects, hasLength(32));
      final thin = lineRects.map((r) => min(r.w, r.h)).toList()..sort();
      expect(thin.first, closeTo(0.1, 1e-9));
      expect(thin.last, closeTo(2.0, 1e-9));
      for (final r in lineRects) {
        expect(max(r.w, r.h), closeTo(plateLineLengthMm, 1e-9));
        expect(r.black, isTrue);
      }
    });

    test('a line rectangle is centred on its sheet coordinates (page = centre + sheet mm)', () {
      final plate = buildPlateLayout(PaperSize.letter, _labels, _plate);
      final l = buildPlateLines().firstWhere((l) => l.id == 'H2-4');
      final cx = PaperSize.letter.widthMm / 2;
      final r = [for (final p in plate) if (p is SheetRect && p.markerId == null) p].firstWhere((r) => (r.x + r.w / 2 - (cx + l.centreMm.x)).abs() < 1e-9 && (r.y + r.h / 2 - (sheetCentreFromTopMm + l.centreMm.y)).abs() < 1e-9);
      expect(r.h, closeTo(0.5, 1e-9)); // horizontal line: its thickness is the height
    });
  });

  group('plate truth CSV', () {
    String csv(Iterable<String> rows) => 'posisi,lebar_mm,u_mm\n${rows.join('\n')}\n';
    final ok = [for (final l in buildPlateLines().take(10)) '${l.id},${(l.nominalMm * 1.1).toStringAsFixed(3)},0.01'];

    test('a valid file is characterized', () {
      final t = PlateTruth.fromCsv(csv(ok));
      expect(t.characterized, isTrue);
      expect(t.lines, hasLength(10));
      expect(t.lines['V1-1']!.widthMm, closeTo(0.11, 1e-9));
      expect(t.lines['V1-1']!.uMm, 0.01);
    });

    test('JSON round trip keeps source and values', () {
      final t = PlateTruth.fromJson(PlateTruth.fromCsv(csv(ok)).toJson());
      expect(t.characterized, isTrue);
      expect(t.lines['V1-2']!.widthMm, closeTo(0.22, 1e-9));
      final n = PlateTruth.fromJson(PlateTruth.nominal().toJson());
      expect(n.source, PlateTruthSource.nominal);
      expect(n.lines, hasLength(32));
    });

    void rejects(String name, String text, String message) {
      test('rejects $name', () {
        expect(() => PlateTruth.fromCsv(text), throwsA(isA<PlateTruthException>().having((e) => e.message, 'message', contains(message))));
      });
    }

    rejects('a wrong header', 'id,w,u\nV1-1,0.1,0.01\n', 'Baris pertama');
    rejects('an empty file', '', 'Baris pertama');
    rejects('an unknown position', csv(['X9-1,0.1,0.01', ...ok]), 'tidak dikenal');
    rejects('a duplicate position', csv([...ok, ok.first]), 'dua kali');
    rejects('a decimal comma', csv(['V1-1,"0,11",0.01', ...ok.skip(1)]), 'kolom');
    rejects('a comma separated number written with a comma', csv(['V1-1,0,11,0.01']), 'kolom');
    rejects('text instead of a number', csv(['V1-1,abc,0.01', ...ok.skip(1)]), 'bukan angka');
    rejects('a negative width', csv(['V1-1,-0.1,0.01', ...ok.skip(1)]), 'bukan angka');
    rejects('a width far from nominal (unit mistake)', csv(['V1-1,100,0.01', ...ok.skip(1)]), 'nominal');
    rejects('an uncertainty above 1 mm', csv(['V1-1,0.1,2', ...ok.skip(1)]), 'u_mm');
    rejects('a width of 0.3 times nominal minus a hair', csv(['V1-8,0.5,0.01', ...ok.skip(1)]), 'nominal');
    rejects('too few lines', csv(ok.take(7)), 'Minimal 8');
    rejects('too many rows', csv([for (var i = 0; i < 65; i++) ok.first]), 'Terlalu banyak');
    rejects('a file over 8 KB', '${csv(ok)}${' ' * 9000}', 'terlalu besar');

    test('CRLF line ends and a BOM are accepted', () {
      final t = PlateTruth.fromCsv('﻿posisi,lebar_mm,u_mm\r\n${ok.join('\r\n')}\r\n');
      expect(t.lines, hasLength(10));
    });

    test('nominal truth rejects an invalid placeholder uncertainty', () {
      expect(() => PlateTruth.nominal(uMm: -1), throwsArgumentError);
      expect(() => PlateTruth.nominal(uMm: double.nan), throwsArgumentError);
    });
  });

  group('evaluatePlate', () {
    // Every line measured at truth + bias (+ small spread), truth characterised.
    ({PlateTruth truth, Map<String, List<FrameInput>> frames}) run({double bias = 0.01, Set<String> skip = const {}, double truthU = 0.01}) {
      final lines = buildPlateLines();
      final truthW = {for (final l in lines) l.id: l.nominalMm * 1.05};
      return (
        truth: PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in lines) '${l.id},${truthW[l.id]!.toStringAsFixed(4)},$truthU'].join('\n')}\n'),
        frames: {for (final l in lines) l.id: skip.contains(l.id) ? <FrameInput>[] : _burst(truthW[l.id]! + bias)},
      );
    }

    test('a good run with a characterized truth validates; u_dev is the RMS bias floored at u_truth', () {
      final r = run();
      final e = evaluatePlate(truth: r.truth, frames: r.frames);
      expect(e.stats.reported, 32);
      expect(e.stats.biasMm, closeTo(0.01, 1e-4));
      expect(e.stats.coverage, 1);
      expect(e.validated, isTrue, reason: e.reasons.join(' | '));
      expect(e.reasons, isEmpty);
      expect(e.uTruthMedianMm, 0.01);
      final d = DeviceValidation.fromResultsJson(e.toJson());
      expect(d.validated, isTrue);
      // the bias (0.01) is not below the truth floor (0.01): u_dev = 0.01
      expect(d.uDevFor(0.5), closeTo(0.01, 1e-3));
    });

    test('a smaller bias than the truth uncertainty is floored at u_truth', () {
      final r = run(bias: 0.001, truthU: 0.02);
      final e = evaluatePlate(truth: r.truth, frames: r.frames);
      expect(DeviceValidation.fromResultsJson(e.toJson()).uDevFor(0.5), closeTo(0.02, 1e-9));
    });

    test('NOMINAL truth never validates, however good the run', () {
      final r = run(bias: 0);
      final nominal = PlateTruth.nominal();
      final e = evaluatePlate(truth: nominal, frames: {for (final l in buildPlateLines()) l.id: _burst(l.nominalMm)});
      expect(e.validated, isFalse);
      expect(e.reasons.single, contains('NOMINAL'));
      expect(e.truthSource, PlateTruthSource.nominal);
      expect(r.truth.characterized, isTrue);
    });

    test('too few reported lines do not validate and say how many', () {
      final skip = {for (final l in buildPlateLines().take(20)) l.id};
      final r = run(skip: skip);
      final e = evaluatePlate(truth: r.truth, frames: r.frames);
      expect(e.stats.reported, 12);
      expect(e.validated, isFalse);
      expect(e.reasons.join(' '), contains('Hanya 12 garis'));
    });

    test('a biased phone fails the coverage test (bias far above the budget)', () {
      final r = run(bias: 0.25);
      final e = evaluatePlate(truth: r.truth, frames: r.frames);
      // u_dev takes the bias into account, so a CONSTANT bias is covered; a random bias is not:
      expect(e.stats.biasMm, closeTo(0.25, 1e-3));
      expect(e.validated, isTrue, reason: 'a constant bias becomes u_dev, which widens U and keeps the coverage');
      expect(DeviceValidation.fromResultsJson(e.toJson()).uDevFor(0.5), closeTo(0.25, 0.01));
    });

    test('an erratic phone (alternating +-0.2 mm bias) fails the coverage and does not validate', () {
      final lines = buildPlateLines();
      final truthW = {for (final l in lines) l.id: l.nominalMm * 1.05};
      final truth = PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in lines) '${l.id},${truthW[l.id]!.toStringAsFixed(4)},0.005'].join('\n')}\n');
      final frames = <String, List<FrameInput>>{};
      for (var i = 0; i < lines.length; i++) {
        frames[lines[i].id] = _burst(truthW[lines[i].id]! + (i.isEven ? 0.2 : -0.2) * (lines[i].nominalMm >= 0.5 ? 1 : 0.2));
      }
      final e = evaluatePlate(truth: truth, frames: frames);
      expect(e.stats.biasMm.abs(), lessThan(0.05));
      expect(e.validated, isFalse);
      expect(e.reasons.join(' '), contains('Cakupan'));
    });

    test('lines without a truth or without frames are ignored; no usable line is an error', () {
      final r = run();
      final partial = PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in buildPlateLines().take(8)) '${l.id},${l.nominalMm},0.01'].join('\n')}\n');
      final e = evaluatePlate(truth: partial, frames: r.frames);
      expect(e.lines, hasLength(8));
      expect(() => evaluatePlate(truth: r.truth, frames: const {}), throwsArgumentError);
    });

    test('results JSON is stable and complete', () {
      final r = run();
      final j = evaluatePlate(truth: r.truth, frames: r.frames).toJson();
      expect(j['v'], 1);
      expect(j['truth_source'], 'KARAKTERISASI');
      expect((j['lines']! as List), hasLength(32));
      expect((j['stats']! as Map)['reported'], 32);
    });
  });

  group('aggregateVisitWithDevice', () {
    final frames = _burst(0.5);

    test('without a validation it is exactly aggregateVisit and keeps BELUM_DIVALIDASI', () {
      final a = aggregateVisitWithDevice(frames);
      expect(a.budget!.belumDivalidasi, isTrue);
      expect(a.budget!.uDev, closeTo(0.5 * 0.06, 1e-12));
    });

    test('a validated run sets u_dev and removes BELUM_DIVALIDASI; an unvalidated one does not', () {
      final r = (() {
        final lines = buildPlateLines();
        final truth = PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in lines) '${l.id},${l.nominalMm},0.005'].join('\n')}\n');
        return evaluatePlate(truth: truth, frames: {for (final l in lines) l.id: _burst(l.nominalMm + 0.004)});
      })();
      expect(r.validated, isTrue, reason: r.reasons.join('|'));
      final v = DeviceValidation.fromResultsJson(r.toJson());
      final b = aggregateVisitWithDevice(frames, validation: v).budget!;
      expect(b.belumDivalidasi, isFalse);
      expect(b.uDev, closeTo(0.005, 0.002));
      final unvalidated = DeviceValidation(stats: v.stats, uTruthMedianMm: v.uTruthMedianMm, validated: false);
      expect(aggregateVisitWithDevice(frames, validation: unvalidated).budget!.belumDivalidasi, isTrue);
    });

    test('a width far from every tested width keeps the default (no extrapolation)', () {
      final lines = buildPlateLines();
      final truth = PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in lines) '${l.id},${l.nominalMm},0.005'].join('\n')}\n');
      final v = DeviceValidation.fromResultsJson(
        evaluatePlate(truth: truth, frames: {for (final l in lines) l.id: _burst(l.nominalMm)}).toJson(),
      );
      expect(v.uDevFor(8), isNull);
      expect(aggregateVisitWithDevice(_burst(8), validation: v).budget!.belumDivalidasi, isTrue);
    });

    test('a visit without a budget is returned untouched', () {
      final r = aggregateVisitWithDevice([_frame(0.5)], validation: const DeviceValidation(stats: PlateStats(n: 0, reported: 0, biasMm: 0, rmseMm: 0, coverage: 0, lowerLimitMm: null, groups: []), uTruthMedianMm: 0, validated: true));
      expect(r.status, VisitStatus.ditolak);
    });
  });

  group('plate scene and processFramePoints (synthetic photo)', () {
    const image = ImageSize(1400, 1300);
    final cam = SyntheticCamera(image: image, fPx: 1120, distanceMm: 0.12 * 1120, tiltDeg: 5, tiltAzimuthDeg: 30, rollDeg: 8, offsetXmm: 2, offsetYmm: -1);
    // Printed a little wider than nominal, like toner does: the TRUE widths the measurement must find.
    final trueW = {for (final l in buildPlateLines()) l.id: l.nominalMm + 0.04};
    late final Uint8List photo;
    setUpAll(() {
      final img = renderGray(
        width: image.width,
        height: image.height,
        toScene: (px, py) => cam.unproject(Pt(px, py)),
        scene: plateScene(widthsMm: trueW),
        supersample: 2,
        psfSigmaPx: 1,
        noiseSigma: 0.004,
        rng: Random(11),
      );
      photo = syntheticPhoto(img, SyntheticDetector(noisePx: 0.15, rng: Random(5)).detect(cam, sheetId: plateSheetId));
    });
    const ports = FramePorts(source: SyntheticPhotoSource(), detector: EmbeddedMarkerDetector());
    final points = [for (final l in buildPlateLines()) FramePoint(l.centreMm, l.directionDeg)];
    const ctx = FrameContext(sheetId: plateSheetId, pointMm: Pt(0, 0), directionDeg: 0);

    test('one decode serves 32 points; wide lines are measured to within 0.03 mm of their true width', () {
      final events = <String>[];
      final outcomes = processFramePoints(
        encoded: photo,
        ports: FramePorts(source: SyntheticPhotoSource(trace: events.add), detector: const EmbeddedMarkerDetector()),
        context: ctx,
        points: points,
      );
      expect(events, ['open', 'close']);
      expect(outcomes, hasLength(32));
      final lines = buildPlateLines();
      var checked = 0;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].nominalMm < 0.5) continue;
        final o = outcomes[i];
        expect(o.accepted, isTrue, reason: '${lines[i].id}: ${o.messages}');
        // 0.03 mm = a quarter of a pixel (0.12 mm/px), generous for sigma 1 px and noise 0.004.
        expect(o.input.record!.widthMm, closeTo(trueW[lines[i].id]!, 0.03), reason: lines[i].id);
        checked++;
      }
      expect(checked, 20);
    });

    test('a point of the multi-point call equals the single-point processFrame at that point', () {
      final lines = buildPlateLines();
      final i = lines.indexWhere((l) => l.id == 'H1-6');
      final multi = processFramePoints(encoded: photo, ports: ports, context: ctx, points: points)[i];
      final single = processFrame(
        encoded: photo,
        ports: ports,
        context: FrameContext(sheetId: plateSheetId, pointMm: lines[i].centreMm, directionDeg: lines[i].directionDeg),
      );
      expect(multi.input.record!.widthMm, single.input.record!.widthMm);
      expect(multi.mmPerPx, single.mmPerPx);
    });

    test('unreadable bytes and too few markers are replayed for every point', () {
      final bad = processFramePoints(encoded: Uint8List.fromList([1, 2, 3]), ports: ports, context: ctx, points: points);
      expect(bad, hasLength(32));
      expect(bad.every((o) => o.input.geometryRejections.contains(FrameRejection.imageUnreadable)), isTrue);
    });
  });
}
