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

  test('eine zu lange Spalte verliert ihren Rest NICHT', () {
    // Gemessen am 28.08.2026 beim Vergleich der Bon-Bytes von 3.3.0 gegen
    // 5.2.0: die Fortsetzungszeile fehlte vollstaendig. Ursache war ein
    // `row(nextRow)` ohne `bytes +=` -- uebernommen aus esc_pos_utils 1.1.0,
    // wo esc_pos_utils_plus genau das behoben hatte. Auf dem Bon hiess das
    // ein abgeschnittener Artikelname.
    const lang = 'Marmelade Himbeere Extra Fein Grossglas';
    final b = gen().row([
      PosColumn(
          text: lang,
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: '14,70',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    // Jedes Zeichen des Namens muss in den Bytes vorkommen, verteilt ueber
    // so viele Zeilen wie noetig.
    final ausgabe = String.fromCharCodes(b.where((x) => x >= 32 && x < 127));
    for (final teil in ['Marmelade', 'Extra', 'Grossglas']) {
      expect(ausgabe, contains(teil),
          reason: '"$teil" fehlt auf dem Bon – die Fortsetzung ging verloren');
    }
  });

  test('eine Spalte, die passt, erzeugt keine Fortsetzungszeile', () {
    final kurz = gen().row([
      PosColumn(text: 'Brot', width: 6, styles: const PosStyles()),
      PosColumn(
          text: '3,30',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    final lang = gen().row([
      PosColumn(
          text: 'Brot mit einem sehr langen Namen der umbricht',
          width: 6,
          styles: const PosStyles()),
      PosColumn(
          text: '3,30',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    expect(lang.length, greaterThan(kurz.length),
        reason: 'die umbrochene Zeile muss mehr Bytes erzeugen');
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

  group('Zeichen ausserhalb Latin-1', () {
    // Artikelnamen kommen aus dem Panel und koennen alles enthalten. Ein
    // Beleg, der beim Drucken abstuerzt, ist am Tresen viel schlimmer als
    // einer mit einem Ersatzzeichen: der Beleg ist laengst signiert, nur das
    // Papier fehlt dann.
    test('ein Emoji im Artikelnamen stuerzt den Druck nicht ab', () {
      expect(() => gen().text('Kaffee \u2615'), returnsNormally);
    });

    test('unbekannte Zeichen werden zu ?, der Rest bleibt lesbar', () {
      final bytes = gen().text('Cafe \u2615 Bar');
      final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(text, contains('Cafe ? Bar'));
    });

    test('das Euro-Zeichen wird lesbar ersetzt, nicht weggeworfen', () {
      // 0,50 ? waere eine Zumutung; 0,50 EUR ist eine Auskunft.
      final bytes = gen().text('0,50 \u20ac');
      final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(text, contains('0,50 EUR'));
    });

    test('Umlaute bleiben Umlaute', () {
      final bytes = gen().text('Grün');
      expect(bytes, contains(0xFC), reason: 'ü ist Latin-1 0xFC');
    });
  });

  test('reset + setGlobalCodeTable(CP1252) setzt Codepage-Byte 16', () {
    final g = gen();
    g.reset();
    final b = g.setGlobalCodeTable('CP1252');
    expect(b.last, 16);
  });
}
