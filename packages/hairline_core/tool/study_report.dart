// Copyright (c) 2026 Vassel Goleyu. MIT License.
//
// Reads the stored study frames, calibrates rho and writes the validation documents.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hairline_core/hairline_core.dart';
import 'package:hairline_core/synthetic.dart';

const _candidates = <double>[1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64];
const _target = 0.9;

StudyFrames _load(String dir) {
  final StudyFrames data = {};
  for (final f in Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'))) {
    for (final line in f.readAsLinesSync()) {
      final j = jsonDecode(line) as Map<String, Object?>;
      (data[j['c']! as int] ??= {})[j['r']! as int] = [
        for (final x in j['f']! as List<Object?>) frameInputFromJson(x! as Map<String, Object?>),
      ];
    }
  }
  return data;
}

String _um(double mm) => mm.isNaN ? '-' : (mm * 1000).toStringAsFixed(1);
String _pct(double v) => v.isNaN ? '-' : (100 * v).toStringAsFixed(1);
String _q(List<double> sorted, double p) => sorted.isEmpty ? '-' : sorted[((sorted.length - 1) * p).round()].toStringAsFixed(3);
String _mm(double? v) => v == null ? 'tidak ada' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Pooled numbers of a set of cells.
final class _Pool {
  _Pool(Iterable<CellResult> cs) : cells = cs.toList();
  final List<CellResult> cells;
  int get visits => cells.fold(0, (s, c) => s + c.summary.visits);
  int get terukur => cells.fold(0, (s, c) => s + c.reported);
  int get dibawah => cells.fold(0, (s, c) => s + c.summary.dibawahBatas);
  int get tidak => cells.fold(0, (s, c) => s + c.summary.tidakTerukur);
  int get ditolak => cells.fold(0, (s, c) => s + c.summary.ditolak);
  double get bias => terukur == 0 ? double.nan : cells.fold(0.0, (s, c) => s + (c.reported == 0 ? 0 : c.summary.biasMm * c.reported)) / terukur;
  double get rmse => terukur == 0 ? double.nan : sqrt(cells.fold(0.0, (s, c) => s + (c.reported == 0 ? 0 : c.summary.rmseMm * c.summary.rmseMm * c.reported)) / terukur);
  double get covFit => terukur == 0 ? double.nan : cells.fold(0, (s, c) => s + c.coveredFitOnly) / terukur;
  double get covFitStrict => terukur == 0 ? double.nan : cells.fold(0, (s, c) => s + c.coveredFitOnlyStrict) / terukur;
  double get covFitHalf => terukur == 0 ? double.nan : cells.fold(0, (s, c) => s + c.coveredFitOnlyHalf) / terukur;
  double get covRandom => terukur == 0 ? double.nan : cells.fold(0, (s, c) => s + c.coveredRandom) / terukur;
  double get covDefault => terukur == 0 ? double.nan : cells.fold(0, (s, c) => s + c.coveredDefault) / terukur;
  double medianOfCells(double Function(CellResult) f) {
    final v = [for (final c in cells) f(c)].where((x) => !x.isNaN).toList()..sort();
    return v.isEmpty ? double.nan : v[v.length ~/ 2];
  }
}

String _table(List<String> header, List<List<String>> rows) =>
    '| ${header.join(' | ')} |\n|${List.filled(header.length, '---').join('|')}|\n${rows.map((r) => '| ${r.join(' | ')} |').join('\n')}\n';

List<String> _poolRow(String label, _Pool p) => [
      label,
      '${p.visits}',
      '${p.terukur}',
      '${p.dibawah}',
      '${p.tidak}',
      '${p.ditolak}',
      _um(p.bias),
      _um(p.rmse),
      _pct(p.covFit),
      _pct(p.covRandom),
      _pct(p.covDefault),
      _um(p.medianOfCells((c) => c.summary.medianUExpandedMm)),
      _um(p.medianOfCells((c) => c.summary.medianFloorMm)),
    ];

const _poolHeader = [
  'kelompok', 'kunjungan', 'TERUKUR', 'DI_BAWAH', 'TIDAK_TERUKUR', 'DITOLAK', //
  'bias (um)', 'RMSE (um)', 'cakupan fit (%)', 'cakupan acak (%)', 'cakupan bawaan (%)', 'U median (um)', 'batas ukur median (um)',
];

