import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/generator.dart';
import 'package:kasseneck_api/src/printing/escpos/enums.dart';
import 'package:kasseneck_api/src/printing/escpos/capability_profile.dart';
import 'package:kasseneck_api/src/printing/escpos/pos_styles.dart';
import 'package:kasseneck_api/src/printing/escpos/pos_column.dart';
import 'package:kasseneck_api/src/printing/escpos/qrcode.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

void main() {
  EscPosGenerator gen() => EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());

  test('text liefert Bytes inkl. Inhalt', () {
    final b = gen().text('Hallo');
    expect(b, isNotEmpty);
    expect(b.join(','), contains('Hallo'.codeUnits.join(',')));
  });

  test('row mit Spaltenbreite-Summe 12 wirft nicht', () {
    final b = gen().row([
      PosColumn(text: 'A', width: 6, styles: const PosStyles(align: PosAlign.left)),
      PosColumn(text: 'B', width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    expect(b, isNotEmpty);
  });

  test('qrcode delegiert an nativen QRCode-Befehl', () {
    final b = gen().qrcode('XYZ', size: QRSize.size6);
    expect(b.join(','), contains([0x31, 0x43, 0x06].join(','))); // Modulgroesse 6
  });

  test('imageRaster: 16x8 schwarz -> Header GS v 0 + Datenlaenge 2*8', () {
    final img = RasterImage.filled(16, 8, 0, 0, 0, 255);
    final b = gen().imageRaster(img);
    // Datenanteil = widthBytes(2)*height(8) = 16 schwarze Bytes (0xFF)
    expect(b.where((x) => x == 0xFF).length, greaterThanOrEqualTo(16));
  });

  test('image (ESC *) liefert Bytes ohne Crash fuer Nicht-/8-Breite', () {
    final img = RasterImage.filled(10, 24, 0, 0, 0, 255);
    expect(gen().image(img), isNotEmpty);
  });

  test('reset + setGlobalCodeTable(CP1252) setzt Codepage-Byte 16', () {
    final g = gen();
    g.reset();
    final b = g.setGlobalCodeTable('CP1252');
    expect(b.last, 16);
  });
}
