/// Die Modelle der Lager-API, so wie sie am Draht `/v3` stehen – Zwilling von
/// `src/inventory/typen.ts` im JS-Paket.
///
/// **Ganzzahlen mit fester Skala:** Mengen in Tausendstel der Basiseinheit
/// (`1000` = 1 Stueck, `250` = 0,250 kg), Geld in Cent, Einkaufspreise in
/// Mikro-Euro (`1000000` = 1 €). Nichts davon wird geteilt oder gerundet;
/// eine Bruchzahl in einer Antwort ist ein Antwortfehler
/// (`KasseneckValidationError` mit `kind: response`), nie ein Ersatzwert.
///
/// Zeitpunkte sind ISO 8601 in UTC (`2026-10-06T08:15:00.000Z`), Tage (Wiener
/// Tag) `YYYY-MM-DD`. Katalogwerte (Typ, Quelle, Ursache, Status) bleiben
/// Text: ein Wert, den diese Paketversion nicht kennt, kommt unveraendert an.
///
/// Jedes Modell hat `toJson()` in der Drahtform (etwa zum Speichern einer
/// eigenen Kopie). Optionale Felder, die der Server nur mit einem Recht sendet,
/// fehlen dort ganz, wenn sie in der Antwort fehlten; `has…` sagt, ob sie da
/// waren („fehlt“ heisst „kein Recht“, nicht „leer“).
library;

import '../kasse/lager.dart' show StockValue;

/// Ein Artikel, wie `getArticle`, `listArticles`, `lookupArticleByCode` und die
/// Ereignisse `article.*` ihn senden.
class Article {
  Article({
    required this.id,
    this.name,
    this.description,
    this.unitPriceCents,
    this.vatRate,
    this.unit,
    this.number,
    this.ean,
    this.internalCode,
    this.groupId,
    this.revenueGroupId,
    this.stockTracked = false,
    this.stockKind,
    this.stockLocationIds = const [],
    this.minStock,
    this.minStockByLocation = const {},
    this.active = true,
    this.externalIds,
    this.metadata,
    this.variantGroupId,
    this.variantAttributes,
    this.createdAt,
    this.updatedAt,
    this.purchasePriceMicros,
    bool? hasPurchasePriceMicros,
  }) : hasPurchasePriceMicros = hasPurchasePriceMicros ?? purchasePriceMicros != null;

  final String id;
  final String? name;

  /// Beschreibung (bis 2000 Zeichen); `null` = keine. Seit 10.4.
  final String? description;
  final int? unitPriceCents;

  /// USt-Satz in Prozent, z. B. `20`, `10`, `4.9`.
  final num? vatRate;
  final String? unit;
  final String? number;
  final String? ean;
  final String? internalCode;
  final String? groupId;
  final String? revenueGroupId;
  final bool stockTracked;

  /// Meist ein Wert aus `stockKinds`: `quantity` (Menge) oder `serial`
  /// (Einzelstueck). `null`, wenn der Server das Feld nicht sendet (vor Stufe
  /// 5b); ein Wert, den diese Paketversion nicht kennt, bleibt als Text stehen.
  /// Seit 10.4.
  final String? stockKind;

  /// Standorte, an denen der Artikel gefuehrt wird; leer = nur der Standard-Standort.
  final List<String> stockLocationIds;

  /// **Altfeld.** Mindestbestand des Artikels in Tausendstel; `null` = keiner.
  /// Er loest nichts aus: Warnungen, `belowMinimum` und `stock.below_minimum`
  /// richten sich nach [minStockByLocation].
  final int? minStock;

  /// Mindestbestand je Standort in Tausendstel (`{'haupt': 20000}`), die
  /// Schwelle fuer `below_minimum`, gemessen am verfuegbaren Bestand
  /// (`onHand - reserved`). Leer = keiner, auch wenn ein Server vor Stufe 5b
  /// das Feld nicht sendet. Seit 10.4.
  final Map<String, int> minStockByLocation;
  final bool active;

  /// Eigene Kennungen je Fremdsystem (`{'shop': '4711'}`); `null`, wenn der
  /// Artikel keine traegt.
  final Map<String, String>? externalIds;
  final Map<String, String>? metadata;
  final String? variantGroupId;
  final Map<String, String>? variantAttributes;
  final String? createdAt;
  final String? updatedAt;

