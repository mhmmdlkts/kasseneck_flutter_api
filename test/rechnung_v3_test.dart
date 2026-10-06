import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/invoice.dart';

/// Die Rechnungs-API auf dem englischen `/v3`-Draht, gegen den Vertrags-Export
/// des Backends (`v3/antworten/rechnungen.json`, erzeugt aus den echten
/// Handlern).
///
/// Jeder Fall laeuft durch [InvoiceApi]: Adresse und Parameter muessen genau
/// so hinausgehen, wie der Export sie aufgezeichnet hat, und jede gelesene
/// Rechnungssicht traegt nur Werte aus den Katalogen von `vertrag.dart`
/// (Belegart, Steuerfall, Abschreibungsgrund, fehlende E-Rechnungs-Angaben,
/// Zahlart, Hinweis). Ein Fehlerfall kommt mit seinem Code an.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

final _export = jsonDecode(File('test/fixtures/vertrag/v3/antworten/rechnungen.json').readAsStringSync())
    as Map<String, dynamic>;
final _faelle = (_export['cases'] as List).cast<Map<String, dynamic>>();

({InvoiceApi api, List<http.Request> log}) _apiFuer(Map<String, dynamic> fall) {
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
  return (api: InvoiceApi(apiKey: _apiKey, httpClient: mock), log: log);
}

