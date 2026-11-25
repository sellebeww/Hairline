// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';

import '../capture/pending_baseline.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'point_controller.dart';
import 'point_overlay.dart';
import 'queries.dart';

/// Baseline visit step 2: the best photo with overlay; the user taps the crack, the core
/// snaps the point to the nearest ridge, the user confirms direction and 4 mm segment.
class PointPage extends ConsumerWidget {
  const PointPage({super.key, required this.crackId});
  final int crackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pointControllerProvider(crackId).select((s) => s.visitId), (prev, id) {
      if (id != null) {
        ref.invalidate(crackDetailProvider(crackId));
        GoRouter.maybeOf(context)?.pushReplacement('/result/$id');
      }
    });
    final ui = ref.watch(pointControllerProvider(crackId));
    final controller = ref.read(pointControllerProvider(crackId).notifier);
    final pending = ref.watch(pendingBaselinesProvider)[crackId];
    final base = ui.base;
    final busy = ui.phase == PointPhase.locating || ui.phase == PointPhase.saving;

    Widget body;
    if (ui.phase == PointPhase.failed || pending == null && ui.phase != PointPhase.saved && ui.phase != PointPhase.saving) {
      body = _Failure(message: ui.message ?? Strings.pointNoPending, reasons: ui.reasons, crackId: crackId);
    } else if (base == null || pending == null) {
      body = Center(child: Semantics(label: Strings.pointPreparing, child: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text(Strings.pointPreparing)])));
    } else {
      final located = ui.located;
      body = Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final img = base.size;
            final scale = c.maxWidth / img.width;
            final w = c.maxWidth, h = img.height * scale;
            return InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Semantics(
                    label: Strings.pointPhotoSemantics,
                    image: true,
                    child: GestureDetector(
                      onTapUp: busy ? null : (d) => controller.tap(Pt(d.localPosition.dx / scale, d.localPosition.dy / scale)),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.memory(
                          pending.bestPhoto,
                          fit: BoxFit.fill,
                          errorBuilder: (context, e, st) => const ColoredBox(color: Color(0xFF333333), child: Center(child: Text(Strings.pointPhotoMissing, style: TextStyle(color: Colors.white)))),
                        ),
                        CustomPaint(
                          painter: PointOverlayPainter(
                            h: base.h!,
                            printScale: ui.printScale,
                            scale: scale,
                            pointMm: located?.pointMm,
                            directionDeg: located?.directionDeg,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        _Panel(ui: ui, onConfirm: controller.confirm),
      ]);
    }
    return PopScope(
      canPop: !busy,
      child: Scaffold(appBar: AppBar(title: const Text(Strings.pointTitle)), body: SafeArea(child: body)),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.ui, required this.onConfirm});
  final PointUiState ui;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final loc = ui.located;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ui.phase == PointPhase.locating || ui.phase == PointPhase.saving)
          Semantics(
            liveRegion: true,
            child: Row(children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(ui.phase == PointPhase.saving ? Strings.pointSaving : Strings.pointLocating)),
            ]),
          )
        else if (loc != null && loc.located) ...[
          Text(Strings.pointDirection(loc.directionDeg!), style: Theme.of(context).textTheme.titleSmall),
          Text(Strings.pointCoordinates(loc.pointMm!.x, loc.pointMm!.y)),
          const Text(Strings.pointSegmentCaption),
        ] else ...[
          if (ui.message != null) StatusBadge(icon: Icons.touch_app, text: ui.message!, colors: StatusColors.caution) else const Text(Strings.pointInstruction),
        ],
        const SizedBox(height: 4),
        const Text(Strings.pointZoneHint, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: ui.canConfirm ? onConfirm : null, icon: const Icon(Icons.check), label: const Text(Strings.pointConfirm)),
      ]),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.reasons, required this.crackId});
  final String message;
  final List<String> reasons;
  final int crackId;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        StatusBadge(icon: Icons.error_outline, text: message, colors: StatusColors.caution),
        const SizedBox(height: 12),
        if (reasons.isNotEmpty) BulletList(reasons),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => GoRouter.maybeOf(context)?.pushReplacement('/capture/$crackId'),
          icon: const Icon(Icons.camera_alt),
          label: const Text(Strings.pointRecapture),
        ),
      ]);
}
