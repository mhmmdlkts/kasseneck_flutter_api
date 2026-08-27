import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Die Rechnung hinter dem Kassieren-Bildschirm — Zwilling von
/// `kassierenRechnung` der Browser-Kasse.
///
/// Der wichtigste Punkt: **Trinkgeld erhöht, was der Gast gibt, nicht den
/// Belegbetrag.** Beides auseinanderzuhalten entscheidet über das Rückgeld.

KasseSettingsBetrieb betriebMit(Map<String, dynamic> g) => KasseSettings.aus({'betrieb': g}).betrieb;

Warenkorb korbMit(List<int> betraege) {
  var korb = const Warenkorb.leer();
  for (final (i, c) in betraege.indexed) {
    korb = korb.hinzugefuegt(
      Positionsentwurf(bezeichnung: 'Ware $i', betragCents: c, steuersatz: VatRate.vat20),
    );
  }
  return korb;
}

void main() {
  test('bar ohne Rabatt: zu zahlen ist die Summe, Rückgeld aus dem Gegebenen', () {
    final r = kassierrechnung(
      korbMit([280, 220]),
      betriebMit({}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, gegebenCents: 1000),
    );

    expect(r.summeCents, 500);
    expect(r.zuZahlenCents, 500);
    expect(r.gesamtCents, 500);
    expect(r.rueckgeldCents, 500);
    expect(r.bereit, isTrue);
  });

  test('Rabatt kann die Summe nicht übersteigen', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({'rabatt': 'an'}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, rabattCents: 900),
    );

    expect(r.rabattCents, 500, reason: 'gedeckelt auf die Summe');
    expect(r.zuZahlenCents, 0);
  });

  test('Trinkgeld erhöht das Gegebene, nicht den Beleg', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({'trinkgeld': true}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, trinkgeldCents: 100, gegebenCents: 1000),
    );

    expect(r.zuZahlenCents, 500, reason: 'der Belegbetrag bleibt der Belegbetrag');
    expect(r.trinkgeldCents, 100);
    expect(r.gesamtCents, 600, reason: 'so viel gibt der Gast');
    expect(r.rueckgeldCents, 400);
  });

  test('schaltet der Betrieb das Trinkgeld ab, zählt es nirgends mit', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({'trinkgeld': false}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, trinkgeldCents: 100),
    );

    expect(r.trinkgeldCents, 0);
    expect(r.gesamtCents, 500);
  });

  test('zu wenig gegeben: nicht bereit, und es fehlt genau die Differenz', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, gegebenCents: 300),
    );

    expect(r.fehltCents, 200);
    expect(r.bereit, isFalse);
    expect(r.grund, isNotNull);
  });

  test('noch nichts gegeben ist kein Fehler — nur noch nicht fertig', () {
    // Der Kassier hat den Betrag schlicht noch nicht getippt; das ist kein
    // Grund, ihm eine rote Meldung hinzustellen.
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash),
    );

    expect(r.fehltCents, 0);
    expect(r.bereit, isTrue);
    expect(r.rueckgeldCents, 0);
  });

  test('mit Karte gibt es keine Rückgeld-Rechnung', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({'zahlKarte': true, 'kartenanbieter': 'extern'}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.creditCard, gegebenCents: 300),
    );

    expect(r.bar, isFalse);
    expect(r.gegebenCents, isNull, reason: 'ein Kartenbetrag wird nicht „gegeben"');
    expect(r.bereit, isTrue);
  });

  test('schaltet der Betrieb das Rückgeld ab, wird auch bar nicht gerechnet', () {
    final r = kassierrechnung(
      korbMit([500]),
      betriebMit({'rueckgeld': false}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash, gegebenCents: 300),
    );

    expect(r.bar, isFalse);
    expect(r.bereit, isTrue);
  });

  test('leerer Korb ist nie bereit', () {
    final r = kassierrechnung(
      const Warenkorb.leer(),
      betriebMit({}),
      const Kassierstand(zahlungsart: KeckPaymentMethod.cash),
    );

    expect(r.bereit, isFalse);
    expect(r.grund, contains('Noch nichts erfasst'));
  });

  test('der Startstand nimmt die erste angebotene Zahlungsart', () {
    // Ein Betrieb ohne Bargeld darf nicht mit „Bar" vorbelegt starten.
    final nurKarte = betriebMit({'zahlBar': false, 'zahlKarte': true, 'kartenanbieter': 'extern'});
    expect(Kassierstand.start(nurKarte).zahlungsart, KeckPaymentMethod.creditCard);
    expect(Kassierstand.start(betriebMit({})).zahlungsart, KeckPaymentMethod.cash);
  });

  test('USt der Belegpositionen zählt den Rabatt mit', () {
    // Sonst stuende auf dem Beleg mehr MwSt, als der Gast gezahlt hat.
    // ustSumme muss dabei von sich aus dasselbe liefern wie die Rechnung
    // ueber die Belegpositionen — frueher tat es das nicht.
    final ohne = ustSumme(korbMit([1200]));
    final positionen = belegPositionen(korbMit([1200]), 200);
    final mit = ustSummePositionen(positionen);

    expect(ohne, 200);
    expect(mit, 167);
    expect(ustSumme(korbMit([1200]), rabattCents: 200), 167);
  });
}
