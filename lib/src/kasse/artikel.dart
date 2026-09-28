/// Artikelgruppen und Artikel in der Form, die die Kachel-Kasse braucht —
/// Zwilling von `kasse/artikel.ts` im JS-Paket (Backend:
/// `article-endpoints.js`).
library;

/// Kategorie der Kachel-Kasse.
class Artikelgruppe {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> felder = {'id', 'name', 'color', 'symbol', 'sort', 'vatRate'};

  const Artikelgruppe({
    required this.id,
    required this.name,
    required this.farbe,
    required this.sort,
    this.symbol,
    this.steuersatz,
  });

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String farbe;

  /// Kategorie-Symbol (Emoji, höchstens zwei Zeichen) oder `null`.
  final String? symbol;
  final int sort;

  /// Vorschlag der Gruppe; der Artikel entscheidet.
  final num? steuersatz;

  factory Artikelgruppe.aus(Map<String, dynamic> json) => Artikelgruppe(
        id: json['id'] is String ? json['id'] as String : '',
        name: json['name'] is String ? json['name'] as String : '',
        farbe: json['color'] is String ? json['color'] as String : '#6B7280',
        symbol: json['symbol'] is String ? json['symbol'] as String : null,
        sort: json['sort'] is num ? (json['sort'] as num).toInt() : 0,
        steuersatz: json['vatRate'] is num ? json['vatRate'] as num : null,
      );

  /// Zurück in die Form, aus der [Artikelgruppe.aus] wieder liest — für
  /// Zwischenspeicher, nicht fürs Backend.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': farbe,
        'symbol': symbol,
        'sort': sort,
        'vatRate': steuersatz,
      };
}

/// Mengenregel eines Artikels.
///
/// [piece] = ganze Stück (1, 2, 3 …), [decimal] = Kommamenge in der Einheit
/// (0,250 kg; 1,5 m); der Name ist der Wert am Draht (`quantityRule`).
/// **Beleg und DEP bleiben ganzzahlig:** eine Kommamenge wird als EINE
/// Position mit ausgerechnetem Betrag gebucht, und die Bezeichnung trägt die
/// Menge („Wurst 0,250 kg").
enum Mengenregel { piece, decimal }

/// Die Werte von `quantityRule` (Katalog `MENGENREGEL`).
const List<String> quantityRules = ['piece', 'decimal'];

class Mengenvorgabe {
  const Mengenvorgabe({required this.regel, required this.fragen, required this.stellen});

  final Mengenregel regel;

  /// Die Kasse fragt beim Antippen nach der Menge (Wurst nach Gewicht: ja;
  /// Semmel: nein).
  final bool fragen;

  /// Nachkommastellen bei [Mengenregel.decimal].
  final int stellen;
}

/// Einheiten, die nach Menge verkauft werden.
const Map<String, int> _dezimalEinheiten = {
  'kg': 3, 'g': 0, 'l': 2, 'ml': 0, 'm': 2, 'lfm': 2, 'km': 1,
  'm²': 2, 'm2': 2, 'm³': 3, 'm3': 3, 'std': 2, 'h': 2, 'min': 0, 't': 3,
};

/// Vorgabe je Einheit — was der Betrieb bei einem neuen Artikel bekommt und
/// ändern darf.
Mengenvorgabe mengenregelFuerEinheit(String? einheit) {
  final u = (einheit ?? '').trim().toLowerCase();
  final stellen = _dezimalEinheiten[u];
  if (stellen == null) return const Mengenvorgabe(regel: Mengenregel.piece, fragen: false, stellen: 0);
  // g, ml, min: ganze Zahl, aber die Menge wird gefragt.
  if (stellen == 0) return const Mengenvorgabe(regel: Mengenregel.piece, fragen: true, stellen: 0);
  return Mengenvorgabe(regel: Mengenregel.decimal, fragen: true, stellen: stellen);
}

/// Wirksame Regel eines Artikels: die gespeicherte Angabe schlägt die Vorgabe
/// der Einheit.
Mengenvorgabe mengenVorgabe(KasseArtikel a) {
  final v = mengenregelFuerEinheit(a.einheit);
  final regel = a.mengenregel ?? v.regel;
  return Mengenvorgabe(
    regel: regel,
    fragen: a.mengeFragen ?? v.fragen,
    stellen: regel == Mengenregel.decimal ? (v.stellen < 1 ? 2 : v.stellen) : 0,
  );
}

/// Artikel, wie ihn die Kasse für Kacheln und Belegpositionen braucht.
class KasseArtikel {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> felder = {'id', 'name', 'unitPriceCents', 'vatRate', 'unit', 'groupId', 'revenueGroupId', 'tile', 'active', 'quantityRule', 'askQuantity', 'maxQuantity'};

  /// Die Felder von `tile`.
  static const Set<String> kachelFelder = {'visible', 'sort'};

