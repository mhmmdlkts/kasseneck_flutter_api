import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

/// Der Erzeuger kodiert Text in der Tabelle, die er dem Drucker ansagt.
///
/// Bis 10.0 schickte er fuer `CP437` zwar `ESC t 0`, aber die Bytes von
/// Latin-1: ein `ä` kam als 0xE4 an, und das ist in CP437 ein `Σ`.
void main() {
  List<int> textMit(String? codeTable, String text) {
    final gen = EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());
    gen.setGlobalCodeTable(codeTable);
    return gen.text(text);
  }

  List<int> ende(List<int> bytes, int n) => bytes.sublist(bytes.length - n);

  test('CP437 sendet die CP437-Bytes, nicht Latin-1 (ä = 0x84)', () {
    expect(ende(textMit('CP437', 'ä'), 7), [0x1c, 0x2e, 0x1b, 0x74, 0, 0x84, 0x0a]);
    expect(ende(textMit('CP437', 'Grüße Öl 20°'), 13), [...'Gr'.codeUnits, 0x81, 0xe1, ...'e '.codeUnits, 0x99, ...'l 20'.codeUnits, 0xf8, 0x0a]);
  });

  test('CP437: Zeichen ohne Platz werden Ersatz statt eines falschen Zeichens', () {
    // € ersetzt der alte Weg schon am Text (EUR), § hat in CP437 keinen Platz.
    expect(ende(textMit('CP437', '5 € § Ð'), 13), [...'5 EUR Par. ?'.codeUnits, 0x0a]);
  });

  test('CP1252 und ohne Tabelle: Latin-1 wie bisher, auch ein C1-Steuerzeichen roh', () {
    expect(ende(textMit('CP1252', 'ä•€\u0085'), 7), [0xe4, 0x2e, ...'EUR'.codeUnits, 0x85, 0x0a]);
    expect(ende(textMit(null, 'ä€'), 5), [0xe4, ...'EUR'.codeUnits, 0x0a]);
  });

  for (final t in codeTables) {
    test('${t.id.name}: ESC t ${t.escT} und die Bytes der Tabelle', () {
      const text = 'Grüße 5 € § 20°';
      final erwartet = [0x1c, 0x2e, 0x1b, 0x74, t.escT, ...encodeForCodeTable(text, t.id), 0x0a];
      expect(ende(textMit(t.id.name, text), erwartet.length), erwartet);
    });
  }

  test('PosStyles.defaults() (CP437) auf dem Weg KeckPrinter.printText und CustomPrintJob: CP437-Bytes', () async {
    // `PosStyles.defaults()` traegt `codeTable: 'CP437'`. Kein Weg des Pakets
    // (Beleg, Testdruck, Logo, QR) benutzt diesen Stil; betroffen sind nur
    // eigene Druckauftraege, die ihn selbst uebergeben: `EscPosGenerator.text`/
    // `row`, `KeckPrinter.printText`, `KeckPrinterService.printText`,
    // `CustomPrintJob.text`. Bis 10.0 kam dort Latin-1 unter `ESC t 0` an.
    // Bis 10.0: ... 1b 74 00 47 72 fc df 65 0a (Latin-1, am Drucker "Gr³▀e").
    final fake = _MitschnittTransport();
    await KeckPrinter(fake, size: KeckPaperSize.mm58).printText('Grüße', styles: const PosStyles.defaults());
    expect(ende(fake.bytes, 11), [0x1c, 0x2e, 0x1b, 0x74, 0, ...'Gr'.codeUnits, 0x81, 0xe1, 0x65, 0x0a]);
    final job = CustomPrintJob().text('Grüße', styles: const PosStyles.defaults());
    expect(ende(job.build(EscPosGenerator(EscPaperSize.mm58, CapabilityProfile())), 11), ende(fake.bytes, 11));
  });

  test('Spalten rechnen an den fertigen Bytes: € auf pc437 ist EUR, der Betrag bleibt rechtsbuendig', () {
    List<int> zeile(String betrag) {
      final gen = EscPosGenerator(EscPaperSize.mm58, CapabilityProfile())..setGlobalCodeTable('pc437');
      return gen.row([
        PosColumn(text: 'Kaffee', width: 8),
        PosColumn(text: betrag, width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    expect(zeile('2,50 €'), zeile('2,50 EUR'));
  });
}

class _MitschnittTransport implements PrinterTransport {
  List<int> bytes = [];
  @override
  Future<KeckPrintResult> send(List<int> b) async {
    bytes = List.of(b);
    return const KeckPrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

