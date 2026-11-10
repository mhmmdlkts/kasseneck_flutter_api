import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/invoice.dart';

/// Pfand an Rechnungs- und Gutschriftspositionen (`items[].deposit`),
/// Zwilling von `test/rechnung-client.test.ts` und `rechnung-vertrag.test.ts`
/// im npm-Paket (1.36.0). GTINs sind erfunden und pruefziffernrichtig.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _gut = _json('test/fixtures/vertrag/invoice-api-examples/issue-invoice-deposit.json');
final _fehlerfall = _json('test/fixtures/vertrag/invoice-api-examples/issue-error-deposit.json');

const _rechnung = {
  'id': 'inv1',
  'number': '2026-0042',
  'docType': 'invoice',
  'status': 'final',
  'invoiceDate': '2026-11-10',
  'dueDate': '2026-11-24',
  'customerId': 'k1',
  'totals': {
    'netCents': 6000,
    'vatCents': 1080,
    'grossCents': 7080,
    'byRate': [
      {'rate': 20, 'netCents': 6000, 'vatCents': 1080},
    ],
  },
  'einvoice': {'level': 'full', 'formats': ['UBL'], 'missing': []},
  'statusUrl': 'https://mein.kasseneck.at/r/abc',
  'statusPassword': 'XK4P',
};

({InvoiceApi api, List<http.Request> log}) _apiMit(Object antwort) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response.bytes(utf8.encode(jsonEncode(antwort)), 200,
        headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
  });
  return (api: InvoiceApi(apiKey: _apiKey, httpClient: mock), log: log);
}

