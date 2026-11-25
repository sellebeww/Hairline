// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hairline/data/database.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline/providers.dart';
import 'package:hairline/theme.dart';
import 'package:hairline_core/hairline_core.dart';

/// In-memory database container for screen tests (no files, no isolates).
ProviderContainer memoryContainer({List<Override> overrides = const []}) {
  final db = AppDatabase(NativeDatabase.memory());
  final dir = Directory.systemTemp.createTempSync('hairline_screen_');
  final c = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    appDirectoryProvider.overrideWithValue(dir),
    ...overrides,
  ]);
  addTearDown(() {
    c.dispose();
    dir.deleteSync(recursive: true);
    return db.close();
  });
  return c;
}

Widget app(ProviderContainer c, Widget home, {double textScale = 1}) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
        home: home,
      ),
    );

Future<int> seedCrack(HairlineRepository repo, {String label = 'Retak dinding', int sheet = 0}) async {
  final site = await repo.createSite(name: 'Rumah Contoh');
  return repo.createCrack(
    siteId: site,
    label: label,
    sheetId: sheet,
    printScale: 1,
    printScaleURel: 0.003,
    pointMm: const Pt(0, 0),
    directionDeg: 25,
    createdAt: DateTime.utc(2026, 11, 1),
  );
}

/// Stores a visit with a given aggregate result (no frames), as the processor would.
Future<int> seedVisit(
  HairlineRepository repo,
  int crackId, {
  required DateTime ts,
  String kind = 'followup',
  VisitStatus status = VisitStatus.terukur,
  double? width,
  double uRand = 0.02,
  double uExpanded = 0.05,
  double floorMm = 0.05,
  String version = measurementAlgorithmVersion,
  String device = 'Pixel 7',
  bool validated = false,
  Map<String, int> frameWarnings = const {},
}) {
  final numeric = status == VisitStatus.terukur;
  final budget = status == VisitStatus.tidakTerukur
      ? null
      : {
          'n': 5,
          'width_mm': width,
          'u_fit_mean': 0.01, 'u_repeat': 0.012, 'u_stat': 0.012, 'u_sigma_w': 0.01, 'u_pos': 0.0, 'u_par': 0.003, 'u_geo': 0.001,
          'u_print': 0.002, 'u_dev': 0.06, 'u_rand': uRand, 'u_sys': 0.06, 'u_c': 0.065, 'k': 2.1, 'u_expanded': uExpanded,
          'floor_mm': floorMm, 'mm_per_px': 0.11, 'belum_divalidasi': !validated,
        };
  return repo.saveVisit(VisitDraft(
    crackId: crackId,
    tsUtc: ts,
    kind: kind,
    deviceModel: device,
    cameraInfoJson: '{"flags":[]}',
    algorithmVersion: version,
    frames: const [],
    aggregate: MeasurementDraft(
      isAggregate: true,
      status: status.code,
      widthMm: numeric ? width : null,
      uRand: numeric ? uRand : null,
      uSys: numeric ? 0.06 : null,
      uExpanded: numeric ? uExpanded : null,
      k: numeric ? 2.1 : null,
      componentsJson: jsonEncode({
        'algorithm_version': version,
        'budget': budget,
        'issue': status == VisitStatus.tidakTerukur ? VisitIssue.mostlyUnmeasurable.code : null,
        'accepted_frames': 5,
        'frame_rejections': const <Object>[],
        'frame_warnings': frameWarnings,
      }),
    ),
  ));
}
