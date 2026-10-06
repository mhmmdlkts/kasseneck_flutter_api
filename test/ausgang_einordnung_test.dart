import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/inventory.dart';
import 'package:kasseneck_api/invoice.dart'
    show CustomerInput, InvoiceApi, InvoiceItemInput, InvoiceTransport, IssueInvoiceRequest, RecordPaymentRequest;
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/v3.dart';

import 'helpers/lager_anfragen.dart';

/// Welcher Aufruf meldet nach dem Senden Ausgang unklar? Zwilling von
/// `test/ausgang-einordnung.test.ts` im npm-Paket 1.5.1.
///
/// Bis 10.4.0 nur die sechs, die signieren, FinanzOnline ansprechen oder Geld
/// bewegen. Ein Wareneingang, eine Reservierung oder `issueInvoice` kam nach
/// einem Zeitlimit als `rejected` zurueck, obwohl der Server gebucht haben
/// konnte; wer dem glaubte und mit einem neuen `idempotencyKey` nachsandte,
/// buchte doppelt. Seit 10.4.1 gilt die Liste des Vertrags
/// (`surface.json`, `unknownOutcomeCalls`) fuer jeden Fehler nach dem Senden:
/// Zeitlimit, Netzfehler, HTTP 5xx, unlesbare Erfolgsantwort und HTML mit
/// Kennzeichen. Lesen und Probelauf bleiben `rejected`.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final List<String> _vertrag =
    (_json('test/fixtures/vertrag/surface.json')['unknownOutcomeCalls'] as List).cast<String>();

final List<Map<String, dynamic>> _lagerFaelle =
    (_json('test/fixtures/vertrag/v3/antworten/lager.json')['cases'] as List).cast<Map<String, dynamic>>();

/// Die Parameter eines Vertragsfalls, tief kopiert.
Map<String, dynamic> _params(String fall) =>
    jsonDecode(jsonEncode(_lagerFaelle.firstWhere((c) => c['name'] == fall)['params'])) as Map<String, dynamic>;

/// Die Aufrufe dieses Pakets **ohne** Wirkung, wie `CALLS_WITHOUT_EFFECT` in
/// npm. Hier von Hand: ein neuer Aufruf in [Aufrufe.alle] muss bewusst
/// eingeordnet werden, sonst wird der Waechter rot.
const Set<String> _lesen = {
  'downloadDailyReport',
  'downloadReport',
  'generateFullReceiptId', // leitet nur einen Link-Schluessel ab, schreibt nichts
  'getArticle',
  'getCustomer',
  'getFirstReceiptDate',
  'getInvoice',
  'getInvoicePdf',
  'getInvoiceSetupStatus',
  'getInvoiceXml',
  'getKasseSettings',
  'getPrintJob',
  'getReceipt',
  'getReportV2',
  'getReservation',
  'getStock',
  'hobexGetStatus',
  'listArticles',
  'listBrands',
  'listInvoices',
  'listLocations',
  'listMyArticleGroups',
  'listMyArticles',
  'listMyCashregisters',
  'listMyPrinters',
  'listMyReceipts',
  'listMyStock',
  'listMyStockLocations',
  'listMyTipRecipients',
  'listRegisterSessionsForDevice',
  'listRegisterUsersForDevice',
  'listReservations',
  'listStock',
  'listStockMovements',
  'listWebhookDeliveries',
  'listWebhooks',
  'lookupArticleByCode',
  'searchCustomers',
};

/// Legen etwas an, das ohne die verlorene Antwort niemand erreicht und das
/// verfaellt, und buchen nichts: die Sitzung der Kassen-Anmeldung und der
/// Stripe-Zahlungslink. Mit `unknown` saehe die Kasse beim Zeitlimit der
/// Anmeldung „kann gebucht sein“.
const Set<String> _wiederholbar = {
  'createPaymentLinkStripe',
  'endRegisterSession',
  'registerPinLogin',
  'registerUserLogin',
  'renewRegisterSession',
};

const _kennzeichen = {'kasseneck-api-version': 'v3'};
const _frist = Duration(milliseconds: 20);

/// Eine Art, nach dem Senden zu scheitern.
class _Art {
  const _Art(this.name, this.grund, this.antwort);
  final String name;

