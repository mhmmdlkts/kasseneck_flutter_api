/// Leser der Lager-Antworten: aus dem Draht `/v3` werden die Modelle in
/// `modelle.dart`. Paketintern, nicht Teil der Oberflaeche – Zwilling von
/// `src/inventory/lesen.ts` im JS-Paket.
///
/// Regel wie beim Lager an der Kasse (`kasse/lager.dart`): eine Menge, ein
/// Betrag oder eine Folgenummer ist eine Ganzzahl, sonst endet der Aufruf mit
/// [KasseneckValidationError] (`kind: response`). Ein Ersatzwert wie `0`
/// waere eine falsche Aussage („kein Bestand“ statt „Antwort kaputt“). Texte
/// sind nachsichtiger: ein fehlender oder fremder Wert wird `null`.
///
/// Ganzzahl heisst wie im JS-Zwilling `Number.isSafeInteger`: `4000.0` ist
/// eine (JSON kennt keinen Unterschied, Dart schon), `4000.5` und alles
/// jenseits von 2^53 - 1 nicht.
library;

import '../kasse/lager.dart' show StockValue;
import '../register/fehler.dart';
import 'modelle.dart';
import 'vertrag.dart';

/// Wo gelesen wird: Aufruf und Pfad unter `data`, fuer die Meldung.
class Ort {
  const Ort(this.name, this.pfad);

  final String name;
  final String pfad;

  Ort unter(String teil) => Ort(name, '$pfad.$teil');
}

KasseneckValidationError antwortfehler(String name, String grund) => KasseneckValidationError(name, grund, 'response');

Map<String, dynamic>? objekt(Object? w) {
  if (w is Map<String, dynamic>) return w;
  if (w is Map && w.keys.every((k) => k is String)) return w.cast<String, dynamic>();
  return null;
}

/// Ein Eintrag, der ein Objekt sein muss.
Map<String, dynamic> _eintrag(Ort ort, Object? w) =>
    objekt(w) ?? (throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad} ist kein Objekt)'));

String? _text(Object? w) => w is String ? w : null;

String? _textOderNull(Object? w) => w is String && w.isNotEmpty ? w : null;

/// Eine Kennung, die da sein muss; ohne sie ist der Eintrag nicht zuzuordnen.
String _kennung(Ort ort, String feld, Object? w) {
  if (w is! String || w.isEmpty) {
    throw antwortfehler(ort.name, 'Antwort enthaelt keine Kennung (data.${ort.pfad}.$feld fehlt)');
  }
  return w;
}

const int _groessteSichere = 9007199254740991;

/// `w` als Ganzzahl im sicheren Bereich, sonst `null`.
int? ganzzahlVon(Object? w) {
  if (w is int) return w.abs() <= _groessteSichere ? w : null;
  if (w is double && w.isFinite && w == w.truncateToDouble() && w.abs() <= _groessteSichere) return w.toInt();
  return null;
}

/// Eine Ganzzahl, die da sein muss.
int _ganzzahl(Ort ort, String feld, Object? w) =>
    ganzzahlVon(w) ?? (throw antwortfehler(ort.name, 'Antwort enthaelt keine ganze Zahl (data.${ort.pfad}.$feld)'));

/// Eine Ganzzahl oder `null`; fehlt der Wert, gilt `null`.
int? _ganzzahlOderNull(Ort ort, String feld, Object? w) => w == null ? null : _ganzzahl(ort, feld, w);

/// Eine Ganzzahl, wo eine kaputte Angabe nichts verfaelscht (HTTP-Status, Position): sonst `null`.
int? _ganzzahlNachsichtig(Object? w) => ganzzahlVon(w);

/// Mengen je Standort (`minStockByLocation`): jeder Wert eine Ganzzahl. Fehlt
/// das Feld (Server vor Stufe 5b), gilt „keiner“ (`{}`).
Map<String, int> _mengenJeStandort(Ort ort, String feld, Object? w) {
  if (w == null) return const {};
  final o = objekt(w);
  if (o == null) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.$feld ist kein Objekt)');
  return Map.unmodifiable({for (final e in o.entries) e.key: _ganzzahl(ort, '$feld.${e.key}', e.value)});
}

/// Eine Liste von Kennungen (`movementIds`, `lotIds`); fehlt sie, ist sie leer.
List<String> _kennungsliste(Ort ort, String feld, Object? w) {
  if (w == null) return const [];
  if (w is! List || !w.every((x) => x is String)) {
    final pfad = ort.pfad.isEmpty ? feld : '${ort.pfad}.$feld';
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.$pfad ist keine Liste von Kennungen)');
  }
  return List.unmodifiable(w.cast<String>());
}

/// Eine Textabbildung (`externalIds`, `metadata`, `variantAttributes`): nur Texteintraege.
Map<String, String>? _textAbbildung(Object? w) {
  if (w is! Map) return null;
  return {
    for (final e in w.entries)
      if (e.key is String && e.value is String) e.key as String: e.value as String,
  };
}

// ---- Artikel ------------------------------------------------------------------

