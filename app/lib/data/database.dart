// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

/// Current schema version. Bump with a step in [AppDatabase.migration] and a test.
const int currentSchemaVersion = 1;

@DriftDatabase(tables: [Sites, Cracks, CrackPoints, Visits, Frames, Measurements, ValidationRuns])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // No released version precedes 1: every future step is added here as
          // `if (from < N) {...}` together with a migration test.
          throw StateError('No migration from schema $from to $to');
        },
        beforeOpen: (details) async {
          if (details.versionBefore != null && details.versionBefore! > currentSchemaVersion) {
            throw StateError(
              'Database schema ${details.versionBefore} is newer than this app supports ($currentSchemaVersion).',
            );
          }
          // SQLite ignores foreign keys unless asked, per connection.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