Map<String, dynamic> _params(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

Map<String, dynamic> _erfolg(Object? daten) => {'status': 'success', 'message': '', 'data': daten};

void main() {
  test('issueInvoice nimmt items[].deposit an und sendet es unveraendert', () async {
    final (:api, :log) = _apiMit(_erfolg({'invoice': _rechnung, 'replayed': false}));
    final anfrage = IssueInvoiceRequest.fromJson(_gut['request'] as Map<String, dynamic>);
    final pfand = anfrage.items.whereType<IssueInvoiceItemInput>().where((p) => p.deposit != null).toList();
    expect(pfand, hasLength(2), reason: 'das Beispiel enthaelt zwei Pfandzeilen');
    expect(pfand.first.deposit!.depositFor, 0);
    expect(pfand.first.deposit!.gtin, '9012345000011');
    expect(pfand.last.deposit!.ownFilling, isTrue);
    await api.issueInvoice(anfrage);
    expect(_params(log.single), _gut['request']);
  });

  test('createCreditNote nimmt items[].deposit an', () async {
    final (:api, :log) = _apiMit(_erfolg({'creditNote': _rechnung, 'replayed': false, 'remainingCents': 0}));
    final anfrage = CreditNoteRequest(
      idempotencyKey: 'gs-1',
      invoiceId: 'inv1',
      reason: 'return',
      items: const [
        CreditNoteItemInput(
          description: 'Pfand Dose',
          quantity: 12,
          unitPriceCents: 25,
          vatRate: 0,
          deposit: InvoiceItemDepositInput(depositTypeId: 'pf_einweg_dose', depositFor: 0, gtin: '9012345000011'),
        ),
      ],
    );
    await api.createCreditNote(anfrage);
    final item = (_params(log.single)['items'] as List).single as Map;
    expect(item['deposit'], {'depositTypeId': 'pf_einweg_dose', 'depositFor': 0, 'gtin': '9012345000011'});
    final zurueck = CreditNoteRequest.fromJson(_params(log.single));
    expect((zurueck.items.single as CreditNoteItemInput).deposit!.depositTypeId, 'pf_einweg_dose');
  });

  test('ohne Pfand geht kein deposit hinaus, auch nicht als null', () {
    const p = IssueInvoiceItemInput(description: 'Brot', quantity: 1, unitPriceCents: 450, vatRate: 10);
    expect(p.toJson().containsKey('deposit'), isFalse);
    const g = CreditNoteItemInput(description: 'Brot', quantity: 1, unitPriceCents: 450, vatRate: 10);
    expect(g.toJson().containsKey('deposit'), isFalse);
    expect(const InvoiceItemInput(description: 'Brot', quantity: 1, unitPriceCents: 450, vatRate: 10).toJson().containsKey('deposit'),
        isFalse, reason: 'deposit gehoert nur an Rechnung und Gutschrift');
    const d = InvoiceItemDepositInput(depositTypeId: 'x', depositFor: 1);
    expect(d.toJson(), {'depositTypeId': 'x', 'depositFor': 1});
  });

  test('das Fehlerbeispiel: ungueltige Pfandfelder gehen unveraendert hinaus, der Server meldet die Feldpfade', () async {
    expect(_fehlerfall['endpoint'], 'issueInvoice');
    final expected = _fehlerfall['expected'] as Map<String, dynamic>;
    expect(expected['code'], 'validation');
    expect(expected['fields'],
        ['items[1].deposit.depositTypeId', 'items[1].deposit.depositFor', 'items[1].deposit.gtin']);
    final (:api, :log) = _apiMit({
      'status': 'error',
      'message': 'Ungueltig',
      'code': 'validation',
      'data': {'code': 'validation', 'fields': expected['fields']},
    });
    final e = await api
        .issueInvoice(IssueInvoiceRequest.fromJson(_fehlerfall['request'] as Map<String, dynamic>))
        .then<Object?>((_) => null, onError: (Object x) => x);
    expect(e, isA<KasseneckApiError>());
    expect(_params(log.single), _fehlerfall['request']);
  });

  test('Pfandfehler des Servers kommen als bekannte Rechnungs-Codes an', () async {
    for (final code in [
      'deposit_not_enabled',
      'deposit_type_not_found',
      'deposit_set_by_server',
      'invalid_deposit_quantity',
      'invalid_deposit',
    ]) {
      final (:api, :log) = _apiMit({
        'status': 'error',
        'message': 'Pfand',
        'code': code,
        'data': {'code': code, 'index': 1},
      });
      final e = await api
          .issueInvoice(IssueInvoiceRequest.fromJson(_gut['request'] as Map<String, dynamic>))
          .then<Object?>((_) => null, onError: (Object x) => x);
      expect(e, isA<KasseneckApiError>(), reason: code);
      expect(invoiceErrorCode(e!), code);
      expect((e as KasseneckApiError).details['index'], 1);
    }
  });

  test('getInvoice liest deposit an Pfandzeilen, ohne Pfand bleibt die Position unveraendert', () async {
    const ware = {
      'description': 'Mineralwasser 12er',
      'subtitle': '',
      'quantity': 1,
      'unit': 'piece',
      'kind': 'goods',
      'unitPriceCents': 1200,
      'vatRate': 20,
      'discountPct': 0,
    };
    final pfand = {
      ...ware,
      'description': 'Pfand Einweg',
      'quantity': 12,
      'unitPriceCents': 25,
      'vatRate': 0,
      'deposit': {'depositTypeId': 'pf_einweg_dose', 'depositKind': 'single_use', 'depositFor': 0, 'gtin': '9012345000011'},
    };
    final eigen = {
      ...pfand,
      'description': 'Pfand Kiste',
      'unitPriceCents': 300,
      'deposit': {'depositTypeId': 'pf_mehrweg_kiste', 'depositKind': 'reusable', 'depositFor': 0, 'ownFilling': true},
    };
    final (:api, log: _) = _apiMit(_erfolg({
      'invoice': {..._rechnung, 'items': [ware, pfand, eigen], 'customer': null, 'payments': <Object>[]},
    }));
    final gelesen = await api.getInvoice(invoiceId: 'inv1');
    expect(gelesen.items![0].deposit, isNull);
    expect(gelesen.items![1].deposit!.depositKind, 'single_use');
    expect(gelesen.items![1].deposit!.gtin, '9012345000011');
    expect(gelesen.items![1].deposit!.ownFilling, isNull);
    expect(gelesen.items![2].deposit!.ownFilling, isTrue);
    expect(gelesen.items![2].deposit!.depositFor, 0);
  });

  test('eine unlesbare Pfandangabe an der Position ist ein Antwortfehler', () async {
    final kaputt = {
      'description': 'Pfand', 'subtitle': '', 'quantity': 1, 'unit': 'piece', 'kind': 'goods',
      'unitPriceCents': 25, 'vatRate': 0, 'discountPct': 0,
      'deposit': {'depositTypeId': 'x'},
    };
    final (:api, log: _) = _apiMit(_erfolg({
      'invoice': {..._rechnung, 'items': [kaputt], 'customer': null, 'payments': <Object>[]},
    }));
    await expectLater(api.getInvoice(invoiceId: 'inv1'), throwsA(isA<KasseneckValidationError>()));
  });

  test('der Vertrag nennt das Feld deposit mit denselben Grenzen wie das Modell', () {
    final schema = _json('test/fixtures/vertrag/invoice-api.schema.json');
    final text = jsonEncode(schema);
    expect(text, contains('"depositTypeId"'));
    expect(text, contains('"depositFor"'));
    expect(text, contains('^[0-9]{8,14}\$'));
    expect(InvoiceItem.fields, contains('deposit'));
  });
}