  /// `reason` des [KasseneckHttpError]; `null` bei HTML (dort entscheidet die Wirkung).
  final String? grund;

  /// Liefert die Antwort oder wirft; `null` heisst: antwortet nie.
  final Future<http.Response>? Function() antwort;
}

http.Response _mitKennzeichen(String rumpf, {int status = 200, String typ = 'application/json'}) =>
    http.Response.bytes(utf8.encode(rumpf), status, headers: {'content-type': typ, ..._kennzeichen});

final List<_Art> _arten = [
  _Art('Zeitlimit', KasseneckHttpError.reasonTimeout, () => null),
  _Art('Netzfehler', KasseneckHttpError.reasonNetwork, () => Future.error(const SocketException('weg'))),
  _Art('HTTP 503', 'server-error', () async => _mitKennzeichen('{"status":"error"}', status: 503)),
  _Art('HTTP 500 ohne Kennzeichen', 'server-error',
      () async => http.Response('<html/>', 500, headers: {'content-type': 'text/html'})),
  _Art('leerer Rumpf', 'empty-body', () async => _mitKennzeichen('')),
  _Art('kein JSON', 'not-json', () async => _mitKennzeichen('kein json')),
  _Art('ohne Statusfeld', 'missing-status', () async => _mitKennzeichen('{"data":{}}')),
  _Art('data kein Objekt', 'data-not-object', () async => _mitKennzeichen('{"status":"success","data":[1]}')),
  _Art('HTML mit Kennzeichen', null, () async => _mitKennzeichen('<html></html>', typ: 'text/html; charset=utf-8')),
];

/// Ein Netz, das jede Anfrage festhaelt und nach [art] scheitert.
({http.Client client, List<http.Request> anfragen}) _netz(_Art art) {
  final anfragen = <http.Request>[];
  final client = MockClient((request) {
    anfragen.add(request);
    return art.antwort() ?? Completer<http.Response>().future;
  });
  return (client: client, anfragen: anfragen);
}

/// Ein Aufruf ueber die echte Huelle.
class _Fall {
  const _Fall(this.titel, this.name, this.los, {required this.wirkung, this.probelauf = false});
  final String titel;

  /// Der Name am Draht (ein Probelauf traegt den des echten Aufrufs).
  final String name;
  final bool wirkung;
  final bool probelauf;
  final Future<Object?> Function(http.Client client) los;
}

InventoryClient _lager(http.Client c) => InventoryClient(apiKey: _apiKey, httpClient: c, timeout: _frist);
InvoiceApi _rechnung(http.Client c) => InvoiceApi(apiKey: _apiKey, httpClient: c, timeout: _frist);

const _ausstellen = IssueInvoiceRequest(
  idempotencyKey: 'bestellung-4711',
  customerId: 'k1',
  taxScheme: 'normal',
  priceMode: 'net',
  serviceStart: '2026-09-15',
  items: [InvoiceItemInput(description: 'Beratung', quantity: 2, unitPriceCents: 5000, vatRate: 20)],
);

