// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';

import '../data/repository.dart';

/// Debug only: creates a site and one crack (sheet 0, print scale 1, point at the window
/// centre) so that the capture screen can be tried before the screens that create cracks
/// exist. Returns the crack id.
Future<int> seedDemoCrack(HairlineRepository repo, {double directionDeg = 0}) async {
  final site = await repo.createSite(name: 'Situs uji (debug)');
  return repo.createCrack(
    siteId: site,
    label: 'Retak uji (debug)',
    sheetId: 0,
    printScale: 1,
    printScaleURel: 0.003,
    pointMm: const Pt(0, 0),
    directionDeg: directionDeg,
    createdAt: DateTime.now().toUtc(),
  );
}
