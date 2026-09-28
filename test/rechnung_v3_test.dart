import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/rechnung.dart';

/// Die Rechnungs-API auf dem englischen `/v3`-Draht, gegen den Vertrags-Export
/// des Backends (`v3/antworten/rechnungen.json`, erzeugt aus den echten
/// Handlern).
///
/// Jeder Fall laeuft durch [RechnungApi]: Adresse und Parameter muessen genau
/// so hinausgehen, wie der Export sie aufgezeichnet hat, und jede gelesene
/// Rechnungssicht traegt nur Werte aus den Katalogen von `vertrag.dart`
/// (Belegart, Steuerfall, Abschreibungsgrund, fehlende E-Rechnungs-Angaben,
/// Zahlart, Hinweis). Ein Fehlerfall kommt mit seinem Code an.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

final _export = jsonDecode(File('test/fixtures/vertrag/v3/antworten/rechnungen.json').readAsStringSync())
    as Map<String, dynamic>;
final _faelle = (_export['cases'] as List).cast<Map<String, dynamic>>();

({RechnungApi api, List<http.Request> log}) _apiFuer(Map<String, dynamic> fall) {
  final log = <http.Request>[];
  final kopf = (fall['headers'] as Map).cast<String, String>();
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode(fall['response'])),
      fall['httpStatus'] as int,
      headers: {'content-type': 'application/json', for (final e in kopf.entries) e.key.toLowerCase(): e.value},
    );
  });
  return (api: RechnungApi(apiKey: _apiKey, httpClient: mock), log: log);
}

/// Ruft den Endpunkt des Falls mit dessen Parametern ueber die oeffentlichen
/// Methoden auf; die Anfrage-Modelle werden dabei aus den Parametern gebaut.
Future<Object> _rufe(RechnungApi api, String endpunkt, Map<String, dynamic> p) async {
  switch (endpunkt) {
    case 'issueInvoice':
      final anfrage = IssueInvoiceRequest.fromJson(Map.of(p)..remove('dryRun'));
      return p['dryRun'] == true ? api.previewInvoice(anfrage) : api.issueInvoice(anfrage);
    case 'getInvoice':
      return api.getInvoice(invoiceId: p['invoiceId'] as String?, number: p['number'] as String?);
    case 'createCreditNote':
      return api.createCreditNote(CreditNoteRequest.fromJson(p));
    case 'cancelInvoice':
      return api.cancelInvoice(
        idempotencyKey: p['idempotencyKey'] as String,
        invoiceId: p['invoiceId'] as String,
        reason: p['reason'] as String,
        note: p['note'] as String?,
      );
    case 'recordInvoicePayment':
      return api.recordInvoicePayment(RecordPaymentRequest(
        idempotencyKey: p['idempotencyKey'] as String,
        invoiceId: p['invoiceId'] as String,
        method: p['method'] as String,
        amountCents: p['amountCents'] as int?,
        paidAt: p['paidAt'] as String?,
        reference: p['reference'] as String?,
        onSite: p['onSite'] as bool?,
      ));
    case 'listInvoices':
      return api.listInvoices(
        from: p['from'] as String?,
        to: p['to'] as String?,
        status: p['status'] as String?,
        docType: p['docType'] as String?,
        customerId: p['customerId'] as String?,
        limit: p['limit'] as int?,
        cursor: p['cursor'] as String?,
      );
    case 'getInvoiceSetupStatus':
      return api.getInvoiceSetupStatus();
    case 'listBrands':
      return api.listBrands();
  }
  throw StateError('Endpunkt $endpunkt hat im Test keinen Aufruf');
}

