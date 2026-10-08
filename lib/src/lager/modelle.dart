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

import 'dart:typed_data';

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

  /// Nur an einer Variante: die Variantengruppe. Gesetzt nur ueber
  /// `createVariantGroup`/`addVariant`, nie umgehaengt.
  final String? variantGroupId;

  /// Nur an einer Variante: je Merkmal der Gruppe genau ein Wert
  /// (`{'farbe': 'rot', 'groesse': 'S'}`). Die Schluessel kommen nach Codepunkt
  /// sortiert, nicht in der Merkmalsreihenfolge der Gruppe; die steht in
  /// [VariantGroup.attributes].
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

// ---- Varianten (Backend Stufe 5c, seit 10.5) ---------------------------------
//
// Eine Variante ist ein gewoehnlicher Artikel mit `variantGroupId` und
// `variantAttributes`: eigene Kennung, eigener Code, eigener Bestand, eigene
// Kachel an der Kasse. Die Gruppe haelt nur, was alle teilen (Name, Merkmale
// mit ihren Werten, Vorgaben fuer neue Varianten) und die Liste ihrer aktiven
// Varianten. Jede Kombination gibt es je Gruppe hoechstens einmal.

/// Ein Merkmal einer Variantengruppe mit seinen Werten, in der Reihenfolge der
/// Gruppe. Dieselbe Form in der Anfrage (`CreateVariantGroupRequest.attributes`)
/// und in der Antwort.
class VariantAttribute {
  const VariantAttribute({required this.key, required this.label, required this.values});

  /// `^[a-z0-9_]{1,32}$`, eindeutig in der Gruppe; Schluessel in `variantAttributes`.
  final String key;

  /// Beschriftung, 1–40 Zeichen, z. B. „Größe“.
  final String label;

  /// 1–30 Werte zu je 1–30 Zeichen, eindeutig ohne Gross/Klein, getrimmt und in
  /// Unicode-NFC gespeichert. Werte kommen nur dazu (`addAttributeValues`), nie weg.
  final List<String> values;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'values': [...values]};
}

/// Vorgaben einer Gruppe: sie fuellen bei der **Anlage** einer Variante die
/// Felder, die die Variante nicht selbst nennt. Ein spaeteres Aendern der
/// Vorgaben aendert keine bestehende Variante (dafuer `updateArticle`). Ein
/// Feld ohne Vorgabe ist `null` und fehlt in [toJson].
class VariantGroupDefaults {
  const VariantGroupDefaults({this.unitPriceCents, this.vatRate, this.unit, this.groupId, this.stockTracked});

  final int? unitPriceCents;

  /// USt-Satz in Prozent.
  final num? vatRate;
  final String? unit;
  final String? groupId;

  /// Ohne Vorgabe gilt wie bei `createArticle` `false` (dann nicht reservierbar).
  final bool? stockTracked;

  Map<String, dynamic> toJson() => {
        'unitPriceCents': ?unitPriceCents,
        'vatRate': ?vatRate,
        'unit': ?unit,
        'groupId': ?groupId,
        'stockTracked': ?stockTracked,
      };
}

/// Eine Variante in der Liste ihrer Gruppe.
class VariantGroupMember {
  const VariantGroupMember({required this.articleId, this.variantAttributes = const {}});

  final String articleId;

  /// Je Merkmal ein Wert, Schluessel nach Codepunkt sortiert.
  final Map<String, String> variantAttributes;

  Map<String, dynamic> toJson() => {'articleId': articleId, 'variantAttributes': {...variantAttributes}};
}

