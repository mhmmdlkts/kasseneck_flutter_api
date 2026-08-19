/// Die Rechnung hinter dem Kassieren — ohne Bildschirm, ohne Netz.
///
/// Zwilling von `lib/kassieren.ts` der Browser-Kasse. Rabatt ist **kein Feld**
/// am Beleg, sondern eine negative Position je Steuersatz ([verteileRabatt]):
/// so stimmt die MwSt-Tabelle des Belegs immer, das DEP zeigt den Rabatt als
/// Position, und Signatur und Backend bleiben unberührt.
///
/// Trinkgeld hat hier bewusst keine Rechnung: die Buchung ist noch offen, die
/// Anzeige bleibt hinter dem Schalter und schreibt nichts in den Beleg.
library;

import '../../enums/keck_payment_method.dart';
import '../../enums/vat_rate.dart';
import '../../models/kasseneck_item.dart';
import 'einstellungen.dart';
import 'warenkorb.dart';

/// Welche Zahlungsarten der Betrieb anbietet — nie keine (dann Bar).
List<KeckPaymentMethod> zahlungsarten(KasseSettingsBetrieb betrieb) {
  final aus = <KeckPaymentMethod>[];
  if (betrieb.zahlBar) aus.add(KeckPaymentMethod.cash);
  // Karte nur mit eingerichtetem Anbieter — der Schalter allein nützt nichts.
  if (betrieb.kartenAktiv) aus.add(KeckPaymentMethod.creditCard);
  return aus.isEmpty ? [KeckPaymentMethod.cash] : aus;
}

enum RabattArt { prozent, betrag }

/// Rabatt in Cent aus der Eingabe; außerhalb von 0 … Summe gibt es keinen.
int? rabattCents(RabattArt art, num wert, int summe) {
  if (wert.isNaN || wert.isInfinite || wert < 0) return null;
  if (art == RabattArt.prozent && wert > 100) return null;
  final c = art == RabattArt.prozent ? (summe * wert / 100).round() : wert.round();
  if (c > summe) return null;
  return c;
}

/// Positionen für den Beleg: Korb plus Rabattzeilen (eine je Steuersatz).
List<KasseneckItem> belegPositionen(Warenkorb warenkorb, int rabatt) {
  final basis = warenkorb.positionen.map((p) => p.alsBelegposition()).toList();
  if (rabatt <= 0) return basis;
  return [...basis, ...verteileRabatt(basis, rabatt)];
}

/// Zu zahlen nach Rabatt — nie unter null.
int zuZahlen(Warenkorb warenkorb, int rabatt) {
  final rest = warenkorb.summeCents - rabatt;
  return rest < 0 ? 0 : rest;
}

int rueckgeld(int zuZahlenCents, int gegebenCents) {
  final rest = gegebenCents - zuZahlenCents;
  return rest < 0 ? 0 : rest;
}

/// Schnellwahl für „Gegeben": passend, der nächste runde Euro, dann Scheine.
List<int> schnellbetraege(int zuZahlenCents) {
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

class AbschlussPruefung {
  const AbschlussPruefung({required this.bereit, this.grund});

  final bool bereit;
  final String? grund;
}

/// Darf abgeschlossen werden? Bar mit Rückgeld-Rechnung braucht genug Gegebenes.
AbschlussPruefung abschlussPruefung({
  required KeckPaymentMethod zahlungsart,
  required int zuZahlen,
  required int? gegeben,
  required bool rueckgeldAn,
  required bool leer,
}) {
  if (leer) {
    return const AbschlussPruefung(
      bereit: false,
      grund: 'Noch nichts erfasst — bitte zuerst eine Position aufnehmen.',
    );
  }
  if (zahlungsart == KeckPaymentMethod.cash && rueckgeldAn && gegeben != null && gegeben < zuZahlen) {
    return const AbschlussPruefung(bereit: false, grund: 'Gegeben ist weniger als der Betrag.');
  }
  return const AbschlussPruefung(bereit: true);
}

/// Enthaltene MwSt aus dem Bruttobetrag (ganzzahlig, wie im Backend).
int ustCents(int brutto, num satz) => (brutto * satz / (100 + satz)).round();

int ustSumme(Warenkorb warenkorb) =>
    warenkorb.positionen.fold(0, (s, p) => s + ustCents(p.zeilensummeCents, p.vat.rate));

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
List<KasseneckItem> verteileRabatt(List<KasseneckItem> positionen, int rabattCents, {String name = 'Rabatt'}) {
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
    zeilen.add(KasseneckItem(name: name, quantity: 1, priceCents: -anteile[i], vat: saetze[i]));
  }
  return zeilen;
}
