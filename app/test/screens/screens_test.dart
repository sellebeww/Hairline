// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline/capture/pending_baseline.dart';
import 'package:hairline/debug/embedded_ports.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline/pipeline/point_locator.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/router.dart';
import 'package:hairline/screens/about_page.dart';
import 'package:hairline/screens/point_overlay.dart';
import 'package:hairline/sheet/sheet_output.dart';
import 'package:hairline/theme.dart';
import 'package:hairline_core/hairline_core.dart';

import '../support/seed.dart';

class _RecordingOutput implements SheetOutput {
  final calls = <String>[];
  @override
  Future<void> print(int sheetId, PaperSize paper) async => calls.add('print $sheetId ${paper.label}');
  @override
  Future<void> share(int sheetId, PaperSize paper) async => calls.add('share $sheetId ${paper.label}');
}

class _FakeLocator extends PointLocator {
  const _FakeLocator() : super(embeddedFramePorts);

  // A photo 1000 x 800 px at 5 px per mm, window centre at (500, 400).
  static const h = <double>[5, 0, 500, 0, 5, 400, 0, 0, 1];

  @override
  Future<PointLocation> locate({required Uint8List photo, required int sheetId, required double printScale, Pt? tapPx}) async {
    const size = ImageSize(1000, 800);
    if (tapPx == null) return const PointLocation(size: size, h: h, markerCount: 4);
    if (tapPx.x < 500) return const PointLocation(size: size, h: h, markerCount: 4, message: 'Retak tidak ditemukan di dekat ketukan.');
    return const PointLocation(size: size, h: h, markerCount: 4, pointMm: Pt(1.5, -2), directionDeg: 20, snr: 12);
  }
}

/// Database futures complete on real time, outside the fake-async zone of `testWidgets`.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

