/// Lager an der Kasse: Standorte, Bestand und der Standort der Kasse –
/// Zwilling von `pos/lager.ts` im JS-Paket (Backend: `lager-endpoints.js`).
/// Die Aufrufe selbst stehen in [RegisterReceiptClient] (`stockLocations`,
/// `stock`, `setStockLocation`); es gibt sie nur ueber den Kassenweg
/// `/api/v3`. Rechte am Server: `stockView` (lesen), `stockCosts` (Werte),
/// `stockLocation` (Standort setzen).
///
/// **Ganzzahlen:** Mengen sind Tausendstel der Basiseinheit (`1000` = 1 Stueck,
/// `250` = 0,250 kg), Werte ganze Cent bzw. Mikro-Euro. Nichts wird geteilt,
/// gerundet oder geklemmt – ein negativer Bestand (mehr verkauft als gebucht)
/// ist eine Aussage des Servers und bleibt negativ. Eine Zahl, die keine
/// Ganzzahl ist, oder eine fehlende Menge wird **nie** zu `0`: der Aufruf
/// endet mit [KasseneckValidationError] (`kind: response`), denn „kein
/// Bestand" und „Antwort kaputt“ sind verschiedene Aussagen. Die Kasse liest
/// das als „Lager voruebergehend nicht verfuegbar“ und verkauft weiter.
library;

import '../register/fehler.dart';

/// Standort-Typen (Katalog `STANDORT_TYP`), englisch wie am Draht.
const List<String> stockLocationTypes = ['warehouse', 'store', 'vehicle', 'other'];

/// Typ eines Standorts; der Name ist der Wert am Draht.
enum StockLocationType { warehouse, store, vehicle, other }

/// Anschrift eines Standorts. Jeder Teil ist `null`, wenn er fehlt oder leer
/// ist; eine Anschrift ohne einen einzigen Teil gibt es nicht (dann ist
/// [StockLocation.address] `null`).
class StockLocationAddress {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'street', 'zip', 'city', 'country'};

  const StockLocationAddress({this.street, this.zip, this.city, this.country});

  final String? street;
  final String? zip;
  final String? city;
  final String? country;
}

/// Ein Standort des Betriebs (Lager, Geschaeft, Fahrzeug).
class StockLocation {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'id', 'name', 'type', 'address', 'licensePlate', 'active', 'virtual'};

  const StockLocation({
    required this.id,
    required this.name,
    this.type,
    this.address,
    this.licensePlate,
    this.active = true,
    this.virtual = false,
  });

  final String id;
  final String name;

  /// `null`: ein Typ, den dieses Paket nicht kennt.
  final StockLocationType? type;

  /// `null`, wenn der Standort keinen Adressteil traegt (Fahrzeuge haben keine).
  final StockLocationAddress? address;

  /// Kennzeichen, nur bei [StockLocationType.vehicle].
  final String? licensePlate;

  /// `false` = aufgeloest; als Standort der Kasse abgewiesen
  /// (`location_inactive`).
  final bool active;

  /// `true` = Hauptstandort, den der Server ohne eigenes Dokument ergaenzt.
  final bool virtual;
}

/// Bestand eines Artikels an einem Standort, in Tausendstel der Basiseinheit.
class StockLevel {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'articleId', 'locationId', 'sellable', 'defective', 'reserved', 'available'};

  const StockLevel({
    required this.articleId,
    required this.locationId,
    required this.sellable,
    required this.defective,
    required this.reserved,
    required this.available,
  });

  final String articleId;
  final String locationId;
  final int sellable;
  final int defective;
  final int reserved;

  /// `sellable - reserved`, vom Server gerechnet; hier nicht nachgerechnet,
  /// damit es genau eine Stelle gibt, die ihn bestimmt.
  final int available;
}

