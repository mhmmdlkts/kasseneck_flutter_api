// Bruecke vom Draht zur Anfrage: baut aus den Parametern eines Vertragsfalls
// (`v3/antworten/lager.json`, `params`) die typisierte Anfrage der
// schreibenden Lager-API und ruft sie auf. Der Test vergleicht danach, was
// hinausging, mit denselben Parametern; eine Bruecke, die ein Feld verliert
// oder erfindet, faellt dort auf.
//
// Ein fehlender `idempotencyKey` wird zum leeren Text: in Dart ist der
// Schluessel `required String`, „fehlt“ laesst sich nur so nachstellen, und
// der Client weist beides gleich ab.
import 'package:kasseneck_api/inventory.dart';

String _schluessel(Map<String, dynamic> p) => p['idempotencyKey'] as String? ?? '';

List<Map<String, dynamic>> _liste(Object? w) => [for (final e in (w as List? ?? const [])) (e as Map).cast<String, dynamic>()];

Map<String, String>? _texte(Object? w) => (w as Map?)?.cast<String, String>();

List<StockItem> _stueck(Object? w) => [
      for (final p in _liste(w))
        StockItem(articleId: p['articleId'] as String, quantity: p['quantity'] as int, serialNumber: p['serialNumber'] as String?),
    ];

List<GoodsReceiptItem> _eingang(Object? w) => [
      for (final p in _liste(w))
        GoodsReceiptItem(
          articleId: p['articleId'] as String,
          quantity: p['quantity'] as int,
          totalCents: p['totalCents'] as int?,
          unitPriceMicros: p['unitPriceMicros'] as int?,
          landedCostCents: p['landedCostCents'] as int?,
          expiresOn: p['expiresOn'] as String?,
          batch: p['batch'] as String?,
          serialNumbers: (p['serialNumbers'] as List?)?.cast<String>(),
        ),
    ];

List<LandedCost>? _nebenkosten(Object? w) => w == null
    ? null
    : [for (final n in _liste(w)) LandedCost(type: n['type'] as String, amountCents: n['amountCents'] as int)];

GoodsReceiptSupplier? _lieferant(Object? w) => w == null
    ? null
    : GoodsReceiptSupplier(name: (w as Map)['name'] as String, address: w['address'] as String?);

CreateArticleRequest artikelAnlegen(Map<String, dynamic> p) => CreateArticleRequest(
      idempotencyKey: _schluessel(p),
      name: p['name'] as String,
      description: p['description'] as String?,
      unitPriceCents: p['unitPriceCents'] as int?,
      vatRate: p['vatRate'] as num?,
      unit: p['unit'] as String?,
      number: p['number'] as String?,
      ean: p['ean'] as String?,
      groupId: p['groupId'] as String?,
      revenueGroupId: p['revenueGroupId'] as String?,
      stockTracked: p['stockTracked'] as bool?,
      stockLocationIds: (p['stockLocationIds'] as List?)?.cast<String>(),
      minStock: p['minStock'] as int?,
      minStockByLocation: (p['minStockByLocation'] as Map?)?.cast<String, int>(),
      stockKind: p['stockKind'] as String?,
      purchasePriceMicros: p['purchasePriceMicros'] as int?,
      externalIds: _texte(p['externalIds']),
      metadata: _texte(p['metadata']),
    );

/// `null` am Draht heisst „leeren“: es wird ein Eintrag in `clear`.
UpdateArticleRequest artikelAendern(Map<String, dynamic> p) => UpdateArticleRequest(
      idempotencyKey: _schluessel(p),
      articleId: p['articleId'] as String,
      name: p['name'] as String?,
      description: p['description'] as String?,
      unitPriceCents: p['unitPriceCents'] as int?,
      vatRate: p['vatRate'] as num?,
      unit: p['unit'] as String?,
      number: p['number'] as String?,
      ean: p['ean'] as String?,
      groupId: p['groupId'] as String?,
      revenueGroupId: p['revenueGroupId'] as String?,
      stockTracked: p['stockTracked'] as bool?,
      stockLocationIds: (p['stockLocationIds'] as List?)?.cast<String>(),
      minStock: p['minStock'] as int?,
      minStockByLocation: (p['minStockByLocation'] as Map?)?.cast<String, int?>(),
      stockKind: p['stockKind'] as String?,
      purchasePriceMicros: p['purchasePriceMicros'] as int?,
      externalIds: _texte(p['externalIds']),
      metadata: _texte(p['metadata']),
      clear: {for (final e in p.entries) if (e.value == null) e.key},
    );

ReceiveGoodsRequest wareneingang(Map<String, dynamic> p) => ReceiveGoodsRequest(
      idempotencyKey: _schluessel(p),
      items: _eingang(p['items']),
      locationId: p['locationId'] as String?,
      landedCosts: _nebenkosten(p['landedCosts']),
      allocation: p['allocation'] as String?,
      supplier: _lieferant(p['supplier']),
      reference: p['reference'] as String?,
      note: p['note'] as String?,
    );

