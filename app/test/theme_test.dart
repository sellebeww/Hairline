// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/theme.dart';

void main() {
  test('every status color pair reaches WCAG AA (4.5:1) for normal text', () {
    for (final pair in StatusColors.all) {
      expect(contrastRatio(pair.bg, pair.fg), greaterThanOrEqualTo(4.5), reason: '${pair.bg} on ${pair.fg}');
    }
  });

  test('theme text colors on the surface reach AA', () {
    final scheme = buildTheme().colorScheme;
    expect(contrastRatio(scheme.surface, scheme.onSurface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(scheme.primary, scheme.onPrimary), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(scheme.error, scheme.onError), greaterThanOrEqualTo(4.5));
  });
}
