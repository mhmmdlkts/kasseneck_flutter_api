import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encode->decode Roundtrip erhaelt Maße + opake Farbe', () async {
    final src = RasterImage.filled(4, 3, 12, 34, 56, 255);
    final png = await encodePng(src);
    final back = await decodePng(png);
    expect(back.width, 4);
    expect(back.height, 3);
    // erstes Pixel ~ Ausgangsfarbe (PNG verlustfrei)
    expect(back.rgba.sublist(0, 4), [12, 34, 56, 255]);
  });

  test('decode liefert straight Alpha (transparent schwarz bleibt 0-Alpha)', () async {
    final src = RasterImage.filled(2, 2, 0, 0, 0, 0);
    final png = await encodePng(src);
    final back = await decodePng(png);
    expect(back.rgba[3], 0); // Alpha 0
  });
}
