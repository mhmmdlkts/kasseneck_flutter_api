/// Der laufende Verkauf: Positionen erfassen, ändern, zusammenzählen.
///
/// Zwilling von `lib/warenkorb.ts` der Browser-Kasse. Zwei Entscheidungen
/// tragen die ganze Datei:
///
/// **1. Jeder Betrag ist eine ganze Zahl in Cent.** Von der Eingabe bis zur
/// Summe, ohne einen einzigen Zwischenschritt in Euro. Ein Euro-Betrag als
/// Fließkommazahl fällt beim Hinsehen nicht auf (0.33 sieht aus wie 33 Cent) —
/// er fällt auf, wenn drei davon zusammenkommen: `3 * 0.33` ist
/// `0.9899999999999999`, und je nach Rundung steht auf dem Beleg ein Cent zu
/// wenig. Deshalb liest auch [betragAusText] die Eingabe über die Ziffern.
///
/// **2. Der Steuersatz wird nur durchgereicht.** An [VatRate] hängt der
/// RKSV-Kategoriebuchstabe (A/B/C/D/E/G), und der hängt an der Signaturkette
/// des Backends. Hier wird er weder nachgebaut noch umbenannt.
library;

import '../../enums/vat_rate.dart';
import '../../models/kasseneck_item.dart';
import 'einstellungen.dart';

/// Eine Position des laufenden Verkaufs.
class Position {
  const Position({
    required this.id,
    required this.name,
    required this.quantity,
    required this.priceCents,
    required this.vat,
    this.maxMenge,
  });

  /// Kennung nur für diesen Bildschirm: zwei gleich aussehende Positionen sind
  /// zwei Positionen, und ohne eigene Kennung entfernte ein Griff beide. Sie
  /// verlässt die Kasse nie — die Nutzlast des Belegs kennt sie nicht.
  final String id;
  final String name;
  final int quantity;

  /// Einzelpreis in ganzen Cent.
  final int priceCents;
  final VatRate vat;

  /// Höchstmenge je Beleg (vom Artikel); fehlt bei freien Positionen.
  final int? maxMenge;

  /// Zeilensumme in ganzen Cent — beide Faktoren sind ganze Zahlen.
  int get zeilensummeCents => priceCents * quantity;

  Position mitMenge(int menge) => Position(
        id: id,
        name: name,
        quantity: menge,
        priceCents: priceCents,
        vat: vat,
        maxMenge: maxMenge,
      );

  /// Als Belegposition — ohne die Kassen-Kennung, die das Backend nichts angeht.
  KasseneckItem alsBelegposition() =>
      KasseneckItem(name: name, quantity: quantity, priceCents: priceCents, vat: vat);
}

/// Was der Kassier eingegeben hat, bevor daraus eine Position wird.
class Positionsentwurf {
  const Positionsentwurf({
    required this.bezeichnung,
    required this.betragCents,
    required this.steuersatz,
    this.maxMenge,
  });

  /// Pflicht. § 132a BAO verlangt die handelsübliche Bezeichnung auf dem Beleg.
  final String bezeichnung;

  /// Einzelpreis in ganzen Cent.
  final int betragCents;
  final VatRate steuersatz;

  /// Höchstmenge je Beleg (Artikel); die Menge im Korb geht nie darüber.
  final int? maxMenge;
}

/// Eine Anzeigezeile des Korbs: gebündelt (Menge × Preis) oder je Stück einzeln.
class Korbzeile {
  const Korbzeile({required this.key, required this.position, required this.menge, required this.betragCents});

  final String key;
  final Position position;
  final int menge;
  final int betragCents;
}

/// Fortlaufende Nummer für die Kennung — sie braucht nur Eindeutigkeit
/// innerhalb dieser Sitzung.
int _laufendeNummer = 0;

class Warenkorb {
  const Warenkorb({required this.positionen});

  /// Ein Verkauf, an dem noch nichts erfasst ist.
  const Warenkorb.leer() : positionen = const [];

  final List<Position> positionen;

  int get summeCents => positionen.fold(0, (s, p) => s + p.zeilensummeCents);

  bool get istLeer => positionen.isEmpty;

