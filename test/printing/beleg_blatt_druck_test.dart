import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

BelegLayout _fixture(String name) => BelegLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/erwartet/$name.lines.json').readAsStringSync()))!;

DruckLogo _probeLogo(int zeichen) {
  const logo = BlattLogo(stufe: LogoStufe.s, pxBreite: 40, pxHoehe: 20);
  final m = logoRasterMass(logoMass(logo, zeichen), zeichen);
  return DruckLogo(stufe: LogoStufe.s, pxBreite: 40, pxHoehe: 20,
      raster: LogoRaster(breite: m.breite, hoehe: m.hoehe, punkte: Uint8List(m.breite * m.hoehe)..fillRange(0, m.breite * m.hoehe, 1)));
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

  test('Testkasse: Rahmen, dann GS v 0, dann Firmenname; Marke am Ende', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setBelegBlatt(_fixture('testkasse-verkauf'), logo: _probeLogo(48), marke: true, cut: false, qrMode: QrPrintMode.native);
    final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
    final rahmenEnde = alles.indexOf('=' * 48, alles.indexOf('TESTKASSE'));
    final bild = alles.indexOf('\x1dv0');
    final firma = alles.indexOf('Muster');
    expect(rahmenEnde, greaterThan(0));
    expect(bild, greaterThan(rahmenEnde));
    expect(firma, greaterThan(bild));
    expect(alles.lastIndexOf('erstellt mit Kasseneck'), greaterThan(firma));
  });

  test('ohne Logo und Marke: kein Rasterbild, keine Markenzeile, jede Textzeile des Blatts im Bytestrom', () async {
    final layout = _fixture('storno-voll');
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    await paper.setBelegLayout(layout, qrMode: QrPrintMode.native, cut: false);
    final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
    expect(alles.contains('\x1dv0'), isFalse);
    expect(alles.contains('erstellt mit'), isFalse);
    // Woerter je Zeile in Reihenfolge: der Drucker rastert den druckbar gemachten
    // Text ("EUR" statt "€"), die Leerzeichen einer rechtsbuendigen Zeile
    // verschieben sich dabei -- die Woerter nicht.
    var ab = 0;
    for (final z in belegBlatt(layout, zeichen: 32).bloecke.whereType<BlattZeile>()) {
      if (z.leer) continue;
      final woerter = z.text.replaceAll('€', 'EUR').replaceAll('—', '-').replaceAll('–', '-').trim().split(RegExp(r' +'));
      final muster = RegExp(woerter.map(RegExp.escape).join(' +'));
      final treffer = muster.allMatches(alles, ab).firstOrNull;
      expect(treffer, isNotNull, reason: 'Zeile fehlt oder steht in falscher Reihenfolge: "${z.text.trim()}"');
      ab = treffer!.end;
    }
  });

  test('Logo-Raster in falscher Groesse wird abgewiesen', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    final falsch = DruckLogo(stufe: LogoStufe.s, pxBreite: 40, pxHoehe: 20, raster: LogoRaster(breite: 3, hoehe: 3, punkte: Uint8List(9)));
    expect(() => paper.setBelegBlatt(_fixture('verkauf-bar'), logo: falsch), throwsArgumentError);
  });

  test('Logo-Raster in falscher Groesse: kein Byte des vorigen Belegs wird angetastet', () async {
    // Die Pruefung laeuft vor reset() -- ein abgewiesenes Logo laesst das
    // Papier so stehen, wie es war, statt einen halben Beleg zu hinterlassen.
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setBelegBlatt(_fixture('verkauf-bar'), cut: false, qrMode: QrPrintMode.native);
    final vorher = paper.bytes.expand((b) => b).toList();
    final falsch = DruckLogo(stufe: LogoStufe.s, pxBreite: 40, pxHoehe: 20, raster: LogoRaster(breite: 3, hoehe: 3, punkte: Uint8List(9)));
    await expectLater(paper.setBelegBlatt(_fixture('verkauf-bar'), logo: falsch), throwsArgumentError);
    expect(paper.bytes.expand((b) => b).toList(), vorher);
  });

  test('QR als Bild: Breite in Druckpunkten wie das Blatt (npm-Mass), nicht fest 280', () async {
    final layout = _fixture('verkauf-bar');
    final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await paper.setBelegBlatt(layout, cut: false, qrMode: QrPrintMode.imageRaster);
    final alles = paper.bytes.expand((b) => b).toList();
    final i = List.generate(alles.length - 3, (k) => k).firstWhere((k) => alles[k] == 0x1d && alles[k + 1] == 0x76 && alles[k + 2] == 0x30);
    final breiteBytes = alles[i + 4] + (alles[i + 5] << 8);
    final qr = belegBlatt(layout, zeichen: 48).bloecke.whereType<BlattQr>().single;
    expect(breiteBytes, ((qr.breiteAnteil * 576).round() + 7) ~/ 8);
  });

  test('nativer QR druckt mit Fehlerkorrektur M (GS ( k ... 31 45 49), wie Blatt, ePOS und Bildweg', () async {
    final h = '\x1D(k'.codeUnits;
    final korrekturM = [...h, 0x03, 0x00, 0x31, 0x45, 49];
    final korrekturL = [...h, 0x03, 0x00, 0x31, 0x45, 48];

    final blatt = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
    await blatt.setBelegBlatt(_fixture('verkauf-bar'), cut: false, qrMode: QrPrintMode.native);
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
      final layout = BelegLayout(paperSize: 'mm80', regelwerk: 2, lines: [
        BelegText(text: 'Firma', align: BelegAlign.center, bold: true),
        BelegQr(data: 'x' * 2332),
      ]);
      await paper.setBelegBlatt(layout, cut: false, qrMode: modus);
      expect(paper.qrFehler, contains('keine QR-Version'));
      final alles = latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
      expect(alles, contains('Firma'));
    });
  }
}
