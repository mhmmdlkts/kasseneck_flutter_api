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

  test('eine passende Spalte bleibt einzeilig, eine zu lange bekommt eine '
      'Fortsetzung', () {
    // Gezaehlt werden ZEILENVORSCHUEBE, nicht Bytes. Die naheliegende
    // Pruefung "die umbrochene Zeile ist laenger" faellt nicht auf den
    // Fehler herein -- sie ist auch OHNE die Korrektur wahr (gemessen:
    // 35 gegen 24 Bytes), weil die abgeschnittene Spalte auf ihre volle
    // Breite aufgefuellt wird. Sie waere ein Test, der nie rot wird.
    int zeilenvorschuebe(List<int> bytes) =>
        bytes.where((b) => b == 0x0A).length;

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

    expect(zeilenvorschuebe(kurz), 1,
        reason: 'was passt, darf keine Fortsetzungszeile bekommen -- sonst '
            'zerreisst die Korrektur jeden normalen Bon');
    expect(zeilenvorschuebe(lang), greaterThan(1),
        reason: 'der Rest der zu langen Spalte braucht eine eigene Zeile');
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

  /// Index der ersten Fundstelle von [muster] in [bytes], sonst -1.
  int stelle(List<int> bytes, List<int> muster) {
    for (var i = 0; i + muster.length <= bytes.length; i++) {
      var passt = true;
      for (var j = 0; j < muster.length; j++) {
        if (bytes[i + j] != muster[j]) {
          passt = false;
          break;
        }
      }
      if (passt) return i;
    }
    return -1;
  }

  test('volle Zeile nach dem QR: Ausrichtung vor dem Inhalt, ohne Positionsbefehl', () {
    // `ESC a` gilt am Drucker NUR am Zeilenanfang. Stand davor ein `ESC $`,
    // verwarf der Epson die Ausrichtung -- die Zentrierung des QR-Codes blieb
    // fuer alle Zeilen darunter stehen, und das bereits auf volle Breite
    // zentrierte Raster wurde ein zweites Mal zentriert. Gemessen am Bon vom
    // 18.09.2026: Versatz genau (48 - Zeichenzahl) / 4.
    //
    // Der QR-Code davor ist die Vorbedingung, nicht Beiwerk: `setStyles`
    // schreibt `ESC a` nur bei einem Wechsel, und ein frischer Erzeuger steht
    // ohnehin auf links. Erst der zentriert gesetzte QR stellt den Zustand
    // her, in dem der Fehler entsteht.
    final g = gen();
    g.qrcode('TESTQRDATA');
    final b = g.text('Danke', styles: const PosStyles(align: PosAlign.left));

    expect(stelle(b, [0x1B, 0x24]), -1,
        reason: 'eine volle Zeile braucht keinen Positionsbefehl');
    final ausrichtung = stelle(b, [0x1B, 0x61, 0x30]);
    final inhalt = stelle(b, 'Danke'.codeUnits);
    expect(ausrichtung, greaterThanOrEqualTo(0),
        reason: 'ESC a 0 muss gesetzt werden, sonst bleibt der Drucker zentriert');
    expect(ausrichtung, lessThan(inhalt),
        reason: 'die Ausrichtung muss vor dem Text stehen');
  });

  test('Spaltenzeile: erst Ausrichtung, dann Position', () {
    // Die erste Spalte ist zentriert, damit `setStyles` ueberhaupt einen
    // Wechsel sieht (frischer Erzeuger steht auf links).
    final b = gen().row([
      PosColumn(text: 'A', width: 6, styles: const PosStyles(align: PosAlign.center)),
      PosColumn(text: 'B', width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    final ausrichtung = stelle(b, [0x1B, 0x61]);
    final position = stelle(b, [0x1B, 0x24]);
    expect(position, greaterThanOrEqualTo(0),
        reason: 'Spalten werden weiterhin positioniert');
    expect(ausrichtung, greaterThanOrEqualTo(0));
    expect(ausrichtung, lessThan(position));
  });
}
