/// Die Aufrufe der Lager-API: Artikel, Standorte, Bestand und Bewegungen
/// lesen, Konto-Webhooks verwalten (Backend Stufe 5a), Artikel anlegen und
/// aendern, Bestand buchen und Ware reservieren (Stufe 5b), Variantengruppen
/// (Stufe 5c, seit 10.5), Inventur (Lager-Kern Stufe 3, seit 10.7) – Zwilling von
/// `createInventoryClient` im JS-Paket `@kreiseck/kasseneck-api/inventory`.
///
/// **Geprueft wird hier nur, was ohne Netz sicher falsch ist** (leere Kennung,
/// `limit` ausserhalb 1–200, eine Aenderung ohne Feld, ein Code zugleich mit
/// einer eigenen Kennung, ein ungueltiger `idempotencyKey`; mehr in
/// `schreiben.dart`). Alles Fachliche prueft der Server und meldet es als
/// `validation` mit `details['errors']` oder mit seinem Code; zwei Pruefungen
/// hiessen zwei Wahrheiten. Eine abgewiesene Anfrage geht nie hinaus.
///
/// Lesen hat keine Wirkung: nach einem Zeitlimit darf derselbe Aufruf
/// wiederholt werden. Bei `rate_limited` vorher [inventoryRetryAfterSec]
/// warten.
///
/// **Schreiben** wird nie von selbst wiederholt. Nach einem Zeitlimit oder
/// Netzfehler (`KasseneckHttpError`, Grund `timeout` bzw. `network`) ist offen,
/// ob der Aufruf beim Server gewirkt hat (seit 10.4.1 Ausgang `unknown`, Liste
/// `unknownOutcomeCalls`): dann denselben Aufruf mit **demselben**
/// `idempotencyKey` noch einmal senden. Er wirkt genau einmal und liefert die
/// gespeicherte Antwort; ein neuer Schluessel buchte ein zweites Mal.
library;

import 'package:http/http.dart' as http;

import '../aufrufe.dart';
import '../kasse/lager.dart' show StockValue;
import '../register/fehler.dart';
import 'fehler.dart';
import 'lesen.dart';
import 'anfragen.dart';
import 'modelle.dart';
import 'schreiben.dart';
import 'transport.dart';
import 'vertrag.dart';

class InventoryClient {
  /// [apiKey] ist der `api_key` des Kontos (`kr_live_…` / `kr_test_…`) und
  /// gehoert auf einen Server. Ein Partner-Schluessel (`pk_…`) oder ein
  /// Kassen-Token (`cb_…`) wirft schon hier.
  InventoryClient({
    required String apiKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  }) : _transport = InventoryTransport(
          apiKey: apiKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
          timeout: timeout,
          clientHeader: clientHeader,
          omitKasseneckHeaders: omitKasseneckHeaders,
        );

  /// Mit einem bereits gebauten Transport (Tests, eigene Adresse).
  InventoryClient.withTransport(InventoryTransport transport) : _transport = transport;

  final InventoryTransport _transport;

  // ---- Artikel ------------------------------------------------------------------

  Future<Article> getArticle(String articleId) async {
    const name = Aufrufe.getArticle;
    final daten = await _transport.call(name, {'articleId': kennung(name, 'articleId', articleId)});
    return artikel(const Ort(name, 'article'), daten['article']);
  }

