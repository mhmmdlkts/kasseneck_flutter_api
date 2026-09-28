/// Die Rechnung hinter dem Kassieren — ohne Bildschirm, ohne Netz.
///
/// Zwilling von `lib/kassieren.ts` der Browser-Kasse. Rabatt ist **kein Feld**
/// am Beleg, sondern eine negative Position je Steuersatz ([distributeDiscount]):
/// so stimmt die MwSt-Tabelle des Belegs immer, das DEP zeigt den Rabatt als
/// Position, und Signatur und Backend bleiben unberührt.
///
/// Trinkgeld hat hier bewusst keine Rechnung: die Buchung ist noch offen, die
/// Anzeige bleibt hinter dem Schalter und schreibt nichts in den Beleg.
library;

import '../../enums/keck_payment_method.dart';
import '../../enums/vat_rate.dart';
import '../../models/kasseneck_item.dart';
import '../../models/keck_payment.dart';
import '../vat_math.dart';
import 'einstellungen.dart';
import 'warenkorb.dart';

// Die USt-Zerlegung gehoert zur Kassieren-Schnittstelle: wer die enthaltene
// MwSt anzeigt, braucht dieselbe Regel wie der Beleg — und nicht eine eigene.
export '../vat_math.dart' show netCentsFromGross, vatCentsFromGross;

/// Welche Zahlungsarten der Betrieb anbietet — nie keine (dann Bar).
List<KeckPaymentMethod> offeredPaymentMethods(PosBusinessSettings betrieb) {
  final aus = <KeckPaymentMethod>[];
  if (betrieb.payCash) aus.add(KeckPaymentMethod.cash);
  // Karte nur mit eingerichtetem Anbieter — der Schalter allein nützt nichts.
  if (betrieb.cardPaymentEnabled) aus.add(KeckPaymentMethod.creditCard);
  return aus.isEmpty ? [KeckPaymentMethod.cash] : aus;
}

enum DiscountKind { percent, amount }

/// Rabatt in Cent aus der Eingabe; außerhalb von 0 … Summe gibt es keinen.
int? discountCentsFor(DiscountKind art, num wert, int summe) {
  if (wert.isNaN || wert.isInfinite || wert < 0) return null;
  if (art == DiscountKind.percent && wert > 100) return null;
  final c = art == DiscountKind.percent ? (summe * wert / 100).round() : wert.round();
  if (c > summe) return null;
  return c;
}

/// Positionen für den Beleg: Korb plus Rabattzeilen (eine je Steuersatz).
List<KasseneckItem> receiptItems(Cart warenkorb, int rabatt) {
  final basis = warenkorb.items.map((p) => p.toReceiptItem()).toList();
  if (rabatt <= 0) return basis;
  return [...basis, ...distributeDiscount(basis, rabatt)];
}

/// Zu zahlen nach Rabatt — nie unter null.
int amountDue(Cart warenkorb, int rabatt) {
  final rest = warenkorb.totalCents - rabatt;
  return rest < 0 ? 0 : rest;
}

int computeChange(int zuZahlenCents, int gegebenCents) {
  final rest = gegebenCents - zuZahlenCents;
  return rest < 0 ? 0 : rest;
}

/// Schnellwahl für „Gegeben": passend, der nächste runde Euro, dann Scheine.
List<int> quickAmounts(int zuZahlenCents) {
  const scheine = [500, 1000, 2000, 5000, 10000, 20000];
  final aus = <int>[zuZahlenCents];
  final rund = ((zuZahlenCents + 99) ~/ 100) * 100;
  if (rund > zuZahlenCents) aus.add(rund);
  for (final s in scheine) {
    if (aus.length >= 4) break;
    if (s > zuZahlenCents && !aus.contains(s)) aus.add(s);
  }
  return aus.take(4).toList();
}

class CompletionCheck {
  const CompletionCheck({required this.ready, this.reason});

  final bool ready;
  final String? reason;
}

