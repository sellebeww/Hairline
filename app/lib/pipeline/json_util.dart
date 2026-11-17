// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:convert';

/// JSON for the database: NaN and infinity (not valid JSON) become null.
String encodeJson(Object? value) => jsonEncode(_safe(value));

Object? _safe(Object? v) => switch (v) {
      double d when !d.isFinite => null,
      Map<Object?, Object?> m => {for (final e in m.entries) '${e.key}': _safe(e.value)},
      Iterable<Object?> l => [for (final e in l) _safe(e)],
      _ => v,
    };
