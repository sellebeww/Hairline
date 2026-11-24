// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/lens_info.dart';
import 'package:hairline_core/hairline_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelLensInfoSource.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void reply(Future<Object?>? Function(MethodCall call) handler) => messenger.setMockMethodCallHandler(channel, handler);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('channel name matches the Kotlin side', () {
    expect(MethodChannelLensInfoSource.channelName, 'id.vassel.hairline/lens');
  });

  test('a complete reply is parsed and the request carries the camera id', () async {
    MethodCall? seen;
    reply((call) async {
      seen = call;
      return {
        'cameraId': '0',
        'focalLengthMm': 5.4,
        'sensorWidthMm': 7.0,
        'sensorHeightMm': 5.2,
        'pixelArrayWidth': 4000,
        'pixelArrayHeight': 3000,
        'sensorOrientation': 90,
        'deviceModel': 'Vendor Model X',
      };
    });
    final info = await MethodChannelLensInfoSource().read('0');
    expect(seen!.method, 'getLensInfo');
    expect((seen!.arguments as Map<Object?, Object?>)['cameraId'], '0');
    expect(info.focalLengthMm, 5.4);
    expect(info.sensorLongSideMm, 7.0);
    expect(info.pixelArrayWidth, 4000);
    expect(info.sensorOrientation, 90);
    expect(info.deviceModel, 'Vendor Model X');
    final cam = info.toCameraInfo(flags: ['fokus_tidak_terkunci']);
    expect(cam.focalMm, 5.4);
    expect(cam.sensorLongSideMm, 7.0);
    expect(cam.toJson()['flags'], ['fokus_tidak_terkunci']);
  });

  test('missing, zero, negative or non-finite values become null instead of failing', () async {
    reply((call) async => {
          'cameraId': '2',
          'focalLengthMm': 0,
          'sensorWidthMm': -3.0,
          'sensorHeightMm': double.nan,
          'pixelArrayWidth': 0,
          'sensorOrientation': 45,
          'deviceModel': '  ',
        });
    final info = await MethodChannelLensInfoSource().read('2');
    expect(info.focalLengthMm, isNull);
    expect(info.sensorWidthMm, isNull);
    expect(info.sensorHeightMm, isNull);
    expect(info.pixelArrayWidth, isNull);
    expect(info.sensorOrientation, isNull);
    expect(info.sensorLongSideMm, isNull);
    expect(info.deviceModel, 'tidak diketahui');
  });

  test('a platform error or a missing plugin yields "unavailable", never an exception', () async {
    reply((call) async => throw PlatformException(code: 'LENS_INFO', message: 'boom'));
    expect((await MethodChannelLensInfoSource().read('9')).focalLengthMm, isNull);
    reply((call) async => throw MissingPluginException());
    final info = await MethodChannelLensInfoSource().read('9');
    expect(info.cameraId, '9');
    expect(info.focalLengthMm, isNull);
    reply((call) async => null);
    expect((await MethodChannelLensInfoSource().read('9')).sensorLongSideMm, isNull);
  });

  test('unavailable lens data falls back to the default focal length and tilt stays approximate', () {
    final cam = const LensInfo.unavailable().toCameraInfo();
    final k = CameraIntrinsics.fromImage(const ImageSize(4000, 3000), focalMm: cam.focalMm, sensorLongSideMm: cam.sensorLongSideMm);
    expect(k.fPx, closeTo(0.75 * 4000, 1e-9));
    expect(const TiltEstimate(5).tiltIsApprox, isTrue);
  });

  test('available lens data gives focal_mm / sensor_long_side_mm x long side (orientation independent)', () {
    const lens = LensInfo(focalLengthMm: 5.6, sensorWidthMm: 5.0, sensorHeightMm: 7.0);
    final cam = lens.toCameraInfo();
    final landscape = CameraIntrinsics.fromImage(const ImageSize(4000, 3000), focalMm: cam.focalMm, sensorLongSideMm: cam.sensorLongSideMm);
    final portrait = CameraIntrinsics.fromImage(const ImageSize(3000, 4000), focalMm: cam.focalMm, sensorLongSideMm: cam.sensorLongSideMm);
    expect(landscape.fPx, closeTo(5.6 / 7.0 * 4000, 1e-9));
    expect(portrait.fPx, landscape.fPx);
  });
}