/// Eine Variantengruppe, wie `getVariantGroup`, `listVariantGroups`, die
/// schreibenden Gruppenaufrufe und die Ereignisse `variant_group.*` sie
/// senden. Die Artikel selbst traegt sie nicht: die liest
/// `listArticles(variantGroupId: …)`.
class VariantGroup {
  const VariantGroup({
    required this.id,
    this.name,
    this.attributes = const [],
    this.defaults = const VariantGroupDefaults(),
    this.active = true,
    this.variants = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// 1–100 Zeichen; Standardname einer Variante: „`<Gruppe> <Wert1> <Wert2>`“.
  final String? name;

  /// 1–3 Merkmale in der Reihenfolge der Gruppe (sie bestimmt den Standardnamen).
  final List<VariantAttribute> attributes;
  final VariantGroupDefaults defaults;

  /// `false` = stillgelegt: alle Varianten stillgelegt, kein `addVariant`, endgueltig.
  final bool active;

  /// Die aktiven Varianten einer aktiven Gruppe; eine einzeln stillgelegte
  /// Variante faellt heraus (ihre Kombination ist dann wieder frei). Beim
  /// Stilllegen der Gruppe wird die Liste eingefroren.
  final List<VariantGroupMember> variants;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'attributes': [for (final m in attributes) m.toJson()],
        'defaults': defaults.toJson(),
        'active': active,
        'variants': [for (final v in variants) v.toJson()],
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

/// Eine Seite von `listVariantGroups`, nach `updatedAt` aufsteigend.
class VariantGroupPage {
  const VariantGroupPage({required this.variantGroups, this.nextCursor});

  final List<VariantGroup> variantGroups;

  /// `null` = letzte Seite.
  final String? nextCursor;

  Map<String, dynamic> toJson() => {
        'variantGroups': [for (final g in variantGroups) g.toJson()],
        'nextCursor': nextCursor,
      };
}

// ---- Inventur (Lager-Kern Stufe 3, seit 10.7) --------------------------------
//
// Eine Inventur zaehlt den Bestand eines Standorts: anlegen (Umfang, Stichtag
// oder permanent, blind als Standard), zaehlen (mehrere Zaehlungen je Artikel
// werden addiert, eine falsche wird mit Grund storniert), pruefen (erst jetzt
// Soll und Differenz), einzelne Positionen nachzaehlen, abschliessen (bucht je
// Position eine Bewegung `stocktake`, legt das Inventurprotokoll ab) oder
// abbrechen. Dieselben Modelle liest der Kassenweg (`pos.dart`).
//
// **Blind:** vor `review` traegt keine Antwort ein Soll, eine Differenz oder
// „pruefen“; die Felder fehlen dann ganz und sind hier `null`. Werte
// (`…Cents`, `…Micros`) kommen nur mit dem Recht `costs` und fehlen sonst
// ebenso. Katalogwerte (Stand, Art, Quelle, Akteur, Gruende) bleiben Text.
//
// `toJson()` ist die Drahtform; ein Feld, das der Server nur in einem Stand
// oder nur mit einem Recht sendet, fehlt dort, wenn es `null` ist.

/// Wer etwas tat: Inhaber, Kasseneck-Admin, Kassen-Benutzer oder ein
/// API-Schluessel.
class StocktakeActor {
  const StocktakeActor({this.type, this.id, this.name});

  /// Meist ein Wert aus `stocktakeActorTypes`; ein unbekannter bleibt erhalten.
  final String? type;
  final String? id;

  /// Anzeigename (Kassen-Benutzer); `null` beim Inhaber und bei der API.
  final String? name;

  Map<String, dynamic> toJson() => {'type': type, 'id': id, 'name': name};
}

/// Umfang einer Inventur, bei der Anlage eingefroren.
class StocktakeScope {
  const StocktakeScope({this.type, this.groupIds = const [], this.articleIds = const []});

  /// Meist ein Wert aus `stocktakeScopeTypes`.
  final String? type;

  /// Nur bei `groups`, sonst leer.
  final List<String> groupIds;

  /// Nur bei `articles`, sonst leer.
  final List<String> articleIds;

  Map<String, dynamic> toJson() => {'type': type, 'groupIds': [...groupIds], 'articleIds': [...articleIds]};
}

/// Fortschritt: Zahl der Positionen und ob Positionen zum Nachzaehlen offen sind.
class StocktakeProgress {
  const StocktakeProgress({required this.items, this.counted, this.recountOpen = false});

  final int items;

  /// Gezaehlte Positionen; nur `getStocktake` zaehlt sie (sonst `null`, nie 0:
  /// „unbekannt“ ist nicht „keine“).
  final int? counted;
  final bool recountOpen;

  Map<String, dynamic> toJson() => {'items': items, 'counted': ?counted, 'recountOpen': recountOpen};
}

/// Die Pruefung: wann und von wem angestossen, ob Soll und Differenz schon
/// gerechnet sind.
class StocktakeReview {
  const StocktakeReview({this.startedAt, this.startedBy, this.complete = false, this.expectedAsOf, this.recountUncounted});

  final String? startedAt;
  final StocktakeActor? startedBy;

  /// `false`: der Server rechnet noch; danach erneut `getStocktake`.
  final bool complete;

  /// Stand der Soll-Rechnung; `null`, solange sie nicht fertig ist.
  final String? expectedAsOf;

  /// Positionen, die zum Nachzaehlen offen und noch ungezaehlt sind; `null`,
  /// wenn der Server es nicht nennt.
  final int? recountUncounted;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt,
        'startedBy': startedBy?.toJson(),
        'complete': complete,
        'expectedAsOf': expectedAsOf,
        'recountUncounted': recountUncounted,
      };
}

/// Der Abschluss: er bucht in Teilen und laesst sich wieder aufnehmen.
class StocktakeClosing {
  const StocktakeClosing({
    this.startedAt,
    this.startedBy,
    this.uncountedAsZero = false,
    this.parts,
    this.bookedParts,
    this.completedAt,
  });

  final String? startedAt;
  final StocktakeActor? startedBy;

  /// Ungezaehlte Positionen als 0 gebucht (sonst nicht gebucht, im Protokoll
  /// „nicht gezaehlt“).
  final bool uncountedAsZero;

  /// Zahl der Teile; `null`, solange der Plan noch nicht steht.
  final int? parts;

  /// Gebuchte Teile; `null`, wenn der Server es nicht nennt.
  final int? bookedParts;

  /// `null`, solange der Abschluss noch bucht.
  final String? completedAt;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt,
        'startedBy': startedBy?.toJson(),
        'uncountedAsZero': uncountedAsZero,
        'parts': parts,
        'bookedParts': bookedParts,
        'completedAt': ?completedAt,
      };
}

/// Der Abbruch einer Inventur.
class StocktakeCancellation {
  const StocktakeCancellation({this.reason, this.cancelledAt, this.cancelledBy});

