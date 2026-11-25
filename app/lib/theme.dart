// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';

/// App theme: Material 3 from one seed. Text scales with the system setting (never clamped).
ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5F8B)),
      visualDensity: VisualDensity.standard,
    );

/// A background and the text color used on it. Every pair reaches WCAG AA (4.5:1 for
/// normal text), checked by a test. Meaning is always also carried by an icon and text.
typedef ColorPair = ({Color bg, Color fg});

abstract final class StatusColors {
  /// BELUM_DIVALIDASI and other cautions.
  static const ColorPair caution = (bg: Color(0xFFFFE9B0), fg: Color(0xFF3B2A00));

  /// "Kemungkinan bertambah lebar".
  static const ColorPair wider = (bg: Color(0xFFFFD9C2), fg: Color(0xFF4A1C00));

  /// "Kemungkinan menyempit".
  static const ColorPair narrower = (bg: Color(0xFFCFE6FF), fg: Color(0xFF062B4F));

  /// "Tidak ada perubahan terdeteksi" and "tidak terukur".
  static const ColorPair neutral = (bg: Color(0xFFE6E6E6), fg: Color(0xFF1B1B1B));

  static const List<ColorPair> all = [caution, wider, narrower, neutral];
}

/// WCAG contrast ratio between two colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
