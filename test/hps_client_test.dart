import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// HpsClient gegen einen MockClient: Verben, URLs, Body-Struktur und die
/// komplette Fehler-Maschinerie — ohne echtes Terminal.

({HpsClient client, List<http.Request> log}) clientWith({String body = '{}', int status = 200, Uri? base, Duration? timeout}) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(body, status, headers: {'content-type': 'application/json'});
  });
  return (
    client: HpsClient(tid: '3600335', baseUrl: base, httpClient: mock, timeout: timeout ?? const Duration(seconds: 5)),
    log: log,
  );
}

Map<String, dynamic> txBody(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['transaction'] as Map<String, dynamic>;

void main() {
  group('Transaktions-Requests: Verb, URL, Body', () {
    test('payment: POST + transactionType=1 + EUR-Default + auto-transactionId', () async {
      final c = clientWith();
      await c.client.payment(amount: 12.5);
      final r = c.log.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'http://127.0.0.1:8080/api/transaction/payment');
      final tx = txBody(r);
      expect(tx['tid'], '3600335');
      expect(tx['amount'], 12.5);
      expect(tx['currency'], 'EUR');
      expect(tx['transactionType'], 1);
      expect(RegExp(r'^\d+$').hasMatch(tx['transactionId'] as String), isTrue);
    });

    test('payment: tip/reference/eigene transactionId/currency werden uebernommen', () async {
      final c = clientWith();
      await c.client.payment(amount: 10, tip: 1.5, reference: 'Bon 7', transactionId: 'TX-7', currency: 'CHF');
      final tx = txBody(c.log.single);
      expect(tx['tip'], 1.5);
      expect(tx['reference'], 'Bon 7');
      expect(tx['transactionId'], 'TX-7');
      expect(tx['currency'], 'CHF');
    });

    test('refund: POST refund + originalTransactionId', () async {
      final c = clientWith();
      await c.client.refund(amount: 5, originalTransactionId: 'ORIG-1');
      final r = c.log.single;
      expect(r.url.path, '/api/transaction/refund');
      expect(txBody(r)['originalTransactionId'], 'ORIG-1');
      expect(txBody(r).containsKey('transactionType'), isFalse);
    });

    test('preAuth / Capture / Cancel: Pfade und Verben', () async {
      final c = clientWith();
      await c.client.preAuth(amount: 50, transactionId: 'PA-1');
      await c.client.preAuthCapture(preAuthTransactionId: 'PA-1', amount: 50);
      await c.client.preAuthCancel(preAuthTransactionId: 'PA-1', amount: 50);
      expect(c.log[0].method, 'POST');
      expect(c.log[0].url.path, '/api/transaction/preauth');
      expect(c.log[1].url.path, '/api/transaction/preauthcapture');
      expect(txBody(c.log[1])['transactionId'], 'PA-1');
      expect(c.log[2].method, 'DELETE');
      expect(c.log[2].url.path, '/api/transaction/preauth');
    });

    test('cancel: DELETE auf payment/{tid}/{tx} + technicalCancel-Query', () async {
      final c = clientWith();
      await c.client.cancel(transactionId: 'TX-9');
      await c.client.cancel(transactionId: 'TX-9', technicalCancel: true);
      expect(c.log[0].method, 'DELETE');
      expect(c.log[0].url.path, '/api/transaction/payment/3600335/TX-9');
      expect(c.log[0].url.queryParameters.containsKey('technicalCancel'), isFalse);
      expect(c.log[1].url.queryParameters['technicalCancel'], 'true');
    });

    test('abort liefert die transactionId aus der Antwort', () async {
      final c = clientWith(body: '{"transactionId": "ABORTED-1"}');
      final id = await c.client.abort(transactionId: 'TX-1');
      expect(id, 'ABORTED-1');
      expect(c.log.single.url.path, '/api/transaction/abort/3600335/TX-1');
    });

    test('transactionStatus: GET auf v2-Endpoint', () async {
      final c = clientWith(body: '{"responseCode": "0"}');
      final res = await c.client.transactionStatus(transactionId: 'TX-1');
      expect(c.log.single.method, 'GET');
      expect(c.log.single.url.path, '/api/v2/transactions/3600335/TX-1');
      expect(res.isApproved, isTrue);
    });

    test('diagnosis: GET + Parsing', () async {
      final c = clientWith(body: '{"deviceStatus": "IN_OPERATION", "host": "https://tecstest.x"}');
      final d = await c.client.diagnosis();
      expect(c.log.single.url.path, '/api/terminals/3600335/diagnosis');
      expect(d.isInOperation, isTrue);
      expect(d.isTestEnvironment, isTrue);
    });

    test('batchTotals/closeBatch: Sekunden-ISO ohne Millis im Pfad', () async {
      final c = clientWith();
      final since = DateTime(2026, 6, 12, 9, 5, 3, 999);
      await c.client.batchTotals(since);
      await c.client.closeBatch(since);
      expect(c.log[0].url.path, '/api/terminals/3600335/batchtotal/2026-06-12T09:05:03');
      expect(c.log[1].url.path, '/api/terminals/3600335/closebatch/2026-06-12T09:05:03');
    });
  });

  group('URL-Joining (Basis mit/ohne Slash)', () {
    test('Basis mit trailing Slash -> kein Doppelslash', () async {
      final c = clientWith(base: Uri.parse('http://192.168.0.5:8080/'));
      await c.client.diagnosis();
      expect(c.log.single.url.toString(), 'http://192.168.0.5:8080/api/terminals/3600335/diagnosis');
    });
    test('Basis mit Pfad-Praefix bleibt erhalten', () async {
      final c = clientWith(base: Uri.parse('http://h:1/prefix'));
      await c.client.diagnosis();
      expect(c.log.single.url.path, '/prefix/api/terminals/3600335/diagnosis');
    });
  });

  group('Fehler-Maschinerie', () {
    test('non-2xx mit JSON-message -> HpsHttpException mit dieser Message', () async {
      final c = clientWith(body: '{"message": "Terminal busy"}', status: 400);
      expect(
        () => c.client.payment(amount: 1),
        throwsA(isA<HpsHttpException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', 'Terminal busy')),
      );
    });
    test('non-2xx mit leerem Body -> "HTTP <code>"', () async {
      final c = clientWith(body: '', status: 503);
      expect(
        () => c.client.payment(amount: 1),
        throwsA(isA<HpsHttpException>().having((e) => e.message, 'message', 'HTTP 503')),
      );
    });
    test('non-2xx mit Rohtext -> Rohtext als Message', () async {
      final c = clientWith(body: 'Internal Failure', status: 500);
      expect(
        () => c.client.payment(amount: 1),
        throwsA(isA<HpsHttpException>().having((e) => e.message, 'message', 'Internal Failure')),
      );
    });
    test('Netzwerkfehler -> HpsConnectionException', () async {
      final mock = MockClient((_) async => throw http.ClientException('connection refused'));
      final client = HpsClient(tid: '1', httpClient: mock);
      expect(() => client.payment(amount: 1), throwsA(isA<HpsConnectionException>()));
    });
    test('Timeout -> HpsConnectionException', () async {
      final mock = MockClient((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final client = HpsClient(tid: '1', httpClient: mock, timeout: const Duration(milliseconds: 20));
      expect(() => client.payment(amount: 1), throwsA(isA<HpsConnectionException>()));
    });
    test('leerer 200-Body -> leere Map -> Status "in progress"', () async {
      final c = clientWith(body: '');
      final res = await c.client.payment(amount: 1);
      expect(res.isInProgress, isTrue);
    });
    test('Nicht-Map-JSON wird unter value gekapselt', () async {
      final c = clientWith(body: '"plain"');
      final totals = await c.client.batchTotals(DateTime(2026));
      expect(totals, {'value': 'plain'});
    });
    test('Exception-toString-Formate', () {
      expect(const HpsException('x').toString(), 'HpsException: x');
      expect(HpsHttpException(503, 'down').toString(), 'HpsHttpException(503): down');
      expect(HpsConnectionException('cause').toString(), contains('Could not reach'));
    });
  });

  group('close()', () {
    test('injizierter Client wird NICHT geschlossen, eigener schon', () {
      final tracking = _TrackingClient();
      HpsClient(tid: '1', httpClient: tracking).close();
      expect(tracking.closed, isFalse);
      // eigener Client: close() darf nicht werfen
      HpsClient(tid: '1').close();
    });
  });

  group('HpsTransactionType-Codes (API-Kontrakt)', () {
    test('numerische Codes', () {
      expect(HpsTransactionType.sale.code, 1);
      expect(HpsTransactionType.preAuth.code, 2);
      expect(HpsTransactionType.preAuthCancel.code, 7);
      expect(HpsTransactionType.preAuthCapture.code, 8);
    });
  });
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  @override
  void close() => closed = true;
}