  final String? reason;
  final String? cancelledAt;
  final StocktakeActor? cancelledBy;

  Map<String, dynamic> toJson() => {'reason': reason, 'cancelledAt': cancelledAt, 'cancelledBy': cancelledBy?.toJson()};
}

/// Summen des Abschlusses (Anzahlen von Positionen; Werte nur mit dem Recht
/// `costs`).
class StocktakeTotals {
  const StocktakeTotals({
    required this.items,
    required this.counted,
    required this.uncounted,
    required this.recounted,
    required this.withDifference,
    required this.needsCheck,
    required this.notBooked,
    this.differenceValueCents,
    this.inventoryValueCents,
  });

  final int items;
  final int counted;
  final int uncounted;
  final int recounted;
  final int withDifference;
  final int needsCheck;
  final int notBooked;

  /// Summe der gebuchten Differenzwerte in Cent; nur mit dem Recht `costs`.
  final int? differenceValueCents;

  /// Inventarwert in Cent; nur mit dem Recht `costs`.
  final int? inventoryValueCents;

  Map<String, dynamic> toJson() => {
        'items': items,
        'counted': counted,
        'uncounted': uncounted,
        'recounted': recounted,
        'withDifference': withDifference,
        'needsCheck': needsCheck,
        'notBooked': notBooked,
        'differenceValueCents': ?differenceValueCents,
        'inventoryValueCents': ?inventoryValueCents,
      };
}

/// Ein Hinweis zur Inventur, mit der Zahl der betroffenen Positionen. Er ist
/// kein Fehler: der Vorgang hat gewirkt.
class StocktakeWarning {
  const StocktakeWarning({required this.code, required this.items, this.message});

