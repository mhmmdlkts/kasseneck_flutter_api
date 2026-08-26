import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/hobex_hps.dart' show CardPaymentOutcome;

KasseneckApi apiWith(List<http.Response Function()> responses) {
  var i = 0;
  final mock = MockClient((_) async {
    final r = responses[i < responses.length ? i : responses.length - 1];
    i++;
    return r();
  });
  return KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
}

/// Vollstaendiges, gueltiges Beleg-JSON -- HobexReceipt.fromJson verlangt
/// jedes Feld (nicht nullbar), ein unvollstaendiger Rumpf wirft beim Parsen.
String receiptJson({required String responseCode, required String transactionId}) {
  return '{'
      '"transactionId":"$transactionId",'
      '"tid":"3600335",'
      '"receipt":"0001",'
      '"approvalCode":"123456",'
      '"reference":null,'
      '"transactionDate":"2026-08-26T10:00:00",'
      '"cardNumber":"1234",'
      '"cardExpiry":"12/30",'
      '"brand":"VISA",'
      '"cardIssuer":"Bank",'
      '"responseCode":"$responseCode",'
      '"transactionType":"purchase",'
      '"currency":"EUR",'
      '"amount":25,'
      '"tip":0,'
      '"cvm":"0"'
      '}';
}

void main() {
  group('Cloud-Zahlung mit geklaertem Ausgang', () {
    test('genehmigt -> approved', () async {
      final api = apiWith([
        () => http.Response('{"data":${receiptJson(responseCode: '0', transactionId: 'TX-1')}}', 200),
      ]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-1', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-1');
    });

    test('Abbruch, danach sagt der Status genehmigt -> approved', () async {
      final api = apiWith([
        () => throw Exception('Verbindung weg'),
        () => http.Response(
            '{"status":"success","data":${receiptJson(responseCode: '0', transactionId: 'TX-2')}}', 200),
      ]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-2', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
    });

    test('Abbruch und Status bleibt unbekannt -> unresolved, nie declined', () async {
      final api = apiWith([() => throw Exception('Verbindung weg')]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-3', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-3');
    });

    test('abgelehnt -> declined', () async {
      final api = apiWith([
        () => http.Response('{"data":${receiptJson(responseCode: '51', transactionId: 'TX-4')}}', 200),
      ]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-4', amount: 25);
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.transactionId, 'TX-4');
    });

    test('Statusabfrage scheitert dreimal in Folge -> unresolved, nie declined', () async {
      final api = apiWith([
        () => throw Exception('Verbindung weg'),
        () => throw Exception('Verbindung weg'),
        () => throw Exception('Verbindung weg'),
        () => throw Exception('Verbindung weg'),
      ]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-5', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-5');
    });

    test(
        'Status antwortet mit null (Dienst kennt Kennung nicht) -> weiter '
        'klaeren ohne Fehlerzaehler', () async {
      final api = apiWith([
        () => throw Exception('Verbindung weg'),
        // hobexGetStatus liefert null bei status != success -- keine Aussage,
        // die den Transportfehler-Zaehler erhoehen darf.
        () => http.Response('{"status":"pending"}', 200),
        () => http.Response(
            '{"status":"success","data":${receiptJson(responseCode: '0', transactionId: 'TX-6')}}', 200),
      ]);
      final res = await HobexCloudPayments(api, sleep: (_) async {})
          .pay(transactionId: 'TX-6', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      // Das unbekannte "pending" darf den Zaehler nicht angehoben haben --
      // sonst waere hier faelschlich ein Transportfehler protokolliert.
      expect(res.steps.any((s) => s.contains('gescheitert')), isFalse);
    });
  });
}
