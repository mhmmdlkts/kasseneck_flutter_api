import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

import '../helpers/test_receipts.dart';

/// Der native QR-Weg mit gerechneter Modulgroesse.
///
/// Reale RKSV-Nutzlast, 57 Module, Ruhezone: mit den bisherigen sechs Punkten
/// je Modul 390 Druckpunkte breit — auf einem 58-mm-Drucker (384) druckte das
/// Geraet **gar nichts**. Genau dieser Fall ist hier festgenagelt.

/// Ein Beleg-QR in der Groessenordnung, die im Betrieb wirklich vorkommt.
const String echterQr =
    '_R1-AT1_Demo-Kassa-01_AT0_2026-09-11T12:34:56_10,00_0,00_0,00_0,00_0,00_'
    'qVTG5xZ8kQA=_a1b2c3d4_wO4NfGk2pLQ=_hIRFbbuAUUk9j7t0lwdZQtVUqbLfOyvF6Qr8zZ3+'
    'kTs5bwWJmn0PxYuAeD2cRiVgKlNpHXtMEoS4UvCa7dIB==';

PrintPaper papier([KeckPaperSize size = KeckPaperSize.mm58]) =>
    PrintPaper(paperSize: size, profile: CapabilityProfile());

List<int> flach(PrintPaper p) => p.bytes.expand((e) => e).toList();

/// Das Argument des Befehls "Modulgroesse" (`GS ( k … 31 43 n`).
int? modulgroesseByte(PrintPaper p) {
  final List<int> b = flach(p);
  for (int i = 0; i + 1 < b.length; i++) {
    if (b[i] == 0x31 && b[i + 1] == 0x43) return b[i + 2];
  }
  return null;
}

bool enthaelt(List<int> heu, List<int> nadel) {
  for (int i = 0; i + nadel.length <= heu.length; i++) {
    bool treffer = true;
    for (int j = 0; j < nadel.length; j++) {
      if (heu[i + j] != nadel[j]) {
        treffer = false;
        break;
      }
    }
    if (treffer) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gerechnete Modulgroesse am nativen Befehl', () {
    test('kurze Nutzlast bleibt bei 6 — der Bestand aendert sich nicht', () {
      final PrintPaper p = papier();
      p.addQrCode('TESTQRDATA');
      expect(modulgroesseByte(p), 6);
      expect(p.qrFehler, isNull);
      expect(p.qrAusweich, isNull);
    });

    test('realer Beleg-QR auf 58 mm: 5 statt 6 — und damit ueberhaupt ein QR', () {
      final PrintPaper p = papier();
      p.addQrCode(echterQr);
      expect(modulgroesseByte(p), 5);
      expect(p.qrFehler, isNull);
      expect(p.qrAusweich, isNull);
    });

    test('derselbe QR auf 80 mm bleibt bei 6', () {
      final PrintPaper p = papier(KeckPaperSize.mm80);
      p.addQrCode(echterQr);
      expect(modulgroesseByte(p), 6);
    });

    test('ausdruecklich gewaehlte Groesse deckelt, hebt aber nicht an', () {
      final PrintPaper klein = papier();
      klein.addQrCode('TESTQRDATA', groesse: QrModulGroesse.klein);
      expect(modulgroesseByte(klein), 4);

      final PrintPaper gross = papier();
      gross.addQrCode('TESTQRDATA', groesse: QrModulGroesse.gross);
      expect(modulgroesseByte(gross), 8);

      // Auf 58 mm passt der echte QR auch mit `gross` nur mit 5.
      final PrintPaper eng = papier();
      eng.addQrCode(echterQr, groesse: QrModulGroesse.gross);
      expect(modulgroesseByte(eng), 5);
    });

    test('eine fest uebergebene QRSize wird nicht angetastet', () {
      // Der Weg fuer Aufrufer, die genau wissen, was sie tun — er darf nicht
      // heimlich nachrechnen, sonst waere er wertlos.
      final PrintPaper p = papier();
      p.addQrCode(echterQr, size: QRSize.size6);
      expect(modulgroesseByte(p), 6);
    });

    test('unter der Mindestgroesse wird gedruckt und gemeldet', () {
      final PrintPaper p = papier();
      p.addQrCode('X' * 600); // 93 Module -> 3 Punkte
      expect(modulgroesseByte(p), 3);
      expect(p.qrFehler, isNull);
      expect(p.qrAusweich, isNotNull);
      expect(p.qrAusweich, contains('3'));
    });

    test('nativ unmoeglich: kein stiller Ausfall, sondern ein gemeldeter', () {
      // Direkt gerufen kann dieser Weg kein Bild drucken (synchron) — er sagt
      // es und legt die Belegdaten in Klarschrift aufs Papier.
      final PrintPaper p = papier();
      p.addQrCode('X' * 1000); // 121 Module -> passt auch mit 3 nicht
      expect(modulgroesseByte(p), isNull);
      expect(p.qrFehler, isNotNull);
    });
  });

  group('Notausgang am Beleg', () {
    test('zu breites Symbol wird als Bild gedruckt statt gar nicht', () async {
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(qr: 'X' * 1000), qrMode: QrPrintMode.native);
      // GS v 0 — der Rasterbild-Befehl. Kein GS ( k.
      expect(enthaelt(flach(p), [0x1D, 0x76, 0x30]), isTrue);
      expect(enthaelt(flach(p), [0x1D, 0x28, 0x6B]), isFalse);
      expect(p.qrAusweich, isNotNull, reason: 'die Kasse muss den Wechsel erfahren');
      expect(p.qrFehler, isNull, reason: 'der QR steht ja auf dem Papier');
    });

    test('passt es nativ, wird nicht ausgewichen', () async {
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(qr: echterQr), qrMode: QrPrintMode.native);
      expect(enthaelt(flach(p), [0x1D, 0x28, 0x6B]), isTrue);
      expect(p.qrAusweich, isNull);
      expect(p.qrFehler, isNull);
    });

    test('reset raeumt den Ausweich-Hinweis mit ab', () async {
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(qr: 'X' * 1000), qrMode: QrPrintMode.native);
      expect(p.qrAusweich, isNotNull);
      await p.setKeckReceipt(buildReceipt(), qrMode: QrPrintMode.native);
      expect(p.qrAusweich, isNull, reason: 'sonst klebt der Hinweis am naechsten Beleg');
    });
  });

  group('Modell 1', () {
    test('nativeModel1 stellt den Modellbefehl voran', () async {
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(), qrMode: QrPrintMode.nativeModel1);
      // GS ( k 04 00 31 41 49 00 — Funktion 165, Modell 1.
      expect(enthaelt(flach(p), [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x31, 0x00]), isTrue);
    });

    test('der bisherige native Weg schickt weiterhin gar keinen Modellbefehl', () async {
      // Haette `native` ploetzlich Modell 2 gewaehlt, waere das eine stille
      // Umstellung an jedem Bestandsgeraet.
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(), qrMode: QrPrintMode.native);
      expect(enthaelt(flach(p), [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41]), isFalse);
    });

    test('Modell 1 nimmt dieselbe gerechnete Modulgroesse', () {
      final PrintPaper p = papier();
      p.addQrCode(echterQr, modell1: true);
      expect(modulgroesseByte(p), 5);
    });
  });

  group('Durchreichen bis zum Aufrufer', () {
    test('die gewaehlte Groesse kommt am QR an', () async {
      final PrintPaper p = papier();
      await p.setKeckReceipt(buildReceipt(),
          qrMode: QrPrintMode.native, qrGroesse: QrModulGroesse.klein);
      expect(modulgroesseByte(p), 4);
    });
  });
}
