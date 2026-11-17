// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/data/database.dart';
import 'package:hairline/data/frame_storage.dart';
import 'package:hairline/data/repository.dart';
import 'package:hairline/pipeline/frame_processor.dart';
import 'package:hairline/pipeline/visit_processor.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

import '../support/synthetic_ports.dart';

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

int _filesIn(Directory root) {
  final d = Directory('${root.path}/frames');
  return d.existsSync() ? d.listSync().whereType<File>().length : 0;
}

/// A repository whose visit transaction fails after the files were written.
final class _FailingRepository extends HairlineRepository {
  _FailingRepository(super.db);

  @override
  Future<int> saveVisit(VisitDraft d) async => throw StateError('disk full');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final cam = testCamera();
  late Uint8List gray, grayThin;

  setUpAll(() {
    // One full-size render of the sheet (about 15 s each); bursts re-encode it with new corner noise.
    gray = srgbBytes(renderSheetPhoto(
      camera: cam, crackWidthMm: trueWidthMm, crackDirectionDeg: crackDirectionDeg, noiseSigma: 0.004, rng: Random(5)));
    grayThin = srgbBytes(renderSheetPhoto(
      camera: cam, crackWidthMm: 0.02, crackDirectionDeg: crackDirectionDeg, noiseSigma: 0.004, rng: Random(6)));
  });

  late AppDatabase db;
  late HairlineRepository repo;
  late Directory root;
  late FrameStorage storage;
  late FrameProcessor frames;
  late VisitProcessor processor;
  late int crackId;
  final fixedNow = DateTime.utc(2026, 11, 17, 9);

  VisitProcessor makeProcessor({HairlineRepository? repository, String version = measurementAlgorithmVersion}) => VisitProcessor(
        frames: frames,
        repository: repository ?? repo,
        storage: storage,
        algorithmVersion: version,
        now: () => fixedNow,
      );