Article artikel(Ort ort, Object? w) {
  final a = _eintrag(ort, w);
  var standorte = const <String>[];
  final roh = a['stockLocationIds'];
  if (roh != null) {
    if (roh is! List || !roh.every((s) => s is String)) {
      throw antwortfehler(
          ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.stockLocationIds ist keine Liste von Kennungen)');
    }
    standorte = List.unmodifiable(roh.cast<String>());
  }
  final vatRate = a['vatRate'];
  if (vatRate != null && (vatRate is! num || !vatRate.isFinite)) {
    throw antwortfehler(ort.name, 'Antwort enthaelt keinen USt-Satz (data.${ort.pfad}.vatRate)');
  }
  final hatEinkauf = a.containsKey('purchasePriceMicros');
  return Article(
    id: _kennung(ort, 'id', a['id']),
    name: _text(a['name']),
    description: _text(a['description']),
    unitPriceCents: _ganzzahlOderNull(ort, 'unitPriceCents', a['unitPriceCents']),
    vatRate: vatRate as num?,
    unit: _text(a['unit']),
    number: _text(a['number']),
    ean: _text(a['ean']),
    internalCode: _text(a['internalCode']),
    groupId: _text(a['groupId']),
    revenueGroupId: _text(a['revenueGroupId']),
    stockTracked: a['stockTracked'] == true,
    stockKind: _textOderNull(a['stockKind']),
    stockLocationIds: standorte,
    minStock: _ganzzahlOderNull(ort, 'minStock', a['minStock']),
    minStockByLocation: _mengenJeStandort(ort, 'minStockByLocation', a['minStockByLocation']),
    active: a['active'] != false,
    externalIds: _textAbbildung(a['externalIds']),
    metadata: _textAbbildung(a['metadata']),
    variantGroupId: _text(a['variantGroupId']),
    variantAttributes: _textAbbildung(a['variantAttributes']),
    createdAt: _text(a['createdAt']),
    updatedAt: _text(a['updatedAt']),
    // Nur mit dem Recht `costs`; ohne fehlt das Feld ganz.
    purchasePriceMicros: hatEinkauf ? _ganzzahlOderNull(ort, 'purchasePriceMicros', a['purchasePriceMicros']) : null,
    hasPurchasePriceMicros: hatEinkauf,
  );
}

// ---- Standorte ------------------------------------------------------------------

Location standort(Ort ort, Object? w) {
  final s = _eintrag(ort, w);
  final a = objekt(s['address']);
  final teile = a == null
      ? null
      : LocationAddress(
          street: _textOderNull(a['street']),
          zip: _textOderNull(a['zip']),
          city: _textOderNull(a['city']),
          country: _textOderNull(a['country']),
        );
  final typ = s['type'];
  return Location(
    id: _kennung(ort, 'id', s['id']),
    name: s['name'] is String ? s['name'] as String : '',
    type: typ is String && locationTypes.contains(typ) ? typ : null,
    // Eine Adresse ohne einen einzigen Teil ist keine Adresse.
    address: teile != null && [teile.street, teile.zip, teile.city, teile.country].any((t) => t != null) ? teile : null,
    licensePlate: _textOderNull(s['licensePlate']),
    active: s['active'] != false,
    virtual: s['virtual'] == true,
  );
}

// ---- Bestand ------------------------------------------------------------------

StockLevel bestand(Ort ort, Object? w) {
  final b = _eintrag(ort, w);
  return StockLevel(
    articleId: _kennung(ort, 'articleId', b['articleId']),
    locationId: _kennung(ort, 'locationId', b['locationId']),
    onHand: _ganzzahl(ort, 'onHand', b['onHand']),
    reserved: _ganzzahl(ort, 'reserved', b['reserved']),
    available: _ganzzahl(ort, 'available', b['available']),
    defective: _ganzzahl(ort, 'defective', b['defective']),
    sequence: _ganzzahl(ort, 'sequence', b['sequence']),
    updatedAt: _text(b['updatedAt']),
  );
}

StockValue wert(Ort ort, Object? w) {
  final v = _eintrag(ort, w);
  return StockValue(
    articleId: _kennung(ort, 'articleId', v['articleId']),
    stockValueCents: _ganzzahl(ort, 'stockValueCents', v['stockValueCents']),
    averageCostMicros: _ganzzahlOderNull(ort, 'averageCostMicros', v['averageCostMicros']),
  );
}

// ---- Bewegungen ------------------------------------------------------------------

StockMovementLot _los(Ort ort, Object? w) {
  final l = _eintrag(ort, w);
  final hatWert = l.containsKey('valueCents');
  return StockMovementLot(
    lotId: _text(l['lotId']),
    quantity: _ganzzahl(ort, 'quantity', l['quantity']),
    expiresOn: _text(l['expiresOn']),
    batch: _text(l['batch']),
    serialNumber: _text(l['serialNumber']),
    receivedAt: _text(l['receivedAt']),
    valueCents: hatWert ? _ganzzahlOderNull(ort, 'valueCents', l['valueCents']) : null,
    hasValueCents: hatWert,
  );
}

