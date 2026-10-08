/// Der Vertrag der Lager-API (Backend Stufe 5a lesen, 5b schreiben und
/// reservieren, 5c Varianten, Lager-Kern Stufe 3 Inventur) als Listen – Zwilling von `src/inventory/vertrag.ts` im
/// JS-Paket `@kreiseck/kasseneck-api`.
///
/// `test/lager_api_test.dart` vergleicht jede Liste in beide Richtungen mit
/// dem Abschnitt `inventory` in `test/fixtures/vertrag/surface.json` und mit
/// den Katalogen von `v3/v3-vokabular.json` (gezogen von
/// `tool/zwillinge.sh`). Wer hier etwas aendert, aendert zuerst das JS-Paket.
library;

/// Die 44 Endpunkte (14 aus 5a, 13 aus 5b, 5 aus 5c, 12 der Inventur), in der
/// Reihenfolge von `endpoints.public`.
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
  'createArticle',
  'updateArticle',
  'deactivateArticle',
  'receiveGoods',
  'transferStock',
  'recordStockLoss',
  'changeStockCondition',
  'reverseStockMovement',
  'createReservation',
  'extendReservation',
  'releaseReservation',
  'getReservation',
  'listReservations',
  'createVariantGroup',
  'updateVariantGroup',
  'getVariantGroup',
  'listVariantGroups',
  'addVariant',
  'createStocktake',
  'listStocktakes',
  'getStocktake',
  'listStocktakeItems',
  'recordStocktakeCount',
  'voidStocktakeCount',
  'listStocktakeCounts',
  'reviewStocktake',
  'recountStocktake',
  'closeStocktake',
  'cancelStocktake',
  'getStocktakePdf',
];

/// Art eines Standorts (Katalog `STANDORT_TYP`).
const List<String> locationTypes = ['warehouse', 'store', 'vehicle', 'other'];

/// Art einer Lagerbewegung (Katalog `BEWEGUNG_ART`), zugleich der Filter
/// `type`. `goods_receipt` ist der Wareneingang, `takeover` der uebernommene
/// Anfangsbestand (auch per Import). `receipt` gibt es hier nicht: das ist der
/// Kassenbeleg und steht nur als Quelle ([stockMovementSources]).
/// `reservation` (seit 10.4) aendert nur `reserved`: `quantityDelta` ist 0, die
/// Menge steht in `reservedDelta`. Neue Arten stehen hinten.
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
  'reservation',
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

/// Die Ereignisse, die ein Konto-Webhook abonnieren kann, in der Reihenfolge
/// von `listWebhooks().events`. `reservation.*` (seit 10.4) tragen die
/// Reservierung wie `getReservation`, mit dem Status danach:
/// `reservation.released` und `reservation.redeemed` kommen bei jeder
/// wirksamen Freigabe bzw. Einloesung, auch einer teilweisen (dann bleibt der
/// Status `active`). `variant_group.created` und `variant_group.updated`
/// (seit 10.5) tragen die Variantengruppe wie `getVariantGroup`; `updated`
/// kommt nur bei einer aussen sichtbaren Aenderung (neuer Wert, neue oder
/// stillgelegte Variante, Name, Vorgaben, Stilllegen der Gruppe).
const List<String> inventoryWebhookEvents = [
  'stock.changed',
  'stock.below_minimum',
  'article.created',
  'article.updated',
  'article.deactivated',
  'reservation.expired',
  'reservation.released',
  'reservation.redeemed',
  'variant_group.created',
  'variant_group.updated',
];

/// Die Felder der Huelle jeder Zustellung, in der Reihenfolge am Draht. Statt
/// `partnerId` (Partner-Webhooks) traegt sie `accountId`; `test` steht nur auf
/// Probesendungen.
const List<String> inventoryWebhookEnvelopeFields = ['id', 'type', 'createdAt', 'accountId', 'test', 'data'];

/// Hoechstzahl der Webhooks je Konto (`webhook_limit`).
const int inventoryWebhookLimit = 5;

/// Groesstes `limit` einer Liste; ohne Angabe liefert der Server 50.
const int inventoryListLimitMax = 200;