  /// Einkaufspreis je Basiseinheit in Mikro-Euro (Wiederbeschaffungs- vor
  /// letztem vor Standard-Einkaufspreis); `null` = keiner hinterlegt oder kein
  /// Recht, siehe [hasPurchasePriceMicros].
  final int? purchasePriceMicros;

  /// Stand `purchasePriceMicros` in der Antwort? Nur mit dem Recht `costs`
  /// (Konto-Schalter `lagerApi.kosten`); ohne fehlt das Feld ganz.
  final bool hasPurchasePriceMicros;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'unitPriceCents': unitPriceCents,
        'vatRate': vatRate,
        'unit': unit,
        'number': number,
        'ean': ean,
        'internalCode': internalCode,
        'groupId': groupId,
        'revenueGroupId': revenueGroupId,
        'stockTracked': stockTracked,
        'stockKind': stockKind,
        'stockLocationIds': [...stockLocationIds],
        'minStock': minStock,
        'minStockByLocation': {...minStockByLocation},
        'active': active,
        if (externalIds != null) 'externalIds': {...externalIds!},
        if (metadata != null) 'metadata': {...metadata!},
        if (variantGroupId != null) 'variantGroupId': variantGroupId,
        if (variantAttributes != null) 'variantAttributes': {...variantAttributes!},
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (hasPurchasePriceMicros) 'purchasePriceMicros': purchasePriceMicros,
      };
}

/// Eine Seite von `listArticles`.
class ArticlePage {
  const ArticlePage({required this.articles, this.nextCursor});

  final List<Article> articles;

  /// `null` = letzte Seite.
  final String? nextCursor;
}

/// Anschrift eines Standorts; ein leerer Teil ist `null`.
class LocationAddress {
  const LocationAddress({this.street, this.zip, this.city, this.country});

  final String? street;
  final String? zip;
  final String? city;
  final String? country;

  Map<String, dynamic> toJson() => {'street': street, 'zip': zip, 'city': city, 'country': country};
}

/// Ein Standort des Kontos (Lager, Geschaeft, Fahrzeug).
class Location {
  const Location({
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

  /// Ein Wert aus `locationTypes`; `null`: ein Typ, den diese Paketversion nicht kennt.
  final String? type;

  /// `null`, wenn der Standort keinen einzigen Adressteil traegt.
  final LocationAddress? address;

  /// Kennzeichen, nur bei `vehicle`.
  final String? licensePlate;

  /// `false` = aufgeloest.
  final bool active;

  /// `true` = Hauptstandort, den der Server ohne eigenes Dokument ergaenzt.
  final bool virtual;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'address': address?.toJson(),
        'licensePlate': licensePlate,
        'active': active,
        'virtual': virtual,
      };
}

/// Bestand eines Artikels an einem Standort, Mengen in Tausendstel.
///
/// Gleichnamig mit dem `StockLevel` der Kasse (`package:kasseneck_api/pos.dart`,
/// dort mit `sellable`); wer beide Bibliotheken einbindet, nimmt ein Praefix.
class StockLevel {
  const StockLevel({
    required this.articleId,
    required this.locationId,
    required this.onHand,
    required this.reserved,
    required this.available,
    required this.defective,
    required this.sequence,
    this.updatedAt,
  });

  final String articleId;
  final String locationId;

  /// Verkaufbare Menge am Standort.
  final int onHand;

  /// Reserviert (Checkout im Shop).
  final int reserved;

  /// `onHand - reserved`, vom Server gerechnet; darf negativ sein (die Kasse
  /// verkauft trotzdem).
  final int available;
  final int defective;

  /// Steigt bei jedem Schreiben dieses Bestands um 1. Einen gespeicherten Stand
  /// nur ueberschreiben, wenn `sequence` groesser ist: so richten doppelte oder
  /// verspaetete Ereignisse nichts an.
  final int sequence;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'locationId': locationId,
        'onHand': onHand,
        'reserved': reserved,
        'available': available,
        'defective': defective,
        'sequence': sequence,
        'updatedAt': updatedAt,
      };
}

/// Antwort von `getStock`.
class StockResult {
  const StockResult({required this.stock, this.values});

  final List<StockLevel> stock;

  /// `null` ohne das Recht `costs` (der Server laesst das Feld weg), sonst die
  /// Werte. Eine Oberflaeche zeigt bei `null` keinen Wert, nie „0,00 €“.
  final List<StockValue>? values;
}

/// Eine Seite von `listStock`.
class StockPage extends StockResult {
  const StockPage({required super.stock, super.values, this.nextCursor});

