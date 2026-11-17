// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Why a frame cannot be measured at all (as opposed to a measured result whose
/// status is "not measurable"). UI maps [code] to a specific Indonesian message.
enum RejectReason {
  patchTooSmall('PATCH_TOO_SMALL'),
  psfEdgesUnavailable('PSF_EDGES_UNAVAILABLE'),
  blurTooLarge('BLUR_TOO_LARGE'),
  blurAnisotropic('BLUR_ANISOTROPIC'),
  saturated('SATURATED'),
  crackNotFound('CRACK_NOT_FOUND'),
  invalidInput('INVALID_INPUT');

  const RejectReason(this.code);
  final String code;
}

/// Thrown by the low-level measurement steps; `measureFrame` turns it into a
/// structured rejection.
final class MeasurementException implements Exception {
  const MeasurementException(this.reason, this.message);

  final RejectReason reason;

  /// Specific message for the user (Indonesian).
  final String message;

  @override
  String toString() => 'MeasurementException(${reason.code}): $message';
}