StockMovement bewegung(Ort ort, Object? w) {
  final b = _eintrag(ort, w);
  final nachher = objekt(b['stockAfter']);
  final quelle = objekt(b['source']);
  final lose = b['lots'] ?? const [];
  if (lose is! List) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.lots ist keine Liste)');
  final nachherOrt = ort.unter('stockAfter');
  final hatWert = b.containsKey('valueDeltaCents');
  final hatVerbrauch = b.containsKey('consumedValueCents');
  return StockMovement(
    id: _kennung(ort, 'id', b['id']),
    type: _text(b['type']),
    articleId: _text(b['articleId']),
    locationId: _text(b['locationId']),
    condition: _text(b['condition']),
    quantityDelta: _ganzzahl(ort, 'quantityDelta', b['quantityDelta']),
    // Server vor Stufe 5b senden das Feld nicht: dort aenderte keine Bewegung `reserved`.
    reservedDelta: !b.containsKey('reservedDelta') ? 0 : _ganzzahl(ort, 'reservedDelta', b['reservedDelta']),
    stockAfter: nachher == null
        ? null
        : StockAfter(
            sellable: _ganzzahl(nachherOrt, 'sellable', nachher['sellable']),
            defective: _ganzzahl(nachherOrt, 'defective', nachher['defective']),
            reserved: _ganzzahlOderNull(nachherOrt, 'reserved', nachher['reserved']),
          ),
    operationId: _text(b['operationId']),
    source: quelle == null
        ? null
        : StockMovementSourceRef(
            type: _text(quelle['type']),
            id: _text(quelle['id']),
            register: _text(quelle['register']),
            position: _ganzzahlNachsichtig(quelle['position']),
          ),
    viennaDay: _text(b['viennaDay']),
    time: _text(b['time']),
    lots: List.unmodifiable([for (final (i, l) in lose.indexed) _los(Ort(ort.name, '${ort.pfad}.lots[$i]'), l)]),
    valueDeltaCents: hatWert ? _ganzzahlOderNull(ort, 'valueDeltaCents', b['valueDeltaCents']) : null,
    hasValueDeltaCents: hatWert,
    consumedValueCents: hatVerbrauch ? _ganzzahlOderNull(ort, 'consumedValueCents', b['consumedValueCents']) : null,
    hasConsumedValueCents: hatVerbrauch,
  );
}

// ---- Webhooks ------------------------------------------------------------------

InventoryWebhook webhook(Ort ort, Object? w) {
  final h = _eintrag(ort, w);
  final z = objekt(h['lastDelivery']);
  final ereignisse = h['events'];
  return InventoryWebhook(
    id: _kennung(ort, 'id', h['id']),
    url: h['url'] is String ? h['url'] as String : '',
    events: ereignisse is List ? List.unmodifiable(ereignisse.whereType<String>()) : const [],
    active: h['active'] != false,
    description: _text(h['description']),
    createdAt: _text(h['createdAt']),
    lastDelivery: z == null
        ? null
        : InventoryWebhookLastDelivery(
            at: _text(z['at']), status: _text(z['status']), statusCode: _ganzzahlNachsichtig(z['statusCode'])),
    consecutiveFailures: _ganzzahlNachsichtig(h['consecutiveFailures']) ?? 0,
  );
}

InventoryWebhookDelivery zustellung(Ort ort, Object? w) {
  final z = _eintrag(ort, w);
  return InventoryWebhookDelivery(
    deliveryId: _kennung(ort, 'deliveryId', z['deliveryId']),
    webhookId: _text(z['webhookId']),
    event: _text(z['event']),
    eventId: _text(z['eventId']),
    status: _text(z['status']),
    attempts: _ganzzahlNachsichtig(z['attempts']) ?? 0,
    statusCode: _ganzzahlNachsichtig(z['statusCode']),
    response: _text(z['response']),
    error: _text(z['error']),
    createdAt: _text(z['createdAt']),
    lastAttemptAt: _text(z['lastAttemptAt']),
    nextAttemptAt: _text(z['nextAttemptAt']),
    test: z['test'] == true,
  );
}

InventoryWebhookTestDelivery probeZustellung(Ort ort, Object? w, String webhookId) {
  final z = _eintrag(ort, w);
  final eigene = z['webhookId'];
  return InventoryWebhookTestDelivery(
    deliveryId: _kennung(ort, 'deliveryId', z['deliveryId']),
    webhookId: eigene is String && eigene.isNotEmpty ? eigene : webhookId,
    status: _text(z['status']),
    statusCode: _ganzzahlNachsichtig(z['statusCode']),
  );
}

// ---- Ereignisse ------------------------------------------------------------------

StockChangedEventData bestandGeaendert(Ort ort, Object? w) {
  final d = _eintrag(ort, w);
  final ursache = d['cause'];
  if (ursache is! String || ursache.isEmpty) throw antwortfehler(ort.name, 'Ereignis ohne Ursache (${ort.pfad}.cause)');
  final s = bestand(ort, d);
  return StockChangedEventData(
    articleId: s.articleId,
    locationId: s.locationId,
    onHand: s.onHand,
    reserved: s.reserved,
    available: s.available,
    defective: s.defective,
    sequence: s.sequence,
    updatedAt: s.updatedAt,
    cause: ursache,
    movementId: _textOderNull(d['movementId']),
  );
}

StockBelowMinimumEventData unterMindestbestand(Ort ort, Object? w) {
  final d = _eintrag(ort, w);
  return StockBelowMinimumEventData(
    articleId: _kennung(ort, 'articleId', d['articleId']),
    locationId: _kennung(ort, 'locationId', d['locationId']),
    available: _ganzzahl(ort, 'available', d['available']),
    minStock: _ganzzahl(ort, 'minStock', d['minStock']),
  );
}

// ---- Schreiben (Stufe 5b) ------------------------------------------------------------

