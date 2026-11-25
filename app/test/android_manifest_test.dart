// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards CLAUDE.md sections 4 and 5.8 on the manifest sources (the built release manifest is
// checked with `aapt dump permissions` in the phase 9 audit).
void main() {
  final main = File('android/app/src/main/AndroidManifest.xml').readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('the main (release) manifest declares only CAMERA and no INTERNET', () {
    final granted = RegExp(r'<uses-permission\s+android:name="([^"]+)"\s*/>').allMatches(main).map((m) => m.group(1)).toList();
    expect(granted, ['android.permission.CAMERA']);
    expect(main, isNot(contains('INTERNET')));
  });

  test('libraries cannot add storage, audio or network-state permissions through the manifest merger', () {
    for (final p in ['RECORD_AUDIO', 'WRITE_EXTERNAL_STORAGE', 'READ_EXTERNAL_STORAGE', 'ACCESS_NETWORK_STATE']) {
      expect(RegExp('android.permission.$p"\\s+tools:node="remove"').hasMatch(main), isTrue, reason: p);
    }
  });

  test('photos and the database are kept out of cloud backup and device transfer (5.8)', () {
    expect(main, contains('android:allowBackup="false"'));
    expect(main, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules)!.group(1)!;
      for (final domain in ['file', 'database', 'sharedpref']) {
        expect(body, contains('<exclude domain="$domain"/>'), reason: '$section $domain');
      }
    }
  });

  test('INTERNET exists only in the debug and profile manifests (tooling)', () {
    for (final flavor in ['debug', 'profile']) {
      expect(File('android/app/src/$flavor/AndroidManifest.xml').readAsStringSync(), contains('android.permission.INTERNET'));
    }
  });
}
