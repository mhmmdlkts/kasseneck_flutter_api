import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

import '../helpers/test_receipts.dart';

/// Der Beleg-QR ist gesetzlich gefordert (RKSV). Er darf weder den Druck
/// abbrechen noch lautlos verschwinden — und sein Inhalt darf nicht
/// „entschaerft" werden: ein ersetztes Zeichen ergaebe einen sauber lesbaren
/// QR, der nicht mehr zum signierten Beleg passt.

PrintPaper papier([KeckPaperSize size = KeckPaperSize.mm58]) =>
    PrintPaper(paperSize: size, profile: CapabilityProfile());

List<int> flach(PrintPaper p) => p.bytes.expand((e) => e).toList();

List<String> texte(PrintPaper p) => p.myPosPaper.commands
    .where((c) => c['type'] == 'text')
    .map((c) => c['value'] as String)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native QR-Modus erzeugt Modulgroesse-Byte', () {
    final paper = papier();
    paper.addQrCode('TESTTOKEN'); // native
    expect(flach(paper).join(','), contains([0x31, 0x43].join(','))); // FN167 QR-Modulgroesse
    expect(paper.qrFehler, isNull);
  });

  test('Zeichen ueber 0xFF reissen den Druck nicht mehr ab', () {
    // latin1.encode warf hier "Contains invalid characters" — ungefangen, im
    // nativen Modus, den der MyPos-Terminaldruck fest erzwingt.
    const daten = '_R1-AT0_Kaffeehaus-Wien_€漢';
    final paper = papier();
    paper.addQrCode(daten);

    expect(paper.qrFehler, isNull);
    // Die Nutzlast steht unveraendert als UTF-8 im Bytestrom — nicht als '?'.
    expect(flach(paper), containsAllInOrder(utf8.encode(daten)));
    expect(paper.myPosPaper.commands.firstWhere((c) => c['type'] == 'qrCode')['value'], daten);
  });

  test('reines ASCII bleibt byteweise, wie es war (Latin-1 == UTF-8)', () {
    final qr = QRCode('ABC', QRSize.size6, QRCorrection.L);
    final h = '\x1D(k'.codeUnits;
    expect(qr.bytes, [
      ...h, 0x03, 0x00, 0x31, 0x43, 0x06,
      ...h, 0x03, 0x00, 0x31, 0x45, 48,
      ...h, 3 + 3, 0x00, 0x31, 0x50, 0x30, ...latin1.encode('ABC'),
      ...h, 0x03, 0x00, 0x31, 0x52, 0x30,
      ...h, 0x03, 0x00, 0x31, 0x51, 0x30,
    ]);
  });

  test('Nutzlast ueber 252 Byte: das Laengenfeld laeuft nicht mehr ueber', () {
    // pH stand fest auf 0x00; bei 300 Byte Nutzlast war pL = (300+3) % 256
    // = 47, der Drucker las also 44 Byte Daten statt 300.
    final qr = QRCode('A' * 300, QRSize.size6, QRCorrection.L);
    final start = _indexVon(qr.bytes, '\x1D(k'.codeUnits + [0x2F, 0x01]);
    expect(start, isNonNegative, reason: 'Speicher-Befehl mit pL=0x2F, pH=0x01 nicht gefunden');
    expect(qr.bytes[start + 3], 0x2F); // pL
    expect(qr.bytes[start + 4], 0x01); // pH — war vorher fest 0x00
    expect(qr.bytes[start + 3] + qr.bytes[start + 4] * 256, 303);
  });

  test('unmoegliche Nutzlast wirft im Generator, nicht erst am Drucker', () {
    expect(() => QRCode('A' * (QRCode.maxNutzlast + 1), QRSize.size6, QRCorrection.L),
        throwsArgumentError);
  });

  group('Ausfall wird sichtbar statt lautlos', () {
    test('leere Nutzlast (nativ): Aufdruck statt eines QR ohne Inhalt', () {
      final paper = papier();
      paper.addQrCode('');

      expect(paper.qrFehler, isNotNull);
      expect(texte(paper), contains('!! QR-CODE FEHLT !!'));
      expect(paper.myPosPaper.commands.map((c) => c['type']), isNot(contains('qrCode')));
    });

    test('QR-Bild nicht erzeugbar: Aufdruck und Belegdaten in Klarschrift', () async {
      // Mehr, als in einen QR-Code passt (Version 40) -> das qr-Paket wirft.
      // Frueher endete das in einem kDebugMode-print: im Release entstand ein
      // Pflichtbeleg ohne QR, ohne jedes Signal.
      final daten = 'X' * 3000;
      final paper = papier();
      await paper.addQrCodeAsImage(daten);

      expect(paper.qrFehler, isNotNull);
      final t = texte(paper);
      expect(t, contains('!! QR-CODE FEHLT !!'));
      // Die Belegdaten stehen trotzdem auf dem Papier, auf 32 Zeichen
      // umbrochen und vollstaendig.
      final daten1 = t.where((z) => z.startsWith('XXXX')).toList();
      expect(daten1.join().length, 3000);
      expect(daten1.map((z) => z.length).reduce((a, b) => a > b ? a : b), 32);
      expect(paper.myPosPaper.commands.map((c) => c['type']), isNot(contains('image')));
    });

    test('ein gelungener QR setzt keinen Fehler', () async {
      final paper = papier();
      await paper.addQrCodeAsImage('_R1-AT0_kurz');
      expect(paper.qrFehler, isNull);
      expect(paper.myPosPaper.commands.map((c) => c['type']), contains('image'));
      expect(texte(paper), isNot(contains('!! QR-CODE FEHLT !!')));
    });

    test('setKeckReceipt: qrFehler bleibt leer, wenn der QR steht', () async {
      final paper = papier();
      await paper.setKeckReceipt(cartA(), qrMode: QrPrintMode.native);
      expect(paper.qrFehler, isNull);
      expect(texte(paper), isNot(contains('!! QR-CODE FEHLT !!')));
    });

    test('reset raeumt den Fehler weg', () {
      final paper = papier();
      paper.addQrCode('');
      expect(paper.qrFehler, isNotNull);
      paper.reset();
      expect(paper.qrFehler, isNull);
    });
  });
}

int _indexVon(List<int> haystack, List<int> needle) {
  for (int i = 0; i + needle.length <= haystack.length; i++) {
    var treffer = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        treffer = false;
        break;
      }
    }
    if (treffer) return i;
  }
  return -1;
}