String _allText(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
    ].join('\n');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ProviderContainer c;
  late _RecordingOutput output;
  late GoRouter router;

  Future<void> boot(WidgetTester tester, String location, {double textScale = 1, List<Override> overrides = const [], Future<void> Function()? seed}) async {
    tester.view
      ..physicalSize = const Size(1080, 3600) // tall: ListView builds lazily, everything must be on screen to be found
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    output = _RecordingOutput();
    c = memoryContainer(overrides: [
      sheetOutputProvider.overrideWithValue(output),
      framePortsFactoryProvider.overrideWithValue(embeddedFramePorts),
      ...overrides,
    ]);
    if (seed != null) await tester.runAsync(seed);
    router = c.read(routerProvider)..go(location);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: buildTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      ),
    ));
    await settle(tester);
  }

  group('sites and cracks', () {
    testWidgets('empty list, then add a site (name required, location optional and paired) and land on its cracks', (tester) async {
      await boot(tester, '/');
      expect(find.text(Strings.sitesEmpty), findsOneWidget);
      await tester.tap(find.text(Strings.addSite));
      await settle(tester);
      await tester.tap(find.text(Strings.save));
      await settle(tester);
      expect(find.text(Strings.errSiteName), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, Strings.siteName), 'Rumah Contoh');
      await tester.enterText(find.widgetWithText(TextFormField, Strings.siteLat), '95');
      await tester.tap(find.text(Strings.save));
      await settle(tester);
      expect(find.text(Strings.errLat), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, Strings.siteLat), '-6,2');
      await tester.tap(find.text(Strings.save));
      await settle(tester);
      expect(find.text(Strings.errLatLonPair), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, Strings.siteLon), '106,8');
      await tester.tap(find.text(Strings.save));
      await settle(tester);
      expect(find.text(Strings.cracksTitle('Rumah Contoh')), findsOneWidget);
      expect(find.text(Strings.cracksEmpty), findsOneWidget);
      final site = (await tester.runAsync(() => c.read(hairlineRepositoryProvider).allSites()))!.single;
      expect(site.lat, closeTo(-6.2, 1e-9));
      expect(site.lon, closeTo(106.8, 1e-9));
    });

    testWidgets('the site list shows sites and opens their cracks; help and about open from the app bar', (tester) async {
      await boot(tester, '/', seed: () async => seedCrack(c.read(hairlineRepositoryProvider)));
      expect(find.text('Rumah Contoh'), findsOneWidget);
      await tester.tap(find.byTooltip(Strings.menuHelp));
      await settle(tester);
      expect(find.text(Strings.helpHowTitle), findsOneWidget);
      router.go('/about');
      await settle(tester);
      expect(find.text(Strings.aboutOwner), findsOneWidget);
      router.go('/');
      await settle(tester);
      await tester.tap(find.text('Rumah Contoh'));
      await settle(tester);
      expect(find.text('Retak dinding'), findsOneWidget);
      expect(find.text(Strings.crackNoBaseline), findsOneWidget);
    });

    testWidgets('guided setup: print buttons, ruler validation, print_scale from the reading, relief, crack saved', (tester) async {
      await boot(tester, '/sites/1/cracks/new', seed: () async => c.read(hairlineRepositoryProvider).createSite(name: 'Situs'));
      expect(find.text(Strings.setupStepOf(1, 6)), findsOneWidget);
      FilledButton next() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, Strings.next));
      expect(next().onPressed, isNull, reason: 'a label is required');
      await tester.enterText(find.byType(TextField).first, 'Dinding timur');
      await tester.pump();
      await tester.tap(find.text(Strings.next));
      await settle(tester);

      // Step 2: print and share go to the output with the chosen paper.
      expect(find.text(Strings.setupPrintTitle), findsOneWidget);
      await tester.tap(find.text(Strings.printSheet));
      await settle(tester);
      await tester.tap(find.text('Letter'));
      await settle(tester);
      await tester.tap(find.text(Strings.shareSheet));
      await settle(tester);
      expect(output.calls, ['print 0 A4', 'share 0 Letter']);
      await tester.tap(find.text(Strings.next));
      await settle(tester);

      // Step 3: the ruler reading gates the next step.
      expect(next().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.text(Strings.errRulerNumber), findsOneWidget);
      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      expect(find.text(Strings.errRulerRange(80, 120)), findsOneWidget);
      expect(next().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '99,5');
      await tester.pump();
      expect(find.textContaining('Skala cetak 0,9950'), findsOneWidget);
      await tester.tap(find.text(Strings.next));
      await settle(tester);

      expect(find.text(Strings.setupCutTitle), findsOneWidget);
      await tester.tap(find.text(Strings.next));
      await settle(tester);
      expect(find.text(Strings.setupMountTitle), findsOneWidget);
      expect(find.text(Strings.setupMountWarning), findsOneWidget);
      await tester.tap(find.text(Strings.next));
      await settle(tester);
      await tester.tap(find.text(Strings.reliefRough));
      await settle(tester);
      await tester.tap(find.text(Strings.setupFinish));
      await settle(tester);

      final crack = (await tester.runAsync(() => c.read(hairlineRepositoryProvider).cracksOfSite(1)))!.single;
      expect(crack.label, 'Dinding timur');
      expect(crack.printScale, closeTo(0.995, 1e-12));
      expect(crack.printScaleURel, closeTo((0.5 / 1.7320508075688772) / 99.5, 1e-9));
      expect(crack.reliefMm, 1.0);
      expect(find.text(Strings.crackDetailTitle), findsOneWidget);
      expect(find.text(Strings.noVisits), findsOneWidget);
      expect(find.text(Strings.newBaselineVisit), findsOneWidget);
      expect(find.text(Strings.seriesBrokenNote), findsOneWidget);
    });

    testWidgets('crack detail lists visits with their results and offers the trend from two visits on', (tester) async {
      await boot(tester, '/cracks/1', seed: () async {
        final repo = c.read(hairlineRepositoryProvider);
        final id = await seedCrack(repo);
        await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 2), kind: 'baseline', width: 0.612, uExpanded: 0.05);
        await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 20), status: VisitStatus.dibawahBatasUkur, floorMm: 0.07);
      });
      expect(find.text(Strings.visitBaseline), findsOneWidget);
      expect(find.text(Strings.visitFollowup), findsOneWidget);
      expect(find.textContaining(Strings.resultWidthHeadline(0.612, 0.05)), findsOneWidget);
      expect(find.textContaining(Strings.belowFloor(0.07)), findsOneWidget);
      expect(find.text(Strings.newFollowupVisit), findsOneWidget);
      expect(find.text(Strings.viewTrend), findsOneWidget);
    });
  });

  group('result screen', () {
    testWidgets('a measured width: w ± U, k, mm per pixel, frames, BELUM_DIVALIDASI, components, honest statements, no "aman"', (tester) async {
      await boot(tester, '/result/1', seed: () async {
        final repo = c.read(hairlineRepositoryProvider);
        final id = await seedCrack(repo);
        await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 2), kind: 'baseline', width: 0.612, uExpanded: 0.0504);
      });
      expect(find.text(Strings.resultWidthHeadline(0.612, 0.0504)), findsOneWidget);
      expect(find.text(Strings.kFactor(2.1)), findsWidgets);
      expect(find.text(Strings.resultMmPerPx(0.11)), findsOneWidget);
      expect(find.text(Strings.resultFramesAccepted(5)), findsOneWidget);
      expect(find.text(Strings.notValidatedBadge), findsOneWidget);
      expect(find.text(Strings.resultBaselineNote), findsOneWidget);
      expect(find.text(Strings.componentLabel('u_dev')), findsNothing, reason: 'components are collapsed');
      await tester.dragUntilVisible(find.text(Strings.componentsTitle), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text(Strings.componentsTitle));
      await settle(tester);
      expect(find.text(Strings.componentLabel('u_dev')), findsOneWidget);
      await tester.dragUntilVisible(find.text(Strings.honestyIndicative), find.byType(ListView), const Offset(0, -300));
      for (final t in [Strings.honestyIndicative, Strings.honestyEngineer, Strings.honestyNoChange, Strings.honestyAccuracy, Strings.honestyCoplanar]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(_allText(tester).toLowerCase(), isNot(matches(RegExp(r'\baman\b'))));
    });

    testWidgets('below the floor: no width number; not measurable: reason shown, no number', (tester) async {
      await boot(tester, '/result/1', seed: () async {
        final repo = c.read(hairlineRepositoryProvider);
        final id = await seedCrack(repo);
        await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 2), kind: 'baseline', status: VisitStatus.dibawahBatasUkur, width: 0.03, floorMm: 0.071);
        await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 9), status: VisitStatus.tidakTerukur);
      });
      expect(find.text(Strings.belowFloor(0.071)), findsOneWidget);
      expect(find.text(Strings.resultBelowFloorMeaning), findsOneWidget);
      expect(find.textContaining('±'), findsNothing);
      router.go('/result/2');
      await settle(tester);
      expect(find.text(Strings.statusNotMeasurable), findsOneWidget);
      expect(find.text(Strings.reasonMostlyUnmeasurable), findsOneWidget);
      expect(find.textContaining('±'), findsNothing);
      expect(find.text(Strings.notValidatedBadge), findsOneWidget);
    });

    testWidgets('an unknown visit says so', (tester) async {
      await boot(tester, '/result/99');
      expect(find.text(Strings.resultNotFound), findsOneWidget);
    });
  });

  group('trend screen', () {
    Future<void> three(List<double> widths, {String? device2, String? version2}) async {
      final repo = c.read(hairlineRepositoryProvider);
      final id = await seedCrack(repo);
      for (var i = 0; i < widths.length; i++) {
        await seedVisit(
          repo,
          id,
          ts: DateTime.utc(2026, 11, 2 + 7 * i),
          kind: i == 0 ? 'baseline' : 'followup',
          width: widths[i],
          uRand: 0.02,
          device: i == 1 && device2 != null ? device2 : 'Pixel 7',
          version: i == 1 && version2 != null ? version2 : measurementAlgorithmVersion,
        );
      }
    }

    testWidgets('classifies each visit in the words of 5.6, shows delta and MDC, no regression', (tester) async {
      await boot(tester, '/trend/1', seed: () => three([0.5, 0.51, 1.2]));
      expect(find.text(Strings.trendClass(TrendClass.tidakAdaPerubahanTerdeteksi)), findsWidgets);
      expect(find.text(Strings.trendClass(TrendClass.kemungkinanBertambahLebar)), findsWidgets);
      expect(find.text(Strings.trendClassNoneNote), findsWidgets);
      expect(find.textContaining('Perubahan minimum yang dapat dideteksi (MDC)'), findsWidgets);
      expect(find.text(Strings.trendNoForecast), findsOneWidget);
      expect(find.text(Strings.trendBaselineTag), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Grafik lebar retak')), findsOneWidget);
      expect(_allText(tester).toLowerCase(), isNot(matches(RegExp(r'\baman\b'))));
      expect(find.text(Strings.reprocessUpToDate(measurementAlgorithmVersion)), findsOneWidget);
    });

    testWidgets('one visit asks for another', (tester) async {
      await boot(tester, '/trend/1', seed: () => three([0.9]));
      expect(find.text(Strings.trendNeedTwo), findsOneWidget);
    });

    testWidgets('a narrowing crack is named; context warnings appear', (tester) async {
      await boot(tester, '/trend/1', seed: () => three([1.2, 0.5], device2: 'Galaxy S22', version2: 'p9-0'));
      expect(find.text(Strings.trendClass(TrendClass.kemungkinanMenyempit)), findsWidgets);
      expect(find.text(Strings.contextWarning(ContextWarning.deviceModelDiffers)), findsOneWidget);
      expect(find.text(Strings.contextWarning(ContextWarning.algorithmVersionDiffers)), findsOneWidget);
    });

    testWidgets('a newer algorithm version offers reprocessing; a visit that cannot be reprocessed is reported', (tester) async {
      await boot(tester, '/trend/1', overrides: [currentAlgorithmVersionProvider.overrideWithValue('p9-0')], seed: () => three([0.5, 0.9]));
      expect(find.text(Strings.reprocessBody), findsOneWidget);
      await tester.dragUntilVisible(find.widgetWithText(FilledButton, Strings.reprocess), find.byType(ListView), const Offset(0, -300));
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, Strings.reprocess));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settle(tester);
      // The seeded visits have no stored photos, so nothing can be measured again: reported, not hidden.
      expect(find.text(Strings.reprocessDone(0, 2)), findsOneWidget);
    });
  });

  group('measurement point screen', () {
    PendingBaseline pending() => PendingBaseline(
          crackId: 1,
          photos: [Uint8List(8)],
          bestIndex: 0,
          deviceModel: 'Pixel 7',
          camera: const CameraInfo(),
          referencePoseJson: null,
        );

    testWidgets('tap on nothing explains; tap on the crack shows direction and enables the confirm button', (tester) async {
      await boot(tester, '/point/1', overrides: [pointLocatorProvider.overrideWithValue(const _FakeLocator())], seed: () async {
        await seedCrack(c.read(hairlineRepositoryProvider));
        c.read(pendingBaselinesProvider.notifier).put(pending());
      });
      FilledButton confirm() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, Strings.pointConfirm));
      expect(find.text(Strings.pointInstruction), findsOneWidget);
      expect(confirm().onPressed, isNull);

      final photo = tester.getTopLeft(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PointOverlayPainter));
      await tester.tapAt(photo + const Offset(10, 10)); // left half: the fake finds no crack
      await settle(tester);
      expect(find.textContaining('Retak tidak ditemukan'), findsOneWidget);
      expect(confirm().onPressed, isNull);

      await tester.tapAt(photo + const Offset(300, 100));
      await settle(tester);
      expect(find.text(Strings.pointDirection(20)), findsOneWidget);
      expect(find.text(Strings.pointCoordinates(1.5, -2)), findsOneWidget);
      expect(find.text(Strings.pointSegmentCaption), findsOneWidget);
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('without the baseline photos in memory the screen says so and offers a new capture', (tester) async {
      await boot(tester, '/point/1', seed: () async => seedCrack(c.read(hairlineRepositoryProvider)));
      expect(find.text(Strings.pointNoPending), findsOneWidget);
      expect(find.text(Strings.pointRecapture), findsOneWidget);
    });

    test('overlay geometry: window 70 mm and zone 50 mm project through H; the 4 mm segment follows the direction', () {
      const h = _FakeLocator.h; // 5 px per mm, centre (500, 400)
      final w = projectSquare(h, windowHalfSizeMm, 1);
      expect(w.first.x, closeTo(500 - 175, 1e-9));
      expect(w.first.y, closeTo(400 - 175, 1e-9));
      expect(w[2].x - w[0].x, closeTo(350, 1e-9));
      final z = projectSquare(h, measurementZoneHalfMm, 1);
      expect(z[2].x - z[0].x, closeTo(250, 1e-9));
      final (a, b) = projectSegment(h, const Pt(0, 0), 0, 1);
      expect(b.x - a.x, closeTo(20, 1e-9), reason: '4 mm x 5 px/mm');
      expect(a.y, closeTo(400, 1e-9));
      final (c1, c2) = projectSegment(h, const Pt(0, 0), 90, 1);
      expect(c2.y - c1.y, closeTo(20, 1e-9));
      final (s1, s2) = projectSegment(h, const Pt(0, 0), 0, 0.5);
      expect(s2.x - s1.x, closeTo(10, 1e-9), reason: 'print scale shrinks the segment');
    });
  });

  group('about and accessibility', () {
    testWidgets('the about version equals pubspec.yaml', (tester) async {
      await boot(tester, '/about');
      expect(find.text(Strings.aboutVersion(appVersion)), findsOneWidget);
      expect(find.text(Strings.aboutLicense), findsOneWidget);
    });

    for (final path in ['/', '/help', '/about', '/result/1', '/trend/1', '/cracks/1', '/sites/1/cracks/new', '/point/1']) {
      testWidgets('$path at 2x text scale: no overflow, and semantics (labels) are built', (tester) async {
        final handle = tester.ensureSemantics();
        await boot(tester, path, textScale: 2, seed: () async {
          final repo = c.read(hairlineRepositoryProvider);
          final id = await seedCrack(repo);
          await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 2), kind: 'baseline', width: 0.612);
          await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 9), width: 1.3);
        });
        expect(tester.takeException(), isNull);
        handle.dispose();
      });
    }
  });
}