/// Darf abgeschlossen werden? Bar mit Rückgeld-Rechnung braucht genug Gegebenes.
CompletionCheck completionCheck({
  required KeckPaymentMethod paymentMethod,
  required int dueCents,
  required int? tenderedCents,
  required bool changeEnabled,
  required bool cartEmpty,
}) {
  if (cartEmpty) {
    return const CompletionCheck(
      ready: false,
      reason: 'Noch nichts erfasst — bitte zuerst eine Position aufnehmen.',
    );
  }
  if (paymentMethod == KeckPaymentMethod.cash && changeEnabled && tenderedCents != null && tenderedCents < dueCents) {
    return const CompletionCheck(ready: false, reason: 'Gegeben ist weniger als der Betrag.');
  }
  return const CompletionCheck(ready: true);
}

/// Was der Kassier am Kassieren-Bildschirm eingestellt hat.
class CheckoutState {
  const CheckoutState({
    required this.paymentMethod,
    this.discountCents = 0,
    this.tenderedCents,
    this.tipCents = 0,
  });

  /// Startstand: die erste Zahlungsart, die der Betrieb anbietet. Ein Betrieb
  /// ohne Bargeld darf nicht mit „Bar" vorbelegt beginnen.
  factory CheckoutState.start(PosBusinessSettings betrieb) =>
      CheckoutState(paymentMethod: offeredPaymentMethods(betrieb).first);

  final KeckPaymentMethod paymentMethod;
  final int discountCents;

  /// Bar gegeben; `null`, solange nichts getippt wurde — das ist etwas anderes
  /// als „null Euro gegeben".
  final int? tenderedCents;
  final int tipCents;

  CheckoutState copyWith({
    KeckPaymentMethod? paymentMethod,
    int? discountCents,
    int? tenderedCents,
    bool clearTendered = false,
    int? tipCents,
  }) =>
      CheckoutState(
        paymentMethod: paymentMethod ?? this.paymentMethod,
        discountCents: discountCents ?? this.discountCents,
        tenderedCents: clearTendered ? null : (tenderedCents ?? this.tenderedCents),
        tipCents: tipCents ?? this.tipCents,
      );
}

/// Alle Beträge des Kassiervorgangs auf einen Blick.
class CheckoutTotals {
  const CheckoutTotals({
    required this.subtotalCents,
    required this.discountCents,
    required this.dueCents,
    required this.tipCents,
    required this.totalCents,
    required this.cash,
    required this.tenderedCents,
    required this.missingCents,
    required this.changeCents,
    required this.ready,
    this.reason,
  });

  /// Warenkorb ohne Rabatt.
  final int subtotalCents;
  final int discountCents;

  /// **Belegbetrag** nach Rabatt — ohne Trinkgeld.
  final int dueCents;

  /// Trinkgeld; steht nicht im Belegbetrag, aber im Gegebenen.
  final int tipCents;

  /// Was der Gast tatsächlich gibt: [dueCents] + [tipCents].
  final int totalCents;

  /// Wird bar mit Rückgeld gerechnet?
  final bool cash;

  /// Nur bei [cash]: was gegeben wurde.
  final int? tenderedCents;

  /// Was noch fehlt; 0, solange nichts getippt wurde.
  final int missingCents;
  final int changeCents;

  final bool ready;
  final String? reason;
}

