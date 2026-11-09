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
import 'artikel.dart';
import 'artikel_id.dart';
import 'einstellungen.dart';
import 'pfand.dart';
import 'zusaetze.dart';

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
    this.addOnOf,
    this.kind,
    this.depositTypeId,
    this.depositKind,
    this.depositOf,
    this.perUnit,
    this.ean,
    this.codes,
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

  /// Zusatz-Kacheln (11.18.0): Kennung der Hauptzeile, wenn diese Position ein
  /// Zusatz ist. Im Korb zaehlt die Kennung, nicht der Index: Loeschen,
  /// Umordnen und die Einzelzeilen-Ansicht brechen so keinen Verweis. Den Index
  /// `addOnOf` der Belegposition rechnet erst [receiptItems].
  final String? addOnOf;

  /// Pfand & Leergut: `'deposit'` bei einer abgeleiteten Pfandzeile (nur in der
  /// Vorschau von [Cart.lines], nie im Korb), `'deposit_return'` bei Leergut im
  /// Korb (negativer Einzelpreis); sonst `null`.
  final String? kind;

  /// Pfandart (nur Pfand und Leergut).
  final String? depositTypeId;

  /// `single_use` oder `reusable` (nur Pfand und Leergut).
  final String? depositKind;

  /// Nur an einer abgeleiteten Pfandzeile: Kennung der Position, zu der das
  /// Pfand gehoert. Die Zeile ist nicht aenderbar und nicht loeschbar; ihre
  /// Menge folgt der Position.
  final String? depositOf;

  /// Pfandstueck je Stueck der Position (nur Pfandzeile).
  final num? perUnit;

  /// Strichcode des Gebindes (Einweg: EWP-GTIN).
  final String? ean;

  /// Nur an Leergut: gelernte Codes (Code -> Menge); ihre Summe ist die Menge.
  final Map<String, int>? codes;

  /// Leergut im Korb („Mit Einkauf verrechnen“)?
  bool get isDepositReturn => kind == 'deposit_return';

  /// Abgeleitete Pfandzeile der Vorschau?
  bool get isDerivedDeposit => depositOf != null;

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
        addOnOf: addOnOf,
        kind: kind,
        depositTypeId: depositTypeId,
        depositKind: depositKind,
        depositOf: depositOf,
        perUnit: perUnit,
        ean: ean,
        // Gelernte Codes gelten fuer genau diese Menge.
        codes: quantity == this.quantity ? codes : null,
      );

  /// Als Belegposition – ohne die Kassen-Kennung, die das Backend nichts
  /// angeht; mit dem Artikel-Verweis, wenn es einen gibt. [addOnOf] ist der
  /// Index der Hauptposition im Beleg (setzt [receiptItems]).
  KasseneckItem toReceiptItem({int? addOnOf}) => KasseneckItem(
        name: name,
        quantity: quantity,
        priceCents: priceCents,
        vat: vat,
        articleId: articleId,
        addOnOf: addOnOf,
        kind: kind,
        depositTypeId: depositTypeId,
        depositKind: depositKind,
        perUnit: perUnit,
        ean: ean,
        codes: codes,
      );
}