  /// Eine Seite Artikel, nach `updatedAt` aufsteigend.
  ///
  /// [updatedSince] (inklusive): wer sich das `updatedAt` des letzten Treffers
  /// merkt (`DateTime.parse(article.updatedAt!)`) und damit wieder fragt,
  /// verliert nichts. [limit] 1–200, Vorgabe des Servers 50; [cursor] ist der
  /// `nextCursor` der vorigen Seite.
  Future<ArticlePage> listArticles({
    DateTime? updatedSince,
    String? groupId,
    String? variantGroupId,
    bool? active,
    bool? stockTracked,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listArticles;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'updatedSince': _zeit(updatedSince),
          'groupId': groupId,
          'variantGroupId': variantGroupId,
          'active': active,
          'stockTracked': stockTracked,
          'limit': limit,
          'cursor': cursor,
        }));
    return ArticlePage(articles: liste(name, daten, 'articles', artikel), nextCursor: naechsterCursor(name, daten));
  }

  /// Alle Artikel der Abfrage, Seite fuer Seite ueber `nextCursor`. [cursor]
  /// ist der Startpunkt; nennt der Server denselben Cursor zweimal, endet der
  /// Strom mit einem Antwortfehler statt einer Endlosschleife.
  Stream<Article> iterateArticles({
    DateTime? updatedSince,
    String? groupId,
    String? variantGroupId,
    bool? active,
    bool? stockTracked,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listArticles, cursor, (c) async {
        final s = await listArticles(
          updatedSince: updatedSince,
          groupId: groupId,
          variantGroupId: variantGroupId,
          active: active,
          stockTracked: stockTracked,
          limit: limit,
          cursor: c,
        );
        return (eintraege: s.articles, nextCursor: s.nextCursor);
      });

  /// Ein aktiver Artikel per [code] (`number`, `ean` oder `internalCode`) oder
  /// per eigener Kennung aus `externalIds` ([externalSystem] mit
  /// [externalId]), nie beides. Ein stillgelegter Artikel gilt als nicht
  /// gefunden (`article_not_found`).
  Future<Article> lookupArticleByCode({String? code, String? externalSystem, String? externalId}) async {
    const name = Aufrufe.lookupArticleByCode;
    final extern = externalSystem != null || externalId != null;
    if (code != null && extern) {
      throw const KasseneckValidationError(name, 'entweder code oder externalSystem mit externalId', 'request');
    }
    final params = extern
        ? {
            'externalSystem': kennung(name, 'externalSystem', externalSystem),
            'externalId': kennung(name, 'externalId', externalId),
          }
        : {'code': kennung(name, 'code', code)};
    final daten = await _transport.call(name, params);
    return artikel(const Ort(name, 'article'), daten['article']);
  }

  // ---- Standorte und Bestand -------------------------------------------------------

  /// Alle Standorte des Kontos, samt aufgeloesten (`active: false`) und dem
  /// Hauptstandort.
  Future<List<Location>> listLocations() async {
    const name = Aufrufe.listLocations;
    return liste(name, await _transport.call(name, const {}), 'locations', standort);
  }

  /// Bestand eines Artikels je Standort.
  Future<StockResult> getStock(String articleId) async {
    const name = Aufrufe.getStock;
    final daten = await _transport.call(name, {'articleId': kennung(name, 'articleId', articleId)});
    return StockResult(stock: liste(name, daten, 'stock', bestand), values: _werte(name, daten));
  }

  /// Eine Seite Bestandszeilen. [belowMinimum]: nur Zeilen, deren `onHand`
  /// unter dem Mindestbestand ihres Standorts liegt (dieselbe Regel wie
  /// `stock.below_minimum`). [changedSince] (inklusive), nach `updatedAt`
  /// aufsteigend.
  Future<StockPage> listStock({
    String? locationId,
    String? articleId,
    bool? belowMinimum,
    DateTime? changedSince,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listStock;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'locationId': locationId,
          'articleId': articleId,
          'belowMinimum': belowMinimum,
          'changedSince': _zeit(changedSince),
          'limit': limit,
          'cursor': cursor,
        }));
    return StockPage(
      stock: liste(name, daten, 'stock', bestand),
      values: _werte(name, daten),
      nextCursor: naechsterCursor(name, daten),
    );
  }

  /// Alle Bestandszeilen der Abfrage, Seite fuer Seite. Die Werte (`values`)
  /// stehen je Seite in [listStock]; der Strom liefert nur die Zeilen.
  Stream<StockLevel> iterateStock({
    String? locationId,
    String? articleId,
    bool? belowMinimum,
    DateTime? changedSince,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listStock, cursor, (c) async {
        final s = await listStock(
          locationId: locationId,
          articleId: articleId,
          belowMinimum: belowMinimum,
          changedSince: changedSince,
          limit: limit,
          cursor: c,
        );
        return (eintraege: s.stock, nextCursor: s.nextCursor);
      });

  /// Das Lagerprotokoll, neueste zuerst. Nur nach [articleId] **oder**
  /// [locationId] filtern, nicht beides (sonst `validation`). [type] aus
  /// `stockMovementTypes`, [source] aus `stockMovementSources`.
  Future<StockMovementPage> listStockMovements({
    String? articleId,
    String? locationId,
    DateTime? from,
    DateTime? to,
    String? type,
    String? source,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listStockMovements;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'articleId': articleId,
          'locationId': locationId,
          'from': _zeit(from),
          'to': _zeit(to),
          'type': type,
          'source': source,
          'limit': limit,
          'cursor': cursor,
        }));
    return StockMovementPage(movements: liste(name, daten, 'movements', bewegung), nextCursor: naechsterCursor(name, daten));
  }

  Stream<StockMovement> iterateStockMovements({
    String? articleId,
    String? locationId,
    DateTime? from,
    DateTime? to,
    String? type,
    String? source,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listStockMovements, cursor, (c) async {
        final s = await listStockMovements(
          articleId: articleId,
          locationId: locationId,
          from: from,
          to: to,
          type: type,
          source: source,
          limit: limit,
          cursor: c,
        );
        return (eintraege: s.movements, nextCursor: s.nextCursor);
      });

  // ---- Webhooks ------------------------------------------------------------------

  /// Legt einen Webhook an (hoechstens 5 je Konto, `webhook_limit`). [url] ist
  /// eine vollstaendige `https://`-Adresse, [events] mindestens eines aus
  /// `inventoryWebhookEvents`.
  ///
  /// **Das Secret in der Antwort kommt nur dieses eine Mal**; sofort dorthin
  /// schreiben, wo der Empfaenger es liest, nicht in ein Protokoll.
  Future<InventoryWebhookWithSecret> createWebhook({
    required String url,
    required List<String> events,
    String? description,
  }) async {
    const name = Aufrufe.createWebhook;
    final adresse = kennung(name, 'url', url);
    if (events.isEmpty) {
      throw const KasseneckValidationError(name, 'events ist leer; ein Webhook ohne Ereignis bekaeme nie etwas', 'request');
    }
    return _mitSecret(name, await _transport.call(name, {'url': adresse, 'events': [...events], 'description': ?description}));
  }

  /// Aendert nur die genannten Felder. [removeDescription] loescht die
  /// Beschreibung (am Draht `description: null`) und schliesst [description]
  /// aus.
  Future<InventoryWebhook> updateWebhook(
    String webhookId, {
    String? url,
    List<String>? events,
    bool? active,
    String? description,
    bool removeDescription = false,
  }) async {
    const name = Aufrufe.updateWebhook;
    final id = kennung(name, 'webhookId', webhookId);
    if (removeDescription && description != null) {
      throw const KasseneckValidationError(name, 'description und removeDescription zugleich', 'request');
    }
    final params = <String, dynamic>{
      'webhookId': id,
      'url': ?url,
      if (events != null) 'events': [...events],
      'active': ?active,
      'description': ?description,
      if (removeDescription) 'description': null,
    };
    if (params.length == 1) throw const KasseneckValidationError(name, 'Aenderung nennt kein Feld', 'request');
    final daten = await _transport.call(name, params);
    return webhook(const Ort(name, 'webhook'), daten['webhook']);
  }

  Future<({String webhookId, bool deleted})> deleteWebhook(String webhookId) async {
    const name = Aufrufe.deleteWebhook;
    final id = kennung(name, 'webhookId', webhookId);
    final daten = await _transport.call(name, {'webhookId': id});
    final gemeldet = daten['webhookId'];
    return (webhookId: gemeldet is String && gemeldet.isNotEmpty ? gemeldet : id, deleted: daten['deleted'] == true);
  }

  /// Die Webhooks des Kontos und die Ereignisse, die es abonnieren kann.
  Future<InventoryWebhookList> listWebhooks() async {
    const name = Aufrufe.listWebhooks;
    final daten = await _transport.call(name, const {});
    final ereignisse = daten['events'];
    return InventoryWebhookList(
      webhooks: liste(name, daten, 'webhooks', webhook),
      events: ereignisse is List ? List.unmodifiable(ereignisse.whereType<String>()) : const [],
    );
  }

  /// Eine Probe genau dieses Ereignisses an genau diesen Webhook, mit
  /// erfundener Nutzlast und `test: true` in der Huelle. Der Webhook muss das
  /// Ereignis abonnieren (`event_not_subscribed`) und aktiv sein
  /// (`webhook_inactive`); hoechstens 20 je Konto und Wiener Kalendertag.
  Future<InventoryWebhookTestResult> sendWebhookTest(String webhookId, String event) async {
    const name = Aufrufe.sendWebhookTest;
    final id = kennung(name, 'webhookId', webhookId);
    final ereignis = kennung(name, 'event', event);
    final daten = await _transport.call(name, {'webhookId': id, 'event': ereignis});
    final eventId = daten['eventId'];
    final gesendet = daten['event'];
    return InventoryWebhookTestResult(
      eventId: eventId is String ? eventId : '',
      event: gesendet is String ? gesendet : ereignis,
      deliveries: liste(name, daten, 'deliveries', (ort, e) => probeZustellung(ort, e, id)),
    );
  }

  /// Ein neues Secret fuer denselben Webhook. Ab der Antwort gilt nur noch das
  /// neue (keine Uebergangsfrist): erst speichern, dann weiterarbeiten.
  Future<InventoryWebhookWithSecret> rotateWebhookSecret(String webhookId) async {
    const name = Aufrufe.rotateWebhookSecret;
    return _mitSecret(name, await _transport.call(name, {'webhookId': kennung(name, 'webhookId', webhookId)}));
  }

  /// Die letzten Zustellungen, neueste zuerst; mit [webhookId] nur die eines
  /// Webhooks.
  Future<List<InventoryWebhookDelivery>> listWebhookDeliveries({String? webhookId, int? limit}) async {
    const name = Aufrufe.listWebhookDeliveries;
    final params = {
      if (webhookId != null) 'webhookId': kennung(name, 'webhookId', webhookId),
      ..._abfrage(name, {'limit': limit}),
    };
    return liste(name, await _transport.call(name, params), 'deliveries', zustellung);
  }

  // ---- Artikel schreiben (Stufe 5b) -------------------------------------------------

  /// Legt einen Artikel an. Mit `ean` ein Fremdartikel mit diesem Code
  /// (gueltige Pruefziffer, frei im Konto), sonst vergibt der Server den
  /// naechsten eigenen Code. Antwort: der Artikel wie [getArticle].
  Future<Article> createArticle(CreateArticleRequest request) async {
    const name = Aufrufe.createArticle;
    final p = request.toJson();
    _schreiben(name, p);
    return _artikel(name, await _transport.call(name, p));
  }

  /// Aendert nur die genannten Felder eines Artikels; [UpdateArticleRequest.clear]
  /// leert Felder.
  Future<Article> updateArticle(UpdateArticleRequest request) async {
    const name = Aufrufe.updateArticle;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'articleId', p['articleId']);
    final fremd = request.clear.difference(leerbareArtikelfelder);
    if (fremd.isNotEmpty) throw anfragefehler(name, 'clear nennt Felder, die sich nicht leeren lassen: ${fremd.join(', ')}');
    final doppelt = request.clear.where((f) => p[f] != null).toList();
    if (doppelt.isNotEmpty) throw anfragefehler(name, 'zugleich gesetzt und geleert: ${doppelt.join(', ')}');
    if (p.keys.every((k) => k == 'idempotencyKey' || k == 'articleId')) {
      throw anfragefehler(name, 'die Aenderung nennt kein Feld');
    }
    return _artikel(name, await _transport.call(name, p));
  }

  /// Legt einen Artikel still (`active: false`); Code und eigene Kennungen
  /// werden frei.
  Future<Article> deactivateArticle(DeactivateArticleRequest request) async {
    const name = Aufrufe.deactivateArticle;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'articleId', p['articleId']);
    return _artikel(name, await _transport.call(name, p));
  }

  // ---- Buchen (Stufe 5b) -----------------------------------------------------------

  /// Bucht einen Wareneingang. Ohne `locationId` am Standard-Standort; die
  /// Antwort traegt keine Werte, auch mit dem Recht `costs` nicht. Fuer die
  /// Vorschau mit Werten: [previewGoodsReceipt].
  Future<StockOperation> receiveGoods(ReceiveGoodsRequest request) async {
    const name = Aufrufe.receiveGoods;
    final p = request.toJson();
    _schreiben(name, p);
    pruefePositionen(name, p['items']);
    return vorgang(name, await _transport.call(name, p));
  }

  /// Vorschau eines Wareneingangs (`receiveGoods` mit `dryRun: true`): prueft
  /// Positionen, Artikel, Preise und Nebenkosten und rechnet die Verteilung,
  /// schreibt aber nichts. Ein `idempotencyKey` ist freigestellt, wird nur auf
  /// seine Form geprueft und nicht verbraucht. Werte (`baseCents` …) nur mit
  /// dem Recht `costs`. Fehler tragen den Aufrufnamen `receiveGoods`.
  Future<GoodsReceiptPreview> previewGoodsReceipt(GoodsReceiptPreviewRequest request) async {
    const name = Aufrufe.receiveGoods;
    final p = request.toJson();
    _schreiben(name, p, schluesselPflicht: false);
    pruefePositionen(name, p['items']);
    final daten = await _transport.call(name, {...p, 'dryRun': true});
    return GoodsReceiptPreview(preview: liste(name, daten, 'preview', vorschauZeile));
  }

  /// Bucht Ware von einem Standort an einen anderen; ueberzieht nie (`exceeds_stock`).
  Future<StockOperation> transferStock(TransferStockRequest request) async {
    const name = Aufrufe.transferStock;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'fromLocationId', p['fromLocationId']);
    kennung(name, 'toLocationId', p['toLocationId']);
    pruefePositionen(name, p['items']);
    return vorgang(name, await _transport.call(name, p));
  }

  /// Bucht einen Abgang (Bruch, Schwund, Diebstahl, Entnahme …); ueberzieht
  /// nie (`exceeds_stock`).
  Future<StockOperation> recordStockLoss(RecordStockLossRequest request) async {
    const name = Aufrufe.recordStockLoss;
    final p = request.toJson();
    _schreiben(name, p);
    pruefePositionen(name, p['items']);
    return vorgang(name, await _transport.call(name, p));
  }

  /// Bucht Ware zwischen `sellable` und `defective` um; ueberzieht nie (`exceeds_stock`).
  Future<StockOperation> changeStockCondition(ChangeStockConditionRequest request) async {
    const name = Aufrufe.changeStockCondition;
    final p = request.toJson();
    _schreiben(name, p);
    pruefePositionen(name, p['items']);
    return vorgang(name, await _transport.call(name, p));
  }

  /// Nimmt einen ganzen Vorgang (`operationId`) mit einer Gegenbuchung zurueck.
  Future<StockOperation> reverseStockMovement(ReverseStockMovementRequest request) async {
    const name = Aufrufe.reverseStockMovement;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'operationId', p['operationId']);
    return vorgang(name, await _transport.call(name, p));
  }

  // ---- Reservierung (Stufe 5b) -------------------------------------------------------

  /// Reserviert Ware (Checkout im Shop): ganz oder gar nicht, gemessen am
  /// verfuegbaren Bestand (`onHand - reserved`). Fehlt etwas, entsteht nichts:
  /// `insufficient_available`, die fehlenden Positionen in
  /// [inventoryShortfalls]. Eingeloest wird ueber eine Rechnung
  /// (`InvoiceApi.issueInvoice` mit `IssueInvoiceItemInput.reservationId`),
  /// sonst laeuft die Reservierung ab und gibt die Ware wieder frei.
  Future<Reservation> createReservation(CreateReservationRequest request) async {
    const name = Aufrufe.createReservation;
    final p = request.toJson();
    _schreiben(name, p);
    pruefePositionen(name, p['items']);
    pruefeMinuten(name, request.expiresInMinutes, pflicht: false);
    return _reservierung(name, await _transport.call(name, p));
  }

  /// Verlaengert eine aktive Reservierung: neuer Ablauf = jetzt + `expiresInMinutes`.
  Future<Reservation> extendReservation(ExtendReservationRequest request) async {
    const name = Aufrufe.extendReservation;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'reservationId', p['reservationId']);
    pruefeMinuten(name, request.expiresInMinutes, pflicht: true);
    return _reservierung(name, await _transport.call(name, p));
  }

  /// Gibt reservierte Ware frei: ohne `items` alles, sonst je Position (ohne
  /// `quantity` der ganze offene Rest). Die Antwort traegt den Stand danach;
  /// `released` wird der Status erst, wenn nichts mehr offen ist.
  Future<Reservation> releaseReservation(ReleaseReservationRequest request) async {
    const name = Aufrufe.releaseReservation;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'reservationId', p['reservationId']);
    if (request.items case final positionen? when positionen.isEmpty) {
      throw anfragefehler(name, 'items ist leer; um alles freizugeben, items ganz weglassen');
    }
    pruefePositionen(name, p['items']);
    return _reservierung(name, await _transport.call(name, p));
  }

  /// Eine Reservierung mit ihrem aktuellen Stand.
  Future<Reservation> getReservation(String reservationId) async {
    const name = Aufrufe.getReservation;
    final id = kennung(name, 'reservationId', reservationId);
    return _reservierung(name, await _transport.call(name, {'reservationId': id}));
  }

  /// Eine Seite Reservierungen, neueste zuerst. [status] aus
  /// `reservationStatuses`, [reference] genau diese Referenz.
  Future<ReservationPage> listReservations({String? status, String? reference, int? limit, String? cursor}) async {
    const name = Aufrufe.listReservations;
    final daten = await _transport.call(
        name, _abfrage(name, {'status': status, 'reference': reference, 'limit': limit, 'cursor': cursor}));
    return ReservationPage(
      reservations: liste(name, daten, 'reservations', reservierung),
      nextCursor: naechsterCursor(name, daten),
    );
  }

  /// Alle Reservierungen der Abfrage, Seite fuer Seite ueber `nextCursor`.
  Stream<Reservation> iterateReservations({String? status, String? reference, int? limit, String? cursor}) =>
      _seitenweise(Aufrufe.listReservations, cursor, (c) async {
        final s = await listReservations(status: status, reference: reference, limit: limit, cursor: c);
        return (eintraege: s.reservations, nextCursor: s.nextCursor);
      });

  // ---- Varianten (Stufe 5c) -----------------------------------------------------------
  //
  // Eine Variante ist ein gewoehnlicher Artikel mit `variantGroupId` und
  // `variantAttributes`; gelesen, gebucht und reserviert wird sie wie jeder
  // Artikel. Die Gruppenantworten tragen nur die Kennungen der Varianten, die
  // Artikel selbst liefert `listArticles(variantGroupId: …)`.
  //
  // Vor dem Senden geprueft wird wie im JS-Zwilling nur, was ohne Netz sicher
  // falsch ist: der Schluessel, `variantGroupId`, `createMatrix: true` zusammen
  // mit `variants`, eine Aenderung ohne Feld, `active` anders als `false` oder
  // nicht allein, und wie ueberall der sichere Ganzzahlbereich. Die Grenzen
  // (Merkmale, Werte, Matrix, aktive Varianten) prueft der Server: er darf sie
  // anheben, ohne dass diese Paketversion dann falsch abweist. Bruchzahlen,
  // eine fehlende Merkmalsabbildung oder `variants`, die keine Liste ist,
  // schliesst hier schon der Typ aus.
  //
  // Wiederholen wie bei jedem Schreiben: nach Ausgang unklar denselben Aufruf
  // mit **demselben** `idempotencyKey`; ein neuer Schluessel legte die Gruppe
  // ein zweites Mal an. Ein abgebrochenes Stilllegen vollendet jede
  // Wiederholung von `updateVariantGroup(active: false)`, auch mit neuem
  // Schluessel.

  /// Legt eine Variantengruppe an: mit `createMatrix: true` alle Kombinationen
  /// der Werte (hoechstens 100), sonst die genannten `variants` (hoechstens
  /// 100), ohne beides nur die Gruppe. Jede Variante entsteht als Artikel mit
  /// den Feldern wie bei [createArticle]; was sie nicht nennt, fuellen die
  /// Vorgaben. Antwort: die Gruppe mit `variants` (Kennung und Merkmale je
  /// Variante).
  ///
  /// Braucht die Anlage mehr Schreibvorgaenge, als in einen Vorgang passen,
  /// kommt `too_many_positions` mit `field` (`variants` bzw. `createMatrix`)
  /// und nichts ist geschrieben: weniger Varianten senden, den Rest per
  /// [addVariant].
  Future<VariantGroup> createVariantGroup(CreateVariantGroupRequest request) async {
    const name = Aufrufe.createVariantGroup;
    final p = request.toJson();
    _schreiben(name, p);
    if (request.createMatrix == true && request.variants != null) {
      throw anfragefehler(
          name, 'createMatrix und variants schliessen sich aus: entweder alle Kombinationen oder die genannten Varianten');
    }
    _vorgabenLeeren(name, request.defaults);
    return _gruppe(name, await _transport.call(name, p));
  }

  /// Aendert eine aktive Gruppe (Name, Vorgaben, neue Werte) oder legt sie mit
  /// `active: false` still: die Gruppe und alle ihre Varianten, endgueltig. Die
  /// Antwort kommt erst, wenn alle Varianten stillgelegt sind. Bestehende
  /// Varianten aendern Name und Vorgaben nicht (dafuer [updateArticle]).
  Future<VariantGroup> updateVariantGroup(UpdateVariantGroupRequest request) async {
    const name = Aufrufe.updateVariantGroup;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'variantGroupId', p['variantGroupId']);
    if (request.clearDefaults && request.defaults != null) {
      throw anfragefehler(name, 'defaults und clearDefaults zugleich');
    }
    final aenderungen = ['name', 'defaults', 'addAttributeValues'].where(p.containsKey);
    if (request.active case final aktiv?) {
      if (aktiv) throw anfragefehler(name, 'active kennt nur false (stilllegen); eine stillgelegte Gruppe bleibt stillgelegt');
      if (aenderungen.isNotEmpty) throw anfragefehler(name, 'active: false steht allein, ohne weitere Aenderung');
    } else if (aenderungen.isEmpty) {
      throw anfragefehler(name, 'die Aenderung nennt kein Feld');
    }
    _vorgabenLeeren(name, request.defaults);
    return _gruppe(name, await _transport.call(name, p));
  }

  /// Legt eine Variante in einer aktiven Gruppe an. Antwort: der Artikel wie
  /// [createArticle]. Gibt es die Kombination schon, kommt
  /// `variant_already_exists` mit `articleId` der bestehenden Variante; nach
  /// dem Stilllegen einer Variante ist ihre Kombination wieder frei.
  Future<Article> addVariant(AddVariantRequest request) async {
    const name = Aufrufe.addVariant;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'variantGroupId', p['variantGroupId']);
    return _artikel(name, await _transport.call(name, p));
  }

  /// Eine Variantengruppe mit ihren aktiven Varianten (eingefroren, wenn stillgelegt).
  Future<VariantGroup> getVariantGroup(String variantGroupId) async {
    const name = Aufrufe.getVariantGroup;
    final id = kennung(name, 'variantGroupId', variantGroupId);
    return _gruppe(name, await _transport.call(name, {'variantGroupId': id}));
  }

  /// Eine Seite Variantengruppen, nach `updatedAt` aufsteigend (gleiche Zeit
  /// nach Kennung). [updatedSince] inklusive; [limit] 1–200, Vorgabe des
  /// Servers 50.
  Future<VariantGroupPage> listVariantGroups({bool? active, DateTime? updatedSince, int? limit, String? cursor}) async {
    const name = Aufrufe.listVariantGroups;
    final daten = await _transport.call(
        name, _abfrage(name, {'active': active, 'updatedSince': _zeit(updatedSince), 'limit': limit, 'cursor': cursor}));
    return VariantGroupPage(
      variantGroups: liste(name, daten, 'variantGroups', variantengruppe),
      nextCursor: naechsterCursor(name, daten),
    );
  }

  /// Alle Variantengruppen der Abfrage, Seite fuer Seite ueber `nextCursor`.
  Stream<VariantGroup> iterateVariantGroups({bool? active, DateTime? updatedSince, int? limit, String? cursor}) =>
      _seitenweise(Aufrufe.listVariantGroups, cursor, (c) async {
        final s = await listVariantGroups(active: active, updatedSince: updatedSince, limit: limit, cursor: c);
        return (eintraege: s.variantGroups, nextCursor: s.nextCursor);
      });

  // ---- Inventur (Lager-Kern Stufe 3, seit 10.7) --------------------------------
  //
  // Ablauf: [createStocktake] → [recordStocktakeCount] (beliebig oft, auch von
  // mehreren Geraeten; je Position addiert) → [reviewStocktake] (erst jetzt
  // Soll und Differenz) → bei Bedarf [recountStocktake] und erneut
  // [reviewStocktake] → [closeStocktake] → [getStocktakePdf]. Pruefen und
  // Abschliessen rechnet der Server im Hintergrund: die Antwort traegt den
  // Zwischenstand (`review.complete: false` bzw. `status: 'closing'`),
  // [getStocktake] den Fortgang.
  //
  // **Blind:** vor `review` traegt keine Antwort ein Soll; `blind: false` zeigt
  // beim Zaehlen nur den heutigen Buchbestand (`bookStockNow`), nie das Soll
  // zur Referenzzeit.
  //
  // Rechte wie beim Schreiben: Lesen mit jedem Schluessel, alles Schreibende
  // (auch Zaehlen) mit dem Konto-Schalter „Lager-API schreiben“ (Test-Schluessel
  // immer), sonst `inventory_api_not_enabled`; Werte und das Protokoll mit
  // Werten nur mit dem Recht `costs`.
  //
  // Vor dem Senden geprueft wird wie im JS-Zwilling nur, was ohne Netz sicher
  // falsch ist: der Schluessel, fehlende Kennungen (`stocktakeId`,
  // `locationId`, `articleId`, `countId`), ein leerer Grund, eine leere
  // Nachzaehlen-Liste und der sichere Ganzzahlbereich. Eine negative Menge
  // geht hinaus (der Server meldet `invalid_quantity`); Umfang, Stichtag,
  // Seriennummern und Zustand prueft der Server.
  //
  // Wiederholen wie bei jedem Schreiben: nach Ausgang unklar denselben Aufruf
  // mit **demselben** `idempotencyKey`. Eine Zaehlung wirkt dann genau einmal
  // (das Zaehldokument ist selbst der Nachweis); ein neuer Schluessel zaehlte
  // die Ware ein zweites Mal.

  /// Legt eine Inventur an. Je Standort hoechstens eine offene
  /// (`stocktake_location_busy`, [inventoryBusyStocktakeId] nennt sie); Umfang
  /// `groups` bzw. `articles` nur mit bestandsgefuehrten Artikeln
  /// (`article_not_tracked`). Jede Inventur beginnt in `counting`.
  Future<Stocktake> createStocktake(CreateStocktakeRequest request) async {
    const name = Aufrufe.createStocktake;
    final p = request.toJson();
    _schreiben(name, p);
    kennung(name, 'locationId', p['locationId']);
    return _inventur(name, await _transport.call(name, p));
  }

  /// Eine Seite Inventuren des Kontos. Ohne [updatedSince] zuletzt geaenderte
  /// zuerst (`updatedAt` absteigend; offene stehen dabei nicht zwingend oben,
  /// dafuer gibt es [status]). Mit [updatedSince] aufsteigend und inklusive:
  /// ein Abgleich mit dem groessten gesehenen `updatedAt` als naechstem
  /// [updatedSince] ist lueckenlos (der Eintrag an der Grenze kommt noch einmal).
  Future<StocktakePage> listStocktakes({
    String? status,
    String? locationId,
    DateTime? updatedSince,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listStocktakes;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'status': status,
          'locationId': locationId,
          'updatedSince': _zeit(updatedSince),
          'limit': limit,
          'cursor': cursor,
        }));
    return StocktakePage(stocktakes: liste(name, daten, 'stocktakes', inventur), nextCursor: naechsterCursor(name, daten));
  }

  /// Alle Inventuren der Abfrage, Seite fuer Seite, in der Reihenfolge von
  /// [listStocktakes].
  Stream<Stocktake> iterateStocktakes({
    String? status,
    String? locationId,
    DateTime? updatedSince,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listStocktakes, cursor, (c) async {
        final s = await listStocktakes(
            status: status, locationId: locationId, updatedSince: updatedSince, limit: limit, cursor: c);
        return (eintraege: s.stocktakes, nextCursor: s.nextCursor);
      });

  /// Eine Inventur samt `progress.counted` (gezaehlte Positionen).
  Future<Stocktake> getStocktake(String stocktakeId) async {
    const name = Aufrufe.getStocktake;
    final id = kennung(name, 'stocktakeId', stocktakeId);
    return _inventur(name, await _transport.call(name, {'stocktakeId': id}));
  }

  /// Positionen einer Inventur nach Kennung; [openOnly] = ungezaehlt bzw. in
  /// `review` zum Nachzaehlen offen.
  Future<StocktakeItemPage> listStocktakeItems({
    required String stocktakeId,
    bool? openOnly,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listStocktakeItems;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'stocktakeId': kennung(name, 'stocktakeId', stocktakeId),
          'openOnly': openOnly,
          'limit': limit,
          'cursor': cursor,
        }));
    return StocktakeItemPage(items: liste(name, daten, 'items', inventurPosition), nextCursor: naechsterCursor(name, daten));
  }

  /// Alle Positionen der Abfrage, Seite fuer Seite.
  Stream<StocktakeItem> iterateStocktakeItems({
    required String stocktakeId,
    bool? openOnly,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listStocktakeItems, cursor, (c) async {
        final s = await listStocktakeItems(stocktakeId: stocktakeId, openOnly: openOnly, limit: limit, cursor: c);
        return (eintraege: s.items, nextCursor: s.nextCursor);
      });

  /// Zaehlungen einer Inventur, neueste zuerst, auch stornierte; mit
  /// [articleId] nur die des Artikels.
  Future<StocktakeCountPage> listStocktakeCounts({
    required String stocktakeId,
    String? articleId,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listStocktakeCounts;
    final daten = await _transport.call(
        name,
        _abfrage(name, {
          'stocktakeId': kennung(name, 'stocktakeId', stocktakeId),
          'articleId': articleId,
          'limit': limit,
          'cursor': cursor,
        }));
    return StocktakeCountPage(counts: liste(name, daten, 'counts', inventurZaehlung), nextCursor: naechsterCursor(name, daten));
  }

  /// Alle Zaehlungen der Abfrage, Seite fuer Seite.
  Stream<StocktakeCount> iterateStocktakeCounts({
    required String stocktakeId,
    String? articleId,
    int? limit,
    String? cursor,
  }) =>
      _seitenweise(Aufrufe.listStocktakeCounts, cursor, (c) async {
        final s = await listStocktakeCounts(stocktakeId: stocktakeId, articleId: articleId, limit: limit, cursor: c);
        return (eintraege: s.counts, nextCursor: s.nextCursor);
      });

  /// Eine Zaehlung. Antwort: die Zaehlung und ihre Position danach (Summe der
  /// Runde in `item.quantity`, ohne Seriennummern). Gezaehlt wird in
  /// `counting`, in `review` nur an Positionen, die zum Nachzaehlen frei sind
  /// (sonst `stocktake_not_open`).
  Future<StocktakeCountResult> recordStocktakeCount(RecordStocktakeCountRequest request) async {
    const name = Aufrufe.recordStocktakeCount;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    zaehlungPruefen(name, p);
    return zaehlungMitPosition(name, await _transport.call(name, p));
  }

  /// Storniert eine Zaehlung mit Grund; die Position wird aus den uebrigen
  /// Zaehlungen neu summiert.
  Future<StocktakeCountResult> voidStocktakeCount(VoidStocktakeCountRequest request) async {
    const name = Aufrufe.voidStocktakeCount;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    stornoPruefen(name, p);
    return zaehlungMitPosition(name, await _transport.call(name, p));
  }

  /// Pruefen: `counting` → `review`, in `review` neu rechnen (nach dem
  /// Nachzaehlen). Die Antwort kommt sofort mit `review.complete: false`; Soll
  /// und Differenz stehen an den Positionen, sobald `complete` `true` ist.
  Future<Stocktake> reviewStocktake(ReviewStocktakeRequest request) async {
    const name = Aufrufe.reviewStocktake;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    return _inventur(name, await _transport.call(name, p));
  }

  /// Nachzaehlen: je genannter Position eine neue Runde; danach zaehlen und
  /// erneut [reviewStocktake]. Solange die Pruefung noch rechnet
  /// (`review.complete: false`), kommt `stocktake_review_running`.
  Future<Stocktake> recountStocktake(RecountStocktakeRequest request) async {
    const name = Aufrufe.recountStocktake;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    if (request.items.isEmpty) throw anfragefehler(name, 'items fehlt oder ist leer');
    for (final (i, x) in request.items.indexed) {
      kennung(name, 'items[$i].articleId', x.articleId);
    }
    grundPruefen(name, request.reason);
    return _inventur(name, await _transport.call(name, p));
  }

  /// Abschliessen (nur aus `review`, sonst `stocktake_not_in_review`; offene
  /// Nachzaehlungen ergeben `stocktake_recount_open`, eine noch rechnende
  /// Pruefung `stocktake_review_running`). Der Server bucht in Teilen weiter;
  /// die Antwort traegt meist `status: 'closing'`. Ein erneuter Aufruf waehrend
  /// `closing` stoesst den Abschluss wieder an.
  Future<CloseStocktakeResult> closeStocktake(CloseStocktakeRequest request) async {
    const name = Aufrufe.closeStocktake;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    final daten = await _transport.call(name, p);
    return CloseStocktakeResult(
      stocktake: _inventur(name, daten),
      warnings: inventurWarnungen(Ort(name, 'warnings'), daten['warnings']),
    );
  }

  /// Abbrechen mit Grund (aus `counting` oder `review`); der Standort ist
  /// danach frei.
  Future<Stocktake> cancelStocktake(CancelStocktakeRequest request) async {
    const name = Aufrufe.cancelStocktake;
    final p = request.toJson();
    _inventurSchreiben(name, p);
    grundPruefen(name, request.reason);
    return _inventur(name, await _transport.call(name, p));
  }

  /// Das Inventurprotokoll (PDF), erst nach dem Abschluss
  /// (`stocktake_not_closed`, auch fuer eine abgebrochene Inventur). Mit dem
  /// Recht `costs` die Fassung mit Werten, sonst die nur mit Mengen. Bis 9 MiB
  /// kommt die Datei selbst ([StocktakePdfFile]), darueber ein signierter
  /// Lese-Link fuer 15 Minuten ([StocktakePdfLink]); die geladene Datei an
  /// `download.sha256` pruefen. Lesen: nach einem Zeitlimit darf der Aufruf
  /// wiederholt werden.
  Future<StocktakePdf> getStocktakePdf(String stocktakeId) async {
    const name = Aufrufe.getStocktakePdf;
    final id = kennung(name, 'stocktakeId', stocktakeId);
    switch (await _transport.callPdfOrData(name, {'stocktakeId': id})) {
      case PdfOrDataFile(:final pdf):
        return StocktakePdfFile(pdf);
      case PdfOrDataPayload(:final data):
        final link = data['download'];
        if (link == null) {
          throw antwortfehler(name, 'Antwort ist weder ein PDF noch ein Lese-Link (data.download fehlt)');
        }
        return StocktakePdfLink(protokollLink(name, link));
    }
  }

  // ---- Hilfen -------------------------------------------------------------------

  /// Was jede schreibende Anfrage vor dem Senden erfuellen muss: ein gueltiger
  /// Schluessel und Ganzzahlen im sicheren Bereich.
  static void _schreiben(String name, Map<String, dynamic> p, {bool schluesselPflicht = true}) {
    pruefeSchluessel(name, p, pflicht: schluesselPflicht);
    pruefeGanzzahlen(name, p);
  }

  static Article _artikel(String name, Map<String, dynamic> daten) => artikel(Ort(name, 'article'), daten['article']);

  static VariantGroup _gruppe(String name, Map<String, dynamic> daten) =>
      variantengruppe(Ort(name, 'variantGroup'), daten['variantGroup']);

  /// [VariantGroupDefaultsInput.clear]: nur die fuenf Vorgaben, keine zugleich
  /// gesetzt und geleert.
  static void _vorgabenLeeren(String name, VariantGroupDefaultsInput? vorgaben) {
    if (vorgaben == null) return;
    final fremd = vorgaben.clear.difference(leerbareVorgaben);
    if (fremd.isNotEmpty) throw anfragefehler(name, 'defaults.clear nennt fremde Felder: ${fremd.join(', ')}');
    final gesetzt = vorgaben.toJson();
    final doppelt = vorgaben.clear.where((f) => gesetzt[f] != null).toList();
    if (doppelt.isNotEmpty) throw anfragefehler(name, 'defaults zugleich gesetzt und geleert: ${doppelt.join(', ')}');
  }

  /// Schreibende Inventur-Anfrage: Schluessel, Ganzzahlen und `stocktakeId`
  /// (ausser beim Anlegen).
  static void _inventurSchreiben(String name, Map<String, dynamic> p) {
    _schreiben(name, p);
    kennung(name, 'stocktakeId', p['stocktakeId']);
  }

  static Stocktake _inventur(String name, Map<String, dynamic> daten) => inventur(Ort(name, 'stocktake'), daten['stocktake']);

  static Reservation _reservierung(String name, Map<String, dynamic> daten) =>
      reservierung(Ort(name, 'reservation'), daten['reservation']);

  /// Ein Zeitpunkt wie `Date.toISOString()` im JS-Zwilling: UTC, Millisekunden,
  /// `Z`. Der Server nimmt nur ISO 8601; Mikrosekunden fallen weg.
  static String? _zeit(DateTime? zeit) =>
      zeit == null ? null : DateTime.fromMillisecondsSinceEpoch(zeit.millisecondsSinceEpoch, isUtc: true).toIso8601String();

  /// Die Abfrage einer Liste: `null` faellt weg; `limit` und `cursor` werden
  /// geprueft, bevor etwas hinausgeht.
  static Map<String, dynamic> _abfrage(String name, Map<String, Object?> felder) {
    final raus = <String, dynamic>{
      for (final e in felder.entries)
        if (e.value != null) e.key: e.value,
    };
    final limit = raus['limit'];
    if (limit is int && (limit < 1 || limit > inventoryListLimitMax)) {
      throw anfragefehler(name, 'limit muss eine ganze Zahl von 1 bis $inventoryListLimitMax sein');
    }
    final cursor = raus['cursor'];
    if (cursor is String) kennung(name, 'cursor', cursor);
    return raus;
  }

  /// Die Werte (`values`): fehlt das Feld, fehlt das Recht `costs`, also `null`, nie `[]`.
  static List<StockValue>? _werte(String name, Map<String, dynamic> daten) =>
      daten['values'] == null ? null : liste(name, daten, 'values', wert);

  static InventoryWebhookWithSecret _mitSecret(String name, Map<String, dynamic> daten) {
    final secret = daten['secret'];
    if (secret is! String || secret.isEmpty) {
      throw antwortfehler(name, 'Antwort enthaelt kein secret; ohne es laesst sich keine Zustellung pruefen');
    }
    return InventoryWebhookWithSecret(webhook: webhook(Ort(name, 'webhook'), daten['webhook']), secret: secret);
  }

  /// Blaettert ueber alle Seiten, Eintrag fuer Eintrag. Derselbe Cursor
  /// zweimal waere eine Endlosschleife: dann endet der Strom mit einem
  /// Antwortfehler. Auch der Startcursor zaehlt: nennt die erste Antwort ihn
  /// wieder, waere es dieselbe Seite.
  static Stream<T> _seitenweise<T>(
    String name,
    String? start,
    Future<({List<T> eintraege, String? nextCursor})> Function(String? cursor) seite,
  ) async* {
    final gesehen = <String>{?start};
    var cursor = start;
    while (true) {
      final s = await seite(cursor);
      for (final e in s.eintraege) {
        yield e;
      }
      final naechster = s.nextCursor;
      if (naechster == null) return;
      if (!gesehen.add(naechster)) throw antwortfehler(name, 'Antwort nennt denselben nextCursor zweimal');
      cursor = naechster;
    }
  }
}