final List<_Fall> _faelle = [
  // Lager schreiben, Webhooks und Reservierung: mit Wirkung.
  for (final (aufruf, fall) in [
    ('receiveGoods', 'receive_goods'),
    ('createArticle', 'create_article'),
    ('transferStock', 'transfer_stock'),
    ('recordStockLoss', 'record_stock_loss'),
    ('createReservation', 'create_reservation'),
    ('extendReservation', 'extend_reservation'),
    ('releaseReservation', 'release_reservation'),
  ])
    _Fall(aufruf, aufruf, (c) => schreibAufruf(_lager(c), aufruf, _params(fall)), wirkung: true),
  _Fall('createWebhook', 'createWebhook', (c) {
    final p = _params('create_webhook');
    return _lager(c).createWebhook(url: p['url'] as String, events: (p['events'] as List).cast<String>());
  }, wirkung: true),
  // Rechnung: mit Wirkung.
  _Fall('issueInvoice', 'issueInvoice', (c) => _rechnung(c).issueInvoice(_ausstellen), wirkung: true),
  _Fall('cancelInvoice', 'cancelInvoice',
      (c) => _rechnung(c).cancelInvoice(idempotencyKey: 's1', invoiceId: 'inv1', reason: 'cancellation'),
      wirkung: true),
  _Fall('recordInvoicePayment', 'recordInvoicePayment',
      (c) => _rechnung(c).recordInvoicePayment(
          const RecordPaymentRequest(idempotencyKey: 'z1', invoiceId: 'inv1', method: 'card', onSite: true)),
      wirkung: true),
  _Fall('createCustomer', 'createCustomer',
      (c) => _rechnung(c).createCustomer(const CustomerInput(type: 'company', name: 'Max Hollerer GmbH', country: 'AT'),
          idempotencyKey: 'kunde-1'),
      wirkung: true),
  _Fall('updateCustomer', 'updateCustomer', (c) => _rechnung(c).updateCustomer('k1', {'city': 'Graz'}), wirkung: true),
  // Lesen: abgelehnt.
  _Fall('getStock', 'getStock', (c) => _lager(c).getStock('roggenbrot'), wirkung: false),
  _Fall('getReservation', 'getReservation', (c) => _lager(c).getReservation('auto43'), wirkung: false),
  _Fall('getInvoice', 'getInvoice', (c) => _rechnung(c).getInvoice(invoiceId: 'inv1'), wirkung: false),
  _Fall('listInvoices', 'listInvoices', (c) => _rechnung(c).listInvoices(limit: 2), wirkung: false),
  // Probelauf unter dem Namen des echten Aufrufs: abgelehnt.
  _Fall('previewGoodsReceipt', 'receiveGoods', (c) => schreibAufruf(_lager(c), 'receiveGoods', _params('receive_goods_dry_run')),
      wirkung: false, probelauf: true),
  _Fall('previewInvoice', 'issueInvoice', (c) => _rechnung(c).previewInvoice(_ausstellen), wirkung: false, probelauf: true),
];

Matcher _erwartet(_Art art, {required bool wirkung}) {
  final ausgang = wirkung ? ErrorOutcome.unknown : ErrorOutcome.rejected;
  if (art.grund == null) {
    return wirkung
        ? isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', 'not-json')
            .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)
        : isA<KasseneckApiError>()
            .having((e) => e.code, 'code', 'route_missing')
            .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected);
  }
  return isA<KasseneckHttpError>()
      .having((e) => e.reason, 'reason', art.grund)
      .having((e) => e.outcome, 'outcome', ausgang);
}

