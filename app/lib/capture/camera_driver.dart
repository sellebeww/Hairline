// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'camera_service.dart';

/// One raw luminance frame of the image stream.
final class RawYFrame {
  const RawYFrame({required this.y, required this.width, required this.height, required this.rowStride});

  final Uint8List y;
  final int width;
  final int height;
  final int rowStride;
}

final class DriverInfo {
  const DriverInfo({required this.cameraId, this.sensorOrientation});

  final String cameraId;
  final int? sensorOrientation;
}

/// The thin layer over `CameraController`, kept free of sequencing logic so that
/// [DeviceCameraService] (lifecycle, races, errors) can be tested with a fake driver.
/// This implementation needs a real camera: written, not run (docs/DEVICE_TEST.md).
abstract interface class CameraDriver {
  /// Permission, controller, flash off, portrait capture orientation. Throws [CameraFailure].
  Future<DriverInfo> open();

  Widget preview();

  Future<void> startStream(void Function(RawYFrame frame) onFrame);

  Future<void> stopStream();

  /// Requests focus and exposure locks; reports which ones went through without error.
  Future<LockResult> lock();

  Future<void> unlock();

  /// One still as JPEG bytes. The temporary file the plugin wrote is deleted.
  Future<Uint8List> takePicture();

  /// Releases the controller. Idempotent.
  Future<void> close();
}

typedef CameraDriverFactory = CameraDriver Function();

/// [CameraDriver] over the `camera` package: back camera, highest still resolution
/// (the package ties the stream resolution to the same preset), flash off, YUV420 stream.
final class CameraPluginDriver implements CameraDriver {
  CameraController? _c;

  CameraController get _ctl => _c ?? (throw const CameraFailure(CameraFailureKind.interrupted, 'controller closed'));

  static CameraFailure _map(CameraException e) => switch (e.code) {
        'CameraAccessDenied' => CameraFailure(CameraFailureKind.permissionDenied, e.description),
        'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' => CameraFailure(CameraFailureKind.permissionDeniedForever, e.description),
        _ => CameraFailure(CameraFailureKind.openFailed, '${e.code}: ${e.description}'),
      };

  @override
  Future<DriverInfo> open() async {
    final List<CameraDescription> all;
    try {
      all = await availableCameras();
    } on CameraException catch (e) {
      throw _map(e);
    }
    final back = all.where((d) => d.lensDirection == CameraLensDirection.back).toList();
    if (back.isEmpty) throw const CameraFailure(CameraFailureKind.noCamera);
    // Several back lenses: the first is the main camera on the phones the plugin lists.
    // Which lens to use on multi-lens phones is a device test item (docs/DEVICE_TEST.md).
    final description = back.first;
    final c = CameraController(description, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    _c = c;
    try {
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (e) {
      await close();
      throw _map(e);
    }
    return DriverInfo(cameraId: description.name, sensorOrientation: description.sensorOrientation);
  }

  @override
  Widget preview() => CameraPreview(_ctl);

  @override
  Future<void> startStream(void Function(RawYFrame frame) onFrame) => _ctl.startImageStream((image) {
        final plane = image.planes.first;
        onFrame(RawYFrame(y: plane.bytes, width: image.width, height: image.height, rowStride: plane.bytesPerRow));
      });

  @override
  Future<void> stopStream() async {
    final c = _c;
    if (c != null && c.value.isStreamingImages) await c.stopImageStream();
  }

  @override
  Future<LockResult> lock() async {
    var focus = false, exposure = false;
    try {
      await _ctl.setFocusMode(FocusMode.locked);
      focus = true;
    } on CameraException {
      // The device cannot lock focus: the burst goes on and is flagged (5.4 gate decides).
    }
    try {
      await _ctl.setExposureMode(ExposureMode.locked);
      exposure = true;
    } on CameraException {
      // Same for exposure.
    }
    return LockResult(focusLocked: focus, exposureLocked: exposure);
  }

  @override
  Future<void> unlock() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
    } on CameraException {
      // Nothing to restore on a device that never locked.
    }
  }

  @override
  Future<Uint8List> takePicture() async {
    final XFile file;
    try {
      file = await _ctl.takePicture();
    } on CameraException catch (e) {
      throw CameraFailure(CameraFailureKind.captureFailed, '${e.code}: ${e.description}');
    }
    try {
      return await file.readAsBytes();
    } finally {
      // The plugin's cache file is a second copy of the photo outside the private store.
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  @override
  Future<void> close() async {
    final c = _c;
    _c = null;
    if (c == null) return;
    try {
      await c.dispose();
    } on CameraException {
      // Closing an already-lost camera.
    }
  }
}