InventoryWarning _warnung(Ort ort, Object? w) {
  final h = _eintrag(ort, w);
  final code = h['code'];
  if (code is! String || code.isEmpty) throw antwortfehler(ort.name, 'Hinweis ohne Code (data.${ort.pfad}.code)');
  return InventoryWarning(
    code: code,
    articleId: _textOderNull(h['articleId']),
    locationId: _textOderNull(h['locationId']),
    message: h['message'] is String ? h['message'] as String : '',
  );
}

/// Antwort einer Buchung; ohne `operationId` ist nicht belegt, dass gebucht
/// wurde. Das ist ein Antwortfehler und kein Ersatzwert: der Aufrufer
/// wiederholt dann mit demselben Schluessel und bekommt die gespeicherte
/// Antwort.
StockOperation vorgang(String name, Map<String, dynamic> daten) {
  final ort = Ort(name, '');
  final id = daten['operationId'];
  if (id is! String || id.isEmpty) throw antwortfehler(name, 'Antwort enthaelt keine Kennung (data.operationId fehlt)');
  final hinweise = daten['warnings'] ?? const [];
  if (hinweise is! List) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.warnings ist keine Liste)');
  return StockOperation(
    operationId: id,
    movementIds: _kennungsliste(ort, 'movementIds', daten['movementIds']),
    lotIds: _kennungsliste(ort, 'lotIds', daten['lotIds']),
    warnings: List.unmodifiable([for (final (i, h) in hinweise.indexed) _warnung(Ort(name, 'warnings[$i]'), h)]),
  );
}

/// Eine Zeile der Wareneingangs-Vorschau; Werte nur, wenn der Server sie sendet (Recht `costs`).
GoodsReceiptPreviewLine vorschauZeile(Ort ort, Object? w) {
  final z = _eintrag(ort, w);
  final serien = z['serialNumbers'] ?? const [];
  if (serien is! List || !serien.every((x) => x is String)) {
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.serialNumbers ist keine Liste)');
  }
  const werte = ['baseCents', 'landedCostCents', 'valueCents', 'unitCostMicros'];
  return GoodsReceiptPreviewLine(
    articleId: _kennung(ort, 'articleId', z['articleId']),
    quantity: _ganzzahl(ort, 'quantity', z['quantity']),
    expiresOn: _textOderNull(z['expiresOn']),
    batch: _textOderNull(z['batch']),
    serialNumbers: List.unmodifiable(serien.cast<String>()),
    priceFromArticle: z['priceFromArticle'] == true,
    baseCents: _ganzzahlOderNull(ort, 'baseCents', z['baseCents']),
    landedCostCents: _ganzzahlOderNull(ort, 'landedCostCents', z['landedCostCents']),
    valueCents: _ganzzahlOderNull(ort, 'valueCents', z['valueCents']),
    unitCostMicros: _ganzzahlOderNull(ort, 'unitCostMicros', z['unitCostMicros']),
    hasValues: werte.any(z.containsKey),
  );
}

ReservationItem _reservierungsPosition(Ort ort, Object? w) {
  final p = _eintrag(ort, w);
  return ReservationItem(
    articleId: _kennung(ort, 'articleId', p['articleId']),
    locationId: _kennung(ort, 'locationId', p['locationId']),
    quantity: _ganzzahl(ort, 'quantity', p['quantity']),
    redeemed: _ganzzahl(ort, 'redeemed', p['redeemed']),
    released: _ganzzahl(ort, 'released', p['released']),
  );
}

Reservation reservierung(Ort ort, Object? w) {
  final r = _eintrag(ort, w);
  final positionen = r['items'];
  if (positionen is! List) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.items ist keine Liste)');
  return Reservation(
    id: _kennung(ort, 'id', r['id']),
    status: _textOderNull(r['status']),
    reference: _text(r['reference']),
    items: List.unmodifiable(
        [for (final (i, p) in positionen.indexed) _reservierungsPosition(Ort(ort.name, '${ort.pfad}.items[$i]'), p)]),
    expiresAt: _text(r['expiresAt']),
    createdAt: _text(r['createdAt']),
  );
}

/// Die fehlenden Positionen aus `insufficient_available` (`data.details[]`).
/// Ein kaputter Eintrag faellt weg: der Aufruf ist ohnehin gescheitert, und
/// ein Wurf im Fehlerpfad verdeckte den eigentlichen Fehler.
List<InventoryShortfall> fehlmengen(Object? roh) {
  if (roh is! List) return const [];
  return List.unmodifiable([
    for (final e in roh)
      if (objekt(e) case final o?)
        if ((o['articleId'], o['locationId'], ganzzahlVon(o['requested']), ganzzahlVon(o['available']))
            case (final String articleId, final String locationId, final int requested, final int available))
          InventoryShortfall(articleId: articleId, locationId: locationId, requested: requested, available: available),
  ]);
}

// ---- Varianten (Stufe 5c) ------------------------------------------------------------

/// Eine Liste von Texten (Werte eines Merkmals); etwas anderes ist kaputt.
List<String> _textliste(Ort ort, String feld, Object? w) {
  if (w is! List || !w.every((x) => x is String)) {
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.$feld ist keine Liste von Texten)');
  }
  return List.unmodifiable(w.cast<String>());
}