  /// `null` = letzte Seite.
  final String? nextCursor;
}

/// Ein Los einer Bewegung.
class StockMovementLot {
  StockMovementLot({
    this.lotId,
    required this.quantity,
    this.expiresOn,
    this.batch,
    this.serialNumber,
    this.receivedAt,
    this.valueCents,
    bool? hasValueCents,
  }) : hasValueCents = hasValueCents ?? valueCents != null;

  final String? lotId;
  final int quantity;
  final String? expiresOn;
  final String? batch;
  final String? serialNumber;
  final String? receivedAt;

  /// Nur mit dem Recht `costs`, siehe [hasValueCents].
  final int? valueCents;
  final bool hasValueCents;

  Map<String, dynamic> toJson() => {
        'lotId': lotId,
        'quantity': quantity,
        'expiresOn': expiresOn,
        'batch': batch,
        'serialNumber': serialNumber,
        'receivedAt': receivedAt,
        if (hasValueCents) 'valueCents': valueCents,
      };
}

/// Bestand am Standort nach einer Bewegung, in Tausendstel.
class StockAfter {
  const StockAfter({required this.sellable, required this.defective, this.reserved});

  final int sellable;
  final int defective;

  /// Reserviert nach der Bewegung; steht nur an Reservierungsbewegungen,
  /// sonst `null` (nicht erfasst, nicht „0“). Seit 10.4.
  final int? reserved;

  Map<String, dynamic> toJson() => {'sellable': sellable, 'defective': defective, 'reserved': reserved};
}

/// Woher eine Bewegung kommt.
class StockMovementSourceRef {
  const StockMovementSourceRef({this.type, this.id, this.register, this.position});

  /// Meist ein Wert aus `stockMovementSources`; ein unbekannter bleibt erhalten.
  final String? type;

  /// Kennung des Belegs, der Rechnung o. Ae.
  final String? id;

  /// Kasse, an der verkauft wurde.
  final String? register;

  /// Position im Beleg bzw. in der Rechnung.
  final int? position;

  Map<String, dynamic> toJson() => {'type': type, 'id': id, 'register': register, 'position': position};
}

/// Eine Zeile des Lagerprotokolls; neueste zuerst.
class StockMovement {
  StockMovement({
    required this.id,
    this.type,
    this.articleId,
    this.locationId,
    this.condition,
    required this.quantityDelta,
    this.reservedDelta = 0,
    this.stockAfter,
    this.operationId,
    this.source,
    this.viennaDay,
    this.time,
    this.lots = const [],
    this.valueDeltaCents,
    bool? hasValueDeltaCents,
    this.consumedValueCents,
    bool? hasConsumedValueCents,
  })  : hasValueDeltaCents = hasValueDeltaCents ?? valueDeltaCents != null,
        hasConsumedValueCents = hasConsumedValueCents ?? consumedValueCents != null;

  final String id;

  /// Meist ein Wert aus `stockMovementTypes`; ein unbekannter bleibt erhalten.
  final String? type;
  final String? articleId;
  final String? locationId;

  /// Meist ein Wert aus `stockConditions`.
  final String? condition;

  /// Mengenaenderung in Tausendstel (Abgang negativ); bei `reservation` immer 0.
  final int quantityDelta;

  /// Aenderung von `reserved` in Tausendstel: positiv beim Reservieren, negativ
  /// bei Freigabe, Ablauf und Einloesen; 0 bei allen anderen Bewegungen (auch
  /// wenn ein Server vor Stufe 5b das Feld nicht sendet). Seit 10.4.
  final int reservedDelta;
  final StockAfter? stockAfter;
  final String? operationId;
  final StockMovementSourceRef? source;

  /// Wiener Tag `YYYY-MM-DD`.
  final String? viennaDay;
  final String? time;
  final List<StockMovementLot> lots;

  /// Nur mit dem Recht `costs`, siehe [hasValueDeltaCents].
  final int? valueDeltaCents;
  final bool hasValueDeltaCents;

  /// Nur mit dem Recht `costs`, siehe [hasConsumedValueCents].
  final int? consumedValueCents;
  final bool hasConsumedValueCents;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'articleId': articleId,
        'locationId': locationId,
        'condition': condition,
        'quantityDelta': quantityDelta,
        'reservedDelta': reservedDelta,
        'stockAfter': stockAfter?.toJson(),
        'operationId': operationId,
        'source': source?.toJson(),
        'viennaDay': viennaDay,
        'time': time,
        'lots': [for (final l in lots) l.toJson()],
        if (hasValueDeltaCents) 'valueDeltaCents': valueDeltaCents,
        if (hasConsumedValueCents) 'consumedValueCents': consumedValueCents,
      };
}

