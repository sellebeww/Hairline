// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// Characterises a printed validation plate from a flatbed scan, with the SAME core measurement
// the app uses (ridge tracking, profile model, sub-pixel width), and writes the truth CSV
// (`posisi,lebar_mm,u_mm`) that the app imports.
//
//   cd tools && dart pub get
//   dart run measure_scan.dart --image scan.pgm --dpi 2400 --origin 4210,4180 --out truth.csv
//     [--angle 0] [--sigma-px 1.5] [--linear] [--scale-u-rel 0.005]
//
// Scan the plate (flat, face down, edges parallel to the glass) at 1200 dpi or more, gray, 8 or 16
// bit, no sharpening, no descreening, no automatic enhancement. Convert to PGM:
//   magick scan.tif -colorspace Gray scan.pgm
// --origin is the pixel of the window centre (the middle of the 70 mm square). Any image viewer
// that shows pixel coordinates gives it; an error below 1 mm is absorbed by the ridge search.
// --angle is the clockwise rotation of the plate in the scan, in degrees (0 when placed square).
// If the four markers are inside the scan their edges give the blur of the scanner; otherwise
// --sigma-px (the scanner blur in pixels, default 1.5) is used.
import 'dart:io';

import 'package:hairline_core/hairline_core.dart';

const _usage = 'Usage: dart run measure_scan.dart --image scan.pgm --dpi 2400 --origin X,Y [--out truth.csv] '
    '[--angle DEG] [--sigma-px PX] [--linear] [--scale-u-rel 0.005]';

Future<int> main(List<String> args) async {
  final opts = <String, String>{};
  var linear = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--linear') {
      linear = true;
    } else if (a.startsWith('--') && i + 1 < args.length) {
      opts[a.substring(2)] = args[++i];
    } else {
      stderr.writeln('Argumen tidak dikenal: $a\n$_usage');
      return 64;
    }
  }
  final image = opts['image'], dpi = double.tryParse(opts['dpi'] ?? ''), origin = (opts['origin'] ?? '').split(',');
  final ox = origin.length == 2 ? double.tryParse(origin[0]) : null, oy = origin.length == 2 ? double.tryParse(origin[1]) : null;
  final angle = double.tryParse(opts['angle'] ?? '0'), sigma = double.tryParse(opts['sigma-px'] ?? '1.5');
  final scaleU = double.tryParse(opts['scale-u-rel'] ?? '$defaultScanScaleURel');
  if (image == null || dpi == null || ox == null || oy == null || angle == null || sigma == null || scaleU == null) {
    stderr.writeln(_usage);
    return 64;
  }
  try {
    final pgm = PgmImage.parse(await File(image).readAsBytes());
    final lines = measurePlateScan(
      image: pgm,
      dpi: dpi,
      originPx: Pt(ox, oy),
      angleDeg: angle,
      sigmaPx: sigma,
      linear: linear,
      scaleURel: scaleU,
    );
    for (final l in lines) {
      stderr.writeln(l.status == 'TERUKUR'
          ? '${l.id}\tnominal ${l.nominalMm}\tlebar ${l.widthMm!.toStringAsFixed(4)} +- ${l.uMm!.toStringAsFixed(4)} mm'
          : '${l.id}\tnominal ${l.nominalMm}\t${l.status}: ${l.message}');
    }
    final csv = scanMeasurementsToCsv(lines);
    final out = opts['out'];
    if (out == null) {
      stdout.write(csv);
    } else {
      await File(out).writeAsString(csv);
      stderr.writeln('Ditulis: $out');
    }
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('Galat berkas: ${e.message}');
  } on ArgumentError catch (e) {
    stderr.writeln('Galat parameter: ${e.message}');
  } on PlateTruthException catch (e) {
    stderr.writeln('Terlalu sedikit garis terukur untuk membuat CSV: ${e.message} Periksa --origin, --angle dan --dpi.');
  } on FileSystemException catch (e) {
    stderr.writeln('Galat berkas: ${e.message}');
  }
  return 1;
}
