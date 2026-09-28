import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_tip.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

/// Die Hauptklasse [KasseneckApi] gegen den Vertrag `/v3`
/// (`test/fixtures/vertrag/v3/antworten/belege.json`), Zwilling der
/// Verkaufs- und Lesefaelle in `test/receipts-v3.test.ts` des npm-Pakets:
/// Verkauf nur mit Zahlungen, gesendet wird genau, was der Vertrag zeigt,
/// Fehler behalten Code und Ausgang, das Server-Layout gewinnt.
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;
final _belege = (_json('antworten/belege.json')['cases'] as List).cast<Map<String, dynamic>>();
Map<String, dynamic> _fall(String name) => _belege.firstWhere((f) => f['name'] == name);

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};

http.Response _antwort(Map<String, dynamic> fall) =>
    http.Response(jsonEncode(fall['response']), fall['httpStatus'] as int, headers: _kopf);

KasseneckApi _api(http.Client client, {Duration? signatureTimeout}) => KasseneckApi(
      apiKey: 'kr_test_x',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
      signatureTimeout: signatureTimeout ?? const Duration(seconds: 90),
    );

({MockClient client, List<http.Request> log}) _mock(FutureOr<http.Response> Function(http.Request) antwort) {
  final log = <http.Request>[];
  return (
    client: MockClient((r) async {
      log.add(r);
      return antwort(r);
    }),
    log: log,
  );
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

/// Positionen in v1- und v2-Form gleich behandeln (wie der npm-Test): der
/// Server nimmt beide, das Paket schreibt v2.
Map<String, dynamic> _positionV2(Map p) => {
      'name': p['name'],
      'quantity': p['quantity'] ?? p['amount'],
      'unitPriceCents': p['unitPriceCents'] ?? p['priceOneCents'],
      'vatRate': p['vatRate'] ?? p['vat'],
    };

Map<String, dynamic> _normalisiert(Map<String, dynamic> params) => {
      ...params,
      if (params['items'] is List) 'items': [for (final p in params['items'] as List) _positionV2(p as Map)],
    };

List<KeckPaymentInput> _zahlungen(Map params) => [
      for (final z in (params['payments'] as List).cast<Map<String, dynamic>>())
        KeckPaymentInput(
          method: KeckPaymentMethod.values.byName(z['method'] as String),
          amountCents: z['amountCents'] as int,
          tenderedCents: z['tenderedCents'] as int?,
          provider: z['provider'] == null ? null : CreditCardProvider.values.byName(z['provider'] as String),
          providerPaymentId: z['providerPaymentId'] as String?,
          providerData: (z['providerData'] as Map?)?.cast<String, dynamic>(),
        ),
    ];

List<KeckVoucher>? _gutscheine(Map params) => (params['vouchers'] as List?)
    ?.cast<Map<String, dynamic>>()
    .map((g) => KeckVoucher(
          code: g['code'] as String?,
          name: g['name'] as String?,
          action: VoucherAction.values.byName(g['action'] as String),
          type: VoucherType.values.byName(g['type'] as String),
          valueCents: g['valueCents'] as int?,
        ))
    .toList();

KeckTip? _tip(Map params) {
  final t = params['tip'] as Map?;
  if (t == null) return null;
  return KeckTip(cents: t['cents'] as int, receivedImmediately: t['receivedImmediately'] as bool?);
}

Future<KasseneckReceipt?> _verkaufen(KasseneckApi api, Map<String, dynamic> params) => api.sellReceipt(
      payments: _zahlungen(params),
      items: [for (final p in (params['items'] as List).cast<Map<String, dynamic>>()) KasseneckItem.fromJson(p)],
      vouchers: _gutscheine(params),
      tip: _tip(params),
    );

final _einfach = [KasseneckItem(name: 'Kaffee', quantity: 2, priceCents: 300, vat: VatRate.vat20)];
const _bar = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 600)];