/// Die ganze Rechnung des Kassierens — Zwilling von `kassierenRechnung` der
/// Browser-Kasse.
///
/// **Trinkgeld erhöht, was der Gast gibt, nicht den Belegbetrag.** Der Beleg
/// trägt den Warenwert; das Trinkgeld bucht das Backend als eigene Positionen.
/// Für das Rückgeld zählt trotzdem beides zusammen — sonst bekäme der Gast sein
/// Trinkgeld als Wechselgeld zurück.
CheckoutTotals checkoutTotals(Cart warenkorb, PosBusinessSettings betrieb, CheckoutState stand) {
  final summe = warenkorb.totalCents;
  final rabatt = stand.discountCents > summe ? summe : (stand.discountCents < 0 ? 0 : stand.discountCents);
  final zahlen = amountDue(warenkorb, rabatt);
  final trinkgeld = betrieb.tip && stand.tipCents > 0 ? stand.tipCents : 0;
  final gesamt = zahlen + trinkgeld;
  final bar = stand.paymentMethod == KeckPaymentMethod.cash && betrieb.change;
  final gegeben = bar ? stand.tenderedCents : null;
  final pruefung = completionCheck(
    paymentMethod: stand.paymentMethod,
    dueCents: gesamt,
    tenderedCents: stand.tenderedCents,
    changeEnabled: betrieb.change,
    cartEmpty: warenkorb.isEmpty,
  );
  return CheckoutTotals(
    subtotalCents: summe,
    discountCents: rabatt,
    dueCents: zahlen,
    tipCents: trinkgeld,
    totalCents: gesamt,
    cash: bar,
    tenderedCents: gegeben,
    // Nichts getippt heißt nicht „zu wenig": der Kassier ist schlicht noch
    // nicht fertig, und dafür gibt es keine rote Meldung.
    missingCents: bar && gegeben != null && gegeben > 0 && gegeben < gesamt ? gesamt - gegeben : 0,
    changeCents: bar && gegeben != null ? computeChange(gesamt, gegeben) : 0,
    ready: pruefung.ready,
    reason: pruefung.reason,
  );
}

/// Die Barzahlung aus der Kassierrechnung als Eintrag fuer `payments` --
/// mit `tenderedCents`, damit das Backend Gegeben und Rueckgeld am Beleg
/// fuehrt und der Bon sie zeigt.
///
/// [amountCents] ist der Teil, der bar bezahlt wird; ohne Angabe alles, was
/// der Gast gibt ([CheckoutTotals.totalCents], also samt Trinkgeld -- der
/// Zahlbetrag des Backends zaehlt das Mitarbeiter-Trinkgeld mit). Bei
/// mehreren Zahlungen ist es der Rest nach den Karten.
///
/// `tenderedCents` geht nur mit, wenn das Rueckgeld gerechnet wird
/// ([CheckoutTotals.cash]) und das Gegebene den Betrag deckt: zu wenig
/// Gegebenes lehnte der Server ab (`payment_tendered_invalid`), und ein Beleg
/// darf an einer Anzeige-Angabe nicht scheitern.
KeckPaymentInput cashPayment(CheckoutTotals rechnung, {int? amountCents}) {
  final betrag = amountCents ?? rechnung.totalCents;
  final gegeben = rechnung.tenderedCents;
  return KeckPaymentInput(
    method: KeckPaymentMethod.cash,
    amountCents: betrag,
    tenderedCents: rechnung.cash && gegeben != null && gegeben >= betrag ? gegeben : null,
  );
}

/// Enthaltene MwSt des Warenkorbs — **wie sie auf dem Beleg stehen wird**.
///
/// Zwei Dinge, die die frueheren Fassungen falsch hatten:
///
/// 1. **Je Steuersatz gerundet, nicht je Position.** Dreimal 0,33 € zu 20 %
///    ergaben einzeln gerundet 0,18 €, als eine Position mit Menge 3 dagegen
///    0,17 € — der Beleg weist fuer dieselbe Ware 0,16 € aus. Der Steuersatz
///    ist die Gruppe, nicht die Zeile.
/// 2. **Der Rabatt zaehlt mit.** Ein Korb ueber 12,00 € zu 20 % mit 2,00 €
///    Rabatt enthaelt 1,67 € MwSt, nicht 2,00 € — der Rabatt ist eine negative
///    Belegposition ([distributeDiscount]) und senkt den Umsatz seines Satzes.
///
/// [discountCents] ist derselbe Wert, der auch in [receiptItems] geht.
int vatTotalCents(Cart warenkorb, {int discountCents = 0}) =>
    vatTotalCentsOfItems(receiptItems(warenkorb, discountCents));

