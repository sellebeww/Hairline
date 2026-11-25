// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:hairline_core/hairline_core.dart';

import '../l10n/strings.dart';
import '../pipeline/visit_processor.dart';
import 'capture_flow.dart';
import 'live_analysis.dart';

/// How the guidance is shown: icon and text carry the meaning, color only reinforces it.
enum GuideLevel { ok, adjust, blocked }

GuideLevel guideLevelOf(CaptureState s) => switch (s.phase) {
      CapturePhase.ready || CapturePhase.result || CapturePhase.baselineCaptured || CapturePhase.validated =>
        s.outcome is VisitNotStored ? GuideLevel.adjust : GuideLevel.ok,
      CapturePhase.adjusting || CapturePhase.burst || CapturePhase.processing => GuideLevel.adjust,
      CapturePhase.waitingForMarkers || CapturePhase.error => GuideLevel.blocked,
    };

IconData guideIcon(GuideLevel l) => switch (l) {
      GuideLevel.ok => Icons.check_circle,
      GuideLevel.adjust => Icons.warning_amber_rounded,
      GuideLevel.blocked => Icons.error_outline,
    };

Color guideColor(GuideLevel l) => switch (l) {
      GuideLevel.ok => const Color(0xFF2E7D32),
      GuideLevel.adjust => const Color(0xFFF9A825),
      GuideLevel.blocked => const Color(0xFFC62828),
    };

IconData instructionIcon(PoseInstruction i) => switch (i) {
      PoseInstruction.holdFlat => Icons.screen_rotation_alt,
      PoseInstruction.closer => Icons.zoom_in,
      PoseInstruction.farther => Icons.zoom_out,
      PoseInstruction.rotateCw => Icons.rotate_right,
      PoseInstruction.rotateCcw => Icons.rotate_left,
      PoseInstruction.moveLeft => Icons.arrow_back,
      PoseInstruction.moveRight => Icons.arrow_forward,
      PoseInstruction.moveUp => Icons.arrow_upward,
      PoseInstruction.moveDown => Icons.arrow_downward,
    };

/// The headline of the guidance for the current state.
String headlineOf(CaptureState s) => switch (s.phase) {
      CapturePhase.waitingForMarkers => Strings.statusWaiting,
      CapturePhase.adjusting => _adjustHeadline(s.analysis),
      CapturePhase.ready => Strings.statusReady,
      CapturePhase.burst => Strings.statusBurst,
      CapturePhase.processing => Strings.statusProcessing,
      CapturePhase.baselineCaptured => Strings.statusBaselineCaptured,
      CapturePhase.validated => Strings.statusValidated,
      CapturePhase.result => s.outcome is VisitStored ? Strings.statusResultStored : Strings.statusResultRejected,
      CapturePhase.error => Strings.statusError,
    };

String _adjustHeadline(LiveAnalysis? a) {
  if (a == null) return Strings.statusAdjusting;
  if (a.instructions.isNotEmpty) return Strings.instruction(a.instructions.first);
  if (a.geometryRejections.isNotEmpty) return Strings.rejection(a.geometryRejections.first);
  return Strings.statusAdjusting; // good pose, still settling (stability not reached)
}

/// Draws the detected marker outlines, the target (ghost) outline of the reference pose,
/// the cut-out window and the measurement point, in the upright live frame scaled to the
/// canvas. The ghost is dashed and the live outlines solid, so they differ without color.
final class CaptureOverlayPainter extends CustomPainter {
  const CaptureOverlayPainter({required this.analysis, required this.level});

  final LiveAnalysis? analysis;
  final GuideLevel level;

  static const double _dash = 8, _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final a = analysis;
    if (a == null || a.size.width == 0 || a.size.height == 0) return;
    final sx = size.width / a.size.width, sy = size.height / a.size.height;
    Offset o(Pt p) => Offset(p.x * sx, p.y * sy);
    Path quad(List<Pt> pts) => Path()
      ..addPolygon([for (final p in pts) o(p)], true);

    final live = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = guideColor(level);
    for (final m in a.markers) {
      canvas.drawPath(quad(m), live);
    }

    final ghost = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    for (final g in a.ghost) {
      _dashed(canvas, quad(g), ghost);
    }

    final window = a.windowQuad;
    if (window != null) {
      canvas.drawPath(
        quad(window),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white70,
      );
    }
    final point = a.pointPx;
    if (point != null) {
      final c = o(point);
      final cross = Paint()
        ..strokeWidth = 2
        ..color = Colors.white;
      canvas.drawLine(c + const Offset(-10, 0), c + const Offset(10, 0), cross);
      canvas.drawLine(c + const Offset(0, -10), c + const Offset(0, 10), cross);
    }
  }

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(CaptureOverlayPainter old) => old.analysis != analysis || old.level != level;
}

/// Status line: icon, headline, and the secondary facts (markers, tilt, scale).
class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key, required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final level = guideLevelOf(state);
    final a = state.analysis;
    final primary = state.phase == CapturePhase.adjusting && a != null && a.instructions.isNotEmpty ? a.instructions.first : null;
    final headline = headlineOf(state);
    return Semantics(
      liveRegion: true,
      label: headline,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: guideColor(level), width: 2), borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(primary != null ? instructionIcon(primary) : guideIcon(level), color: guideColor(level)),
              const SizedBox(width: 8),
              Expanded(child: Text(headline, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
            if (a != null && state.phase != CapturePhase.result && state.phase != CapturePhase.error) ...[
              const SizedBox(height: 4),
              Text(Strings.markersSeen(a.markerCount), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (a.tiltDeg != null && a.mmPerPx != null)
                Text('${Strings.tilt(a.tiltDeg!)}. ${Strings.scale(a.mmPerPx!)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The lines of the result card: what was stored or why nothing was, with the honest
/// statements of CLAUDE.md section 1 (indicative, unvalidated label, scale always shown).
List<String> outcomeLines(VisitOutcome outcome, List<String> flags) {
  final lines = <String>[];
  final r = outcome.result;
  final b = r.budget;
  if (outcome is VisitNotStored) {
    lines.addAll(outcome.reasons);
  } else {
    lines.add(Strings.framesAccepted(r.acceptedFrames, outcome.frames.length));
    switch (r.status) {
      case VisitStatus.terukur when b != null:
        lines.add(Strings.widthWithU(b.widthMm, b.uExpanded, b.k));
      case VisitStatus.dibawahBatasUkur when b != null:
        lines.add(Strings.belowFloor(b.floorMm));
      default:
        lines.add(Strings.statusNotMeasurable);
    }
    if (b != null) {
      lines.add(Strings.scale(b.mmPerPx));
      if (b.belumDivalidasi) lines.add(Strings.notValidated);
    }
    lines.add(Strings.resultIndicative);
  }
  if (flags.contains(Strings.flagFocusNotLocked)) lines.add(Strings.warnFocusNotLocked);
  if (flags.contains(Strings.flagExposureNotLocked)) lines.add(Strings.warnExposureNotLocked);
  return lines;
}

class OutcomeSummary extends StatelessWidget {
  const OutcomeSummary({super.key, required this.outcome, required this.flags});

  final VisitOutcome outcome;
  final List<String> flags;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in outcomeLines(outcome, flags))
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      );
}
