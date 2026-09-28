import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Der laufende Verkauf: erfassen, ändern, zusammenzählen — und der Rabatt als
/// negative Position je Steuersatz. Alles in ganzen Cent, ohne einen einzigen
/// Zwischenschritt in Euro.

Cart korbMit(List<(String, int, int, VatRate)> zeilen) {
  var korb = const Cart.empty();
  for (final (name, menge, preis, satz) in zeilen) {
    korb = korb.added(CartItemDraft(name: name, unitPriceCents: preis, vatRate: satz));
    final id = korb.items.last.id;
    if (menge != 1) korb = korb.withQuantity(id, menge);
  }
  return korb;
}

void main() {
  group('Warenkorb', () {
    test('Position anlegen, Summe in ganzen Cent', () {
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20), ('Semmel', 4, 79, VatRate.vat10)]);
      expect(korb.items, hasLength(2));
      expect(korb.items.first.quantity, 3);
      expect(korb.totalCents, 3 * 280 + 4 * 79);
      expect(korb.isEmpty, isFalse);
      expect(const Cart.empty().isEmpty, isTrue);
    });

    test('ohne Bezeichnung bleibt der Korb unverändert — § 132a BAO verlangt sie', () {
      const leer = Cart.empty();
      final gleich = leer.added(const CartItemDraft(name: '   ', unitPriceCents: 100, vatRate: VatRate.vat20));
      expect(identical(gleich, leer), isTrue, reason: 'unverändert heißt unverändert');
    });

    test('zwei gleich aussehende Positionen sind zwei Positionen', () {
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20), ('Kaffee', 1, 280, VatRate.vat20)]);
      expect(korb.items.map((p) => p.id).toSet(), hasLength(2));
      final weniger = korb.removed(korb.items.first.id);
      expect(weniger.items, hasLength(1), reason: 'ein Griff entfernt genau eine');
    });

    test('Menge null entfernt die Position; gebrochene Menge bleibt folgenlos', () {
      final korb = korbMit([('Kaffee', 2, 280, VatRate.vat20)]);
      final id = korb.items.first.id;
      expect(korb.withQuantity(id, 0).isEmpty, isTrue);
      expect(korb.withQuantity(id, -1).isEmpty, isTrue);
      expect(identical(korb.withQuantity('gibtsnicht', 5), korb), isTrue);
    });

    test('Höchstmenge je Beleg wird nie überschritten', () {
      var korb = const Cart.empty().added(
        const CartItemDraft(name: 'Gutschein', unitPriceCents: 5000, vatRate: VatRate.vat0, maxQuantity: 3),
      );
      final id = korb.items.first.id;
      korb = korb.withQuantity(id, 99);
      expect(korb.items.first.quantity, 3);
    });

    test('verkaufte Positionen abziehen: was währenddessen dazukam, bleibt stehen', () {
      // Der Abschluss dauert (Signatur, DEP) — der nächste Gast steht schon da.
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20), ('Semmel', 1, 79, VatRate.vat10)]);
      final verkauft = Cart(items: [korb.items.first.withQuantity(2)]);
      final rest = korb.subtracted(verkauft);
      expect(rest.items, hasLength(2));
      expect(rest.items.first.quantity, 1, reason: 'zwei von drei verkauft');
      expect(rest.items.last.name, 'Semmel');
      // Alles verkauft: Korb leer.
      expect(korb.subtracted(korb).isEmpty, isTrue);
    });

    test('Anzeigezeilen: gebündelt oder je Stück einzeln', () {
      final korb = korbMit([('Kaffee', 3, 280, VatRate.vat20)]);
      final gebuendelt = korb.lines(PosQuantity.x);
      expect(gebuendelt, hasLength(1));
      expect(gebuendelt.single.quantity, 3);
      expect(gebuendelt.single.amountCents, 840);

      final einzeln = korb.lines(PosQuantity.off);
      expect(einzeln, hasLength(3));
      expect(einzeln.every((z) => z.quantity == 1 && z.amountCents == 280), isTrue);
      expect(einzeln.map((z) => z.key).toSet(), hasLength(3), reason: 'jede Zeile eindeutig');
    });
  });

  group('Betrag lesen und schreiben', () {
    test('gelesen wird über die Ziffern, nicht über Fließkomma', () {
      expect(parseAmountCents('12,50'), 1250);
      expect(parseAmountCents('12.50'), 1250);
      expect(parseAmountCents('4,5'), 450, reason: '„4,5" sind 50 Cent, nicht 5');
      expect(parseAmountCents(' 7 '), 700);
      expect(parseAmountCents('100000'), 10000000);
    });

    test('abgewiesen wird, was nicht eindeutig ist', () {
      for (final text in ['', 'abc', '1,234', '-5', '0', '0,00', '1,2,3', '1 000']) {
        expect(parseAmountCents(text), isNull, reason: 'Eingabe „$text"');
      }
    });

    test('der beschriebene Deckel existiert jetzt auch', () {
      // hoechstbetragCent wurde bis hierher an keiner Stelle gelesen: der
      // Kommentar beschrieb einen Schutz, den es nicht gab.
      expect(parseAmountCents('100000'), maxAmountCents);
      expect(parseAmountCents('100000,00'), maxAmountCents);
      expect(parseAmountCents('100000,01'), isNull);
      expect(parseAmountCents('999999'), isNull);
    });

    test('sehr viele Ziffern liefern null statt zu werfen', () {
      // int.parse warf hier eine FormatException — erreichbar ueber eine
      // haengende Taste oder eine eingefuegte Zeichenkette.
      expect(parseAmountCents('99999999999999999999'), isNull);
      expect(parseAmountCents('9' * 400), isNull);
    });

    test('für den Schirm: Tausenderpunkt, Komma, Euro dahinter', () {
      expect(formatEuro(250), '2,50 €');
      expect(formatEuro(0), '0,00 €');
      expect(formatEuro(5), '0,05 €');
      expect(formatEuro(-320), '-3,20 €');
      expect(formatEuro(10000000), '100.000,00 €');
      expect(formatEuro(100000), '1.000,00 €');
    });

    test('Steuersatz, wie er am Tresen gelesen wird', () {
      expect(formatVatRate(VatRate.vat20), '20 %');
      expect(formatVatRate(VatRate.vat4_9), '4,9 %');
    });
  });

  group('Rabatt', () {
    test('eine negative Position je Steuersatz, anteilig zum Umsatz', () {
      final positionen = [
        KasseneckItem(name: 'A', quantity: 1, priceCents: 6000, vat: VatRate.vat20),
        KasseneckItem(name: 'B', quantity: 1, priceCents: 4000, vat: VatRate.vat10),
      ];
      final zeilen = distributeDiscount(positionen, 1000);
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
      final zeilen = distributeDiscount(positionen, 100);
      expect(zeilen.map((z) => z.priceCents).reduce((a, b) => a + b), -100);
      // Keine Zeile ist größer als der Umsatz ihres Satzes.
      for (final z in zeilen) {
        expect(-z.priceCents, lessThanOrEqualTo(334));
      }
    });

    test('kein Rabatt: keine Zeile; Rabatt über dem Umsatz: Fehler', () {
      final positionen = [KasseneckItem(name: 'A', quantity: 1, priceCents: 500, vat: VatRate.vat20)];
      expect(distributeDiscount(positionen, 0), isEmpty);
      expect(() => distributeDiscount(positionen, 501), throwsArgumentError);
      expect(() => distributeDiscount(positionen, -1), throwsArgumentError);
    });

    test('Rabattzeilen zählen nicht als Umsatz — ein zweiter Rabatt rechnet nur auf die Ware', () {
      final positionen = [
        KasseneckItem(name: 'A', quantity: 1, priceCents: 1000, vat: VatRate.vat20),
        KasseneckItem(name: 'Rabatt', quantity: 1, priceCents: -200, vat: VatRate.vat20),
      ];
      expect(distributeDiscount(positionen, 100).single.priceCents, -100);
    });
  });

  group('Kassieren', () {
    const bar = PosBusinessSettings();
    test('Zahlungsarten: nie keine, Karte nur mit Anbieter', () {
      expect(offeredPaymentMethods(bar), [KeckPaymentMethod.cash]);
      expect(offeredPaymentMethods(const PosBusinessSettings(payCard: true)), [KeckPaymentMethod.cash],
          reason: 'ohne Anbieter nützt der Schalter nichts');
      expect(
        offeredPaymentMethods(const PosBusinessSettings(payCard: true, cardProvider: PosCardProvider.hobex)),
        [KeckPaymentMethod.cash, KeckPaymentMethod.creditCard],
      );
      expect(offeredPaymentMethods(const PosBusinessSettings(payCash: false)), [KeckPaymentMethod.cash],
          reason: 'ohne jede Zahlungsart bliebe die Kasse stehen');
    });

    test('Rabatt aus der Eingabe; außerhalb der Grenzen null', () {
      expect(discountCentsFor(DiscountKind.percent, 10, 1000), 100);
      expect(discountCentsFor(DiscountKind.amount, 250, 1000), 250);
      expect(discountCentsFor(DiscountKind.percent, 101, 1000), isNull);
      expect(discountCentsFor(DiscountKind.amount, 1001, 1000), isNull, reason: 'mehr als die Summe gibt es nicht');
      expect(discountCentsFor(DiscountKind.amount, -1, 1000), isNull);
    });

    test('zu zahlen, Rückgeld, Schnellbeträge', () {
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20)]);
      expect(amountDue(korb, 0), 280);
      expect(amountDue(korb, 80), 200);
      expect(amountDue(korb, 999), 0, reason: 'nie unter null');
      expect(computeChange(280, 500), 220);
      expect(computeChange(280, 100), 0);
      final schnell = quickAmounts(280);
      expect(schnell.first, 280, reason: 'passend zuerst');
      expect(schnell, contains(300));
      expect(schnell.length, lessThanOrEqualTo(4));
      expect(schnell.toSet().length, schnell.length, reason: 'ohne Doppelte');
    });

    test('Abschluss: leerer Korb nein, Bar mit zu wenig Gegebenem nein', () {
      expect(completionCheck(paymentMethod: KeckPaymentMethod.cash, dueCents: 0, tenderedCents: null, changeEnabled: true, cartEmpty: true).ready, isFalse);
      final zuWenig = completionCheck(paymentMethod: KeckPaymentMethod.cash, dueCents: 500, tenderedCents: 200, changeEnabled: true, cartEmpty: false);
      expect(zuWenig.ready, isFalse);
      expect(zuWenig.reason, contains('weniger'));
      expect(completionCheck(paymentMethod: KeckPaymentMethod.cash, dueCents: 500, tenderedCents: 200, changeEnabled: false, cartEmpty: false).ready, isTrue);
      expect(completionCheck(paymentMethod: KeckPaymentMethod.creditCard, dueCents: 500, tenderedCents: null, changeEnabled: true, cartEmpty: false).ready, isTrue);
    });

    test('enthaltene MwSt nach der Belegregel gerundet', () {
      expect(vatCentsFromGross(120, 20), 20);
      expect(vatCentsFromGross(280, 20), 47);
      expect(vatCentsFromGross(79, 10), 7);
      expect(vatCentsFromGross(100, 0), 0);
      // Der Grenzfall, an dem die fruehere Regel (brutto*satz/(100+satz)) um
      // einen Cent danebenlag: 0,99 EUR zu 20 % sind 0,16 EUR MwSt, nicht 0,17.
      expect(vatCentsFromGross(99, 20), 16);
      expect(netCentsFromGross(99, 20), 83);
      final korb = korbMit([('Kaffee', 1, 280, VatRate.vat20), ('Semmel', 1, 79, VatRate.vat10)]);
      expect(vatTotalCents(korb), 47 + 7);
    });

    test('ustSumme rundet je Steuersatz, nicht je Position', () {
      // Dreimal „Kugel Eis" a 0,33 EUR zu 20 %: je Position gerundet waeren das
      // 0,18 EUR, als eine Position mit Menge 3 waeren es 0,17 EUR. Auf dem
      // Beleg stehen 0,99 EUR zu 20 % und damit 0,16 EUR — egal wie getippt.
      final einzeln = korbMit([
        ('Kugel Eis', 1, 33, VatRate.vat20),
        ('Kugel Eis', 1, 33, VatRate.vat20),
        ('Kugel Eis', 1, 33, VatRate.vat20),
      ]);
      final gebuendelt = korbMit([('Kugel Eis', 3, 33, VatRate.vat20)]);
      expect(vatTotalCents(einzeln), 16);
      expect(vatTotalCents(gebuendelt), 16);
    });

    test('ustSumme zaehlt den Rabatt mit', () {
      // 12,00 EUR zu 20 % minus 2,00 EUR Rabatt enthalten 1,67 EUR MwSt.
      // Ohne den Rabatt waeren es 2,00 EUR — 33 Cent zu viel ausgewiesen.
      final korb = korbMit([('Ware', 1, 1200, VatRate.vat20)]);
      expect(vatTotalCents(korb), 200);
      expect(vatTotalCents(korb, discountCents: 200), 167);
      expect(vatTotalCents(korb, discountCents: 200), vatTotalCentsOfItems(receiptItems(korb, 200)));
    });

    test('Belegpositionen: Korb plus Rabattzeilen, ohne Kassen-Kennungen', () {
      final korb = korbMit([('Kaffee', 2, 300, VatRate.vat20)]);
      final ohne = receiptItems(korb, 0);
      expect(ohne, hasLength(1));
      expect(ohne.single.name, 'Kaffee');
      expect(ohne.single.quantity, 2);

      final mit = receiptItems(korb, 60);
      expect(mit, hasLength(2));
      expect(mit.last.priceCents, -60);
      expect(mit.map((p) => p.priceCents * p.quantity).reduce((a, b) => a + b), 540);
    });
  });
}
