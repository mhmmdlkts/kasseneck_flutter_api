import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/pos.dart'
    show KasseneckItem, KeckPaymentInput, KeckPaymentMethod, RegisterReceiptClient, VatRate;
import 'package:kasseneck_api/register.dart' show RegisterTransport;

/// `autoDeposits` und `onPremises` am Verkauf (11.24.0), Zwilling von
/// `createReceiptParams` im npm-Paket (1.32.0), beide Wege. Ohne Angabe bleibt
/// die Nutzlast byte-gleich.
final _v3 = Directory('test/fixtures/vertrag/v3');

http.Response _antwort(String datei) {
  final fall = ((jsonDecode(File('${_v3.path}/antworten/$datei.json').readAsStringSync()) as Map)['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((f) => f['name'] == 'sale_cash_tendered');
  return http.Response.bytes(utf8.encode(jsonEncode(fall['response'])), 200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final _semmeln = [KasseneckItem(name: 'Semmel', quantity: 4, priceCents: 79, vat: VatRate.vat10)];
const _bar = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 316, tenderedCents: 500)];

typedef _Weg = Future<Object?> Function(http.Client c, List<KasseneckItem> items, {bool? auto, bool? vorOrt});

final Map<String, (String, _Weg)> _wege = {
  'KasseneckApi.sellReceipt': ('belege', (c, items, {auto, vorOrt}) => KasseneckApi(
        apiKey: 'kr_test_x',
        cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
        httpClient: c,
      ).sellReceipt(items: items, payments: _bar, autoDeposits: auto, onPremises: vorOrt)),
  'RegisterReceiptClient.sell': ('kasse-belege', (c, items, {auto, vorOrt}) => RegisterReceiptClient(RegisterTransport(
        idToken: () async => 'eyJ-ID',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KECK-1',
        httpClient: c,
      )).sell(items: items, payments: _bar, autoDeposits: auto, onPremises: vorOrt)),
};

void main() {
  for (final MapEntry(key: weg, value: (datei, verkaufen)) in _wege.entries) {
    group(weg, () {
      test('autoDeposits und onPremises gehen hinaus, wenn gesetzt', () async {
        final log = <http.Request>[];
        await verkaufen(MockClient((r) async {
          log.add(r);
          return _antwort(datei);
        }), _semmeln, auto: true, vorOrt: false);
        expect(_params(log.single)['autoDeposits'], isTrue);
        expect(_params(log.single)['onPremises'], isFalse);
      });

      test('ohne Angabe fehlen beide Felder', () async {
        final log = <http.Request>[];
        await verkaufen(MockClient((r) async {
          log.add(r);
          return _antwort(datei);
        }), _semmeln);
        expect(_params(log.single).containsKey('autoDeposits'), isFalse);
        expect(_params(log.single).containsKey('onPremises'), isFalse);
      });

      test('Pfandzeile mit articleId wirft vor dem Senden', () async {
        var gesendet = false;
        final pfand = [KasseneckItem(name: 'Pfand', quantity: 1, priceCents: 25, vat: VatRate.vat20, kind: 'deposit', articleId: 'a1')];
        await expectLater(
          verkaufen(MockClient((r) async {
            gesendet = true;
            return _antwort(datei);
          }), pfand),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('invalid_deposit'))),
        );
        expect(gesendet, isFalse);
      });
    });
  }

  test('Vokabular des Vertrags nennt autoDeposits und onPremises', () {
    final voc = jsonDecode(File('${_v3.path}/v3-vokabular.json').readAsStringSync());
    final text = jsonEncode(voc);
    for (final feld in ['autoDeposits', 'onPremises']) {
      expect(text, contains('"$feld"'), reason: 'Vokabular nennt $feld');
    }
  });
}