/// Lagerwert eines Artikels. Derselbe Typ an der Kasse (`pos.dart`) und in der
/// Lager-API (`inventory.dart`); er kommt nur, wenn Werte freigegeben sind: an
/// der Kasse mit dem Recht `stockCosts` des Kassenbenutzers, in der Lager-API
/// mit dem Konto-Schalter „Einkaufswerte per API“ (Recht `costs`).
class StockValue {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'articleId', 'stockValueCents', 'averageCostMicros'};

  const StockValue({required this.articleId, required this.stockValueCents, this.averageCostMicros});

  final String articleId;
  final int stockValueCents;

  /// Durchschnittlicher Einstandspreis je Basiseinheit in Mikro-Euro; `null`
  /// bei Menge 0.
  final int? averageCostMicros;
}

/// Antwort von `listMyStock`.
class StockList {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'stock', 'values'};

  const StockList({required this.stock, this.values});

  final List<StockLevel> stock;

  /// `null`, wenn der Aufrufer das Recht `stockCosts` nicht hat (der Server
  /// laesst das Feld weg); leer, wenn er es hat und nichts bewertet ist. Eine
  /// Oberflaeche zeigt bei `null` keinen Wert, nie „0,00 €“.
  final List<StockValue>? values;
}

/// Antwort von `setMyCashregisterStockLocation`.
class CashregisterStockLocation {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest (Feldmengen-Waechter
  /// in test/kasse_v3_test.dart gegen `v3/antworten/kasse.json`).
  static const Set<String> fields = {'cashregisterId', 'stockLocationId'};

  const CashregisterStockLocation({required this.cashregisterId, this.stockLocationId});

  final String cashregisterId;

  /// `null` = Standard-Standort des Betriebs.
  final String? stockLocationId;
}

// ---------------------------------------------------------------------------
// Leser (paketintern; die Aufrufe stehen in RegisterReceiptClient)
// ---------------------------------------------------------------------------

KasseneckValidationError _antwortfehler(String name, String grund) => KasseneckValidationError(name, grund, 'response');

/// Freitext, der fehlen darf (Name, Adressteile, Kennzeichen): leer = `null`.
String? _textOderNull(Object? w) => w is String && w.isNotEmpty ? w : null;

/// Eine Kennung, die da sein muss: ohne sie ist die Zeile nicht zuzuordnen,
/// und ein leerer Text als `stockLocationId` setzte die Kasse zurueck.
String _kennung(String name, String pfad, Object? w) {
  if (w is! String || w.isEmpty) throw _antwortfehler(name, 'Antwort enthaelt keine Kennung (data.$pfad fehlt)');
  return w;
}

/// Groesste Zahl, die JavaScript noch ganz darstellt (`Number.MAX_SAFE_INTEGER`).
const int _sicherGanz = 9007199254740991;

/// Eine Zahl des Servers: Ganzzahl oder Antwortfehler, nie ein Ersatzwert.
///
/// `12000.0` gilt als ganz: JavaScript kennt den Unterschied nicht, und der
/// JS-Zwilling nimmt dieselbe Zahl an. Groesser als 2^53 nimmt er sie auch,
/// hier waere `toInt` dort aber nicht mehr genau – darum gilt sie als kaputt.
int _ganzzahl(String name, String pfad, Object? w) {
  if (w is int) return w;
  if (w is double && w.isFinite && w == w.truncateToDouble() && w.abs() <= _sicherGanz) return w.toInt();
  throw _antwortfehler(name, 'Antwort enthaelt keine ganze Zahl (data.$pfad)');
}

/// Die Liste `data.<feld>`, jedes Element durch [lesen]. Ein Element, das kein
/// Objekt ist, wird als leeres Objekt gelesen und scheitert dort an seiner
/// Kennung – wie im JS-Zwilling, nie still uebersprungen: eine fehlende Zeile
/// saehe aus wie ein Artikel ohne Bestand.
List<T> lagerListe<T>(Map<String, dynamic> daten, String feld, String name, T Function(Map<String, dynamic>, int) lesen) {
  final roh = daten[feld];
  if (roh is! List) {
    throw _antwortfehler(
        name,
        roh == null
            ? 'Antwort enthaelt keine Liste (data.$feld fehlt)'
            : 'Antwort ist unbrauchbar (data.$feld ist keine Liste)');
  }
  return [
    for (final (i, e) in roh.indexed) lesen(e is Map ? Map<String, dynamic>.from(e) : const <String, dynamic>{}, i),
  ];
}

StockLocation lagerStandortLesen(String name, Map<String, dynamic> s, int i) {
  final pfad = 'locations[$i]';
  final a = s['address'];
  final teile = a is Map
      ? StockLocationAddress(
          street: _textOderNull(a['street']),
          zip: _textOderNull(a['zip']),
          city: _textOderNull(a['city']),
          country: _textOderNull(a['country']),
        )
      : null;
  // Eine Adresse ohne einen einzigen Teil ist keine Adresse.
  final adresse =
      teile != null && [teile.street, teile.zip, teile.city, teile.country].any((t) => t != null) ? teile : null;
  final typ = s['type'];
  return StockLocation(
    id: _kennung(name, '$pfad.id', s['id']),
    name: s['name'] is String ? s['name'] as String : '',
    type: StockLocationType.values.where((t) => t.name == typ).firstOrNull,
    address: adresse,
    licensePlate: _textOderNull(s['licensePlate']),
    active: s['active'] != false,
    virtual: s['virtual'] == true,
  );
}

StockLevel lagerBestandLesen(String name, Map<String, dynamic> b, int i) {
  final pfad = 'stock[$i]';
  return StockLevel(
    articleId: _kennung(name, '$pfad.articleId', b['articleId']),
    locationId: _kennung(name, '$pfad.locationId', b['locationId']),
    sellable: _ganzzahl(name, '$pfad.sellable', b['sellable']),
    defective: _ganzzahl(name, '$pfad.defective', b['defective']),
    reserved: _ganzzahl(name, '$pfad.reserved', b['reserved']),
    available: _ganzzahl(name, '$pfad.available', b['available']),
  );
}

StockValue lagerWertLesen(String name, Map<String, dynamic> w, int i) {
  final pfad = 'values[$i]';
  final schnitt = w['averageCostMicros'];
  return StockValue(
    articleId: _kennung(name, '$pfad.articleId', w['articleId']),
    stockValueCents: _ganzzahl(name, '$pfad.stockValueCents', w['stockValueCents']),
    // Fehlt der Durchschnitt oder ist er null, ist die Menge 0 – eine
    // vorhandene, aber unbrauchbare Zahl ist dagegen ein Antwortfehler.
    averageCostMicros: schnitt == null ? null : _ganzzahl(name, '$pfad.averageCostMicros', schnitt),
  );
}

/// `listMyStock`: fehlt `values`, fehlt dem Aufrufer das Recht `stockCosts`
/// (`null`, nie leer); etwas anderes als eine Liste ist dagegen kaputt.
StockList lagerBestandslisteLesen(String name, Map<String, dynamic> daten) {
  final stock = lagerListe(daten, 'stock', name, (e, i) => lagerBestandLesen(name, e, i));
  if (daten['values'] == null) return StockList(stock: stock);
  return StockList(stock: stock, values: lagerListe(daten, 'values', name, (e, i) => lagerWertLesen(name, e, i)));
}

/// Antwort von `setMyCashregisterStockLocation`.
CashregisterStockLocation lagerKassenStandortLesen(String name, Map<String, dynamic> daten) {
  final kasse = daten['cashregisterId'];
  if (kasse is! String || kasse.isEmpty) {
    throw _antwortfehler(name, 'Antwort enthaelt keine Kasse (data.cashregisterId fehlt)');
  }
  final stand = daten['stockLocationId'];
  if (stand != null && stand is! String) {
    throw _antwortfehler(name, 'Antwort enthaelt einen unbrauchbaren Standort (data.stockLocationId)');
  }
  return CashregisterStockLocation(cashregisterId: kasse, stockLocationId: _textOderNull(stand));
}
