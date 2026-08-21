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

/// Was der Kassier am Kassieren-Bildschirm eingestellt hat.
class Kassierstand {
  const Kassierstand({
    required this.zahlungsart,
    this.rabattCents = 0,
    this.gegebenCents,
    this.trinkgeldCents = 0,
  });

  /// Startstand: die erste Zahlungsart, die der Betrieb anbietet. Ein Betrieb
  /// ohne Bargeld darf nicht mit „Bar" vorbelegt beginnen.
  factory Kassierstand.start(KasseSettingsBetrieb betrieb) =>
      Kassierstand(zahlungsart: zahlungsarten(betrieb).first);

  final KeckPaymentMethod zahlungsart;
  final int rabattCents;

  /// Bar gegeben; `null`, solange nichts getippt wurde — das ist etwas anderes
  /// als „null Euro gegeben".
  final int? gegebenCents;
  final int trinkgeldCents;

  Kassierstand kopie({
    KeckPaymentMethod? zahlungsart,
    int? rabattCents,
    int? gegebenCents,
    bool gegebenLoeschen = false,
    int? trinkgeldCents,
  }) =>
      Kassierstand(
        zahlungsart: zahlungsart ?? this.zahlungsart,
        rabattCents: rabattCents ?? this.rabattCents,
        gegebenCents: gegebenLoeschen ? null : (gegebenCents ?? this.gegebenCents),
        trinkgeldCents: trinkgeldCents ?? this.trinkgeldCents,
      );
}

/// Alle Beträge des Kassiervorgangs auf einen Blick.
class Kassierrechnung {
  const Kassierrechnung({
    required this.summeCents,
    required this.rabattCents,
    required this.zuZahlenCents,
    required this.trinkgeldCents,
    required this.gesamtCents,
    required this.bar,
    required this.gegebenCents,
    required this.fehltCents,
    required this.rueckgeldCents,
    required this.bereit,
    this.grund,
  });

  /// Warenkorb ohne Rabatt.
  final int summeCents;
  final int rabattCents;

  /// **Belegbetrag** nach Rabatt — ohne Trinkgeld.
  final int zuZahlenCents;

  /// Trinkgeld; steht nicht im Belegbetrag, aber im Gegebenen.
  final int trinkgeldCents;

  /// Was der Gast tatsächlich gibt: [zuZahlenCents] + [trinkgeldCents].
  final int gesamtCents;

  /// Wird bar mit Rückgeld gerechnet?
  final bool bar;

  /// Nur bei [bar]: was gegeben wurde.
  final int? gegebenCents;

  /// Was noch fehlt; 0, solange nichts getippt wurde.
  final int fehltCents;
  final int rueckgeldCents;

  final bool bereit;
  final String? grund;
}

/// Die ganze Rechnung des Kassierens — Zwilling von `kassierenRechnung` der
/// Browser-Kasse.
///
/// **Trinkgeld erhöht, was der Gast gibt, nicht den Belegbetrag.** Der Beleg
/// trägt den Warenwert; das Trinkgeld bucht das Backend als eigene Positionen.
/// Für das Rückgeld zählt trotzdem beides zusammen — sonst bekäme der Gast sein
/// Trinkgeld als Wechselgeld zurück.
Kassierrechnung kassierrechnung(Warenkorb warenkorb, KasseSettingsBetrieb betrieb, Kassierstand stand) {
  final summe = warenkorb.summeCents;
  final rabatt = stand.rabattCents > summe ? summe : (stand.rabattCents < 0 ? 0 : stand.rabattCents);
  final zahlen = zuZahlen(warenkorb, rabatt);
  final trinkgeld = betrieb.trinkgeld && stand.trinkgeldCents > 0 ? stand.trinkgeldCents : 0;
  final gesamt = zahlen + trinkgeld;
  final bar = stand.zahlungsart == KeckPaymentMethod.cash && betrieb.rueckgeld;
  final gegeben = bar ? stand.gegebenCents : null;
  final pruefung = abschlussPruefung(
    zahlungsart: stand.zahlungsart,
    zuZahlen: gesamt,
    gegeben: stand.gegebenCents,
    rueckgeldAn: betrieb.rueckgeld,
    leer: warenkorb.istLeer,
  );
  return Kassierrechnung(
    summeCents: summe,
    rabattCents: rabatt,
    zuZahlenCents: zahlen,
    trinkgeldCents: trinkgeld,
    gesamtCents: gesamt,
    bar: bar,
    gegebenCents: gegeben,
    // Nichts getippt heißt nicht „zu wenig": der Kassier ist schlicht noch
    // nicht fertig, und dafür gibt es keine rote Meldung.
    fehltCents: bar && gegeben != null && gegeben > 0 && gegeben < gesamt ? gesamt - gegeben : 0,
    rueckgeldCents: bar && gegeben != null ? rueckgeld(gesamt, gegeben) : 0,
    bereit: pruefung.bereit,
    grund: pruefung.grund,
  );
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
    // kind 'discount': der Bon fasst die Zeilen zu einer Summenzeile mit
    // Zwischensumme zusammen, der Bericht fuehrt sie als "Rabatte"
    // (Zwilling von verteileRabatt im JS-Paket seit 0.6.42).
    zeilen.add(KasseneckItem(name: name, quantity: 1, priceCents: -anteile[i], vat: saetze[i], kind: 'discount'));
  }
  return zeilen;
}
