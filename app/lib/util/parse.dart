// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Parses a decimal typed by the user, accepting a comma as the separator (Indonesian
/// keyboards). Returns null for anything that is not a finite number.
double? parseDecimal(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}
