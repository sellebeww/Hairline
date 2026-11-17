// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:drift/drift.dart';
import 'package:hairline_core/hairline_core.dart';

import 'database.dart';

/// Domain errors of the repository (messages for the user, Indonesian).
final class RepositoryException implements Exception {
  const RepositoryException(this.message);
  final String message;

  @override
  String toString() => 'RepositoryException: $message';
}

/// One stored measurement row, before ids exist.
final class MeasurementDraft {
  const MeasurementDraft({
    required this.isAggregate,
    required this.status,
    required this.componentsJson,
    this.widthMm,
    this.uRand,
    this.uSys,
    this.uExpanded,
    this.k,
  });

  final bool isAggregate;
  final String status;
  final String componentsJson;
  final double? widthMm, uRand, uSys, uExpanded, k;
}

/// One accepted frame, with its per-frame measurement.
final class FrameDraft {
  const FrameDraft({
    required this.path,
    required this.sha256,
    required this.homographyJson,
    required this.rmsPx,
    required this.looMm,
    required this.sigmaMm,
    required this.tiltDeg,
    required this.mmPerPx,
    required this.qualityJson,
    required this.measurement,
  });

  final String path, sha256, homographyJson, qualityJson;
  final double rmsPx, tiltDeg, mmPerPx;
  final double? looMm, sigmaMm;
  final MeasurementDraft measurement;
}

/// Everything one visit writes, saved in one transaction.
final class VisitDraft {
  const VisitDraft({
    required this.crackId,
    required this.tsUtc,
    required this.kind,
    required this.deviceModel,
    required this.cameraInfoJson,
    required this.frames,
    required this.aggregate,
    required this.algorithmVersion,
    this.referencePoseJson,
  });

  final int crackId;
  final DateTime tsUtc;
  final String kind, deviceModel, cameraInfoJson, algorithmVersion;
  final String? referencePoseJson;
  final List<FrameDraft> frames;
  final MeasurementDraft aggregate;
}

/// A crack with its single measurement point.
final class CrackContext {
  const CrackContext({required this.crack, required this.point});
  final Crack crack;
  final CrackPoint point;
}

/// Reads and writes the schema of 5.7. No measurement logic.
class HairlineRepository {
  HairlineRepository(this._db);
  final AppDatabase _db;

  static DateTime _utc(DateTime t) {
    if (!t.isUtc) throw ArgumentError.value(t, 'timestamp', 'must be UTC');
    return t;
  }

  Future<int> createSite({required String name, double? lat, double? lon, String notes = ''}) =>
      _db.into(_db.sites).insert(SitesCompanion.insert(name: name, lat: Value(lat), lon: Value(lon), notes: Value(notes)));

  /// Creates a crack and its single measurement point in one transaction.
  Future<int> createCrack({
    required int siteId,
    required String label,
    required int sheetId,
    required double printScale,
    required double printScaleURel,
    required Pt pointMm,
    required double directionDeg,
    required DateTime createdAt,
    double reliefMm = defaultReliefMm,
  }) =>
      _db.transaction(() async {
        final id = await _db.into(_db.cracks).insert(CracksCompanion.insert(
              siteId: siteId,
              label: label,
              sheetId: sheetId,
              printScale: printScale,
              printScaleURel: printScaleURel,
              reliefMm: Value(reliefMm),
              createdAt: _utc(createdAt),
            ));
        await _db.into(_db.crackPoints).insert(CrackPointsCompanion.insert(
              crackId: id,
              xMm: pointMm.x,
              yMm: pointMm.y,
              directionDeg: directionDeg,
            ));
        return id;
      });

  /// One point per crack in the MVP (5.7): a second one is refused.
  Future<int> addCrackPoint({required int crackId, required Pt pointMm, required double directionDeg}) =>
      _db.transaction(() async {
        final existing = await (_db.select(_db.crackPoints)..where((p) => p.crackId.equals(crackId))).get();
        if (existing.isNotEmpty) throw const RepositoryException('Satu retak hanya boleh punya satu titik ukur.');
        return _db.into(_db.crackPoints).insert(
              CrackPointsCompanion.insert(crackId: crackId, xMm: pointMm.x, yMm: pointMm.y, directionDeg: directionDeg),
            );
      });

  Future<CrackContext> crackContext(int crackId) async {
    final crack = await (_db.select(_db.cracks)..where((c) => c.id.equals(crackId))).getSingleOrNull();
    if (crack == null) throw const RepositoryException('Retak tidak ditemukan.');
    final points = await (_db.select(_db.crackPoints)..where((p) => p.crackId.equals(crackId))).get();
    if (points.length != 1) throw const RepositoryException('Retak harus punya tepat satu titik ukur.');
    return CrackContext(crack: crack, point: points.single);
  }

