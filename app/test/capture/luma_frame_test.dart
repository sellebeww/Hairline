// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/capture/luma_frame.dart';
import 'package:hairline_core/hairline_core.dart';

void main() {
  group('LumaFrame.fromYPlane', () {
    test('samples the right source pixel and honours the row stride', () {
      // 10 x 6 image, stride 16 (padding bytes are 255 and must never be read), pixel = 10*y + x.
      const w = 10, h = 6, stride = 16;
      final y = Uint8List(stride * h)..fillRange(0, stride * h, 255);
      for (var j = 0; j < h; j++) {
        for (var i = 0; i < w; i++) {
          y[j * stride + i] = 10 * j + i;
        }
      }
      final f = LumaFrame.fromYPlane(y: y, width: w, height: h, rowStride: stride, maxLongSide: 5);
      expect(f.step, 2); // ceil(10 / 5)
      expect(f.width, 5);
      expect(f.height, 3);
      // Small (i, j) is source (2i + 1, 2j + 1).
      for (var j = 0; j < f.height; j++) {
        for (var i = 0; i < f.width; i++) {
          expect(f.bytes[j * f.width + i], 10 * (2 * j + 1) + (2 * i + 1), reason: 'pixel $i,$j');
        }
      }
    });

    test('step 1 keeps every pixel and the source mapping is the identity', () {
      final y = Uint8List.fromList(List.generate(12, (i) => i));
      final f = LumaFrame.fromYPlane(y: y, width: 4, height: 3, rowStride: 4);
      expect(f.step, 1);
      expect(f.bytes, y);
      expect(f.toSource(const Pt(2, 1)), const Pt(2, 1));
    });

    test('toSource maps the decimated grid back to source pixels', () {
      final f = LumaFrame.fromYPlane(y: Uint8List(80 * 60), width: 80, height: 60, rowStride: 80, maxLongSide: 20);
      expect(f.step, 4);
      expect(f.toSource(const Pt(3, 2)), const Pt(3 * 4 + 2, 2 * 4 + 2));
    });

    test('rejects buffers that do not fit the declared geometry', () {
      expect(() => LumaFrame.fromYPlane(y: Uint8List(10), width: 4, height: 3, rowStride: 4), throwsArgumentError);
      expect(() => LumaFrame.fromYPlane(y: Uint8List(12), width: 4, height: 3, rowStride: 3), throwsArgumentError);
      expect(() => LumaFrame.fromYPlane(y: Uint8List(12), width: 0, height: 3, rowStride: 4), throwsArgumentError);
    });

    test('a 12 MP plane decimates to at most 800 px on the long side', () {
      final f = LumaFrame.fromYPlane(y: Uint8List(4000 * 3000), width: 4000, height: 3000, rowStride: 4000);
      expect(f.step, 5);
      expect(f.width, 800);
      expect(f.height, 600);
    });
  });
}
