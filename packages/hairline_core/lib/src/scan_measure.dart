// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:math';
import 'dart:typed_data';

import 'frame_ports.dart';
import 'homography.dart';
import 'linalg_small.dart';
import 'measure.dart';
import 'patch.dart';
import 'plate.dart';
import 'point.dart';
import 'psf.dart';
import 'quality.dart';
import 'sheet.dart';

// Characterisation of a printed validation plate from a flatbed scan (`tools/measure_scan.dart`).
// The scan is not a perspective image: sheet mm map to pixels by a similarity (dpi, rotation,
// origin), and the SAME core measurement (`measureFrame`: ridge tracking, profile model,
// sub-pixel width) runs on it. The result is the effective printed width, the same definition
// the phone measures (the area of the dark profile), including dot gain.

/// A binary PGM (`P5`, 8 or 16 bit, big endian) held in memory. Scanner software and
/// ImageMagick (`magick scan.tif -colorspace Gray scan.pgm`) write it.
final class PgmImage implements DecodedImage {
  PgmImage._(this.width, this.height, this._maxval, this._data);

  /// Largest side accepted (pixels): 2400 dpi A4 is 19843 x 28063.
  static const int maxSide = 40000;

  /// Throws [FormatException] (message in Indonesian) for anything that is not a complete P5 file.
  factory PgmImage.parse(Uint8List bytes) {
    var pos = 0;
    String? token() {
      while (pos < bytes.length) {
        final c = bytes[pos];
        if (c == 0x23) {
          while (pos < bytes.length && bytes[pos] != 0x0A) {
            pos++;
          }
        } else if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
          pos++;
        } else {
          break;
        }
      }
      final start = pos;
      while (pos < bytes.length && !(bytes[pos] == 0x20 || bytes[pos] == 0x09 || bytes[pos] == 0x0A || bytes[pos] == 0x0D)) {
        pos++;
      }
      return pos == start ? null : String.fromCharCodes(bytes, start, pos);
    }

    if (token() != 'P5') throw const FormatException('Bukan berkas PGM biner (P5). Ekspor pindaian sebagai PGM abu-abu.');
    final w = int.tryParse(token() ?? ''), h = int.tryParse(token() ?? ''), maxval = int.tryParse(token() ?? '');
    if (w == null || h == null || maxval == null || w < 1 || h < 1 || w > maxSide || h > maxSide || maxval < 1 || maxval > 65535) {
      throw const FormatException('Header PGM tidak valid.');
    }
    pos++; // exactly one whitespace byte follows maxval
    final bytesPerSample = maxval > 255 ? 2 : 1;
    if (bytes.length - pos < w * h * bytesPerSample) throw const FormatException('Berkas PGM terpotong.');
    return PgmImage._(w, h, maxval, Uint8List.sublistView(bytes, pos, pos + w * h * bytesPerSample));
  }

  @override
  final int width;
  @override
  final int height;
  final int _maxval;
  final Uint8List _data;

  @override
  GrayPatch extractPatch(int x, int y, int w, int h) {
    if (x < 0 || y < 0 || x + w > width || y + h > height) throw RangeError('patch outside the image');
    final out = Float32List(w * h);
    final wide = _maxval > 255;
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final k = (y + j) * width + x + i;
        out[j * w + i] = (wide ? (_data[2 * k] << 8) | _data[2 * k + 1] : _data[k]) / _maxval;
      }
    }
    return GrayPatch(originX: x, originY: y, width: w, height: h, data: out);
  }

  @override
  void dispose() {}
}

/// Default relative uncertainty of the scan scale (`dpi`): flatbed scanners are
/// specified to about 0.5 percent. A conservative placeholder, NOT a calibration.
const double defaultScanScaleURel = 0.005;

/// One plate line measured on a scan.
final class ScanLineMeasurement {
  const ScanLineMeasurement({required this.id, required this.nominalMm, required this.status, this.widthMm, this.uMm, this.message});

  final String id;
  final double nominalMm;

  /// `TERUKUR`, or why not (`TIDAK_TERUKUR`, `DI_BAWAH_BATAS_UKUR`, `DITOLAK`, `DI_LUAR_PINDAIAN`).
  final String status;

  /// Effective width and standard uncertainty (mm) when [status] is `TERUKUR`.
  final double? widthMm, uMm;
  final String? message;
}

