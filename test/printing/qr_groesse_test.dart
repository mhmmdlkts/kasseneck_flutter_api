import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

/// Die Rechenregel fuer die Modulgroesse des Beleg-QR.
///
/// Sie ist der Grund, aus dem auf 58 mm ueberhaupt wieder ein QR erscheint:
/// fest sechs Punkte je Modul ergaben bei realer RKSV-Nutzlast 390 Punkte
/// Breite auf einem 384 Punkte breiten Drucker -- und ein zu breites Symbol
/// druckt kein Geraet, es druckt gar nichts.
void main() {
  group('QrMass.berechne', () {
    test('Normalfall: groesste passende Groesse, gedeckelt', () {
      // 21 Module + 8 Ruhezone = 29; 384 / 29 = 13 -> der Deckel entscheidet.
      final QrSizing g = QrMetrics.compute(paperWidthDots: 384, moduleCount: 21);
      expect(g.fits, isTrue);
      expect(g.moduleDots, 6, reason: 'auto deckelt auf den Bestandswert 6');
      expect(g.module, 21);
      expect(g.widthDots, 29 * 6);
      expect(g.belowMinimum, isFalse);
    });

    test('der Deckel hebt nie an, was nicht passt', () {
      // 57 Module -> 65; 384 / 65 = 5. `gross` will 8 und bekommt trotzdem 5.
      for (final QrModuleSize w in QrModuleSize.values) {
        final QrSizing g =
            QrMetrics.compute(paperWidthDots: 384, moduleCount: 57, moduleSize: w);
        expect(g.moduleDots, w == QrModuleSize.small ? 4 : 5, reason: w.name);
      }
    });

    test('80 mm: gerechnet waeren 8, `auto` bleibt bei 6', () {
      // Hier haengt die Byteidentitaet des Bestands: ohne Deckel druckte jedes
      // 80-mm-Geraet ab sofort einen groesseren QR als gestern.
      expect(QrMetrics.compute(paperWidthDots: 576, moduleCount: 57).moduleDots, 6);
      expect(
          QrMetrics.compute(
                  paperWidthDots: 576,
                  moduleCount: 57,
                  moduleSize: QrModuleSize.large)
              .moduleDots,
          8);
    });

    test('genau an der Mindestgroesse: 4 Punkte, ohne Ausnahmemeldung', () {
      // 77 Module -> 85; 384 / 85 = 4.
      final QrSizing g = QrMetrics.compute(paperWidthDots: 384, moduleCount: 77);
      expect(g.moduleDots, 4);
      expect(g.belowMinimum, isFalse);
    });

    test('unter der Mindestgroesse: 3 Punkte, und der Aufrufer erfaehrt es', () {
      // 93 Module -> 101; 384 / 101 = 3. Erlaubt, aber keine stille Notloesung.
      final QrSizing g = QrMetrics.compute(paperWidthDots: 384, moduleCount: 93);
      expect(g.moduleDots, 3);
      expect(g.belowMinimum, isTrue);
      expect(g.fits, isTrue);
    });

    test('auch mit 3 zu breit: es passt nicht, und das steht im Ergebnis', () {
      // 121 Module -> 129; 384 / 129 = 2.
      final QrSizing g = QrMetrics.compute(paperWidthDots: 384, moduleCount: 121);
      expect(g.fits, isFalse);
      expect(g.moduleDots, isNull);
      expect(g.widthDots, 0);
    });

    test('sinnlose Eingaben werfen, statt still 0 zu liefern', () {
      expect(() => QrMetrics.compute(paperWidthDots: 0, moduleCount: 21),
          throwsArgumentError);
      expect(() => QrMetrics.compute(paperWidthDots: 384, moduleCount: 0),
          throwsArgumentError);
    });
  });

  group('QrMass.modulAnzahl', () {
    test('rechnet mit Fehlerkorrektur M, nicht mit einer Tabelle im Kopf', () {
      expect(QrMetrics.moduleCount('TESTQRDATA'), 21);
      expect(QrMetrics.moduleCount('X' * 400), 77);
      expect(QrMetrics.moduleCount('X' * 1000), 121);
    });

    test('M liegt nie unter L -- die Rechnung ist konservativ', () {
      // Der native Befehl druckt mit L. Wer mit M rechnet, rechnet also nie zu
      // knapp. Waere es umgekehrt, passte das Symbol rechnerisch und auf dem
      // Papier nicht.
      expect(QrMetrics.moduleCount('X' * 300), greaterThanOrEqualTo(61));
    });
  });

  group('QrMass.fuer', () {
    test('realer Beleg-QR auf 58 mm: 5 Punkte statt gar kein QR', () {
      const String qr =
          '_R1-AT1_Demo-Kassa-01_AT0_2026-09-11T12:34:56_10,00_0,00_0,00_0,00_0,00_'
          'qVTG5xZ8kQA=_a1b2c3d4_wO4NfGk2pLQ=_hIRFbbuAUUk9j7t0lwdZQtVUqbLfOyvF6Qr8zZ3+'
          'kTs5bwWJmn0PxYuAeD2cRiVgKlNpHXtMEoS4UvCa7dIB==';
      final QrSizing g =
          QrMetrics.forPayload(payload: qr, paperWidthDots: KeckPaperSize.mm58.printWidthDots);
      expect(g.module, 57);
      expect(g.moduleDots, 5);
      expect(g.widthDots, 325);
      expect(g.widthDots, lessThanOrEqualTo(384));
      // Mit der alten festen Groesse waere es 390 gewesen -- zu breit.
      expect(65 * 6, greaterThan(KeckPaperSize.mm58.printWidthDots));
    });

    test('leere Nutzlast wirft nicht, sondern passt nicht', () {
      expect(QrMetrics.forPayload(payload: '', paperWidthDots: 384).fits, isFalse);
    });
  });

  test('Papierbreiten stehen in Druckpunkten am Format', () {
    expect(KeckPaperSize.mm58.printWidthDots, 384);
    expect(KeckPaperSize.mm80.printWidthDots, 576);
  });
}