VariantAttribute _merkmal(Ort ort, Object? w) {
  final m = _eintrag(ort, w);
  return VariantAttribute(
    key: _kennung(ort, 'key', m['key']),
    label: m['label'] is String ? m['label'] as String : '',
    values: _textliste(ort, 'values', m['values']),
  );
}

/// Vorgaben einer Gruppe: nur die Felder, die der Server sendet. Ein Preis als
/// Bruchzahl ist kaputt (er fuellte sonst jede neue Variante falsch), ein Feld
/// mit fremdem Typ ebenso. `null` gilt als nicht gesendet.
VariantGroupDefaults _vorgaben(Ort ort, Object? w) {
  if (w == null) return const VariantGroupDefaults();
  final v = objekt(w);
  final vOrt = ort.unter('defaults');
  if (v == null) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${vOrt.pfad} ist kein Objekt)');
  final vatRate = v['vatRate'];
  if (vatRate != null && (vatRate is! num || !vatRate.isFinite)) {
    throw antwortfehler(ort.name, 'Antwort enthaelt keinen USt-Satz (data.${vOrt.pfad}.vatRate)');
  }
  String? text(String feld) {
    final t = v[feld];
    if (t == null || t is String) return t as String?;
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${vOrt.pfad}.$feld ist kein Text)');
  }

  final gefuehrt = v['stockTracked'];
  if (gefuehrt != null && gefuehrt is! bool) {
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${vOrt.pfad}.stockTracked ist kein Wahrheitswert)');
  }
  return VariantGroupDefaults(
    unitPriceCents: _ganzzahlOderNull(vOrt, 'unitPriceCents', v['unitPriceCents']),
    vatRate: vatRate as num?,
    unit: text('unit'),
    groupId: text('groupId'),
    stockTracked: gefuehrt as bool?,
  );
}

VariantGroupMember _mitglied(Ort ort, Object? w) {
  final x = _eintrag(ort, w);
  return VariantGroupMember(
    articleId: _kennung(ort, 'articleId', x['articleId']),
    variantAttributes: Map.unmodifiable(_textAbbildung(x['variantAttributes']) ?? const <String, String>{}),
  );
}

/// Eine Variantengruppe. `attributes` und `variants` sind zugesagte Listen:
/// fehlen sie, ist die Antwort kaputt (eine leere Liste hiesse „keine Merkmale“
/// bzw. „keine Varianten“).
VariantGroup variantengruppe(Ort ort, Object? w) {
  final g = _eintrag(ort, w);
  final merkmale = g['attributes'];
  final varianten = g['variants'];
  for (final (feld, liste) in [('attributes', merkmale), ('variants', varianten)]) {
    if (liste is! List) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.$feld ist keine Liste)');
  }
  return VariantGroup(
    id: _kennung(ort, 'id', g['id']),
    name: _text(g['name']),
    attributes: List.unmodifiable(
        [for (final (i, m) in (merkmale as List).indexed) _merkmal(ort.unter('attributes[$i]'), m)]),
    defaults: _vorgaben(ort, g['defaults']),
    active: g['active'] != false,
    variants: List.unmodifiable(
        [for (final (i, v) in (varianten as List).indexed) _mitglied(ort.unter('variants[$i]'), v)]),
    createdAt: _text(g['createdAt']),
    updatedAt: _text(g['updatedAt']),
  );
}

// ---- Inventur (Lager-Kern Stufe 3, seit 10.7) --------------------------------
//
// Gleiche Regeln wie im JS-Zwilling (`inventur`, `inventurPosition`,
// `inventurZaehlung` in `src/inventory/lesen.ts`): Pflichtzahlen (Runde,
// Zaehlungen, Positionen, Zaehlmenge, Groesse) sind Ganzzahlen oder ein
// Antwortfehler; was der Server nur in einem Stand oder nur mit einem Recht
// sendet, ist `null`, wenn es fehlt.

/// Ein Unterobjekt, das `null` sein darf (`review`, `closing` …); etwas anderes
/// als Objekt oder `null` ist kaputt.
Map<String, dynamic>? _objektOderNull(Ort ort, String feld, Object? w) {
  if (w == null) return null;
  return objekt(w) ?? (throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.$feld ist kein Objekt)'));
}

/// Ein Wahrheitswert, der da sein muss: ein fehlendes „gezaehlt“ ist nicht „ungezaehlt“.
bool _wahrheitswert(Ort ort, String feld, Object? w) {
  if (w is! bool) throw antwortfehler(ort.name, 'Antwort enthaelt keinen Wahrheitswert (data.${ort.pfad}.$feld)');
  return w;
}

/// Eine Liste von Texten, die fehlen darf (dann leer); etwas anderes ist kaputt.
List<String> _textlisteOderLeer(Ort ort, String feld, Object? w) => w == null ? const [] : _textliste(ort, feld, w);

/// Wer etwas tat; fehlt die Angabe, `null`. Etwas anderes als ein Objekt ist
/// kaputt, nie still „niemand“.
StocktakeActor? _akteur(Ort ort, String feld, Object? w) {
  if (w == null) return null;
  final a = objekt(w);
  if (a == null) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.$feld ist kein Objekt)');
  return StocktakeActor(type: _textOderNull(a['type']), id: _textOderNull(a['id']), name: _textOderNull(a['name']));
}

