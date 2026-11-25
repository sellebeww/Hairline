// Copyright (c) 2026 Vassel Goleyu. MIT License.
import '../plate.dart';
import 'render.dart';

/// The validation plate as ink on paper: the four markers of sheet [plateSheetId] (solid)
/// and the 32 lines. [widthsMm] gives the TRUE printed width of a line by id (default:
/// the nominal one), so a test can print lines wider than nominal like a real printer does.
/// Everything scales with [printScale]; lines are rectangles of [plateLineLengthMm].
Scene plateScene({
  double printScale = 1,
  Map<String, double> widthsMm = const {},
  double paper = 0.9,
  double ink = 0.05,
}) {
  final markers = sheetScene(sheetId: plateSheetId, printScale: printScale, paper: paper, ink: ink);
  final lines = [
    for (final l in buildPlateLines())
      (
        cx: l.centreMm.x * printScale,
        cy: l.centreMm.y * printScale,
        hx: (l.vertical ? (widthsMm[l.id] ?? l.nominalMm) : plateLineLengthMm) / 2 * printScale,
        hy: (l.vertical ? plateLineLengthMm : (widthsMm[l.id] ?? l.nominalMm)) / 2 * printScale,
      ),
  ];
  return (x, y) {
    for (final l in lines) {
      if ((x - l.cx).abs() <= l.hx && (y - l.cy).abs() <= l.hy) return ink;
    }
    return markers(x, y);
  };
}
