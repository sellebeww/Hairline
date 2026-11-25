// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';
import 'lens_info.dart';
import 'luma_frame.dart';

enum CameraFailureKind { permissionDenied, permissionDeniedForever, noCamera, openFailed, interrupted, busy, captureFailed }

/// A camera problem with a specific message for the user (Indonesian) and a technical detail.
final class CameraFailure implements Exception {
  const CameraFailure(this.kind, [this.detail]);

  final CameraFailureKind kind;
  final String? detail;

  String get message => switch (kind) {
        CameraFailureKind.permissionDenied => Strings.errPermissionDenied,
        CameraFailureKind.permissionDeniedForever => Strings.errPermissionDeniedForever,
        CameraFailureKind.noCamera => Strings.errNoCamera,
        CameraFailureKind.openFailed => Strings.errCameraOpen,
        CameraFailureKind.interrupted => Strings.errCameraInterrupted,
        CameraFailureKind.busy => Strings.errCameraBusy,
        CameraFailureKind.captureFailed => Strings.errCapture,
      };

  @override
  String toString() => 'CameraFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// What the capture flow needs to know once the camera is open.
final class CameraSetup {
  const CameraSetup({required this.lens, required this.quarterTurns});

  final LensInfo lens;

  /// Clockwise quarter turns from the stream's pixels to what the user sees upright.
  final int quarterTurns;
}

/// Whether the focus and exposure locks actually took effect before the burst. With the
/// CameraX backend a lock that the device ignores does not throw, so "locked" here means
/// "requested and no error"; only a device test can prove it holds (docs/DEVICE_TEST.md).
final class LockResult {
  const LockResult({required this.focusLocked, required this.exposureLocked});

  final bool focusLocked;
  final bool exposureLocked;

  List<String> get flags => [
        if (!focusLocked) Strings.flagFocusNotLocked,
        if (!exposureLocked) Strings.flagExposureNotLocked,
      ];
}

final class BurstResult {
  const BurstResult({required this.photos, required this.locks});

  /// JPEG bytes, in shooting order.
  final List<Uint8List> photos;
  final LockResult locks;
}

/// Offered every raw frame by the camera; calls `produce` only when it takes the frame
/// (the detection worker's `offer`).
typedef FrameOffer = bool Function(LumaFrame Function() produce);

/// Back camera for the capture flow. Implementations: [DeviceCameraService] (the
/// `camera` package) and `FakeCameraService` (debug and tests).
abstract interface class CameraService {
  /// True for a camera that replays synthetic photos: what it produces is never PERANGKAT data.
  bool get isSimulated;

  /// Opens the camera (asks for the permission), flash off, portrait capture orientation.
  /// Throws [CameraFailure].
  Future<CameraSetup> initialize();

  Widget buildPreview(BuildContext context);

  /// Starts delivering frames to [offer]. Safe to call again after [stopLiveFrames].
  Future<void> startLiveFrames(FrameOffer offer);

  Future<void> stopLiveFrames();

  /// Stops the stream, locks focus and exposure, takes [count] stills at least [minGap]
  /// apart, unlocks again and resumes the stream if it was running. Throws [CameraFailure]
  /// ([CameraFailureKind.interrupted] when the app was paused or the service disposed meanwhile).
  Future<BurstResult> captureBurst({int count = 6, Duration minGap = const Duration(milliseconds: 200), void Function(int taken)? onProgress});

  /// App went to the background (also for an incoming call): releases the camera.
  Future<void> pause();

  /// App is back: reopens the camera and the stream if it was running.
  Future<void> resume();

  /// Releases everything. Idempotent.
  Future<void> dispose();
}