void _pruefeRechnung(Invoice r, String wo) {
  expect(docTypes, contains(r.docType), reason: '$wo docType');
  if (r.taxScheme != null) expect(taxSchemes, contains(r.taxScheme), reason: '$wo taxScheme');
  if (r.writeOffReasonCode != null) {
    expect(writeOffReasonCodes, contains(r.writeOffReasonCode), reason: '$wo writeOffReasonCode');
  }
  for (final m in r.einvoice?.missing ?? const <String>[]) {
    expect(einvoiceMissingCodes, contains(m), reason: '$wo einvoice.missing');
  }
  for (final z in r.payments ?? const <InvoiceDetailPayment>[]) {
    if (z.method != null) expect(invoicePaymentMethods, contains(z.method), reason: '$wo payments.method');
  }
}

void _pruefeHinweise(List<InvoiceNotice> hinweise, String wo) {
  for (final h in hinweise) {
    expect(invoiceNoticeCodes, contains(h.code), reason: '$wo notice');
  }
}

void _pruefeErgebnis(Object ergebnis, String wo) {
  switch (ergebnis) {
    case Invoice r:
      _pruefeRechnung(r, wo);
    case IssueResult r:
      _pruefeRechnung(r.invoice, wo);
      _pruefeHinweise(r.notice, wo);
    case PreviewResult r:
      expect(docTypes, contains(r.preview.docType), reason: '$wo preview.docType');
      expect(taxSchemes, contains(r.preview.taxScheme), reason: '$wo preview.taxScheme');
      for (final m in r.preview.einvoice?.missing ?? const <String>[]) {
        expect(einvoiceMissingCodes, contains(m), reason: '$wo preview.einvoice.missing');
      }
      _pruefeHinweise(r.notice, wo);
    case CancelResult r:
      _pruefeRechnung(r.creditNote, wo);
    case CreditNoteResult r:
      _pruefeRechnung(r.creditNote, wo);
    case RecordPaymentResult r:
      _pruefeRechnung(r.invoice, wo);
      expect(invoicePaymentMethods, contains(r.payment.method), reason: '$wo payment.method');
      _pruefeHinweise(r.notice, wo);
    case InvoicePage r:
      for (final i in r.invoices) {
        _pruefeRechnung(i, wo);
      }
    case InvoiceSetupStatus r:
      for (final l in r.missing) {
        expect(invoiceSetupRequirements, contains(l.requirement), reason: '$wo missing');
      }
    case List<Brand> _:
      break;
    default:
      fail('$wo: unerwartetes Ergebnis ${ergebnis.runtimeType}');
  }
}

