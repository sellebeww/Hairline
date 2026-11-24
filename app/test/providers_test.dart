// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/providers.dart';
import 'package:hairline_core/hairline_core.dart';

import 'support/synthetic_ports.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hairline_prov_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer container() => ProviderContainer(overrides: [
        appDirectoryProvider.overrideWithValue(tmp),
        framePortsFactoryProvider.overrideWithValue(syntheticPorts),
      ]);

  test('the pipeline is wired from overridable providers and uses a real database file in the private directory', () async {
    final c = container();
    final repo = c.read(hairlineRepositoryProvider);
    final site = await repo.createSite(name: 'Uji');
    final crack = await repo.createCrack(
      siteId: site, label: 'A', sheetId: 0, printScale: 1, printScaleURel: 0.003,
      pointMm: const Pt(0, 0), directionDeg: 10, createdAt: DateTime.utc(2026, 11, 17),
    );
    expect((await repo.crackContext(crack)).crack.label, 'A');
    expect(File('${tmp.path}/hairline.sqlite').existsSync(), isTrue);
    expect(c.read(visitProcessorProvider).repository, same(repo));
    expect(c.read(frameStorageProvider), isNotNull);
    c.dispose();
  });

  test('the repositories and processors are single instances per container', () {
    final c = container();
    expect(c.read(visitProcessorProvider), same(c.read(visitProcessorProvider)));
    expect(c.read(frameProcessorProvider), same(c.read(frameProcessorProvider)));
    c.dispose();
  });

  test('an app that did not wire the native ports fails loudly instead of measuring with nothing', () {
    final c = ProviderContainer(overrides: [appDirectoryProvider.overrideWithValue(tmp)]);
    expect(() => c.read(frameProcessorProvider), throwsA(anything));
    c.dispose();
  });

  test('the start-up sweep deletes photo files that no stored frame refers to and keeps the others', () async {
    final c = container();
    final storage = c.read(frameStorageProvider);
    final repo = c.read(hairlineRepositoryProvider);
    final saved = await storage.saveVisitFrames([Uint8List.fromList([1, 2, 3])]);
    final orphan = await storage.saveVisitFrames([Uint8List.fromList([9, 9])]);
    final site = await repo.createSite(name: 'Uji');
    await repo.createCrack(
      siteId: site, label: 'A', sheetId: 0, printScale: 1, printScaleURel: 0.003,
      pointMm: const Pt(0, 0), directionDeg: 10, createdAt: DateTime.utc(2026, 11, 17),
    );
    // No visit refers to either file yet: both are orphans.
    expect(await sweepOrphanFrames(repo, storage), unorderedEquals([saved.single.name, orphan.single.name]));
    expect(await sweepOrphanFrames(repo, storage), isEmpty);
    c.dispose();
  });
}
