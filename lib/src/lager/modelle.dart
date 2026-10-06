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
    this.unitPriceCents,
    this.vatRate,
    this.unit,
    this.number,
    this.ean,
    this.internalCode,
    this.groupId,
    this.revenueGroupId,
    this.stockTracked = false,
    this.stockLocationIds = const [],
    this.minStock,
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

  /// Standorte, an denen der Artikel gefuehrt wird; leer = nur der Standard-Standort.
  final List<String> stockLocationIds;

  /// Mindestbestand des Artikels in Tausendstel; `null` = keiner. Warnungen,
  /// `belowMinimum` und `stock.below_minimum` richten sich nach dem
  /// Mindestbestand je Standort, nicht nach diesem Wert.
  final int? minStock;
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
        'unitPriceCents': unitPriceCents,
        'vatRate': vatRate,
        'unit': unit,
        'number': number,
        'ean': ean,
        'internalCode': internalCode,
        'groupId': groupId,
        'revenueGroupId': revenueGroupId,
        'stockTracked': stockTracked,
        'stockLocationIds': [...stockLocationIds],
        'minStock': minStock,
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
  const StockAfter({required this.sellable, required this.defective});

  final int sellable;
  final int defective;

  Map<String, dynamic> toJson() => {'sellable': sellable, 'defective': defective};
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

  /// Mengenaenderung in Tausendstel (Abgang negativ).
  final int quantityDelta;
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
  final int available;

  /// Der Mindestbestand des Standorts in Tausendstel: die unterschrittene
  /// Schwelle, gemessen am Bestand `onHand`. Der `minStock` des Artikels allein
  /// loest nie aus.
  final int minStock;

  Map<String, dynamic> toJson() =>
      {'articleId': articleId, 'locationId': locationId, 'available': available, 'minStock': minStock};
}
