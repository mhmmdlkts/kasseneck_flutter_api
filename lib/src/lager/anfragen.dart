/// Die Anfragen der schreibenden Lager-API (Backend Stufe 5b): Artikel
/// anlegen, aendern und stilllegen, Bestand buchen und Ware reservieren –
/// Zwilling der Anfragetypen in `src/inventory/typen.ts` im JS-Paket.
///
/// **Jede schreibende Anfrage traegt `idempotencyKey`** (1–120 Zeichen,
/// Pflicht): dieselbe Anfrage mit demselben Schluessel wirkt genau einmal, eine
/// Wiederholung liefert die gespeicherte Antwort von damals. Derselbe
/// Schluessel mit anderem Inhalt ergibt `idempotency_conflict`. Nach einem
/// Zeitlimit also mit **demselben** Schluessel wiederholen, nie mit einem
/// neuen: ein neuer buchte ein zweites Mal. Den Schluessel darum vor dem
/// ersten Senden festlegen und mit dem Auftrag speichern (etwa die Nummer der
/// Bestellung samt Schritt, `shop-res-1001`).
///
/// Mengen in Tausendstel der Basiseinheit, Geld in Cent, Einkaufspreise in
/// Mikro-Euro; alles Ganzzahlen. Katalogwerte (Grund, Zustand, Art) bleiben
/// Text und gehen unveraendert hinaus: einen unbekannten Wert weist der Server
/// mit seinem Code ab (`invalid_reason`, `invalid_condition`, `validation`).
///
/// `toJson()` ist die Drahtform; ein Feld, das `null` ist, geht nicht hinaus.
/// Leeren (am Draht `null`) laesst sich ein Feld nur ueber
/// [UpdateArticleRequest.clear].
///
/// Schreiben braucht den Konto-Schalter „Lager-API schreiben“ (sonst
/// `inventory_api_not_enabled`); in der Test-Umgebung (`kr_test_…`) ist er
/// immer an.
library;

// ---- Artikel ------------------------------------------------------------------

/// Die Felder eines Artikels beim Anlegen.
class ArticleInput {
  const ArticleInput({
    required this.name,
    this.description,
    this.unitPriceCents,
    this.vatRate,
    this.unit,
    this.number,
    this.ean,
    this.groupId,
    this.revenueGroupId,
    this.stockTracked,
    this.stockLocationIds,
    this.minStock,
    this.minStockByLocation,
    this.stockKind,
    this.purchasePriceMicros,
    this.externalIds,
    this.metadata,
  });

  /// 1–200 Zeichen, getrimmt gespeichert.
  final String name;

  /// Bis 2000 Zeichen.
  final String? description;
  final int? unitPriceCents;

  /// USt-Satz in Prozent (`20`, `13`, `10`, `4.9`, `0`, `19`).
  final num? vatRate;

  /// 1–20 Zeichen; ohne Angabe die Vorgabe des Kontos.
  final String? unit;

  /// Artikelnummer, 1–64 Zeichen.
  final String? number;

  /// GTIN/EAN mit gueltiger Pruefziffer: der Artikel wird ein Fremdartikel mit
  /// diesem Code. Ohne `ean` vergibt der Server einen eigenen Code nach den
  /// Einstellungen des Kontos (`internalCode`). Ein Code, der schon einem
  /// anderen Artikel gehoert, ergibt `code_taken` (mit `field` und `articleId`).
  final String? ean;

  /// Artikelgruppe; unbekannt = `group_not_found`.
  final String? groupId;

  /// Erloesgruppe; unbekannt = `revenue_group_not_found`.
  final String? revenueGroupId;
  final bool? stockTracked;

  /// Hoechstens 50 Standorte; unbekannt = `location_not_found`.
  final List<String>? stockLocationIds;

  /// **Altfeld** ohne Wirkung auf Meldungen; Tausendstel in ganzen Einheiten
  /// (Vielfaches von 1000).
  final int? minStock;

  /// Mindestbestand je Standort in Tausendstel, hoechstens 50 Standorte.
  final Map<String, int>? minStockByLocation;

  /// Ein Wert aus `stockKinds`; nach der ersten Bewegung fest.
  final String? stockKind;

  /// Standard-Einkaufspreis je Basiseinheit in Mikro-Euro. Nur mit dem
  /// Konto-Recht `costs`, sonst `inventory_api_not_enabled` mit dem Feldfehler
  /// `purchasePriceMicros`.
  final int? purchasePriceMicros;

