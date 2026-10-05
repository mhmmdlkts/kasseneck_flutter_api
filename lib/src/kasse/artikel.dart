/// Artikelgruppen und Artikel in der Form, die die Kachel-Kasse braucht —
/// Zwilling von `kasse/artikel.ts` im JS-Paket (Backend:
/// `article-endpoints.js`).
library;

/// Kategorie der Kachel-Kasse.
class ArticleGroup {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'id', 'name', 'color', 'symbol', 'sort', 'vatRate'};

  const ArticleGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.sort,
    this.symbol,
    this.vatRate,
  });

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String color;

  /// Kategorie-Symbol (Emoji, höchstens zwei Zeichen) oder `null`.
  final String? symbol;
  final int sort;

  /// Vorschlag der Gruppe; der Artikel entscheidet.
  final num? vatRate;

  factory ArticleGroup.fromJson(Map<String, dynamic> json) => ArticleGroup(
        id: json['id'] is String ? json['id'] as String : '',
        name: json['name'] is String ? json['name'] as String : '',
        color: json['color'] is String ? json['color'] as String : '#6B7280',
        symbol: json['symbol'] is String ? json['symbol'] as String : null,
        sort: json['sort'] is num ? (json['sort'] as num).toInt() : 0,
        vatRate: json['vatRate'] is num ? json['vatRate'] as num : null,
      );

  /// Zurück in die Form, aus der [ArticleGroup.fromJson] wieder liest – für
  /// Zwischenspeicher, nicht fürs Backend.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'symbol': symbol,
        'sort': sort,
        'vatRate': vatRate,
      };
}

/// Mengenregel eines Artikels.
///
/// [piece] = ganze Stück (1, 2, 3 …), [decimal] = Kommamenge in der Einheit
/// (0,250 kg; 1,5 m); der Name ist der Wert am Draht (`quantityRule`).
/// **Beleg und DEP bleiben ganzzahlig:** eine Kommamenge wird als EINE
/// Position mit ausgerechnetem Betrag gebucht, und die Bezeichnung trägt die
/// Menge („Wurst 0,250 kg").
enum QuantityRule { piece, decimal }

/// Die Werte von `quantityRule` (Katalog `MENGENREGEL`).
const List<String> quantityRules = ['piece', 'decimal'];

class QuantityDefaults {
  const QuantityDefaults({required this.rule, required this.ask, required this.decimals});

  final QuantityRule rule;

  /// Die Kasse fragt beim Antippen nach der Menge (Wurst nach Gewicht: ja;
  /// Semmel: nein).
  final bool ask;

  /// Nachkommastellen bei [QuantityRule.decimal].
  final int decimals;
}

/// Einheiten, die nach Menge verkauft werden.
const Map<String, int> _dezimalEinheiten = {
  'kg': 3, 'g': 0, 'l': 2, 'ml': 0, 'm': 2, 'lfm': 2, 'km': 1,
  'm²': 2, 'm2': 2, 'm³': 3, 'm3': 3, 'std': 2, 'h': 2, 'min': 0, 't': 3,
};

/// Vorgabe je Einheit — was der Betrieb bei einem neuen Artikel bekommt und
/// ändern darf.
QuantityDefaults quantityRuleForUnit(String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  final stellen = _dezimalEinheiten[u];
  if (stellen == null) return const QuantityDefaults(rule: QuantityRule.piece, ask: false, decimals: 0);
  // g, ml, min: ganze Zahl, aber die Menge wird gefragt.
  if (stellen == 0) return const QuantityDefaults(rule: QuantityRule.piece, ask: true, decimals: 0);
  return QuantityDefaults(rule: QuantityRule.decimal, ask: true, decimals: stellen);
}

