import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/rechnung.dart';
import 'package:kasseneck_api/src/aufrufe.dart';

/// Der Rechnungs-Client gegen den Vertrag des JS-Zwillings.
///
/// Zwei Arten von Prüfung: die Listen des Vertrags (Codes, Gründe,
/// Einrichtungspunkte …) werden in **beide** Richtungen verglichen — ein Wert zu
/// viel ist hier ebenso ein Fehler wie einer zu wenig. Und die Beispielanfragen
/// des Vertrags laufen durch die Modelle und müssen unverändert beim Server
/// ankommen.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) =>
    jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _rechnung = {
  'id': 'inv1',
  'number': '2026-0042',
  'docType': 'RE',
  'status': 'final',
  'invoiceDate': '2026-09-15',
  'dueDate': '2026-09-29',
  'customerId': 'k1',
  'totals': {
    'netCents': 10000,
    'vatCents': 2000,
    'grossCents': 12000,
    'byRate': [
      {'rate': 20, 'netCents': 10000, 'vatCents': 2000},
    ],
  },
  'einvoice': {'level': 'full', 'formats': ['UBL', 'Factur-X'], 'missing': []},
  'statusUrl': 'https://mein.kasseneck.at/r/abc',
  'statusPassword': 'XK4P',
  'metadata': {'bestellung': '4711'},
};

Map<String, dynamic> _erfolg(Object? daten) => {'status': 'success', 'message': '', 'data': daten};
Map<String, dynamic> _fehler(String meldung, String code, [Map<String, dynamic> daten = const {}]) =>
    {'status': 'error', 'message': meldung, 'code': code, 'data': {'code': code, ...daten}};

