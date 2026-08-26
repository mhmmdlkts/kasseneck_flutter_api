import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// Ein API-Doppel, das seine Antworten der Reihe nach abarbeitet (die letzte
/// gilt weiter, sobald die Folge erschoepft ist) und mitzaehlt, wie oft es
/// tatsaechlich angefragt wurde.
({KasseneckApi api, int Function() callCount}) apiWith(
  List<http.Response Function()> responses,
) {
  var i = 0;
  var calls = 0;
  final mock = MockClient((_) async {
    calls++;
    final r = responses[i < responses.length ? i : responses.length - 1];
    i++;
    return r();
  });
  final api = KasseneckApi(
    apiKey: 'k',
    cashregisterToken: 'dGVzdDp0ZXN0',
    httpClient: mock,
  );
  return (api: api, callCount: () => calls);
}

/// Vollstaendiges, gueltiges Beleg-JSON -- HobexReceipt.fromJson verlangt
/// jedes Feld (nicht nullbar), ein unvollstaendiger Rumpf wirft beim Parsen.
String receiptJson({
  required String responseCode,
  required String transactionId,
}) {
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

/// Eine Uhr, die nicht an der Wanduhr haengt, sondern nur durch die Pausen
/// vorrueckt, die die Klaerung selbst einlegt.
///
/// Damit ist das Ablaufen des Budgets exakt nachrechenbar, statt davon
/// abzuhaengen, wie ausgelastet die Maschine gerade ist -- derselbe Kunstgriff
/// wie in test/hps_payments_test.dart (TestUhr).
class TestUhr implements Stopwatch {
  Duration _elapsed = Duration.zero;

  /// Ruecke die Uhr um [d] vor. Wird vom sleep-Doppel aufgerufen.
  void vor(Duration d) => _elapsed += d;

  @override
  Duration get elapsed => _elapsed;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;

  @override
  int get elapsedTicks => _elapsed.inMicroseconds;

  @override
  int get frequency => Duration.microsecondsPerSecond;

  @override
  bool get isRunning => true;
}

HobexCloudPayments cloudPaymentsFor(
  KasseneckApi api, {
  Duration? budget,
  Duration? maxBackoff,
  List<Duration>? pausen,
}) {
  final uhr = TestUhr();
  return HobexCloudPayments(
    api,
    resolveBudget: budget ?? const Duration(seconds: 90),
    maxBackoff: maxBackoff ?? const Duration(seconds: 10),
    // Kein echtes Warten im Test: die Pause wird mitgeschrieben und laesst
    // stattdessen die Uhr vorruecken. Nur so vergeht Zeit -- ein Test kann
    // deshalb genau ausrechnen, wann das Budget aufgebraucht ist.
    sleep: (d) async {
      pausen?.add(d);
      uhr.vor(d);
    },
    clock: () => uhr,
  );
}

void main() {
  group('Cloud-Zahlung mit geklaertem Ausgang', () {
    test('genehmigt -> approved', () async {
      final (:api, :callCount) = apiWith([
        () => http.Response(
            '{"data":${receiptJson(responseCode: '0', transactionId: 'TX-1')}}',
            200),
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-1', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-1');
      expect(callCount(), 1, reason: 'muss beim direkten Erfolg reichen');
    });

    test('Abbruch, danach sagt der Status genehmigt -> approved', () async {
      final (:api, :callCount) = apiWith([
        () => throw Exception('Verbindung weg'),
        () => http.Response(
            '{"status":"success","data":${receiptJson(responseCode: '0', transactionId: 'TX-2')}}',
            200),
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-2', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(callCount(), 2);
    });

    test('Abbruch und Status bleibt unbekannt -> unresolved, nie declined',
        () async {
      final (:api, :callCount) =
          apiWith([() => throw Exception('Verbindung weg')]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-3', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-3');
    });

    test('abgelehnt -> declined', () async {
      final (:api, :callCount) = apiWith([
        () => http.Response(
            '{"data":${receiptJson(responseCode: '51', transactionId: 'TX-4')}}',
            200),
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-4', amount: 25);
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.transactionId, 'TX-4');
      expect(res.mayRetrySafely, isTrue);
      expect(callCount(), 1);
    });

    test('leerer Ergebniscode -> weiter geklaert, nicht declined', () async {
      // Ein "responseCode": "" ist kein Ergebniscode -- die isEmpty-Zeile in
      // _fromReceipt muss ihn wie einen fehlenden behandeln, sonst wird ein
      // unentschiedener Vorgang faelschlich als declined gemeldet.
      final (:api, :callCount) = apiWith([
        () => http.Response(
            '{"data":${receiptJson(responseCode: '', transactionId: 'TX-4c')}}',
            200),
        () => http.Response(
            '{"status":"success","data":${receiptJson(responseCode: '0', transactionId: 'TX-4c')}}',
            200),
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-4c', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-4c');
      expect(callCount(), 2,
          reason: 'ein leerer Code entscheidet nichts -- es muss '
              'nachgefragt werden');
    });

    test(
        'Statusabfrage scheitert dreimal in Folge -> unresolved, nie '
        'declined, vorzeitig beendet', () async {
      final (:api, :callCount) = apiWith([
        () => throw Exception('Verbindung weg'), // pay()
        () => throw Exception('Verbindung weg'), // status 1
        () => throw Exception('Verbindung weg'), // status 2
        () => throw Exception('Verbindung weg'), // status 3 -> Abbruch
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-5', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-5');
      // Ohne den vorzeitigen Abbruch bei maxTransportFailures wuerde die
      // Schleife weiter abfragen, bis das (im Test riesige) Budget
      // aufgebraucht ist -- der Test schluege dann nur ueber den
      // Default-Timeout von package:test fehl, mit einer irrefuehrenden
      // Meldung. Die Anzahl der tatsaechlichen Aufrufe sichert den Abbruch
      // selbst zu: genau 1 (pay) + 3 (status bis maxTransportFailures),
      // keiner mehr.
      expect(callCount(), 4);
    });

    test('eine beantwortete Abfrage setzt den Fehlerzaehler zurueck', () async {
      // throw, throw, null, throw, throw, success: ohne den Reset nach der
      // dritten Antwort (null) waeren das vier Fehlschlaege in Folge -- bei
      // maxTransportFailures = 3 wuerde vorzeitig mit unresolved abgebrochen,
      // BEVOR die letzte, erfolgreiche Antwort je abgefragt wird. Nur mit dem
      // Reset kommt die Schleife bis zum sechsten Aufruf durch.
      final (:api, :callCount) = apiWith([
        () => throw Exception('Verbindung weg'), // pay()
        () => throw Exception('Verbindung weg'), // status 1 -> Zaehler 1
        () => http.Response('{"status":"pending"}', 200), // status 2 -> Reset
        () => throw Exception('Verbindung weg'), // status 3 -> Zaehler 1
        () => throw Exception('Verbindung weg'), // status 4 -> Zaehler 2
        () => http.Response(
            '{"status":"success","data":${receiptJson(responseCode: '0', transactionId: 'TX-6')}}',
            200),
      ]);
      final res =
          await cloudPaymentsFor(api).pay(transactionId: 'TX-6', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-6');
      expect(callCount(), 6);
    });

    test('Budget erschoepft, ohne echtes Warten im Test -> unresolved',
        () async {
      final pausen = <Duration>[];
      final (:api, :callCount) = apiWith([
        () => throw Exception('Verbindung weg'), // pay()
        // Der Dienst sagt dauerhaft "kein Ergebnis" -- kein Transportfehler,
        // die Klaerung laeuft also nicht ueber maxTransportFailures aus,
        // sondern wirklich ins Budget.
        () => http.Response('{"status":"pending"}', 200),
      ]);
      final res = await cloudPaymentsFor(
        api,
        budget: const Duration(seconds: 5),
        pausen: pausen,
      ).pay(transactionId: 'TX-7', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-7');
      expect(
        callCount(),
        4,
        reason: 'pay() + drei Statusabfragen, bis das Budget von 5s '
            '(1s+2s+2s Pause) aufgebraucht ist',
      );
      // Die letzte Pause waere 4s gewesen; nach 3s verbrauchtem Budget
      // bleiben nur 2s -- die Klaerung ueberzieht das Budget nicht.
      expect(pausen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 2),
      ]);
      expect(pausen.fold(Duration.zero, (a, b) => a + b),
          const Duration(seconds: 5));
    });

    test('leere Kennung -> ArgumentError, kein Request', () async {
      final (:api, :callCount) = apiWith([]);
      await expectLater(
        cloudPaymentsFor(api).pay(transactionId: '', amount: 25),
        throwsA(isA<ArgumentError>()),
      );
      expect(callCount(), 0,
          reason: 'die Pruefung schlaegt zu, bevor etwas gesendet wird');
    });
  });
}
