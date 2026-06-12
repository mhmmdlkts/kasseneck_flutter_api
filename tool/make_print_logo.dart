import 'dart:io';
import 'package:image/image.dart' as img;

/// Erzeugt aus dem Hi-Res-Lockup (doc/kreiseck_logo_hires.png, aus den
/// Canva-Ebenen rekonstruiert via make_hires_logo.dart) eine reine
/// Schwarz/Weiss-Version fuer den Thermodruck (Drucker koennen kein Rot).
void main() {
  final src = img.decodePng(File('doc/kreiseck_logo_hires.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('decode failed');
    exit(1);
  }
  // 1200px reicht fuer jeden Thermodruck (mm80 bei 85% = 428px) und haelt das Asset klein.
  final scaled = img.copyResize(src, width: 1200, interpolation: img.Interpolation.cubic);
  const pad = 24;
  final out = img.Image(width: scaled.width + pad * 2, height: scaled.height + pad * 2);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  for (int y = 0; y < scaled.height; y++) {
    for (int x = 0; x < scaled.width; x++) {
      final p = scaled.getPixel(x, y);
      if (p.a < 128) continue; // transparent -> weiss
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum < 200) {
        out.setPixelRgb(x + pad, y + pad, 0, 0, 0);
      }
    }
  }
  File('assets/kreiseck_logo_print.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('OK ${out.width}x${out.height}');
}
