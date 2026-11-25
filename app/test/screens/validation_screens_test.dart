// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/router.dart';
import 'package:hairline/sheet/sheet_output.dart';
import 'package:hairline/theme.dart';
import 'package:hairline/validation/validation_providers.dart';
import 'package:hairline_core/hairline_core.dart';

import '../support/seed.dart';

class _Output implements SheetOutput {
  final calls = <String>[];
  @override
  Future<void> print(int sheetId, PaperSize paper) async {}
  @override
  Future<void> share(int sheetId, PaperSize paper) async {}
  @override
  Future<void> printPlate(PaperSize paper) async => calls.add('printPlate ${paper.label}');
  @override
  Future<void> sharePlate(PaperSize paper) async => calls.add('sharePlate ${paper.label}');
}

FrameInput _frame(double w) => FrameInput.accepted(FrameRecord(
      status: MeasureStatus.terukur,
      widthMm: w,
      uFitRawMm: 0.004,
      rho: 1,
      uSigmaWMm: 0.002,
      dwDs: 0,
      mmPerPx: 0.06,
      rmsPx: 0.2,
      looMm: 0.05,
      tiltDeg: 3,
    ));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _text(WidgetTester tester) => [for (final w in tester.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? ''].join('\n');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late ProviderContainer c;
  late _Output output;
  late GoRouter router;

  Future<void> boot(WidgetTester tester, String location) async {
    tester.view
      ..physicalSize = const Size(1080, 4800)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    output = _Output();
    c = memoryContainer(overrides: [sheetOutputProvider.overrideWithValue(output)]);
    router = c.read(routerProvider)..go(location);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(theme: buildTheme(), routerConfig: router)));
    await settle(tester);
  }

  Future<int> seedRun(WidgetTester tester, {required ValidationSource source, required bool characterized, double bias = 0.004}) async {
    late int id;
    await tester.runAsync(() async {
      final lines = buildPlateLines();
      final truth = characterized
          ? PlateTruth.fromCsv('posisi,lebar_mm,u_mm\n${[for (final l in lines) '${l.id},${l.nominalMm},0.005'].join('\n')}\n')
          : PlateTruth.nominal();
      final e = evaluatePlate(
        truth: truth,
        frames: {for (final l in lines) l.id: [for (final d in [-0.003, 0.0, 0.003, 0.0015, -0.0015]) _frame(l.nominalMm + bias + d)]},
      );
      id = await c.read(hairlineRepositoryProvider).saveValidationRun(
            deviceModel: 'Pixel Uji',
            tsUtc: DateTime.utc(2026, 11, 25, 8),
            plateTruthJson: jsonEncode({'v': 1, 'truth': truth.toJson()}),
            resultsJson: jsonEncode(e.toJson()),
            biasMm: e.stats.biasMm,
            rmseMm: e.stats.rmseMm,
            coverage: e.stats.coverage,
            algorithmVersion: measurementAlgorithmVersion,
            source: source,
          );
    });
    return id;
  }

  group('validation setup screen', () {
    testWidgets('the home screen offers it; plate print and share go through the output', (tester) async {
      await boot(tester, '/');
      await tester.tap(find.byTooltip(Strings.validationEntry));
      await settle(tester);
      expect(find.text(Strings.validationTitle), findsWidgets);
      await tester.tap(find.text(Strings.printPlate));
      await tester.tap(find.text(Strings.sharePlate));
      await settle(tester);
      expect(output.calls, ['printPlate A4', 'sharePlate A4']);
    });

    testWidgets('validates the ruler reading, the u_truth and the CSV with specific messages, then starts with the setup', (tester) async {
      await boot(tester, '/validation');
      Future<void> start() async {
        await tester.ensureVisible(find.text(Strings.validationStart));
        await tester.tap(find.text(Strings.validationStart));
        await settle(tester);
      }

      await start();
      expect(find.text(Strings.errRulerNumber), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, Strings.rulerReading), '50');
      await start();
      expect(find.text(Strings.errRulerRange(minRulerReadingMm, maxRulerReadingMm)), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, Strings.rulerReading), '99,5');
      await tester.enterText(find.widgetWithText(TextField, Strings.uTruthField), '5');
      await start();
      expect(find.text(Strings.errUTruth), findsOneWidget);

      await tester.tap(find.text(Strings.truthCsv));
      await settle(tester);
      await start();
      expect(find.text(Strings.errCsvEmpty), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, Strings.truthCsvField), 'a,b,c\n');
      await start();
      expect(find.textContaining('Baris pertama harus persis'), findsOneWidget);
      expect(c.read(validationSetupProvider), isNull);

      final csv = 'posisi,lebar_mm,u_mm\n${[for (final l in buildPlateLines().take(9)) '${l.id},${l.nominalMm},0.01'].join('\n')}\n';
      await tester.enterText(find.widgetWithText(TextField, Strings.truthCsvField), csv);
      await start();
      final setup = c.read(validationSetupProvider)!;
      expect(setup.truth.characterized, isTrue);
      expect(setup.printScale, closeTo(0.995, 1e-9));
    });

    testWidgets('nominal truth with a valid u_truth sets a NOMINAL setup', (tester) async {
      await boot(tester, '/validation');
      await tester.enterText(find.widgetWithText(TextField, Strings.rulerReading), '100');
      await tester.ensureVisible(find.text(Strings.validationStart));
      await tester.tap(find.text(Strings.validationStart));
      await settle(tester);
      final setup = c.read(validationSetupProvider)!;
      expect(setup.truth.source, PlateTruthSource.nominal);
      expect(setup.truth.lines['V1-1']!.uMm, 0.05);
    });

    testWidgets('earlier runs are listed with source and verdict and open their result', (tester) async {
      await boot(tester, '/');
      final id = await seedRun(tester, source: ValidationSource.sintetis, characterized: false);
      router.go('/validation');
      await settle(tester);
      expect(find.textContaining(Strings.validationRunSubtitle('SINTETIS', Strings.truthNominal, false)), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Pixel Uji'));
      await tester.tap(find.textContaining('Pixel Uji'));
      await settle(tester);
      expect(find.text(Strings.validationResultTitle), findsWidgets);
      expect(id, 1);
    });
  });

  group('validation result screen', () {
    testWidgets('SINTETIS and NOMINAL: labelled, never a validation, no "aman"', (tester) async {
      await boot(tester, '/');
      final id = await seedRun(tester, source: ValidationSource.sintetis, characterized: false);
      router.go('/validation/run/$id');
      await settle(tester);
      final t = _text(tester);
      expect(t, contains(Strings.sourceSintetisNote));
      expect(t, contains(Strings.truthNominal));
      expect(t, contains(Strings.verdictNotValidated));
      expect(t, isNot(contains(Strings.verdictValidated)));
      expect(t, contains(Strings.recUseCsv));
      expect(t, contains(Strings.validationScope));
      expect(t.toLowerCase(), isNot(contains('aman')));
      expect(t, contains('Bias'));
    });

    testWidgets('PERANGKAT with a characterized truth that met the thresholds says so, with the per width table', (tester) async {
      await boot(tester, '/');
      final id = await seedRun(tester, source: ValidationSource.perangkat, characterized: true);
      router.go('/validation/run/$id');
      await settle(tester);
      final t = _text(tester);
      expect(t, contains(Strings.sourcePerangkatNote));
      expect(t, contains(Strings.verdictValidated));
      expect(t, contains('Lebar 0,100 mm'));
      expect(t, contains(Strings.validationLowerLimit('0,10')));
    });
  });
}
