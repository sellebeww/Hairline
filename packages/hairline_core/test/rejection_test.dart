// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:test/test.dart';

void main() {
  test('reason codes are unique and stable (the UI maps them to messages)', () {
    final codes = RejectReason.values.map((r) => r.code).toList();
    expect(codes.toSet().length, codes.length);
    expect(RejectReason.crackNotFound.code, 'CRACK_NOT_FOUND');
    expect(RejectReason.patchTooSmall.code, 'PATCH_TOO_SMALL');
  });

  test('MeasurementException carries the reason and a readable description', () {
    const e = MeasurementException(RejectReason.saturated, 'terlalu terang');
    expect(e.reason, RejectReason.saturated);
    expect(e.toString(), 'MeasurementException(SATURATED): terlalu terang');
  });
}