/// Replications present for every one of the 864 conditions.
Set<int> _completeReps(StudyFrames all) {
  final grid = studyGrid().length;
  final count = <int, int>{};
  for (final m in all.values) {
    for (final r in m.keys) {
      count[r] = (count[r] ?? 0) + 1;
    }
  }
  return {for (final e in count.entries) if (e.value == grid) e.key};
}

StudyFrames _subset(StudyFrames all, bool Function(int rep) keep) => {
      for (final e in all.entries) e.key: {for (final r in e.value.entries) if (keep(r.key)) r.key: r.value},
    };

/// Calibrates on the complete replications below [calReps] and checks the chosen `rho`
/// on the complete replications from [calReps] on (hold-out: not used to choose `rho`).
void analyze({required String framesDir, int calReps = 5}) {
  final all = _load(framesDir);
  final complete = _completeReps(all);
  final data = _subset(all, (r) => complete.contains(r) && r < calReps);
  final hold = _subset(all, (r) => complete.contains(r) && r >= calReps);
  final holdReps = complete.where((r) => r >= calReps).length;
  final reps = complete.where((r) => r < calReps).length;
  final visits = data.values.fold(0, (s, m) => s + m.length);
  stdout.writeln('calibration: $reps complete replications ($visits visits); hold-out: $holdReps complete replications');

  final cal = calibrateRho(data, candidates: _candidates, target: _target);
  final rho = cal.rho ?? _candidates.last;
  final curve = [for (final r in _candidates) r <= rho || cal.rho == null ? cal.curve.firstWhere((e) => e.rho == r) : evaluateStudy(data, r)];
  final before = curve.first;
  final after = curve.firstWhere((e) => e.rho == rho);
  stdout.writeln('rho = ${cal.rho} (curve: ${curve.map((e) => '${e.rho}:${_pct(e.coverageFitOnly)}/${_pct(e.coverageFitOnlyStrict)}').join(' ')})');

  final md = StringBuffer();
  void w(String s) => md.writeln(s);
  w('# Validasi sintetis (SINTETIS)\n');
  w('Label: **SINTETIS**. Semua angka di dokumen ini dihasilkan oleh `packages/hairline_core/tool/run_synthetic_study.dart` '
      '(seed tetap 20261117, algoritma `$measurementAlgorithmVersion`, core `$hairlineCoreVersion`). Tidak ada ponsel, kamera, atau pelat cetak nyata. '
      'Hasil membuktikan perilaku pada simulasi saja; akurasi dan cakupan pada perangkat nyata BELUM terbukti (butuh validasi pelat `PERANGKAT`).\n');
  w('## 1. Desain studi\n');
  w('- Grid penuh: lebar {0,1; 0,2; 0,3; 0,5; 1,0; 2,0} mm x mm/px {0,04; 0,06; 0,10; 0,15} x sigma blur {0,6; 1,0; 1,5; 2,0} px x derau {1; 3; 6} tingkat abu-abu 8 bit (sd) x tilt {0; 10; 20} derajat = ${studyGrid().length} kondisi.');
  w('- Replikasi: $reps kunjungan per kondisi untuk kalibrasi (replikasi 0 sampai ${calReps - 1}), ditambah $holdReps replikasi hold-out (tidak dipakai memilih `rho`), tiap kunjungan 5 frame (burst), total $visits kunjungan dan ${visits * 5} frame. Pose acak per kunjungan (azimut tilt 0..360, roll +-20 derajat, geser +-10 mm, f 0,7..0,9 sisi panjang), derau sudut penanda 0,2 px, arah retak acak (hindari sumbu piksel), arah tersimpan meleset U(-3, 3) derajat, retak menyimpang U(-0,3, 0,3) mm dari titik tersimpan. Kontras retak: kedalaman 0,4 dari latar 0,8 (82 tingkat abu-abu). Skala mm/px adalah skala geometrik di titik ukur.');
  w('- Rantai nyata: deteksi sudut berderau -> homografi (DLT + LM) -> estimasi tilt (f_px bawaan 0,75 x sisi panjang, sedangkan f sebenarnya 0,7..0,9) -> gerbang geometri 5.4 -> render patch retak (supersample 4, PSF, derau, kuantisasi 8 bit) -> PSF dari tepi penanda (patch penanda terpisah 0,25 mm/px dengan blur, derau, dan sudut pandang yang sama) -> `measureFrame` -> `aggregateVisit` (median, anggaran 5.5).');
  w('- Anggaran: `u_print_rel = 0` (tidak ada galat cetak), `dz = 0,3 mm`, tanpa validasi perangkat sehingga `u_dev = 0,5 mm/px` (BELUM_DIVALIDASI). Ketidakpastian kebenaran `u_truth`: renderer tidak eksak, tiap sampel tepi meleset paling banyak 0,5/S px (S = 4, D18); dianggap seragam, dua tepi per lebar: `u_truth = sqrt(2) x 0,5 / (4 sqrt(3)) = 0,1021 px x mm/px` (0,004 sampai 0,015 mm). Interval gabungan `k sqrt(u_c^2 + u_truth^2)`, persis seperti pelat bersertifikat; kolom "ketat" memakai `u_truth = 0`.');
  w('- Terukur dihitung hanya pada kunjungan yang dilaporkan aplikasi (status TERUKUR). Galat = terukur - kebenaran. Cakupan = fraksi kunjungan dengan |galat| <= U.');
  w('- Tiga tingkat cakupan: **fit** = `k sqrt(u_stat^2 + u_sigma_w^2)` (bagian yang diinflasi `rho`; dipakai untuk kalibrasi), **acak** = `U` dengan `u_dev = u_print = 0` (menambah `u_pos`, `u_par`, `u_geo`; `u_par` mengandaikan relief 0,3 mm yang tidak ada di adegan sintetis, jadi konservatif), **bawaan** = `U` anggaran lengkap yang dilihat pengguna.');
  w('- Keterbatasan simulasi: frame dalam satu burst berbagi pose dan render bebas-derau (getaran tangan tidak disimulasikan, sehingga `u_repeat` bisa terlalu kecil dibanding burst nyata; pose berbeda antar kunjungan, jadi cakupan antar kunjungan tetap melihat efeknya); PSF diestimasi dari patch penanda dengan homografi sebenarnya patch itu; kernel render Gaussian dikonvolusi apertur kotak, sedangkan ponsel nyata punya penajaman ISP dan JPEG.\n');

  w('## 2. Kalibrasi `rho`\n');
  w('Kriteria: cakupan fit gabungan >= ${(_target * 100).round()} persen DAN tidak ada kondisi yang secara statistik di bawah ${(_target * 100).round()} persen (batas atas interval Wilson 95 persen < ${(_target * 100).round()} persen). '
      'Kondisi yang titik estimasinya di bawah 90 persen tetapi tidak signifikan (misalnya 7 dari 8) dihitung terpisah.\n');
  w(_table(
    ['rho', 'cakupan fit (%)', 'fit ketat u_truth=0 (%)', 'cakupan acak (%)', 'cakupan bawaan (%)', 'kondisi < 90% (titik)', 'kondisi < 90% (signifikan)', 'kondisi < 90% (signifikan, ketat)'],
    [
      for (final e in curve)
        ['${e.rho}', _pct(e.coverageFitOnly), _pct(e.coverageFitOnlyStrict), _pct(e.coverageRandom), _pct(e.coverageDefault), '${e.cellsBelowPoint(_target)}', '${e.cellsSignificantlyBelow(_target)}', '${e.unreliableCellsStrict(_target).length}'],
    ],
  ));
  w(cal.rho != null
      ? '\n**`rho` terpilih = ${cal.rho}** (nilai terkecil yang memenuhi kriteria; kriteria memakai `u_truth` renderer). Nilai sebelumnya `rho = 1,0` tidak dikalibrasi; kini dikalibrasi terhadap simulasi dan tetap 1,0. '
          'Kolom ketat (`u_truth = 0`) menunjukkan sisanya: sel lebar 2,0 mm yang galat sebenarnya hanya beberapa um sampai 0,15 px; lihat bagian 6 dan percobaan renderer.\n'
      : '\n**Tidak ada `rho` yang memenuhi kriteria** sampai ${_candidates.last}. Lihat bagian 6 (kondisi tidak andal).\n');

  w('## 3. Cakupan sebelum dan sesudah kalibrasi\n');
  w('Per lebar, semua kondisi lain dipool (kunjungan TERUKUR). Sebelum: `rho = 1`. Sesudah: `rho = $rho`. Kolom "pada U/2" mengukur kekonservatifan: bila cakupan fit pada setengah lebar interval masih tinggi, interval lebih dari dua kali lebih lebar daripada yang dibutuhkan (aman tetapi mengurangi daya deteksi tren).\n');
  w(_table(
    ['lebar (mm)', 'TERUKUR', 'fit sebelum (%)', 'fit sesudah (%)', 'fit ketat sebelum (%)', 'fit ketat sesudah (%)', 'fit sesudah pada U/2 (%)', 'acak sebelum (%)', 'acak sesudah (%)', 'bawaan sebelum (%)', 'bawaan sesudah (%)'],
    [
      for (final wd in studyWidthsMm)
        () {
          final b = _Pool(before.cells.where((c) => c.condition.widthMm == wd)), a = _Pool(after.cells.where((c) => c.condition.widthMm == wd));
          return ['$wd', '${a.terukur}', _pct(b.covFit), _pct(a.covFit), _pct(b.covFitStrict), _pct(a.covFitStrict), _pct(a.covFitHalf), _pct(b.covRandom), _pct(a.covRandom), _pct(b.covDefault), _pct(a.covDefault)];
        }(),
      () {
        final b = _Pool(before.cells), a = _Pool(after.cells);
        return ['**semua**', '${a.terukur}', _pct(b.covFit), _pct(a.covFit), _pct(b.covFitStrict), _pct(a.covFitStrict), _pct(a.covFitHalf), _pct(b.covRandom), _pct(a.covRandom), _pct(b.covDefault), _pct(a.covDefault)];
      }(),
    ],
  ));
  w('\nKekonservatifan: persentil ke-95 dari `|galat| / U` per lebar (nilai 1,0 berarti tepat 95 persen cakupan; makin kecil makin lebar intervalnya dibanding galat yang terjadi). "fit ketat" memakai interval fit tanpa `u_truth`; "bawaan" memakai `U` anggaran lengkap dengan `u_truth`.\n');
  w(_table(
    ['lebar (mm)', 'p95 galat/U fit ketat', 'p95 galat/U bawaan', 'median galat/U bawaan'],
    [
      for (final wd in studyWidthsMm)
        () {
          final cs = after.cells.where((c) => c.condition.widthMm == wd).toList();
          final fit = [for (final c in cs) ...c.errorOverUFitStrict]..sort(), def = [for (final c in cs) ...c.errorOverUDefault]..sort();
          return ['$wd', _q(fit, 0.95), _q(def, 0.95), _q(def, 0.5)];
        }(),
      () {
        final fit = [for (final c in after.cells) ...c.errorOverUFitStrict]..sort(), def = [for (final c in after.cells) ...c.errorOverUDefault]..sort();
        return ['**semua**', _q(fit, 0.95), _q(def, 0.95), _q(def, 0.5)];
      }(),
    ],
  ));
  Evaluation? holdEval;
  w('\n### Hold-out (replikasi tidak dipakai untuk kalibrasi)\n');
  if (holdReps == 0) {
    w('Belum ada replikasi hold-out yang lengkap.\n');
  } else {
    final hb = evaluateStudy(hold, 1), ha = evaluateStudy(hold, rho);
    holdEval = ha;
    w('$holdReps replikasi x ${studyGrid().length} kondisi, seed yang berbeda dari kalibrasi (replikasi >= $calReps). `rho` tetap $rho.\n');
    w(_table(
      ['lebar (mm)', 'TERUKUR', 'fit rho=1 (%)', 'fit rho=$rho (%)', 'fit pada U/2 (%)', 'acak (%)', 'bawaan (%)'],
      [
        for (final wd in studyWidthsMm)
          () {
            final b = _Pool(hb.cells.where((c) => c.condition.widthMm == wd)), a = _Pool(ha.cells.where((c) => c.condition.widthMm == wd));
            return ['$wd', '${a.terukur}', _pct(b.covFit), _pct(a.covFit), _pct(a.covFitHalf), _pct(a.covRandom), _pct(a.covDefault)];
          }(),
        () {
          final b = _Pool(hb.cells), a = _Pool(ha.cells);
          return ['**semua**', '${a.terukur}', _pct(b.covFit), _pct(a.covFit), _pct(a.covFitHalf), _pct(a.covRandom), _pct(a.covDefault)];
        }(),
      ],
    ));
    w('\nKondisi hold-out yang signifikan di bawah 90 persen (fit): ${ha.cellsSignificantlyBelow(_target)}; titik estimasi di bawah 90 persen: ${ha.cellsBelowPoint(_target)}.\n');
  }
  w('\nPer skala (mm/px):\n');
  w(_table(
    ['mm/px', 'TERUKUR', 'fit sebelum (%)', 'fit sesudah (%)', 'acak sesudah (%)', 'bawaan sesudah (%)'],
    [
      for (final m in studyMmPerPx)
        () {
          final b = _Pool(before.cells.where((c) => c.condition.mmPerPx == m)), a = _Pool(after.cells.where((c) => c.condition.mmPerPx == m));
          return ['$m', '${a.terukur}', _pct(b.covFit), _pct(a.covFit), _pct(a.covRandom), _pct(a.covDefault)];
        }(),
    ],
  ));

  w('\n## 4. Bias, RMSE, cakupan dan batas ukur pada `rho = $rho`\n');
  w('Kolom `U median` dan `batas ukur median` adalah median antar sel dari median per sel. Status dihitung atas semua kunjungan; bias, RMSE, cakupan atas kunjungan TERUKUR.\n');
  w('### 4.1 Lebar x skala\n');
  w(_table(_poolHeader, [
    for (final wd in studyWidthsMm)
      for (final m in studyMmPerPx) _poolRow('$wd mm, $m mm/px', _Pool(after.cells.where((c) => c.condition.widthMm == wd && c.condition.mmPerPx == m))),
  ]));
  w('\n### 4.2 Sigma blur\n');
  w(_table(_poolHeader, [for (final s in studySigmasPx) _poolRow('$s px', _Pool(after.cells.where((c) => c.condition.sigmaPx == s)))]));
  w('\n### 4.3 Derau\n');
  w(_table(_poolHeader, [for (final n in studyNoises) _poolRow('${n.round()} tingkat', _Pool(after.cells.where((c) => c.condition.noise == n)))]));
  w('\n### 4.4 Tilt sebenarnya\n');
  w(_table(_poolHeader, [for (final t in studyTiltsDeg) _poolRow('${t.round()} derajat', _Pool(after.cells.where((c) => c.condition.tiltDeg == t)))]));
  w('\nTabel lengkap per kondisi (864 baris): `docs/SYNTHETIC_VALIDATION_CONDITIONS.csv`.\n');

  // 5. Reporting limits per setting.
  final bySetting = <String, List<StudyVisit>>{};
  final grid = studyGrid();
  for (final ci in data.keys) {
    for (final r in data[ci]!.keys) {
      bySetting.putIfAbsent(grid[ci].settingKey, () => []).add(replayVisit(grid[ci], r, data[ci]![r]!, rho: rho));
    }
  }
  final limits = <String, double?>{for (final e in bySetting.entries) e.key: settingLowerLimit(e.value)};
  w('## 5. Batas ukur\n');
  w('Batas bawah empiris per setelan (skala, blur, derau, tilt): lebar terkecil yang diuji sehingga kunjungan pada lebar itu dan semua lebar yang lebih besar andal '
      '(>= 90 persen dilaporkan, cakupan >= 90 persen, `U` lebih kecil dari lebarnya). Sel "tidak ada" berarti bahkan 2,0 mm tidak andal pada setelan itu. '
      'Kunjungan DITOLAK gerbang dikeluarkan (pengguna mengulang). Aplikasi sendiri memakai batas pelaporan 5.5 `max(0,5 mm/px, 2 u_c)`; kolom terakhir adalah median batas itu.\n');
  final settingRows = <List<String>>[];
  for (final m in studyMmPerPx) {
    for (final s in studySigmasPx) {
      final keys = {for (final c in grid) if (c.mmPerPx == m && c.sigmaPx == s) c.settingKey};
      final ls = [for (final k in keys) limits[k]];
      final numeric = ls.whereType<double>().toList()..sort();
      final floors = _Pool(after.cells.where((c) => c.condition.mmPerPx == m && c.condition.sigmaPx == s)).medianOfCells((c) => c.summary.medianFloorMm);
      settingRows.add([
        '$m',
        '$s',
        '${keys.length}',
        _mm(numeric.isEmpty ? null : numeric.first),
        _mm(numeric.isEmpty ? null : numeric[numeric.length ~/ 2]),
        _mm(numeric.isEmpty ? null : numeric.last),
        '${ls.where((x) => x == null).length}',
        _um(floors),
      ]);
    }
  }
  w(_table(['mm/px', 'sigma (px)', 'setelan', 'batas empiris min (mm)', 'median (mm)', 'maks (mm)', 'setelan tanpa batas', 'batas 5.5 median (um)'], settingRows));

  // Rejection reasons over all frames of the calibration set.
  final reasons = <String, int>{};
  var frameCount = 0, acceptedFrames = 0;
  for (final m in data.values) {
    for (final fr in m.values) {
      for (final f in fr) {
        frameCount++;
        if (f.accepted) acceptedFrames++;
        for (final c in f.rejectionCodes) {
          reasons[c] = (reasons[c] ?? 0) + 1;
        }
      }
    }
  }
  w('\n### Alasan penolakan frame (set kalibrasi)\n');
  w('Dari $frameCount frame, $acceptedFrames diterima (${_pct(acceptedFrames / frameCount)} persen). Alasan penolakan (satu frame bisa punya beberapa):\n');
  w(_table(['kode', 'frame'], [for (final e in (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) [e.key, '${e.value}']]));
  w('\nTilt 20 derajat sebenarnya sering ditolak karena `f_px` bawaan meleset (tilt terestimasi sampai 4 derajat dari nilai benar, D17); itu perilaku gerbang 5.4 yang diharapkan.\n');

  // 6. Unreliable cells.
  final bad = after.unreliableCells(_target), badStrict = after.unreliableCellsStrict(_target);
  final judged = after.cells.where((c) => c.reported > 0).length;
  final strictRho = curve.where((e) => e.unreliableCellsStrict(_target).isEmpty).map((e) => e.rho).cast<double?>().firstWhere((_) => true, orElse: () => null);
  w('\n## 6. Kondisi tidak andal\n');
  w('Dari $judged kondisi yang punya kunjungan TERUKUR:\n');
  w('- Interval yang dilihat pengguna (`U` bawaan dengan `u_truth`): **${after.unreliableCells(_target).where((c) => c.coverageDefault < _target).length}** kondisi di bawah ${(_target * 100).round()} persen secara signifikan; cakupan bawaan gabungan ${_pct(_Pool(after.cells).covDefault)} persen.');
  w('- Interval fit dengan `u_truth` renderer: **${bad.length}** kondisi signifikan di bawah ${(_target * 100).round()} persen (Wilson 95 persen); ${after.cellsBelowPoint(_target)} kondisi dengan titik estimasi di bawah ${(_target * 100).round()} persen karena galat sampling ($reps replikasi).');
  w('- Interval fit dengan kebenaran dianggap eksak (`u_truth = 0`): **${badStrict.length}** kondisi signifikan di bawah ${(_target * 100).round()} persen:\n');
  if (badStrict.isNotEmpty) {
    w(_table(['lebar', 'mm/px', 'sigma', 'derau', 'tilt', 'TERUKUR', 'tercakup (ketat)', 'RMSE (um)', 'U bawaan median (um)', 'cakupan bawaan (%)'], [
      for (final c in badStrict)
        ['${c.condition.widthMm}', '${c.condition.mmPerPx}', '${c.condition.sigmaPx}', '${c.condition.noise.round()}', '${c.condition.tiltDeg.round()}', '${c.reported}', '${c.coveredFitOnlyStrict}', _um(c.summary.rmseMm), _um(c.summary.medianUExpandedMm), _pct(c.coverageDefault)],
    ]));
  }
  final rc = File('build/synthetic_study/renderer_check.md');
  w('\nPenyebab kondisi ketat itu: galat absolut hanya beberapa um sampai sekitar 0,15 px, sama besar dengan resolusi renderer (setiap sampel tepi meleset paling banyak 0,5/S px). '
      'Percobaan (`renderer-check`, derau acak sama, hanya supersample S yang berubah):\n');
  w(rc.existsSync() ? rc.readAsStringSync() : '(percobaan belum dijalankan)\n');
  w('Galat turun nyata saat S dinaikkan, jadi kekurangan cakupan ketat di sini adalah resolusi simulator, bukan ketidakjujuran `u_fit` algoritma; `rho > 1` tidak dipilih karena hanya akan mengejar artefak itu (kalibrasi menuju cakupan ketat pada semua kondisi ${strictRho == null ? 'tidak tercapai sampai `rho` ${_candidates.last}' : 'butuh `rho` $strictRho, yaitu `u_fit` ${(sqrt(strictRho)).toStringAsFixed(1)} kali lebih besar untuk semua retak'}, dan memperlebar interval retak sempit tanpa alasan). '
      'Tidak ada kondisi yang perlu ditolak gerbang karena ketidakandalannya: interval yang dilaporkan menutup kebenaran. Kondisi yang memang tidak dilaporkan (di bawah batas ukur, TIDAK_TERUKUR, ditolak) terlihat pada status di bagian 4.\n');

  // 7. Trend false positives from pipeline pairs, per tilt.
  final pairsBy = <double, ({int pairs, int fp, int widen})>{};
  final zBy = <double, List<double>>{};
  for (final c in grid) {
    final r = data[c.index];
    if (r == null) continue;
    final keys = r.keys.toList()..sort();
    for (var i = 0; i + 1 < keys.length; i += 2) {
      final v0 = replayVisit(c, keys[i], r[keys[i]]!, rho: rho).result, v1 = replayVisit(c, keys[i + 1], r[keys[i + 1]]!, rho: rho).result;
      if (v0.status != VisitStatus.terukur || v1.status != VisitStatus.terukur) continue;
      TrendVisit tv(VisitResult v) => TrendVisit.fromVisit(v, deviceModel: 'SIM', algorithmVersion: measurementAlgorithmVersion, sheetId: 0);
      final cmp = computeTrend([tv(v0), tv(v1)], uPrintRel: 0)[1].vsBaseline!;
      final old = pairsBy[c.tiltDeg] ?? (pairs: 0, fp: 0, widen: 0);
      final hit = cmp.classification != TrendClass.tidakAdaPerubahanTerdeteksi;
      (zBy[c.tiltDeg] ??= []).add(cmp.z!);
      pairsBy[c.tiltDeg] = (pairs: old.pairs + 1, fp: old.fp + (hit ? 1 : 0), widen: old.widen + (cmp.classification == TrendClass.kemungkinanBertambahLebar ? 1 : 0));
    }
  }
  final pairs = pairsBy.values.fold(0, (s, v) => s + v.pairs), fp = pairsBy.values.fold(0, (s, v) => s + v.fp);
  String fpRow(String label, int p, int f, List<double> z) {
    final wi = wilsonInterval(f, p);
    final sd = z.length < 2 ? double.nan : sampleSd(z);
    return '| $label | $p | $f | ${_pct(p == 0 ? double.nan : f / p)} | ${_pct(wi.lower)} sampai ${_pct(wi.upper)} | ${sd.isNaN ? '-' : sd.toStringAsFixed(3)} |';
  }

  w('\n## 7. Tingkat positif palsu tren (rantai penuh, tanpa perubahan nyata)\n');
  w('Dua kunjungan independen dari kondisi yang sama (replikasi 0 dengan 1, 2 dengan 3, ...), keduanya TERUKUR, dibandingkan lewat `computeTrend` dengan `u_print_rel = 0` pada k = 2. '
      'Ekspektasi bila `u_rand` jujur dan galat normal: 4,55 persen. Tilt dipisah karena `u_par = dz tan(tilt)/sqrt(3)` (relief 0,3 mm yang tidak ada di adegan sintetis) mendominasi `u_rand` saat tilt > 0 sehingga angka itu konservatif secara konstruksi; tilt 0 adalah uji yang paling jujur untuk `u_rand`.\n');
  w('| tilt | pasangan | positif | positif palsu (%) | Wilson 95% (%) | sd(z) |\n|---|---|---|---|---|---|');
  for (final t in studyTiltsDeg) {
    final v = pairsBy[t] ?? (pairs: 0, fp: 0, widen: 0);
    w(fpRow('${t.round()} derajat', v.pairs, v.fp, zBy[t] ?? []));
  }
  w(fpRow('**semua**', pairs, fp, [for (final l in zBy.values) ...l]));
  w('\nsd(z) adalah simpangan baku z antar pasangan; untuk `u_delta` yang tepat nilainya 1,0. Nilai jauh di bawah 1 berarti `u_rand` (dan `MDC = 2 u_delta`) lebih besar daripada sebaran nyata antar kunjungan: tren jarang memberi alarm palsu tetapi perubahan kecil yang sebenarnya terdeteksi hanya bila melebihi MDC yang membengkak itu. `u_sigma_w` (bentuk kernel, 10 persen) bersifat sistematis antar kunjungan di kondisi yang sama tetapi masuk `u_rand` menurut 5.5.\n');

  final defRatios = [for (final c in after.cells) ...c.errorOverUDefault]..sort();
  final p95 = defRatios.isEmpty ? double.nan : defRatios[((defRatios.length - 1) * 0.95).round()];
  w('## 8. Apakah "kejujuran ketidakpastian" didukung data?\n');
  w('**Didukung (SINTETIS): interval yang dilaporkan tidak optimistis.** `U` bawaan menutup kebenaran pada ${_pct(after.coverageDefault)} persen dari ${after.reported} kunjungan TERUKUR '
      '(kalibrasi) dan ${holdEval == null ? 'belum ada hold-out' : '${_pct(holdEval.coverageDefault)} persen dari ${holdEval.reported} kunjungan hold-out'}; tidak ada kondisi yang signifikan di bawah 90 persen. '
      'Lebar yang tidak bisa dibuktikan dilaporkan sebagai "di bawah batas ukur" atau "tidak terukur", bukan angka.\n');
  w('**Tidak didukung: bahwa interval itu tepat (terkalibrasi).** Persentil ke-95 dari `|galat| / U` hanya ${p95.toStringAsFixed(3)}, jadi `U` kira-kira ${(1 / p95).round()} kali lebih lebar daripada galat yang terjadi pada cakupan 95 persen; '
      'pada tilt 0 `u_delta` tren sekitar ${(1 / (zBy[0]!.length < 2 ? double.nan : sampleSd(zBy[0]!))).toStringAsFixed(1)} kali sebaran nyata antar kunjungan, dan pada tilt 10 sampai 20 derajat jauh lebih lebar karena `u_par` mengandaikan relief 0,3 mm. '
      'Cakupan 100 persen pada interval 95 persen berarti klaim "95 persen" terlalu hati-hati, bukan tepat. Penyebabnya nilai bawaan yang sengaja konservatif dan tak tervalidasi (`u_dev = 0,5 mm/px`, `dz = 0,3 mm`); '
      'hanya validasi pelat `PERANGKAT` yang dapat mengecilkannya dengan dasar. Satu-satunya komponen yang mendekati tepat adalah interval fit untuk retak lebar (2,0 mm: persentil ke-95 `|galat|/U` fit ketat mendekati 1).\n');
  w('**Tidak diuji:** ponsel, optik, ISP, JPEG, pelat cetak nyata, relief, galat cetak, model ponsel berbeda. Cakupan di perangkat nyata BELUM terbukti.\n');
  w('## 9. Yang tidak dibuktikan\n');
  w('- Perilaku pada ponsel, optik, ISP, JPEG, dan pelat cetak nyata. `u_dev` bawaan (0,5 mm/px) tetap TAK TERVALIDASI.\n- Relief permukaan, galat cetak, dan perbedaan model ponsel (tidak disimulasikan).\n- Cakupan sampai batas statistik: dengan $reps replikasi per kondisi, cakupan per kondisi hanya diketahui kasar; kesimpulan utama ada pada cakupan gabungan dan per kelompok.\n');
  File('../../docs/SYNTHETIC_VALIDATION.md').writeAsStringSync(md.toString());

  final csv = StringBuffer('index,width_mm,mm_per_px,sigma_px,noise,tilt_deg,visits,terukur,di_bawah,tidak_terukur,ditolak,bias_um,rmse_um,coverage_fit,coverage_random,coverage_default,u_expanded_median_um,floor_median_um,lower_limit_setting_mm,tidak_andal\n');
  final badIdx = {for (final c in badStrict) c.condition.index};
  for (final c in after.cells) {
    final s = c.summary;
    csv.writeln([
      c.condition.index, c.condition.widthMm, c.condition.mmPerPx, c.condition.sigmaPx, c.condition.noise.round(), c.condition.tiltDeg.round(),
      s.visits, s.terukur, s.dibawahBatas, s.tidakTerukur, s.ditolak,
      _um(s.biasMm), _um(s.rmseMm), c.coverageFitOnly.isNaN ? '' : c.coverageFitOnly.toStringAsFixed(3),
      c.coverageRandom.isNaN ? '' : c.coverageRandom.toStringAsFixed(3), c.coverageDefault.isNaN ? '' : c.coverageDefault.toStringAsFixed(3),
      _um(s.medianUExpandedMm), _um(s.medianFloorMm), limits[c.condition.settingKey] ?? '', badIdx.contains(c.condition.index) ? 1 : 0,
    ].join(','));
  }
  File('../../docs/SYNTHETIC_VALIDATION_CONDITIONS.csv').writeAsStringSync(csv.toString());
  stdout.writeln('wrote docs/SYNTHETIC_VALIDATION.md and docs/SYNTHETIC_VALIDATION_CONDITIONS.csv');
}
