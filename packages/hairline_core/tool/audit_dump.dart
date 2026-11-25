// Copyright (c) 2026 Vassel Goleyu. MIT License.
// Audit helper (Phase 9): runs hairline_core on the cases written by
// tools/audit/independent_check.py and prints the results as JSON, so the numbers can
// be recomputed independently in Python. Usage: dart run tool/audit_dump.dart in.json out.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';

List<Pt> _pts(Object? raw) => [for (final p in raw! as List) Pt(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())];

Map<String, Object?> _homography(Map<String, Object?> c) {
  final dets = [
    for (final d in c['detections']! as List)
      MarkerDetection(id: (d as Map)['id'] as int, corners: _pts(d['corners'])),
  ];
  final est = estimateSheetHomography(dets, sheetId: c['sheet'] as int, printScale: (c['print_scale'] as num).toDouble());
  final pointsMm = _pts(c['probe_mm']);
  final scales = [for (final p in pointsMm) est.localScale(p)];
  final intr = CameraIntrinsics(fPx: (c['f_px'] as num).toDouble(), cx: (c['cx'] as num).toDouble(), cy: (c['cy'] as num).toDouble());
  return {
    'h': est.h,
    'h_inv': est.hInv,
    'rms_px': est.rmsPx,
    'loo_mm': est.looMm,
    'mm_per_px': [for (final s in scales) s.mmPerPx],
    'anisotropy': [for (final s in scales) s.anisotropy],
    'tilt_deg': estimateTilt(est.h, intr).tiltDeg,
  };
}

FrameRecord _frame(Map<String, Object?> f) => FrameRecord(
      status: MeasureStatus.terukur,
      widthMm: (f['width'] as num).toDouble(),
      uFitRawMm: (f['u_fit_raw'] as num).toDouble(),
      rho: (f['rho'] as num).toDouble(),
      uSigmaWMm: (f['u_sigma_w'] as num).toDouble(),
      dwDs: (f['dw_ds'] as num).toDouble(),
      mmPerPx: (f['mm_per_px'] as num).toDouble(),
      rmsPx: (f['rms_px'] as num).toDouble(),
      looMm: (f['loo_mm'] as num?)?.toDouble(),
      tiltDeg: (f['tilt_deg'] as num).toDouble(),
    );

Map<String, Object?> _budget(Map<String, Object?> c) {
  final o = c['options']! as Map<String, Object?>;
  final b = UncertaintyBudget.fromFrames(
    [for (final f in c['frames']! as List) _frame(f as Map<String, Object?>)],
    UncertaintyOptions(
      dzMm: (o['dz'] as num).toDouble(),
      uPrintRel: (o['u_print_rel'] as num).toDouble(),
      uDevMm: (o['u_dev'] as num?)?.toDouble(),
    ),
  );
  return b.toJson();
}

Map<String, Object?> _trend(Map<String, Object?> c) {
  TrendVisit v(Map<String, Object?> m) => TrendVisit(
        status: VisitStatus.terukur,
        widthMm: (m['width'] as num).toDouble(),
        uRand: (m['u_rand'] as num).toDouble(),
        deviceModel: 'x',
        algorithmVersion: '1',
        sheetId: 0,
      );
  final t = computeTrend([v(c['a']! as Map<String, Object?>), v(c['b']! as Map<String, Object?>)], uPrintRel: (c['u_print_rel'] as num).toDouble());
  final cmp = t[1].vsBaseline!;
  return {'delta': cmp.delta, 'u_delta': cmp.uDelta, 'z': cmp.z, 'mdc': cmp.mdc, 'class': cmp.classification.code};
}

Map<String, Object?> _profile(Map<String, Object?> c) {
  final w = c['patch_w'] as int, h = c['patch_h'] as int;
  final data = Float32List.fromList([for (final v in c['data']! as List) (v as num).toDouble()]);
  final patch = GrayPatch(originX: c['origin_x'] as int, originY: c['origin_y'] as int, width: w, height: h, data: data);
  final hm = [for (final v in c['h']! as List) (v as num).toDouble()];
  final r = fitCrackWidth(
    patch: patch,
    h: hm,
    pointMm: Pt(((c['point_mm'] as List)[0] as num).toDouble(), ((c['point_mm'] as List)[1] as num).toDouble()),
    directionDeg: (c['direction_deg'] as num).toDouble(),
    sigmaMm: (c['sigma_mm'] as num).toDouble(),
  );
  return {
    'status': r.status.code,
    'width_mm': r.widthMm,
    'u_width_mm': r.uWidthMm,
    'center_offset_mm': r.centerOffsetMm,
    'params': r.params,
    'dw_ds': r.dwDs,
  };
}

Future<void> main(List<String> args) async {
  final input = jsonDecode(await File(args[0]).readAsString()) as Map<String, Object?>;
  final out = <String, Object?>{
    'homography': [for (final c in input['homography']! as List) _homography(c as Map<String, Object?>)],
    'budget': [for (final c in input['budget']! as List) _budget(c as Map<String, Object?>)],
    'trend': [for (final c in input['trend']! as List) _trend(c as Map<String, Object?>)],
    'k': [for (final d in input['k_dof']! as List) coverageFactor((d as num).toDouble())],
    'profile': [for (final c in input['profile']! as List) _profile(c as Map<String, Object?>)],
  };
  await File(args[1]).writeAsString(jsonEncode(out));
}
