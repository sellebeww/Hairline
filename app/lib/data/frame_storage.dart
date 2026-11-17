// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A photo written to the private frame directory.
final class StoredFrame {
  const StoredFrame({required this.name, required this.sha256});

  /// File name relative to the frame directory (what `frames.path` stores).
  final String name;

  /// Lower-case hex SHA-256 of the file bytes.
  final String sha256;
}

/// More frames than one visit may keep.
final class TooManyFramesException implements Exception {
  const TooManyFramesException(this.count);
  final int count;

  @override
  String toString() => 'TooManyFramesException: $count frames (max $maxFramesPerVisit)';
}

/// CLAUDE.md 5.7: a visit keeps at most 5 accepted frames.
const int maxFramesPerVisit = 5;

/// Photos in the app's private directory (CLAUDE.md 5.8): random names (no site or time in
/// the name), SHA-256 of the content, at most [maxFramesPerVisit] per visit, deletion of
/// everything that is not part of a stored visit. Nothing is exported from here.
class FrameStorage {
  FrameStorage(Directory root, {Random? random})
      : _dir = Directory(p.join(root.path, 'frames')),
        _random = random ?? Random.secure();

  final Directory _dir;
  final Random _random;

  String _randomName() => '${[for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join()}.jpg';

  File fileOf(String name) => File(p.join(_dir.path, p.basename(name)));

  /// Writes the accepted photos of ONE visit. All or nothing: if one write fails the
  /// files already written are removed and the error is rethrown.
  Future<List<StoredFrame>> saveVisitFrames(List<Uint8List> accepted) async {
    if (accepted.length > maxFramesPerVisit) throw TooManyFramesException(accepted.length);
    await _dir.create(recursive: true);
    final written = <StoredFrame>[];
    try {
      for (final bytes in accepted) {
        final name = _randomName();
        final target = File(p.join(_dir.path, name));
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        written.add(StoredFrame(name: name, sha256: sha256.convert(bytes).toString()));
      }
    } catch (_) {
      try {
        await deleteAll([for (final w in written) w.name]);
      } catch (_) {} // keep the original error; deleteUnreferenced sweeps leftovers
      rethrow;
    }
    return written;
  }

  Future<Uint8List> read(String name) => fileOf(name).readAsBytes();

  /// True when the stored file still has the recorded hash.
  Future<bool> verify(String name, String expectedSha256) async =>
      sha256.convert(await read(name)).toString() == expectedSha256;

  /// Deletes files; missing ones are ignored.
  Future<void> deleteAll(Iterable<String> names) async {
    for (final n in names) {
      final f = fileOf(n);
      if (await f.exists()) await f.delete();
    }
  }

  /// Removes files in the directory that no stored frame refers to (left by a crash
  /// between writing and committing, or temporary files). Returns the removed names.
  Future<List<String>> deleteUnreferenced(Set<String> referenced) async {
    if (!await _dir.exists()) return const [];
    final removed = <String>[];
    await for (final e in _dir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!referenced.contains(name)) {
        await e.delete();
        removed.add(name);
      }
    }
    return removed;
  }
}