GoodsReceiptPreviewRequest vorschau(Map<String, dynamic> p) => GoodsReceiptPreviewRequest(
      idempotencyKey: p['idempotencyKey'] as String?,
      items: _eingang(p['items']),
      locationId: p['locationId'] as String?,
      landedCosts: _nebenkosten(p['landedCosts']),
      allocation: p['allocation'] as String?,
      supplier: _lieferant(p['supplier']),
      reference: p['reference'] as String?,
      note: p['note'] as String?,
    );

TransferStockRequest umbuchung(Map<String, dynamic> p) => TransferStockRequest(
      idempotencyKey: _schluessel(p),
      fromLocationId: p['fromLocationId'] as String,
      toLocationId: p['toLocationId'] as String,
      items: _stueck(p['items']),
      note: p['note'] as String?,
    );

RecordStockLossRequest abgang(Map<String, dynamic> p) => RecordStockLossRequest(
      idempotencyKey: _schluessel(p),
      reason: p['reason'] as String,
      withdrawalType: p['withdrawalType'] as String?,
      condition: p['condition'] as String?,
      locationId: p['locationId'] as String?,
      items: _stueck(p['items']),
      note: p['note'] as String?,
    );

ChangeStockConditionRequest zustand(Map<String, dynamic> p) => ChangeStockConditionRequest(
      idempotencyKey: _schluessel(p),
      from: p['from'] as String,
      to: p['to'] as String,
      locationId: p['locationId'] as String?,
      items: _stueck(p['items']),
      note: p['note'] as String?,
    );

ReverseStockMovementRequest gegenbuchung(Map<String, dynamic> p) => ReverseStockMovementRequest(
      idempotencyKey: _schluessel(p),
      operationId: p['operationId'] as String,
      reason: p['reason'] as String,
    );

CreateReservationRequest reservieren(Map<String, dynamic> p) => CreateReservationRequest(
      idempotencyKey: _schluessel(p),
      items: [
        for (final i in _liste(p['items']))
          ReservationItemInput(
              articleId: i['articleId'] as String, quantity: i['quantity'] as int, locationId: i['locationId'] as String?),
      ],
      reference: p['reference'] as String?,
      expiresInMinutes: p['expiresInMinutes'] as int?,
    );

ExtendReservationRequest verlaengern(Map<String, dynamic> p) => ExtendReservationRequest(
      idempotencyKey: _schluessel(p),
      reservationId: p['reservationId'] as String,
      expiresInMinutes: p['expiresInMinutes'] as int,
    );

ReleaseReservationRequest freigeben(Map<String, dynamic> p) => ReleaseReservationRequest(
      idempotencyKey: _schluessel(p),
      reservationId: p['reservationId'] as String,
      items: p['items'] == null
          ? null
          : [
              for (final i in _liste(p['items']))
                ReleaseReservationItem(
                    articleId: i['articleId'] as String,
                    locationId: i['locationId'] as String?,
                    quantity: i['quantity'] as int?),
            ],
    );

List<VariantAttribute> _merkmale(Object? w) => [
      for (final m in _liste(w))
        VariantAttribute(key: m['key'] as String, label: m['label'] as String, values: (m['values'] as List).cast<String>()),
    ];

/// `null` je Feld heisst „leeren“ (bei der Anlage „nicht angegeben“): ein Eintrag in `clear`.
VariantGroupDefaultsInput? vorgaben(Object? w) {
  if (w == null) return null;
  final d = (w as Map).cast<String, dynamic>();
  return VariantGroupDefaultsInput(
    unitPriceCents: d['unitPriceCents'] as int?,
    vatRate: d['vatRate'] as num?,
    unit: d['unit'] as String?,
    groupId: d['groupId'] as String?,
    stockTracked: d['stockTracked'] as bool?,
    clear: {for (final e in d.entries) if (e.value == null) e.key},
  );
}

VariantInput variante(Map<String, dynamic> p) => VariantInput(
      variantAttributes: _texte(p['variantAttributes'])!,
      name: p['name'] as String?,
      description: p['description'] as String?,
      unitPriceCents: p['unitPriceCents'] as int?,
      vatRate: p['vatRate'] as num?,
      unit: p['unit'] as String?,
      number: p['number'] as String?,
      ean: p['ean'] as String?,
      groupId: p['groupId'] as String?,
      revenueGroupId: p['revenueGroupId'] as String?,
      stockTracked: p['stockTracked'] as bool?,
      stockLocationIds: (p['stockLocationIds'] as List?)?.cast<String>(),
      minStock: p['minStock'] as int?,
      minStockByLocation: (p['minStockByLocation'] as Map?)?.cast<String, int>(),
      stockKind: p['stockKind'] as String?,
      purchasePriceMicros: p['purchasePriceMicros'] as int?,
      externalIds: _texte(p['externalIds']),
      metadata: _texte(p['metadata']),
    );

