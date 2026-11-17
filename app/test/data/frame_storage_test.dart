// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/data/frame_storage.dart';

void main() {
  late Directory root;
  late FrameStorage storage;
  setUp(() {
    root = Directory.systemTemp.createTempSync('hairline_frames_');
    storage = FrameStorage(root, random: Random(1));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Uint8List bytes(int seed) => Uint8List.fromList([for (var i = 0; i < 64; i++) (seed * 31 + i) & 255]);

  test('writes random-named .jpg files with the SHA-256 of the content, inside the private directory', () async {
    final a = bytes(1), b = bytes(2);
    final stored = await storage.saveVisitFrames([a, b]);
    expect(stored, hasLength(2));
    expect(stored[0].name, matches(RegExp(r'^[0-9a-f]{32}\.jpg$')));
    expect(stored[0].name, isNot(stored[1].name));
    expect(stored[0].sha256, sha256.convert(a).toString());
    expect(await storage.read(stored[1].name), b);
    expect(await storage.verify(stored[0].name, stored[0].sha256), isTrue);
    expect(storage.fileOf(stored[0].name).path, startsWith(root.path));
  });

  test('refuses more than 5 frames per visit and writes nothing', () async {
    await expectLater(
      storage.saveVisitFrames([for (var i = 0; i < 6; i++) bytes(i)]),
      throwsA(isA<TooManyFramesException>()),
    );
    expect(await storage.deleteUnreferenced({}), isEmpty);
  });

  test('a changed file no longer verifies', () async {
    final s = (await storage.saveVisitFrames([bytes(3)])).single;
    await storage.fileOf(s.name).writeAsBytes(bytes(4));
    expect(await storage.verify(s.name, s.sha256), isFalse);
  });

  test('deleteAll removes files and ignores missing ones; path traversal in a name is neutralised', () async {
    final s = (await storage.saveVisitFrames([bytes(5)])).single;
    await storage.deleteAll([s.name, 'nope.jpg']);
    expect(storage.fileOf(s.name).existsSync(), isFalse);
    // A hostile name only ever resolves inside the frame directory.
    expect(storage.fileOf('../../etc/passwd').path, startsWith(root.path));
  });

  test('deleteUnreferenced removes orphans and temporary files but keeps referenced frames', () async {
    final keep = (await storage.saveVisitFrames([bytes(6)])).single;
    final orphan = (await storage.saveVisitFrames([bytes(7)])).single;
    File('${storage.fileOf(orphan.name).path}.tmp').writeAsBytesSync([1]);
    final removed = await storage.deleteUnreferenced({keep.name});
    expect(removed, containsAll([orphan.name, '${orphan.name}.tmp']));
    expect(storage.fileOf(keep.name).existsSync(), isTrue);
    expect(storage.fileOf(orphan.name).existsSync(), isFalse);
  });

  test('a write failure removes the files already written (all or nothing)', () async {
    // Make the third name collide with a directory, so its write fails.
    final fixed = FrameStorage(root, random: Random(1));
    final names = <String>[];
    final probe = FrameStorage(root, random: Random(1));
    for (final s in await probe.saveVisitFrames([bytes(1), bytes(2), bytes(3)])) {
      names.add(s.name);
    }
    await probe.deleteAll(names);
    Directory('${root.path}/frames/${names[2]}.tmp').createSync(recursive: true);
    await expectLater(fixed.saveVisitFrames([bytes(1), bytes(2), bytes(3)]), throwsA(anything));
    expect(File('${root.path}/frames/${names[0]}').existsSync(), isFalse);
    expect(File('${root.path}/frames/${names[1]}').existsSync(), isFalse);
  });
}