/// Eine Seite von `listStockMovements`.
class StockMovementPage {
  const StockMovementPage({required this.movements, this.nextCursor});

  final List<StockMovement> movements;

  /// `null` = letzte Seite.
  final String? nextCursor;
}

/// Die letzte Zustellung an einen Webhook.
class InventoryWebhookLastDelivery {
  const InventoryWebhookLastDelivery({this.at, this.status, this.statusCode});

  final String? at;

  /// Meist ein Wert aus `webhookDeliveryStatuses`.
  final String? status;
  final int? statusCode;

  Map<String, dynamic> toJson() => {'at': at, 'status': status, 'statusCode': statusCode};
}

/// Ein Konto-Webhook.
class InventoryWebhook {
  const InventoryWebhook({
    required this.id,
    required this.url,
    this.events = const [],
    this.active = true,
    this.description,
    this.createdAt,
    this.lastDelivery,
    this.consecutiveFailures = 0,
  });

  final String id;
  final String url;
  final List<String> events;
  final bool active;
  final String? description;
  final String? createdAt;

  /// `null`, solange keine Zustellung versucht wurde.
  final InventoryWebhookLastDelivery? lastDelivery;

  /// Fehlversuche in Folge (wie bei Partner-Webhooks); steigt der Wert, stimmt
  /// beim Empfaenger etwas nicht.
  final int consecutiveFailures;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'createdAt': createdAt,
        'events': [...events],
        'active': active,
        'description': description,
        'lastDelivery': lastDelivery?.toJson(),
        'consecutiveFailures': consecutiveFailures,
      };
}

/// Antwort von `createWebhook` und `rotateWebhookSecret`.
class InventoryWebhookWithSecret {
  const InventoryWebhookWithSecret({required this.webhook, required this.secret});

  final InventoryWebhook webhook;

  /// Das Secret fuer `verifyInventoryWebhookSignature`. **Es kommt genau
  /// einmal**, bei `createWebhook` bzw. `rotateWebhookSecret`; danach gibt der
  /// Server es nie wieder aus. Nach einem Wechsel gilt sofort nur das neue.
  /// Nicht in ein Protokoll schreiben.
  final String secret;
}

/// Antwort von `listWebhooks`.
class InventoryWebhookList {
  const InventoryWebhookList({required this.webhooks, required this.events});

  final List<InventoryWebhook> webhooks;

  /// Die Ereignisse, die dieses Konto abonnieren kann.
  final List<String> events;
}

/// Eine Probezustellung aus `sendWebhookTest`.
class InventoryWebhookTestDelivery {
  const InventoryWebhookTestDelivery({required this.deliveryId, required this.webhookId, this.status, this.statusCode});

  /// Kennung der Zustellung (Kopfzeile `X-Kasseneck-Delivery`).
  final String deliveryId;
  final String webhookId;
  final String? status;
  final int? statusCode;

  Map<String, dynamic> toJson() =>
      {'deliveryId': deliveryId, 'webhookId': webhookId, 'status': status, 'statusCode': statusCode};
}

/// Antwort von `sendWebhookTest`.
class InventoryWebhookTestResult {
  const InventoryWebhookTestResult({required this.eventId, required this.event, required this.deliveries});

  final String eventId;
  final String event;
  final List<InventoryWebhookTestDelivery> deliveries;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'event': event,
        'deliveries': [for (final d in deliveries) d.toJson()],
      };
}

/// Eine Zustellung aus `listWebhookDeliveries`.
class InventoryWebhookDelivery {
  const InventoryWebhookDelivery({
    required this.deliveryId,
    this.webhookId,
    this.event,
    this.eventId,
    this.status,
    this.attempts = 0,
    this.statusCode,
    this.response,
    this.error,
    this.createdAt,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.test = false,
  });

  /// Kennung der Zustellung (Kopfzeile `X-Kasseneck-Delivery`).
  final String deliveryId;
  final String? webhookId;
  final String? event;
  final String? eventId;

  /// Meist ein Wert aus `webhookDeliveryStatuses`; `dropped`: der Webhook wurde
  /// vor der Faelligkeit deaktiviert oder geloescht.
  final String? status;
  final int attempts;
  final int? statusCode;

