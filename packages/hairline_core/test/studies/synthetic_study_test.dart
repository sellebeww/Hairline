// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';
import 'package:test/test.dart';

String dump(List<FrameInput> v) => jsonEncode([for (final f in v) frameInputToJson(f)]);

void main() {
  group('grid', () {
    final g = studyGrid();

    test('6 widths x 4 scales x 4 blurs x 3 noises x 3 tilts = 864 distinct conditions, index = position', () {
      expect(g.length, 6 * 4 * 4 * 3 * 3);
      expect({for (final c in g) '${c.widthMm}/${c.mmPerPx}/${c.sigmaPx}/${c.noise}/${c.tiltDeg}'}.length, 864);
      for (var i = 0; i < g.length; i++) {
        expect(g[i].index, i);
      }
    });

    test('values are the ones of the specification', () {
      expect(studyWidthsMm, [0.1, 0.2, 0.3, 0.5, 1.0, 2.0]);
      expect(studyMmPerPx, [0.04, 0.06, 0.10, 0.15]);
      expect(studySigmasPx, [0.6, 1.0, 1.5, 2.0]);
      expect(studyNoises, [1, 3, 6]);
      expect(studyTiltsDeg, [0, 10, 20]);
    });

    test('the setting key ignores the width', () {
      expect(g.where((c) => c.settingKey == g[0].settingKey).length, 6);
    });
  });

  group('codec', () {
    test('frame inputs survive a JSON round trip exactly (accepted, geometry and measure rejections)', () {
      final frames = <FrameInput>[
        FrameInput.accepted(const FrameRecord(
          status: MeasureStatus.dibawahBatasUkur,
          widthMm: 0.123456789012345,
          uFitRawMm: 0.004,
          rho: 2.5,
          uSigmaWMm: 0.003,
          dwDs: double.nan,
          mmPerPx: 0.06,
          rmsPx: 0.31,
          looMm: 0.07,
          tiltDeg: 12.5,
        )),
        const FrameInput.accepted(FrameRecord(status: MeasureStatus.terukur, widthMm: 1, uFitRawMm: 0, rho: 1, uSigmaWMm: 0, dwDs: -0.01, mmPerPx: 0.1, rmsPx: 0.1, looMm: null, tiltDeg: 0)),
        const FrameInput.rejected(geometry: [FrameRejection.tiltTooHigh, FrameRejection.looTooHigh]),
        const FrameInput.rejected(measure: RejectReason.blurTooLarge),
      ];
      final text = dump(frames);
      final back = [for (final j in jsonDecode(text) as List<Object?>) frameInputFromJson(j! as Map<String, Object?>)];
      expect(dump(back), text);
      expect(back[0].record!.dwDs.isNaN, isTrue);
      expect(back[1].record!.looMm, isNull);
      expect(back[2].rejectionCodes, ['TILT_TOO_HIGH', 'LOO_TOO_HIGH']);
      expect(back[3].measureRejection, RejectReason.blurTooLarge);
    });
  });

  group('simulation (one condition, real chain)', () {
    // 1.0 mm crack, 0.10 mm/px, sigma 1 px, noise 1 grey level, no tilt.
    final c = studyGrid().firstWhere((c) => c.widthMm == 1.0 && c.mmPerPx == 0.10 && c.sigmaPx == 1.0 && c.noise == 1 && c.tiltDeg == 0);
    final v0 = simulateVisit(c, 0);

    test('a visit is a burst of 5 frames', () => expect(v0.length, 5));

    test('is deterministic in (seed, condition, replication) and differs between replications', () {
      expect(dump(simulateVisit(c, 0)), dump(v0));
      expect(dump(simulateVisit(c, 1)), isNot(dump(v0)));
    });

    test('an easy condition yields an accepted visit whose width is close to the truth', () {
      final v = replayVisit(c, 0, v0, rho: 1);
      expect(v.result.status, VisitStatus.terukur);
      expect(v.errorMm!.abs(), lessThan(0.02));
      expect(v.covered, isTrue);
    });

    test('replaying with a larger rho widens the budget and never narrows it', () {
      final a = replayVisit(c, 0, v0, rho: 1).result.budget!;
      final b = replayVisit(c, 0, v0, rho: 16).result.budget!;
      expect(b.uFitMean, closeTo(4 * a.uFitMean, 1e-12));
      expect(b.uC, greaterThanOrEqualTo(a.uC));
      expect(b.widthMm, a.widthMm);
    });

    test('summary and lower limit are computed over visits', () {
      final vs = [replayVisit(c, 0, v0, rho: 1)];
      final s = summarizeCondition(c, vs);
      expect(s.visits, 1);
      expect(s.terukur, 1);
      expect(s.coverage, 1.0);
      expect(s.biasMm, closeTo(vs.single.errorMm!, 1e-15));
      expect(settingLowerLimit(vs), 1.0);
    });
  });

  group('empirical limit ignores visits rejected by the gate (the user retakes them)', () {
    FrameInput good(double w) => FrameInput.accepted(FrameRecord(
          status: MeasureStatus.terukur,
          widthMm: w,
          uFitRawMm: 0.004,
          rho: 1,
          uSigmaWMm: 0.003,
          dwDs: 0.01,
          mmPerPx: 0.04,
          rmsPx: 0.3,
          looMm: null,
          tiltDeg: 0,
        ));
    final g = studyGrid();
    final c05 = g.firstWhere((c) => c.widthMm == 0.5 && c.mmPerPx == 0.04 && c.sigmaPx == 0.6 && c.noise == 1 && c.tiltDeg == 0);
    final c10 = g.firstWhere((c) => c.settingKey == c05.settingKey && c.widthMm == 1.0);
    StudyVisit v(StudyCondition c, int rep, List<FrameInput> f) => replayVisit(c, rep, f, rho: 1);

    test('a rejected visit at 0.5 mm does not make 0.5 mm unreliable', () {
      final ok = [good(0.5), good(0.5), good(0.5)];
      final rejected = [good(0.5), const FrameInput.rejected(geometry: [FrameRejection.tiltTooHigh])];
      final visits = [v(c05, 0, ok), v(c05, 1, rejected), v(c10, 0, [good(1.0), good(1.0), good(1.0)])];
      expect(visits[1].result.status, VisitStatus.ditolak);
      expect(settingLowerLimit(visits), 0.5);
    });
  });
}
