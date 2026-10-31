import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/pos.dart'
    show KasseneckItem, KasseneckReceipt, KeckPaymentInput, KeckPaymentMethod, RegisterReceiptClient, VatRate;
import 'package:kasseneck_api/register.dart' show RegisterTransport;

/// Idempotenz am Verkauf (seit 11.14): `idempotencyKey` an
/// [KasseneckApi.sellReceipt] und [RegisterReceiptClient.sell], `replayed`
/// am gelesenen Beleg. Zwilling der Faelle „idempotencyKey“ und „replayed“ in
/// `test/client-receipts.test.ts` des npm-Pakets (1.22.0). Die Regel des
/// Schluessels ist die des Servers (`beleg-idempotenz-core`): Text, nicht nur
/// Leerraum, hoechstens 120 Zeichen, unveraendert gesendet. Einen falschen Typ
/// (Zahl, Liste) laesst schon `String?` nicht zu; der npm-Zwilling prueft ihn.
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _verkauf(String datei) => (_json('antworten/$datei.json')['cases'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((f) => f['name'] == 'sale_cash_tendered');

/// Antwort des Vertragsfalls; [replayed] setzt das Feld wie der Server bei einer Wiederholung.
http.Response _antwort(Map<String, dynamic> fall, {Object? replayed}) {
  final rumpf = jsonDecode(jsonEncode(fall['response'])) as Map<String, dynamic>;
  if (replayed != null) (rumpf['data'] as Map<String, dynamic>)['replayed'] = replayed;
  return http.Response.bytes(utf8.encode(jsonEncode(rumpf)), 200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final _semmeln = [KasseneckItem(name: 'Semmel', quantity: 4, priceCents: 79, vat: VatRate.vat10)];
const _bar = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 316, tenderedCents: 500)];

/// Ein Verkauf ueber einen der beiden Wege; liefert den Beleg und die gesendeten Anfragen.
typedef _Weg = Future<KasseneckReceipt> Function(http.Client client, String? schluessel);

final Map<String, _Weg> _wege = {
  'KasseneckApi.sellReceipt': (client, schluessel) async => (await KasseneckApi(
        apiKey: 'kr_test_x',
        cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
        httpClient: client,
      ).sellReceipt(items: _semmeln, payments: _bar, idempotencyKey: schluessel))!,
  'RegisterReceiptClient.sell': (client, schluessel) => RegisterReceiptClient(RegisterTransport(
        idToken: () async => 'eyJ-ID',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KECK-1',
        httpClient: client,
      )).sell(items: _semmeln, payments: _bar, idempotencyKey: schluessel),
};

String _datei(String weg) => weg.startsWith('Register') ? 'kasse-belege' : 'belege';

Matcher _anfragefehler() => isA<KasseneckValidationError>()
    .having((e) => e.kind, 'kind', 'request')
    .having((e) => e.functionName, 'functionName', 'createReceipt')
    .having((e) => e.reason, 'reason', contains('idempotencyKey'));

void main() {
  for (final MapEntry(key: weg, value: verkaufen) in _wege.entries) {
    group(weg, () {
      final fall = _verkauf(_datei(weg));

      test('idempotencyKey geht unveraendert hinaus; ohne Angabe bleibt die Nutzlast wie im Vertrag', () async {
        // Der Server hasht den Schluessel, wie er ankommt: nie kuerzen, nie trimmen.
        for (final schluessel in ['ersatzbeleg-17', ' ersatzbeleg-17 ', 'x' * 120, '€' * 120, '😀' * 60]) {
          final log = <http.Request>[];
          await verkaufen(MockClient((r) async {
            log.add(r);
            return _antwort(fall);
          }), schluessel);
          expect(log, hasLength(1), reason: schluessel);
          expect(_params(log.single)['idempotencyKey'], schluessel);
        }
        final log = <http.Request>[];
        await verkaufen(MockClient((r) async {
          log.add(r);
          return _antwort(fall);
        }), null);
        expect(_params(log.single).containsKey('idempotencyKey'), isFalse);
      });

      test('leer, nur Leerraum oder laenger als 120 Zeichen wirft vor dem Senden', () async {
        // Laenge in UTF-16-Einheiten wie am Server (String.length): 61 Emoji sind 122 Einheiten.
        for (final schluessel in ['', '   ', 'x' * 121, '😀' * 61]) {
          var gesendet = 0;
          await expectLater(
            verkaufen(MockClient((r) async {
              gesendet++;
              return _antwort(fall);
            }), schluessel),
            throwsA(_anfragefehler()),
            reason: schluessel,
          );
          expect(gesendet, 0, reason: schluessel);
        }
      });

      test('replayed: true nur, wenn der Server genau true meldet; nicht in toJson', () async {
        final zweites = await verkaufen(MockClient((_) async => _antwort(fall, replayed: true)), 'vorgang-4711');
        expect(zweites.replayed, isTrue);
        expect(zweites.receiptId, (((fall['response'] as Map)['data'] as Map)['receipt'] as Map)['receiptId']);
        // Ein gespeicherter Beleg ist keine Wiederholung: das Merkmal gehoert zur Antwort, nicht zum Beleg.
        expect(zweites.toJson().containsKey('replayed'), isFalse);
        expect(KasseneckReceipt.fromJson(zweites.toJson()).replayed, isFalse);
        for (final wert in [null, false, 'true', 1]) {
          final beleg = await verkaufen(MockClient((_) async => _antwort(fall, replayed: wert)), 'vorgang-4711');
          expect(beleg.replayed, isFalse, reason: '$wert');
        }
      });
    });
  }
}