  /// Eigene Kennungen je System (`{'shop': '1001'}`): hoechstens 10 Systeme
  /// `^[a-z0-9_]{1,32}$`, Werte 1–128 Zeichen, je System und Wert eindeutig im
  /// Konto (`external_id_taken`). Damit findet `lookupArticleByCode` den Artikel.
  final Map<String, String>? externalIds;

  /// Freie Merkmale, nie ausgewertet: hoechstens 20 Schluessel
  /// `^[a-zA-Z0-9_]{1,40}$`, Werte bis 500 Zeichen, zusammen 4 KB.
  final Map<String, String>? metadata;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': ?description,
    'unitPriceCents': ?unitPriceCents,
    'vatRate': ?vatRate,
    'unit': ?unit,
    'number': ?number,
    'ean': ?ean,
    'groupId': ?groupId,
    'revenueGroupId': ?revenueGroupId,
    'stockTracked': ?stockTracked,
    if (stockLocationIds != null) 'stockLocationIds': [...stockLocationIds!],
    'minStock': ?minStock,
    if (minStockByLocation != null) 'minStockByLocation': {...minStockByLocation!},
    'stockKind': ?stockKind,
    'purchasePriceMicros': ?purchasePriceMicros,
    if (externalIds != null) 'externalIds': {...externalIds!},
    if (metadata != null) 'metadata': {...metadata!},
  };
}

/// Legt einen Artikel an (`createArticle`).
class CreateArticleRequest extends ArticleInput {
  const CreateArticleRequest({
    required this.idempotencyKey,
    required super.name,
    super.description,
    super.unitPriceCents,
    super.vatRate,
    super.unit,
    super.number,
    super.ean,
    super.groupId,
    super.revenueGroupId,
    super.stockTracked,
    super.stockLocationIds,
    super.minStock,
    super.minStockByLocation,
    super.stockKind,
    super.purchasePriceMicros,
    super.externalIds,
    super.metadata,
  });

  final String idempotencyKey;

  @override
  Map<String, dynamic> toJson() => {'idempotencyKey': idempotencyKey, ...super.toJson()};
}

/// Eine Aenderung (`updateArticle`): nur die genannten Felder, mindestens eines.
///
/// `externalIds` und `metadata` werden ganz ersetzt, `minStockByLocation` je
/// Standort zusammengefuehrt (`{'haupt': null}` nimmt nur diesen Standort weg).
/// Die EAN laesst sich nur bei Fremdartikeln wechseln; `stockKind` nach der
/// ersten Bewegung nicht mehr (`stock_kind_locked`). Ein stillgelegter Artikel
/// ergibt `article_inactive`.
class UpdateArticleRequest {
  const UpdateArticleRequest({
    required this.idempotencyKey,
    required this.articleId,
    this.name,
    this.description,
    this.unitPriceCents,
    this.vatRate,
    this.unit,
    this.number,
    this.ean,
    this.groupId,
    this.revenueGroupId,
    this.stockTracked,
    this.stockLocationIds,
    this.minStock,
    this.minStockByLocation,
    this.stockKind,
    this.purchasePriceMicros,
    this.externalIds,
    this.metadata,
    this.clear = const {},
  });

  final String idempotencyKey;
  final String articleId;
  final String? name;
  final String? description;
  final int? unitPriceCents;
  final num? vatRate;
  final String? unit;
  final String? number;
  final String? ean;
  final String? groupId;
  final String? revenueGroupId;
  final bool? stockTracked;
  final List<String>? stockLocationIds;
  final int? minStock;

  /// Je Standort zusammengefuehrt; ein `null`-Wert nimmt den Mindestbestand
  /// dieses Standorts weg, die uebrigen bleiben.
  final Map<String, int?>? minStockByLocation;
  final String? stockKind;
  final int? purchasePriceMicros;
  final Map<String, String>? externalIds;
  final Map<String, String>? metadata;

  /// Felder, die geleert werden (am Draht `null`): `description`,
  /// `unitPriceCents`, `vatRate`, `number`, `groupId`, `revenueGroupId`,
  /// `minStock`, `stockLocationIds`, `externalIds`, `metadata`,
  /// `minStockByLocation`, `purchasePriceMicros`. `name`, `unit`, `ean`,
  /// `stockTracked` und `stockKind` lassen sich nicht leeren. Ein Feld zugleich
  /// setzen und leeren, ein anderes Feld oder ein Tippfehler gehen nicht hinaus
  /// (`KasseneckValidationError`).
  final Set<String> clear;