StocktakeWarning _inventurWarnung(Ort ort, Object? w) {
  final h = _eintrag(ort, w);
  final code = h['code'];
  if (code is! String || code.isEmpty) throw antwortfehler(ort.name, 'Hinweis ohne Code (data.${ort.pfad}.code)');
  return StocktakeWarning(code: code, items: _ganzzahl(ort, 'items', h['items']), message: _text(h['message']));
}

/// Hinweise einer Inventur; fehlt die Liste, gibt es keine.
List<StocktakeWarning> inventurWarnungen(Ort ort, Object? w) {
  if (w == null) return const [];
  if (w is! List) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad} ist keine Liste)');
  return List.unmodifiable([for (final (i, h) in w.indexed) _inventurWarnung(Ort(ort.name, '${ort.pfad}[$i]'), h)]);
}

StocktakeSeal _siegel(Ort ort, Object? w) {
  final s = _eintrag(ort, w);
  return StocktakeSeal(
    fromDay: _textOderNull(s['fromDay']),
    toDay: _textOderNull(s['toDay']),
    daysChecked: _ganzzahlOderNull(ort, 'daysChecked', s['daysChecked']),
    verified: s['verified'] is bool ? s['verified'] as bool : null,
    firstBreak: _textOderNull(s['firstBreak']),
    gaps: _textlisteOderLeer(ort, 'gaps', s['gaps']),
    gapCount: _ganzzahlOderNull(ort, 'gapCount', s['gapCount']),
    notChecked: s['notChecked'] is String ? s['notChecked'] as String : null,
    checkedUntil: _textOderNull(s['checkedUntil']),
  );
}

/// Kopf einer Inventur. Was erst nach dem Abschluss kommt (Summen, Hinweise,
/// Siegel, Pruefsumme, Protokoll), steht im Modell nur, wenn der Server es
/// sendet; Werte nur mit dem Recht `costs`.
Stocktake inventur(Ort ort, Object? w) {
  final k = _eintrag(ort, w);
  final umfang = _objektOderNull(ort, 'scope', k['scope']);
  final fortschritt = _objektOderNull(ort, 'progress', k['progress']);
  final pruefung = _objektOderNull(ort, 'review', k['review']);
  final abschluss = _objektOderNull(ort, 'closing', k['closing']);
  final abbruch = _objektOderNull(ort, 'cancellation', k['cancellation']);
  final summen = _objektOderNull(ort, 'totals', k['totals']);
  final pdf = _objektOderNull(ort, 'pdf', k['pdf']);
  final uOrt = ort.unter('scope');
  final fOrt = ort.unter('progress');
  final pOrt = ort.unter('review');
  final aOrt = ort.unter('closing');
  final sOrt = ort.unter('totals');
  return Stocktake(
    id: _kennung(ort, 'id', k['id']),
    name: _text(k['name']),
    locationId: _textOderNull(k['locationId']),
    scope: umfang == null
        ? null
        : StocktakeScope(
            type: _textOderNull(umfang['type']),
            groupIds: _textlisteOderLeer(uOrt, 'groupIds', umfang['groupIds']),
            articleIds: _textlisteOderLeer(uOrt, 'articleIds', umfang['articleIds']),
          ),
    type: _textOderNull(k['type']),
    keyDate: _textOderNull(k['keyDate']),
    // Blind ist die sichere Vorgabe: nur ein ausdrueckliches false zeigt Bestand.
    blind: k['blind'] != false,
    status: _textOderNull(k['status']),
    progress: fortschritt == null
        ? null
        : StocktakeProgress(
            items: _ganzzahl(fOrt, 'items', fortschritt['items']),
            counted: _ganzzahlOderNull(fOrt, 'counted', fortschritt['counted']),
            recountOpen: fortschritt['recountOpen'] == true,
          ),
    createdAt: _text(k['createdAt']),
    createdBy: _akteur(ort, 'createdBy', k['createdBy']),
    source: _textOderNull(k['source']),
    updatedAt: _text(k['updatedAt']),
    review: pruefung == null
        ? null
        : StocktakeReview(
            startedAt: _text(pruefung['startedAt']),
            startedBy: _akteur(pOrt, 'startedBy', pruefung['startedBy']),
            complete: pruefung['complete'] == true,
            expectedAsOf: _text(pruefung['expectedAsOf']),
            recountUncounted: _ganzzahlOderNull(pOrt, 'recountUncounted', pruefung['recountUncounted']),
          ),
    closing: abschluss == null
        ? null
        : StocktakeClosing(
            startedAt: _text(abschluss['startedAt']),
            startedBy: _akteur(aOrt, 'startedBy', abschluss['startedBy']),
            uncountedAsZero: abschluss['uncountedAsZero'] == true,
            parts: _ganzzahlOderNull(aOrt, 'parts', abschluss['parts']),
            bookedParts: _ganzzahlOderNull(aOrt, 'bookedParts', abschluss['bookedParts']),
            completedAt: _text(abschluss['completedAt']),
          ),
    cancellation: abbruch == null
        ? null
        : StocktakeCancellation(
            reason: _text(abbruch['reason']),
            cancelledAt: _text(abbruch['cancelledAt']),
            cancelledBy: _akteur(ort.unter('cancellation'), 'cancelledBy', abbruch['cancelledBy']),
          ),
    totals: summen == null
        ? null
        : StocktakeTotals(
            items: _ganzzahl(sOrt, 'items', summen['items']),
            counted: _ganzzahl(sOrt, 'counted', summen['counted']),
            uncounted: _ganzzahl(sOrt, 'uncounted', summen['uncounted']),
            recounted: _ganzzahl(sOrt, 'recounted', summen['recounted']),
            withDifference: _ganzzahl(sOrt, 'withDifference', summen['withDifference']),
            needsCheck: _ganzzahl(sOrt, 'needsCheck', summen['needsCheck']),
            notBooked: _ganzzahl(sOrt, 'notBooked', summen['notBooked']),
            differenceValueCents: _ganzzahlOderNull(sOrt, 'differenceValueCents', summen['differenceValueCents']),
            inventoryValueCents: _ganzzahlOderNull(sOrt, 'inventoryValueCents', summen['inventoryValueCents']),
          ),
    warnings: k.containsKey('warnings') ? inventurWarnungen(ort.unter('warnings'), k['warnings']) : null,
    seal: k['seal'] == null ? null : _siegel(ort.unter('seal'), k['seal']),
    checksum: _textOderNull(k['checksum']),
    inventoryAsOf: _textOderNull(k['inventoryAsOf']),
    pdf: pdf == null
        ? null
        : StocktakePdfInfo(
            available: pdf['available'] == true,
            valuesSha256: pdf['valuesSha256'] is String ? pdf['valuesSha256'] as String : null,
            quantitiesSha256: pdf['quantitiesSha256'] is String ? pdf['quantitiesSha256'] as String : null,
          ),
  );
}