CreateVariantGroupRequest gruppeAnlegen(Map<String, dynamic> p) => CreateVariantGroupRequest(
      idempotencyKey: _schluessel(p),
      name: p['name'] as String,
      attributes: _merkmale(p['attributes']),
      defaults: vorgaben(p['defaults']),
      createMatrix: p['createMatrix'] as bool?,
      variants: p['variants'] == null ? null : [for (final v in _liste(p['variants'])) variante(v)],
    );

/// `defaults: null` am Draht heisst „alle Vorgaben leeren“: [UpdateVariantGroupRequest.clearDefaults].
UpdateVariantGroupRequest gruppeAendern(Map<String, dynamic> p) => UpdateVariantGroupRequest(
      idempotencyKey: _schluessel(p),
      variantGroupId: p['variantGroupId'] as String,
      name: p['name'] as String?,
      defaults: vorgaben(p['defaults']),
      clearDefaults: p.containsKey('defaults') && p['defaults'] == null,
      addAttributeValues: (p['addAttributeValues'] as Map?)
          ?.map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
      active: p['active'] as bool?,
    );

AddVariantRequest varianteErgaenzen(Map<String, dynamic> p) {
  final v = variante(p);
  return AddVariantRequest(
    idempotencyKey: _schluessel(p),
    variantGroupId: p['variantGroupId'] as String,
    variantAttributes: v.variantAttributes,
    name: v.name,
    description: v.description,
    unitPriceCents: v.unitPriceCents,
    vatRate: v.vatRate,
    unit: v.unit,
    number: v.number,
    ean: v.ean,
    groupId: v.groupId,
    revenueGroupId: v.revenueGroupId,
    stockTracked: v.stockTracked,
    stockLocationIds: v.stockLocationIds,
    minStock: v.minStock,
    minStockByLocation: v.minStockByLocation,
    stockKind: v.stockKind,
    purchasePriceMicros: v.purchasePriceMicros,
    externalIds: v.externalIds,
    metadata: v.metadata,
  );
}

/// Ruft den schreibenden Aufruf [endpunkt] mit den Drahtparametern [p] auf.
/// `receiveGoods` mit `dryRun: true` ist die Vorschau: ein eigener Aufruf,
/// `dryRun` gehoert nicht in die Buchung.
Future<Object?> schreibAufruf(InventoryClient l, String endpunkt, Map<String, dynamic> p) {
  switch (endpunkt) {
    case 'createArticle':
      return l.createArticle(artikelAnlegen(p));
    case 'updateArticle':
      return l.updateArticle(artikelAendern(p));
    case 'deactivateArticle':
      return l.deactivateArticle(
          DeactivateArticleRequest(idempotencyKey: _schluessel(p), articleId: p['articleId'] as String));
    case 'receiveGoods':
      return p['dryRun'] == true ? l.previewGoodsReceipt(vorschau(p)) : l.receiveGoods(wareneingang(p));
    case 'transferStock':
      return l.transferStock(umbuchung(p));
    case 'recordStockLoss':
      return l.recordStockLoss(abgang(p));
    case 'changeStockCondition':
      return l.changeStockCondition(zustand(p));
    case 'reverseStockMovement':
      return l.reverseStockMovement(gegenbuchung(p));
    case 'createReservation':
      return l.createReservation(reservieren(p));
    case 'extendReservation':
      return l.extendReservation(verlaengern(p));
    case 'releaseReservation':
      return l.releaseReservation(freigeben(p));
    case 'getReservation':
      return l.getReservation(p['reservationId'] as String);
    case 'listReservations':
      return l.listReservations(
        status: p['status'] as String?,
        reference: p['reference'] as String?,
        limit: p['limit'] as int?,
        cursor: p['cursor'] as String?,
      );
    case 'createVariantGroup':
      return l.createVariantGroup(gruppeAnlegen(p));
    case 'updateVariantGroup':
      return l.updateVariantGroup(gruppeAendern(p));
    case 'addVariant':
      return l.addVariant(varianteErgaenzen(p));
    case 'getVariantGroup':
      return l.getVariantGroup(p['variantGroupId'] as String);
    case 'listVariantGroups':
      return l.listVariantGroups(
        active: p['active'] as bool?,
        updatedSince: p['updatedSince'] == null ? null : DateTime.parse(p['updatedSince'] as String),
        limit: p['limit'] as int?,
        cursor: p['cursor'] as String?,
      );
  }
  throw StateError('kein Aufruf fuer $endpunkt');
}
