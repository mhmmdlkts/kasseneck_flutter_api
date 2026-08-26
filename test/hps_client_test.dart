import 'dart:async';
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

    test('cancel: DELETE auf payment/{tid}/{tx} + amount/currency/technicalCancel-Query', () async {
      final c = clientWith();
      await c.client.cancel(transactionId: 'TX-9', amount: 1.5);
      await c.client.cancel(transactionId: 'TX-9', amount: 1.5, technicalCancel: true);
      expect(c.log[0].method, 'DELETE');
      expect(c.log[0].url.path, '/api/transaction/payment/3600335/TX-9');
      // amount ist Pflicht (sonst 400 Missing amount), currency faellt auf den
      // EUR-Default -> beide gehen immer als Query mit.
      expect(c.log[0].url.queryParameters['amount'], '1.5');
      expect(c.log[0].url.queryParameters['currency'], 'EUR');
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

    test('terminalStatus: GET status; 200 -> true, 503 -> false', () async {
      final ok = clientWith(status: 200, body: '');
      expect(await ok.client.terminalStatus(), isTrue);
      expect(ok.log.single.method, 'GET');
      expect(ok.log.single.url.path, '/api/terminals/3600335/status');

      final down = clientWith(status: 503, body: '');
      expect(await down.client.terminalStatus(), isFalse);
    });

    test('terminals: GET /api/terminals + Array-Parsing', () async {
      final c = clientWith(
        body: '[{"tid":"3600335","merchantName":"Shop","terminalType":"POS",'
            '"active":true,"header":["Zeile 1","Zeile 2"],"fax":null}]',
      );
      final list = await c.client.terminals();
      expect(c.log.single.method, 'GET');
      expect(c.log.single.url.path, '/api/terminals');
      expect(list, hasLength(1));
      expect(list.single.tid, '3600335');
      expect(list.single.merchantName, 'Shop');
      expect(list.single.terminalType, 'POS');
      expect(list.single.active, isTrue);
      expect(list.single.header, ['Zeile 1', 'Zeile 2']);
      expect(list.single.fax, isNull);
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

  group('Kennung wird vor dem Netzweg geprueft', () {
    test('19 Stellen -> ArgumentError, und es geht kein Request hinaus', () async {
      final c = clientWith();
      expect(
        () => c.client.payment(amount: 5, transactionId: '2608261401590000001'),
        throwsA(isA<ArgumentError>()),
      );
      expect(c.log, isEmpty);
    });

    test('leere Kennung -> ArgumentError', () async {
      final c = clientWith();
      expect(
        () => c.client.payment(amount: 5, transactionId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(c.log, isEmpty);
    });

    test('18 Stellen sind erlaubt', () async {
      final c = clientWith();
      await c.client.payment(amount: 5, transactionId: '260826140159000001');
      expect(txBody(c.log.single)['transactionId'], '260826140159000001');
    });
  });

  group('tid-Normalisierung', () {
    test('fuehrende Nullen fallen weg -- im Body und im Pfad', () async {
      final log = <http.Request>[];
      final mock = MockClient((request) async {
        log.add(request);
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      });
      final client = HpsClient(tid: '03600335', httpClient: mock);
      expect(client.tid, '3600335');

      await client.payment(amount: 1);
      expect(txBody(log.first)['tid'], '3600335');

      await client.transactionStatus(transactionId: 'TX-1');
      expect(log.last.url.path, '/api/v2/transactions/3600335/TX-1');
    });

    test('eine tid aus lauter Nullen bleibt unveraendert statt leer zu werden', () {
      final client = HpsClient(tid: '000', httpClient: MockClient((_) async => http.Response('{}', 200)));
      expect(client.tid, '000');
    });
  });

  group('Erzeugte Kennung', () {
    test('2000 Kennungen in Folge sind eindeutig und passen in 18 Stellen', () async {
      final c = clientWith();
      final ids = <String>{};
      for (var i = 0; i < 2000; i++) {
        await c.client.payment(amount: 1);
        final id = txBody(c.log.last)['transactionId'] as String;
        expect(id.length, lessThanOrEqualTo(18));
        expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
        ids.add(id);
      }
      expect(ids.length, 2000);
    });

    // Die feste Millisekunde liegt bewusst weit in der Zukunft (100/200 Jahre
    // ab jetzt): so ist sie garantiert groesser als jede Millisekunde, die
    // andere Tests dieser Datei ueber die echte Systemuhr bereits als
    // zuletzt vergeben hinterlassen haben -- ohne dass dieser Test von der
    // Ausfuehrungsreihenfolge abhaengt. 100/200 Jahre bleiben auch nach dem
    // Aufschlag klar innerhalb der 13-stelligen Millisekunden-Spanne
    // (gueltig bis ca. zum Jahr 2286).
    const oneYearMs = 365 * 24 * 60 * 60 * 1000;

    test('erzwungen viele Kennungen in derselben Millisekunde bleiben eindeutig -- '
        'auch wenn der Zaehler ueberlaeuft', () {
      final fixedMs =
          DateTime.now().millisecondsSinceEpoch + 100 * oneYearMs;
      final ids = <String>{};
      // mehr als 100000, damit der Zaehler je Millisekunde nachweislich
      // ueberlaeuft und auf die naechste Millisekunde weiterschaltet
      const callCount = 250000;
      for (var i = 0; i < callCount; i++) {
        final id = HpsClient.newTransactionId(nowMillis: fixedMs);
        expect(id.length, lessThanOrEqualTo(18));
        expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
        ids.add(id);
      }
      expect(ids.length, callCount);
    });

    test('eine rueckwaerts springende Uhr wiederholt keine bereits vergebene Kennung', () {
      final highMs =
          DateTime.now().millisecondsSinceEpoch + 200 * oneYearMs;
      final ids = <String>{
        HpsClient.newTransactionId(nowMillis: highMs),
        // Uhr springt um eine Minute zurueck (z.B. NTP-Korrektur)
        HpsClient.newTransactionId(nowMillis: highMs - 60000),
        // Uhr springt um eine Stunde zurueck (z.B. Zeitumstellung)
        HpsClient.newTransactionId(nowMillis: highMs - 3600000),
        // dieselbe Millisekunde erneut
        HpsClient.newTransactionId(nowMillis: highMs),
      };
      expect(ids.length, 4);
    });
  });

  group('Frist deckt den ganzen Abruf', () {
    test('haengender Rumpf loest die Frist aus, nicht erst der Antwortkopf', () async {
      // Kopf kommt sofort, der Rumpf nie -- genau das Verhalten, das die alte
      // Frist nicht abdeckte: sie lag allein auf send().
      final never = StreamController<List<int>>();
      addTearDown(never.close);
      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(never.stream, 200,
            headers: {'content-type': 'application/json'});
      });
      final client = HpsClient(
        tid: '3600335',
        httpClient: mock,
        timeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        client.payment(amount: 1),
        throwsA(isA<HpsConnectionException>()),
      );
    });
  });

  group('Beobachter', () {
    test('meldet Start und Erfolg eines Requests', () async {
      final events = <HpsEvent>[];
      final mock = MockClient((_) async => http.Response(
          '{"responseCode":"0","transactionId":"TX-9"}', 200,
          headers: {'content-type': 'application/json'}));
      final client = HpsClient(tid: '3600335', httpClient: mock, observer: events.add);

      await client.payment(amount: 1, transactionId: 'TX-9');

      expect(events.map((e) => e.kind),
          containsAllInOrder([HpsEventKind.requestStarted, HpsEventKind.requestSucceeded]));
    });

    test('meldet den Fehlschlag samt Ursache', () async {
      final events = <HpsEvent>[];
      final mock = MockClient((_) async => throw const SocketExceptionStub());
      final client = HpsClient(tid: '3600335', httpClient: mock, observer: events.add);

      await expectLater(client.payment(amount: 1), throwsA(isA<HpsConnectionException>()));

      final failed = events.firstWhere((e) => e.kind == HpsEventKind.requestFailed);
      expect(failed.error, isNotNull);
    });

    test('ein werfender Beobachter reisst den Zahlweg nicht mit', () async {
      final mock = MockClient((_) async => http.Response(
          '{"responseCode":"0"}', 200, headers: {'content-type': 'application/json'}));
      final client = HpsClient(
        tid: '3600335',
        httpClient: mock,
        observer: (_) => throw StateError('Protokoll kaputt'),
      );
      final res = await client.payment(amount: 1);
      expect(res.isApproved, isTrue);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub';
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  @override
  void close() => closed = true;
}
