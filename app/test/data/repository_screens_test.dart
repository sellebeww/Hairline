// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/screens/about_page.dart';
import 'package:hairline_core/hairline_core.dart';

import '../support/seed.dart';

void main() {
  test('sites sort by name; cracks of a site in creation order', () async {
    final repo = memoryContainer().read(hairlineRepositoryProvider);
    await repo.createSite(name: 'Zeta');
    final a = await repo.createSite(name: 'Alfa');
    expect((await repo.allSites()).map((s) => s.name), ['Alfa', 'Zeta']);
    expect((await repo.site(a))!.name, 'Alfa');
    expect(await repo.site(99), isNull);
    expect(await repo.cracksOfSite(a), isEmpty);
  });

  test('the measurement point moves only before the first visit exists', () async {
    final repo = memoryContainer().read(hairlineRepositoryProvider);
    final id = await seedCrack(repo);
    await repo.updateCrackPoint(crackId: id, pointMm: const Pt(2, -3), directionDeg: 40);
    final p = (await repo.crackContext(id)).point;
    expect((p.xMm, p.yMm, p.directionDeg), (2, -3, 40));
    await seedVisit(repo, id, ts: DateTime.utc(2026, 11, 2), kind: 'baseline', width: 0.5);
    expect(
      repo.updateCrackPoint(crackId: id, pointMm: const Pt(0, 0), directionDeg: 0),
      throwsA(isA<RepositoryException>()),
    );
    expect((await repo.crackContext(id)).point.xMm, 2);
  });

  test('the about version constant equals pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(RegExp(r'[: +]+'))[1], appVersion);
  });
}
