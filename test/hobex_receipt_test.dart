import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/models/hobex_receipt.dart';

Map<String, dynamic> cloudJson({Object? amount = 12.5, Object? tip = 0.5, String cvm = '1'}) => {
      'transactionId': 'TX1',
      'tid': '3600335',
      'receipt': '42',
      'approvalCode': 'ABC',
      'reference': null,
      'transactionDate': '2026-06-12T10:00:00.123456',
      'cardNumber': '************1234',
      'cardExpiry': '2612',
      'brand': 'Visa',
      'cardIssuer': 'Bank',
      'responseCode': '0',
      'transactionType': 'SELL',
      'currency': 'EUR',
      'amount': amount,
      'tip': tip,
      'cvm': cvm,
    };

void main() {
  group('HobexReceipt.fromJson (Cloud)', () {
    test('happy path: Datum ohne Millis, Provider-Default Cloud', () {
      final r = HobexReceipt.fromJson(cloudJson());
      expect(r.transactionDate, '2026-06-12 10:00:00');
      expect(r.creditCardProvider, CreditCardProvider.hobexCloudApi);
      expect(r.amount, 12.5);
      expect(r.tip, 0.5);
    });
    test('amount/tip null -> 0 (kein Crash)', () {
      final r = HobexReceipt.fromJson(cloudJson(amount: null, tip: null));
      expect(r.amount, 0);
      expect(r.tip, 0);
    });
    test('needSignature nur bei cvm == 1', () {
      expect(HobexReceipt.fromJson(cloudJson(cvm: '1')).needSignature, isTrue);
      expect(HobexReceipt.fromJson(cloudJson(cvm: '2')).needSignature, isFalse);
    });
  });

  group('toCardPaymentData', () {
    test('Cloud: nur die gemeinsamen Render-Keys (keine HPS-Extras)', () {
      final data = HobexReceipt.fromJson(cloudJson()).toCardPaymentData();
      expect(data.keys, containsAll(['transactionId', 'date', 'tid', 'no', 'type', 'cardBrand', 'cardNumber', 'responseCode', 'cvm']));
      expect(data.containsKey('approvalCode'), isFalse);
      expect(data.containsKey('amount'), isFalse);
    });
  });

  group('Gleichheit', () {
    test('== und hashCode nur ueber transactionId', () {
      final a = HobexReceipt.fromJson(cloudJson());
      final b = HobexReceipt.fromJson(cloudJson(amount: 99));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