  /// Auszug der Antwort des Empfaengers, hoechstens 500 Zeichen.
  final String? response;
  final String? error;
  final String? createdAt;
  final String? lastAttemptAt;
  final String? nextAttemptAt;
  final bool test;

  Map<String, dynamic> toJson() => {
        'deliveryId': deliveryId,
        'webhookId': webhookId,
        'eventId': eventId,
        'status': status,
        'statusCode': statusCode,
        'createdAt': createdAt,
        'test': test,
        'event': event,
        'attempts': attempts,
        'response': response,
        'error': error,
        'lastAttemptAt': lastAttemptAt,
        'nextAttemptAt': nextAttemptAt,
      };
}

/// Nutzlast von `stock.changed`: der aktuelle Stand, nicht die Aenderung.
class StockChangedEventData extends StockLevel {
  const StockChangedEventData({
    required super.articleId,
    required super.locationId,
    required super.onHand,
    required super.reserved,
    required super.available,
    required super.defective,
    required super.sequence,
    super.updatedAt,
    required this.cause,
    this.movementId,
  });

  /// Meist ein Wert aus `stockChangeCauses`; ein unbekannter bleibt erhalten.
  final String cause;

  /// Die Bewegung, aus der [cause] stammt; `null` bei `other` ohne Bewegung.
  final String? movementId;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'cause': cause, 'movementId': movementId};
}

/// Nutzlast von `stock.below_minimum`: nur beim Unterschreiten, nicht bei
/// jedem weiteren Sinken.
class StockBelowMinimumEventData {
  const StockBelowMinimumEventData({
    required this.articleId,
    required this.locationId,
    required this.available,
    required this.minStock,
  });

  final String articleId;
  final String locationId;

  /// Verfuegbarer Bestand (`onHand - reserved`); eine Reservierung allein kann
  /// ausloesen.
  final int available;

  /// Der Mindestbestand des Standorts in Tausendstel (`minStockByLocation`):
  /// die unterschrittene Schwelle, gemessen an [available]. Der `minStock` des
  /// Artikels allein loest nie aus.
  final int minStock;

  Map<String, dynamic> toJson() =>
      {'articleId': articleId, 'locationId': locationId, 'available': available, 'minStock': minStock};
}

// ---- Schreiben (Backend Stufe 5b, seit 10.4) ---------------------------------

/// Ein Hinweis einer Buchung: sie hat gewirkt, es gibt nur etwas zu wissen.
class InventoryWarning {
  const InventoryWarning({required this.code, this.articleId, this.locationId, this.message = ''});

  /// Meist ein Wert aus `inventoryWarningCodes`; ein unbekannter bleibt erhalten.
  final String code;
  final String? articleId;
  final String? locationId;

  /// Fuer Menschen, deutsch; nie darauf verzweigen.
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'articleId': articleId, 'locationId': locationId, 'message': message};
}

/// Antwort jeder Buchung (`receiveGoods`, `transferStock`, `recordStockLoss`,
/// `changeStockCondition`, `reverseStockMovement`). Werte traegt sie nie. Eine
/// Wiederholung mit demselben `idempotencyKey` liefert genau diese Antwort
/// noch einmal.
class StockOperation {
  const StockOperation({
    required this.operationId,
    this.movementIds = const [],
    this.lotIds = const [],
    this.warnings = const [],
  });

  /// Kennung des Vorgangs; `reverseStockMovement` nimmt ihn zurueck.
  final String operationId;
  final List<String> movementIds;
  final List<String> lotIds;
  final List<InventoryWarning> warnings;

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'movementIds': [...movementIds],
        'lotIds': [...lotIds],
        'warnings': [for (final w in warnings) w.toJson()],
      };
}

/// Eine Zeile der Wareneingangs-Vorschau (`previewGoodsReceipt`).
class GoodsReceiptPreviewLine {
  GoodsReceiptPreviewLine({
    required this.articleId,
    required this.quantity,
    this.expiresOn,
    this.batch,
    this.serialNumbers = const [],
    this.priceFromArticle = false,
    this.baseCents,
    this.landedCostCents,
    this.valueCents,
    this.unitCostMicros,
    bool? hasValues,
  }) : hasValues =
            hasValues ?? (baseCents != null || landedCostCents != null || valueCents != null || unitCostMicros != null);

