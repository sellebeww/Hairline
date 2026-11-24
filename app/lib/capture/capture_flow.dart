// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/foundation.dart';

import '../pipeline/visit_processor.dart';
import 'live_analysis.dart';

/// Where the capture flow is. Exactly one phase at a time.
enum CapturePhase { waitingForMarkers, adjusting, ready, burst, processing, result, error }

/// Tunable values of the flow (starting values, not tuned on a device).
@immutable
final class FlowConfig {
  const FlowConfig({
    this.stableFramesRequired = 5,
    this.staleAfter = const Duration(seconds: 1),
    this.burstCount = 6,
    this.burstMinGap = const Duration(milliseconds: 200),
  });

  /// Consecutive good, steady frames before the shutter unlocks (about 0.5 s at 10 fps).
  final int stableFramesRequired;

  /// No analysis for this long means the detector stalled: the shutter must not stay armed.
  final Duration staleAfter;

  /// Photos per visit (the gate needs 3 accepted, at most 5 are stored).
  final int burstCount;

  /// Minimum pause between two shots.
  final Duration burstMinGap;
}

@immutable
final class CaptureState {
  const CaptureState({
    this.phase = CapturePhase.waitingForMarkers,
    this.analysis,
    this.stableCount = 0,
    this.lastAnalysisAt,
    this.burstTaken = 0,
    this.burstTotal = 0,
    this.processDone = 0,
    this.processTotal = 0,
    this.outcome,
    this.error,
    this.flags = const [],
  });

  final CapturePhase phase;

  /// The latest live analysis; kept (frozen) during burst and processing.
  final LiveAnalysis? analysis;
  final int stableCount;
  final Duration? lastAnalysisAt;
  final int burstTaken;
  final int burstTotal;
  final int processDone;
  final int processTotal;

  /// Set in [CapturePhase.result]: stored, or not stored with reasons.
  final VisitOutcome? outcome;

  /// Set in [CapturePhase.error]: a specific message for the user.
  final String? error;

  /// Capture conditions of the last burst (`fokus_tidak_terkunci`, ...).
  final List<String> flags;

  bool get canShoot => phase == CapturePhase.ready;
}

sealed class CaptureEvent {
  const CaptureEvent();
}

/// A live analysis (null: the detector saw nothing usable) at monotonic time [at].
final class AnalysisEvent extends CaptureEvent {
  const AnalysisEvent(this.analysis, this.at);
  final LiveAnalysis? analysis;
  final Duration at;
}

final class TickEvent extends CaptureEvent {
  const TickEvent(this.at);
  final Duration at;
}

final class ShutterEvent extends CaptureEvent {
  const ShutterEvent(this.total);
  final int total;
}

final class BurstProgressEvent extends CaptureEvent {
  const BurstProgressEvent(this.taken);
  final int taken;
}

final class BurstDoneEvent extends CaptureEvent {
  const BurstDoneEvent({required this.photoCount, required this.flags});
  final int photoCount;
  final List<String> flags;
}

final class ProcessProgressEvent extends CaptureEvent {
  const ProcessProgressEvent(this.done, this.total);
  final int done, total;
}

final class ProcessedEvent extends CaptureEvent {
  const ProcessedEvent(this.outcome);
  final VisitOutcome outcome;
}

final class FailedEvent extends CaptureEvent {
  const FailedEvent(this.message);
  final String message;
}

final class RetryEvent extends CaptureEvent {
  const RetryEvent();
}

bool _aiming(CapturePhase p) =>
    p == CapturePhase.waitingForMarkers || p == CapturePhase.adjusting || p == CapturePhase.ready;

CaptureState _waiting(CaptureState s, {LiveAnalysis? analysis, Duration? at}) => CaptureState(
      analysis: analysis,
      lastAnalysisAt: at ?? s.lastAnalysisAt,
      flags: s.flags,
    );

/// The pure transition function of the capture flow. Events that make no sense in the
/// current phase (a shutter while adjusting, frames during the burst) return [s] itself.
CaptureState reduceCapture(CaptureState s, CaptureEvent e, {FlowConfig config = const FlowConfig()}) {
  switch (e) {
    case AnalysisEvent(:final analysis, :final at):
      if (!_aiming(s.phase)) return s;
      if (analysis == null || analysis.markerCount < 3 || analysis.estimate == null) {
        return _waiting(s, analysis: analysis, at: at);
      }
      if (!analysis.ready) {
        return CaptureState(phase: CapturePhase.adjusting, analysis: analysis, lastAnalysisAt: at, flags: s.flags);
      }
      final stable = analysis.steady ? s.stableCount + 1 : 1;
      return CaptureState(
        phase: stable >= config.stableFramesRequired ? CapturePhase.ready : CapturePhase.adjusting,
        analysis: analysis,
        stableCount: stable,
        lastAnalysisAt: at,
        flags: s.flags,
      );
    case TickEvent(:final at):
      final last = s.lastAnalysisAt;
      if (s.phase == CapturePhase.waitingForMarkers || !_aiming(s.phase)) return s;
      if (last != null && at - last > config.staleAfter) return _waiting(s);
      return s;
    case ShutterEvent(:final total):
      if (!s.canShoot) return s;
      return CaptureState(phase: CapturePhase.burst, analysis: s.analysis, burstTotal: total, lastAnalysisAt: s.lastAnalysisAt);
    case BurstProgressEvent(:final taken):
      if (s.phase != CapturePhase.burst) return s;
      return CaptureState(
        phase: CapturePhase.burst,
        analysis: s.analysis,
        burstTaken: taken,
        burstTotal: s.burstTotal,
        lastAnalysisAt: s.lastAnalysisAt,
      );
    case BurstDoneEvent(:final photoCount, :final flags):
      if (s.phase != CapturePhase.burst) return s;
      return CaptureState(
        phase: CapturePhase.processing,
        analysis: s.analysis,
        processTotal: photoCount,
        flags: flags,
        lastAnalysisAt: s.lastAnalysisAt,
      );
    case ProcessProgressEvent(:final done, :final total):
      if (s.phase != CapturePhase.processing) return s;
      return CaptureState(
        phase: CapturePhase.processing,
        analysis: s.analysis,
        processDone: done,
        processTotal: total,
        flags: s.flags,
        lastAnalysisAt: s.lastAnalysisAt,
      );
    case ProcessedEvent(:final outcome):
      if (s.phase != CapturePhase.processing) return s;
      return CaptureState(
        phase: CapturePhase.result,
        analysis: s.analysis,
        outcome: outcome,
        flags: s.flags,
        processDone: s.processTotal,
        processTotal: s.processTotal,
      );
    case FailedEvent(:final message):
      if (s.phase == CapturePhase.error) return s;
      return CaptureState(phase: CapturePhase.error, analysis: s.analysis, error: message, flags: s.flags);
    case RetryEvent():
      if (s.phase != CapturePhase.result && s.phase != CapturePhase.error) return s;
      return const CaptureState();
  }
}