  /// Meist ein Wert aus `inventoryWarningCodes` (`uncounted_items`,
  /// `not_booked`, `defect_capped`, `recount_uncounted`); ein unbekannter
  /// bleibt erhalten.
  final String code;
  final int items;

  /// Menschentext (deutsch); `null` am Kopf, der nur Codes fuehrt. Nie darauf
  /// verzweigen.
  final String? message;

  Map<String, dynamic> toJson() => {'code': code, 'items': items, 'message': ?message};
}

/// Siegelstand des Lagerprotokolls beim Abschluss: Wiener Tage `YYYY-MM-DD`.
/// `verified: null` heisst „nicht fertig geprueft“, nie Bruch.
class StocktakeSeal {
  const StocktakeSeal({
    this.fromDay,
    this.toDay,
    this.daysChecked,
    this.verified,
    this.firstBreak,
    this.gaps = const [],
    this.gapCount,
    this.notChecked,
    this.checkedUntil,
  });

  final String? fromDay;
  final String? toDay;
  final int? daysChecked;
  final bool? verified;

  /// Erster Tag mit gebrochenem Siegel; `null` = keiner.
  final String? firstBreak;

  /// Tage ohne Siegel.
  final List<String> gaps;
  final int? gapCount;

  /// `time_limit` (Frist des Laufs) oder `unavailable`; `null`, wenn ganz
  /// geprueft.
  final String? notChecked;

  /// Bis wohin geprueft wurde, wenn die Pruefung nicht fertig wurde.
  final String? checkedUntil;

  Map<String, dynamic> toJson() => {
        'fromDay': fromDay,
        'toDay': toDay,
        'daysChecked': daysChecked,
        'verified': verified,
        'firstBreak': firstBreak,
        'gaps': [...gaps],
        'gapCount': gapCount,
        'notChecked': ?notChecked,
        'checkedUntil': ?checkedUntil,
      };
}

/// Das Inventurprotokoll: ob es da ist, und die Pruefsummen der Fassungen, die
/// der Aufrufer sehen darf.
class StocktakePdfInfo {
  const StocktakePdfInfo({this.available = false, this.valuesSha256, this.quantitiesSha256});

  final bool available;

  /// SHA-256 der Fassung mit Werten; nur mit dem Recht `costs`.
  final String? valuesSha256;

  /// SHA-256 der Fassung nur mit Mengen.
  final String? quantitiesSha256;

  Map<String, dynamic> toJson() =>
      {'available': available, 'valuesSha256': ?valuesSha256, 'quantitiesSha256': ?quantitiesSha256};
}

/// Eine Inventur (Kopf), wie jeder Inventur-Aufruf ausser den Listen der
/// Positionen und Zaehlungen sie sendet.
///
/// Die Felder des Ergebnisses ([totals], [warnings], [seal], [checksum],
/// [inventoryAsOf], [pdf]) gibt es erst nach dem Abschluss und nur fuer den,
/// der das Soll sehen darf; vorher sind sie `null`.
class Stocktake {
  const Stocktake({
    required this.id,
    this.name,
    this.locationId,
    this.scope,
    this.type,
    this.keyDate,
    this.blind = true,
    this.status,
    this.progress,
    this.createdAt,
    this.createdBy,
    this.source,
    this.updatedAt,
    this.review,
    this.closing,
    this.cancellation,
    this.totals,
    this.warnings,
    this.seal,
    this.checksum,
    this.inventoryAsOf,
    this.pdf,
  });

  final String id;

  /// 1–100 Zeichen, Vorgabe „`Inventur <Standort> <Tag>`“.
  final String? name;
  final String? locationId;
  final StocktakeScope? scope;

