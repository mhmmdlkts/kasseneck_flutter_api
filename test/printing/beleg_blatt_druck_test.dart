import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

ReceiptLayout _fixture(String name) => ReceiptLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/expected/$name.lines.json').readAsStringSync()))!;

PrintLogo _probeLogo(int zeichen) {
  const logo = SheetLogo(size: SheetLogoSize.s, pixelWidth: 40, pixelHeight: 20);
  final m = logoRasterSize(logoDimensions(logo, zeichen), zeichen);
  return PrintLogo(size: SheetLogoSize.s, pixelWidth: 40, pixelHeight: 20,
      raster: LogoRaster(width: m.width, height: m.height, dots: Uint8List(m.width * m.height)..fillRange(0, m.width * m.height, 1)));
}

int _indexVon(List<int> heu, List<int> nadel) {
  for (var i = 0; i + nadel.length <= heu.length; i++) {
    var gleich = true;
    for (var k = 0; k < nadel.length; k++) {
      if (heu[i + k] != nadel[k]) {
        gleich = false;
        break;
      }
    }
    if (gleich) return i;
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Testkasse: Rahmen, dann GS v 0, dann Firmenname; Marke als Rasterbild am Ende', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setReceiptSheet(_fixture('test-cashregister-sale'), logo: _probeLogo(48), brandMark: true, cut: false, qrMode: QrPrintMode.native);
    final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
    final rahmenEnde = alles.indexOf('=' * 48, alles.indexOf('TESTKASSE'));
    final bild = alles.indexOf('\x1dv0');
    final firma = alles.indexOf('Muster');
    // Die Marke ist ihr eigenes Rasterbild ganz am Ende -- das letzte GS v 0
    // im Strom, nach dem Firmennamen und keine Textzeile mehr.
    final marke = alles.lastIndexOf('\x1dv0');
    expect(rahmenEnde, greaterThan(0));
    expect(bild, greaterThan(rahmenEnde));
    expect(firma, greaterThan(bild));
    expect(marke, greaterThan(firma));
    expect(marke, isNot(bild), reason: 'Logo und Marke sind zwei verschiedene Rasterbilder');
    expect(alles.contains('erstellt mit Kasseneck'), isFalse);
  });

  test('ohne Logo und Marke: kein Rasterbild, keine Markenzeile, jede Textzeile des Blatts im Bytestrom', () async {
    final layout = _fixture('cancellation-full');
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    await paper.setReceiptLayout(layout, qrMode: QrPrintMode.native, cut: false);
    final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
    expect(alles.contains('\x1dv0'), isFalse);
    expect(alles.contains('erstellt mit'), isFalse);
    // Woerter je Zeile in Reihenfolge: der Drucker rastert den druckbar gemachten
    // Text ("EUR" statt "€"), die Leerzeichen einer rechtsbuendigen Zeile
    // verschieben sich dabei -- die Woerter nicht.
    var ab = 0;
    for (final z in receiptSheet(layout, charsPerLine: 32).blocks.whereType<SheetLine>()) {
      if (z.blank) continue;
      final woerter = z.text.replaceAll('€', 'EUR').replaceAll('—', '-').replaceAll('–', '-').trim().split(RegExp(r' +'));
      final muster = RegExp(woerter.map(RegExp.escape).join(' +'));
      final treffer = muster.allMatches(alles, ab).firstOrNull;
      expect(treffer, isNotNull, reason: 'Zeile fehlt oder steht in falscher Reihenfolge: "${z.text.trim()}"');
      ab = treffer!.end;
    }
  });

  test('Logo-Raster in falscher Groesse wird abgewiesen', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    final falsch = PrintLogo(size: SheetLogoSize.s, pixelWidth: 40, pixelHeight: 20, raster: LogoRaster(width: 3, height: 3, dots: Uint8List(9)));
    expect(() => paper.setReceiptSheet(_fixture('sale-cash'), logo: falsch), throwsArgumentError);
  });

  test('Logo-Raster in falscher Groesse: kein Byte des vorigen Belegs wird angetastet', () async {
    // Die Pruefung laeuft vor reset() -- ein abgewiesenes Logo laesst das
    // Papier so stehen, wie es war, statt einen halben Beleg zu hinterlassen.
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setReceiptSheet(_fixture('sale-cash'), cut: false, qrMode: QrPrintMode.native);
    final vorher = paper.bytes.expand((b) => b).toList();
    final falsch = PrintLogo(size: SheetLogoSize.s, pixelWidth: 40, pixelHeight: 20, raster: LogoRaster(width: 3, height: 3, dots: Uint8List(9)));
    await expectLater(paper.setReceiptSheet(_fixture('sale-cash'), logo: falsch), throwsArgumentError);
    expect(paper.bytes.expand((b) => b).toList(), vorher);
  });

  test('QR als Bild: Breite in Druckpunkten wie das Blatt (npm-Mass), nicht fest 280', () async {
    final layout = _fixture('sale-cash');
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setReceiptSheet(layout, cut: false, qrMode: QrPrintMode.imageRaster);
    final alles = paper.bytes.expand((b) => b).toList();
    final i = List.generate(alles.length - 3, (k) => k).firstWhere((k) => alles[k] == 0x1d && alles[k + 1] == 0x76 && alles[k + 2] == 0x30);
    final breiteBytes = alles[i + 4] + (alles[i + 5] << 8);
    final qr = receiptSheet(layout, charsPerLine: 48).blocks.whereType<SheetQr>().single;
    expect(breiteBytes, ((qr.widthFraction * 576).round() + 7) ~/ 8);
  });

  test('nativer QR druckt mit Fehlerkorrektur M (GS ( k ... 31 45 49), wie Blatt, ePOS und Bildweg', () async {
    final h = '\x1D(k'.codeUnits;
    final korrekturM = [...h, 0x03, 0x00, 0x31, 0x45, 49];
    final korrekturL = [...h, 0x03, 0x00, 0x31, 0x45, 48];

    final blatt = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await blatt.setReceiptSheet(_fixture('sale-cash'), cut: false, qrMode: QrPrintMode.native);
    final blattBytes = blatt.bytes.expand((b) => b).toList();
    expect(_indexVon(blattBytes, korrekturM), isNonNegative);
    expect(_indexVon(blattBytes, korrekturL), -1);

    final direkt = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    direkt.addQrCode('TESTTOKEN');
    expect(_indexVon(direkt.bytes.expand((b) => b).toList(), korrekturM), isNonNegative);
  });

  for (final modus in QrPrintMode.values) {
    test('setBelegBlatt $modus: QR-Inhalt ohne passende Version -- kein Absturz, qrFehler gesetzt', () async {
      final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
      final layout = ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: [
        LayoutTextLine(text: 'Firma', align: LayoutAlign.center, bold: true),
        LayoutQrLine(data: 'x' * 2332),
      ]);
      await paper.setReceiptSheet(layout, cut: false, qrMode: modus);
      expect(paper.qrError, contains('keine QR-Version'));
      final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
      expect(alles, contains('Firma'));
    });
  }

  test('der Druckbereich folgt dem Blatt, nicht dem Geraet', () async {
    // Der Fund am Papier (21.09.): ein 58-mm-Blatt auf einem 80-mm-Drucker
    // setzte den Text in die linken 384 Punkte, QR und Logo aber mittig in die
    // 576 des Geraets -- alles Bildhafte stand gegenueber dem Text nach rechts
    // gerueckt. Der Drucker kann es nicht besser wissen, solange ihm niemand
    // sagt, welche Flaeche gemeint ist. Genau das sagt `GS W` jetzt, in der
    // Breite des Blatts: Zeichen je Zeile mal 12 Punkte.
    for (final (size, zeichen) in [(KeckPaperSize.mm58, 32), (KeckPaperSize.mm80, 48)]) {
      final paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
      await paper.setReceiptSheet(_fixture('cancellation-full'), cut: false, qrMode: QrPrintMode.native);
      final alle = paper.bytes.expand((b) => b).toList();
      final punkte = zeichen * 12;
      expect(alle.take(10).toList(), [0x1B, 0x40, 0x1D, 0x4C, 0, 0, 0x1D, 0x57, punkte & 0xff, punkte >> 8],
          reason: '${size.name}: Druckbereich muss $punkte Punkte breit sein');
    }
  });

  test('setBelegBlatt setzt die Codepage im Vorspann nur einmal, nicht doppelt', () async {
    // reset() laeuft zweimal auf demselben Erzeuger: einmal im
    // PrintPaper-Konstruktor, einmal hier in setBelegBlatt. `generator.reset()`
    // schickt die zuletzt hinterlegte Codepage jedes Mal von selbst erneut mit
    // (ueber das generatorinterne `_codeTable`-Feld) -- ein zusaetzlicher,
    // expliziter `setGlobalCodeTable`-Aufruf in `PrintPaper.reset()` verdoppelte
    // sie darum bei jedem Reset nach dem allerersten: `ESC @` gefolgt von
    // ZWEI unmittelbar aufeinanderfolgenden `ESC t 16` statt einem einzigen.
    // (Jede spaetere Zeile schickt die Codepage ohnehin bewusst jedes Mal neu
    // mit, siehe `setStyles` -- das ist kein Fehler und bleibt unangetastet;
    // hier geht es allein um den doppelten Vorspann.) Letzter Byte-
    // Unterschied zum JS-Zwilling, der die Codepage im Vorspann nur einmal
    // setzt.
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    await paper.setReceiptSheet(_fixture('cancellation-full'), cut: false, qrMode: QrPrintMode.native);
    final alle = paper.bytes.expand((b) => b).toList();
    const codepage = [0x1B, 0x74, 16]; // ESC t 16 = CP1252
    // Zwischen ESC @ und der Codepage steht der Druckbereich des Blatts
    // (GS L 0 / GS W 384 bei 32 Zeichen) -- er beschreibt die Flaeche, in der
    // der Drucker mitteln soll, und gehoert wie ESC @ in den Vorspann.
    const bereich = [0x1D, 0x4C, 0, 0, 0x1D, 0x57, 0x80, 0x01];
    final vorspann = [0x1B, 0x40, ...bereich, ...codepage]; // genau EIN ESC t 16
    final verdoppelt = [0x1B, 0x40, ...bereich, ...codepage, ...codepage]; // ZWEIMAL
    expect(_indexVon(alle, verdoppelt), -1,
        reason: 'die Codepage steht im Vorspann doppelt');
    expect(_indexVon(alle, vorspann), 0,
        reason: 'der Vorspann muss mit ESC @ + genau einem ESC t 16 beginnen');
  });
}
