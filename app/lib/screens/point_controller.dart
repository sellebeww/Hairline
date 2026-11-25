// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../capture/pending_baseline.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import '../pipeline/frame_processor.dart';
import '../pipeline/visit_processor.dart';
import '../providers.dart';

part 'point_controller.g.dart';

enum PointPhase {
  /// The overlay (homography of the photo) is being computed.
  preparing,

  /// Waiting for a tap, or showing a located point.
  ready,
  locating,
  saving,

  /// The baseline visit is stored: [PointUiState.visitId].
  saved,

  /// Nothing can be done on this screen: see [PointUiState.message].
  failed,
}

@immutable
final class PointUiState {
  const PointUiState({
    this.phase = PointPhase.preparing,
    this.base,
    this.located,
    this.message,
    this.reasons = const [],
    this.visitId,
    this.printScale = 1,
  });

  final PointPhase phase;

  /// Print scale of the crack (the overlay sizes the window with it).
  final double printScale;

  /// Homography and size of the photo (for the overlay).
  final PointLocation? base;

  /// The snapped point, when the last tap found a crack.
  final PointLocation? located;

  /// Specific message of the last failed tap, or of a failure.
  final String? message;

  /// Why the baseline was not stored (confirm step).
  final List<String> reasons;
  final int? visitId;

  bool get canConfirm => phase == PointPhase.ready && (located?.located ?? false);

  PointUiState copyWith({
    PointPhase? phase,
    PointLocation? base,
    Object? located = _keep,
    Object? message = _keep,
    List<String>? reasons,
    int? visitId,
    double? printScale,
  }) =>
      PointUiState(
        phase: phase ?? this.phase,
        base: base ?? this.base,
        located: identical(located, _keep) ? this.located : located as PointLocation?,
        message: identical(message, _keep) ? this.message : message as String?,
        reasons: reasons ?? this.reasons,
        visitId: visitId ?? this.visitId,
        printScale: printScale ?? this.printScale,
      );
}

const Object _keep = Object();

/// The measurement point screen of the baseline visit: tap, snap to the crack ridge
/// (`locateCrackPoint` of the core), confirm, then store the visit through the full gate.
@riverpod
class PointController extends _$PointController {
  late int _crackId;
  late Crack _crack;
  PendingBaseline? _pending;
  int _tapSerial = 0;

  @override
  PointUiState build(int crackId) {
    _crackId = crackId;
    _pending = ref.read(pendingBaselinesProvider)[crackId];
    if (_pending == null) return const PointUiState(phase: PointPhase.failed, message: Strings.pointNoPending);
    unawaited(Future<void>.microtask(_prepare));
    return const PointUiState();
  }

  Future<void> _prepare() async {
    if (!ref.mounted) return;
    final locator = ref.read(pointLocatorProvider);
    final repo = ref.read(hairlineRepositoryProvider);
    try {
      final crack = await repo.crack(_crackId);
      if (crack == null) return _fail(Strings.crackNotFound);
      _crack = crack;
      final base = await locator.locate(photo: _pending!.bestPhoto, sheetId: crack.sheetId, printScale: crack.printScale);
      if (!ref.mounted) return;
      if (base.h == null) return _fail(base.message ?? Strings.errLoad);
      state = state.copyWith(phase: PointPhase.ready, base: base, printScale: crack.printScale);
    } on Object {
      _fail(Strings.errLoad);
    }
  }

  void _fail(String message) {
    if (ref.mounted) state = state.copyWith(phase: PointPhase.failed, message: message);
  }

  /// A tap at [imagePx] (pixels of the decoded photo). Late answers of earlier taps are dropped.
  Future<void> tap(Pt imagePx) async {
    if (state.phase != PointPhase.ready) return;
    final serial = ++_tapSerial;
    final locator = ref.read(pointLocatorProvider);
    state = state.copyWith(phase: PointPhase.locating, message: null);
    try {
      final r = await locator.locate(photo: _pending!.bestPhoto, sheetId: _crack.sheetId, printScale: _crack.printScale, tapPx: imagePx);
      if (!ref.mounted || serial != _tapSerial) return;
      state = state.copyWith(
        phase: PointPhase.ready,
        located: r.located ? r : null,
        message: r.located ? null : r.message,
      );
    } on Object {
      if (ref.mounted) state = state.copyWith(phase: PointPhase.ready, located: null, message: Strings.errProcessing);
    }
  }

  /// Stores the baseline visit with the located point.
  Future<void> confirm() async {
    final located = state.located;
    final pending = _pending;
    if (!state.canConfirm || located == null || pending == null) return;
    final processor = ref.read(visitProcessorProvider);
    final pendings = ref.read(pendingBaselinesProvider.notifier);
    state = state.copyWith(phase: PointPhase.saving);
    try {
      final outcome = await processor.storeBaseline(pending, pointMm: located.pointMm!, directionDeg: located.directionDeg!);
      if (!ref.mounted) return;
      switch (outcome) {
        case VisitStored(:final visitId):
          pendings.remove(_crackId);
          state = state.copyWith(phase: PointPhase.saved, visitId: visitId);
        case VisitNotStored(:final reasons):
          state = state.copyWith(phase: PointPhase.failed, message: Strings.pointNotStored, reasons: reasons);
        case VisitReprocessed():
          _fail(Strings.errProcessing);
      }
    } on RepositoryException catch (e) {
      _fail(e.message);
    } on FrameProcessException catch (e) {
      _fail(e.message);
    } on Object {
      _fail(Strings.errProcessing);
    }
  }
}
