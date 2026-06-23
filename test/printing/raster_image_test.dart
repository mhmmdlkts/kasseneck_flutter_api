import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

void main() {
  test('filled setzt alle Pixel', () {
    final img = RasterImage.filled(2, 1, 255, 0, 0, 255);
    expect(img.width, 2);
    expect(img.height, 1);
    expect(img.rgba, Uint8List.fromList([255,0,0,255, 255,0,0,255]));
  });

  test('invertRgb invertiert RGB, Alpha bleibt', () {
    final img = RasterImage.filled(1, 1, 10, 20, 30, 128);
    img.invertRgb();
    expect(img.rgba, Uint8List.fromList([245, 235, 225, 128]));
  });

  test('flipHorizontal spiegelt Spalten', () {
    // 2x1: links rot, rechts gruen
    final img = RasterImage(2, 1, Uint8List.fromList([255,0,0,255, 0,255,0,255]));
    final f = img.flipHorizontal();
    expect(f.rgba, Uint8List.fromList([0,255,0,255, 255,0,0,255]));
  });

  test('rotate270 dreht 2x1 zu 1x2', () {
    final img = RasterImage(2, 1, Uint8List.fromList([1,1,1,255, 2,2,2,255]));
    final r = img.rotate270();
    expect(r.width, 1);
    expect(r.height, 2);
  });
}
