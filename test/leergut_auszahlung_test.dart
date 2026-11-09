import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/pos.dart'
    show KasseneckItem, KeckPaymentInput, KeckPaymentMethod, RegisterReceiptClient, VatRate;
import 'package:kasseneck_api/register.dart' show RegisterTransport;

/// Leergut-Auszahlung (11.24.1), Zwilling von `gepruefteZahlungen` im npm-Paket
/// (1.32.1) und von `pfand-core.istLeergutAuszahlung` im Backend, beide Wege.
final _v3 = Directory('test/fixtures/vertrag/v3');

http.Response _antwort(String datei) {
  final fall = ((jsonDecode(File('${_v3.path}/antworten/$datei.json').readAsStringSync()) as Map)['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((f) => f['name'] == 'sale_cash_tendered');
  return http.Response.bytes(utf8.encode(jsonEncode(fall['response'])), 200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final _leergut = [KasseneckItem(name: 'Leergut', quantity: 10, priceCents: -25, vat: VatRate.vat20, kind: 'deposit_return')];
final _ware = KasseneckItem(name: 'Semmel', quantity: 4, priceCents: 79, vat: VatRate.vat10);

typedef _Weg = Future<Object?> Function(http.Client c, List<KasseneckItem> items, List<KeckPaymentInput> payments);

final Map<String, (String, _Weg)> _wege = {
  'KasseneckApi.sellReceipt': ('belege', (c, items, payments) => KasseneckApi(
        apiKey: 'kr_test_x',
        cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
        httpClient: c,
      ).sellReceipt(items: items, payments: payments)),
  'RegisterReceiptClient.sell': ('kasse-belege', (c, items, payments) => RegisterReceiptClient(RegisterTransport(
        idToken: () async => 'eyJ-ID',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KECK-1',
        httpClient: c,
      )).sell(items: items, payments: payments)),
};

KeckPaymentInput _zahlung(int cents, {KeckPaymentMethod method = KeckPaymentMethod.cash, int? tendered, int? tip}) =>
    KeckPaymentInput(method: method, amountCents: cents, tenderedCents: tendered, tipCents: tip);

void main() {
  for (final MapEntry(key: weg, value: (datei, verkaufen)) in _wege.entries) {
    group(weg, () {
      Future<List<http.Request>> senden(List<KasseneckItem> items, List<KeckPaymentInput> payments) async {
        final log = <http.Request>[];
        await verkaufen(MockClient((r) async {
          log.add(r);
          return _antwort(datei);
        }), items, payments);
        return log;
      }

      test('eine negative Barzahlung ueber Leergut geht hinaus', () async {
        final log = await senden(_leergut, [_zahlung(-250)]);
        final z = (_params(log.single)['payments'] as List).single as Map;
        expect(z['amountCents'], -250);
        expect(z['method'], 'cash');
      });

      test('Karte, zwei Zahlungen, tendered, Trinkgeld, zu hoher Betrag: abgelehnt, nichts gesendet', () async {
        final faelle = <String, List<KeckPaymentInput>>{
          'bar': [_zahlung(-250, method: KeckPaymentMethod.creditCard)],
          'genau eine': [_zahlung(-150), _zahlung(-100)],
          'tenderedCents': [_zahlung(-250, tendered: -250)],
          'tipCents': [_zahlung(-250, tip: 10)],
          'Leergutsumme': [_zahlung(-251)],
        };
        for (final MapEntry(key: muster, value: payments) in faelle.entries) {
          var gesendet = false;
          await expectLater(
            verkaufen(MockClient((r) async {
              gesendet = true;
              return _antwort(datei);
            }), _leergut, payments),
            throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains(muster))),
            reason: muster,
          );
          expect(gesendet, isFalse, reason: muster);
        }
      });

      test('negative Barzahlung ohne Leergut bleibt abgelehnt', () async {
        var gesendet = false;
        await expectLater(
          verkaufen(MockClient((r) async {
            gesendet = true;
            return _antwort(datei);
          }), [_ware], [_zahlung(-250)]),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('amountCents'))),
        );
        expect(gesendet, isFalse);
      });

      test('Leergut mit Ware und positivem Betrag ist ein normaler Verkauf', () async {
        final log = await senden([_ware, ..._leergut], [_zahlung(66, tendered: 100)]);
        expect(((_params(log.single)['payments'] as List).single as Map)['amountCents'], 66);
      });
    });
  }
}