  /// Meist ein Wert aus `stocktakeTypes`.
  final String? type;

  /// `YYYY-MM-DD` bei `key_date`, sonst `null`.
  final String? keyDate;

  /// Blind zaehlen (Vorgabe): niemand sieht vor der Pruefung ein Soll. Nur ein
  /// ausdrueckliches `false` am Draht zeigt Bestand.
  final bool blind;

  /// Meist ein Wert aus `stocktakeStatuses`.
  final String? status;
  final StocktakeProgress? progress;
  final String? createdAt;
  final StocktakeActor? createdBy;

  /// Meist ein Wert aus `stocktakeSources`.
  final String? source;

  /// Letzte Aenderung des Kopfs; Grundlage von `listStocktakes(updatedSince: …)`.
  final String? updatedAt;
  final StocktakeReview? review;
  final StocktakeClosing? closing;
  final StocktakeCancellation? cancellation;
  final StocktakeTotals? totals;

  /// Hinweise des Abschlusses (`uncounted_items`, `not_booked`,
  /// `defect_capped`); `null`, wenn der Kopf keine Liste traegt (vor dem
  /// Abschluss), leer, wenn es keinen Hinweis gibt.
  final List<StocktakeWarning>? warnings;
  final StocktakeSeal? seal;

  /// SHA-256 ueber Kopf, Positionen und Zaehlungen (kanonisches JSON), steht
  /// auch im Protokoll.
  final String? checksum;

  /// Meist ein Wert aus `stocktakeInventoryAsOf`.
  final String? inventoryAsOf;
  final StocktakePdfInfo? pdf;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'locationId': locationId,
        'scope': scope?.toJson(),
        'type': type,
        'keyDate': keyDate,
        'blind': blind,
        'status': status,
        'progress': progress?.toJson(),
        'createdAt': createdAt,
        'createdBy': createdBy?.toJson(),
        'source': source,
        'updatedAt': updatedAt,
        'review': review?.toJson(),
        'closing': closing?.toJson(),
        'cancellation': cancellation?.toJson(),
        'totals': ?totals?.toJson(),
        if (warnings != null) 'warnings': [for (final w in warnings!) w.toJson()],
        'seal': ?seal?.toJson(),
        'checksum': ?checksum,
        'inventoryAsOf': ?inventoryAsOf,
        'pdf': ?pdf?.toJson(),
      };
}

/// Ein Nachzaehlen-Auftrag an einer Position.
class StocktakeRecount {
  const StocktakeRecount({this.reason, this.requestedAt, this.requestedBy, this.round});

  final String? reason;
  final String? requestedAt;
  final StocktakeActor? requestedBy;

  /// Die Runde, die das Nachzaehlen begann.
  final int? round;

  Map<String, dynamic> toJson() =>
      {'reason': reason, 'requestedAt': requestedAt, 'requestedBy': requestedBy?.toJson(), 'round': round};
}

/// Was von einer Position nicht gebucht wurde, und warum.
class StocktakeNotBooked {
  const StocktakeNotBooked({required this.code, this.quantity, this.reasons});

  /// Meist ein Wert aus `stocktakeNotBookedReasons`; dazu kommen Codes wie
  /// `serial_not_in_stock`. Jeder Text bleibt stehen.
  final String code;

  /// Nicht gebuchte Menge in Tausendstel; `null`, wenn der Server keine nennt.
  final int? quantity;

  /// Bei mehreren Gruenden je Grund ein Eintrag; sonst `null`.
  final List<({String code, int? quantity})>? reasons;

  Map<String, dynamic> toJson() => {
        'code': code,
        'quantity': quantity,
        if (reasons != null) 'reasons': [for (final g in reasons!) {'code': g.code, 'quantity': g.quantity}],
      };
}

/// Eine Zeile des Inventars (nach dem Abschluss).
class StocktakeInventoryLine {
  const StocktakeInventoryLine({required this.quantity, this.countedOn, this.unitValueMicros, this.valueCents});

