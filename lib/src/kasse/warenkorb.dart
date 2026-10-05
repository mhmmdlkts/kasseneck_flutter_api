/// Der laufende Verkauf: Positionen erfassen, aendern, zusammenzaehlen.
///
/// Zwilling von `lib/warenkorb.ts` der Browser-Kasse. Zwei Entscheidungen
/// tragen die ganze Datei:
///
/// **1. Jeder Betrag ist eine ganze Zahl in Cent.** Von der Eingabe bis zur
/// Summe, ohne einen einzigen Zwischenschritt in Euro. Ein Euro-Betrag als
/// Fliesskommazahl faellt beim Hinsehen nicht auf (0.33 sieht aus wie 33 Cent) —
/// er faellt auf, wenn drei davon zusammenkommen: `3 * 0.33` ist
/// `0.9899999999999999`, und je nach Rundung steht auf dem Beleg ein Cent zu
/// wenig. Deshalb liest auch [parseAmountCents] die Eingabe ueber die Ziffern.
///
/// **2. Der Steuersatz wird nur durchgereicht.** An [VatRate] haengt der
/// RKSV-Kategoriebuchstabe (A/B/C/D/E/G), und der haengt an der Signaturkette
/// des Backends. Hier wird er weder nachgebaut noch umbenannt.
library;

import '../../enums/vat_rate.dart';
import '../../models/kasseneck_item.dart';
import 'artikel_id.dart';
import 'einstellungen.dart';

/// Eine Position des laufenden Verkaufs.
class Position {
  const Position({
    required this.id,
    required this.name,
    required this.quantity,
    required this.priceCents,
    required this.vat,
    this.maxQuantity,
    this.articleId,
  });

  /// Kennung nur fuer diesen Bildschirm: zwei gleich aussehende Positionen sind
  /// zwei Positionen, und ohne eigene Kennung entfernte ein Griff beide. Sie
  /// verlaesst die Kasse nie — die Nutzlast des Belegs kennt sie nicht.
  final String id;
  final String name;
  final int quantity;

  /// Einzelpreis in ganzen Cent.
  final int priceCents;
  final VatRate vat;

  /// Hoechstmenge je Beleg (vom Artikel); fehlt bei freien Positionen.
  final int? maxQuantity;

  /// Artikel-Verweis (Kachel); fehlt bei freien Positionen. Reist in die
  /// Belegposition (Erloesgruppen im Bericht, Lagerbuchung).
  final String? articleId;

  /// Zeilensumme in ganzen Cent — beide Faktoren sind ganze Zahlen.
  int get lineTotalCents => priceCents * quantity;

  Position withQuantity(int quantity) => Position(
        id: id,
        name: name,
        quantity: quantity,
        priceCents: priceCents,
        vat: vat,
        maxQuantity: maxQuantity,
        articleId: articleId,
      );

  /// Als Belegposition – ohne die Kassen-Kennung, die das Backend nichts
  /// angeht; mit dem Artikel-Verweis, wenn es einen gibt.
  KasseneckItem toReceiptItem() =>
      KasseneckItem(name: name, quantity: quantity, priceCents: priceCents, vat: vat, articleId: articleId);
}

/// Was der Kassier eingegeben hat, bevor daraus eine Position wird.
class CartItemDraft {
  const CartItemDraft({
    required this.name,
    required this.unitPriceCents,
    required this.vatRate,
    this.maxQuantity,
    this.articleId,
  });

  /// Pflicht. § 132a BAO verlangt die handelsuebliche Bezeichnung auf dem Beleg.
  final String name;

  /// Einzelpreis in ganzen Cent.
  final int unitPriceCents;
  final VatRate vatRate;

  /// Hoechstmenge je Beleg (Artikel); die Menge im Korb geht nie darueber.
  final int? maxQuantity;

  /// Artikel-Verweis (Kachel); fehlt bei freien Positionen. Ein leerer Wert
  /// gilt als keiner.
  final String? articleId;
}

/// Eine Anzeigezeile des Korbs: gebuendelt (Menge × Preis) oder je Stueck einzeln.
class CartLine {
  const CartLine({required this.key, required this.item, required this.quantity, required this.amountCents});