StocktakeNotBooked _nichtGebucht(Ort ort, Object? w) {
  final n = _eintrag(ort, w);
  final code = n['code'];
  if (code is! String || code.isEmpty) throw antwortfehler(ort.name, 'Antwort enthaelt keinen Grund (data.${ort.pfad}.code)');
  final gruende = n['reasons'];
  if (gruende != null && gruende is! List) {
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.reasons ist keine Liste)');
  }
  return StocktakeNotBooked(
    code: code,
    quantity: _ganzzahlOderNull(ort, 'quantity', n['quantity']),
    reasons: gruende == null
        ? null
        : List.unmodifiable([
            for (final (i, g) in (gruende as List).indexed)
              () {
                final gOrt = ort.unter('reasons[$i]');
                final r = _eintrag(gOrt, g);
                final c = r['code'];
                if (c is! String || c.isEmpty) {
                  throw antwortfehler(ort.name, 'Antwort enthaelt keinen Grund (data.${gOrt.pfad}.code)');
                }
                return (code: c, quantity: _ganzzahlOderNull(gOrt, 'quantity', r['quantity']));
              }(),
          ]),
  );
}

/// Eine Liste von Texten, die nur steht, wenn der Server sie sendet.
List<String>? _textlisteWennDa(Ort ort, String feld, Map<String, dynamic> o) =>
    o.containsKey(feld) ? _textlisteOderLeer(ort, feld, o[feld]) : null;

/// Eine Position. Soll, Differenz und alles aus Pruefung und Abschluss stehen
/// im Modell nur, wenn der Server sie sendet (blind: vor `review` nie).
StocktakeItem inventurPosition(Ort ort, Object? w) {
  final p = _eintrag(ort, w);
  // Wer gezaehlt hat, ist zugesagt: fehlt die Liste, ist die Antwort kaputt (nie „niemand“).
  final zaehler = p['countedBy'];
  if (zaehler is! List) throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.countedBy ist keine Liste)');
  final nachzaehlen = _objektOderNull(ort, 'recount', p['recount']);
  final nOrt = ort.unter('recount');
  final inventar = _objektOderNull(ort, 'inventory', p['inventory']);
  final iOrt = ort.unter('inventory');
  final counted = _wahrheitswert(ort, 'counted', p['counted']);
  final menge = _ganzzahlOderNull(ort, 'quantity', p['quantity']);
  // Gezaehlt heisst: es gibt eine Menge. Beides zusammen kaputt waere „0“ oder „nichts“ geraten.
  if (counted && menge == null) {
    throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.quantity fehlt bei counted: true)');
  }
  return StocktakeItem(
    articleId: _kennung(ort, 'articleId', p['articleId']),
    condition: _kennung(ort, 'condition', p['condition']),
    name: _text(p['name']),
    number: _text(p['number']),
    unit: _text(p['unit']),
    round: _ganzzahl(ort, 'round', p['round']),
    counted: counted,
    quantity: menge,
    counts: _ganzzahl(ort, 'counts', p['counts']),
    firstCountedAt: _text(p['firstCountedAt']),
    referenceTime: _text(p['referenceTime']),
    countedBy: List.unmodifiable([
      for (final (i, a) in zaehler.indexed)
        _akteur(ort, 'countedBy[$i]', a) ??
            (throw antwortfehler(ort.name, 'Antwort ist unbrauchbar (data.${ort.pfad}.countedBy[$i] ist kein Objekt)')),
    ]),
    // Die Zaehl- und Storno-Antwort sendet die Position ohne Seriennummern: dann `null`, nie [].
    serialNumbers: _textlisteWennDa(ort, 'serialNumbers', p),
    recountRequested: p['recountRequested'] == true,
    recount: nachzaehlen == null
        ? null
        : StocktakeRecount(
            reason: _text(nachzaehlen['reason']),
            requestedAt: _text(nachzaehlen['requestedAt']),
            requestedBy: _akteur(nOrt, 'requestedBy', nachzaehlen['requestedBy']),
            round: _ganzzahlOderNull(nOrt, 'round', nachzaehlen['round']),
          ),
    addedLater: p['addedLater'] == true,
    bookStockNow: _ganzzahlOderNull(ort, 'bookStockNow', p['bookStockNow']),
    expectedQuantity: _ganzzahlOderNull(ort, 'expectedQuantity', p['expectedQuantity']),
    differenceQuantity: _ganzzahlOderNull(ort, 'differenceQuantity', p['differenceQuantity']),
    needsCheck: p.containsKey('needsCheck') ? p['needsCheck'] == true : null,
    checkReasons: _textlisteWennDa(ort, 'checkReasons', p),
    expectedAsOf: _text(p['expectedAsOf']),
    differenceValueCents: _ganzzahlOderNull(ort, 'differenceValueCents', p['differenceValueCents']),
    missingSerialNumbers: _textlisteWennDa(ort, 'missingSerialNumbers', p),
    extraSerialNumbers: _textlisteWennDa(ort, 'extraSerialNumbers', p),
    bookedQuantity: _ganzzahlOderNull(ort, 'bookedQuantity', p['bookedQuantity']),
    notBooked: p['notBooked'] == null ? null : _nichtGebucht(ort.unter('notBooked'), p['notBooked']),
    inventory: inventar == null
        ? null
        : StocktakeInventoryLine(
            quantity: _ganzzahl(iOrt, 'quantity', inventar['quantity']),
            countedOn: _textOderNull(inventar['countedOn']),
            unitValueMicros: _ganzzahlOderNull(iOrt, 'unitValueMicros', inventar['unitValueMicros']),
            valueCents: _ganzzahlOderNull(iOrt, 'valueCents', inventar['valueCents']),
          ),
  );
}