  Uint8List photo(Uint8List g, int seed, {Set<int> omit = const {}}) =>
      SyntheticPhotoCodec.encode(g, testImage.width, testImage.height, detections(cam, seed: seed, omit: omit));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = HairlineRepository(db);
    root = Directory.systemTemp.createTempSync('hairline_visit_');
    storage = FrameStorage(root);
    frames = FrameProcessor(syntheticPorts);
    processor = makeProcessor();
    final site = await repo.createSite(name: 'Uji');
    crackId = await repo.createCrack(
      siteId: site,
      label: 'Retak A',
      sheetId: 0,
      printScale: 1,
      printScaleURel: 0.003,
      pointMm: const Pt(0, 0),
      directionDeg: crackDirectionDeg,
      createdAt: DateTime.utc(2026, 11, 1),
    );
  });
  tearDown(() async {
    frames.cancelAll();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('a good burst becomes a stored visit: frames, files with hashes, per-frame and aggregate rows', () async {
    final photos = [for (var i = 0; i < 4; i++) photo(gray, i)];
    final out = await processor.processBurst(
      crackId: crackId,
      photos: photos,
      deviceModel: 'Pixel 7',
      camera: const CameraInfo(focalMm: 6.8, sensorLongSideMm: 9.8),
      kind: 'baseline',
    );
    expect(out, isA<VisitStored>());
    final stored = out as VisitStored;
    expect(stored.result.status, VisitStatus.terukur);

    final visit = (await repo.visit(stored.visitId))!;
    expect((visit.tsUtc.toUtc(), visit.deviceModel, visit.kind), (fixedNow, 'Pixel 7', 'baseline'));
    final fs = await repo.framesOfVisit(stored.visitId);
    expect(fs, hasLength(4));
    for (var i = 0; i < 4; i++) {
      expect(fs[i].accepted, isTrue);
      expect(await storage.verify(fs[i].path, fs[i].sha256), isTrue);
      expect(fs[i].sha256, sha256.convert(photos[i]).toString());
      final h = homographyFromJson(_decode(fs[i].homographyJson));
      expect(h.size.width, testImage.width);
      expect(fs[i].tiltDeg, closeTo(8, 2));
      expect(fs[i].mmPerPx, closeTo(0.12, 0.01));
    }
    expect(_filesIn(root), 4);

    final ms = await repo.measurementsOfVisit(stored.visitId);
    expect(ms, hasLength(5));
    expect(ms.every((m) => m.algorithmVersion == measurementAlgorithmVersion), isTrue);
    final agg = ms.singleWhere((m) => m.isAggregate);
    expect(agg.status, 'TERUKUR');
    expect((agg.widthMm! - trueWidthMm).abs(), lessThanOrEqualTo(agg.uExpanded!));
    expect(agg.k, greaterThan(1.9));
    expect(agg.componentsJson, contains('belum_divalidasi'));
    expect(ms.where((m) => !m.isAggregate).every((m) => m.frameId != null && m.status == 'TERUKUR'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('only 5 frames are kept from a longer burst; the sixth and seventh are not stored', () async {
    final out = await processor.processBurst(
      crackId: crackId,
      photos: [for (var i = 0; i < 7; i++) photo(gray, i)],
      deviceModel: 'Pixel 7',
    ) as VisitStored;
    expect(await repo.framesOfVisit(out.visitId), hasLength(5));
    expect(_filesIn(root), 5);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a rejected frame is dropped, the others are kept', () async {
    final out = await processor.processBurst(
      crackId: crackId,
      photos: [photo(gray, 0), photo(gray, 1, omit: {0, 1}), photo(gray, 2), photo(gray, 3)],
      deviceModel: 'Pixel 7',
    ) as VisitStored;
    expect(out.frames.map((f) => f.accepted), [true, false, true, true]);
    expect(await repo.framesOfVisit(out.visitId), hasLength(3));
    expect(_filesIn(root), 3);
    expect(out.result.frameRejections.single.code, 'TOO_FEW_MARKERS');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('fewer than 3 accepted frames: nothing is stored, with specific reasons', () async {
    final out = await processor.processBurst(
      crackId: crackId,
      photos: [photo(gray, 0), photo(gray, 1), photo(gray, 2, omit: {0, 1}), photo(gray, 3, omit: {2, 3})],
      deviceModel: 'Pixel 7',
    );
    expect(out, isA<VisitNotStored>());
    final reasons = (out as VisitNotStored).reasons;
    expect(reasons.first, contains('Hanya 2 dari 4'));
    expect(reasons, contains(contains('Penanda tertutup')));
    expect(out.result.status, VisitStatus.ditolak);
    for (final t in ['visits', 'frames', 'measurements']) {
      expect(await _count(db, t), 0, reason: t);
    }
    expect(_filesIn(root), 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a crack too thin to measure is stored without a width number', () async {
    final out = await processor.processBurst(
      crackId: crackId,
      photos: [for (var i = 0; i < 3; i++) photo(grayThin, i)],
      deviceModel: 'Pixel 7',
    );
    expect(out, isA<VisitStored>());
    final agg = (await repo.aggregatesOfVisit((out as VisitStored).visitId)).single;
    expect(agg.status, anyOf('DI_BAWAH_BATAS_UKUR', 'TIDAK_TERUKUR'));
    expect(agg.widthMm, isNull);
    expect(agg.uExpanded, isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a failing transaction removes the files that were already written (atomic with the files)', () async {
    final failing = makeProcessor(repository: _FailingRepository(db));
    await expectLater(
      failing.processBurst(crackId: crackId, photos: [for (var i = 0; i < 3; i++) photo(gray, i)], deviceModel: 'Pixel 7'),
      throwsStateError,
    );
    expect(_filesIn(root), 0);
    expect(await _count(db, 'visits'), 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('cancelling a burst stores nothing and leaves no files', () async {
    final token = CancelToken();
    final future = processor.processBurst(
      crackId: crackId,
      photos: [for (var i = 0; i < 4; i++) photo(gray, i)],
      deviceModel: 'Pixel 7',
      cancel: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    token.cancel();
    await expectLater(future, throwsA(isA<VisitCancelledException>()));
    expect(await _count(db, 'visits'), 0);
    expect(_filesIn(root), 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an unknown crack is refused before any work', () async {
    await expectLater(
      processor.processBurst(crackId: 999, photos: [photo(gray, 0)], deviceModel: 'x'),
      throwsA(isA<RepositoryException>()),
    );
  });

  group('reprocessing a stored visit', () {
    late int visitId;
    setUp(() async {
      final out = await processor.processBurst(
        crackId: crackId,
        photos: [for (var i = 0; i < 3; i++) photo(gray, i)],
        deviceModel: 'Pixel 7',
      ) as VisitStored;
      visitId = out.visitId;
    });

    test('adds rows under the new version, keeps every old row, and cannot run twice', () async {
      final before = await repo.measurementsOfVisit(visitId);
      final v2 = makeProcessor(version: 'p9-test');
      final out = await v2.reprocess(visitId);
      expect(out, isA<VisitReprocessed>());
      final after = await repo.measurementsOfVisit(visitId);
      expect(after, hasLength(before.length * 2));
      expect(after.take(before.length).toList(), before, reason: 'old results must not be overwritten');
      expect((await repo.aggregatesOfVisit(visitId)).map((m) => m.algorithmVersion), [measurementAlgorithmVersion, 'p9-test']);
      expect(await repo.framesOfVisit(visitId), hasLength(3)); // the frames themselves are untouched
      await expectLater(v2.reprocess(visitId), throwsA(isA<RepositoryException>()));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a photo that no longer matches its hash blocks reprocessing', () async {
      final f = (await repo.framesOfVisit(visitId)).first;
      await storage.fileOf(f.path).writeAsBytes([0, 1, 2]);
      await expectLater(makeProcessor(version: 'p9-test').reprocess(visitId), throwsA(isA<RepositoryException>()));
      expect(await repo.aggregatesOfVisit(visitId), hasLength(1));
    });

    test('an unknown visit is refused', () async {
      await expectLater(processor.reprocess(999), throwsA(isA<RepositoryException>()));
    });
  });
}

Map<String, Object?> _decode(String json) => (jsonDecode(json) as Map<String, Object?>);