  /// Tausendstel.
  final int quantity;

  /// Aufnahmetag (Wiener Tag der Referenzzeit), `YYYY-MM-DD`.
  final String? countedOn;

  /// Einzelwert je Basiseinheit in Mikro-Euro; nur mit dem Recht `costs`.
  final int? unitValueMicros;

  /// Gesamtwert in Cent; nur mit dem Recht `costs`.
  final int? valueCents;

  Map<String, dynamic> toJson() => {
        'quantity': quantity,
        'unitValueMicros': ?unitValueMicros,
        'valueCents': ?valueCents,
        'countedOn': countedOn,
      };
}

/// Eine Position: ein Artikel in einem Zustand (`sellable` bzw. `defective`).
///
/// Ab `review` (und nur fuer den, der das Soll sehen darf) kommen Soll,
/// Differenz und „pruefen“ dazu ([expectedQuantity] …), nach dem Abschluss die
/// Buchung und das Inventar. Vorher sind diese Felder `null`.
class StocktakeItem {
  const StocktakeItem({
    required this.articleId,
    required this.condition,
    this.name,
    this.number,
    this.unit,
    required this.round,
    required this.counted,
    this.quantity,
    required this.counts,
    this.firstCountedAt,
    this.referenceTime,
    this.countedBy = const [],
    this.serialNumbers,
    this.recountRequested = false,
    this.recount,
    this.addedLater = false,
    this.bookStockNow,
    this.expectedQuantity,
    this.differenceQuantity,
    this.needsCheck,
    this.checkReasons,
    this.expectedAsOf,
    this.differenceValueCents,
    this.missingSerialNumbers,
    this.extraSerialNumbers,
    this.bookedQuantity,
    this.notBooked,
    this.inventory,
  });

  final String articleId;

  /// Meist ein Wert aus `stockConditions`.
  final String condition;

  /// Name, Nummer und Einheit, wie sie bei der Anlage galten.
  final String? name;
  final String? number;
  final String? unit;

  /// Zaehlrunde ab 1; jedes Nachzaehlen beginnt eine neue.
  final int round;

  /// Gezaehlt (auch „0 gezaehlt“); `false` heisst ungezaehlt, nicht leer.
  final bool counted;

  /// Summe der aktiven Zaehlungen der Runde in Tausendstel; `null` = nicht
  /// gezaehlt. Bei [counted] `true` ist sie immer gesetzt.
  final int? quantity;

  /// Zahl der aktiven Zaehlungen der Runde.
  final int counts;
  final String? firstCountedAt;

  /// Referenzzeit: Serverzeit der letzten aktiven Zaehlung der Runde.
  final String? referenceTime;
  final List<StocktakeActor> countedBy;

  /// Gezaehlte Seriennummern der Runde (Einzelstuecke). Nur in den Listen;
  /// die Antwort von Zaehlen und Stornieren sendet die Position ohne sie, dann
  /// ist das Feld `null` (nicht „keine Seriennummern“).
  final List<String>? serialNumbers;
  final bool recountRequested;
  final StocktakeRecount? recount;

  /// Erst beim Zaehlen aufgenommen (Umfang `all`).
  final bool addedLater;

  /// Heutiger Buchbestand in Tausendstel, nur bei `blind: false` waehrend der
  /// Zaehlung. Nie das Soll zur Referenzzeit.
  final int? bookStockNow;
  final int? expectedQuantity;

  /// `quantity - expectedQuantity`; `null`, wenn ungezaehlt oder vor der Pruefung.
  final int? differenceQuantity;

  /// `null` vor der Pruefung.
  final bool? needsCheck;

  /// Meist Werte aus `stocktakeCheckReasons`; `null` vor der Pruefung.
  final List<String>? checkReasons;
  final String? expectedAsOf;

  /// Voraussichtlicher (in `review`) bzw. gebuchter Differenzwert in Cent; nur
  /// mit dem Recht `costs`.
  final int? differenceValueCents;

