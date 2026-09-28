import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Die Rechnung hinter dem Kassieren-Bildschirm — Zwilling von
/// `kassierenRechnung` der Browser-Kasse.
///
/// Der wichtigste Punkt: **Trinkgeld erhöht, was der Gast gibt, nicht den
/// Belegbetrag.** Beides auseinanderzuhalten entscheidet über das Rückgeld.

PosBusinessSettings betriebMit(Map<String, dynamic> g) => PosSettings.fromJson({'betrieb': g}).business;

Cart korbMit(List<int> betraege) {
  var korb = const Cart.empty();
  for (final (i, c) in betraege.indexed) {
    korb = korb.added(
      CartItemDraft(name: 'Ware $i', unitPriceCents: c, vatRate: VatRate.vat20),
    );
  }
  return korb;
}

void main() {
  test('bar ohne Rabatt: zu zahlen ist die Summe, Rückgeld aus dem Gegebenen', () {
    final r = checkoutTotals(
      korbMit([280, 220]),
      betriebMit({}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 1000),
    );

    expect(r.subtotalCents, 500);
    expect(r.dueCents, 500);
    expect(r.totalCents, 500);
    expect(r.changeCents, 500);
    expect(r.ready, isTrue);
  });

  test('Rabatt kann die Summe nicht übersteigen', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({'rabatt': 'an'}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, discountCents: 900),
    );

    expect(r.discountCents, 500, reason: 'gedeckelt auf die Summe');
    expect(r.dueCents, 0);
  });

  test('Trinkgeld erhöht das Gegebene, nicht den Beleg', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({'trinkgeld': true}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tipCents: 100, tenderedCents: 1000),
    );

    expect(r.dueCents, 500, reason: 'der Belegbetrag bleibt der Belegbetrag');
    expect(r.tipCents, 100);
    expect(r.totalCents, 600, reason: 'so viel gibt der Gast');
    expect(r.changeCents, 400);
  });

  test('schaltet der Betrieb das Trinkgeld ab, zählt es nirgends mit', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({'trinkgeld': false}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tipCents: 100),
    );

    expect(r.tipCents, 0);
    expect(r.totalCents, 500);
  });

  test('zu wenig gegeben: nicht bereit, und es fehlt genau die Differenz', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 300),
    );

    expect(r.missingCents, 200);
    expect(r.ready, isFalse);
    expect(r.reason, isNotNull);
  });

  test('noch nichts gegeben ist kein Fehler — nur noch nicht fertig', () {
    // Der Kassier hat den Betrag schlicht noch nicht getippt; das ist kein
    // Grund, ihm eine rote Meldung hinzustellen.
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash),
    );

    expect(r.missingCents, 0);
    expect(r.ready, isTrue);
    expect(r.changeCents, 0);
  });

  test('mit Karte gibt es keine Rückgeld-Rechnung', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({'zahlKarte': true, 'kartenanbieter': 'extern'}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.creditCard, tenderedCents: 300),
    );

    expect(r.cash, isFalse);
    expect(r.tenderedCents, isNull, reason: 'ein Kartenbetrag wird nicht „gegeben"');
    expect(r.ready, isTrue);
  });

  test('schaltet der Betrieb das Rückgeld ab, wird auch bar nicht gerechnet', () {
    final r = checkoutTotals(
      korbMit([500]),
      betriebMit({'rueckgeld': false}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 300),
    );

    expect(r.cash, isFalse);
    expect(r.ready, isTrue);
  });

  test('leerer Korb ist nie bereit', () {
    final r = checkoutTotals(
      const Cart.empty(),
      betriebMit({}),
      const CheckoutState(paymentMethod: KeckPaymentMethod.cash),
    );

    expect(r.ready, isFalse);
    expect(r.reason, contains('Noch nichts erfasst'));
  });

  test('der Startstand nimmt die erste angebotene Zahlungsart', () {
    // Ein Betrieb ohne Bargeld darf nicht mit „Bar" vorbelegt starten.
    final nurKarte = betriebMit({'zahlBar': false, 'zahlKarte': true, 'kartenanbieter': 'extern'});
    expect(CheckoutState.start(nurKarte).paymentMethod, KeckPaymentMethod.creditCard);
    expect(CheckoutState.start(betriebMit({})).paymentMethod, KeckPaymentMethod.cash);
  });

  test('USt der Belegpositionen zählt den Rabatt mit', () {
    // Sonst stuende auf dem Beleg mehr MwSt, als der Gast gezahlt hat.
    // ustSumme muss dabei von sich aus dasselbe liefern wie die Rechnung
    // ueber die Belegpositionen — frueher tat es das nicht.
    final ohne = vatTotalCents(korbMit([1200]));
    final positionen = receiptItems(korbMit([1200]), 200);
    final mit = vatTotalCentsOfItems(positionen);

    expect(ohne, 200);
    expect(mit, 167);
    expect(vatTotalCents(korbMit([1200]), discountCents: 200), 167);
  });
}
