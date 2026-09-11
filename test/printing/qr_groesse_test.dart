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
      final QrGroesse g = QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 21);
      expect(g.passt, isTrue);
      expect(g.punkte, 6, reason: 'auto deckelt auf den Bestandswert 6');
      expect(g.module, 21);
      expect(g.breitePunkte, 29 * 6);
      expect(g.unterMindestmass, isFalse);
    });

    test('der Deckel hebt nie an, was nicht passt', () {
      // 57 Module -> 65; 384 / 65 = 5. `gross` will 8 und bekommt trotzdem 5.
      for (final QrModulGroesse w in QrModulGroesse.values) {
        final QrGroesse g =
            QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 57, groesse: w);
        expect(g.punkte, w == QrModulGroesse.klein ? 4 : 5, reason: w.name);
      }
    });

    test('80 mm: gerechnet waeren 8, `auto` bleibt bei 6', () {
      // Hier haengt die Byteidentitaet des Bestands: ohne Deckel druckte jedes
      // 80-mm-Geraet ab sofort einen groesseren QR als gestern.
      expect(QrMass.berechne(papierbreitePunkte: 576, moduleAnzahl: 57).punkte, 6);
      expect(
          QrMass.berechne(
                  papierbreitePunkte: 576,
                  moduleAnzahl: 57,
                  groesse: QrModulGroesse.gross)
              .punkte,
          8);
    });

    test('genau an der Mindestgroesse: 4 Punkte, ohne Ausnahmemeldung', () {
      // 77 Module -> 85; 384 / 85 = 4.
      final QrGroesse g = QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 77);
      expect(g.punkte, 4);
      expect(g.unterMindestmass, isFalse);
    });

    test('unter der Mindestgroesse: 3 Punkte, und der Aufrufer erfaehrt es', () {
      // 93 Module -> 101; 384 / 101 = 3. Erlaubt, aber keine stille Notloesung.
      final QrGroesse g = QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 93);
      expect(g.punkte, 3);
      expect(g.unterMindestmass, isTrue);
      expect(g.passt, isTrue);
    });

    test('auch mit 3 zu breit: es passt nicht, und das steht im Ergebnis', () {
      // 121 Module -> 129; 384 / 129 = 2.
      final QrGroesse g = QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 121);
      expect(g.passt, isFalse);
      expect(g.punkte, isNull);
      expect(g.breitePunkte, 0);
    });

    test('sinnlose Eingaben werfen, statt still 0 zu liefern', () {
      expect(() => QrMass.berechne(papierbreitePunkte: 0, moduleAnzahl: 21),
          throwsArgumentError);
      expect(() => QrMass.berechne(papierbreitePunkte: 384, moduleAnzahl: 0),
          throwsArgumentError);
    });
  });

  group('QrMass.modulAnzahl', () {
    test('rechnet mit Fehlerkorrektur M, nicht mit einer Tabelle im Kopf', () {
      expect(QrMass.modulAnzahl('TESTQRDATA'), 21);
      expect(QrMass.modulAnzahl('X' * 400), 77);
      expect(QrMass.modulAnzahl('X' * 1000), 121);
    });

    test('M liegt nie unter L -- die Rechnung ist konservativ', () {
      // Der native Befehl druckt mit L. Wer mit M rechnet, rechnet also nie zu
      // knapp. Waere es umgekehrt, passte das Symbol rechnerisch und auf dem
      // Papier nicht.
      expect(QrMass.modulAnzahl('X' * 300), greaterThanOrEqualTo(61));
    });
  });

  group('QrMass.fuer', () {
    test('realer Beleg-QR auf 58 mm: 5 Punkte statt gar kein QR', () {
      const String qr =
          '_R1-AT1_Demo-Kassa-01_AT0_2026-09-11T12:34:56_10,00_0,00_0,00_0,00_0,00_'
          'qVTG5xZ8kQA=_a1b2c3d4_wO4NfGk2pLQ=_hIRFbbuAUUk9j7t0lwdZQtVUqbLfOyvF6Qr8zZ3+'
          'kTs5bwWJmn0PxYuAeD2cRiVgKlNpHXtMEoS4UvCa7dIB==';
      final QrGroesse g =
          QrMass.fuer(nutzlast: qr, papierbreitePunkte: KeckPaperSize.mm58.druckPunkte);
      expect(g.module, 57);
      expect(g.punkte, 5);
      expect(g.breitePunkte, 325);
      expect(g.breitePunkte, lessThanOrEqualTo(384));
      // Mit der alten festen Groesse waere es 390 gewesen -- zu breit.
      expect(65 * 6, greaterThan(KeckPaperSize.mm58.druckPunkte));
    });

    test('leere Nutzlast wirft nicht, sondern passt nicht', () {
      expect(QrMass.fuer(nutzlast: '', papierbreitePunkte: 384).passt, isFalse);
    });
  });

  test('Papierbreiten stehen in Druckpunkten am Format', () {
    expect(KeckPaperSize.mm58.druckPunkte, 384);
    expect(KeckPaperSize.mm80.druckPunkte, 576);
  });
}