/// Ruft den Endpunkt des Falls mit dessen Parametern ueber die oeffentlichen
/// Methoden auf; die Anfrage-Modelle werden dabei aus den Parametern gebaut.
Future<Object> _rufe(InvoiceApi api, String endpunkt, Map<String, dynamic> p) async {
  switch (endpunkt) {
    case 'issueInvoice':
      if (p['dryRun'] == true) {
        return api.previewInvoice(IssueInvoiceRequest.fromJson(Map.of(p)..remove('dryRun')));
      }
      return api.issueInvoice(IssueInvoiceRequest.fromJson(p));
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

/// Eine Map, die mitschreibt, welche Felder gelesen werden. Verschachtelte
/// Maps (auch in Listen) werden mit umhuellt; die Modelle kopieren eine schon
/// getypte Map nicht, darum kommt jeder Zugriff hier an.
class _Spur extends MapBase<String, dynamic> {
  _Spur(Map<String, dynamic> roh) : _daten = {for (final e in roh.entries) e.key: _umhuelle(e.value)};

  final Map<String, dynamic> _daten;
  final Set<String> gelesen = {};

  static Object? _umhuelle(Object? wert) => switch (wert) {
        Map<String, dynamic> m => _Spur(m),
        List l => [for (final e in l) _umhuelle(e)],
        _ => wert,
      };

  @override
  Object? operator [](Object? key) {
    if (key is String) gelesen.add(key);
    return _daten[key];
  }

  @override
  bool containsKey(Object? key) {
    if (key is String) gelesen.add(key);
    return _daten.containsKey(key);
  }

  @override
  void operator []=(String key, dynamic value) => throw UnsupportedError('nur lesen');
  @override
  void clear() => throw UnsupportedError('nur lesen');
  @override
  Iterable<String> get keys => _daten.keys;

  // Durchlaufen zaehlt nicht als Lesen: sonst markierte eine Kopie
  // (Map.from) jedes Feld als gelesen, und der Test waere blind.
  @override
  void forEach(void Function(String key, dynamic value) action) => _daten.forEach(action);
  @override
  Iterable<MapEntry<String, dynamic>> get entries => _daten.entries;
  @override
  Iterable<dynamic> get values => _daten.values;
  @override
  dynamic remove(Object? key) => throw UnsupportedError('nur lesen');
}

/// Felder, die eine Sicht fuehrt, die aber in einer Antwort fehlen duerfen.
/// `reservationId` steht nur am Hinweis `reservation_expired` (seit 10.4).
const _optional = {'unitPriceMicros', 'notice', 'reservationId'};

/// Prueft eine Sicht in drei Richtungen: jedes gesendete Feld steht in der
/// Liste des Modells und in der Antwort fehlt keines der Liste (bis auf
/// [_optional]); jedes gesendete Feld hat das Modell auch gelesen; und das
/// Modell liest nichts, was nicht in [liesAlles] (seiner vollen Liste) steht.
void _feldmenge(Object? knoten, Set<String> felder, String pfad, {Set<String>? liesAlles}) {
  if (knoten == null) return;
  expect(knoten, isA<_Spur>(), reason: '$pfad: kein Objekt');
  final spur = knoten as _Spur;
  final da = spur.keys.toSet();
  expect(da.difference(felder), isEmpty, reason: '$pfad: Felder ohne Eintrag im Modell');
  expect(felder.difference(da).difference(_optional), isEmpty, reason: '$pfad: Felder fehlen in der Antwort');
  expect(da.difference(spur.gelesen), isEmpty, reason: '$pfad: gesendet, aber vom Modell nicht gelesen');
  expect(spur.gelesen.difference(liesAlles ?? felder), isEmpty, reason: '$pfad: gelesen, aber nicht in der Liste');
}

void _rechnungssicht(Object? r, String pfad, {required bool detail}) {
  final spur = r! as _Spur;
  _feldmenge(spur, detail ? Invoice.detailFields : Invoice.fields, pfad, liesAlles: Invoice.detailFields);
  final totals = spur['totals'] as _Spur;
  _feldmenge(totals, InvoiceTotals.fields, '$pfad.totals');
  for (final (i, satz) in (totals['byRate'] as List).indexed) {
    _feldmenge(satz, VatRateTotal.fields, '$pfad.totals.byRate[$i]');
  }
  _feldmenge(spur['einvoice'], EInvoiceStatus.fields, '$pfad.einvoice');
  _feldmenge(spur['brand'], Invoice.brandFields, '$pfad.brand');
  _feldmenge(spur['vatIdProof'], InvoiceVatIdProof.fields, '$pfad.vatIdProof');
  _feldmenge(spur['vatIdRisk'], InvoiceVatIdRisk.fields, '$pfad.vatIdRisk');
  if (!detail) return;
  for (final (i, p) in (spur['items'] as List).indexed) {
    _feldmenge(p, InvoiceItem.fields, '$pfad.items[$i]');
  }
  _feldmenge(spur['customer'], InvoiceRecipient.fields, '$pfad.customer');
  for (final (i, z) in (spur['payments'] as List).indexed) {
    _feldmenge(z, InvoiceDetailPayment.fields, '$pfad.payments[$i]');
  }
  _feldmenge(spur['related'], Invoice.relatedFields, '$pfad.related');
  for (final (i, g) in (spur['creditNotes'] as List).indexed) {
    _feldmenge(g, CreditNoteSummary.fields, '$pfad.creditNotes[$i]');
  }
}

void _hinweisSichten(_Spur d, String pfad) {
  final roh = d['notice'];
  for (final (i, h) in (roh is List ? roh : [?roh]).indexed) {
    _feldmenge(h, InvoiceNotice.fields, '$pfad.notice[$i]');
  }
}

/// Liest die Daten eines Erfolgsfalls mit dem Modell des Endpunkts und prueft
/// danach jede Sicht.
void _feldmengenDesFalls(Map<String, dynamic> fall) {
  final p = fall['name'] as String;
  final d = _Spur(((fall['response'] as Map)['data'] as Map).cast<String, dynamic>());
  switch (fall['endpoint']) {
    case 'issueInvoice':
      if (d.keys.contains('preview')) {
        PreviewResult.fromJson(d);
        _feldmenge(d, PreviewResult.fields, p);
        final v = d['preview'] as _Spur;
        _feldmenge(v, InvoicePreview.fields, '$p.preview');
        _feldmenge(v['totals'], InvoiceTotals.fields, '$p.preview.totals');
        for (final (i, satz) in ((v['totals'] as _Spur)['byRate'] as List).indexed) {
          _feldmenge(satz, VatRateTotal.fields, '$p.preview.totals.byRate[$i]');
        }
        _feldmenge(v['einvoice'], EInvoiceStatus.fields, '$p.preview.einvoice');
        _feldmenge(v['brand'], Invoice.brandFields, '$p.preview.brand');
      } else {
        IssueResult.fromJson(d);
        _feldmenge(d, IssueResult.fields, p);
        _rechnungssicht(d['invoice'], '$p.invoice', detail: false);
      }
      _hinweisSichten(d, p);
    case 'getInvoice':
      Invoice.fromJson(d['invoice'] as _Spur);
      _feldmenge(d, const {'invoice'}, p);
      _rechnungssicht(d['invoice'], '$p.invoice', detail: true);
    case 'listInvoices':
      InvoicePage.fromJson(d);
      _feldmenge(d, InvoicePage.fields, p);
      for (final (i, r) in (d['invoices'] as List).indexed) {
        _rechnungssicht(r, '$p.invoices[$i]', detail: false);
      }
    case 'createCreditNote':
      CreditNoteResult.fromJson(d);
      _feldmenge(d, CreditNoteResult.fields, p);
      _rechnungssicht(d['creditNote'], '$p.creditNote', detail: false);
    case 'cancelInvoice':
      CancelResult.fromJson(d);
      _feldmenge(d, CancelResult.fields, p);
      _rechnungssicht(d['creditNote'], '$p.creditNote', detail: false);
      _feldmenge(d['original'], CancelResult.originalFields, '$p.original');
    case 'recordInvoicePayment':
      RecordPaymentResult.fromJson(d);
      _feldmenge(d, RecordPaymentResult.fields, p);
      _rechnungssicht(d['invoice'], '$p.invoice', detail: false);
      _feldmenge(d['payment'], InvoicePayment.fields, '$p.payment');
      _hinweisSichten(d, p);
    case 'getInvoiceSetupStatus':
      InvoiceSetupStatus.fromJson(d);
      _feldmenge(d, InvoiceSetupStatus.fields, p);
      for (final (i, l) in (d['missing'] as List).indexed) {
        _feldmenge(l, InvoiceSetupGap.fields, '$p.missing[$i]');
      }
    case 'listBrands':
      expect(d.keys, ['brands'], reason: p);
      for (final (i, b) in (d['brands'] as List).indexed) {
        Brand.fromJson(b as _Spur);
        _feldmenge(b, Brand.fields, '$p.brands[$i]');
      }
    default:
      fail('$p: Endpunkt ${fall['endpoint']} ohne Feldpruefung');
  }
}

void main() {
  test('der Export ist der oeffentliche Kanal und hat alle Faelle', () {
    expect(_export['channel'], 'api');
    expect(_faelle.length, 25);
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
        expect((jsonDecode(log.single.body) as Map)['params'], fall['params']);

        if (antwort['status'] == 'error') {
          expect(fehler, isA<KasseneckApiError>(), reason: '$fehler');
          final e = fehler! as KasseneckApiError;
          expect(e.code, antwort['code']);
          expect(invoiceErrorCodes, contains(e.code));
          expect(invoiceErrorCode(e), antwort['code']);
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

  group('Feldmengen (Zwilling von npm F6)', () {
    test('jede Sicht jedes Erfolgsfalls: gesendet = Liste des Modells, alles gelesen', () {
      final erfolge = _faelle.where((f) => (f['response'] as Map)['status'] == 'success').toList();
      expect(erfolge.length, greaterThanOrEqualTo(15));
      for (final fall in erfolge) {
        _feldmengenDesFalls(fall);
      }
    });

    test('Detailsicht: InvoiceRecipient, Bezug und Positionsart gelesen', () {
      final r = Invoice.fromJson({
        ...((_faelle.firstWhere((f) => f['name'] == 'get_invoice')['response'] as Map)['data'] as Map)['invoice'] as Map<String, dynamic>,
        'related': {'invoiceId': 'auto0', 'number': '2026-0001'},
        'reverseChargeReason': 'construction',
      });
      final k = r.customer!;
      expect((k.name, k.type, k.street, k.houseNumber, k.zip, k.city, k.country, k.vatId, k.shortCode, k.email, k.isAuthority),
          ('Baecker Wien GmbH', 'company', 'Hauptplatz 1', null, '1010', 'Wien', 'AT', 'ATU87654321', null, null, false));
      expect((r.relatedInvoiceId, r.relatedNumber, r.reverseChargeReason), ('auto0', '2026-0001', 'construction'));
      expect((r.taxCountry, r.priceMode, r.serviceStart, r.serviceEnd, r.paymentTermDays, r.orderReference),
          ('AT', 'net', '2026-09-26', null, 14, null));
      expect((r.source, r.createdAt, r.finalizedAt), ('api', '2026-09-26T08:00:00.000Z', '2026-09-26T08:00:00.000Z'));
      expect(r.items!.single.kind, 'service');
      expect(InvoiceItem.fromJson({'description': 'x', 'quantity': 1, 'unitPriceCents': 1, 'vatRate': 20}).kind, 'goods');
    });

    test('Rot-Probe: ein Feld ohne Eintrag in der Liste faellt auf', () {
      final fall = _faelle.firstWhere((f) => f['name'] == 'get_invoice');
      final d = _Spur(((fall['response'] as Map)['data'] as Map).cast<String, dynamic>());
      Invoice.fromJson(d['invoice'] as _Spur);
      final ohne = Invoice.detailFields.difference({'finalizedAt'});
      expect(() => _feldmenge(d['invoice'], ohne, 'probe', liesAlles: ohne), throwsA(isA<TestFailure>()));
    });

    test('Rot-Probe: ein gesendetes, aber nicht gelesenes Feld faellt auf', () {
      final d = _Spur({'code': 'cash_receipt_required', 'message': 'x', 'neu': 1});
      InvoiceNotice.fromJson(d);
      expect(() => _feldmenge(d, {...InvoiceNotice.fields, 'neu'}, 'probe'), throwsA(isA<TestFailure>()));
    });
  });

  group('UID-Pruefung beim Ausstellen ohne Steuer (Vertrag 1.5.0)', () {
    Map<String, dynamic> fall(String name) => _faelle.firstWhere((f) => f['name'] == name);

    test('vat_id_check_pending traegt retryAfter; die Wiederholung mit demselben Schluessel und acceptVatIdRisk stellt aus',
        () async {
      final offen = fall('error_vat_id_check_pending');
      final (:api, log: _) = _apiFuer(offen);
      final fehler = await api
          .issueInvoice(IssueInvoiceRequest.fromJson((offen['params'] as Map).cast<String, dynamic>()))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(invoiceErrorCode(fehler), 'vat_id_check_pending');
      final warten = (fehler! as KasseneckApiError).details['retryAfter'];
      expect(warten, isA<int>().having((w) => w, 'Sekunden', greaterThan(0)));

      final risiko = fall('issue_final_vat_id_risk');
      expect((risiko['params'] as Map)['idempotencyKey'], (offen['params'] as Map)['idempotencyKey'],
          reason: 'wiederholt wird mit demselben Schluessel, nur mit dem Feld');
      final (api: api2, :log) = _apiFuer(risiko);
      final anfrage = IssueInvoiceRequest.fromJson((risiko['params'] as Map).cast<String, dynamic>());
      expect(anfrage.acceptVatIdRisk, isTrue);
      final r = await api2.issueInvoice(anfrage);
      expect((jsonDecode(log.single.body) as Map)['params']['acceptVatIdRisk'], true);
      expect(r.invoice.vatIdProof, isNull);
      expect(r.invoice.vatIdRisk!.acceptedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('der eingefrorene Nachweis kommt mit Quelle, Stufe und Pruefcode an', () {
      final mitNachweis = [
        for (final f in _faelle)
          if ((f['response'] as Map)['status'] == 'success')
            if (((f['response'] as Map)['data'] as Map)['invoice'] case final Map i when i['vatIdProof'] != null) (f['name'], i),
      ];
      expect(mitNachweis, isNotEmpty);
      for (final (name, roh) in mitNachweis) {
        final r = Invoice.fromJson(roh.cast<String, dynamic>());
        final n = r.vatIdProof!;
        expect(['finanzonline', 'vies'], contains(n.source), reason: '$name');
        expect([1, 2], contains(n.level), reason: '$name');
        expect(n.checkedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(n.code, anyOf(isNull, isA<String>()));
        expect(r.vatIdRisk, isNull, reason: '$name');
      }
    });

    test('ein Nachweis ohne Pflichtfeld ist eine kaputte Antwort, nie still null', () {
      final roh = ((fall('issue_final_intra_community')['response'] as Map)['data'] as Map)['invoice'] as Map<String, dynamic>;
      final nachweis = Map.of(roh['vatIdProof'] as Map<String, dynamic>)..remove('level');
      expect(() => Invoice.fromJson({...roh, 'vatIdProof': nachweis}), throwsFormatException);
      expect(() => Invoice.fromJson({...roh, 'vatIdRisk': <String, dynamic>{}}), throwsFormatException);
      expect(() => Invoice.fromJson({...roh, 'vatIdProof': 'vies'}), throwsFormatException);
    });

    test('vat_id_invalid ist ein Rechnungs-Fehler; acceptVatIdRisk geht nur gesetzt hinaus', () {
      expect(invoiceErrorCode(const KasseneckApiError('issueInvoice', 'x', code: 'vat_id_invalid')), 'vat_id_invalid');
      const ohne = IssueInvoiceRequest(idempotencyKey: 'k', priceMode: 'net', serviceStart: '2026-10-06', items: []);
      expect(ohne.toJson().containsKey('acceptVatIdRisk'), isFalse);
      const mitFalse =
          IssueInvoiceRequest(idempotencyKey: 'k', priceMode: 'net', serviceStart: '2026-10-06', items: [], acceptVatIdRisk: false);
      expect(mitFalse.toJson()['acceptVatIdRisk'], false);
    });
  });

  group('dryRun', () {
    test('fromJson behaelt dryRun, issueInvoice sendet false mit', () async {
      final fall = _faelle.firstWhere((f) => f['name'] == 'issue_final');
      final anfrage = IssueInvoiceRequest.fromJson((fall['params'] as Map).cast<String, dynamic>());
      expect(anfrage.dryRun, false);
      expect(anfrage.toJson()['dryRun'], false);
    });

    test('issueInvoice mit dryRun: true wird vor dem Senden abgewiesen', () async {
      final fall = _faelle.firstWhere((f) => f['name'] == 'issue_dry_run_intra_community');
      final (:api, :log) = _apiFuer(fall);
      await expectLater(
        api.issueInvoice(IssueInvoiceRequest.fromJson((fall['params'] as Map).cast<String, dynamic>())),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(log, isEmpty);
    });
  });

  test('Anfrage-Codes und Rechnungs-Codes sind getrennt, rechnungFehlerCode kennt nur diese', () {
    expect(invoiceRequestErrorCodes.toSet().intersection(invoiceErrorCodes.toSet()), isEmpty);
    for (final code in invoiceRequestErrorCodes) {
      expect(invoiceErrorCode(KasseneckApiError('getInvoice', 'x', code: code)), isNull, reason: code);
    }
    for (final code in invoiceErrorCodes) {
      expect(invoiceErrorCode(KasseneckApiError('getInvoice', 'x', code: code)), code);
    }
  });
}