  /// Saves the visit, its accepted frames (at most [QualityThresholds.maxStoredFrames]),
  /// the aggregate measurement and one measurement per frame, all or nothing.
  Future<int> saveVisit(VisitDraft d) async {
    if (d.frames.length > QualityThresholds.standard.maxStoredFrames) {
      throw const RepositoryException('Satu kunjungan menyimpan paling banyak 5 frame.');
    }
    final ts = _utc(d.tsUtc);
    return _db.transaction(() async {
      final ctx = await crackContext(d.crackId);
      final visitId = await _db.into(_db.visits).insert(VisitsCompanion.insert(
            crackId: d.crackId,
            tsUtc: ts,
            kind: d.kind,
            deviceModel: d.deviceModel,
            cameraInfoJson: d.cameraInfoJson,
            referencePoseJson: Value(d.referencePoseJson),
          ));
      for (final f in d.frames) {
        final frameId = await _db.into(_db.frames).insert(FramesCompanion.insert(
              visitId: visitId,
              path: f.path,
              sha256: f.sha256,
              homographyJson: f.homographyJson,
              rmsPx: f.rmsPx,
              looMm: Value(f.looMm),
              sigmaMm: Value(f.sigmaMm),
              tiltDeg: f.tiltDeg,
              mmPerPx: f.mmPerPx,
              qualityJson: f.qualityJson,
              accepted: true,
            ));
        await _insertMeasurement(visitId, ctx.point.id, d.algorithmVersion, f.measurement, frameId: frameId);
      }
      await _insertMeasurement(visitId, ctx.point.id, d.algorithmVersion, d.aggregate);
      return visitId;
    });
  }

  /// Adds the results of reprocessing a stored visit under [algorithmVersion]. Existing
  /// rows (of any version) are never touched; the same version twice is refused.
  Future<void> addReprocessedMeasurements({
    required int visitId,
    required String algorithmVersion,
    required MeasurementDraft aggregate,
    required Map<int, MeasurementDraft> perFrame,
  }) =>
      _db.transaction(() async {
        final visit = await (_db.select(_db.visits)..where((v) => v.id.equals(visitId))).getSingleOrNull();
        if (visit == null) throw const RepositoryException('Kunjungan tidak ditemukan.');
        final done = await (_db.select(_db.measurements)
              ..where((m) => m.visitId.equals(visitId) & m.algorithmVersion.equals(algorithmVersion)))
            .get();
        if (done.isNotEmpty) {
          throw RepositoryException('Kunjungan ini sudah diproses dengan versi algoritma $algorithmVersion.');
        }
        final ctx = await crackContext(visit.crackId);
        for (final MapEntry(key: frameId, value: m) in perFrame.entries) {
          await _insertMeasurement(visitId, ctx.point.id, algorithmVersion, m, frameId: frameId);
        }
        await _insertMeasurement(visitId, ctx.point.id, algorithmVersion, aggregate);
      });

  Future<void> _insertMeasurement(int visitId, int pointId, String version, MeasurementDraft m, {int? frameId}) =>
      _db.into(_db.measurements).insert(MeasurementsCompanion.insert(
            visitId: visitId,
            pointId: pointId,
            frameId: Value(frameId),
            isAggregate: m.isAggregate,
            algorithmVersion: version,
            widthMm: Value(m.widthMm),
            uRand: Value(m.uRand),
            uSys: Value(m.uSys),
            uExpanded: Value(m.uExpanded),
            k: Value(m.k),
            componentsJson: m.componentsJson,
            status: m.status,
          ));

  Future<Visit?> visit(int id) => (_db.select(_db.visits)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<List<Visit>> visitsOfCrack(int crackId) =>
      (_db.select(_db.visits)
            ..where((v) => v.crackId.equals(crackId))
            ..orderBy([(v) => OrderingTerm.asc(v.tsUtc)]))
          .get();

  Future<List<Frame>> framesOfVisit(int visitId) =>
      (_db.select(_db.frames)
            ..where((f) => f.visitId.equals(visitId))
            ..orderBy([(f) => OrderingTerm.asc(f.id)]))
          .get();

  Future<List<Measurement>> measurementsOfVisit(int visitId, {String? algorithmVersion}) =>
      (_db.select(_db.measurements)
            ..where((m) => m.visitId.equals(visitId) & (algorithmVersion == null ? const Constant(true) : m.algorithmVersion.equals(algorithmVersion)))
            ..orderBy([(m) => OrderingTerm.asc(m.id)]))
          .get();

  /// Aggregate rows of a visit, oldest version first.
  Future<List<Measurement>> aggregatesOfVisit(int visitId) =>
      (_db.select(_db.measurements)
            ..where((m) => m.visitId.equals(visitId) & m.isAggregate.equals(true))
            ..orderBy([(m) => OrderingTerm.asc(m.id)]))
          .get();

  Future<Set<String>> allFramePaths() async => {for (final f in await _db.select(_db.frames).get()) f.path};

  /// Deletes a frame row. Refused while a measurement refers to it: a measured result
  /// must stay reproducible from its photo.
  Future<void> deleteFrame(int frameId) => _db.transaction(() async {
        final used = await (_db.select(_db.measurements)..where((m) => m.frameId.equals(frameId))).get();
        if (used.isNotEmpty) throw const RepositoryException('Frame ini dipakai oleh pengukuran dan tidak dapat dihapus.');
        await (_db.delete(_db.frames)..where((f) => f.id.equals(frameId))).go();
      });
}
