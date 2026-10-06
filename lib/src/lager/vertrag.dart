/// Der Vertrag der Lager-API (Backend Stufe 5a) als Listen – Zwilling von
/// `src/inventory/vertrag.ts` im JS-Paket `@kreiseck/kasseneck-api`.
///
/// `test/lager_api_test.dart` vergleicht jede Liste in beide Richtungen mit
/// dem Abschnitt `inventory` in `test/fixtures/vertrag/surface.json` und mit
/// den Katalogen von `v3/v3-vokabular.json` (gezogen von
/// `tool/zwillinge.sh`). Wer hier etwas aendert, aendert zuerst das JS-Paket.
library;

/// Die 14 Endpunkte, in der Reihenfolge von `endpoints.public`.
const List<String> inventoryEndpoints = [
  'getArticle',
  'listArticles',
  'lookupArticleByCode',
  'listLocations',
  'getStock',
  'listStock',
  'listStockMovements',
  'createWebhook',
  'updateWebhook',
  'deleteWebhook',
  'listWebhooks',
  'sendWebhookTest',
  'rotateWebhookSecret',
  'listWebhookDeliveries',
];

/// Art eines Standorts (Katalog `STANDORT_TYP`).
const List<String> locationTypes = ['warehouse', 'store', 'vehicle', 'other'];

/// Art einer Lagerbewegung (Katalog `BEWEGUNG_ART`), zugleich der Filter
/// `type`. `goods_receipt` ist der Wareneingang, `takeover` der uebernommene
/// Anfangsbestand (auch per Import). `receipt` gibt es hier nicht: das ist der
/// Kassenbeleg und steht nur als Quelle ([stockMovementSources]).
const List<String> stockMovementTypes = [
  'sale',
  'goods_receipt',
  'loss',
  'return',
  'transfer_out',
  'transfer_in',
  'condition_out',
  'condition_in',
  'stocktake',
  'adjustment',
  'takeover',
  'reversal',
  'revaluation',
  'method_change',
];

/// Woher eine Bewegung kommt (Katalog `BEWEGUNG_QUELLE`), zugleich der Filter
/// `source`.
const List<String> stockMovementSources = [
  'receipt',
  'invoice',
  'cancellation',
  'credit_note',
  'panel',
  'register',
  'api',
  'stocktake',
  'system',
];

/// Zustand der Ware an einer Bewegung (Katalog `LAGER_ZUSTAND`).
const List<String> stockConditions = ['sellable', 'defective'];

/// Ursache eines `stock.changed` (Katalog `LAGER_URSACHE`), abgeleitet aus der
/// juengsten Bewegung mit Mengenwirkung. `other`: keine Regel passt oder es
/// gibt keine Bewegung (dann ist `movementId` `null`).
const List<String> stockChangeCauses = [
  'sale',
  'invoice',
  'credit_note',
  'cancellation',
  'goods_receipt',
  'transfer',
  'loss',
  'condition',
  'reversal',
  'reservation',
  'stocktake',
  'takeover',
  'other',
];

/// Stand einer Zustellung (Katalog `ZUSTELLUNG`, derselbe wie bei
/// Partner-Webhooks). `dropped`: der Webhook wurde vor der Faelligkeit
/// deaktiviert oder geloescht.
const List<String> webhookDeliveryStatuses = ['delivered', 'pending', 'failed', 'dropped'];

/// Die Ereignisse, die ein Konto-Webhook abonnieren kann (Stufe 5a). Spaetere
/// Stufen ergaenzen `reservation.*` und `variant_group.*`;
/// `parseInventoryWebhookEvent` liefert fuer sie `null`.
const List<String> inventoryWebhookEvents = [
  'stock.changed',
  'stock.below_minimum',
  'article.created',
  'article.updated',
  'article.deactivated',
];

/// Die Felder der Huelle jeder Zustellung, in der Reihenfolge am Draht. Statt
/// `partnerId` (Partner-Webhooks) traegt sie `accountId`; `test` steht nur auf
/// Probesendungen.
const List<String> inventoryWebhookEnvelopeFields = ['id', 'type', 'createdAt', 'accountId', 'test', 'data'];

/// Hoechstzahl der Webhooks je Konto (`webhook_limit`).
const int inventoryWebhookLimit = 5;

/// Groesstes `limit` einer Liste; ohne Angabe liefert der Server 50.
const int inventoryListLimitMax = 200;

/// Die Codes, die die Lager-Endpunkte selbst senden. `validation` traegt
/// `errors: [{field, message}]`, `rate_limited` traegt `retryAfterSec` (dazu
/// die Kopfzeile `Retry-After`), auch bei `sendWebhookTest` nach 20
/// Probesendungen je Wiener Kalendertag (dann bis Mitternacht in Wien).
const List<String> inventoryErrorCodes = [
  'validation',
  'invalid_cursor',
  'article_not_found',
  'webhook_not_found',
  'webhook_limit',
  'invalid_webhook_url',
  'event_not_subscribed',
  'webhook_inactive',
  'inventory_api_not_enabled',
  'module_inactive',
  'rate_limited',
  'server_error',
];

/// Codes, die Anmeldung und Rand auf jedem Lager-Aufruf erzeugen koennen,
/// soweit sie nicht schon in [inventoryErrorCodes] stehen; zuletzt
/// `route_missing` (Code des Pakets). Dieselbe Ableitung wie bei der
/// Rechnungs-API.
const List<String> inventoryRequestErrorCodes = [
  'account_not_found',
  'admin_required',
  'api_not_approved',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'dialect_mismatch',
  'internal_translation_error',
  'live_not_enabled',
  'method_not_allowed',
  'mfa_required',
  'not_found',
  'register_user_no_business',
  'register_user_not_allowed',
  'register_user_not_found',
  'response_translation_failed',
  'session_expired',
  'session_other_cashregister',
  'unauthorized',
  'user_disabled',
  'user_verification_failed',
  'route_missing',
];
