import 'dart:typed_data';
import 'dart:ui' as ui;
import 'raster_image.dart';

/// PNG -> RasterImage. Nutzt Flutters eingebauten Codec (keine image-Lib).
/// Liefert STRAIGHT (nicht-premultiplied) RGBA, damit halbtransparente Kanten
/// (Logos) nicht zu dunkel werden.
Future<RasterImage> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? bd =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final int w = image.width;
  final int h = image.height;
  image.dispose();
  codec.dispose();
  if (bd == null) {
    throw StateError('PNG-Decode lieferte keine Bytes');
  }
  return RasterImage(w, h, bd.buffer.asUint8List().sublist(0, w * h * 4));
}

/// RasterImage -> PNG-Bytes (fuer den myPos-Druckpfad).
Future<Uint8List> encodePng(RasterImage img) async {
  final descriptor = ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(img.rgba),
    width: img.width,
    height: img.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final ByteData? bd =
      await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  if (bd == null) {
    throw StateError('PNG-Encode lieferte keine Bytes');
  }
  return bd.buffer.asUint8List();
}
