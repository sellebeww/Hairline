// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:drift/drift.dart';

// Schema of CLAUDE.md 5.7. All timestamps are UTC. Foreign keys are RESTRICT: nothing
// that is referenced disappears silently. `alerts` and `reports` are deliberately absent.

class Sites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

@TableIndex(name: 'idx_cracks_site', columns: {#siteId})
class Cracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get siteId => integer().references(Sites, #id, onDelete: KeyAction.restrict)();
  TextColumn get label => text()();
  // ignore: recursive_getters
  IntColumn get sheetId => integer().check(sheetId.isBetweenValues(0, 11))();
  // ignore: recursive_getters
  RealColumn get printScale => real().check(printScale.isBetweenValues(0.8, 1.2))();
  RealColumn get printScaleURel => real()();
  RealColumn get reliefMm => real().withDefault(const Constant(0.3))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Exactly one row per crack in the MVP, enforced by the repository (not by a UNIQUE
/// index: the schema is ready for several points per crack, the feature is not).
@TableIndex(name: 'idx_crack_points_crack', columns: {#crackId})
class CrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get crackId => integer().references(Cracks, #id, onDelete: KeyAction.restrict)();
  RealColumn get xMm => real()();
  RealColumn get yMm => real()();
  RealColumn get directionDeg => real()();
}

@TableIndex(name: 'idx_visits_crack_ts', columns: {#crackId, #tsUtc})
class Visits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get crackId => integer().references(Cracks, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get tsUtc => dateTime()();
  TextColumn get kind => text()();
  TextColumn get deviceModel => text()();
  TextColumn get cameraInfoJson => text()();
  TextColumn get referencePoseJson => text().nullable()();
}

/// Only accepted frames are stored (at most 5 per visit, enforced by the repository).
/// [path] is relative to the private frame directory.
@TableIndex(name: 'idx_frames_visit', columns: {#visitId})
class Frames extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get visitId => integer().references(Visits, #id, onDelete: KeyAction.restrict)();
  TextColumn get path => text().unique()();
  TextColumn get sha256 => text()();
  TextColumn get homographyJson => text()();
  RealColumn get rmsPx => real()();
  RealColumn get looMm => real().nullable()();
  RealColumn get sigmaMm => real().nullable()();
  RealColumn get tiltDeg => real()();
  RealColumn get mmPerPx => real()();
  TextColumn get qualityJson => text()();
  BoolColumn get accepted => boolean()();
}

/// One aggregate row (`isAggregate`) and one row per frame, per `algorithmVersion`.
/// Reprocessing adds rows with another version and never updates old ones.
@TableIndex(name: 'idx_measurements_visit_version', columns: {#visitId, #algorithmVersion})
class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get visitId => integer().references(Visits, #id, onDelete: KeyAction.restrict)();
  IntColumn get pointId => integer().references(CrackPoints, #id, onDelete: KeyAction.restrict)();
  IntColumn get frameId => integer().nullable().references(Frames, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isAggregate => boolean()();
  TextColumn get algorithmVersion => text()();

  /// Null unless the status is TERUKUR (a number is never stored for a result that
  /// must be shown as "di bawah batas ukur" or "tidak terukur").
  RealColumn get widthMm => real().nullable()();
  RealColumn get uRand => real().nullable()();
  RealColumn get uSys => real().nullable()();
  RealColumn get uExpanded => real().nullable()();
  RealColumn get k => real().nullable()();
  TextColumn get componentsJson => text()();
  TextColumn get status => text()();
}

@TableIndex(name: 'idx_validation_runs_device_ts', columns: {#deviceModel, #tsUtc})
class ValidationRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get deviceModel => text()();
  DateTimeColumn get tsUtc => dateTime()();
  TextColumn get plateTruthJson => text()();
  TextColumn get resultsJson => text()();
  RealColumn get biasMm => real()();
  RealColumn get rmseMm => real()();
  RealColumn get coverage => real()();
  TextColumn get algorithmVersion => text()();

  /// `PERANGKAT` or `SINTETIS`.
  TextColumn get source => text()();
}