  /// Ein Feld, das zugleich gesetzt und in [clear] steht, behaelt hier seinen
  /// Wert; `updateArticle` weist die Anfrage dann ab, statt eine Seite still
  /// gewinnen zu lassen.
  Map<String, dynamic> toJson() {
    final werte = <String, dynamic>{
      'idempotencyKey': idempotencyKey,
      'articleId': articleId,
      'name': ?name,
      'description': ?description,
      'unitPriceCents': ?unitPriceCents,
      'vatRate': ?vatRate,
      'unit': ?unit,
      'number': ?number,
      'ean': ?ean,
      'groupId': ?groupId,
      'revenueGroupId': ?revenueGroupId,
      'stockTracked': ?stockTracked,
      if (stockLocationIds != null) 'stockLocationIds': [...stockLocationIds!],
      'minStock': ?minStock,
      if (minStockByLocation != null) 'minStockByLocation': {...minStockByLocation!},
      'stockKind': ?stockKind,
      'purchasePriceMicros': ?purchasePriceMicros,
      if (externalIds != null) 'externalIds': {...externalIds!},
      if (metadata != null) 'metadata': {...metadata!},
    };
    return {
      ...werte,
      for (final feld in clear)
        if (!werte.containsKey(feld)) feld: null,
    };
  }
}

/// Stilllegen (`deactivateArticle`): `active: false`; Code und eigene
/// Kennungen werden frei. Schon stillgelegt = dieselbe Antwort, nichts
/// geschrieben. Den Bestand behaelt der Artikel, gebucht werden darf weiter.
class DeactivateArticleRequest {
  const DeactivateArticleRequest({required this.idempotencyKey, required this.articleId});

  final String idempotencyKey;
  final String articleId;

  Map<String, dynamic> toJson() => {'idempotencyKey': idempotencyKey, 'articleId': articleId};
}

// ---- Wareneingang ------------------------------------------------------------

/// Eine Position eines Wareneingangs.
class GoodsReceiptItem {
  const GoodsReceiptItem({
    required this.articleId,
    required this.quantity,
    this.totalCents,
    this.unitPriceMicros,
    this.landedCostCents,
    this.expiresOn,
    this.batch,
    this.serialNumbers,
  });

  final String articleId;

  /// Tausendstel, groesser als 0.
  final int quantity;

  /// Gesamtpreis der Position in Cent. Entweder dieser oder [unitPriceMicros];
  /// ohne beide der Einkaufspreis des Artikels.
  final int? totalCents;

  /// Einzelpreis je Basiseinheit in Mikro-Euro.
  final int? unitPriceMicros;

  /// Nebenkosten dieser Position in Cent; gilt nur bei `allocation: 'manual'`.
  final int? landedCostCents;

  /// Ablaufdatum `YYYY-MM-DD`.
  final String? expiresOn;

  /// Charge, 1–64 Zeichen.
  final String? batch;

  /// Seriennummern (Einzelstuecke), hoechstens 80, je 1–128 Zeichen.
  final List<String>? serialNumbers;

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'quantity': quantity,
    'totalCents': ?totalCents,
    'unitPriceMicros': ?unitPriceMicros,
    'landedCostCents': ?landedCostCents,
    'expiresOn': ?expiresOn,
    'batch': ?batch,
    if (serialNumbers != null) 'serialNumbers': [...serialNumbers!],
  };
}

/// Nebenkosten eines Wareneingangs.
class LandedCost {
  const LandedCost({required this.type, required this.amountCents});

  /// Ein Wert aus `landedCostTypes`.
  final String type;

  /// Betrag in Cent; `discount` und `cash_discount` mindern den Wert.
  final int amountCents;

  Map<String, dynamic> toJson() => {'type': type, 'amountCents': amountCents};
}

/// Lieferant eines Wareneingangs.
class GoodsReceiptSupplier {
  const GoodsReceiptSupplier({required this.name, this.address});

  final String name;
  final String? address;

  Map<String, dynamic> toJson() => {'name': name, 'address': ?address};
}

/// Bucht einen Wareneingang (`receiveGoods`). Preise und Nebenkosten darf
/// jeder Schreibende senden (so bekommt der Bestand seinen Wert); zurueck
/// kommen Werte nur mit dem Recht `costs` und nur in der Vorschau
/// ([GoodsReceiptPreviewRequest]).
class ReceiveGoodsRequest {
  const ReceiveGoodsRequest({
    required this.idempotencyKey,
    required this.items,
    this.locationId,
    this.landedCosts,
    this.allocation,
    this.supplier,
    this.reference,
    this.note,
  });

  final String idempotencyKey;

  /// Hoechstens 80 Positionen (`too_many_positions`).
  final List<GoodsReceiptItem> items;

  /// Ohne Angabe der Standard-Standort des Kontos.
  final String? locationId;

  /// Hoechstens 20.
  final List<LandedCost>? landedCosts;