/// Was der Kassier eingegeben hat, bevor daraus eine Position wird.
class CartItemDraft {
  const CartItemDraft({
    required this.name,
    required this.unitPriceCents,
    required this.vatRate,
    this.maxQuantity,
    this.articleId,
    this.addOnOf,
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

  /// Zusatz-Kacheln: Kennung der Hauptzeile im Korb, wenn die Position ein
  /// Zusatz ist; ein leerer Wert gilt als keiner.
  final String? addOnOf;
}

/// Eine Anzeigezeile des Korbs: gebuendelt (Menge × Preis) oder je Stueck einzeln.
class CartLine {
  const CartLine({required this.key, required this.item, required this.quantity, required this.amountCents});

  final String key;
  final Position item;
  final int quantity;
  final int amountCents;

  /// Abgeleitete Pfandzeile: nicht loeschbar und nicht aenderbar, ihre Menge
  /// folgt der Position darueber.
  bool get derived => item.isDerivedDeposit;

  /// Leergutzeile im Korb (negativ, mit +/- aenderbar und loeschbar).
  bool get isReturn => item.isDepositReturn;
}

/// Alles, was die Pfand-Vorschau des Korbs braucht: was der Server aus Konto,
/// Kasse und Beleg wuesste. Ohne dieses Objekt zeigt der Korb kein Pfand und
/// rechnet wie bisher ([Cart.lines], [checkoutTotals]).
class DepositPreviewContext {
  const DepositPreviewContext({
    required this.articles,
    required this.groups,
    required this.depositTypes,
    required this.day,
    this.onPremises = false,
    this.smallBusiness = false,
    this.cashRegister,
  });

  /// Artikel nach Kennung.
  final Map<String, PosArticle> articles;

  /// Artikelgruppen nach Kennung.
  final Map<String, ArticleGroup> groups;

  /// Pfandarten nach Kennung (`deposit.depositTypes`).
  final Map<String, DepositType> depositTypes;

  /// Wiener Tag des Verkaufs, `YYYY-MM-DD` ([viennaDay]).
  final String day;

  /// Vor Ort getrunken: Einweg entfaellt.
  final bool onPremises;
  final bool smallBusiness;

  /// Pfand-Angaben der Kasse; ohne Angabe nimmt sie kein Leergut zurueck.
  final CashRegisterDeposit? cashRegister;

  DepositPreviewInput get _input => DepositPreviewInput(
        auto: true,
        articles: articles,
        groups: groups,
        depositTypes: depositTypes,
        day: day,
        onPremises: onPremises,
        smallBusiness: smallBusiness,
        mayReturn: true,
        cashRegister: cashRegister,
      );
}

/// Die abgeleiteten Pfandzeilen des Korbs: je Position (Kennung) ihre Zeilen,
/// oder der Fehlercode der Vorschau ([depositPreviewErrorCodes]).
class CartDeposits {
  const CartDeposits(this.byPosition, [this.code]);

  /// Position (Kennung) -> ihre Pfandzeilen in Belegreihenfolge.
  final Map<String, List<Position>> byPosition;

  /// Ein Wert aus [depositPreviewErrorCodes], wenn der Server den Verkauf so
  /// abweisen wuerde; dann ist [byPosition] leer.
  final String? code;

  /// Alle Pfandzeilen.
  Iterable<Position> get all => byPosition.values.expand((l) => l);

  /// Summe aller Pfandzeilen in Cent.
  int get totalCents => all.fold(0, (s, p) => s + p.lineTotalCents);
}

/// Hoechstmenge einer Leergutzeile (wie der Server).
const int _maxReturnQuantity = 1000;

/// Eine Warenposition in der Leitungsform, die [withDepositLines] liest.
Map<String, Object?> _alsDraht(Position p) => {
      'name': p.name,
      'quantity': p.quantity,
      'amount': p.quantity,
      'unitPriceCents': p.priceCents,
      'priceOneCents': p.priceCents,
      'vatRate': p.vat.rate,
      'vat': p.vat.rate,
      'articleId': p.articleId,
    };

VatRate? _satzVon(num rate) => VatRate.values.where((v) => v.rate == rate).firstOrNull;

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
  ///
  /// Ein Zusatz (`draft.addOnOf`) kommt direkt hinter die Hauptzeile und ihre
  /// bisherigen Zusaetze; fehlt die Hauptzeile, wird er eine gewoehnliche
  /// Position am Ende.
  Cart added(CartItemDraft draft) {
    final name = draft.name.trim();
    if (name.isEmpty) return this;
    _laufendeNummer += 1;
    final grenze = (draft.maxQuantity != null && draft.maxQuantity! > 0) ? draft.maxQuantity : null;
    final haupt = artikelIdOderNull(draft.addOnOf);
    final hauptIndex = haupt == null ? -1 : items.indexWhere((p) => p.id == haupt);
    final neu = Position(
      id: 'p$_laufendeNummer',
      name: name,
      quantity: 1,
      priceCents: draft.unitPriceCents,
      vat: draft.vatRate,
      maxQuantity: grenze,
      articleId: artikelIdOderNull(draft.articleId),
      addOnOf: hauptIndex < 0 ? null : haupt,
    );
    if (hauptIndex < 0) return Cart(items: [...items, neu]);
    var nach = hauptIndex + 1;
    while (nach < items.length && items[nach].addOnOf == haupt) {
      nach += 1;
    }
    return Cart(items: [...items.sublist(0, nach), neu, ...items.sublist(nach)]);
  }

  /// Hat die Zeile [id] Zusaetze?
  bool hasAddOns(String id) => items.any((p) => p.addOnOf == id);

  /// Nimmt genau eine Position heraus – und mit ihr ihre Zusaetze.
  Cart removed(String id) {
    final rest = items.where((p) => p.id != id && p.addOnOf != id).toList();
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

  /// Hat der Korb Leergut („Mit Einkauf verrechnen“)?
  bool get hasReturns => items.any((p) => p.isDepositReturn);

  /// Summe der Ware in Cent, ohne Leergut.
  int get goodsCents => items.where((p) => !p.isDepositReturn).fold(0, (s, p) => s + p.lineTotalCents);

  /// Summe des Leerguts in Cent (null oder negativ).
  int get returnCents => items.where((p) => p.isDepositReturn).fold(0, (s, p) => s + p.lineTotalCents);

  /// Legt Leergut in den Korb: [quantity] Stueck der Pfandart [type] zum Betrag
  /// des Tages [day] (die Zeile baut [depositReturnLine], wie der Server sie
  /// bucht). Dieselbe Pfandart addiert sich zur vorhandenen Zeile (hoechstens
  /// 1000 Stueck je Zeile; die Summe darueber wirft einen [StateError], der
  /// Korb bleibt unveraendert, nichts wird still gekappt: jedes Stueck Leergut
  /// ist Geld); gelernte [codes] bleiben nur, wenn beide Seiten welche tragen.
  /// Wirft einen [StateError], wenn sich keine Zeile ergibt oder die Zeile
  /// ueber 1000 Stueck kaeme.
  Cart addedReturn(DepositType type, int quantity, {required String day, required bool smallBusiness, Map<String, int>? codes}) {
    final zeile = depositReturnLine(type, quantity, day: day, smallBusiness: smallBusiness, codes: codes);
    final vorhanden = items.indexWhere((p) => p.isDepositReturn && p.depositTypeId == type.id);
    if (vorhanden >= 0) {
      final alt = items[vorhanden];
      final menge = alt.quantity + quantity;
      if (menge > _maxReturnQuantity) {
        throw StateError('Leergut: hoechstens $_maxReturnQuantity Stueck je Zeile (im Korb ${alt.quantity}, dazu $quantity)');
      }
      final neueCodes = alt.codes != null && codes != null
          ? {
              ...alt.codes!,
              for (final e in codes.entries) e.key: (alt.codes![e.key] ?? 0) + e.value,
            }
          : null;
      final neu = Position(
        id: alt.id,
        name: alt.name,
        quantity: menge,
        priceCents: alt.priceCents,
        vat: alt.vat,
        maxQuantity: _maxReturnQuantity,
        kind: 'deposit_return',
        depositTypeId: alt.depositTypeId,
        depositKind: alt.depositKind,
        ean: alt.ean,
        codes: neueCodes,
      );
      return Cart(items: [...items.sublist(0, vorhanden), neu, ...items.sublist(vorhanden + 1)]);
    }
    _laufendeNummer += 1;
    return Cart(items: [
      ...items,
      Position(
        id: 'p$_laufendeNummer',
        name: zeile.name,
        quantity: zeile.quantity,
        priceCents: zeile.priceCents,
        vat: zeile.vat,
        maxQuantity: _maxReturnQuantity,
        kind: 'deposit_return',
        depositTypeId: zeile.depositTypeId,
        depositKind: zeile.depositKind,
        ean: zeile.ean,
        codes: zeile.codes,
      ),
    ]);
  }

  /// Die Pfandzeilen der Positionen, wie der Server sie aus Artikel, Gruppe,
  /// Tag und Ort ableitet ([withDepositLines] mit `autoDeposits`). Eine Zeile
  /// gehoert ihrer Position: Menge folgt, Loeschen der Position loescht sie, die
  /// Zeile selbst ist nicht aenderbar. Leergut im Korb ist keine Ableitung.
  /// Meldet der Server den Verkauf ab (etwa eine Pfandart ohne Betrag am Tag),
  /// steht der Code in [CartDeposits.code].
  CartDeposits deposits(DepositPreviewContext context) {
    final je = <String, List<Position>>{};
    for (final p in items) {
      if (p.isDepositReturn || p.articleId == null) continue;
      final r = withDepositLines([_alsDraht(p)], context._input);
      if (!r.ok) return CartDeposits(const {}, r.code);
      final zeilen = r.items!.skip(1).whereType<Map>().toList();
      if (zeilen.isEmpty) continue;
      final aus = <Position>[];
      for (var k = 0; k < zeilen.length; k++) {
        final z = zeilen[k];
        final vat = _satzVon(z['vatRate'] as num);
        if (vat == null) return const CartDeposits({}, 'invalid_deposit');
        aus.add(Position(
          id: '${p.id}~pfand$k',
          name: z['name'] as String,
          quantity: z['quantity'] as int,
          priceCents: z['unitPriceCents'] as int,
          vat: vat,
          kind: 'deposit',
          depositTypeId: z['depositTypeId'] as String?,
          depositKind: z['depositKind'] as String?,
          depositOf: p.id,
          perUnit: z['perUnit'] as num?,
          ean: z['ean'] as String?,
        ));
      }
      je[p.id] = aus;
    }
    return CartDeposits(je);
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
  /// Positionen in eine Zeile je Stueck zum Einzelpreis auf. Zusaetze stehen
  /// direkt hinter ihrer Hauptzeile.
  ///
  /// Mit [deposit] erscheint das Pfand (npm 1.32.0) als abgeleitete Unterzeile
  /// direkt unter seiner Position, nach deren Zusaetzen ([CartLine.derived]).
  /// Ohne bleibt alles wie bisher.
  List<CartLine> lines(PosQuantity mode, {DepositPreviewContext? deposit}) {
    var geordnet = [for (final z in orderAddOnLines(items, idOf: (p) => p.id, parentOf: (p) => p.addOnOf)) z.line];
    if (deposit != null) {
      final pfand = deposits(deposit).byPosition;
      if (pfand.isNotEmpty) {
        final mit = <Position>[];
        final offen = <Position>[];
        for (final p in geordnet) {
          if (p.addOnOf == null) {
            mit.addAll(offen);
            offen.clear();
            mit.add(p);
            offen.addAll(pfand[p.id] ?? const []);
          } else {
            mit.add(p);
            // Der Zusatz traegt sein eigenes Pfand direkt unter sich.
            mit.addAll(pfand[p.id] ?? const []);
          }
        }
        mit.addAll(offen);
        geordnet = mit;
      }
    }
    if (mode != PosQuantity.off) {
      return geordnet
          .map((p) => CartLine(key: p.id, item: p, quantity: p.quantity, amountCents: p.lineTotalCents))
          .toList();
    }
    return [
      for (final p in geordnet)
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