/// Die Codes, die die Lager-Endpunkte selbst senden (`errorCodes.inventory`;
/// `register_user_not_allowed` steht bei [inventoryRequestErrorCodes]).
/// `validation` traegt `errors: [{field, message}]`, `rate_limited` traegt
/// `retryAfterSec` (dazu die Kopfzeile `Retry-After`), auch bei
/// `sendWebhookTest` nach 20 Probesendungen je Wiener Kalendertag (dann bis
/// Mitternacht in Wien).
///
/// Seit 10.4 hinten angehaengt, in der Reihenfolge des Vertrags: die Codes der
/// schreibenden Endpunkte. `idempotency_key_required` (Schluessel fehlt),
/// `idempotency_conflict` (derselbe Schluessel mit anderem Inhalt),
/// `exceeds_stock` (Abgang, Umbuchung und Zustandswechsel ueberziehen nie),
/// `insufficient_available` (Reservierung; `details['details']`, siehe
/// `inventoryShortfalls`), `code_taken` und `external_id_taken` (mit `field`
/// und `articleId` des Artikels, dem der Code gehoert), `stock_kind_locked`,
/// `reservation_not_found`, `reservation_not_active` …
///
/// Seit 10.5 dahinter die Codes der Variantengruppen: `variant_group_not_found`
/// (unbekannte Kennung), `variant_already_exists` (die Kombination gibt es in
/// der Gruppe schon, dann mit `articleId` der bestehenden Variante, oder sie
/// steht zweimal in `variants`; jeweils mit `field`),
/// `invalid_variant_attributes` (ein Merkmal fehlt, ist unbekannt oder sein
/// Wert steht nicht in der Werteliste; `field` und `errors`),
/// `variant_group_inactive` (stillgelegte Gruppe: kein `addVariant`, keine
/// Aenderung ausser erneutem Stilllegen) und `variant_limit` (mehr als
/// [variantGroupActiveMax] aktive Varianten je Gruppe). Wiederverwendet:
/// `too_many_positions` traegt bei Varianten `field` (`variants`,
/// `createMatrix` bzw. `externalIds` bei `addVariant`): die Anfrage braeuchte
/// mehr Schreibvorgaenge, als in einen Vorgang passen; geschrieben wurde nichts.
///
/// Seit 10.7 dahinter die Codes der Inventur: `stocktake_not_found`,
/// `stocktake_not_open` (Zaehlen oder Stornieren ausserhalb der Zaehlung bzw.
/// an einer Position, die nicht zum Nachzaehlen frei ist), `stocktake_closed`
/// (abgeschlossen oder abgebrochen: nichts mehr schreibbar),
/// `stocktake_not_in_review` (Nachzaehlen und Abschluss nur in `review`),
/// `stocktake_closing` (der Abschluss bucht gerade), `stocktake_location_busy`
/// (am Standort laeuft schon eine Inventur; [inventoryBusyStocktakeId] nennt
/// sie), `stocktake_review_running` (die Pruefung rechnet noch),
/// `stocktake_recount_open` (Abschluss, solange Positionen zum Nachzaehlen
/// offen sind: erst nachzaehlen, dann erneut pruefen), `article_not_in_scope`,
/// `article_not_tracked`, `count_not_found`, `count_already_voided`,
/// `serial_already_counted` (dieselbe Seriennummer zweimal in einer Runde),
/// `too_many_counts` (mehr als [stocktakeCountsPerItemMax] Zaehlungen je
/// Position und Runde) und `stocktake_not_closed` (das Protokoll gibt es erst
/// nach dem Abschluss, auch nicht fuer eine abgebrochene Inventur).
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
  'idempotency_key_required',
  'idempotency_conflict',
  'location_not_found',
  'location_inactive',
  'invalid_location',
  'invalid_locations',
  'invalid_transfer',
  'operation_not_found',
  'already_reversed',
  'reversal_not_possible',
  'reversal_not_supported',
  'exceeds_stock',
  'no_positions',
  'too_many_positions',
  'invalid_step',
  'invalid_quantity',
  'invalid_amount',
  'invalid_price',
  'negative_value',
  'invalid_reason',
  'note_required',
  'withdrawal_type_required',
  'invalid_method',
  'invalid_stock_kind',
  'invalid_minimum',
  'invalid_dimensions',
  'weight_missing',
  'invalid_landed_cost',
  'invalid_distribution',
  'landed_costs_mismatch',
  'return_totals_mismatch',
  'lot_not_found',
  'invalid_serial',
  'serial_required',
  'serial_not_allowed',
  'serial_already_exists',
  'serial_not_in_stock',
  'code_taken',
  'external_id_taken',
  'group_not_found',
  'revenue_group_not_found',
  'stock_kind_locked',
  'article_inactive',
  'invalid_position',
  'invalid_condition',
  'reason_required',
  'insufficient_available',
  'reservation_not_found',
  'reservation_not_active',
  'variant_group_not_found',
  'variant_already_exists',
  'invalid_variant_attributes',
  'variant_group_inactive',
  'variant_limit',
  'stocktake_not_found',
  'stocktake_not_open',
  'stocktake_closed',
  'stocktake_not_in_review',
  'stocktake_closing',
  'stocktake_location_busy',
  'stocktake_review_running',
  'stocktake_recount_open',
  'article_not_in_scope',
  'article_not_tracked',
  'count_not_found',
  'count_already_voided',
  'serial_already_counted',
  'too_many_counts',
  'stocktake_not_closed',
];