  /// Einzelstueck: Soll-Nummern ohne Zaehlung.
  final List<String>? missingSerialNumbers;

  /// Einzelstueck: gezaehlte Nummern, die nicht im Soll stehen.
  final List<String>? extraSerialNumbers;

  /// Gebuchte Menge in Tausendstel (nach dem Abschluss).
  final int? bookedQuantity;
  final StocktakeNotBooked? notBooked;
  final StocktakeInventoryLine? inventory;

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'condition': condition,
        'name': name,
        'number': number,
        'unit': unit,
        'round': round,
        'counted': counted,
        'quantity': quantity,
        'counts': counts,
        'firstCountedAt': firstCountedAt,
        'referenceTime': referenceTime,
        'countedBy': [for (final a in countedBy) a.toJson()],
        if (serialNumbers != null) 'serialNumbers': [...serialNumbers!],
        'recountRequested': recountRequested,
        'recount': ?recount?.toJson(),
        'addedLater': addedLater,
        'bookStockNow': ?bookStockNow,
        'expectedQuantity': ?expectedQuantity,
        'differenceQuantity': ?differenceQuantity,
        'needsCheck': ?needsCheck,
        if (checkReasons != null) 'checkReasons': [...checkReasons!],
        'expectedAsOf': ?expectedAsOf,
        'differenceValueCents': ?differenceValueCents,
        if (missingSerialNumbers != null) 'missingSerialNumbers': [...missingSerialNumbers!],
        if (extraSerialNumbers != null) 'extraSerialNumbers': [...extraSerialNumbers!],
        'bookedQuantity': ?bookedQuantity,
        'notBooked': ?notBooked?.toJson(),
        'inventory': ?inventory?.toJson(),
      };
}

/// Das Storno einer Zaehlung.
class StocktakeCountVoided {
  const StocktakeCountVoided({this.reason, this.voidedAt, this.voidedBy});

  final String? reason;
  final String? voidedAt;
  final StocktakeActor? voidedBy;

  Map<String, dynamic> toJson() => {'reason': reason, 'voidedAt': voidedAt, 'voidedBy': voidedBy?.toJson()};
}

/// Eine Zaehlung.
class StocktakeCount {
  const StocktakeCount({
    required this.id,
    required this.articleId,
    required this.condition,
    required this.quantity,
    this.serialNumbers = const [],
    required this.round,
    this.countedBy,
    this.source,
    this.cashregisterId,
    this.countedAt,
    this.note,
    this.voided,
  });

  final String id;
  final String articleId;
  final String condition;

  /// Tausendstel; `0` heisst „leer gezaehlt“.
  final int quantity;

  /// Leer bei Mengenartikeln; die Antwort traegt die Liste immer.
  final List<String> serialNumbers;
  final int round;
  final StocktakeActor? countedBy;

  /// Meist ein Wert aus `stocktakeSources`.
  final String? source;

  /// Kasse, an der gezaehlt wurde; `null` im Panel und ueber die API.
  final String? cashregisterId;

  /// Serverzeit der Zaehlung (die Geraetezeit zaehlt nie).
  final String? countedAt;
  final String? note;

  /// `null` = aktiv.
  final StocktakeCountVoided? voided;

  Map<String, dynamic> toJson() => {
        'id': id,
        'articleId': articleId,
        'condition': condition,
        'quantity': quantity,
        'serialNumbers': [...serialNumbers],
        'round': round,
        'countedBy': countedBy?.toJson(),
        'source': source,
        'cashregisterId': cashregisterId,
        'countedAt': countedAt,
        'note': note,
        'voided': voided?.toJson(),
      };
}

/// Antwort von Zaehlen und Stornieren: die Zaehlung und ihre Position danach
/// (Summe der Runde in [StocktakeItem.quantity], kein Soll).
class StocktakeCountResult {
  const StocktakeCountResult({required this.count, required this.item});

  final StocktakeCount count;
  final StocktakeItem item;

