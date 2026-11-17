// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/data/database.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline_core/hairline_core.dart';

MeasurementDraft _m({bool aggregate = false, String status = 'TERUKUR', double? width = 0.5}) => MeasurementDraft(
      isAggregate: aggregate,
      status: status,
      widthMm: width,
      uRand: 0.01,
      uSys: 0.02,
      uExpanded: 0.05,
      k: 2.1,
      componentsJson: '{}',
    );

FrameDraft _f(String path) => FrameDraft(
      path: path,
      sha256: 'ab' * 32,
      homographyJson: '{}',
      rmsPx: 0.2,
      looMm: 0.05,
      sigmaMm: 0.1,
      tiltDeg: 5,
      mmPerPx: 0.1,
      qualityJson: '{}',
      measurement: _m(),
    );

VisitDraft _visit(int crackId, List<FrameDraft> frames, {String version = 'v1'}) => VisitDraft(
      crackId: crackId,
      tsUtc: DateTime.utc(2026, 11, 17, 8),
      kind: 'baseline',
      deviceModel: 'Pixel 7',
      cameraInfoJson: '{}',
      algorithmVersion: version,
      frames: frames,
      aggregate: _m(aggregate: true),
    );

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // the migration tests reopen files on purpose
  late AppDatabase db;
  late HairlineRepository repo;
  late int crackId;

  Future<void> seed() async {
    final site = await repo.createSite(name: 'Rumah');
    crackId = await repo.createCrack(
      siteId: site,
      label: 'Dinding utara',
      sheetId: 3,
      printScale: 1.002,
      printScaleURel: 0.003,
      pointMm: const Pt(1, -2),
      directionDeg: 30,
      createdAt: DateTime.utc(2026, 11, 1),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = HairlineRepository(db);
    await seed();
  });
  tearDown(() => db.close());

  group('schema (CLAUDE.md 5.7)', () {
    test('has exactly the seven tables, no alerts or reports, and the planned indexes', () async {
      final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(tables, {'sites', 'cracks', 'crack_points', 'visits', 'frames', 'measurements', 'validation_runs'});
      final indexes = (await db.customSelect("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'").get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(indexes, {
        'idx_cracks_site',
        'idx_crack_points_crack',
        'idx_visits_crack_ts',
        'idx_frames_visit',
        'idx_measurements_visit_version',
        'idx_validation_runs_device_ts',
      });
    });

    test('columns follow 5.7', () async {
      Future<Set<String>> cols(String t) async =>
          (await db.customSelect('PRAGMA table_info($t)').get()).map((r) => r.read<String>('name')).toSet();
      expect(await cols('sites'), {'id', 'name', 'lat', 'lon', 'notes'});
      expect(await cols('cracks'), {'id', 'site_id', 'label', 'sheet_id', 'print_scale', 'print_scale_u_rel', 'relief_mm', 'created_at'});
      expect(await cols('crack_points'), {'id', 'crack_id', 'x_mm', 'y_mm', 'direction_deg'});
      expect(await cols('visits'), {'id', 'crack_id', 'ts_utc', 'kind', 'device_model', 'camera_info_json', 'reference_pose_json'});
      expect(await cols('frames'), {
        'id', 'visit_id', 'path', 'sha256', 'homography_json', 'rms_px', 'loo_mm', 'sigma_mm', 'tilt_deg', 'mm_per_px', 'quality_json', 'accepted',
      });
      expect(await cols('measurements'), {
        'id', 'visit_id', 'point_id', 'frame_id', 'is_aggregate', 'algorithm_version', 'width_mm', 'u_rand', 'u_sys', 'u_expanded', 'k',
        'components_json', 'status',
      });
      expect(await cols('validation_runs'), {
        'id', 'device_model', 'ts_utc', 'plate_truth_json', 'results_json', 'bias_mm', 'rmse_mm', 'coverage', 'algorithm_version', 'source',
      });
    });

    test('timestamps are UTC and must be given as UTC', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      expect((await repo.visit(id))!.tsUtc.toUtc(), DateTime.utc(2026, 11, 17, 8));
      expect(
        () => repo.createCrack(
          siteId: 1, label: 'x', sheetId: 0, printScale: 1, printScaleURel: 0.003,
          pointMm: const Pt(0, 0), directionDeg: 0, createdAt: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('foreign keys', () {
    test('are enforced on the connection', () async {
      final on = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(on.read<int>('foreign_keys'), 1);
    });

    test('a crack for a missing site, a visit for a missing crack, a measurement for a missing frame are refused', () async {
      await expectLater(
        db.into(db.cracks).insert(CracksCompanion.insert(
              siteId: 999, label: 'x', sheetId: 0, printScale: 1, printScaleURel: 0.003, createdAt: DateTime.utc(2026)),
            ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db.into(db.visits).insert(VisitsCompanion.insert(
              crackId: 999, tsUtc: DateTime.utc(2026), kind: 'baseline', deviceModel: 'x', cameraInfoJson: '{}'),
            ),
        throwsA(isA<SqliteException>()),
      );
      final v = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      await expectLater(
        db.into(db.measurements).insert(MeasurementsCompanion.insert(
              visitId: v, pointId: 1, frameId: const Value(999), isAggregate: false, algorithmVersion: 'v1', componentsJson: '{}', status: 'TERUKUR'),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('RESTRICT: a visit with frames or measurements cannot be deleted underneath them', () async {
      final v = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      await expectLater(db.customStatement('DELETE FROM visits WHERE id = $v'), throwsA(isA<SqliteException>()));
      await expectLater(db.customStatement('DELETE FROM cracks WHERE id = $crackId'), throwsA(isA<SqliteException>()));
      expect(await _count(db, 'visits'), 1);
    });

    test('sheet id and print scale have range checks', () async {
      await expectLater(
        repo.createCrack(
          siteId: 1, label: 'x', sheetId: 12, printScale: 1, printScaleURel: 0.003,
          pointMm: const Pt(0, 0), directionDeg: 0, createdAt: DateTime.utc(2026),
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('crack and point', () {
    test('createCrack stores exactly one point; a second point is refused', () async {
      final ctx = await repo.crackContext(crackId);
      expect(ctx.point.xMm, 1);
      expect(ctx.crack.reliefMm, 0.3);
      await expectLater(
        repo.addCrackPoint(crackId: crackId, pointMm: const Pt(0, 0), directionDeg: 0),
        throwsA(isA<RepositoryException>()),
      );
      expect(await _count(db, 'crack_points'), 1);
    });
  });

  group('saving a visit', () {
    test('writes visit, frames, per-frame and aggregate measurements together', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg'), _f('b.jpg'), _f('c.jpg')]));
      expect((await repo.framesOfVisit(id)).map((f) => f.path), ['a.jpg', 'b.jpg', 'c.jpg']);
      final ms = await repo.measurementsOfVisit(id);
      expect(ms.where((m) => m.isAggregate), hasLength(1));
      expect(ms.where((m) => !m.isAggregate && m.frameId != null), hasLength(3));
      expect(ms.every((m) => m.algorithmVersion == 'v1'), isTrue);
    });

    test('is atomic: a failure in the middle leaves nothing behind', () async {
      // The second frame reuses the path of the first (UNIQUE), so the insert fails after
      // the visit row and the first frame were already written inside the transaction.
      await expectLater(repo.saveVisit(_visit(crackId, [_f('dup.jpg'), _f('dup.jpg')])), throwsA(isA<SqliteException>()));
      for (final t in ['visits', 'frames', 'measurements']) {
        expect(await _count(db, t), 0, reason: t);
      }
    });

    test('more than 5 frames are refused before anything is written', () async {
      final six = [for (var i = 0; i < 6; i++) _f('f$i.jpg')];
      await expectLater(repo.saveVisit(_visit(crackId, six)), throwsA(isA<RepositoryException>()));
      expect(await _count(db, 'visits'), 0);
    });

    test('a visit for an unknown crack is refused', () async {
      await expectLater(repo.saveVisit(_visit(999, [_f('a.jpg')])), throwsA(isA<RepositoryException>()));
      expect(await _count(db, 'visits'), 0);
    });
  });

  group('reprocessing', () {
    test('adds rows under a new algorithm version and never touches the old ones', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg'), _f('b.jpg'), _f('c.jpg')]));
      final before = await repo.measurementsOfVisit(id);
      final frames = await repo.framesOfVisit(id);
      await repo.addReprocessedMeasurements(
        visitId: id,
        algorithmVersion: 'v2',
        aggregate: _m(aggregate: true, width: 0.61),
        perFrame: {for (final f in frames) f.id: _m(width: 0.6)},
      );
      final after = await repo.measurementsOfVisit(id);
      expect(after, hasLength(before.length * 2));
      // Old rows are byte-for-byte the same (data classes compare by value).
      expect(after.take(before.length).toList(), before);
      expect((await repo.measurementsOfVisit(id, algorithmVersion: 'v1')), before);
      final v2 = await repo.measurementsOfVisit(id, algorithmVersion: 'v2');
      expect(v2.where((m) => m.isAggregate).single.widthMm, 0.61);
      expect((await repo.aggregatesOfVisit(id)).map((m) => m.algorithmVersion), ['v1', 'v2']);
    });

    test('the same version twice is refused; an unknown visit is refused', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      await expectLater(
        repo.addReprocessedMeasurements(visitId: id, algorithmVersion: 'v1', aggregate: _m(aggregate: true), perFrame: const {}),
        throwsA(isA<RepositoryException>()),
      );
      await expectLater(
        repo.addReprocessedMeasurements(visitId: 999, algorithmVersion: 'v2', aggregate: _m(aggregate: true), perFrame: const {}),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('a failed reprocessing adds nothing (all or nothing)', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      final before = await repo.measurementsOfVisit(id);
      await expectLater(
        repo.addReprocessedMeasurements(visitId: id, algorithmVersion: 'v2', aggregate: _m(aggregate: true), perFrame: {999: _m()}),
        throwsA(isA<SqliteException>()),
      );
      expect(await repo.measurementsOfVisit(id), before);
    });
  });

  group('queries', () {
    test('visits of a crack come back oldest first; allFramePaths lists every stored frame', () async {
      final late = _visit(crackId, [_f('late.jpg')]);
      await repo.saveVisit(VisitDraft(
        crackId: late.crackId, tsUtc: DateTime.utc(2026, 12, 1), kind: 'followup', deviceModel: 'Pixel 7',
        cameraInfoJson: '{}', algorithmVersion: 'v1', frames: late.frames, aggregate: late.aggregate,
      ));
      await repo.saveVisit(_visit(crackId, [_f('early.jpg')])); // 2026-11-17
      final visits = await repo.visitsOfCrack(crackId);
      expect(visits.map((v) => v.tsUtc.toUtc().month), [11, 12]);
      expect(await repo.allFramePaths(), {'late.jpg', 'early.jpg'});
    });
  });

  group('deleting a frame', () {
    test('is refused while a measurement refers to it, and the row stays', () async {
      final id = await repo.saveVisit(_visit(crackId, [_f('a.jpg')]));
      final frame = (await repo.framesOfVisit(id)).single;
      await expectLater(repo.deleteFrame(frame.id), throwsA(isA<RepositoryException>()));
      expect(await repo.framesOfVisit(id), hasLength(1));
      // The database refuses it as well, whatever the caller does.
      await expectLater(db.customStatement('DELETE FROM frames WHERE id = ${frame.id}'), throwsA(isA<SqliteException>()));
    });
  });

  group('migration', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('hairline_db_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a new file is created at the current schema version with data surviving a reopen', () async {
      final file = File('${tmp.path}/a.sqlite');
      final a = AppDatabase(NativeDatabase(file));
      final ra = HairlineRepository(a);
      final site = await ra.createSite(name: 'Kantor');
      expect((await a.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), currentSchemaVersion);
      await a.close();
      final b = AppDatabase(NativeDatabase(file));
      expect(await b.select(b.sites).get(), hasLength(1));
      expect((await b.select(b.sites).getSingle()).id, site);
      await b.close();
    });

    test('a database written by a newer app version is refused, not silently opened', () async {
      final file = File('${tmp.path}/future.sqlite');
      final a = AppDatabase(NativeDatabase(file));
      await a.customSelect('SELECT 1').get(); // creates the schema
      await a.customStatement('PRAGMA user_version = ${currentSchemaVersion + 1}');
      await a.close();
      final b = AppDatabase(NativeDatabase(file));
      await expectLater(b.customSelect('SELECT 1').get(), throwsA(anything));
      await b.close();
    });

    test('an older version without a migration step fails loudly (no step exists yet)', () async {
      final file = File('${tmp.path}/old.sqlite');
      final a = AppDatabase(NativeDatabase(file));
      await a.customSelect('SELECT 1').get();
      await a.customStatement('PRAGMA user_version = 0');
      await a.close();
      // user_version 0 is "new" for SQLite: drift creates the schema again over existing
      // tables, which must not corrupt anything; with tables present createAll fails.
      final b = AppDatabase(NativeDatabase(file));
      await expectLater(b.customSelect('SELECT 1').get(), throwsA(anything));
      await b.close();
    });
  });
}
