import 'dart:typed_data';

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

  test('toColumnFormat: bei bereits durch lineHeight teilbarer Breite wird '
      'bewusst eine zusaetzliche Spaltengruppe gepadded (wie esc_pos_utils 1.1.0)', () {
    final img = RasterImage.filled(8, 8, 0, 0, 0, 255); // 8 % 8 == 0
    final blobs = toColumnFormat(img, 8);
    expect(blobs.length, 2); // 8 -> gepadded auf 16 -> 2 Slices (gewollt)
  });

  test('toColumnFormat: Slice ist zeilen-major (wie esc_pos_utils 1.1.0 getBytes(luminance))', () {
    // 2x2 Bild; lineHeight 2 -> Breite 2 wird auf 4 gepadded (2 schwarze Spalten rechts).
    // Erster Slice deckt x=0..1 ab. Pixel (x,y) bekommen unterschiedliche Graustufen.
    final img = RasterImage(2, 2, Uint8List.fromList([
      10, 10, 10, 255,  20, 20, 20, 255,   // y=0: x0=10, x1=20
      30, 30, 30, 255,  40, 40, 40, 255,   // y=1: x0=30, x1=40
    ]));
    final blobs = toColumnFormat(img, 2);
    // Erster Slice (x=0..1), zeilen-major: y0(x0,x1), y1(x0,x1) = [10,20,30,40]
    expect(blobs.first.sublist(0, 4), [10, 20, 30, 40]);
  });
}
