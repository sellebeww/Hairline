// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'camera_service.dart';
import 'lens_info.dart';
import 'luma_frame.dart';

/// A camera that replays recorded frames: live [frames] on a timer (the last one repeats
/// once the script ends) and [stills] for the burst. For debug builds and tests, so that
/// the whole flow runs without a camera. Counters let tests check the lifecycle.
final class FakeCameraService implements CameraService {
  FakeCameraService({
    required this.frames,
    required this.stills,
    this.frameInterval = const Duration(milliseconds: 100),
    this.shotDelay = const Duration(milliseconds: 20),
    this.lens = const LensInfo(deviceModel: 'Simulasi'),
    this.quarterTurns = 0,
    this.focusLockWorks = true,
    this.initializeFailure,
  });

  @override
  bool get isSimulated => true;

  final List<LumaFrame> frames;
  final List<Uint8List> stills;
  final Duration frameInterval;
  final Duration shotDelay;
  final LensInfo lens;
  final int quarterTurns;
  final bool focusLockWorks;

  /// Makes `initialize` fail, e.g. a denied permission (tests).
  final CameraFailure? initializeFailure;

  /// Set to make the next burst fail with this failure (tests).
  CameraFailure? failNextBurst;

  int initializeCalls = 0, pauseCalls = 0, resumeCalls = 0, disposeCalls = 0, burstCalls = 0;
  int framesOffered = 0, framesTaken = 0;
  bool get isOpen => _open;
  bool get isStreaming => _timer != null;

  bool _open = false;
  bool _disposed = false;
  bool _wantLive = false;
  bool _busy = false;
  int _gen = 0;
  int _next = 0;
  FrameOffer? _offer;
  Timer? _timer;

  @override
  Future<CameraSetup> initialize() async {
    initializeCalls++;
    if (initializeFailure != null) throw initializeFailure!;
    if (_disposed) throw const CameraFailure(CameraFailureKind.interrupted, 'disposed');
    _open = true;
    return CameraSetup(lens: lens, quarterTurns: quarterTurns);
  }

  @override
  Widget buildPreview(BuildContext context) => const ColoredBox(
        color: Color(0xFF263238),
        child: Center(child: Text(Strings.fakePreview, style: TextStyle(color: Colors.white70))),
      );

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(frameInterval, (_) {
      final offer = _offer;
      if (offer == null || frames.isEmpty) return;
      final frame = frames[_next < frames.length ? _next : frames.length - 1];
      if (_next < frames.length) _next++;
      framesOffered++;
      if (offer(() => frame)) framesTaken++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> startLiveFrames(FrameOffer offer) async {
    _offer = offer;
    _wantLive = true;
    if (_open) _startTimer();
  }

  @override
  Future<void> stopLiveFrames() async {
    _wantLive = false;
    _stopTimer();
  }

  @override
  Future<BurstResult> captureBurst({
    int count = 6,
    Duration minGap = const Duration(milliseconds: 200),
    void Function(int taken)? onProgress,
  }) async {
    burstCalls++;
    if (!_open) throw const CameraFailure(CameraFailureKind.interrupted);
    if (_busy) throw const CameraFailure(CameraFailureKind.busy);
    final fail = failNextBurst;
    if (fail != null) {
      failNextBurst = null;
      throw fail;
    }
    _busy = true;
    final gen = _gen;
    final resumeLive = _wantLive;
    _stopTimer();
    try {
      final photos = <Uint8List>[];
      for (var i = 0; i < count; i++) {
        await Future<void>.delayed(shotDelay);
        if (gen != _gen || !_open) throw const CameraFailure(CameraFailureKind.interrupted);
        photos.add(stills[i % stills.length]);
        onProgress?.call(photos.length);
      }
      return BurstResult(photos: photos, locks: LockResult(focusLocked: focusLockWorks, exposureLocked: true));
    } finally {
      _busy = false;
      if (gen == _gen && _open && resumeLive) _startTimer();
    }
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _gen++;
    _open = false;
    _stopTimer();
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    if (_disposed || _open) return;
    _open = true;
    if (_wantLive) _startTimer();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    disposeCalls++;
    _disposed = true;
    _gen++;
    _open = false;
    _wantLive = false;
    _offer = null;
    _stopTimer();
  }
}
