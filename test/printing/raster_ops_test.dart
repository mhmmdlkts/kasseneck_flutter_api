import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';
import 'package:kasseneck_api/src/printing/raster/raster_ops.dart';

void main() {
  test('toEscPosRaster: Laenge = ((w+7)~/8)*h, auch bei Breite NICHT durch 8', () {
    // 10x4 -> widthBytes = 2 -> 8 Bytes. Frueherer esc_pos_utils_plus-Bug: Crash.
    final img = RasterImage.filled(10, 4, 0, 0, 0, 255); // schwarz
    final data = toEscPosRaster(img);
    expect(data.length, 8);
  });

  test('toEscPosRaster: schwarz -> Punkte gesetzt, weiss -> keine', () {
    final black = RasterImage.filled(8, 1, 0, 0, 0, 255);
    final white = RasterImage.filled(8, 1, 255, 255, 255, 255);
    expect(toEscPosRaster(black), [0xFF]);
    expect(toEscPosRaster(white), [0x00]);
  });

  test('toEscPosRaster: linkes Pixel ist MSB', () {
    // 8 Pixel: nur erstes schwarz -> 0x80
    final buf = RasterImage.filled(8, 1, 255, 255, 255, 255);
    buf.rgba[0] = 0; buf.rgba[1] = 0; buf.rgba[2] = 0; // Pixel 0 schwarz
    expect(toEscPosRaster(buf), [0x80]);
  });

  test('compositeOnWhite: transparentes Schwarz wird Weiss (Alpha->Weiss-Fix)', () {
    final fg = RasterImage.filled(1, 1, 0, 0, 0, 0); // schwarz, voll transparent
    final out = compositeOnWhite(fg);
    expect(out.rgba, [255, 255, 255, 255]);
  });

  test('compositeOnWhite: opakes Schwarz bleibt Schwarz', () {
    final fg = RasterImage.filled(1, 1, 0, 0, 0, 255);
    final out = compositeOnWhite(fg);
    expect(out.rgba, [0, 0, 0, 255]);
  });

  test('compositeOnWhite + toEscPosRaster: transparenter QR-Pixel druckt NICHT', () {
    final fg = RasterImage.filled(8, 1, 0, 0, 0, 0); // transparent schwarz
    final flat = compositeOnWhite(fg);
    expect(toEscPosRaster(flat), [0x00]); // kein schwarzes Quadrat
  });

  test('resizeWidth: skaliert Breite, Hoehe proportional', () {
    final src = RasterImage.filled(10, 5, 0, 0, 0, 255);
    final out = resizeWidth(src, 20);
    expect(out.width, 20);
    expect(out.height, 10);
  });

  test('toColumnFormat: Breite auf Vielfaches von lineHeight', () {
    final img = RasterImage.filled(10, 8, 0, 0, 0, 255);
    final blobs = toColumnFormat(img, 8); // gepadded auf 16 -> 2 Slices
    expect(blobs.length, 2);
    expect(blobs[0].length, 8 * 8); // lineHeight*height Luminanzbytes
  });
}
