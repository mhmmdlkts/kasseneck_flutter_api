import 'dart:typed_data';
import 'raster_image.dart';

/// Rec.601-Luminanz (entspricht grayscale aus image 3.x), gerundet 0..255.
int luma(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();

/// Komponiert [fg] per straight-alpha auf weissen Hintergrund.
/// Transparente Pixel werden weiss (verhindert das "schwarze Quadrat" beim
/// alpha-ignorierenden ESC/POS-Rasterizer). Ergebnis ist voll opak.
RasterImage compositeOnWhite(RasterImage fg,
    {int? canvasWidth, int? canvasHeight, int dstX = 0, int dstY = 0}) {
  final int w = canvasWidth ?? fg.width;
  final int h = canvasHeight ?? fg.height;
  final out = Uint8List(w * h * 4);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = 255;
    out[i + 1] = 255;
    out[i + 2] = 255;
    out[i + 3] = 255;
  }
  for (int y = 0; y < fg.height; y++) {
    final int oy = y + dstY;
    if (oy < 0 || oy >= h) continue;
    for (int x = 0; x < fg.width; x++) {
      final int ox = x + dstX;
      if (ox < 0 || ox >= w) continue;
      final s = (y * fg.width + x) * 4;
      final int a = fg.rgba[s + 3];
      if (a == 0) continue; // bleibt weiss
      final d = (oy * w + ox) * 4;
      // over white: out = src*a + 255*(255-a), /255
      out[d] = (fg.rgba[s] * a + 255 * (255 - a)) ~/ 255;
      out[d + 1] = (fg.rgba[s + 1] * a + 255 * (255 - a)) ~/ 255;
      out[d + 2] = (fg.rgba[s + 2] * a + 255 * (255 - a)) ~/ 255;
      out[d + 3] = 255;
    }
  }
  return RasterImage(w, h, out);
}

RasterImage resizeTo(RasterImage src, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    final int sy = (y * src.height ~/ h).clamp(0, src.height - 1);
    for (int x = 0; x < w; x++) {
      final int sx = (x * src.width ~/ w).clamp(0, src.width - 1);
      final s = (sy * src.width + sx) * 4;
      final d = (y * w + x) * 4;
      out[d] = src.rgba[s];
      out[d + 1] = src.rgba[s + 1];
      out[d + 2] = src.rgba[s + 2];
      out[d + 3] = src.rgba[s + 3];
    }
  }
  return RasterImage(w, h, out);
}

RasterImage resizeWidth(RasterImage src, int targetWidth) {
  final int targetHeight = (src.height * targetWidth / src.width).round();
  return resizeTo(src, targetWidth, targetHeight);
}

/// GS v 0 Rohdaten: ein Bit pro Pixel, 8 Pixel/Byte, linkes Pixel = MSB.
/// Punkt gesetzt, wenn Luminanz < 128 (grayscale -> invert -> Threshold 127).
/// Alpha wird ignoriert (wie der ESC/POS-Generator) — daher VORHER auf Weiss
/// komponieren. Breite wird implizit auf Vielfaches von 8 gepadded (Padding-Bits
/// = 0 = kein Punkt). Korrekt fuer JEDE Breite (kein Crash, anders als
/// esc_pos_utils_plus 2.0.4).
List<int> toEscPosRaster(RasterImage img) {
  final int w = img.width, h = img.height;
  final int widthBytes = (w + 7) >> 3;
  final out = Uint8List(widthBytes * h);
  final rgba = img.rgba;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = (y * w + x) * 4;
      if (luma(rgba[p], rgba[p + 1], rgba[p + 2]) < 128) {
        out[y * widthBytes + (x >> 3)] |= (0x80 >> (x & 7));
      }
    }
  }
  return out;
}

/// ESC * Spalten-Format: Breite auf Vielfaches von [lineHeight] mit Schwarz
/// aufgefuellt, dann je [lineHeight] breiter Slice die Luminanz jedes Pixels.
/// Entspricht _toColumnFormat aus esc_pos_utils 1.1.0.
List<List<int>> toColumnFormat(RasterImage img, int lineHeight) {
  // Diese Formel ist bewusst identisch zu esc_pos_utils 1.1.0: sie paddet auch
  // dann eine volle Spaltengruppe an, wenn die Breite bereits durch lineHeight
  // teilbar ist (img.width % lineHeight == 0). Dies ist gewollt und bewahrt
  // das bewaehrte ESC/POS-Verhalten byte-genau.
  final int widthPx = (img.width + lineHeight) - (img.width % lineHeight);
  final int heightPx = img.height;
  // Schwarzer Canvas, Originalbild oben-links eingesetzt.
  final canvas = Uint8List(widthPx * heightPx * 4); // alles 0 -> schwarz, Alpha 0
  for (int i = 3; i < canvas.length; i += 4) {
    canvas[i] = 255; // opak schwarz
  }
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final s = (y * img.width + x) * 4;
      final d = (y * widthPx + x) * 4;
      canvas[d] = img.rgba[s];
      canvas[d + 1] = img.rgba[s + 1];
      canvas[d + 2] = img.rgba[s + 2];
      canvas[d + 3] = img.rgba[s + 3];
    }
  }
  final List<List<int>> blobs = [];
  int left = 0;
  while (left < widthPx) {
    final blob = <int>[];
    for (int y = 0; y < heightPx; y++) {
      for (int x = left; x < left + lineHeight; x++) {
        final p = (y * widthPx + x) * 4;
        blob.add(luma(canvas[p], canvas[p + 1], canvas[p + 2]));
      }
    }
    blobs.add(blob);
    left += lineHeight;
  }
  return blobs;
}