/// Wirksame Regel eines Artikels: die gespeicherte Angabe schlägt die Vorgabe
/// der Einheit.
QuantityDefaults quantityDefaults(PosArticle a) {
  final v = quantityRuleForUnit(a.unit);
  final regel = a.quantityRule ?? v.rule;
  return QuantityDefaults(
    rule: regel,
    ask: a.askQuantity ?? v.ask,
    decimals: regel == QuantityRule.decimal ? (v.decimals < 1 ? 2 : v.decimals) : 0,
  );
}

/// Artikel, wie ihn die Kasse für Kacheln und Belegpositionen braucht.
class PosArticle {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'id', 'name', 'unitPriceCents', 'vatRate', 'unit', 'groupId', 'revenueGroupId', 'tile', 'active', 'quantityRule', 'askQuantity', 'maxQuantity', 'stockLocationIds', 'number', 'ean', 'internalCode', 'stockTracked'};

  /// Die Felder von `tile`.
  static const Set<String> tileFields = {'visible', 'sort'};

  const PosArticle({
    required this.id,
    required this.name,
    required this.unit,
    required this.visible,
    required this.sort,
    required this.active,
    this.unitPriceCents,
    this.vatRate,
    this.groupId,
    this.revenueGroupId,
    this.quantityRule,
    this.askQuantity,
    this.maxQuantity,
    this.stockLocationIds,
    this.number,
    this.ean,
    this.internalCode,
    this.stockTracked,
  });

  final String id;
  final String name;

  /// Einzelpreis in ganzen Cent; `null` = kein Preis hinterlegt.
  final int? unitPriceCents;

  /// Steuersatz in Prozent, roh; `null` = keiner hinterlegt.
  final num? vatRate;

  final String unit;
  final String? groupId;

  /// Erlösgruppe (Buchhaltung, Draht `revenueGroupId`); `null` = keine.
  final String? revenueGroupId;

  /// Im Panel für die Kasse freigegeben.
  final bool visible;
  final int sort;
  final bool active;

  /// Gespeicherte Mengenregel; `null` = Vorgabe der Einheit.
  final QuantityRule? quantityRule;

  /// Gespeichert: Kasse fragt nach der Menge; `null` = Vorgabe der Einheit.
  final bool? askQuantity;

  /// Höchstmenge je Beleg; `null` = keine Grenze.
  final num? maxQuantity;

  /// Standorte, an denen der Artikel gefuehrt wird (Lager); `null`, wenn der
  /// Artikel keine Angabe traegt. Wie die Kasse daraus Kacheln filtert,
  /// entscheidet die Oberflaeche.
  final List<String>? stockLocationIds;

  /// Artikelnummer des Betriebs; `null` = keine. Diese und die beiden
  /// folgenden Texte (Scanner-Suche) kommen unveraendert durch (fuehrende
  /// Nullen, Schreibweise, Leerraum); nur ein leerer Text (auch reiner
  /// Leerraum) oder ein anderer Typ wird `null`.
  final String? number;

  /// EAN/GTIN, wie gespeichert; `null` = keine.
  final String? ean;

  /// Interner Code des Betriebs (eigener Barcode/QR); `null` = keiner.
  final String? internalCode;

  /// Bestandsgefuehrt (Lager-Modul). `null`, wenn die Antwort keine Angabe
  /// traegt (aeltere Backends) – dann nicht aus anderen Feldern ableiten.
  final bool? stockTracked;

  /// Aus der Drahtform `/api/v3` (`tile {visible, sort}`, `quantityRule`,
  /// `askQuantity`, `maxQuantity`, `revenueGroupId`, `stockLocationIds`,
  /// `number`, `ean`, `internalCode`, `stockTracked`).
  ///
  /// Liest auch einen **Zwischenspeicher der Version 9.x** (`kasse
  /// {sichtbar, sort}`, `quantityRule stueck|dezimal`, `askQuantity`,
  /// `maxQuantity`, so schrieb `toJson` bis 9.x): nach dem Update gehen die
  /// Kacheln des letzten Stands nicht verloren.
  factory PosArticle.fromJson(Map<String, dynamic> json) {
    final alt = !json.containsKey('tile') && json.containsKey('kasse');
    final kachel = json[alt ? 'kasse' : 'tile'];
    final regel = json[alt ? 'mengenregel' : 'quantityRule'];
    final fragen = json[alt ? 'mengeFragen' : 'askQuantity'];
    final grenze = json[alt ? 'maxMenge' : 'maxQuantity'];
    final erloes = json['revenueGroupId'];
    final standorte = json['stockLocationIds'];
    return PosArticle(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      // round, nicht toInt: das Backend rechnet den Preis in JavaScript aus
      // Euro hoch, und 19.99 * 100 ergibt dort 1998.9999999999998 -- ein
      // abgeschnittener Wert verkaufte den Artikel dauerhaft einen Cent zu
      // billig, und zwar auf einen signierten Beleg. Alle Schwesterstellen
      // (kasseneck_item, keck_voucher, keck_invoice_item, belege) runden.
      unitPriceCents: json['unitPriceCents'] is num ? (json['unitPriceCents'] as num).round() : null,
      vatRate: json['vatRate'] is num ? json['vatRate'] as num : null,
      unit: json['unit'] is String ? json['unit'] as String : '',
      groupId: json['groupId'] is String ? json['groupId'] as String : null,
      revenueGroupId: erloes is String && erloes.isNotEmpty ? erloes : null,
      // Fehlt die Angabe, ist der Artikel sichtbar: ein Betrieb, der nie
      // etwas eingestellt hat, soll seine Artikel trotzdem sehen.
      visible: kachel is Map ? kachel[alt ? 'sichtbar' : 'visible'] != false : true,
      sort: kachel is Map && kachel['sort'] is num ? (kachel['sort'] as num).toInt() : 0,
      active: json['active'] != false,
      quantityRule: switch (regel) {
        'piece' || 'stueck' => QuantityRule.piece,
        'decimal' || 'dezimal' => QuantityRule.decimal,
        _ => null,
      },
      askQuantity: fragen is bool ? fragen : null,
      maxQuantity: grenze is num && grenze.isFinite && grenze > 0 ? grenze : null,
      // Leere und fremde Eintraege fallen heraus wie im JS-Zwilling; eine
      // leere Liste bleibt leer und wird nicht zu null.
      stockLocationIds: standorte is List ? [for (final s in standorte) if (s is String && s.isNotEmpty) s] : null,
      number: _textOderNull(json['number']),
      ean: _textOderNull(json['ean']),
      internalCode: _textOderNull(json['internalCode']),
      stockTracked: json['stockTracked'] is bool ? json['stockTracked'] as bool : null,
    );
  }

  /// Zurück in die Drahtform, aus der [PosArticle.fromJson] wieder liest (für
  /// Zwischenspeicher, nicht fürs Backend).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unitPriceCents': unitPriceCents,
        'vatRate': vatRate,
        'unit': unit,
        'groupId': groupId,
        'revenueGroupId': revenueGroupId,
        'tile': {'visible': visible, 'sort': sort},
        'active': active,
        'quantityRule': quantityRule?.name,
        'askQuantity': askQuantity,
        'maxQuantity': maxQuantity,
        'stockLocationIds': stockLocationIds,
        'number': number,
        'ean': ean,
        'internalCode': internalCode,
        'stockTracked': stockTracked,
      };
}

/// Ein Text mit Inhalt, unveraendert; leer, nur Leerraum oder kein Text -> `null`
/// (Zwilling von `textOderNull` in `pos/artikel.ts`).
String? _textOderNull(Object? wert) => wert is String && wert.trim().isNotEmpty ? wert : null;

/// Deckelt eine gewünschte Menge an der Höchstmenge des Artikels.
num allowedQuantity(PosArticle a, num wanted) {
  final grenze = a.maxQuantity;
  if (grenze == null || grenze <= 0) return wanted;
  return wanted > grenze ? grenze : wanted;
}