/// Enthaltene MwSt einer Belegpositionsliste — je Steuersatz gruppiert, dann
/// einmal zerlegt. Fuer Aufrufer, die die Positionen schon haben (Storno,
/// Nachdruck), und die gemeinsame Rechnung hinter [vatTotalCents].
int vatTotalCentsOfItems(List<KasseneckItem> positionen) {
  final brutto = <VatRate, int>{};
  for (final p in positionen) {
    brutto[p.vat] = (brutto[p.vat] ?? 0) + p.totalCents;
  }
  return brutto.entries.fold(0, (s, e) => s + vatCentsFromGross(e.value, e.key.rate));
}

/// Rabatt als negative Position(en) — eine je Steuersatz, anteilig zum
/// Bruttoumsatz dieses Satzes.
///
/// Gerundet nach dem größten Rest (Hare-Niemeyer): die Cent, die beim Abrunden
/// übrig bleiben, gehen der Reihe nach an die Gruppen mit dem größten
/// Bruchteil; keine Zeile ist je größer als der Umsatz ihres Satzes, und die
/// Summe der Zeilen ist **immer genau** der Rabatt.
///
/// Rabatt- und Stornozeilen (negativ) zählen nicht als Umsatz: ein zweiter
/// Rabatt rechnet nur auf die Ware.
List<KasseneckItem> distributeDiscount(List<KasseneckItem> positionen, int rabattCents, {String name = 'Rabatt'}) {
  if (rabattCents < 0) {
    throw ArgumentError.value(rabattCents, 'rabattCents', 'Rabatt muss eine ganze Zahl in Cent >= 0 sein');
  }
  if (rabattCents == 0) return const [];

  final gruppen = <VatRate, int>{};
  for (final p in positionen) {
    final betrag = p.totalCents;
    if (betrag <= 0) continue;
    gruppen[p.vat] = (gruppen[p.vat] ?? 0) + betrag;
  }
  final saetze = gruppen.keys.toList();
  final gesamt = gruppen.values.fold(0, (s, u) => s + u);
  if (rabattCents > gesamt) {
    throw ArgumentError.value(rabattCents, 'rabattCents', 'Rabatt uebersteigt den Umsatz');
  }

  final exakt = [for (final s in saetze) rabattCents * gruppen[s]! / gesamt];
  final anteile = [for (final x in exakt) x.floor()];
  var rest = rabattCents - anteile.fold(0, (s, a) => s + a);

  // Restcent: größter Bruchteil zuerst, bei Gleichstand größerer Umsatz.
  final reihenfolge = List<int>.generate(saetze.length, (i) => i)
    ..sort((a, b) {
      final bruch = (exakt[b] - anteile[b]).compareTo(exakt[a] - anteile[a]);
      return bruch != 0 ? bruch : gruppen[saetze[b]]!.compareTo(gruppen[saetze[a]]!);
    });
  for (var runde = 0; rest > 0 && runde <= saetze.length; runde++) {
    for (final i in reihenfolge) {
      if (rest == 0) break;
      if (anteile[i] < gruppen[saetze[i]]!) {
        anteile[i] += 1;
        rest -= 1;
      }
    }
  }

  final zeilen = <KasseneckItem>[];
  for (var i = 0; i < saetze.length; i++) {
    if (anteile[i] <= 0) continue;
    // kind 'discount': der Bon fasst die Zeilen zu einer Summenzeile mit
    // Zwischensumme zusammen, der Bericht fuehrt sie als "Rabatte"
    // (Zwilling von verteileRabatt im JS-Paket seit 0.6.42).
    zeilen.add(KasseneckItem(name: name, quantity: 1, priceCents: -anteile[i], vat: saetze[i], kind: 'discount'));
  }
  return zeilen;
}