  /// Legt eine Position mit Menge 1 an.
  ///
  /// Ohne Bezeichnung bleibt der Korb **unverändert** (derselbe Wert): das
  /// Backend weist eine namenlose Position ohnehin ab. Den Grund nennt der
  /// Bildschirm, bevor der Kassier drückt — hier steht nur die letzte Grenze.
  Warenkorb hinzugefuegt(Positionsentwurf entwurf) {
    final name = entwurf.bezeichnung.trim();
    if (name.isEmpty) return this;
    _laufendeNummer += 1;
    final grenze = (entwurf.maxMenge != null && entwurf.maxMenge! > 0) ? entwurf.maxMenge : null;
    return Warenkorb(positionen: [
      ...positionen,
      Position(
        id: 'p$_laufendeNummer',
        name: name,
        quantity: 1,
        priceCents: entwurf.betragCents,
        vat: entwurf.steuersatz,
        maxMenge: grenze,
      ),
    ]);
  }

  /// Nimmt genau eine Position heraus.
  Warenkorb entfernt(String id) {
    final rest = positionen.where((p) => p.id != id).toList();
    // Unverändert heißt unverändert: derselbe Wert, damit oben niemand ohne
    // Grund neu zeichnet.
    return rest.length == positionen.length ? this : Warenkorb(positionen: rest);
  }

  /// Setzt die Menge einer Position.
  ///
  /// Fällt sie auf null, fällt die Position: eine Zeile „0 × Kaffee" wäre weder
  /// auf dem Schirm noch auf dem Beleg etwas wert.
  Warenkorb mengeGesetzt(String id, int menge) {
    if (menge <= 0) return entfernt(id);
    var getroffen = false;
    final neu = positionen.map((p) {
      if (p.id != id) return p;
      getroffen = true;
      // Höchstmenge je Beleg: darüber geht es nicht — egal woher der Griff kommt.
      final grenze = (p.maxMenge != null && p.maxMenge! > 0) ? p.maxMenge! : null;
      return p.mitMenge(grenze != null && menge > grenze ? grenze : menge);
    }).toList();
    return getroffen ? Warenkorb(positionen: neu) : this;
  }

  /// Zieht die verkauften Positionen ab.
  ///
  /// Gebraucht, weil der Abschluss **dauert** (Signatur, DEP) und die Erfassung
  /// dabei offen bleibt: der nächste Gast steht schon da. Im Augenblick der
  /// Antwort kann der Korb deshalb mehr enthalten, als der Beleg ausweist — ihn
  /// dann pauschal zu leeren hieße, diese Position spurlos zu verlieren: nicht
  /// berechnet, auf keinem Beleg, nicht mehr auffindbar.
  ///
  /// Abgezogen wird nach Kennung **und** Menge: wurden zwei von drei Kaffee
  /// verkauft, bleibt einer stehen.
  Warenkorb abgezogen(Warenkorb verkauft) {
    final mengen = <String, int>{};
    for (final p in verkauft.positionen) {
      mengen[p.id] = (mengen[p.id] ?? 0) + p.quantity;
    }
    final rest = <Position>[];
    for (final p in positionen) {
      final bleibt = p.quantity - (mengen[p.id] ?? 0);
      if (bleibt <= 0) continue;
      rest.add(bleibt == p.quantity ? p : p.mitMenge(bleibt));
    }
    return Warenkorb(positionen: rest);
  }

  /// Zeilen für die Anzeige je Mengenmodus: [KasseMenge.aus] löst gebündelte
  /// Positionen in eine Zeile je Stück zum Einzelpreis auf.
  List<Korbzeile> zeilen(KasseMenge modus) {
    if (modus != KasseMenge.aus) {
      return positionen
          .map((p) => Korbzeile(key: p.id, position: p, menge: p.quantity, betragCents: p.zeilensummeCents))
          .toList();
    }
    return [
      for (final p in positionen)
        for (var i = 0; i < (p.quantity < 1 ? 1 : p.quantity); i++)
          Korbzeile(key: '${p.id}#$i', position: p, menge: 1, betragCents: p.priceCents),
    ];
  }
}

