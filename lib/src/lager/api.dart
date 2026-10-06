/// Die Aufrufe der Lager-API: Artikel, Standorte, Bestand und Bewegungen
/// lesen, Konto-Webhooks verwalten (Backend Stufe 5a), Artikel anlegen und
/// aendern, Bestand buchen und Ware reservieren (Stufe 5b) – Zwilling von
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
/// ob der Aufruf beim Server gewirkt hat: dann denselben Aufruf mit
/// **demselben** `idempotencyKey` noch einmal senden. Er wirkt genau einmal und
/// liefert die gespeicherte Antwort; ein neuer Schluessel buchte ein zweites
/// Mal. Wie im JS-Zwilling traegt ein solcher Fehler hier den Ausgang
/// `rejected`; der Schluessel, nicht der Ausgang, macht die Wiederholung sicher.
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

  // ---- Hilfen -------------------------------------------------------------------

  /// Was jede schreibende Anfrage vor dem Senden erfuellen muss: ein gueltiger
  /// Schluessel und Ganzzahlen im sicheren Bereich.
  static void _schreiben(String name, Map<String, dynamic> p, {bool schluesselPflicht = true}) {
    pruefeSchluessel(name, p, pflicht: schluesselPflicht);
    pruefeGanzzahlen(name, p);
  }

  static Article _artikel(String name, Map<String, dynamic> daten) => artikel(Ort(name, 'article'), daten['article']);

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
