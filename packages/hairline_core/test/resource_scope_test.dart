// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  group('ResourceScope (the disposal pattern of the native adapters)', () {
    test('releases every resource in reverse order after a normal return', () {
      final log = <String>[];
      final r = ResourceScope.run((s) {
        s.add('a', log.add);
        s.add('b', log.add);
        s.add('c', log.add);
        return 42;
      });
      expect(r, 42);
      expect(log, ['c', 'b', 'a']);
    });

    test('releases everything when the body throws, and the body error wins', () {
      final log = <String>[];
      expect(
        () => ResourceScope.run<void>((s) {
          s.add('a', log.add);
          s.add('b', (_) => throw StateError('release failed'));
          throw ArgumentError('body failed');
        }),
        throwsA(isA<ArgumentError>()),
      );
      expect(log, ['a']);
    });

    test('a failing release does not stop the others and is reported afterwards', () {
      final log = <String>[];
      try {
        ResourceScope.run((s) {
          s.add('a', log.add);
          s.add('b', (_) => throw StateError('boom'));
          s.add('c', log.add);
        });
        fail('expected ResourceDisposeException');
      } on ResourceDisposeException catch (e) {
        expect(e.errors, hasLength(1));
      }
      expect(log, ['c', 'a']);
    });

    test('a resource registered by an earlier step is still released if a later step throws', () {
      var released = 0;
      expect(
        () => ResourceScope.run<void>((s) {
          s.add(1, (_) => released++);
          s.add(2, (_) => released++);
          throw FormatException('x');
        }),
        throwsFormatException,
      );
      expect(released, 2);
    });

    test('registering after the scope closed is an error', () {
      late ResourceScope leaked;
      ResourceScope.run((s) => leaked = s);
      expect(() => leaked.add(1, (_) {}), throwsStateError);
    });
  });
}
