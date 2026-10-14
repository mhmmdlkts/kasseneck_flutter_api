import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Storno mit oder ohne Trinkgeld (Schichten-Spec, Nachtrag 5): die Regeln der
/// beiden Fragen gegen die gemeinsamen Faelle des Vertrags
/// (`cancellation-tip-cases.json`, 1:1 wie im npm-Paket 1.11.0) und die
/// Parameter `refundTip`/`tipRefundSource` an `cancelReceipt`.
final _faelle = jsonDecode(File('test/fixtures/vertrag/cancellation-tip-cases.json').readAsStringSync()) as Map<String, dynamic>;

const _jetzt = 1800000000000;

/// Die Faelle tragen nur, was die Regeln lesen; hier kommen die Pflichtfelder dazu.
KasseneckReceipt _beleg(String name) {
  final roh = (_faelle['receipts'] as Map<String, dynamic>)[name] as Map<String, dynamic>?;
  if (roh == null) throw StateError('Beleg $name fehlt in den Faellen');
  return KasseneckReceipt.fromJson({
    'receipt': {
      'qr': 'QR', 'sig': 'SIG', 'certificateSerialNumber': 'C', 'signaturePreviousReceipt': 'P',
      'turnoverCounterAES256ICM': 'T', 'timeStamp': '2026-10-14T10:00:00', 'cashregisterId': 'kasse-1',
      'receiptType': 'standard', 'receiptId': 'kasse-1-ID-12', 'fullReceiptId': 'F',
      ...roh,
    },
  });
}

List<Map<String, int>>? _alsListe(List<CancellationItem>? items) =>
    items == null ? null : [for (final p in items) {'index': p.index, 'quantity': p.quantity}];

List<CancellationItem>? _positionen(Object? roh) => roh is List
    ? [for (final p in roh.cast<Map<String, dynamic>>()) (index: p['index'] as int, quantity: p['quantity'] as int)]
    : null;

List<Map<String, int>>? _ohneWahl(Object? roh) => roh is List
    ? [for (final p in roh.cast<Map<String, dynamic>>()) {'index': p['index'] as int, 'quantity': p['quantity'] as int}]
    : null;

KeckPaymentInput _zahlung(Map<String, dynamic> z) => KeckPaymentInput(
      method: KeckPaymentMethod.values.byName(z['method'] as String),
      amountCents: z['amountCents'] as int,
      refundOf: z['refundOf'] as String?,
      provider: z['provider'] == null ? null : CreditCardProvider.values.byName(z['provider'] as String),
    );