  final String articleId;

  /// Tausendstel.
  final int quantity;
  final String? expiresOn;
  final String? batch;
  final List<String> serialNumbers;

  /// `true`: der Preis kam aus dem Artikel, nicht aus der Anfrage.
  final bool priceFromArticle;

  /// Warenwert ohne Nebenkosten in Cent; nur mit dem Recht `costs`, siehe [hasValues].
  final int? baseCents;

  /// Anteil der Nebenkosten in Cent.
  final int? landedCostCents;

  /// Wert der Zeile in Cent (`baseCents + landedCostCents`).
  final int? valueCents;

  /// Einstandspreis je Basiseinheit in Mikro-Euro.
  final int? unitCostMicros;

  /// Standen die vier Werte in der Antwort? Der Server sendet sie zusammen
  /// und nur mit dem Recht `costs`; ohne fehlen sie ganz („kein Recht“, nicht
  /// „0“).
  final bool hasValues;

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'quantity': quantity,
        'expiresOn': expiresOn,
        'batch': batch,
        'serialNumbers': [...serialNumbers],
        'priceFromArticle': priceFromArticle,
        if (hasValues) ...{
          'baseCents': baseCents,
          'landedCostCents': landedCostCents,
          'valueCents': valueCents,
          'unitCostMicros': unitCostMicros,
        },
      };
}

/// Antwort von `previewGoodsReceipt`: was der Wareneingang buchen wuerde.
class GoodsReceiptPreview {
  const GoodsReceiptPreview({required this.preview});

  final List<GoodsReceiptPreviewLine> preview;

  Map<String, dynamic> toJson() => {
        'preview': [for (final z in preview) z.toJson()],
      };
}

// ---- Reservierung ---------------------------------------------------------------

/// Eine Position einer Reservierung, Mengen in Tausendstel. Offen ist
/// `quantity - redeemed - released` ([open]).
class ReservationItem {
  const ReservationItem({
    required this.articleId,
    required this.locationId,
    required this.quantity,
    this.redeemed = 0,
    this.released = 0,
  });

  final String articleId;
  final String locationId;
  final int quantity;

  /// Ueber eine Rechnung eingeloest.
  final int redeemed;

  /// Freigegeben (von Hand oder durch Ablauf).
  final int released;

  /// Was diese Position noch zurueckhaelt.
  int get open => quantity - redeemed - released;

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'locationId': locationId,
        'quantity': quantity,
        'redeemed': redeemed,
        'released': released,
      };
}

/// Eine Reservierung, wie `getReservation`, jede schreibende
/// Reservierungs-Antwort und die Ereignisse `reservation.*` sie senden.
class Reservation {
  const Reservation({
    required this.id,
    this.status,
    this.reference,
    this.items = const [],
    this.expiresAt,
    this.createdAt,
  });

  final String id;

  /// Meist ein Wert aus `reservationStatuses`; `null`, wenn keiner gesendet
  /// wurde. Ein unbekannter bleibt erhalten.
  final String? status;

  /// Eigene Referenz (Bestellnummer); `null` = keine.
  final String? reference;
  final List<ReservationItem> items;

  /// Ablauf, ISO 8601 UTC.
  final String? expiresAt;
  final String? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'reference': reference,
        'items': [for (final p in items) p.toJson()],
        'expiresAt': expiresAt,
        'createdAt': createdAt,
      };
}

/// Eine Seite von `listReservations`, neueste zuerst.
class ReservationPage {
  const ReservationPage({required this.reservations, this.nextCursor});

  final List<Reservation> reservations;

  /// `null` = letzte Seite.
  final String? nextCursor;

  Map<String, dynamic> toJson() => {
        'reservations': [for (final r in reservations) r.toJson()],
        'nextCursor': nextCursor,
      };
}

/// Eine Position, fuer die beim Reservieren der verfuegbare Bestand nicht
/// reicht (`insufficient_available`, siehe `inventoryShortfalls`).
class InventoryShortfall {
  const InventoryShortfall({
    required this.articleId,
    required this.locationId,
    required this.requested,
    required this.available,
  });

  final String articleId;
  final String locationId;

  /// Angefragt, Tausendstel.
  final int requested;

  /// Verfuegbar (`onHand - reserved`), Tausendstel; darf negativ sein.
  final int available;

  Map<String, dynamic> toJson() =>
      {'articleId': articleId, 'locationId': locationId, 'requested': requested, 'available': available};
}
