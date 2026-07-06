import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

import 'helpers/test_receipts.dart';

KasseneckApi apiWith(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('CASHBOX-9:secret')),
      httpClient: client,
    );

MockClient successClient(void Function(http.Request) capture) => MockClient((request) async {
      capture(request);
      return http.Response(
        jsonEncode({'status': 'success', 'data': buildReceipt().toJson()}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Darf nie aufgerufen werden — fuer Tests, die VOR dem HTTP-Call scheitern muessen.
MockClient neverCalled() => MockClient((request) async {
      fail('HTTP-Request darf hier nicht passieren: ${request.url}');
    });

final validItem = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 100);

void main() {
  group('Request-Anatomie', () {
    test('Header, Endpoint und Body-Struktur', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));

      await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]);

      expect(captured.url.toString(), 'https://api.kasseneck.at/v1/createReceipt');
      expect(captured.headers['Authorization'], 'Bearer test-key');
      expect(captured.headers['cashregister-token'], base64Encode(utf8.encode('CASHBOX-9:secret')));
      expect(captured.headers['content-type'], startsWith('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.keys, ['params']);
      final params = body['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'standard');
      expect(params['paymentMethod'], 'cash');
      final item = (params['items'] as List).first as Map<String, dynamic>;
      expect(item['priceOne'], 1.0);
      expect(item['priceOneCents'], 100); // Dual-Send
    });

    test('sellReceipt parst die Antwort zu einem Beleg', () async {
      final api = apiWith(successClient((_) {}));
      final receipt = await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]);
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, 'TEST-ID-1');
    });
  });

  group('Fehlerpfade', () {
    test('status error -> Exception mit Backend-Message', () async {
      final api = apiWith(MockClient((_) async =>
          http.Response(jsonEncode({'status': 'error', 'message': 'Kasse gesperrt'}), 200)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(predicate((e) => e.toString().contains('Kasse gesperrt'))),
      );
    });
    test('HTTP 500 -> Exception mit Statuscode', () async {
      final api = apiWith(MockClient((_) async => http.Response('kaputt', 500)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(predicate((e) => e.toString().contains('500'))),
      );
    });
    test('leerer Body -> Exception', () async {
      final api = apiWith(MockClient((_) async => http.Response('', 200)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('sellReceipt-Validierung (wirft VOR dem HTTP-Call)', () {
    test('standard ohne Items -> ArgumentError', () {
      final api = apiWith(neverCalled());
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: []),
          throwsArgumentError);
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash),
          throwsArgumentError);
    });
    test('ungueltiges Item (leerer Name) -> ArgumentError', () {
      final api = apiWith(neverCalled());
      final bad = KasseneckItem(name: '', quantity: 1, vat: VatRate.vat20, priceCents: 1);
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [bad]),
          throwsArgumentError);
    });
    test('ungueltiger Voucher -> ArgumentError', () {
      final api = apiWith(neverCalled());
      final bad = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 0);
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem], vouchers: [bad]),
        throwsArgumentError,
      );
    });
    test('NUR Sell-Voucher ohne Items ist erlaubt (geht bis zum HTTP-Call)', () async {
      final api = apiWith(successClient((_) {}));
      final voucher = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000);
      final receipt = await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, vouchers: [voucher]);
      expect(receipt, isNotNull);
    });
  });

  group('checkVoucherCombinationError-Vollmatrix', () {
    final api = apiWith(neverCalled());
    KeckVoucher promoRedeem() => KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 100);
    KeckVoucher promoSell() => KeckVoucher(action: VoucherAction.sell, type: VoucherType.promo, valueCents: 100);
    KeckVoucher valueRedeem() => KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 100);
    KeckVoucher valueSell() => KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 100);

    test('Promo darf nicht verkauft werden', () {
      expect(api.checkVoucherCombinationError([promoSell()], [validItem]), contains('nicht verkauft'));
    });
    test('nur EIN Promo einloesbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), promoRedeem()], [validItem]),
          contains('nur ein Gutschein'));
    });
    test('Promo nicht mit anderen Einloesungen kombinierbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), valueRedeem()], [validItem]),
          contains('nicht mit anderen Gutscheinen kombiniert'));
    });
    test('Promo nicht mit Gutschein-Verkauf kombinierbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), valueSell()], [validItem]),
          contains('nicht andere Gutscheine verkauft'));
    });
    test('Einloesung braucht mindestens ein Item', () {
      expect(api.checkVoucherCombinationError([valueRedeem()], []), contains('mindestens ein item'));
    });
    test('gueltige Kombinationen -> null', () {
      expect(api.checkVoucherCombinationError([promoRedeem()], [validItem]), isNull);
      expect(api.checkVoucherCombinationError([valueRedeem(), valueSell()], [validItem]), isNull);
      expect(api.checkVoucherCombinationError([valueSell()], []), isNull);
    });
  });

  group('Weitere API-Helfer', () {
    test('cancelReceipt negiert die Items des Originals', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));
      final original = cartA();
      await api.cancelReceipt(receipt: original);

      final params = (jsonDecode(captured.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'cancellation');
      final cents = (params['items'] as List).map((i) => i['priceOneCents'] as int).toList();
      expect(cents, [-1999, -29, -105]);
    });
    test('zeroReceipt sendet keine Items', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));
      await api.zeroReceipt();
      final params = (jsonDecode(captured.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'zero');
      expect(params.containsKey('items'), isFalse);
    });
    test('getReceipts: start nach end -> ArgumentError', () {
      final api = apiWith(neverCalled());
      expect(() => api.getReceipts(DateTime(2026, 6, 2), DateTime(2026, 6, 1)), throwsArgumentError);
    });
    test('cashregisterId dekodiert den Token', () {
      final api = apiWith(neverCalled());
      expect(api.cashregisterId, 'CASHBOX-9');
    });
    test('newHobexTransactionId: 19 Zeichen, rein numerisch', () {
      final id = KasseneckApi.newHobexTransactionId();
      expect(id.length, 19);
      expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
    });
  });
}