  /// Ein Wert aus `landedCostAllocations`; Vorgabe des Servers `value`.
  final String? allocation;
  final GoodsReceiptSupplier? supplier;

  /// Lieferschein o. Ae., 1–80 Zeichen.
  final String? reference;

  /// 1–500 Zeichen.
  final String? note;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    ..._wareneingang(items, locationId, landedCosts, allocation, supplier, reference, note),
  };
}

/// Vorschau eines Wareneingangs (`previewGoodsReceipt`, am Draht
/// `receiveGoods` mit `dryRun: true`): dieselben Felder wie
/// [ReceiveGoodsRequest], der Schluessel ist freigestellt. Ein mitgesendeter
/// Schluessel wird nur auf seine Form geprueft und nicht verbraucht; dieselbe
/// Anfrage laesst sich danach mit ihm buchen. Das Schreibrecht braucht die
/// Vorschau trotzdem; den Standort prueft erst die Buchung.
class GoodsReceiptPreviewRequest {
  const GoodsReceiptPreviewRequest({
    this.idempotencyKey,
    required this.items,
    this.locationId,
    this.landedCosts,
    this.allocation,
    this.supplier,
    this.reference,
    this.note,
  });

  final String? idempotencyKey;
  final List<GoodsReceiptItem> items;
  final String? locationId;
  final List<LandedCost>? landedCosts;
  final String? allocation;
  final GoodsReceiptSupplier? supplier;
  final String? reference;
  final String? note;

  /// Ohne `dryRun`; das setzt `previewGoodsReceipt` selbst.
  Map<String, dynamic> toJson() => {
    'idempotencyKey': ?idempotencyKey,
    ..._wareneingang(items, locationId, landedCosts, allocation, supplier, reference, note),
  };
}

Map<String, dynamic> _wareneingang(
  List<GoodsReceiptItem> items,
  String? locationId,
  List<LandedCost>? landedCosts,
  String? allocation,
  GoodsReceiptSupplier? supplier,
  String? reference,
  String? note,
) => {
  'items': [for (final p in items) p.toJson()],
  'locationId': ?locationId,
  if (landedCosts != null) 'landedCosts': [for (final n in landedCosts) n.toJson()],
  'allocation': ?allocation,
  'supplier': ?supplier?.toJson(),
  'reference': ?reference,
  'note': ?note,
};

// ---- Umbuchung, Abgang, Zustand, Gegenbuchung -------------------------------------

/// Eine Position von Umbuchung, Abgang oder Zustandswechsel.
class StockItem {
  const StockItem({required this.articleId, required this.quantity, this.serialNumber});

  final String articleId;

  /// Tausendstel, groesser als 0.
  final int quantity;

  /// Bei Einzelstuecken das Stueck.
  final String? serialNumber;

  Map<String, dynamic> toJson() => {'articleId': articleId, 'quantity': quantity, 'serialNumber': ?serialNumber};
}

/// Umbuchung zwischen zwei Standorten (`transferStock`). Ueberzieht nie
/// (`exceeds_stock`).
class TransferStockRequest {
  const TransferStockRequest({
    required this.idempotencyKey,
    required this.fromLocationId,
    required this.toLocationId,
    required this.items,
    this.note,
  });

  final String idempotencyKey;
  final String fromLocationId;
  final String toLocationId;
  final List<StockItem> items;
  final String? note;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'fromLocationId': fromLocationId,
    'toLocationId': toLocationId,
    'items': [for (final p in items) p.toJson()],
    'note': ?note,
  };
}

/// Abgang (`recordStockLoss`: Bruch, Schwund, Entnahme …). Ueberzieht nie
/// (`exceeds_stock`). `reason: 'other'` braucht [note] (`note_required`),
/// `reason: 'withdrawal'` braucht [withdrawalType] (`withdrawal_type_required`).
class RecordStockLossRequest {
  const RecordStockLossRequest({
    required this.idempotencyKey,
    required this.reason,
    required this.items,
    this.withdrawalType,
    this.condition,
    this.locationId,
    this.note,
  });

  final String idempotencyKey;

  /// Ein Wert aus `stockLossReasons`.
  final String reason;

  /// Ein Wert aus `withdrawalTypes`.
  final String? withdrawalType;

  /// Aus welchem Zustand (`stockConditions`); Vorgabe `sellable`.
  final String? condition;
  final String? locationId;
  final List<StockItem> items;
  final String? note;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'reason': reason,
    'withdrawalType': ?withdrawalType,
    'condition': ?condition,
    'locationId': ?locationId,
    'items': [for (final p in items) p.toJson()],
    'note': ?note,
  };
}

