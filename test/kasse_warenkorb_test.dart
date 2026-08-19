import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Der laufende Verkauf: erfassen, ändern, zusammenzählen — und der Rabatt als
/// negative Position je Steuersatz. Alles in ganzen Cent, ohne einen einzigen
/// Zwischenschritt in Euro.

Warenkorb korbMit(List<(String, int, int, VatRate)> zeilen) {
  var korb = const Warenkorb.leer();
  for (final (name, menge, preis, satz) in zeilen) {
    korb = korb.hinzugefuegt(Positionsentwurf(bezeichnung: name, betragCents: preis, steuersatz: satz));
    final id = korb.positionen.last.id;
    if (menge != 1) korb = korb.mengeGesetzt(id, menge);
  }
  return korb;
}

void main() {
  group('Warenkorb', () {
    test('Position anlegen, Summe in ganzen Cent', () {
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20), ('Semmel', 4, 79, VatRate.vat10)]);
      expect(korb.positionen, hasLength(2));
      expect(korb.positionen.first.quantity, 3);
      expect(korb.summeCents, 3 * 280 + 4 * 79);
      expect(korb.istLeer, isFalse);
      expect(const Warenkorb.leer().istLeer, isTrue);
    });

    test('ohne Bezeichnung bleibt der Korb unverändert — § 132a BAO verlangt sie', () {
      const leer = Warenkorb.leer();
      final gleich = leer.hinzugefuegt(const Positionsentwurf(bezeichnung: '   ', betragCents: 100, steuersatz: VatRate.vat20));
      expect(identical(gleich, leer), isTrue, reason: 'unverändert heißt unverändert');
    });

    test('zwei gleich aussehende Positionen sind zwei Positionen', () {
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20), ('Kaffee', 1, 280, VatRate.vat20)]);
      expect(korb.positionen.map((p) => p.id).toSet(), hasLength(2));
      final weniger = korb.entfernt(korb.positionen.first.id);
      expect(weniger.positionen, hasLength(1), reason: 'ein Griff entfernt genau eine');
    });

    test('Menge null entfernt die Position; gebrochene Menge bleibt folgenlos', () {
      final korb = korbMit([('Kaffee', 2, 280, VatRate.vat20)]);
      final id = korb.positionen.first.id;
      expect(korb.mengeGesetzt(id, 0).istLeer, isTrue);
      expect(korb.mengeGesetzt(id, -1).istLeer, isTrue);
      expect(identical(korb.mengeGesetzt('gibtsnicht', 5), korb), isTrue);
    });

    test('Höchstmenge je Beleg wird nie überschritten', () {
      var korb = const Warenkorb.leer().hinzugefuegt(
        const Positionsentwurf(bezeichnung: 'Gutschein', betragCents: 5000, steuersatz: VatRate.vat0, maxMenge: 3),
      );
      final id = korb.positionen.first.id;
      korb = korb.mengeGesetzt(id, 99);
      expect(korb.positionen.first.quantity, 3);
    });

    test('verkaufte Positionen abziehen: was währenddessen dazukam, bleibt stehen', () {
      // Der Abschluss dauert (Signatur, DEP) — der nächste Gast steht schon da.
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20), ('Semmel', 1, 79, VatRate.vat10)]);
      final verkauft = Warenkorb(positionen: [korb.positionen.first.mitMenge(2)]);
      final rest = korb.abgezogen(verkauft);
      expect(rest.positionen, hasLength(2));
      expect(rest.positionen.first.quantity, 1, reason: 'zwei von drei verkauft');
      expect(rest.positionen.last.name, 'Semmel');
      // Alles verkauft: Korb leer.
      expect(korb.abgezogen(korb).istLeer, isTrue);
    });

    test('Anzeigezeilen: gebündelt oder je Stück einzeln', () {
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20)]);
      final gebuendelt = korb.zeilen(KasseMenge.x);
      expect(gebuendelt, hasLength(1));
      expect(gebuendelt.single.menge, 3);
      expect(gebuendelt.single.betragCents, 840);

      final einzeln = korb.zeilen(KasseMenge.aus);
      expect(einzeln, hasLength(3));
      expect(einzeln.every((z) => z.menge == 1 && z.betragCents == 280), isTrue);
      expect(einzeln.map((z) => z.key).toSet(), hasLength(3), reason: 'jede Zeile eindeutig');
    });
  });

  group('Betrag lesen und schreiben', () {
    test('gelesen wird über die Ziffern, nicht über Fließkomma', () {
      expect(betragAusText('12,50'), 1250);
      expect(betragAusText('12.50'), 1250);
      expect(betragAusText('4,5'), 450, reason: '„4,5" sind 50 Cent, nicht 5');
      expect(betragAusText(' 7 '), 700);
      expect(betragAusText('100000'), 10000000);
    });

    test('abgewiesen wird, was nicht eindeutig ist', () {
      for (final text in ['', 'abc', '1,234', '-5', '0', '0,00', '1,2,3', '1 000']) {
        expect(betragAusText(text), isNull, reason: 'Eingabe „$text"');
      }
    });

    test('für den Schirm: Tausenderpunkt, Komma, Euro dahinter', () {
      expect(alsEuro(250), '2,50 €');
      expect(alsEuro(0), '0,00 €');
      expect(alsEuro(5), '0,05 €');
      expect(alsEuro(-320), '-3,20 €');
      expect(alsEuro(10000000), '100.000,00 €');
      expect(alsEuro(100000), '1.000,00 €');
    });

    test('Steuersatz, wie er am Tresen gelesen wird', () {
      expect(steuersatzText(VatRate.vat20), '20 %');
      expect(steuersatzText(VatRate.vat4komma9), '4,9 %');
    });
  });

  group('Rabatt', () {
    test('eine negative Position je Steuersatz, anteilig zum Umsatz', () {
      final positionen = [
        KasseneckItem(name: 'A', quantity: 1, priceCents: 6000, vat: VatRate.vat20),
        KasseneckItem(name: 'B', quantity: 1, priceCents: 4000, vat: VatRate.vat10),
      ];
      final zeilen = verteileRabatt(positionen, 1000);
      expect(zeilen, hasLength(2));
      expect(zeilen.map((z) => z.priceCents).reduce((a, b) => a + b), -1000);
      expect(zeilen.firstWhere((z) => z.vat == VatRate.vat20).priceCents, -600);
      expect(zeilen.firstWhere((z) => z.vat == VatRate.vat10).priceCents, -400);
      expect(zeilen.every((z) => z.quantity == 1 && z.name == 'Rabatt'), isTrue);
    });

    test('Restcent gehen nach größtem Bruchteil — die Summe stimmt immer', () {
      final positionen = [
        KasseneckItem(name: 'A', quantity: 1, priceCents: 333, vat: VatRate.vat20),
        KasseneckItem(name: 'B', quantity: 1, priceCents: 333, vat: VatRate.vat10),
        KasseneckItem(name: 'C', quantity: 1, priceCents: 334, vat: VatRate.vat13),
      ];
      final zeilen = verteileRabatt(positionen, 100);
      expect(zeilen.map((z) => z.priceCents).reduce((a, b) => a + b), -100);
      // Keine Zeile ist größer als der Umsatz ihres Satzes.
      for (final z in zeilen) {
        expect(-z.priceCents, lessThanOrEqualTo(334));
      }
    });

    test('kein Rabatt: keine Zeile; Rabatt über dem Umsatz: Fehler', () {
      final positionen = [KasseneckItem(name: 'A', quantity: 1, priceCents: 500, vat: VatRate.vat20)];
      expect(verteileRabatt(positionen, 0), isEmpty);
      expect(() => verteileRabatt(positionen, 501), throwsArgumentError);
      expect(() => verteileRabatt(positionen, -1), throwsArgumentError);
    });

    test('Rabattzeilen zählen nicht als Umsatz — ein zweiter Rabatt rechnet nur auf die Ware', () {
      final positionen = [
        KasseneckItem(name: 'A', quantity: 1, priceCents: 1000, vat: VatRate.vat20),
        KasseneckItem(name: 'Rabatt', quantity: 1, priceCents: -200, vat: VatRate.vat20),
      ];
      expect(verteileRabatt(positionen, 100).single.priceCents, -100);
    });
  });

  group('Kassieren', () {
    const bar = KasseSettingsBetrieb();
    test('Zahlungsarten: nie keine, Karte nur mit Anbieter', () {
      expect(zahlungsarten(bar), [KeckPaymentMethod.cash]);
      expect(zahlungsarten(const KasseSettingsBetrieb(zahlKarte: true)), [KeckPaymentMethod.cash],
          reason: 'ohne Anbieter nützt der Schalter nichts');
      expect(
        zahlungsarten(const KasseSettingsBetrieb(zahlKarte: true, kartenanbieter: KasseKartenanbieter.hobex)),
        [KeckPaymentMethod.cash, KeckPaymentMethod.creditCard],
      );
      expect(zahlungsarten(const KasseSettingsBetrieb(zahlBar: false)), [KeckPaymentMethod.cash],
          reason: 'ohne jede Zahlungsart bliebe die Kasse stehen');
    });

    test('Rabatt aus der Eingabe; außerhalb der Grenzen null', () {
      expect(rabattCents(RabattArt.prozent, 10, 1000), 100);
      expect(rabattCents(RabattArt.betrag, 250, 1000), 250);
      expect(rabattCents(RabattArt.prozent, 101, 1000), isNull);
      expect(rabattCents(RabattArt.betrag, 1001, 1000), isNull, reason: 'mehr als die Summe gibt es nicht');
      expect(rabattCents(RabattArt.betrag, -1, 1000), isNull);
    });

    test('zu zahlen, Rückgeld, Schnellbeträge', () {
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20)]);
      expect(zuZahlen(korb, 0), 280);
      expect(zuZahlen(korb, 80), 200);
      expect(zuZahlen(korb, 999), 0, reason: 'nie unter null');
      expect(rueckgeld(280, 500), 220);
      expect(rueckgeld(280, 100), 0);
      final schnell = schnellbetraege(280);
      expect(schnell.first, 280, reason: 'passend zuerst');
      expect(schnell, contains(300));
      expect(schnell.length, lessThanOrEqualTo(4));
      expect(schnell.toSet().length, schnell.length, reason: 'ohne Doppelte');
    });

    test('Abschluss: leerer Korb nein, Bar mit zu wenig Gegebenem nein', () {
      expect(abschlussPruefung(zahlungsart: KeckPaymentMethod.cash, zuZahlen: 0, gegeben: null, rueckgeldAn: true, leer: true).bereit, isFalse);
      final zuWenig = abschlussPruefung(zahlungsart: KeckPaymentMethod.cash, zuZahlen: 500, gegeben: 200, rueckgeldAn: true, leer: false);
      expect(zuWenig.bereit, isFalse);
      expect(zuWenig.grund, contains('weniger'));
      expect(abschlussPruefung(zahlungsart: KeckPaymentMethod.cash, zuZahlen: 500, gegeben: 200, rueckgeldAn: false, leer: false).bereit, isTrue);
      expect(abschlussPruefung(zahlungsart: KeckPaymentMethod.creditCard, zuZahlen: 500, gegeben: null, rueckgeldAn: true, leer: false).bereit, isTrue);
    });

    test('enthaltene MwSt wie im Backend gerundet', () {
      expect(ustCents(120, 20), 20);
      expect(ustCents(280, 20), 47);
      expect(ustCents(79, 10), 7);
      expect(ustCents(100, 0), 0);
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20), ('Semmel', 1, 79, VatRate.vat10)]);
      expect(ustSumme(korb), 47 + 7);
    });

    test('Belegpositionen: Korb plus Rabattzeilen, ohne Kassen-Kennungen', () {
      final korb = korbMit([('Kaffee', 2, 300, VatRate.vat20)]);
      final ohne = belegPositionen(korb, 0);
      expect(ohne, hasLength(1));
      expect(ohne.single.name, 'Kaffee');
      expect(ohne.single.quantity, 2);

      final mit = belegPositionen(korb, 60);
      expect(mit, hasLength(2));
      expect(mit.last.priceCents, -60);
      expect(mit.map((p) => p.priceCents * p.quantity).reduce((a, b) => a + b), 540);
    });
  });
}