  const KasseArtikel({
    required this.id,
    required this.name,
    required this.einheit,
    required this.sichtbar,
    required this.sort,
    required this.aktiv,
    this.preisCents,
    this.steuersatz,
    this.gruppeId,
    this.erloesgruppeId,
    this.mengenregel,
    this.mengeFragen,
    this.maxMenge,
  });

  final String id;
  final String name;

  /// Einzelpreis in ganzen Cent; `null` = kein Preis hinterlegt.
  final int? preisCents;

  /// Steuersatz in Prozent, roh; `null` = keiner hinterlegt.
  final num? steuersatz;

  final String einheit;
  final String? gruppeId;

  /// Erlösgruppe (Buchhaltung, Draht `revenueGroupId`); `null` = keine.
  final String? erloesgruppeId;

  /// Im Panel für die Kasse freigegeben.
  final bool sichtbar;
  final int sort;
  final bool aktiv;

  /// Gespeicherte Mengenregel; `null` = Vorgabe der Einheit.
  final Mengenregel? mengenregel;

  /// Gespeichert: Kasse fragt nach der Menge; `null` = Vorgabe der Einheit.
  final bool? mengeFragen;

  /// Höchstmenge je Beleg; `null` = keine Grenze.
  final num? maxMenge;

  /// Aus der Drahtform `/api/v3` (`tile {visible, sort}`, `quantityRule`,
  /// `askQuantity`, `maxQuantity`, `revenueGroupId`).
  ///
  /// Liest auch einen **Zwischenspeicher der Version 9.x** (`kasse
  /// {sichtbar, sort}`, `mengenregel stueck|dezimal`, `mengeFragen`,
  /// `maxMenge`, so schrieb `toJson` bis 9.x): nach dem Update gehen die
  /// Kacheln des letzten Stands nicht verloren.
  factory KasseArtikel.aus(Map<String, dynamic> json) {
    final alt = !json.containsKey('tile') && json.containsKey('kasse');
    final kachel = json[alt ? 'kasse' : 'tile'];
    final regel = json[alt ? 'mengenregel' : 'quantityRule'];
    final fragen = json[alt ? 'mengeFragen' : 'askQuantity'];
    final grenze = json[alt ? 'maxMenge' : 'maxQuantity'];
    final erloes = json['revenueGroupId'];
    return KasseArtikel(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      // round, nicht toInt: das Backend rechnet den Preis in JavaScript aus
      // Euro hoch, und 19.99 * 100 ergibt dort 1998.9999999999998 -- ein
      // abgeschnittener Wert verkaufte den Artikel dauerhaft einen Cent zu
      // billig, und zwar auf einen signierten Beleg. Alle Schwesterstellen
      // (kasseneck_item, keck_voucher, keck_invoice_item, belege) runden.
      preisCents: json['unitPriceCents'] is num ? (json['unitPriceCents'] as num).round() : null,
      steuersatz: json['vatRate'] is num ? json['vatRate'] as num : null,
      einheit: json['unit'] is String ? json['unit'] as String : '',
      gruppeId: json['groupId'] is String ? json['groupId'] as String : null,
      erloesgruppeId: erloes is String && erloes.isNotEmpty ? erloes : null,
      // Fehlt die Angabe, ist der Artikel sichtbar: ein Betrieb, der nie
      // etwas eingestellt hat, soll seine Artikel trotzdem sehen.
      sichtbar: kachel is Map ? kachel[alt ? 'sichtbar' : 'visible'] != false : true,
      sort: kachel is Map && kachel['sort'] is num ? (kachel['sort'] as num).toInt() : 0,
      aktiv: json['active'] != false,
      mengenregel: switch (regel) {
        'piece' || 'stueck' => Mengenregel.piece,
        'decimal' || 'dezimal' => Mengenregel.decimal,
        _ => null,
      },
      mengeFragen: fragen is bool ? fragen : null,
      maxMenge: grenze is num && grenze.isFinite && grenze > 0 ? grenze : null,
    );
  }

  /// Zurück in die Drahtform, aus der [KasseArtikel.aus] wieder liest (für
  /// Zwischenspeicher, nicht fürs Backend).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unitPriceCents': preisCents,
        'vatRate': steuersatz,
        'unit': einheit,
        'groupId': gruppeId,
        'revenueGroupId': erloesgruppeId,
        'tile': {'visible': sichtbar, 'sort': sort},
        'active': aktiv,
        'quantityRule': mengenregel?.name,
        'askQuantity': mengeFragen,
        'maxQuantity': maxMenge,
      };
}

/// Deckelt eine gewünschte Menge an der Höchstmenge des Artikels.
num mengeErlaubt(KasseArtikel a, num gewuenscht) {
  final grenze = a.maxMenge;
  if (grenze == null || grenze <= 0) return gewuenscht;
  return gewuenscht > grenze ? grenze : gewuenscht;
}