/// Codes, die Anmeldung und Rand auf jedem Lager-Aufruf erzeugen koennen,
/// soweit sie nicht schon in [inventoryErrorCodes] stehen; zuletzt
/// `route_missing` (Code des Pakets). Dieselbe Ableitung wie bei der
/// Rechnungs-API.
const List<String> inventoryRequestErrorCodes = [
  'account_not_found',
  'admin_required',
  'api_not_approved',
  'app_check_invalid',
  'app_check_missing',
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

// ---- Schreiben und Reservierung (Backend Stufe 5b, seit 10.4) -----------------

/// Hinweise einer Buchung (`warnings[].code`, `warningCodes.inventory`). Sie
/// sind keine Fehler: die Buchung hat gewirkt. `insufficient_stock` gibt es nur
/// beim Verkauf (Abgang, Umbuchung und Zustandswechsel weisen mit
/// `exceeds_stock` ab), `below_minimum` misst am verfuegbaren Bestand
/// (`onHand - reserved`) gegen den Mindestbestand des Standorts,
/// `reservation_exceeded` meldet eine Rechnung, die mehr verkauft als
/// reserviert war.
///
/// Seit 10.7 die Hinweise der Inventur, je mit der Zahl der Positionen
/// (`items`): `defect_capped` (eine Fehlmenge im Zustand `defective` reichte
/// ueber den Defektbestand, der Rest blieb ungebucht), `uncounted_items` (nicht
/// gezaehlt und darum nicht gebucht), `not_booked` (nicht oder nicht ganz
/// gebucht, Grund an der Position, `notBooked`) und `recount_uncounted`
/// (Positionen zum Nachzaehlen blieben ungezaehlt; die Antwort von
/// `closeStocktake` traegt ihn).
const List<String> inventoryWarningCodes = [
  'insufficient_stock',
  'below_minimum',
  'return_exceeds_sale',
  'reservation_exceeded',
  'defect_capped',
  'uncounted_items',
  'not_booked',
  'recount_uncounted',
];

/// Bestandsart eines Artikels (`stockKind`): `quantity` = Menge, `serial` =
/// Einzelstueck mit Seriennummer. Kein Katalog des Vokabulars, der Server
/// uebersetzt das Feld selbst; nach der ersten Bewegung fest
/// (`stock_kind_locked`).
const List<String> stockKinds = ['quantity', 'serial'];

/// Grund eines Abgangs (`RecordStockLossRequest.reason`, Katalog
/// `LAGER_ABGANG_GRUND`). `other` braucht `note`.
const List<String> stockLossReasons = ['breakage', 'shrinkage', 'theft', 'expired', 'withdrawal', 'disposal', 'other'];

/// Art einer Entnahme (`withdrawalType`, Katalog `LAGER_ENTNAHME_ART`); Pflicht
/// bei `reason: 'withdrawal'`, sonst nicht erlaubt.
const List<String> withdrawalTypes = ['private', 'staff', 'gift', 'sample'];

/// Art von Nebenkosten eines Wareneingangs (`landedCosts[].type`, Katalog
/// `LAGER_NEBENKOSTEN_ART`). `discount` und `cash_discount` mindern den Wert.
const List<String> landedCostTypes = ['freight', 'customs', 'insurance', 'other', 'discount', 'cash_discount'];

/// Verteilung der Nebenkosten (`allocation`, Katalog `LAGER_VERTEILUNG`);
/// Vorgabe des Servers `value`.
const List<String> landedCostAllocations = ['value', 'quantity', 'weight', 'manual'];

/// Stand einer Reservierung (Katalog `RESERVIERUNG_STATUS`). Nur `active` haelt
/// Ware zurueck; die drei anderen sind endgueltig: `redeemed` (ueber eine
/// Rechnung eingeloest), `released` (freigegeben), `expired` (abgelaufen).
const List<String> reservationStatuses = ['active', 'redeemed', 'released', 'expired'];

/// Laengster `idempotencyKey` in Zeichen; laenger weist schon der Client ab,
/// er schneidet nie ab.
const int inventoryIdempotencyKeyMax = 120;

/// Kuerzeste Haltedauer einer Reservierung in Minuten (`expiresInMinutes`).
const int reservationMinutesMin = 5;

/// Laengste Haltedauer einer Reservierung in Minuten (30 Tage).
const int reservationMinutesMax = 43200;

// ---- Varianten (Backend Stufe 5c, seit 10.5) ---------------------------------

// Grenzen einer Variantengruppe, wie das Backend sie prueft. Das Paket prueft
// sie **nicht** vor dem Senden: der Server darf sie anheben, ohne dass eine
// aeltere Paketversion dann faelschlich abweist. Wer darueber liegt, bekommt
// `validation` (Merkmale, Werte, Matrix, `variants`) bzw. `variant_limit`.

/// Merkmale je Gruppe (Schluessel `^[a-z0-9_]{1,32}$`, eindeutig; `__…__` ist
/// reserviert).
const int variantAttributesMax = 3;

/// Werte je Merkmal (je 1–30 Zeichen, eindeutig ohne Gross/Klein).
const int variantValuesMax = 30;

/// Kombinationen bei `createMatrix: true` und hoechstens so viele Eintraege in
/// `variants` je Anfrage.
const int variantMatrixMax = 100;

/// Aktive Varianten je Gruppe (`variant_limit`).
const int variantGroupActiveMax = 250;

// ---- Inventur (Lager-Kern Stufe 3, seit 10.7) --------------------------------

/// Stand einer Inventur (Katalog `INVENTUR_STATUS`). Gezaehlt wird in
/// `counting`; `review` rechnet Soll und Differenz (erst ab hier sichtbar,
/// blind); `closing` bucht den Abschluss in Teilen; `closed` und `cancelled`
/// sind endgueltig. `creating` steht nur, solange eine grosse Anlage ihre
/// Positionen schreibt.
const List<String> stocktakeStatuses = ['creating', 'counting', 'review', 'closing', 'closed', 'cancelled'];

/// Art einer Inventur (Katalog `INVENTUR_ART`): `key_date` zu einem Stichtag
/// (`keyDate`), `perpetual` (permanente Inventur, ohne Stichtag).
const List<String> stocktakeTypes = ['key_date', 'perpetual'];

/// Umfang einer Inventur (Katalog `INVENTUR_UMFANG`): alle bestandsgefuehrten
/// Artikel des Standorts, Artikelgruppen oder genannte Artikel.
const List<String> stocktakeScopeTypes = ['all', 'groups', 'articles'];

/// Warum eine Position in der Pruefung „pruefen“ traegt (Katalog
/// `INVENTUR_PRUEFGRUND`): Bewegung zwischen der ersten und letzten Zaehlung,
/// Zaehlung mehr als 10 Tage vom Stichtag, Seriennummern weichen ab, nicht
/// gezaehlt.
const List<String> stocktakeCheckReasons = ['movements_between_counts', 'far_from_key_date', 'serial_mismatch', 'not_counted'];

/// Warum eine Position nicht oder nicht ganz gebucht wurde (`notBooked.code`,
/// Katalog `INVENTUR_NICHT_GEBUCHT`). Dazu kommen Codes, die schon englisch
/// sind (`serial_not_in_stock`, `serial_already_exists`, `article_not_found`);
/// das Modell laesst darum jeden Text stehen.
const List<String> stocktakeNotBookedReasons = ['serial_mismatch', 'recount_open', 'defect_capped'];

/// Woher eine Zaehlung bzw. Inventur kam (Katalog `INVENTUR_QUELLE`).
const List<String> stocktakeSources = ['register', 'panel', 'api'];

/// Wer handelte (Katalog `INVENTUR_AKTEUR`): Inhaber, Kasseneck-Admin,
/// Kassen-Benutzer, API-Schluessel.
const List<String> stocktakeActorTypes = ['owner', 'admin', 'register_user', 'api'];

/// Zu welchem Zeitpunkt das Inventar im Protokoll steht (Katalog
/// `INVENTUR_INVENTAR_ZUM`): `key_date` (auf das Ende des Stichtags
/// fortgeschrieben, Abschluss nach dem Stichtag) oder `count_date` (Menge zur
/// Aufnahme: permanente Inventur oder Abschluss vor dem Stichtag).
const List<String> stocktakeInventoryAsOf = ['key_date', 'count_date'];

// Grenzen einer Inventur, wie das Backend sie prueft. Wie bei den Varianten
// prueft das Paket sie **nicht** vor dem Senden.

/// Positionen je Inventur (`too_many_positions`; groessere Bestaende in
/// mehreren Inventuren nacheinander).
const int stocktakeItemsMax = 5000;

/// Positionen je `recountStocktake`.
const int stocktakeRecountItemsMax = 200;

/// Zaehlungen je Position und Runde (`too_many_counts`), hoechstens so viele
/// Seriennummern je Zaehlung.
const int stocktakeCountsPerItemMax = 200;