void main() {
  test('der Export ist der oeffentliche Kanal und hat alle Faelle', () {
    expect(_export['channel'], 'api');
    expect(_faelle.length, 23);
  });

  group('jeder Fall aus v3/antworten/rechnungen.json', () {
    for (final fall in _faelle) {
      final name = fall['name'] as String;
      test(name, () async {
        final (:api, :log) = _apiFuer(fall);
        final antwort = fall['response'] as Map<String, dynamic>;
        Object? ergebnis;
        Object? fehler;
        try {
          ergebnis = await _rufe(api, fall['endpoint'] as String, (fall['params'] as Map).cast<String, dynamic>());
        } catch (e) {
          fehler = e;
        }

        // Adresse und Parameter wie aufgezeichnet.
        expect(log, hasLength(1));
        expect(log.single.url.path, fall['path']);
        expect(log.single.url.host, 'api.kasseneck.at');
        // Einzige Abweichung: `dryRun: false` schickt issueInvoice nicht mit,
        // das Backend liest ein fehlendes dryRun als false.
        final erwartet = Map.of(fall['params'] as Map);
        if (fall['endpoint'] == 'issueInvoice' && erwartet['dryRun'] == false) erwartet.remove('dryRun');
        expect((jsonDecode(log.single.body) as Map)['params'], erwartet);

        if (antwort['status'] == 'error') {
          expect(fehler, isA<KasseneckApiError>(), reason: '$fehler');
          final e = fehler! as KasseneckApiError;
          expect(e.code, antwort['code']);
          expect(invoiceErrorCodes, contains(e.code));
          expect(rechnungFehlerCode(e), antwort['code']);
          final missing = e.details['missing'];
          if (missing is List) {
            for (final m in missing) {
              expect(einvoiceMissingCodes, contains(m), reason: 'details.missing');
            }
          }
          final steuerfall = e.details['expected'];
          if (steuerfall != null) expect(taxSchemes, contains(steuerfall), reason: 'details.expected');
        } else {
          expect(fehler, isNull, reason: '$fehler');
          _pruefeErgebnis(ergebnis!, name);
        }
      });
    }
  });

  group('einzelne Sichten', () {
    Map<String, dynamic> antwortVon(String name) =>
        _faelle.firstWhere((f) => f['name'] == name)['response'] as Map<String, dynamic>;
    Map<String, dynamic> rechnungVon(String name) =>
        ((antwortVon(name)['data'] as Map)['invoice'] as Map).cast<String, dynamic>();

    test('abgeschriebene Rechnung: writtenOff und writeOffReasonCode', () {
      final r = Invoice.fromJson(rechnungVon('get_invoice_written_off'));
      expect((r.writtenOff, r.writeOffReasonCode), (true, 'uncollectible'));
      expect(r.docType, 'invoice');
      expect(r.taxScheme, 'normal');
      expect(r.payments, isEmpty);
      expect(r.items!.single.unit, 'piece');
    });

    test('ig. Lieferung: Steuerfall intraCommunitySupply', () {
      final r = Invoice.fromJson(rechnungVon('get_invoice_intra_community'));
      expect(r.taxScheme, 'intraCommunitySupply');
      expect(r.writeOffReasonCode, isNull);
    });

    test('Liste der Gutschriften: docType credit_note', () {
      final seite = (antwortVon('list_credit_notes')['data'] as Map)['invoices'] as List;
      expect({for (final i in seite) Invoice.fromJson((i as Map).cast<String, dynamic>()).docType}, {'credit_note'});
    });

    test('E-Rechnung: fehlende Angaben englisch', () {
      final r = Invoice.fromJson({
        ...rechnungVon('get_invoice'),
        'einvoice': {'level': 'partial', 'formats': ['UBL'], 'missing': ['vat_id', 'order_reference']},
      });
      expect(r.einvoice!.missing, ['vat_id', 'order_reference']);
      expect(r.einvoiceLevel, 'partial');
    });

    test('gebuchte Zahlungen: id, amountCents, date, method, reference', () {
      final r = Invoice.fromJson({
        ...rechnungVon('get_invoice'),
        'payments': [
          {'id': 'z1', 'amountCents': 5000, 'date': '2026-09-26', 'method': 'transfer', 'reference': 'SEPA-4711'},
          {'id': null, 'amountCents': 700, 'date': null, 'method': null, 'reference': null},
        ],
      });
      final (voll, alt) = (r.payments![0], r.payments![1]);
      expect((voll.id, voll.amountCents, voll.date, voll.method, voll.reference),
          ('z1', 5000, '2026-09-26', 'transfer', 'SEPA-4711'));
      expect((alt.id, alt.amountCents, alt.date, alt.method, alt.reference), (null, 700, null, null, null));
    });

    test('ohne Detailfelder (Liste, Ausstellen) bleiben sie null', () {
      final r = Invoice.fromJson(
          ((antwortVon('issue_final')['data'] as Map)['invoice'] as Map).cast<String, dynamic>());
      expect((r.payments, r.taxScheme, r.writeOffReasonCode), (null, null, null));
      expect(r.einvoice!.level, 'full');
    });

    test('Zahlung ohne Betrag ist eine kaputte Antwort', () {
      expect(
        () => Invoice.fromJson({
          ...rechnungVon('get_invoice'),
          'payments': [
            {'id': 'z1', 'date': '2026-09-26', 'method': 'transfer', 'reference': null},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