void main() {
  group('sellReceipt sendet genau den Vertrag (belege.json)', () {
    for (final name in ['sale_card_with_tip', 'sale_cash_tendered', 'sale_mixed_payments', 'sale_v2_items_value_voucher']) {
      test(name, () async {
        final fall = _fall(name);
        final m = _mock((_) => _antwort(fall));
        final beleg = (await _verkaufen(_api(m.client), fall['params'] as Map<String, dynamic>))!;
        expect(m.log, hasLength(1));
        expect(m.log.single.url.toString(), 'https://api.kasseneck.at/v3/createReceipt');
        expect(_normalisiert(_params(m.log.single)), _normalisiert(fall['params'] as Map<String, dynamic>));
        final daten = (fall['response'] as Map)['data'] as Map<String, dynamic>;
        expect(beleg.receiptId, (daten['receipt'] as Map)['receiptId']);
        expect(beleg.layout!.toJson(), daten['layout']);
      });
    }

    test('zeroReceipt sendet nur den Belegtyp', () async {
      final fall = _fall('zero_receipt');
      final m = _mock((_) => _antwort(fall));
      await _api(m.client).zeroReceipt();
      expect(_params(m.log.single), fall['params']);
    });

    test('Gutschein geht nur mit valueCents hinaus, ohne Euro-Wert und ohne leere Felder', () async {
      final fall = _fall('sale_v2_items_value_voucher');
      final m = _mock((_) => _antwort(fall));
      await _api(m.client).sellReceipt(
        payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 370)],
        items: _einfach,
        vouchers: [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 500)],
      );
      expect(_params(m.log.single)['vouchers'], [
        {'action': 'redeem', 'type': 'value', 'valueCents': 500},
      ]);
    });

    test('eine leere Zahlungsliste geht hinaus (Rabatt deckt alles)', () async {
      final fall = _fall('sale_cash_tendered');
      final m = _mock((_) => _antwort(fall));
      await _api(m.client).sellReceipt(payments: const [], items: _einfach);
      expect(_params(m.log.single)['payments'], isEmpty);
    });

    test('mixed als Zahlart wirft vor dem Senden', () async {
      final m = _mock((_) => fail('darf nicht senden'));
      await expectLater(
        _api(m.client).sellReceipt(
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 600)], items: _einfach),
        throwsArgumentError,
      );
      expect(m.log, isEmpty);
    });
  });

  group('Hauptklasse sendet keine 0.x-Felder mehr', () {
    final quelle = File('lib/kasseneck_api.dart').readAsStringSync();
    for (final alt in [
      "'paymentMethod'",
      "'creditCardProvider'",
      "'cardPaymentId'",
      "'cardPaymentData'",
      "'value':",
      'createCancelReceipt',
      'ReceiptType.cancellation',
    ]) {
      test('kein $alt in lib/kasseneck_api.dart', () {
        expect(quelle.contains(alt), isFalse, reason: '$alt ist 0.x (unter /v3 abgewiesen bzw. entfallen)');
      });
    }
  });

  group('Ausgang bleibt erhalten (sellReceipt): nichts wiederholt, nichts verpackt', () {
    Future<Object?> fehlerVon(KasseneckApi api) async {
      try {
        await api.sellReceipt(payments: _bar, items: _einfach);
      } catch (e) {
        return e;
      }
      return null;
    }

    test('receipt_outcome_unknown: KasseneckApiError, Ausgang unklar, ein Aufruf', () async {
      final m = _mock((_) => http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Ausgang unklar',
            'code': 'receipt_outcome_unknown',
            'data': {'code': 'receipt_outcome_unknown'},
          }),
          200,
          headers: _kopf));
      final e = await fehlerVon(_api(m.client));
      expect(e, isA<KasseneckApiError>().having((e) => e.code, 'code', 'receipt_outcome_unknown'));
      expect(isOutcomeUnknown(e), isTrue);
      expect(m.log, hasLength(1));
    });

    test('Netzfehler: KasseneckHttpError, Ausgang unklar, ein Aufruf', () async {
      final m = _mock((_) => throw http.ClientException('weg'));
      final e = await fehlerVon(_api(m.client));
      expect(e, isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.unknown));
      expect(isOutcomeUnknown(e), isTrue);
      expect(m.log, hasLength(1));
    });

    test('HTTP 503: Ausgang unklar, ein Aufruf', () async {
      final m = _mock((_) => http.Response('', 503, headers: _kopf));
      final e = await fehlerVon(_api(m.client));
      expect(isOutcomeUnknown(e), isTrue);
      expect(m.log, hasLength(1));
    });

    test('Zeitueberschreitung: Ausgang unklar, ein Aufruf', () async {
      final m = _mock((_) => Completer<http.Response>().future);
      final e = await fehlerVon(_api(m.client, signatureTimeout: const Duration(milliseconds: 20)));
      expect(e, isA<KasseneckHttpError>());
      expect(isOutcomeUnknown(e), isTrue);
      expect(m.log, hasLength(1));
    });

    test('Erfolg mit unlesbarem Beleg: response_unreadable mit Kennung, ein Aufruf', () async {
      final m = _mock((_) => http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'receipt': {'receiptId': 'KECK-1-ID-9'},
            },
          }),
          200,
          headers: _kopf));
      final e = await fehlerVon(_api(m.client));
      expect(e, isA<KasseneckApiError>().having((e) => e.code, 'code', 'response_unreadable'));
      expect((e as KasseneckApiError).details['receiptId'], 'KECK-1-ID-9');
      expect(isOutcomeUnknown(e), isTrue);
      expect(m.log, hasLength(1));
    });

    test('abgelehnt (payment_method_not_supported): Code bleibt, Ausgang abgelehnt', () async {
      final fall = _fall('error_payment_method_not_supported');
      final m = _mock((_) => _antwort(fall));
      final e = await fehlerVon(_api(m.client));
      expect(e, isA<KasseneckApiError>().having((e) => e.code, 'code', 'payment_method_not_supported'));
      expect(isOutcomeUnknown(e), isFalse);
    });
  });

  group('lesende Aufrufe englisch', () {
    test('getReceipt: receipt_not_found kommt mit Code', () async {
      final fall = _fall('error_receipt_not_found');
      final m = _mock((_) => _antwort(fall));
      await expectLater(
        _api(m.client).getReceipt('KECK-1-ID-99'),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'receipt_not_found')),
      );
      expect(_params(m.log.single), fall['params']);
    });

    test('getReceipts (getReportV2): start/end, Belege und Firmendaten englisch', () async {
      final fall = _fall('report');
      final m = _mock((_) => _antwort(fall));
      final belege = await _api(m.client).getReceipts(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(m.log.single.url.toString(), 'https://api.kasseneck.at/v3/getReportV2');
      final p = _params(m.log.single);
      expect(p.keys.toSet(), (fall['params'] as Map).keys.toSet());
      expect(p['start'], startsWith(fall['params']['start'] as String));
      expect(p['end'], startsWith(fall['params']['end'] as String));
      final daten = (fall['response'] as Map)['data'] as Map<String, dynamic>;
      final roh = (daten['receipts'] as List).cast<Map<String, dynamic>>();
      final meta = daten['metadata'] as Map<String, dynamic>;
      expect(belege.map((b) => b.receiptId), roh.map((b) => b['receiptId']));
      for (final (i, b) in belege.indexed) {
        expect(b.headerVersionId, roh[i]['headerVersionId'], reason: b.receiptId);
        expect(b.layoutRuleset, roh[i]['layoutRuleset'], reason: b.receiptId);
        expect(b.taxNumber, meta['taxNumber']);
        expect(b.vatId, meta['vatId']);
      }
    });

    test('getReceipts: Fehlerhuelle kommt mit Code', () async {
      final m = _mock((_) => http.Response(
          jsonEncode({'status': 'error', 'message': 'nein', 'code': 'validation', 'data': {'code': 'validation'}}), 200,
          headers: _kopf));
      await expectLater(
        _api(m.client).getReceipts(DateTime(2026, 9, 1), DateTime(2026, 9, 2)),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'validation')),
      );
    });

    test('getFirstReceiptDate und listTipRecipients: Fehlerhuelle kommt mit Code', () async {
      final m = _mock((_) => http.Response(
          jsonEncode({'status': 'error', 'message': 'nein', 'code': 'unauthorized', 'data': {'code': 'unauthorized'}}), 200,
          headers: _kopf));
      final api = _api(m.client);
      await expectLater(api.getFirstReceiptDate(),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'unauthorized')));
      await expectLater(api.listTipRecipients(),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'unauthorized')));
    });
  });

  group('receiptLayoutFromResult', () {
    Map<String, dynamic> daten(String name) =>
        Map<String, dynamic>.from((_fall(name)['response'] as Map)['data'] as Map);

    test('ein Server-Layout gewinnt immer, in seiner Breite', () {
      final d = daten('sale_card_with_tip');
      final beleg = KasseneckReceipt.fromJson(d);
      final wahl = receiptLayoutFromResult(beleg);
      expect(wahl.fromServer, isTrue);
      expect(wahl.layout!.toJson(), d['layout']);
      expect(wahl.paperSize, KeckPaperSize.mm80);
      expect(receiptLayoutFromResult(beleg, fallbackPaperSize: KeckPaperSize.mm58).layout!.toJson(), d['layout']);
    });

    test('ohne Server-Layout: Rueckfall in fallbackPaperSize, Vorgabe mm58', () {
      final d = daten('sale_card_with_tip')..remove('layout');
      final beleg = KasseneckReceipt.fromJson(d);
      final wahl = receiptLayoutFromResult(beleg);
      expect(wahl.fromServer, isFalse);
      expect(wahl.layout, isNull);
      expect(wahl.paperSize, KeckPaperSize.mm58);
      expect(receiptLayoutFromResult(beleg, fallbackPaperSize: KeckPaperSize.mm80).paperSize, KeckPaperSize.mm80);
    });

    test('sellReceipt liefert den Beleg mit dem Server-Layout der Antwort', () async {
      final fall = _fall('sale_cash_tendered');
      final m = _mock((_) => _antwort(fall));
      final beleg = (await _verkaufen(_api(m.client), fall['params'] as Map<String, dynamic>))!;
      expect(receiptLayoutFromResult(beleg).layout!.toJson(), ((fall['response'] as Map)['data'] as Map)['layout']);
    });
  });
}
