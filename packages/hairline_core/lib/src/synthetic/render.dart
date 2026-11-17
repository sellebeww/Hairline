// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import '../point.dart';
import '../sheet.dart';
import 'noise.dart';

/// Grayscale image, values 0..1 (`byte/255`, like `GrayPatch`, D4). Pixel (i,j)
/// is centred on (i,j) and covers [i-0.5, i+0.5) x [j-0.5, j+0.5).
final class GrayImage {
  GrayImage(this.width, this.height, this.data);

  final int width;
  final int height;
  final Float32List data;

  double at(int x, int y) => data[y * width + x];

  /// Bilinear sample at continuous pixel coordinates, clamped at the border.
  double sample(double x, double y) {
    final cx = x.clamp(0.0, width - 1.0);
    final cy = y.clamp(0.0, height - 1.0);
    final x0 = cx.floor(), y0 = cy.floor();
    final x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1);
    final fx = cx - x0, fy = cy - y0;
    final top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx;
    final bot = at(x0, y1) * (1 - fx) + at(x1, y1) * fx;
    return top * (1 - fy) + bot * fy;
  }
}

/// Ideal (continuous) intensity 0..1 at a scene point in mm.
typedef Scene = double Function(double xMm, double yMm);

/// Maps pixel coordinates to scene mm.
typedef PixelToScene = Pt Function(double px, double py);

/// Linear map `scene = (pixel - centerPx) * mmPerPx`. The default [centerPx] is
/// the centre of a 240 x 240 image; pass the real image centre for other sizes.
PixelToScene pixelToSceneLinear({required double mmPerPx, Pt centerPx = const Pt(119.5, 119.5)}) =>
    (px, py) => Pt((px - centerPx.x) * mmPerPx, (py - centerPx.y) * mmPerPx);

/// Renders [scene] to an 8-bit-quantised grayscale image.
///
/// Pipeline (physical order): sample the ideal scene on an S x S sub-pixel grid
/// per pixel; blur with a Gaussian PSF of [psfSigmaPx] (output pixels), applied at
/// sub-pixel resolution with replicated borders; integrate over each pixel (box
/// average, i.e. anti-aliasing); multiply by a linear illumination gradient
/// (relative change across the image, [illumGradX], [illumGradY]: 0.2 means +-10
/// percent); add Gaussian noise of [noiseSigma] (intensity units); clip to 0..1;
/// quantise to 8 bits. No OpenCV.
GrayImage renderGray({
  required int width,
  required int height,
  required PixelToScene toScene,
  required Scene scene,
  int supersample = 4,
  double psfSigmaPx = 0,
  double illumGradX = 0,
  double illumGradY = 0,
  double noiseSigma = 0,
  Random? rng,
  bool quantize8bit = true,
}) {
  final s = supersample;
  final w = width * s, h = height * s;
  var hi = Float64List(w * h);
  for (var j = 0; j < h; j++) {
    final py = (j + 0.5) / s - 0.5;
    for (var i = 0; i < w; i++) {
      final p = toScene((i + 0.5) / s - 0.5, py);
      hi[j * w + i] = scene(p.x, p.y);
    }
  }
  if (psfSigmaPx > 0) hi = _blur(hi, w, h, psfSigmaPx * s);

  final noise = noiseSigma > 0 ? (rng ?? Random(0)) : null;
  final out = Float32List(width * height);
  final inv = 1.0 / (s * s);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var b = 0; b < s; b++) {
        final row = (y * s + b) * w + x * s;
        for (var a = 0; a < s; a++) {
          sum += hi[row + a];
        }
      }
      var v = sum * inv;
      v *= 1 + illumGradX * ((x + 0.5) / width - 0.5) + illumGradY * ((y + 0.5) / height - 0.5);
      if (noise != null) v += noiseSigma * gaussian(noise);
      v = v.clamp(0.0, 1.0);
      if (quantize8bit) v = (v * 255).round() / 255;
      out[y * width + x] = v;
    }
  }
  return GrayImage(width, height, out);
}

