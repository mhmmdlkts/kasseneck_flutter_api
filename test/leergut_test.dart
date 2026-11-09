import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';
import 'package:kasseneck_api/src/v3.dart' show unknownOutcomeCalls;

/// Leergut-Codes: die Zuordnung eines Scans gegen die Pruefaelle des npm-Pakets
/// (`return-code-cases.json`) und die beiden Aufrufe der Kasse. Zwilling von
/// `test/leergut.test.ts`.

final _datei = jsonDecode(File('test/fixtures/vertrag/return-code-cases.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _map(Object? w) => (w as Map).cast<String, dynamic>();

({RegisterReceiptClient client, List<http.Request> log}) _kasse(Object antwort) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(jsonEncode(antwort), 200, headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
  });
  return (
    client: RegisterReceiptClient(
      RegisterTransport(idToken: () async => 'id-token-1', sessionId: () async => 'sess-1', cashregisterId: 'KASSE1', httpClient: mock),
    ),
    log: log,
  );
}

Map<String, dynamic> _params(http.Request r) => _map(jsonDecode(r.body)['params']);

void main() {
  final faelle = (_datei['cases'] as List).cast<Map<String, dynamic>>();

  test('die Datei hat ihre Faelle', () => expect(faelle.length, 12));

  for (final f in faelle) {
    test('Leergut-Scan: ${f['name']}', () {
      final i = _map(f['input']);
      final r = matchReturnCode(
        i['code'] as String,
        articles: [for (final a in i['articles'] as List) PosArticle.fromJson(_map(a))],
        groups: [for (final g in i['groups'] as List) ArticleGroup.fromJson(_map(g))],
        learned: [for (final l in i['learned'] as List) ReturnCode.fromJson(l)!],
        depositTypes: [
          for (final t in i['depositTypes'] as List)
            DepositType(id: _map(t)['id'] as String, kind: 'reusable', name: '', active: _map(t)['active'] == true),
        ],
      );
      final soll = _map(f['expected']);
      if (soll['unknown'] == true) {
        expect(r.unknown, isTrue);
        expect(r.entries, isNull);
      } else {
        expect(r.unknown, isFalse);
        expect(
          [for (final e in r.entries!) {'depositTypeId': e.depositTypeId, 'quantity': e.quantity}],
          soll['entries'],
        );
      }
    });
  }

  group('Aufrufe', () {
    test('learnReturnCode sendet gtin und depositTypeId an learnMyLeergutCode', () async {
      final k = _kasse({'status': 'success', 'data': {'gtin': '9012345001025', 'depositTypeId': 'flasche'}});
      final r = await k.client.learnReturnCode(const ReturnCode(gtin: '9012345001025', depositTypeId: 'flasche'));
      expect(r, const ReturnCode(gtin: '9012345001025', depositTypeId: 'flasche'));
      expect(k.log.single.url.toString(), endsWith('/learnMyLeergutCode'));
      expect(_params(k.log.single)['gtin'], '9012345001025');
      expect(_params(k.log.single)['depositTypeId'], 'flasche');
    });

    test('learnReturnCode prueft die Form vor dem Senden', () async {
      final k = _kasse({'status': 'success', 'data': {}});
      for (final falsch in const [
        ReturnCode(gtin: '9012345001024', depositTypeId: 'flasche'),
        ReturnCode(gtin: '9012345001025', depositTypeId: ''),
      ]) {
        await expectLater(k.client.learnReturnCode(falsch), throwsA(isA<KasseneckValidationError>()));
      }
      expect(k.log, isEmpty);
    });

    test('listReturnCodes liest codes und ueberspringt Unlesbares', () async {
      final k = _kasse({
        'status': 'success',
        'data': {
          'codes': [
            {'gtin': '9012345001025', 'depositTypeId': 'flasche'},
            {'gtin': 5},
            null,
          ],
        },
      });
      expect(await k.client.listReturnCodes(), [const ReturnCode(gtin: '9012345001025', depositTypeId: 'flasche')]);
      expect(k.log.single.url.toString(), endsWith('/listMyLeergutCodes'));
      expect(await _kasse({'status': 'success', 'data': {}}).client.listReturnCodes(), isEmpty);
    });

    test('Fehlercodes des Pfands kommen mit ihrem Code an und haben einen Satz', () async {
      final k = _kasse({'status': 'error', 'code': 'deposit_type_not_found', 'message': 'x'});
      await expectLater(
        k.client.learnReturnCode(const ReturnCode(gtin: '9012345001025', depositTypeId: 'weg')),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'deposit_type_not_found')),
      );
      for (final code in ['deposit_not_enabled', 'deposit_type_not_found', 'deposit_set_by_server', 'invalid_deposit_quantity', 'deposit_return_not_offered', 'deposit_type_not_issued', 'deposit_follows_item', 'invalid_deposit']) {
        expect(isPosErrorCode(code), isTrue, reason: code);
        final key = depositErrorMessage(code);
        expect(key, isNotNull, reason: code);
        expect(messageText(key!), matches(RegExp(r'^[A-ZÄÖÜ].*[.!?]$')), reason: code);
      }
      expect(depositErrorMessage('server_error'), isNull);
      expect(depositErrorMessage(null), isNull);
      for (final code in ['deposit_not_enabled', 'deposit_return_not_offered', 'deposit_set_by_server', 'deposit_type_not_found', 'deposit_type_not_issued', 'invalid_deposit', 'invalid_deposit_quantity', 'invalid_item_kind']) {
        expect(isReceiptErrorCode(code), isTrue, reason: code);
      }
    });

    test('learnMyLeergutCode hat unklaren Ausgang, listMyLeergutCodes nicht', () {
      expect(unknownOutcomeCalls, contains('learnMyLeergutCode'));
      expect(unknownOutcomeCalls, isNot(contains('listMyLeergutCodes')));
    });
  });
}
