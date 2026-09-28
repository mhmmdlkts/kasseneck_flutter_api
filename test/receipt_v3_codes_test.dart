import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart' show CancellationState;
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/src/receipt/codes.dart' show anmeldungUndRandCodes, cancellationErrorCodes, paymentErrorCodes, receiptEmailErrorCodes;

/// Kataloge und Fehlercodes der Belegwelt sind genau die des `/v3`-Vokabulars
/// (Zwilling von „Kataloge und Codes sind die des /v3-Vokabulars" in
/// `test/receipts-v3.test.ts` und `test/kassenweg-codes.ts` im npm-Paket).
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

/// Fehlercodes, die ein Fall des Kassenwegs im Vertrag zeigt.
Set<String> _kassenwegFaelle() {
  final codes = <String>{};
  for (final e in (_json('antworten/kasse.json')['endpoints'] as Map).values) {
    for (final f in ((e as Map)['cases'] as List).cast<Map<String, dynamic>>()) {
      final r = f['response'] as Map;
      if (r['status'] == 'error') codes.add(r['code'] as String);
    }
  }
  for (final f in (_json('antworten/kasse-belege.json')['cases'] as List).cast<Map<String, dynamic>>()) {
    final r = f['response'] as Map;
    if (r['status'] == 'error') codes.add(r['code'] as String);
  }
  return codes;
}

void main() {
  final vok = _json('v3-vokabular.json');
  final codes = (vok['errorCodes'] as Map).cast<String, dynamic>();
  List<String> liste(String name) => (codes[name] as List).cast<String>();

  test('Anmeldung und Rand: errorCodes.auth ohne Partner-Zugang und errorCodes.edge, sortiert', () {
    // errorCodes.auth fuehrt den Partner-Zugang am Ende: der Rest hinter dem
    // letzten Code, den ein Fall des Kassenwegs zeigt.
    final auth = liste('auth');
    final gesehen = _kassenwegFaelle();
    var letzter = -1;
    for (final (i, c) in auth.indexed) {
      if (gesehen.contains(c)) letzter = i;
    }
    final partner = auth.sublist(letzter + 1).toSet();
    expect(partner, hasLength(7));
    final soll = {...auth.where((c) => !partner.contains(c)), ...liste('edge')}.toList()..sort();
    expect(anmeldungUndRandCodes, soll);
  });

  test('jede Liste: Codes des Endpunkts, dann Anmeldung und Rand, dann die des Pakets', () {
    List<String> mitRand(List<String> eigen, List<String> paket) =>
        [...eigen, ...anmeldungUndRandCodes.where((c) => !eigen.contains(c)), ...paket];
    const signierend = ['route_missing', 'response_unreadable'];
    expect(clientErrorCodes, signierend.toSet());
    expect(cancellationErrorCodes, mitRand(liste('cancellation'), signierend));
    expect(paymentErrorCodes, mitRand(liste('payments'), ['route_missing']));
    expect(receiptEmailErrorCodes, mitRand(liste('receiptEmail'), ['route_missing']));
    expect(receiptEmailSendErrorCodes, liste('receiptEmail'));
    final je = (codes['receiptMessagesByEndpoint'] as Map).cast<String, dynamic>();
    final beleg = {...(je['createReceipt'] as List).cast<String>(), ...(je['getReceipt'] as List).cast<String>()}.toList()..sort();
    expect(receiptErrorCodes, mitRand(beleg, signierend));
    // Die oeffentlichen Namen zeigen auf dieselben Listen.
    expect(cancellationErrorCodes, same(cancellationErrorCodes));
    expect(paymentErrorCodes, same(paymentErrorCodes));
    expect(receiptEmailErrorCodes, same(receiptEmailErrorCodes));
  });

  test('jeder Fehlercode eines Belegfalls im Vertrag steht in einer Liste seines Endpunkts', () {
    final listen = <String, List<String>>{
      'createReceipt': [...receiptErrorCodes, ...paymentErrorCodes],
      'getReceipt': receiptErrorCodes,
      'cancelReceipt': [...cancellationErrorCodes, ...paymentErrorCodes],
      'sendReceiptEmail': receiptEmailErrorCodes,
    };
    var geprueft = 0;
    for (final datei in ['belege', 'kasse-belege', 'storno', 'belegmail']) {
      for (final f in (_json('antworten/$datei.json')['cases'] as List).cast<Map<String, dynamic>>()) {
        final r = f['response'] as Map;
        final liste = listen[f['endpoint']];
        if (r['status'] != 'error' || liste == null) continue;
        expect(liste, contains(r['code']), reason: '$datei/${f['name']}');
        geprueft++;
      }
    }
    expect(geprueft, greaterThan(20));
  });

  test('jeder Code ist ein /v3-Code (klein, englisch) oder einer des Pakets', () {
    final alle = liste('all').toSet();
    for (final code in [...cancellationErrorCodes, ...paymentErrorCodes, ...receiptEmailErrorCodes, ...receiptErrorCodes]) {
      expect(alle.contains(code) || clientErrorCodes.contains(code), isTrue, reason: code);
      expect(code, code.toLowerCase(), reason: code);
    }
    expect(receiptErrorCodes, contains('receipt_outcome_unknown'));
    expect(isReceiptErrorCode('receipt_outcome_unknown'), isTrue);
    expect(isReceiptErrorCode('RECEIPT_OUTCOME_UNKNOWN'), isFalse);
  });

  test('Kataloge: Stornogruende, Stornostand, Mailweg, Layout-Ton wie das Vokabular', () {
    final kataloge = (vok['catalogs'] as Map).cast<String, dynamic>();
    List<String> werte(String k) => (kataloge[k] as Map).values.cast<String>().toList();
    expect(cancellationReasons.keys.toList(), werte('STORNO_GRUND'));
    expect(cancellationStatuses, werte('STORNO_STAND'));
    expect([for (final s in CancellationState.values) if (s != CancellationState.unknown) s.name], werte('STORNO_STAND'));
    expect(receiptEmailVias, werte('MAILWEG'));
    expect(LayoutBannerTone.values.map((t) => t.wire).toList(), werte('LAYOUT_TON'));
  });
}
