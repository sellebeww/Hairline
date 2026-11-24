// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'data/database.dart';
import 'data/frame_storage.dart';
import 'data/repository.dart';
import 'pipeline/frame_processor.dart';
import 'pipeline/visit_processor.dart';

part 'providers.g.dart';

/// Private application directory (database and photos). Overridden in `main` and in tests.
@Riverpod(keepAlive: true)
Directory appDirectory(Ref ref) => throw UnimplementedError('Override appDirectoryProvider in main().');

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(NativeDatabase.createInBackground(File(p.join(ref.watch(appDirectoryProvider).path, 'hairline.sqlite'))));
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
HairlineRepository hairlineRepository(Ref ref) => HairlineRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
FrameStorage frameStorage(Ref ref) => FrameStorage(ref.watch(appDirectoryProvider));

/// The adapters built inside the worker isolate. Must be overridden by the app with the
/// OpenCV factory (`openCvPorts` of package:hairline_opencv) once the app depends on it
/// (BLOCKERS B1, DECISIONS D34); tests override it with the synthetic ports.
@Riverpod(keepAlive: true)
FramePortsFactory framePortsFactory(Ref ref) =>
    throw UnimplementedError('Override framePortsFactoryProvider with the OpenCV ports factory.');

@Riverpod(keepAlive: true)
FrameProcessor frameProcessor(Ref ref) {
  final processor = FrameProcessor(ref.watch(framePortsFactoryProvider));
  ref.onDispose(processor.cancelAll);
  return processor;
}

@Riverpod(keepAlive: true)
VisitProcessor visitProcessor(Ref ref) => VisitProcessor(
      frames: ref.watch(frameProcessorProvider),
      repository: ref.watch(hairlineRepositoryProvider),
      storage: ref.watch(frameStorageProvider),
    );

/// Removes photo files that no stored frame refers to (left by a crash between writing and
/// committing). Call once at start, before any capture. Returns the removed names.
Future<List<String>> sweepOrphanFrames(HairlineRepository repository, FrameStorage storage) async =>
    storage.deleteUnreferenced(await repository.allFramePaths());
