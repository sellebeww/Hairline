// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

/// Standard normal sample (Box-Muller). Deterministic for a seeded [rng].
double gaussian(Random rng) {
  final u1 = 1 - rng.nextDouble(); // in (0, 1], avoids log(0)
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}
