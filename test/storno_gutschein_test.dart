import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

// Rueckgabe als Gutschein (npm 1.25.0): cancelReceipt mit refundAs voucher und idempotencyKey, Ergebnis
// mit issuedVouchers und replayed; die Kasseneinstellung liest vouchers.returnType.

({RegisterReceiptClient client, List<http.Request> log}) _client(Map<String, Object?> zusatz) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(
      jsonEncode({
        'status': 'success',
        'data': {
          'receipt': {
            'receiptId': 'KASSE1-ID-43', 'fullReceiptId': 'voll-43', 'receiptType': 'cancellation', 'cashregisterId': 'KASSE1',
            'timeStamp': '2026-11-02T10:15:00', 'paymentMethod': 'cash', 'payments': [],
            'items': [{'name': 'Torte', 'quantity': 1, 'unitPriceCents': -2490, 'vatRate': 10}],
            'vouchers': [{'action': 'redeem', 'type': 'value', 'voucherType': 'multi_purpose', 'valueCents': 2490, 'value': 24.9, 'name': 'Gutschein', 'code': '····-····-2D9A', 'codeSuffix': '2D9A', 'voucherId': 'g1', 'fromReturn': true}],
            'qr': '_R1-AT1_KASSE1_...', 'sig': 'sig', 'certificateSerialNumber': 'cert', 'signaturePreviousReceipt': 'prev',
            'turnoverCounterAES256ICM': 'aes', 'signatureSuccess': true,
          },
          'cancellationOf': {'receiptId': 'KASSE1-ID-42', 'fullReceiptId': 'voll-42'},
          'remaining': [0],
          ...zusatz,
        },
      }),
      200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
    );
  });
  return (
    client: RegisterReceiptClient(
      RegisterTransport(idToken: () async => 'id-token-1', sessionId: () async => 'sess-1', cashregisterId: 'KASSE1', httpClient: mock),
    ),
    log: log,
  );
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

const _gutschein = {
  'id': 'g1', 'code': 'K7QM-4XRP-2D9A', 'type': 'multi_purpose', 'index': 0, 'codeSuffix': '2D9A', 'faceValueCents': 2490,
  'typeId': 's1', 'typeName': 'Rückgabe', 'fromReturn': true,
  'validity': {'pattern': '1+3', 'redeemableYears': 1, 'redeemableUntil': '2027-11-02', 'refundableUntil': '2030-11-02', 'validUntil': null},
};

void main() {
  test('refundAs voucher und idempotencyKey gehen hinaus, der Gutschein mit Code kommt zurueck', () async {
    final c = _client({'issuedVouchers': [_gutschein]});
    final r = await c.client.cancelReceipt(
        originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled', refundAs: 'voucher', idempotencyKey: 'storno-k-1');
    expect(_params(c.log.single), containsPair('refundAs', 'voucher'));
    expect(_params(c.log.single), containsPair('idempotencyKey', 'storno-k-1'));
    expect(r.issuedVouchers, hasLength(1));
    final g = r.issuedVouchers.single;
    expect((g.id, g.code, g.codeSuffix, g.faceValueCents, g.typeName, g.fromReturn, g.reprintRequired),
        ('g1', 'K7QM-4XRP-2D9A', '2D9A', 2490, 'Rückgabe', true, false));
    expect(g.validity?.redeemableUntil, '2027-11-02');
    expect(r.replayed, isFalse);
    expect(r.receipt.vouchers!.single.fromReturn, isTrue);
  });

  test('Wiederholung: derselbe Beleg, Gutschein ohne Code mit reprintRequired, replayed', () async {
    final c = _client({'replayed': true, 'issuedVouchers': [{'id': 'g1', 'codeSuffix': '2D9A', 'faceValueCents': 2490, 'fromReturn': true, 'reprintRequired': true}]});
    final r = await c.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'other', refundAs: 'voucher', idempotencyKey: 'k');
    expect(r.replayed, isTrue);
    expect(r.issuedVouchers.single.code, isNull);
    expect(r.issuedVouchers.single.reprintRequired, isTrue);
  });

  test('ohne refundAs: keine neuen Felder, keine Gutscheine', () async {
    final c = _client({});
    final r = await c.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error');
    expect(_params(c.log.single).containsKey('refundAs'), isFalse);
    expect(_params(c.log.single).containsKey('idempotencyKey'), isFalse);
    expect(r.issuedVouchers, isEmpty);
  });

  test('refundAs nur voucher, nur mit Schluessel (1 bis 120 Zeichen), nie mit payments', () async {
    final c = _client({});
    Future<void> nein(Future<Object?> Function() f) => expectLater(f(), throwsA(isA<KasseneckValidationError>()));
    await nein(() => c.client.cancelReceipt(originalReceiptId: 'R', reason: 'other', refundAs: 'cash', idempotencyKey: 'k'));
    await nein(() => c.client.cancelReceipt(originalReceiptId: 'R', reason: 'other', refundAs: 'voucher'));
    await nein(() => c.client.cancelReceipt(originalReceiptId: 'R', reason: 'other', refundAs: 'voucher', idempotencyKey: ''));
    await nein(() => c.client.cancelReceipt(originalReceiptId: 'R', reason: 'other', refundAs: 'voucher', idempotencyKey: 'x' * 121));
    await nein(() => c.client.cancelReceipt(
        originalReceiptId: 'R', reason: 'other', refundAs: 'voucher', idempotencyKey: 'k',
        payments: [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -100)]));
    expect(c.log, isEmpty);
  });

  test('Kasseneinstellung: returnType gelesen, fehlt sonst', () {
    const basis = {'sale': false, 'valueVoucherType': null, 'vatRateBp': null};
    expect(PosVoucherSettings.fromJson({...basis, 'returnType': {'typeId': 's1', 'typeName': 'Rückgabe'}}).returnType?.typeName, 'Rückgabe');
    expect(PosVoucherSettings.fromJson(basis).returnType, isNull);
    expect(PosVoucherSettings.fromJson({...basis, 'returnType': {'typeId': ''}}).returnType, isNull);
  });

  test('Text je Code: cancellationErrorMessage', () {
    expect(cancellationErrorMessage('refund_as_voucher_amount'), 'cancellation.voucher_amount');
    expect(cancellationErrorMessage('idempotency_conflict'), 'cancellation.input_rejected');
    expect(cancellationErrorMessage('cancellation_outcome_unknown'), 'cancellation.outcome_unknown');
  });
}