  Map<String, dynamic> toJson() => {'count': count.toJson(), 'item': item.toJson()};
}

/// Eine Seite von `listStocktakes`.
class StocktakePage {
  const StocktakePage({required this.stocktakes, this.nextCursor});

  final List<Stocktake> stocktakes;

  /// `null` = letzte Seite.
  final String? nextCursor;

  Map<String, dynamic> toJson() => {'stocktakes': [for (final s in stocktakes) s.toJson()], 'nextCursor': nextCursor};
}

/// Eine Seite von `listStocktakeItems` bzw. `listMyStocktakeItems`, nach Kennung.
class StocktakeItemPage {
  const StocktakeItemPage({required this.items, this.nextCursor});

  final List<StocktakeItem> items;

  /// `null` = letzte Seite.
  final String? nextCursor;

  Map<String, dynamic> toJson() => {'items': [for (final p in items) p.toJson()], 'nextCursor': nextCursor};
}

/// Eine Seite von `listStocktakeCounts` bzw. `listMyStocktakeCounts`, neueste zuerst.
class StocktakeCountPage {
  const StocktakeCountPage({required this.counts, this.nextCursor});

  final List<StocktakeCount> counts;

  /// `null` = letzte Seite.
  final String? nextCursor;

  Map<String, dynamic> toJson() => {'counts': [for (final z in counts) z.toJson()], 'nextCursor': nextCursor};
}

/// Antwort von `closeStocktake`: der Kopf (meist `closing`, der Server bucht
/// im Hintergrund weiter) und Hinweise wie `recount_uncounted`.
class CloseStocktakeResult {
  const CloseStocktakeResult({required this.stocktake, this.warnings = const []});

  final Stocktake stocktake;

  /// Leer, wenn es keinen Hinweis gibt.
  final List<StocktakeWarning> warnings;

  Map<String, dynamic> toJson() =>
      {'stocktake': stocktake.toJson(), 'warnings': [for (final w in warnings) w.toJson()]};
}

/// Lese-Link auf das Inventurprotokoll, wenn es zu gross fuer die Antwort ist
/// (ueber 9 MiB). Signiert und 15 Minuten gueltig; die geladene Datei an
/// [sha256] pruefen.
class StocktakePdfDownload {
  const StocktakePdfDownload({
    required this.url,
    required this.expiresAt,
    required this.sizeBytes,
    required this.sha256,
    this.fileName,
    this.contentType,
  });

  final String url;
  final String expiresAt;
  final int sizeBytes;

  /// SHA-256 der Datei, hexadezimal (dieselbe wie `pdf.valuesSha256` bzw.
  /// `pdf.quantitiesSha256` am Kopf).
  final String sha256;
  final String? fileName;
  final String? contentType;

  Map<String, dynamic> toJson() => {
        'url': url,
        'expiresAt': expiresAt,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'fileName': fileName,
        'contentType': contentType,
      };
}

/// Das Inventurprotokoll: als Datei ([StocktakePdfFile]) oder, ueber 9 MiB,
/// als Lese-Link ([StocktakePdfLink]). Mit dem Recht `costs` die Fassung mit
/// Werten, sonst die nur mit Mengen.
///
/// Ein `switch` ohne `default` deckt beide Faelle; [kind] ist der Name des
/// Falls wie im JS-Zwilling (`pdf` bzw. `download`).
sealed class StocktakePdf {
  const StocktakePdf();

  String get kind;
}

/// Das Inventurprotokoll als Datei (beginnt mit `%PDF`).
final class StocktakePdfFile extends StocktakePdf {
  const StocktakePdfFile(this.pdf);

  final Uint8List pdf;

  @override
  String get kind => 'pdf';
}

/// Das Inventurprotokoll als Lese-Link: die Datei war zu gross fuer die Antwort.
final class StocktakePdfLink extends StocktakePdf {
  const StocktakePdfLink(this.download);

  final StocktakePdfDownload download;

  @override
  String get kind => 'download';
}
