import 'dart:typed_data';

/// Einfaches RGBA-Bild (4 Bytes/Pixel: R,G,B,A) als Ersatz fuer image.Image.
/// Bewusst minimal — nur was der Druckpfad braucht.
class RasterImage {
  final int width;
  final int height;
  final Uint8List rgba;

  RasterImage(this.width, this.height, this.rgba)
      : assert(rgba.length == width * height * 4);

  factory RasterImage.filled(int w, int h, int r, int g, int b, int a) {
    final buf = Uint8List(w * h * 4);
    for (int i = 0; i < buf.length; i += 4) {
      buf[i] = r;
      buf[i + 1] = g;
      buf[i + 2] = b;
      buf[i + 3] = a;
    }
    return RasterImage(w, h, buf);
  }

  RasterImage clone() => RasterImage(width, height, Uint8List.fromList(rgba));

  /// RGB invertieren (255 - v), Alpha unveraendert.
  void invertRgb() {
    for (int i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255 - rgba[i];
      rgba[i + 1] = 255 - rgba[i + 1];
      rgba[i + 2] = 255 - rgba[i + 2];
    }
  }

  RasterImage flipHorizontal() {
    final out = Uint8List(rgba.length);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final src = (y * width + x) * 4;
        final dst = (y * width + (width - 1 - x)) * 4;
        out[dst] = rgba[src];
        out[dst + 1] = rgba[src + 1];
        out[dst + 2] = rgba[src + 2];
        out[dst + 3] = rgba[src + 3];
      }
    }
    return RasterImage(width, height, out);
  }

  /// 270 Grad im Uhrzeigersinn (entspricht copyRotate(img, 270) aus image 3.x).
  RasterImage rotate270() {
    final out = Uint8List(rgba.length);
    final int nw = height, nh = width;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final src = (y * width + x) * 4;
        // 270 cw: (x,y) -> (y, width-1-x)
        final int dx = y;
        final int dy = width - 1 - x;
        final dst = (dy * nw + dx) * 4;
        out[dst] = rgba[src];
        out[dst + 1] = rgba[src + 1];
        out[dst + 2] = rgba[src + 2];
        out[dst + 3] = rgba[src + 3];
      }
    }
    return RasterImage(nw, nh, out);
  }
}
