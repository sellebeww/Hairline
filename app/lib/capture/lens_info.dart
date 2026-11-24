// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/services.dart';

import '../pipeline/visit_processor.dart';

/// Lens facts read from Android `CameraCharacteristics` (Kotlin `LensInfoPlugin`).
///
/// Every field is optional: devices may report nothing, zero, or nonsense. Missing
/// values are null and the core then falls back to the default focal length
/// (`0.75 x longest side`); `tilt_is_approx` is true either way (5.2).
final class LensInfo {
  const LensInfo({
    this.cameraId,
    this.focalLengthMm,
    this.sensorWidthMm,
    this.sensorHeightMm,
    this.pixelArrayWidth,
    this.pixelArrayHeight,
    this.sensorOrientation,
    this.deviceModel = 'tidak diketahui',
  });

  /// Nothing known (channel missing or the platform reported no characteristics).
  const LensInfo.unavailable({this.cameraId})
      : focalLengthMm = null,
        sensorWidthMm = null,
        sensorHeightMm = null,
        pixelArrayWidth = null,
        pixelArrayHeight = null,
        sensorOrientation = null,
        deviceModel = 'tidak diketahui';

  /// Parses the channel reply; invalid numbers become null instead of failing.
  factory LensInfo.fromMap(Map<Object?, Object?> m) {
    double? pos(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : null;
    int? posInt(Object? v) => v is num && v.isFinite && v > 0 ? v.toInt() : null;
    final orient = m['sensorOrientation'];
    final model = m['deviceModel'];
    return LensInfo(
      cameraId: m['cameraId'] is String ? m['cameraId']! as String : null,
      focalLengthMm: pos(m['focalLengthMm']),
      sensorWidthMm: pos(m['sensorWidthMm']),
      sensorHeightMm: pos(m['sensorHeightMm']),
      pixelArrayWidth: posInt(m['pixelArrayWidth']),
      pixelArrayHeight: posInt(m['pixelArrayHeight']),
      sensorOrientation: orient is int && orient >= 0 && orient < 360 && orient % 90 == 0 ? orient : null,
      deviceModel: model is String && model.trim().isNotEmpty ? model.trim() : 'tidak diketahui',
    );
  }

  final String? cameraId;
  final double? focalLengthMm;
  final double? sensorWidthMm;
  final double? sensorHeightMm;
  final int? pixelArrayWidth;
  final int? pixelArrayHeight;
  final int? sensorOrientation;
  final String deviceModel;

  /// Physical sensor dimension along the image's long side; null unless both are known.
  double? get sensorLongSideMm {
    final w = sensorWidthMm, h = sensorHeightMm;
    if (w == null || h == null) return null;
    return w > h ? w : h;
  }

  /// For `visits.camera_info_json` and the intrinsics approximation.
  CameraInfo toCameraInfo({List<String> flags = const []}) =>
      CameraInfo(focalMm: focalLengthMm, sensorLongSideMm: sensorLongSideMm, flags: flags);
}

/// Where lens characteristics come from.
abstract interface class LensInfoSource {
  Future<LensInfo> read(String cameraId);
}

/// Android implementation behind the platform channel [channelName].
final class MethodChannelLensInfoSource implements LensInfoSource {
  MethodChannelLensInfoSource([MethodChannel? channel]) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'id.vassel.hairline/lens';
  final MethodChannel _channel;

  @override
  Future<LensInfo> read(String cameraId) async {
    try {
      final reply = await _channel.invokeMapMethod<Object?, Object?>('getLensInfo', {'cameraId': cameraId});
      return reply == null ? LensInfo.unavailable(cameraId: cameraId) : LensInfo.fromMap(reply);
    } on PlatformException {
      return LensInfo.unavailable(cameraId: cameraId);
    } on MissingPluginException {
      return LensInfo.unavailable(cameraId: cameraId);
    }
  }
}