  final String key;
  final Position item;
  final int quantity;
  final int amountCents;
}

/// Fortlaufende Nummer fuer die Kennung — sie braucht nur Eindeutigkeit
/// innerhalb dieser Sitzung.
int _laufendeNummer = 0;

class Cart {
  const Cart({required this.items});

  /// Ein Verkauf, an dem noch nichts erfasst ist.
  const Cart.empty() : items = const [];

  final List<Position> items;

  int get totalCents => items.fold(0, (s, p) => s + p.lineTotalCents);

  bool get isEmpty => items.isEmpty;

  /// Legt eine Position mit Menge 1 an.
  ///
  /// Ohne Bezeichnung bleibt der Korb **unveraendert** (derselbe Wert): das
  /// Backend weist eine namenlose Position ohnehin ab. Den Grund nennt der
  /// Bildschirm, bevor der Kassier drueckt — hier steht nur die letzte Grenze.
  Cart added(CartItemDraft draft) {
    final name = draft.name.trim();
    if (name.isEmpty) return this;
    _laufendeNummer += 1;
    final grenze = (draft.maxQuantity != null && draft.maxQuantity! > 0) ? draft.maxQuantity : null;
    return Cart(items: [
      ...items,
      Position(
        id: 'p$_laufendeNummer',
        name: name,
        quantity: 1,
        priceCents: draft.unitPriceCents,
        vat: draft.vatRate,
        maxQuantity: grenze,
        articleId: artikelIdOderNull(draft.articleId),
      ),
    ]);
  }

  /// Nimmt genau eine Position heraus.
  Cart removed(String id) {
    final rest = items.where((p) => p.id != id).toList();
    // Unveraendert heisst unveraendert: derselbe Wert, damit oben niemand ohne
    // Grund neu zeichnet.
    return rest.length == items.length ? this : Cart(items: rest);
  }

  /// Setzt die Menge einer Position.
  ///
  /// Faellt sie auf null, faellt die Position: eine Zeile „0 × Kaffee" waere weder
  /// auf dem Schirm noch auf dem Beleg etwas wert.
  Cart withQuantity(String id, int quantity) {
    if (quantity <= 0) return removed(id);
    var getroffen = false;
    final neu = items.map((p) {
      if (p.id != id) return p;
      getroffen = true;
      // Hoechstmenge je Beleg: darueber geht es nicht — egal woher der Griff kommt.
      final grenze = (p.maxQuantity != null && p.maxQuantity! > 0) ? p.maxQuantity! : null;
      return p.withQuantity(grenze != null && quantity > grenze ? grenze : quantity);
    }).toList();
    return getroffen ? Cart(items: neu) : this;
  }

  /// Zieht die verkauften Positionen ab.
  ///
  /// Gebraucht, weil der Abschluss **dauert** (Signatur, DEP) und die Erfassung
  /// dabei offen bleibt: der naechste Gast steht schon da. Im Augenblick der
  /// Antwort kann der Korb deshalb mehr enthalten, als der Beleg ausweist — ihn
  /// dann pauschal zu leeren hiesse, diese Position spurlos zu verlieren: nicht
  /// berechnet, auf keinem Beleg, nicht mehr auffindbar.
  ///
  /// Abgezogen wird nach Kennung **und** Menge: wurden zwei von drei Kaffee
  /// verkauft, bleibt einer stehen.
  Cart subtracted(Cart sold) {
    final mengen = <String, int>{};
    for (final p in sold.items) {
      mengen[p.id] = (mengen[p.id] ?? 0) + p.quantity;
    }
    final rest = <Position>[];
    for (final p in items) {
      final bleibt = p.quantity - (mengen[p.id] ?? 0);
      if (bleibt <= 0) continue;
      rest.add(bleibt == p.quantity ? p : p.withQuantity(bleibt));
    }
    return Cart(items: rest);
  }