Map<String, dynamic> _gesendet(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

void main() {
  group('Einordnung', () {
    test('unknownOutcomeCalls ist die Liste des Vertrags, gleich und sortiert', () {
      expect(_vertrag, isNotEmpty);
      expect(_vertrag, [..._vertrag]..sort(), reason: 'surface.json fuehrt die Liste sortiert');
      expect(_vertrag.toSet().length, _vertrag.length, reason: 'ohne Doppel');
      expect(unknownOutcomeCalls.toList(), _vertrag);
    });

    test('jeder Aufruf dieses Pakets ist genau einmal eingeordnet, ohne Leichen', () {
      for (final call in Aufrufe.alle) {
        final treffer = [
          if (unknownOutcomeCalls.contains(call)) 'mit Wirkung',
          if (_lesen.contains(call)) 'lesen',
          if (_wiederholbar.contains(call)) 'wiederholbar',
        ];
        expect(treffer, hasLength(1), reason: '$call: $treffer');
      }
      for (final call in {..._lesen, ..._wiederholbar}) {
        expect(Aufrufe.alle, contains(call), reason: '$call steht in der Einordnung, aber nicht in Aufrufe.alle');
      }
    });

    test('Probelauf nur fuer Aufrufe, die das Backend mit dryRun als Probelauf fuehrt', () {
      expect(dryRunCalls, {'issueInvoice', 'receiveGoods'});
      expect(unknownOutcomeCalls, containsAll(dryRunCalls));
    });
  });

  for (final art in _arten) {
    group(art.name, () {
      test('mit Wirkung unknown, Lesen und Probelauf rejected, ueber die echten Huellen', () async {
        for (final fall in _faelle) {
          final netz = _netz(art);
          await expectLater(fall.los(netz.client), throwsA(_erwartet(art, wirkung: fall.wirkung)), reason: fall.titel);
          // Die Anfrage ging wirklich hinaus, unter dem Namen am Draht, und
          // `dryRun` steht genau beim Probelauf drin.
          expect(netz.anfragen, hasLength(1), reason: fall.titel);
          expect(netz.anfragen.single.url.path, endsWith('/${fall.name}'), reason: fall.titel);
          expect(_gesendet(netz.anfragen.single)['dryRun'], fall.probelauf ? isTrue : isNull, reason: fall.titel);
        }
      });

      test('dryRun senkt nur, wenn genau true hinausgeht, und nur bei receiveGoods und issueInvoice', () async {
        final lagerWeg = InventoryTransport(apiKey: _apiKey, httpClient: _netz(art).client, timeout: _frist);
        final rechnungWeg = InvoiceTransport(apiKey: _apiKey, httpClient: _netz(art).client, timeout: _frist);
        final wege = <String, Future<Object?> Function(Map<String, dynamic> params)>{
          'receiveGoods': (p) => lagerWeg.call('receiveGoods', p),
          'issueInvoice': (p) => rechnungWeg.call('issueInvoice', p),
        };
        for (final MapEntry(key: name, value: los) in wege.entries) {
          await expectLater(los({'dryRun': true}), throwsA(_erwartet(art, wirkung: false)), reason: '$name dryRun true');
          for (final wert in <Object?>[false, 'true', 1, null]) {
            await expectLater(los({'dryRun': ?wert}), throwsA(_erwartet(art, wirkung: true)), reason: '$name dryRun $wert');
          }
        }
        // Ein anderer Aufruf mit Wirkung bleibt unklar, auch mit dryRun: true;
        // sein Handler kennt das Feld nicht, der Vorgang waere echt.
        await expectLater(lagerWeg.call('recordStockLoss', {'dryRun': true}), throwsA(_erwartet(art, wirkung: true)));
        await expectLater(rechnungWeg.call('cancelInvoice', {'dryRun': true}), throwsA(_erwartet(art, wirkung: true)));
      });
    });
  }

  test('v3Post: dryRun zaehlt nur fuer dryRunCalls, ein Beleg bleibt unklar', () async {
    Future<Object> fehler(String name, {required bool dryRun}) async {
      try {
        await v3Post(
          MockClient((_) async => throw const SocketException('weg')),
          functionName: name,
          basis: kPublicBaseUrl,
          name: name,
          headers: const {'Content-Type': 'application/json'},
          kasseneck: V3Headers(name),
          body: '{}',
          timeout: const Duration(seconds: 5),
          dryRun: dryRun,
        );
      } on Object catch (e) {
        return e;
      }
      fail('$name: kein Fehler');
    }

    final unklar = isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.unknown);
    final abgelehnt = isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.rejected);
    expect(await fehler('createReceipt', dryRun: true), unklar);
    expect(await fehler('setMyKasseSettings', dryRun: true), unklar);
    expect(await fehler('receiveGoods', dryRun: true), abgelehnt);
    expect(await fehler('receiveGoods', dryRun: false), unklar);
    expect(await fehler('getStock', dryRun: false), abgelehnt);
    expect(outcomeAfterSending('financeWebService/status_cashbox'), ErrorOutcome.unknown);
    expect(unreadableOutcome('issueInvoice', dryRun: true), ErrorOutcome.rejected);
    expect(unreadableOutcome('cancelInvoice', dryRun: true), ErrorOutcome.unknown);
  });

  test('issueInvoice mit dryRun: true geht gar nicht erst hinaus', () async {
    final netz = _netz(_arten[1]);
    final probe = IssueInvoiceRequest(
      idempotencyKey: _ausstellen.idempotencyKey,
      customerId: _ausstellen.customerId,
      taxScheme: _ausstellen.taxScheme,
      priceMode: _ausstellen.priceMode,
      serviceStart: _ausstellen.serviceStart,
      items: _ausstellen.items,
      dryRun: true,
    );
    await expectLater(_rechnung(netz.client).issueInvoice(probe),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')));
    expect(netz.anfragen, isEmpty);
  });
}
