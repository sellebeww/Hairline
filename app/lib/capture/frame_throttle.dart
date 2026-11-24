// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Admission control for the live detector: at most one frame in flight and at least
/// [minInterval] between two admitted frames. Everything else is dropped, never queued,
/// so memory stays bounded however slow the detector is.
///
/// Target 8 to 12 frames per second (CLAUDE.md phase 6): the default 85 ms interval caps
/// the rate near 11.8 fps; a slow detector lowers it by itself because the next frame is
/// only admitted after [release].
final class FrameThrottle {
  FrameThrottle({this.minInterval = const Duration(milliseconds: 85), Duration Function()? clock})
      : _clock = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final Duration minInterval;
  final Duration Function() _clock;
  Duration? _lastAdmitted;
  bool _busy = false;

  /// Frames admitted.
  int admitted = 0;

  /// Frames dropped because the detector was still busy.
  int droppedBusy = 0;

  /// Frames skipped to keep the rate at or below the target.
  int skippedRate = 0;

  bool get busy => _busy;

  /// True when this frame may be processed; the caller must call [release] when done
  /// (or when it decides not to process after all).
  bool tryAcquire() {
    if (_busy) {
      droppedBusy++;
      return false;
    }
    final now = _clock();
    final last = _lastAdmitted;
    if (last != null && now - last < minInterval) {
      skippedRate++;
      return false;
    }
    _busy = true;
    _lastAdmitted = now;
    admitted++;
    return true;
  }

  void release() => _busy = false;
}
