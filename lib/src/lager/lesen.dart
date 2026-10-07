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
