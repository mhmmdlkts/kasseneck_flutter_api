import 'dart:io';
import 'package:image/image.dart' as img;

/// Erzeugt aus dem transparenten Kreiseck-Logo eine reine Schwarz/Weiss-Version
/// fuer den Thermodruck (Drucker koennen kein Rot — Dithering wuerde matschig).
void main() {
  final src = img.decodePng(File('doc/kreiseck_logo_src.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('decode failed');
    exit(1);
  }
  const pad = 12;
  final out = img.Image(width: src.width + pad * 2, height: src.height + pad * 2);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (p.a < 128) continue; // transparent -> weiss
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum < 200) {
        out.setPixelRgb(x + pad, y + pad, 0, 0, 0);
      }
    }
  }
  File('assets/kreiseck_logo_print.png').createSync(recursive: true);
  File('assets/kreiseck_logo_print.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('OK ${out.width}x${out.height}');
}