({RegisterReceiptClient client, List<http.Request> log}) _client() {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(
      jsonEncode({
        'status': 'success',
        'data': {
          'receipt': {
            'receiptId': 'KASSE1-ID-43', 'fullReceiptId': 'voll-43', 'receiptType': 'cancellation', 'cashregisterId': 'KASSE1',
            'timeStamp': '2026-10-14T10:15:00', 'paymentMethod': 'cash',
            'items': [{'name': 'Kaffee', 'quantity': 2, 'unitPriceCents': -280, 'vatRate': 20}],
            'qr': '_R1-AT1_KASSE1_...', 'sig': 'sig', 'certificateSerialNumber': 'cert', 'signaturePreviousReceipt': 'prev',
            'turnoverCounterAES256ICM': 'aes', 'signatureSuccess': true,
          },
          'cancellationOf': {'receiptId': 'KASSE1-ID-42', 'fullReceiptId': 'voll-42'},
          'remaining': [0, 0, 1],
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

void main() {
  test('openStaffTipCents: alle Faelle des Vertrags', () {
    final liste = (_faelle['openStaffTipCents'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(6));
    for (final f in liste) {
      expect(openStaffTipCents(_beleg(f['receipt'] as String), nowMs: _jetzt), f['expected'], reason: f['receipt'] as String);
    }
  });

  test('asksRefundTip: alle Faelle des Vertrags (mit Wertgutschein keine Frage, R59)', () {
    final liste = (_faelle['asksRefundTip'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(7));
    for (final f in liste) {
      expect(asksRefundTip(_beleg(f['receipt'] as String), nowMs: _jetzt), f['expected'], reason: f['receipt'] as String);
    }
  });

  test('cancellationItemsForTip: alle Faelle des Vertrags (Rueckgabe-Wahl geht in Dart getrennt hinaus)', () {
    final liste = (_faelle['cancellationItemsForTip'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(10));
    for (final f in liste) {
      final raus = cancellationItemsForTip(_beleg(f['receipt'] as String), _positionen(f['items']), refundTip: f['refundTip'] as bool, nowMs: _jetzt);
      expect(_alsListe(raus), _ohneWahl(f['expected']), reason: jsonEncode(f));
    }
  });

  test('asksTipRefundSource: alle Faelle des Vertrags', () {
    final liste = (_faelle['asksTipRefundSource'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(8));
    for (final f in liste) {
      expect(asksTipRefundSource(_beleg(f['receipt'] as String), f['cashRefundCents'] as int, nowMs: _jetzt), f['expected'], reason: jsonEncode(f));
    }
  });

  test('cancellationCashRefundCents: alle Faelle des Vertrags', () {
    final liste = (_faelle['cancellationCashRefundCents'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(6));
    for (final f in liste) {
      final zahlungen = f['payments'] is List ? [for (final z in (f['payments'] as List).cast<Map<String, dynamic>>()) _zahlung(z)] : null;
      expect(cancellationCashRefundCents(_beleg(f['receipt'] as String), zahlungen, f['dueCents'] as int), f['expected'], reason: jsonEncode(f));
    }
  });

  test('Quellen und Fehlercodes wie unter /v3, Texte aus dem Katalog', () {
    expect(tipRefundSources, ['drawer', 'employee']);
    expect(isTipRefundSource('employee'), isTrue);
    expect(isTipRefundSource('mitarbeiter'), isFalse);
    final ab = cancellationErrorCodes.indexOf('invalid_return_disposition');
    expect(cancellationErrorCodes.sublist(ab + 1, ab + 5),
        ['tip_refund_conflict', 'invalid_tip_refund_source', 'tip_refund_source_requires_cash', 'tip_keep_not_possible_with_voucher']);
    expect(labelText('cancellation.tip_refund_question'), 'Trinkgeld auch zurückgeben?');
    expect(labelText('cancellation.tip_source_employee'), 'Gibt die Mitarbeiterin direkt');
    expect(messageText('cancellation.tip_source_missing'), 'Bitte wählen: Woher kommt das Trinkgeld zurück?');
    expect(messageText('tip.kept_setting_hint'), contains('zählt nicht ins Soll der Lade'));
    expect(messageText('cancellation.tip_refunded_with_voucher'), 'Beleg mit Gutschein: Das Trinkgeld wird mitstorniert.');
    expect(labelText('cancellation.tip_stays'), 'bleibt');
    expect(labelText('shift_receipt.tip_refunded_by_employee'), 'selbst zurückgegeben');
  });

  group('cancelReceipt: refundTip und tipRefundSource', () {
    test('gehen hinaus; ohne beides bleibt die Nutzlast gleich', () async {
      final f = _client();
      await f.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled', refundTip: true, tipRefundSource: 'employee');
      await f.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled', refundTip: false, items: const [(index: 0, quantity: 2)]);
      await f.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled');
      expect(_params(f.log[0]), {'cashregisterId': 'KASSE1', 'originalReceiptId': 'KASSE1-ID-42', 'reason': 'customer_cancelled', 'refundTip': true, 'tipRefundSource': 'employee'});
      expect(_params(f.log[1]), {
        'cashregisterId': 'KASSE1', 'originalReceiptId': 'KASSE1-ID-42', 'reason': 'customer_cancelled', 'items': [{'index': 0, 'quantity': 2}], 'refundTip': false,
      });
      expect(_params(f.log[2]), {'cashregisterId': 'KASSE1', 'originalReceiptId': 'KASSE1-ID-42', 'reason': 'customer_cancelled'});
    });

    test('falsche Wahl wirft vor dem Senden', () async {
      final f = _client();
      await expectLater(
        f.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled', tipRefundSource: 'mitarbeiter'),
        throwsA(isA<KasseneckValidationError>()),
      );
      await expectLater(
        f.client.cancelReceipt(originalReceiptId: 'KASSE1-ID-42', reason: 'customer_cancelled', refundTip: false, tipRefundSource: 'drawer'),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });
  });
}