({RechnungApi api, List<http.Request> log}) _apiMit(List<Object> antworten, {Duration? timeout}) {
  final log = <http.Request>[];
  var i = 0;
  final mock = MockClient((request) async {
    log.add(request);
    final antwort = antworten[i < antworten.length ? i : antworten.length - 1];
    i += 1;
    if (antwort is http.Response) return antwort;
    if (antwort is Future<http.Response> Function()) return antwort();
    return http.Response.bytes(utf8.encode(jsonEncode(antwort)), 200, headers: {'content-type': 'application/json'});
  });
  return (api: RechnungApi(apiKey: _apiKey, httpClient: mock, timeout: timeout), log: log);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

void main() {
  group('Vertrag', () {
    final vertrag = _json('test/fixtures/vertrag/oberflaeche.json');
    final listen = vertrag['rechnung'] as Map<String, dynamic>;
    final hier = <String, List<Object>>{
      'rechnungAufrufe': rechnungAufrufe,
      'invoiceErrorCodes': invoiceErrorCodes,
      'creditNoteReasons': creditNoteReasons,
      'taxSchemes': taxSchemes,
      'priceModes': priceModes,
      'vatRates': vatRates,
      'customerTypes': customerTypes,
      'invoiceListStatus': invoiceListStatus,
      'docTypes': docTypes,
      'einvoiceFormats': einvoiceFormats,
      'invoiceSetupRequirements': invoiceSetupRequirements,
      'invoiceLanguages': invoiceLanguages,
      'invoiceUnits': invoiceUnits,
    };

    test('jede Liste des Vertrags gibt es hier, und keine mehr', () {
      expect(hier.keys.toSet(), listen.keys.toSet());
    });

    test('jede Liste stimmt Wert für Wert und in der Reihenfolge', () {
      for (final e in hier.entries) {
        expect(e.value, listen[e.key], reason: 'rechnung.${e.key}');
      }
    });

    test('jeder Rechnungs-Aufruf steht in Aufrufe.alle', () {
      for (final name in rechnungAufrufe) {
        expect(Aufrufe.alle, contains(name));
      }
    });

    test('dieselbe Paketversion wie die Anheftung', () {
      final schema = _json('test/fixtures/vertrag/rechnung-api.schema.json');
      expect(schema['paket'], vertrag['version']);
      expect((schema['aufrufe'] as Map).keys.toList(), rechnungAufrufe);
      expect(schema['codes'], invoiceErrorCodes);
    });
  });

  group('Beispielanfragen des Vertrags', () {
    final ordner = Directory('test/fixtures/vertrag/rechnung-api-beispiele');
    final gute = ordner
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
        .where((b) => (b['erwartet'] as Map)['ok'] == true)
        .toList();

    test('es gibt gültige Beispiele für die Modelle', () {
      expect(gute.map((b) => b['aufruf']).toSet(), containsAll(['issueInvoice', 'createCustomer', 'createCreditNote']));
    });

    test('jede gültige Anfrage geht unverändert an den Server', () async {
      for (final b in gute) {
        final aufruf = b['aufruf'] as String;
        final anfrage = b['anfrage'] as Map<String, dynamic>;
        final antwort = _erfolg({
          'invoice': _rechnung,
          'creditNote': _rechnung,
          'customer': {'id': 'k1', 'type': 'company', 'name': 'X', 'country': 'AT'},
          'replayed': false,
          'remainingCents': 0,
          'ready': true,
          'environment': 'live',
          'missing': [],
          'brands': [],
        });
        final (:api, :log) = _apiMit([antwort]);
        switch (aufruf) {
          case 'issueInvoice':
            await api.issueInvoice(IssueInvoiceRequest.fromJson(anfrage));
          case 'createCreditNote':
            await api.createCreditNote(CreditNoteRequest.fromJson(anfrage));
          case 'createCustomer':
            await api.createCustomer(CustomerInput.fromJson(anfrage['customer'] as Map<String, dynamic>));
          case 'getInvoiceSetupStatus':
            await api.getInvoiceSetupStatus();
          case 'listBrands':
            await api.listBrands();
          default:
            fail('Beispiel für $aufruf ohne Testweg');
        }
        expect(log.single.url.toString(), 'https://api.kasseneck.at/v1/$aufruf');
        expect(_params(log.single), anfrage, reason: '${b['beschreibung']}');
      }
    });
  });

  group('Aufrufe', () {
    test('issueInvoice: Bearer ohne Kassen-Token, Ergebnis gelesen', () async {
      final (:api, :log) = _apiMit([_erfolg({'invoice': _rechnung, 'replayed': true})]);
      final ergebnis = await api.issueInvoice(const IssueInvoiceRequest(
        idempotencyKey: 'bestellung-4711',
        customerId: 'k1',
        taxScheme: 'normal',
        priceMode: 'net',
        serviceStart: '2026-09-15',
        items: [InvoiceItemInput(description: 'Beratung', quantity: 2, unitPriceCents: 5000, vatRate: 20)],
      ));
      expect(log.single.headers['Authorization'], 'Bearer $_apiKey');
      expect(log.single.headers.containsKey('cashregister-token'), isFalse);
      expect(ergebnis.replayed, isTrue);
      expect(ergebnis.invoice.number, '2026-0042');
      expect(ergebnis.invoice.totals.grossCents, 12000);
      expect(ergebnis.invoice.totals.byRate.single.rate, 20);
      expect(ergebnis.invoice.metadata, {'bestellung': '4711'});
      expect(ergebnis.invoice.einvoiceLevel, 'full');
    });

    test('eine Antwort ohne die zugesagte Rechnung ist ein Antwortfehler', () async {
      final (:api, log: _) = _apiMit([_erfolg({'replayed': false})]);
      await expectLater(
        api.issueInvoice(const IssueInvoiceRequest(
            idempotencyKey: 'k', taxScheme: 'normal', priceMode: 'net', serviceStart: '2026-09-15', items: [])),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
      );
    });

    test('getInvoice: Detailfelder gelesen, genau eine Kennung verlangt', () async {
      final detail = {
        ..._rechnung,
        'items': [
          {'description': 'Beratung', 'subtitle': '', 'quantity': 2, 'unit': 'Std', 'unitPriceCents': 5000, 'vatRate': 20, 'discountPct': 0},
        ],
        'paidCents': 0,
        'openCents': 12000,
        'overdue': false,
        'creditNotes': [
          {'id': 'g1', 'number': '2026-0043', 'grossCents': 2400},
        ],
      };
      final (:api, :log) = _apiMit([_erfolg({'invoice': detail})]);
      final r = await api.getInvoice(number: '2026-0042');
      expect(_params(log.single), {'number': '2026-0042'});
      expect(r.items!.single.unitPriceCents, 5000);
      expect(r.openCents, 12000);
      expect(r.creditNotes!.single.grossCents, 2400);
      expect(() => api.getInvoice(), throwsA(isA<KasseneckValidationError>()));
      expect(() => api.getInvoice(invoiceId: 'a', number: 'b'), throwsA(isA<KasseneckValidationError>()));
    });

    test('cancelInvoice und createCreditNote lesen ihre Ergebnisse', () async {
      final (:api, log: _) = _apiMit([
        _erfolg({'creditNote': {..._rechnung, 'docType': 'GU'}, 'original': {'id': 'inv1', 'status': 'cancelled'}, 'originalPaidCents': 500, 'replayed': false}),
        _erfolg({'creditNote': {..._rechnung, 'docType': 'GU'}, 'remainingCents': 9600, 'replayed': false}),
      ]);
      final storno = await api.cancelInvoice(idempotencyKey: 's1', invoiceId: 'inv1', reason: 'cancellation');
      expect((storno.originalId, storno.originalStatus, storno.originalPaidCents), ('inv1', 'cancelled', 500));
      final gutschrift = await api.createCreditNote(const CreditNoteRequest(
        idempotencyKey: 'g1',
        invoiceId: 'inv1',
        reason: 'price_reduction',
        items: [InvoiceItemInput(description: 'Nachlass', quantity: 1, unitPriceCents: 2000, vatRate: 20)],
      ));
      expect(gutschrift.remainingCents, 9600);
      expect(gutschrift.creditNote.docType, 'GU');
    });

    test('Kunden: anlegen, suchen, ändern', () async {
      final kunde = {'id': 'k1', 'type': 'company', 'name': 'Café Muster GmbH', 'country': 'AT', 'vatId': 'ATU12345675', 'externalId': 'shop-4711'};
      final (:api, :log) = _apiMit([
        _erfolg({'customer': kunde}),
        _erfolg({'customers': [kunde], 'nextCursor': 'c2'}),
        _erfolg({'customer': {...kunde, 'city': 'Graz'}}),
      ]);
      final angelegt = await api.createCustomer(
        const CustomerInput(type: 'company', name: 'Café Muster GmbH', country: 'AT', externalId: 'shop-4711'),
        idempotencyKey: 'kunde-1',
      );
      expect(_params(log[0]), {
        'customer': {'type': 'company', 'name': 'Café Muster GmbH', 'country': 'AT', 'externalId': 'shop-4711'},
        'idempotencyKey': 'kunde-1',
      });
      expect(angelegt.vatId, 'ATU12345675');
      final seite = await api.searchCustomers(name: 'cafe', limit: 10);
      expect(_params(log[1]), {'name': 'cafe', 'limit': 10});
      expect((seite.customers.single.id, seite.nextCursor), ('k1', 'c2'));
      final geaendert = await api.updateCustomer('k1', {'city': 'Graz'});
      expect(_params(log[2]), {'customerId': 'k1', 'customer': {'city': 'Graz'}});
      expect(geaendert.city, 'Graz');
    });

    test('listInvoices schickt nur gesetzte Filter', () async {
      final (:api, :log) = _apiMit([_erfolg({'invoices': [_rechnung], 'nextCursor': null})]);
      final seite = await api.listInvoices(status: 'open', limit: 2);
      expect(_params(log.single), {'status': 'open', 'limit': 2});
      expect((seite.invoices.single.id, seite.nextCursor), ('inv1', null));
    });

    test('getInvoicePdf liefert die Bytes, ein Fehler kommt als Fachfehler', () async {
      final pdf = utf8.encode('%PDF-1.7\n…');
      final (:api, :log) = _apiMit([
        http.Response.bytes(pdf, 200, headers: {'content-type': 'application/pdf'}),
        _fehler('Rechnung nicht gefunden.', 'invoice_not_found'),
      ]);
      final bytes = await api.getInvoicePdf('inv1');
      expect(utf8.decode(bytes.sublist(0, 4)), '%PDF');
      expect(_params(log.first), {'invoiceId': 'inv1'});
      await expectLater(api.getInvoicePdf('x'), throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invoice_not_found')));
    });

    test('getInvoiceXml: Text aus dem Umschlag, Standardformat ubl', () async {
      final (:api, :log) = _apiMit([_erfolg({'xml': '<Invoice/>', 'format': 'ubl', 'filename': 'rechnung-2026-0042.xml'})]);
      expect(await api.getInvoiceXml('inv1'), '<Invoice/>');
      expect(_params(log.single), {'invoiceId': 'inv1', 'format': 'ubl'});
    });

    test('getInvoiceSetupStatus: ohne Parameter, Lücken gelesen', () async {
      final (:api, :log) = _apiMit([
        _erfolg({
          'ready': false,
          'environment': 'test',
          'missing': [
            {'requirement': 'bank_account', 'message': 'IBAN fehlt.'},
          ],
        }),
      ]);
      final stand = await api.getInvoiceSetupStatus();
      expect(_params(log.single), <String, dynamic>{});
      expect((stand.ready, stand.environment, stand.missing.single.requirement), (false, 'test', 'bank_account'));
    });
  });

  group('Fehler', () {
    test('Code und Details: am Code entscheiden, Nutzlast bleibt lesbar', () async {
      final (:api, log: _) = _apiMit([
        _fehler('Gutschrift übersteigt die Rechnung.', 'credit_exceeds_invoice', {'remainingCents': {'total': 6000}}),
        _fehler('Bitte Eingaben prüfen.', 'validation', {
          'errors': [
            {'field': 'items[0].vatRate', 'message': 'Bei diesem Steuerschema ist der USt-Satz 0.'},
          ],
        }),
        _fehler('Die Einrichtung ist unvollständig.', 'invoice_setup_incomplete', {
          'missing': [
            {'requirement': 'number_format', 'message': 'Nummernformat fehlt.'},
          ],
        }),
        {'status': 'error', 'message': 'Zu viele Anfragen.', 'code': 'rate_limited'},
      ]);
      const gutschrift = CreditNoteRequest(idempotencyKey: 'g', invoiceId: 'i', reason: 'other', items: []);

      final e1 = await api.createCreditNote(gutschrift).then<Object?>((_) => null, onError: (Object e) => e);
      expect(rechnungFehlerCode(e1), 'credit_exceeds_invoice');
      expect((e1 as KasseneckApiError).details['remainingCents'], {'total': 6000});

      final e2 = await api.createCreditNote(gutschrift).then<Object?>((_) => null, onError: (Object e) => e);
      expect(rechnungFehlerCode(e2), 'validation');
      expect(rechnungFeldFehler(e2).single.field, 'items[0].vatRate');

      final e3 = await api.createCreditNote(gutschrift).then<Object?>((_) => null, onError: (Object e) => e);
      expect(rechnungFehlerCode(e3), 'invoice_setup_incomplete');
      expect(((e3 as KasseneckApiError).details['missing'] as List).single['requirement'], 'number_format');

      final e4 = await api.createCreditNote(gutschrift).then<Object?>((_) => null, onError: (Object e) => e);
      expect(e4, isA<KasseneckApiError>());
      expect(rechnungFehlerCode(e4), isNull, reason: 'ein Code außerhalb des Katalogs ist kein Rechnungs-Fehlercode');
      expect(rechnungFeldFehler(Exception('fremd')), isEmpty);
    });

    test('Schlüssel: leer, Partner-Schlüssel und Kassen-Token werden ohne Netz abgewiesen, ohne den Wert zu nennen', () {
      for (final falsch in ['', 'pk_live_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345', 'cb_live_ZmFsc2NoZXJUb2tlbg']) {
        expect(
          () => RechnungApi(apiKey: falsch),
          throwsA(isA<KasseneckValidationError>().having((e) => '$e'.contains(falsch) && falsch.isNotEmpty, 'nennt Wert', isFalse)),
        );
      }
      expect(() => RechnungApi(apiKey: '0a1b2c3d4e5f-uid123'), returnsNormally, reason: 'Altformate bleiben gültig');
    });

    test('Zeitablauf ist ein eigener Grund, kein Netzfehler', () async {
      final (:api, log: _) = _apiMit([
        () => Future<http.Response>.delayed(const Duration(milliseconds: 200), () => http.Response('{}', 200)),
      ], timeout: const Duration(milliseconds: 20));
      await expectLater(
        api.getInvoiceSetupStatus(),
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', KasseneckHttpError.zeitablauf)),
      );
    });
  });

  group('Sprache und Marke (Vertrag 0.17.0)', () {
    test('listBrands: ohne Parameter, liest die Marken', () async {
      final (:api, :log) = _apiMit([
        _erfolg({
          'brands': [
            {'id': 'm1', 'name': 'Haus', 'isDefault': true},
            {'id': 'm2', 'name': 'Zweit', 'isDefault': false},
          ],
        }),
      ]);
      final marken = await api.listBrands();
      expect(_params(log.single), <String, dynamic>{});
      expect(log.single.url.toString(), 'https://api.kasseneck.at/v1/listBrands');
      expect(marken.map((m) => (m.id, m.name, m.isDefault)).toList(), [('m1', 'Haus', true), ('m2', 'Zweit', false)]);
    });

    test('listBrands: eine Antwort ohne brands ist ein Antwortfehler', () async {
      final (:api, log: _) = _apiMit([_erfolg(<String, dynamic>{})]);
      await expectLater(api.listBrands(), throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')));
    });

    test('getInvoicePdf: language geht nur mit, wenn gesetzt', () async {
      final pdf = utf8.encode('%PDF-1.7\n');
      final (:api, :log) = _apiMit([
        http.Response.bytes(pdf, 200, headers: {'content-type': 'application/pdf'}),
        http.Response.bytes(pdf, 200, headers: {'content-type': 'application/pdf'}),
      ]);
      await api.getInvoicePdf('inv1');
      await api.getInvoicePdf('inv1', language: 'de');
      expect(_params(log[0]), {'invoiceId': 'inv1'});
      expect(_params(log[1]), {'invoiceId': 'inv1', 'language': 'de'});
    });

    test('Anfrage und Rechnung tragen Sprache und Marke; Altbestand ist Deutsch', () async {
      final (:api, :log) = _apiMit([
        _erfolg({'invoice': {..._rechnung, 'language': 'en', 'brand': {'id': 'm1', 'name': 'Haus'}}, 'replayed': false}),
        _erfolg({'invoice': _rechnung, 'replayed': false}),
      ]);
      final r = await api.issueInvoice(const IssueInvoiceRequest(
        idempotencyKey: 'k-en', taxScheme: 'normal', priceMode: 'net', serviceStart: '2026-09-15', language: 'en', brandId: 'm1',
        items: [InvoiceItemInput(description: 'Consulting', quantity: 1, unitPriceCents: 5000, vatRate: 20)],
      ));
      expect(_params(log[0])['language'], 'en');
      expect(_params(log[0])['brandId'], 'm1');
      expect((r.invoice.language, r.invoice.brandId, r.invoice.brandName), ('en', 'm1', 'Haus'));
      final alt = await api.issueInvoice(const IssueInvoiceRequest(
        idempotencyKey: 'k-alt', taxScheme: 'normal', priceMode: 'net', serviceStart: '2026-09-15', items: []));
      expect((alt.invoice.language, alt.invoice.brandId), ('de', null));
      expect(_params(log[1]).containsKey('language'), isFalse);
    });

    test('Kunde: language in beide Richtungen, fehlt = de', () {
      expect(const CustomerInput(type: 'company', name: 'X', country: 'AT', language: 'en').toJson()['language'], 'en');
      expect(const CustomerInput(type: 'company', name: 'X', country: 'AT').toJson().containsKey('language'), isFalse);
      expect(Customer.fromJson({'id': 'k1', 'type': 'company', 'name': 'X', 'country': 'AT'}).language, 'de');
      expect(Customer.fromJson({'id': 'k1', 'type': 'company', 'name': 'X', 'country': 'AT', 'language': 'en'}).language, 'en');
    });
  });
}
