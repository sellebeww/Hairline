// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// Full synthetic study (CLAUDE.md phase 4, items 6 and 7). Two steps:
//   dart run tool/run_synthetic_study.dart simulate [--reps 8] [--rep-start 0] [--workers 8]
//       Simulates every condition of the grid (864) x reps visits of 5 frames through the
//       real chain and appends one JSON line per visit to build/synthetic_study/frames.jsonl
//       (resumable: finished (condition, replication) pairs are skipped).
//   dart run tool/run_synthetic_study.dart analyze
//   dart run tool/run_synthetic_study.dart renderer-check
//       Re-renders the two worst cells of the calibration (2.0 mm cracks at 0.15 mm/px, which the
//       exact-truth coverage flags) with supersample 4 and 8 and writes build/synthetic_study/renderer_check.md.
//   dart run tool/run_synthetic_study.dart analyze
//       Calibrates rho from the stored frames and writes docs/SYNTHETIC_VALIDATION.md and
//       docs/SYNTHETIC_VALIDATION_CONDITIONS.csv.
// Every number in those documents comes from this program (seed 20261117).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hairline_core/synthetic.dart';

import 'study_report.dart';

const _dir = 'build/synthetic_study';

Future<void> main(List<String> args) async {
  final cmd = args.isEmpty ? 'help' : args.first;
  int opt(String name, int def) {
    final i = args.indexOf('--$name');
    return i >= 0 ? int.parse(args[i + 1]) : def;
  }

  switch (cmd) {
    case 'simulate':
      await simulate(reps: opt('reps', 8), repStart: opt('rep-start', 0), workers: opt('workers', 8));
    case 'worker':
      worker(reps: opt('reps', 8), repStart: opt('rep-start', 0), shard: opt('shard', 0), shards: opt('shards', 1));
    case 'renderer-check':
      rendererCheck();
    case 'analyze':
      analyze(framesDir: _dir);
    default:
      stdout.writeln('usage: run_synthetic_study.dart simulate [--reps N] [--rep-start N] [--workers N] | renderer-check | analyze');
  }
}

Set<String> _doneVisits() {
  final done = <String>{};
  final dir = Directory(_dir);
  if (!dir.existsSync()) return done;
  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'))) {
    for (final line in f.readAsLinesSync()) {
      final j = jsonDecode(line) as Map<String, Object?>;
      done.add('${j['c']}/${j['r']}');
    }
  }
  return done;
}

/// One shard of the visits, run in its own process (isolates of one group share a heap and
/// its stop-the-world garbage collection, which made 8 isolates 8 times slower than one).
void worker({required int reps, required int repStart, required int shard, required int shards}) {
  final done = _doneVisits();
  final grid = studyGrid();
  final sink = File('$_dir/frames_$shard.jsonl').openSync(mode: FileMode.append);
  var n = 0;
  for (var r = repStart; r < repStart + reps; r++) {
    for (final c in grid) {
      if ((c.index * 31 + r) % shards != shard || done.contains('${c.index}/$r')) continue;
      final frames = simulateVisit(c, r);
      sink.writeStringSync('${jsonEncode({'c': c.index, 'r': r, 'f': [for (final f in frames) frameInputToJson(f)]})}\n');
      sink.flushSync();
      n++;
    }
  }
  sink.closeSync();
  stdout.writeln('worker $shard done: $n visits');
}

Future<void> simulate({required int reps, required int repStart, required int workers}) async {
  Directory(_dir).createSync(recursive: true);
  stdout.writeln('study: ${studyGrid().length} conditions, replications $repStart..${repStart + reps - 1}, '
      '${_doneVisits().length} visits already stored, $workers worker processes');
  final sw = Stopwatch()..start();
  final procs = [
    for (var i = 0; i < workers; i++)
      await Process.start(Platform.resolvedExecutable, ['run', 'tool/run_synthetic_study.dart', 'worker', '--reps', '$reps', '--rep-start', '$repStart', '--shard', '$i', '--shards', '$workers']),
  ];
  await Future.wait([
    for (final p in procs) ...[p.stdout.transform(utf8.decoder).forEach(stdout.write), p.stderr.transform(utf8.decoder).forEach(stderr.write), p.exitCode],
  ]);
  stdout.writeln('done in ${(sw.elapsed.inSeconds / 60).toStringAsFixed(1)} min, ${_doneVisits().length} visits stored');
}

/// Is the residual error of wide cracks the renderer's? Same noise draws, supersample 4 vs 8.
void rendererCheck() {
  final g = studyGrid();
  final cells = [
    g.firstWhere((c) => c.widthMm == 2.0 && c.mmPerPx == 0.15 && c.sigmaPx == 0.6 && c.noise == 3 && c.tiltDeg == 0),
    g.firstWhere((c) => c.widthMm == 2.0 && c.mmPerPx == 0.15 && c.sigmaPx == 1.0 && c.noise == 6 && c.tiltDeg == 0),
  ];
  final out = StringBuffer('| lebar (mm) | mm/px | sigma (px) | derau | S | galat replikasi 0..4 (um) | RMS (um) |\n|---|---|---|---|---|---|---|\n');
  for (final c in cells) {
    for (final ss in [4, 8]) {
      final e = [
        for (var r = 0; r < 5; r++)
          (replayVisit(c, r, simulateVisit(c, r, config: StudyConfig(supersample: ss)), rho: 1).errorMm ?? double.nan) * 1000,
      ];
      final rms = sqrt(e.fold<double>(0, (s, x) => s + x * x) / e.length);
      out.writeln('| ${c.widthMm} | ${c.mmPerPx} | ${c.sigmaPx} | ${c.noise.round()} | $ss | ${e.map((x) => x.toStringAsFixed(1)).join(' ')} | ${rms.toStringAsFixed(1)} |');
    }
  }
  File('$_dir/renderer_check.md').writeAsStringSync(out.toString());
  stdout.write(out);
}
