import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';

/// Tests fuer die hobex-HPS-Schicht: CVM-Parsing, TransactionResponse,
/// und den Adapter HobexReceipt.fromHps -> toCardPaymentData (Render-Keys).
void main() {
  group('Cvm.fromValue', () {
    test('numerisch (Payment-Response)', () {
      expect(Cvm.fromValue(0), Cvm.unknown);
      expect(Cvm.fromValue(1), Cvm.signature);
      expect(Cvm.fromValue(2), Cvm.pin);
      expect(Cvm.fromValue(3), Cvm.noCvm);
    });
    test('string (Status-v2)', () {
      expect(Cvm.fromValue('SIGNATURE'), Cvm.signature);
      expect(Cvm.fromValue('PIN'), Cvm.pin);
    });
    test('null/unbekannt -> null', () {
      expect(Cvm.fromValue(null), isNull);
      expect(Cvm.fromValue('XYZ'), isNull);
    });
  });

  group('TransactionResponse.fromJson', () {
    test('approved (responseCode 0)', () {
      final r = TransactionResponse.fromJson({
        'transactionId': 'TX1',
        'responseCode': '0',
        'amount': 12.5,
        'cardNumber': '************1234',
        'cvm': 1,
        'brand': 'Visa',
      });
      expect(r.isApproved, isTrue);
      expect(r.isInProgress, isFalse);
      expect(r.amount, 12.5);
      expect(r.cardNumber, '************1234'); // maskierte PAN bleibt erhalten
      expect(r.cvm, Cvm.signature);
    });
    test('declined', () {
      final r = TransactionResponse.fromJson({'responseCode': '05'});
      expect(r.isApproved, isFalse);
      expect(r.isInProgress, isFalse);
    });
    test('in progress (kein responseCode)', () {
      final r = TransactionResponse.fromJson({'transactionId': 'TX2'});
      expect(r.isInProgress, isTrue);
    });
    test('amount als String wird geparst', () {
      final r = TransactionResponse.fromJson({'amount': '9.90'});
      expect(r.amount, 9.9);
    });
  });

  group('HobexReceipt.fromHps + toCardPaymentData', () {
    test('Felder gemappt, Provider hobexHps, Render-Keys vorhanden', () {
      final res = TransactionResponse.fromJson({
        'transactionId': 'TX1',
        'tid': '3600335',
        'receipt': '42',
        'transactionType': 'SELL',
        'brand': 'Visa',
        'cardNumber': '************1234',
        'cardExpiry': '2612',
        'cardIssuer': 'Bank',
        'approvalCode': 'ABC',
        'responseCode': '0',
        'amount': 12.5,
        'currency': 'EUR',
        'transactionDate': '2026-06-10T12:00:00.000',
        'cvm': 1,
      });
      final hr = HobexReceipt.fromHps(res);
      expect(hr.creditCardProvider, CreditCardProvider.hobexHps);
      expect(hr.transactionId, 'TX1');
      expect(hr.cardNumber, '************1234');

      final data = hr.toCardPaymentData();
      // Keys, die print_paper/_hobexHps + keck_receipt_widget/_hobexHpsPart lesen:
      for (final k in ['date', 'tid', 'no', 'type', 'cardBrand', 'cardNumber',
        'responseCode', 'cvm', 'approvalCode', 'cardExpiry']) {
        expect(data.containsKey(k), isTrue, reason: 'Render-Key fehlt: $k');
      }
      expect(data['no'], '42');
      expect(data['cardNumber'], '************1234');
      expect(data['cvm'], '1');
      expect(data['amount'], '12.50');
    });

    test('needSignature bei cvm == 1', () {
      final res = TransactionResponse.fromJson({'cvm': 1, 'responseCode': '0'});
      expect(HobexReceipt.fromHps(res).needSignature, isTrue);
    });
  });

  group('Diagnosis.fromJson', () {
    test('Status & Test-Umgebung erkannt', () {
      final d = Diagnosis.fromJson({
        'deviceStatus': 'IN_OPERATION',
        'responseCode': '0',
        'host': 'https://tecstest.hobex.at',
        'hps': '1.8.4',
        'tid': '3600335',
      });
      expect(d.isInOperation, isTrue);
      expect(d.isAuthorized, isTrue);
      expect(d.isTestEnvironment, isTrue);
    });
  });
}
