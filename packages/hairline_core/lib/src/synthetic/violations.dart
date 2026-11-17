// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';

import 'render.dart';

/// Scenes that break one assumption of the width model on purpose (comparison only).

/// [scene] (built with a crack along the x axis, direction 0) rotated about the origin
/// so that the crack runs along [directionDeg]. Axis-aligned cracks pick up the
/// renderer's supersampling quantisation (0.5/S px per edge, the same for every
/// sample along the edge), so violation cases are rotated to avoid mixing it in.
Scene rotatedAboutOrigin(Scene scene, double directionDeg) {
  final a = directionDeg * pi / 180;
  final c = cos(a), s = sin(a);
  return (x, y) => scene(x * c + y * s, -x * s + y * c);
}

/// A horizontal crack (direction 0, centred on y = 0, nominal [widthMm]) whose two
/// edges wander independently by a smooth pseudo-random function of amplitude
/// [amplitudeMm] (sum of six sinusoids, fixed [seed]). Returns the scene and the true
/// mean width over the 4 mm segment `x in [-2, 2]` (numerical).
({Scene scene, double meanWidthMm}) roughEdgeCrackScene({
  double widthMm = 0.5,
  double amplitudeMm = 0.08,
  double depth = 0.6,
  double background = 0.8,
  int seed = 21,
}) {
  final rng = Random(seed);
  final phases = [for (var i = 0; i < 6; i++) rng.nextDouble() * 2 * pi];
  const freqs = [0.9, 1.7, 2.9, 4.3, 6.1, 8.3];
  double edge(double x, int side) {
    var v = 0.0;
    for (var i = 0; i < 6; i++) {
      v += sin(freqs[i] * x + phases[i] + side * 1.7) / sqrt(6);
    }
    return amplitudeMm * v;
  }

  var mean = 0.0;
  const n = 4000;
  for (var i = 0; i < n; i++) {
    final x = -2 + 4 * (i + 0.5) / n;
    mean += widthMm + edge(x, 1) - edge(x, 0);
  }
  final inside = background * (1 - depth);
  return (
    scene: (x, y) => (y >= -widthMm / 2 + edge(x, 0) && y <= widthMm / 2 + edge(x, 1)) ? inside : background,
    meanWidthMm: mean / n,
  );
}

/// [scene] with the half plane `y > 0` scaled by [factor] (a shadow on one side).
Scene withOneSidedShadow(Scene scene, double factor) => (x, y) => y > 0 ? factor * scene(x, y) : scene(x, y);

/// [scene] darkened by a Gaussian stain (sd 0.4 mm, peak darkening [amplitude]) centred
/// at ([cx], [cy]) mm.
Scene withStain(Scene scene, double amplitude, {double cx = 0.3, double cy = 0.9}) => (x, y) {
      final d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      return scene(x, y) * (1 - amplitude * exp(-d2 / (2 * 0.4 * 0.4)));
    };
