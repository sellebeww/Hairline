import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  test('core package is importable and versioned', () {
    expect(hairlineCoreVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });
}
