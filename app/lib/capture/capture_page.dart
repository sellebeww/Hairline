// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../pipeline/visit_processor.dart';
import 'capture_controller.dart';
import 'capture_flow.dart';
import 'capture_overlay.dart';

/// The capture screen: preview, outlines, guidance, shutter, quality-gate result.
class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key, required this.crackId});

  final int crackId;

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The overlay assumes the upright portrait frame (the camera also locks portrait).
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(captureControllerProvider(widget.crackId).notifier).onLifecycle(state);
  }

  void _openPoint() => GoRouter.maybeOf(context)?.pushReplacement('/point/${widget.crackId}');

  void _openResult() {
    final outcome = ref.read(captureControllerProvider(widget.crackId)).flow.outcome;
    if (outcome is VisitStored) GoRouter.maybeOf(context)?.pushReplacement('/result/${outcome.visitId}');
  }

  @override
  Widget build(BuildContext context) {
    // The baseline photos are kept in memory: go on to the measurement point at once.
    ref.listen(captureControllerProvider(widget.crackId).select((u) => u.flow.phase), (prev, next) {
      if (next == CapturePhase.baselineCaptured) _openPoint();
    });
    final ui = ref.watch(captureControllerProvider(widget.crackId));
    final controller = ref.read(captureControllerProvider(widget.crackId).notifier);
    final s = ui.flow;
    final analysis = s.analysis;
    final aspect = analysis == null ? 3 / 4 : analysis.size.width / analysis.size.height;
    final busy = s.phase == CapturePhase.burst || s.phase == CapturePhase.processing;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text(Strings.captureTitle)),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Stack(fit: StackFit.expand, children: [
                    ui.starting || ui.paused
                        ? const Center(child: CircularProgressIndicator())
                        : ref.read(cameraServiceProvider).buildPreview(context),
                    CustomPaint(painter: CaptureOverlayPainter(analysis: analysis, level: guideLevelOf(s))),
                    Positioned(left: 8, right: 8, top: 8, child: GuidanceBanner(state: s)),
                  ]),
                ),
              ),
            ),
            _BottomPanel(
              ui: ui,
              onShutter: controller.shutter,
              onRetry: controller.retry,
              onChoosePoint: _openPoint,
              onOpenResult: _openResult,
            ),
          ]),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.ui,
    required this.onShutter,
    required this.onRetry,
    required this.onChoosePoint,
    required this.onOpenResult,
  });

  final CaptureUiState ui;
  final Future<void> Function() onShutter;
  final Future<void> Function() onRetry;
  final VoidCallback onChoosePoint;
  final VoidCallback onOpenResult;

  @override
  Widget build(BuildContext context) {
    final s = ui.flow;
    final children = <Widget>[];
    if (ui.note != null) children.add(_Note(ui.note!));
    if (ui.isBaseline && !ui.starting && s.phase != CapturePhase.result) children.add(const _Note(Strings.baselineHint));
    switch (s.phase) {
      case CapturePhase.burst:
        children.add(_Progress(value: s.burstTotal == 0 ? null : s.burstTaken / s.burstTotal, label: Strings.burstProgress(s.burstTaken, s.burstTotal)));
      case CapturePhase.processing:
        children.add(_Progress(
          value: s.processTotal == 0 ? null : s.processDone / s.processTotal,
          label: Strings.processProgress(s.processDone, s.processTotal),
        ));
      case CapturePhase.baselineCaptured:
        children
          ..add(const _Note(Strings.baselineCapturedHint))
          ..add(FilledButton(onPressed: onChoosePoint, child: const Text(Strings.choosePoint)));
      case CapturePhase.result:
        children
          ..add(OutcomeSummary(outcome: s.outcome!, flags: s.flags))
          ..add(FilledButton(onPressed: onRetry, child: const Text(Strings.retry)));
        if (s.outcome is VisitStored) children.add(TextButton(onPressed: onOpenResult, child: const Text(Strings.openResult)));
      case CapturePhase.error:
        children
          ..add(_Note(s.error ?? Strings.statusError))
          ..add(FilledButton(onPressed: onRetry, child: const Text(Strings.retry)));
      case CapturePhase.waitingForMarkers:
      case CapturePhase.adjusting:
      case CapturePhase.ready:
        if (s.phase == CapturePhase.waitingForMarkers) children.add(const _Note(Strings.waitingHint));
        children
          ..add(Semantics(
            button: true,
            enabled: s.canShoot,
            hint: s.canShoot ? null : Strings.shutterDisabledHint,
            child: FilledButton.icon(
              onPressed: s.canShoot ? onShutter : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text(Strings.shutter),
            ),
          ))
          ..add(const Padding(padding: EdgeInsets.only(top: 4), child: Text(Strings.tiltAndScaleApprox, style: TextStyle(color: Colors.white54, fontSize: 11))));
    }
    return Container(
      width: double.infinity,
      color: Colors.black87,
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)));
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.label});
  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: value),
      ]);
}