/// Separable Gaussian blur, kernel radius 4 sigma, replicated borders.
Float64List _blur(Float64List src, int w, int h, double sigma) {
  final r = (4 * sigma).ceil();
  final k = [for (var i = -r; i <= r; i++) exp(-i * i / (2 * sigma * sigma))];
  final norm = k.reduce((a, b) => a + b);
  for (var i = 0; i < k.length; i++) {
    k[i] /= norm;
  }
  final tmp = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var t = -r; t <= r; t++) {
        acc += k[t + r] * src[y * w + (x + t).clamp(0, w - 1)];
      }
      tmp[y * w + x] = acc;
    }
  }
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var t = -r; t <= r; t++) {
        acc += k[t + r] * tmp[(y + t).clamp(0, h - 1) * w + x];
      }
      out[y * w + x] = acc;
    }
  }
  return out;
}

/// Synthetic crack of exactly known width, in scene mm.
///
/// The crack is the set of points within `widthMm / 2` of its centreline, so the
/// width is exact along the whole length. The centreline passes through
/// [centerMm] with direction [directionDeg] (angle of the direction vector from the
/// scene x axis; y points down) and bends with signed curvature [curvaturePerMm]
/// (a circular arc, positive towards the normal `(-sin, cos)`). Intensity is
/// `background * (1 - depth)` inside and `background` outside.
Scene crackScene({
  required double widthMm,
  double depth = 0.6,
  double directionDeg = 0,
  double curvaturePerMm = 0,
  Pt centerMm = const Pt(0, 0),
  double background = 0.8,
}) {
  final a = directionDeg * pi / 180;
  final dx = cos(a), dy = sin(a);
  final nx = -dy, ny = dx;
  final half = widthMm / 2;
  final inside = background * (1 - depth);
  return (x, y) {
    final px = x - centerMm.x, py = y - centerMm.y;
    final double dist;
    if (curvaturePerMm == 0) {
      dist = (px * nx + py * ny).abs();
    } else {
      final r = 1 / curvaturePerMm; // signed
      final cx = nx * r, cy = ny * r; // arc centre relative to centerMm
      dist = (sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)) - r.abs()).abs();
    }
    return dist <= half ? inside : background;
  };
}

/// The four marker squares of sheet [sheetId] as ink on paper. Marker interiors
/// are solid (the bit pattern is irrelevant for edge and PSF tests).
Scene sheetScene({
  required int sheetId,
  double printScale = 1,
  double paper = 0.9,
  double ink = 0.05,
}) {
  final h = markerSideMm / 2 * printScale;
  final centers = [
    for (final id in markerIdsForSheet(sheetId)) markerCenterMm(id, printScale: printScale),
  ];
  return (x, y) {
    for (final c in centers) {
      if ((x - c.x).abs() <= h && (y - c.y).abs() <= h) return ink;
    }
    return paper;
  };
}

/// Effective crack width: the integral of `(1 - I/background) / depth` along the
/// line through [centerPx] perpendicular to [directionDeg]. Independent of the PSF
/// (area preserving), so it can validate the renderer. Assumes no illumination
/// gradient. [halfRangeMm] must cover the crack and the PSF tails.
double effectiveWidthMm(
  GrayImage img, {
  required double mmPerPx,
  required double directionDeg,
  required double background,
  required double depth,
  double halfRangeMm = 2,
  Pt? centerPx,
}) {
  final c = centerPx ?? Pt((img.width - 1) / 2, (img.height - 1) / 2);
  final a = directionDeg * pi / 180;
  final nx = -sin(a), ny = cos(a);
  const sub = 4;
  final stepMm = mmPerPx / sub;
  final n = (halfRangeMm / stepMm).round();
  var sum = 0.0;
  for (var i = -n; i <= n; i++) {
    final s = i * stepMm / mmPerPx;
    sum += (1 - img.sample(c.x + nx * s, c.y + ny * s) / background) / depth;
  }
  return sum * stepMm;
}