  /// Zeilen fuer die Anzeige je Mengenmodus: [PosQuantity.off] loest gebuendelte
  /// Positionen in eine Zeile je Stueck zum Einzelpreis auf.
  List<CartLine> lines(PosQuantity mode) {
    if (mode != PosQuantity.off) {
      return items
          .map((p) => CartLine(key: p.id, item: p, quantity: p.quantity, amountCents: p.lineTotalCents))
          .toList();
    }
    return [
      for (final p in items)
        for (var i = 0; i < (p.quantity < 1 ? 1 : p.quantity); i++)
          CartLine(key: '${p.id}#$i', item: p, quantity: 1, amountCents: p.priceCents),
    ];
  }
}

/// Die Steuersaetze zur Wahl — haeufige zuerst.
const List<VatRate> vatRateChoices = [
  VatRate.vat20,
  VatRate.vat19,
  VatRate.vat13,
  VatRate.vat10,
  VatRate.vat4_9,
  VatRate.vat0,
];

/// Der uebliche Fall am Tresen.
const VatRate defaultVatRate = VatRate.vat20;

/// Obergrenze je Position: 100.000,00 €.
///
/// Sie haengt daran, dass hier in **Euro** getippt wird: wer von einer
/// Cent-Kasse kommt, tippt „1250" fuer 12,50 € — und bekaeme ohne Deckel
/// 1250,00 € auf einen unveraenderlichen Beleg. Der Deckel faengt den groben Fall
/// ab, nicht den knappen.
const int maxAmountCents = 10000000;

/// Betrag aus dem Eingabefeld in ganzen Cent — oder `null`.
///
/// Gelesen wird ueber die Ziffern, ausdruecklich nicht ueber eine Fliesskommazahl
/// mit anschliessender Multiplikation. Komma und Punkt sind beide zugelassen
/// (auf einer Bildschirmtastatur liegt oft nur eines davon). Abgewiesen wird
/// alles andere, insbesondere **drei Nachkommastellen** (eine falsche Eingabe,
/// keine Aufforderung zum Runden — wer hier rundete, entschiede am Kassier
/// vorbei ueber Geld) und **0,00 oder negativ** (ein Nullbeleg entsteht nicht
/// hier, und ein Storno ist eine eigene Handlung mit eigenem Beleg) sowie
/// alles ueber [maxAmountCents] – der Deckel, den der Kommentar dort seit
/// jeher beschreibt und den bis hierher niemand pruefte.
int? parseAmountCents(String text) {
  final treffer = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(text.trim());
  if (treffer == null) return null;
  final ganzeText = treffer.group(1)!;
  // Mehr Stellen, als der Deckel je zulaesst: hier warf `int.parse` ab 19
  // Ziffern eine `FormatException`, statt wie zugesagt `null` zu liefern —
  // erreichbar ueber eine haengende Taste oder eine eingefuegte Zeichenkette.
  if (ganzeText.length > 9) return null;
  final ganze = int.parse(ganzeText);
  // Auf zwei Stellen aufgefuellt: „4,5" sind 50 Cent und nicht 5.
  final nachkommaText = (treffer.group(2) ?? '').padRight(2, '0');
  final nachkomma = nachkommaText.isEmpty ? 0 : int.parse(nachkommaText);
  final cents = ganze * 100 + nachkomma;
  if (cents <= 0 || cents > maxAmountCents) return null;
  return cents;
}

/// Betrag fuer den Schirm: „2,50 €".
///
/// Aus den Ziffern zusammengesetzt und nicht ueber eine Zahlenformatierung: die
/// Cent stehen bereits als ganze Zahl da, es gibt nichts zu formatieren, was
/// eine Division nicht wieder unscharf machen wuerde.
String formatEuro(int cents) {
  final negativ = cents < 0;
  final ziffern = cents.abs().toString().padLeft(3, '0');
  final ganze = ziffern.substring(0, ziffern.length - 2);
  final rest = ziffern.substring(ziffern.length - 2);
  return '${negativ ? '-' : ''}${_mitTausenderpunkt(ganze)},$rest €';
}

/// Punkt je drei Stellen — „100000" wird zu „100.000". An der Kasse selten,
/// aber genau dort, wo es vorkommt, zaehlt es: „100000,00 €" laesst sich nicht
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
String formatVatRate(VatRate rate) {
  final zahl = rate.rate;
  final text = zahl == zahl.roundToDouble() ? zahl.toInt().toString() : zahl.toString();
  return '${text.replaceAll('.', ',')} %';
}