/// Eine Zaehlung: Menge, Runde und Kennungen muessen da sein.
StocktakeCount inventurZaehlung(Ort ort, Object? w) {
  final z = _eintrag(ort, w);
  final storno = _objektOderNull(ort, 'voided', z['voided']);
  return StocktakeCount(
    id: _kennung(ort, 'id', z['id']),
    articleId: _kennung(ort, 'articleId', z['articleId']),
    condition: _kennung(ort, 'condition', z['condition']),
    quantity: _ganzzahl(ort, 'quantity', z['quantity']),
    // Die Zaehlung traegt ihre Seriennummern immer (leer bei Mengenartikeln); fehlt die Liste, ist sie kaputt.
    serialNumbers: _textliste(ort, 'serialNumbers', z['serialNumbers']),
    round: _ganzzahl(ort, 'round', z['round']),
    countedBy: _akteur(ort, 'countedBy', z['countedBy']),
    source: _textOderNull(z['source']),
    cashregisterId: _textOderNull(z['cashregisterId']),
    countedAt: _text(z['countedAt']),
    note: _text(z['note']),
    voided: storno == null
        ? null
        : StocktakeCountVoided(
            reason: _text(storno['reason']),
            voidedAt: _text(storno['voidedAt']),
            voidedBy: _akteur(ort.unter('voided'), 'voidedBy', storno['voidedBy']),
          ),
  );
}

/// Antwort von Zaehlen und Stornieren: beide Teile sind zugesagt.
StocktakeCountResult zaehlungMitPosition(String name, Map<String, dynamic> daten) => StocktakeCountResult(
      count: inventurZaehlung(Ort(name, 'count'), daten['count']),
      item: inventurPosition(Ort(name, 'item'), daten['item']),
    );

/// Lese-Link auf ein grosses Inventurprotokoll; ohne Adresse, Ablauf, Groesse
/// oder Pruefsumme ist er unbrauchbar.
StocktakePdfDownload protokollLink(String name, Object? w) {
  final ort = Ort(name, 'download');
  final d = _eintrag(ort, w);
  return StocktakePdfDownload(
    url: _kennung(ort, 'url', d['url']),
    expiresAt: _kennung(ort, 'expiresAt', d['expiresAt']),
    sizeBytes: _ganzzahl(ort, 'sizeBytes', d['sizeBytes']),
    sha256: _kennung(ort, 'sha256', d['sha256']),
    fileName: _textOderNull(d['fileName']),
    contentType: _textOderNull(d['contentType']),
  );
}

// ---- Listen ------------------------------------------------------------------

/// Eine zugesagte Liste `data.<feld>`, Eintrag fuer Eintrag gelesen.
List<T> liste<T>(String name, Map<String, dynamic> daten, String feld, T Function(Ort ort, Object? eintrag) lesen) {
  final roh = daten[feld];
  if (roh is! List) {
    throw antwortfehler(
        name,
        roh == null
            ? 'Antwort enthaelt keine Liste (data.$feld fehlt)'
            : 'Antwort ist unbrauchbar (data.$feld ist keine Liste)');
  }
  return List.unmodifiable([for (final (i, e) in roh.indexed) lesen(Ort(name, '$feld[$i]'), e)]);
}

/// Der Cursor der naechsten Seite; `null` am Ende. Etwas anderes als Text oder `null` ist kaputt.
String? naechsterCursor(String name, Map<String, dynamic> daten) {
  final c = daten['nextCursor'];
  if (c == null) return null;
  if (c is! String || c.isEmpty) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.nextCursor)');
  return c;
}
