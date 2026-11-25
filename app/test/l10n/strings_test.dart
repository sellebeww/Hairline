// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/l10n/strings.dart';
import 'package:hairline_core/hairline_core.dart';

List<File> _dart(String dir) => [
      for (final f in Directory(dir).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart') && !f.path.endsWith('.g.dart')) f,
    ];

void main() {
  final catalog = File('lib/l10n/strings.dart').readAsStringSync();
  final literals = [for (final m in RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(catalog)) m.group(1)!];

  test('the catalog has literals to check', () => expect(literals.length, greaterThan(250)));

  test('no catalog text says the building is safe: "aman" and "tidak berbahaya" never appear (CLAUDE.md 1)', () {
    final forbidden = RegExp(r'\b(aman|tidak berbahaya|amankah)\b', caseSensitive: false);
    expect([for (final l in literals) if (forbidden.hasMatch(l)) l], isEmpty);
  });

  test('classification and warning wording never contains "aman" and matches 5.6', () {
    for (final c in TrendClass.values) {
      expect(Strings.trendClass(c).toLowerCase(), isNot(contains('aman')));
    }
    expect(Strings.trendClass(TrendClass.tidakAdaPerubahanTerdeteksi), 'Tidak ada perubahan terdeteksi');
    expect(Strings.trendClass(TrendClass.kemungkinanBertambahLebar), 'Kemungkinan bertambah lebar');
    expect(Strings.trendClass(TrendClass.kemungkinanMenyempit), 'Kemungkinan menyempit');
    for (final w in ContextWarning.values) {
      expect(Strings.contextWarning(w).toLowerCase(), isNot(contains('aman')));
    }
    for (final i in PoseInstruction.values) {
      expect(Strings.instruction(i), isNotEmpty);
    }
    for (final r in FrameRejection.values) {
      expect(Strings.rejection(r), isNotEmpty);
    }
  });

  test('the honest statements are all present', () {
    expect(Strings.honestyIndicative, contains('indikatif'));
    expect(Strings.honestyIndicative, contains('insinyur struktur'));
    expect(Strings.honestyEngineer, contains('hubungi insinyur atau pihak berwenang'));
    expect(Strings.honestyNoChange, contains('lebih kecil dari ketidakpastian pengukuran'));
    expect(Strings.honestyAccuracy, allOf(contains('SINTETIS'), contains('PERANGKAT')));
    expect(Strings.honestyCoplanar, contains('sebidang'));
  });

  test('no em dash (code point 0x2014) anywhere in the sources, tests or docs', () {
    final bad = <String>[];
    for (final root in ['lib', 'test', '../packages/hairline_core/lib', '../packages/hairline_core/test', '../docs']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.dart') || f.path.endsWith('.md')) {
          if (f.readAsStringSync().contains(String.fromCharCode(0x2014))) bad.add(f.path);
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('widgets hold no hardcoded user text: every Text(...) takes a catalog value', () {
    // A literal may only join catalog values (interpolations) with punctuation, never carry words.
    final literalText = RegExp(r"""Text\(\s*(['"])(.*?)\1""");
    final offenders = <String>[];
    for (final f in _dart('lib')) {
      if (f.path.contains('/l10n/') || f.path.contains('/debug/') || f.path.endsWith('main_fake.dart')) continue;
      for (final m in literalText.allMatches(f.readAsStringSync())) {
        final words = m.group(2)!.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+|\\[nt]'), '');
        if (RegExp('[A-Za-z]').hasMatch(words)) offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('printed sheet text is Latin-1 (standard PDF font)', () {
    final printed = [Strings.sheetPrintedTitle(3), Strings.sheetPrintedCutHint, Strings.sheetPrintedScaleBar, ...Strings.sheetPrintedNotes];
    for (final t in printed) {
      expect(t.codeUnits.every((c) => c < 256), isTrue, reason: t);
    }
  });
}