/// Die Steuersätze zur Wahl — häufige zuerst.
const List<VatRate> steuersaetze = [
  VatRate.vat20,
  VatRate.vat19,
  VatRate.vat13,
  VatRate.vat10,
  VatRate.vat4komma9,
  VatRate.vat0,
];

/// Der übliche Fall am Tresen.
const VatRate vorgabeSteuersatz = VatRate.vat20;

/// Obergrenze je Position: 100.000,00 €.
///
/// Sie hängt daran, dass hier in **Euro** getippt wird: wer von einer
/// Cent-Kasse kommt, tippt „1250" für 12,50 € — und bekäme ohne Deckel
/// 1250,00 € auf einen unveränderlichen Beleg. Der Deckel fängt den groben Fall
/// ab, nicht den knappen.
const int hoechstbetragCent = 10000000;

/// Betrag aus dem Eingabefeld in ganzen Cent — oder `null`.
///
/// Gelesen wird über die Ziffern, ausdrücklich nicht über eine Fließkommazahl
/// mit anschließender Multiplikation. Komma und Punkt sind beide zugelassen
/// (auf einer Bildschirmtastatur liegt oft nur eines davon). Abgewiesen wird
/// alles andere, insbesondere **drei Nachkommastellen** (eine falsche Eingabe,
/// keine Aufforderung zum Runden — wer hier rundete, entschiede am Kassier
/// vorbei über Geld) und **0,00 oder negativ** (ein Nullbeleg entsteht nicht
/// hier, und ein Storno ist eine eigene Handlung mit eigenem Beleg) sowie
/// alles über [hoechstbetragCent] — der Deckel, den der Kommentar dort seit
/// jeher beschreibt und den bis hierher niemand prüfte.
int? betragAusText(String text) {
  final treffer = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(text.trim());
  if (treffer == null) return null;
  final ganzeText = treffer.group(1)!;
  // Mehr Stellen, als der Deckel je zulässt: hier warf `int.parse` ab 19
  // Ziffern eine `FormatException`, statt wie zugesagt `null` zu liefern —
  // erreichbar über eine hängende Taste oder eine eingefügte Zeichenkette.
  if (ganzeText.length > 9) return null;
  final ganze = int.parse(ganzeText);
  // Auf zwei Stellen aufgefüllt: „4,5" sind 50 Cent und nicht 5.
  final nachkommaText = (treffer.group(2) ?? '').padRight(2, '0');
  final nachkomma = nachkommaText.isEmpty ? 0 : int.parse(nachkommaText);
  final cents = ganze * 100 + nachkomma;
  if (cents <= 0 || cents > hoechstbetragCent) return null;
  return cents;
}

/// Betrag für den Schirm: „2,50 €".
///
/// Aus den Ziffern zusammengesetzt und nicht über eine Zahlenformatierung: die
/// Cent stehen bereits als ganze Zahl da, es gibt nichts zu formatieren, was
/// eine Division nicht wieder unscharf machen würde.
String alsEuro(int cents) {
  final negativ = cents < 0;
  final ziffern = cents.abs().toString().padLeft(3, '0');
  final ganze = ziffern.substring(0, ziffern.length - 2);
  final rest = ziffern.substring(ziffern.length - 2);
  return '${negativ ? '-' : ''}${_mitTausenderpunkt(ganze)},$rest €';
}

/// Punkt je drei Stellen — „100000" wird zu „100.000". An der Kasse selten,
/// aber genau dort, wo es vorkommt, zählt es: „100000,00 €" lässt sich nicht
/// auf einen Blick von „10000,00 €" unterscheiden.
String _mitTausenderpunkt(String ganze) {
  final puffer = StringBuffer();
  for (var stelle = 0; stelle < ganze.length; stelle++) {
    final vonHinten = ganze.length - stelle;
    if (stelle > 0 && vonHinten % 3 == 0) puffer.write('.');
    puffer.write(ganze[stelle]);
  }
  return puffer.toString();
}

/// Beschriftung eines Steuersatzes, wie sie am Tresen gelesen wird.
String steuersatzText(VatRate satz) {
  final zahl = satz.rate;
  final text = zahl == zahl.roundToDouble() ? zahl.toInt().toString() : zahl.toString();
  return '${text.replaceAll('.', ',')} %';
}