/// Measures the 32 lines of a scanned plate.
///
/// [dpi] is the scan resolution; [originPx] the pixel (pixel centres are integers) where the
/// sheet origin (centre of the window) falls; [angleDeg] the clockwise rotation of the plate
/// in the scan (the ridge search tolerates about 1.5 mm of mispositioning). The PSF comes from the
/// marker edges when all four markers are inside the scan, else from [sigmaPx] (required then).
/// `u_mm = sqrt(u_fit^2 + u_sigma_w^2 + (w u_scale)^2)`; [scaleURel] is the relative uncertainty of
/// the scale. [linear] true if the scan values are already linear light (default: gamma encoded,
/// linearized like phone photos). Quality gates that only make sense for phone photos
/// (blur, tilt) are relaxed: a flatbed scan is sharp but its PSF in pixels grows with dpi.
List<ScanLineMeasurement> measurePlateScan({
  required DecodedImage image,
  required double dpi,
  required Pt originPx,
  double angleDeg = 0,
  double? sigmaPx,
  bool linear = false,
  double scaleURel = defaultScanScaleURel,
}) {
  if (!(dpi >= 100 && dpi <= 9600) || !originPx.isFinite || !angleDeg.isFinite || !(scaleURel >= 0 && scaleURel <= 0.1)) {
    throw ArgumentError('dpi must be within 100..9600, origin and angle finite, scale uncertainty within 0..0.1');
  }
  if (sigmaPx != null && !(sigmaPx > 0.2 && sigmaPx < 30)) throw ArgumentError.value(sigmaPx, 'sigmaPx', 'must be within 0.2..30 px');
  final s = dpi / 25.4;
  final a = angleDeg * pi / 180, c = cos(a), sn = sin(a);
  final Mat3 h = [s * c, -s * sn, originPx.x, s * sn, s * c, originPx.y, 0, 0, 1];
  GrayPatch? extract(Pt centre, double halfMm) {
    final xs = <double>[], ys = <double>[];
    for (final dx in [-halfMm, halfMm]) {
      for (final dy in [-halfMm, halfMm]) {
        final p = applyHomography(h, Pt(centre.x + dx, centre.y + dy));
        xs.add(p.x);
        ys.add(p.y);
      }
    }
    final x0 = xs.reduce(min).floor() - 3, x1 = xs.reduce(max).ceil() + 3;
    final y0 = ys.reduce(min).floor() - 3, y1 = ys.reduce(max).ceil() + 3;
    if (x0 < 0 || y0 < 0 || x1 >= image.width || y1 >= image.height) return null;
    final p = image.extractPatch(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
    return linear ? p : p.linearizedFromSrgb();
  }

  final markerPatches = <int, GrayPatch>{};
  for (final id in markerIdsForSheet(plateSheetId)) {
    final p = extract(markerCenterMm(id), markerSideMm / 2 + 14 / s);
    if (p != null) markerPatches[id] = p;
  }
  final PsfEstimate psf;
  if (markerPatches.length == 4) {
    psf = estimatePsfFromPatches(patches: markerPatches, h: h);
  } else if (sigmaPx != null) {
    psf = PsfEstimate(edges: const [], sigmaPx: sigmaPx, uSigmaPx: 0.25 * sigmaPx, sigmaMm: sigmaPx / s, uSigmaMm: 0.25 * sigmaPx / s, anisotropy: null);
  } else {
    throw ArgumentError('the scan does not contain the four markers: give sigmaPx (the blur of the scanner in pixels)');
  }

  const thresholds = QualityThresholds(maxSigmaPx: 30, maxBlurAnisotropy: 10, maxSaturatedFraction: 1);
  final out = <ScanLineMeasurement>[];
  for (final l in buildPlateLines()) {
    ScanLineMeasurement fail(String status, String message) =>
        ScanLineMeasurement(id: l.id, nominalMm: l.nominalMm, status: status, message: message);
    final patch = extract(l.centreMm, 8);
    if (patch == null) {
      out.add(fail('DI_LUAR_PINDAIAN', 'Garis berada di luar pindaian: periksa titik asal (origin) dan sudut.'));
      continue;
    }
    final r = measureFrame(
      patch: patch,
      h: h,
      pointMm: l.centreMm,
      directionDeg: l.directionDeg,
      sheetId: plateSheetId,
      psf: psf,
      thresholds: thresholds,
    );
    switch (r) {
      case MeasureRejected(:final message):
        out.add(fail('DITOLAK', message));
      case MeasureAccepted(:final measurement):
        if (measurement.status != MeasureStatus.terukur) {
          out.add(fail('TIDAK_TERUKUR', 'Garis tidak terukur pada pindaian ini.'));
        } else if (measurement.widthMm < measurement.floorMm) {
          out.add(fail('DI_BAWAH_BATAS_UKUR', 'Lebar di bawah batas ukur pindaian: naikkan dpi.'));
        } else {
          final w = measurement.widthMm;
          final u = sqrt(pow(measurement.uFitMm, 2) + pow(measurement.uSigmaWMm, 2) + pow(w * scaleURel, 2));
          out.add(ScanLineMeasurement(id: l.id, nominalMm: l.nominalMm, status: 'TERUKUR', widthMm: w, uMm: u));
        }
    }
  }
  return out;
}

/// CSV `posisi,lebar_mm,u_mm` of the measured lines (importable as plate truth). Throws
/// [PlateTruthException] when fewer than 8 lines were measured; the text is re-read by
/// [PlateTruth.fromCsv] so it can never produce a file the app would reject.
String scanMeasurementsToCsv(List<ScanLineMeasurement> lines) {
  final buf = StringBuffer('posisi,lebar_mm,u_mm\n');
  for (final l in lines) {
    if (l.status == 'TERUKUR') buf.writeln('${l.id},${l.widthMm!.toStringAsFixed(4)},${l.uMm!.toStringAsFixed(4)}');
  }
  final text = buf.toString();
  PlateTruth.fromCsv(text);
  return text;
}
