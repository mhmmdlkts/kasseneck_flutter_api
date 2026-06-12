import 'dart:io';
import 'package:image/image.dart' as img;

/// Rekonstruiert das Kreiseck-Lockup (Ring + Wortmarke) in hoher Aufloesung
/// aus den Canva-Einzelebenen. Proportionen werden am 587px-Original gemessen.
img.Image crop(img.Image src, {required bool Function(img.Pixel) hit}) {
  int minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (final p in src) {
    if (p.a > 128 && hit(p)) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  return img.copyCrop(src, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
}

void main() {
  final ringSrc = img.decodePng(File('/Users/mali/Downloads/kartvizit (2)/kreiseck_title_black_o.png').readAsBytesSync())!;
  final wordSrc = img.decodePng(File('/Users/mali/Downloads/kartvizit (2)/kreiseck_title_black.png').readAsBytesSync())!;
  final orig = img.decodePng(File('doc/kreiseck_logo_src.png').readAsBytesSync())!;

  final ring = crop(ringSrc, hit: (p) => p.r > 80 && p.g < 100); // rote Pixel
  final word = crop(wordSrc, hit: (p) => p.r < 100);             // schwarze Pixel

  // Original vermessen: Ring (rot) und Wortmarke (schwarz, rechts vom Ring)
  final origRing = crop(orig, hit: (p) => p.r > 80 && p.g < 100);
  // Bounding-Verhaeltnisse aus dem Original ableiten
  // Ring-Hoehe als Referenz; Wortmarken-Hoehe + Abstand relativ dazu messen wir
  // grob ueber die bekannten Werte des Originals (Ring ~170px, Cap ~62px, Gap ~55px).
  const scale = 4.0; // Ziel: ~4x des Originals
  final ringH = (origRing.height * scale).round();
  final ringScaled = img.copyResize(ring, height: ringH, interpolation: img.Interpolation.cubic);
  // Wortmarke: Hoehe relativ zum Ring wie im Original (62/170)
  final wordH = (ringH * 62 / 170).round();
  final wordScaled = img.copyResize(word, height: wordH, interpolation: img.Interpolation.cubic);
  final gap = (ringH * 55 / 170).round();

  const pad = 40;
  final outW = pad + ringScaled.width + gap + wordScaled.width + pad;
  final outH = pad + ringH + pad;
  final out = img.Image(width: outW, height: outH, numChannels: 4);
  // transparent lassen (PDF embedPng kann Alpha)
  img.compositeImage(out, ringScaled, dstX: pad, dstY: pad);
  img.compositeImage(out, wordScaled, dstX: pad + ringScaled.width + gap, dstY: pad + ((ringH - wordH) / 2).round());

  File('/tmp/kreiseck_logo_hires.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('OK ${out.width}x${out.height}');
}