/// Ware zwischen verkaufbar und defekt umbuchen (`changeStockCondition`).
/// Ueberzieht nie (`exceeds_stock`).
class ChangeStockConditionRequest {
  const ChangeStockConditionRequest({
    required this.idempotencyKey,
    required this.from,
    required this.to,
    required this.items,
    this.locationId,
    this.note,
  });

  final String idempotencyKey;

  /// Werte aus `stockConditions`.
  final String from;
  final String to;
  final String? locationId;
  final List<StockItem> items;
  final String? note;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'from': from,
    'to': to,
    'locationId': ?locationId,
    'items': [for (final p in items) p.toJson()],
    'note': ?note,
  };
}

/// Gegenbuchung (`reverseStockMovement`): nimmt einen ganzen Vorgang zurueck.
/// Verkaeufe und Reservierungen gehen so nicht (`reversal_not_supported`), ein
/// zweites Mal auch nicht (`already_reversed`).
class ReverseStockMovementRequest {
  const ReverseStockMovementRequest({required this.idempotencyKey, required this.operationId, required this.reason});

  final String idempotencyKey;

  /// `StockOperation.operationId` des Vorgangs.
  final String operationId;

  /// Pflicht, bis 500 Zeichen; leer = `reason_required`.
  final String reason;

  Map<String, dynamic> toJson() => {'idempotencyKey': idempotencyKey, 'operationId': operationId, 'reason': reason};
}

// ---- Reservierung ---------------------------------------------------------------

/// Eine Position einer neuen Reservierung.
class ReservationItemInput {
  const ReservationItemInput({required this.articleId, required this.quantity, this.locationId});

  final String articleId;

  /// Tausendstel, groesser als 0.
  final int quantity;

  /// Ohne Angabe der Standard-Standort des Kontos.
  final String? locationId;

  Map<String, dynamic> toJson() => {'articleId': articleId, 'quantity': quantity, 'locationId': ?locationId};
}

/// Reservieren (`createReservation`, Checkout im Shop): ganz oder gar nicht.
/// Fehlt verfuegbarer Bestand an einer Position, entsteht nichts und der
/// Fehler `insufficient_available` nennt die fehlenden Positionen
/// (`inventoryShortfalls`). Nur bestandsgefuehrte Artikel; gleiche Artikel am
/// gleichen Standort werden zusammengezaehlt.
class CreateReservationRequest {
  const CreateReservationRequest({
    required this.idempotencyKey,
    required this.items,
    this.reference,
    this.expiresInMinutes,
  });

  final String idempotencyKey;

  /// 1–50 Positionen.
  final List<ReservationItemInput> items;

  /// 1–128 Zeichen; `listReservations(reference: …)` findet sie damit.
  final String? reference;

  /// 5 … 43 200 Minuten; ohne Angabe die Vorgabe des Kontos (7 Tage).
  final int? expiresInMinutes;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'items': [for (final p in items) p.toJson()],
    'reference': ?reference,
    'expiresInMinutes': ?expiresInMinutes,
  };
}

/// Verlaengern (`extendReservation`): neuer Ablauf = jetzt + Minuten. Nur
/// eine aktive, noch nicht faellige Reservierung (`reservation_not_active`).
class ExtendReservationRequest {
  const ExtendReservationRequest({
    required this.idempotencyKey,
    required this.reservationId,
    required this.expiresInMinutes,
  });

  final String idempotencyKey;
  final String reservationId;

  /// 5 … 43 200 Minuten.
  final int expiresInMinutes;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'reservationId': reservationId,
    'expiresInMinutes': expiresInMinutes,
  };
}

/// Eine Position einer Freigabe.
class ReleaseReservationItem {
  const ReleaseReservationItem({required this.articleId, this.locationId, this.quantity});

  final String articleId;
  final String? locationId;

  /// Ohne Angabe der ganze offene Rest der Position.
  final int? quantity;

  Map<String, dynamic> toJson() => {'articleId': articleId, 'locationId': ?locationId, 'quantity': ?quantity};
}

/// Freigeben (`releaseReservation`): ohne [items] alles, sonst je Position
/// (ganz oder teilweise). Der Status wird erst `released`, wenn nichts mehr
/// offen ist.
class ReleaseReservationRequest {
  const ReleaseReservationRequest({required this.idempotencyKey, required this.reservationId, this.items});

  final String idempotencyKey;
  final String reservationId;

  /// Nicht leer; ganz weglassen, um alles freizugeben.
  final List<ReleaseReservationItem>? items;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'reservationId': reservationId,
    if (items != null) 'items': [for (final p in items!) p.toJson()],
  };
}
