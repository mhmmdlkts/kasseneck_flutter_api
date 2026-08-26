import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Eine Antwort des Terminal-Doppels auf genau einen Request.
typedef Responder = http.Response Function(http.Request request);

/// Ein Terminal-Doppel, das nach dem URL-PFAD antwortet statt nach der
/// Aufrufreihenfolge.
///
/// Jeder Weg (Zahlung, Status, Abbruch, Gutschrift) hat seine eigene Folge von
/// Antworten; die letzte Antwort einer Folge gilt weiter, sobald die Folge
/// erschoepft ist. Damit bleibt ein Test unabhaengig davon, wie oft die
/// Umsetzung intern abfragt -- eine zusaetzliche Statusabfrage verschiebt nicht
/// mehr die Antwort auf den Abbruch.
class FakeTerminal {
  FakeTerminal({
    this.payment = const <Responder>[],
    this.status = const <Responder>[],
    this.abort = const <Responder>[],
    this.refund = const <Responder>[],
    this.cancel = const <Responder>[],
  });

  /// POST /api/transaction/payment
  final List<Responder> payment;

  /// GET /api/v2/transactions/{tid}/{transactionId}
  final List<Responder> status;

  /// POST /api/transaction/abort/{tid}/{transactionId}
  final List<Responder> abort;

  /// POST /api/transaction/refund
  final List<Responder> refund;

  /// DELETE /api/transaction/payment/{tid}/{transactionId}
  final List<Responder> cancel;

  /// Alle gesehenen Requests, in Reihenfolge.
  final List<http.Request> log = <http.Request>[];

  final Map<String, int> _calls = <String, int>{};

  http.Client get client => MockClient((request) async {
        log.add(request);
        final route = _routeOf(request.method, request.url.path);
        final handlers = _handlersOf(route);
        if (handlers.isEmpty) {
          throw StateError(
            'Kein Verhalten fuer den Pfad ${request.url.path} hinterlegt',
          );
        }
        final index = (_calls[route] ?? 0);
        _calls[route] = index + 1;
        final handler =
            handlers[index < handlers.length ? index : handlers.length - 1];
        return handler(request);
      });

  /// Wie oft ein Weg aufgerufen wurde.
  int callsOn(String route) => _calls[route] ?? 0;

  static String _routeOf(String method, String path) {
    // Reihenfolge zaehlt: der Abbruch-Pfad enthaelt 'transaction', der
    // Storno-Pfad enthaelt 'payment' -- und teilt sich den Pfadanteil sogar
    // mit der Zahlung selbst. Erst die Methode (DELETE) trennt beide.
    if (path.contains('/api/v2/transactions/')) return 'status';
    if (path.contains('/api/transaction/abort/')) return 'abort';
    if (path.contains('/api/transaction/refund')) return 'refund';
    if (method == 'DELETE' && path.contains('/api/transaction/payment/')) {
      return 'cancel';
    }
    if (path.contains('/api/transaction/payment')) return 'payment';
    return path;
  }

  List<Responder> _handlersOf(String route) {
    switch (route) {
      case 'payment':
        return payment;
      case 'status':
        return status;
      case 'abort':
        return abort;
      case 'refund':
        return refund;
      case 'cancel':
        return cancel;
      default:
        return const <Responder>[];
    }
  }
}

/// Liest den `transaction`-Teil eines JSON-Request-Rumpfes aus (Zahlung,
/// Gutschrift). Der Storno-Weg schickt keinen Rumpf -- seine Parameter
/// stecken in der Query, siehe `request.url.queryParameters`.
Map<String, dynamic> txBodyOf(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['transaction']
        as Map<String, dynamic>;

http.Response json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response fehler(int statusCode, String message) => http.Response(
      jsonEncode({'message': message}),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

/// Ein Transportfehler: die Leitung bricht ab, es kommt keine Antwort an.
http.Response boom(http.Request _) => throw const _Transport();

class _Transport implements Exception {
  const _Transport();

  @override
  String toString() => 'Leitung abgebrochen';
}

/// Eine Uhr, die nicht an der Wanduhr haengt, sondern nur durch die Pausen
/// vorrueckt, die die Klaerung selbst einlegt.
///
/// Damit ist das Ablaufen des Budgets exakt nachrechenbar, statt davon
/// abzuhaengen, wie ausgelastet die Maschine gerade ist: ohne echtes Warten
/// verginge sonst gar keine Zeit, und mit echtem Warten waere jede Zusicherung
/// ein Wettlauf gegen die Maschine.
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

HpsPayments paymentsFor(
  FakeTerminal terminal, {
  Duration? budget,
  Duration? maxBackoff,
  HpsObserver? observer,
  List<Duration>? pausen,
}) {
  final client = HpsClient(
    tid: '3600335',
    httpClient: terminal.client,
    timeout: const Duration(milliseconds: 200),
  );
  final uhr = TestUhr();
  return HpsPayments(
    client,
    resolveBudget: budget ?? const Duration(minutes: 10),
    maxBackoff: maxBackoff ?? const Duration(seconds: 10),
    // Kein echtes Warten im Test: die Pause wird mitgeschrieben und laesst
    // stattdessen die Uhr vorruecken. Nur so vergeht Zeit -- ein Test kann
    // deshalb genau ausrechnen, wann das Budget aufgebraucht ist.
    sleep: (d) async {
      pausen?.add(d);
      uhr.vor(d);
    },
    clock: () => uhr,
    observer: observer,
  );
}

void main() {
  group('Zahlung mit geklaertem Ausgang', () {
    test('genehmigte Antwort -> approved, Kennung kommt zurueck', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-1'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-1');
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'TX-1');
      expect(res.response, isNotNull);
    });

    test('abgelehnte Antwort -> declined', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '51', 'responseText': 'Deckung'}),
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-2');
      expect(res.outcome, HpsOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, 'TX-2');
    });

    test('Zahlung bricht ab, Status sagt genehmigt -> approved', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-3'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-3');
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'TX-3');
    });

    test('Zahlung bricht ab, Status sagt abgelehnt -> declined', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '51'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-4');
      expect(res.outcome, HpsOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
    });

    test('quittierter Abbruch plus Ergebniscode -> declined', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-5'}),
          // Erst diese Antwort entscheidet: ein echter, negativer Code.
          (_) => json({'responseCode': '17', 'responseText': 'abgebrochen'}),
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5');
      expect(res.outcome, HpsOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(
        t.log.any((r) => r.url.path.contains('/api/transaction/abort/')),
        isTrue,
      );
      // Der quittierte Abbruch allein reicht nicht: es wird nachgefragt.
      expect(t.callsOn('status'), 2);
    });

    test('quittierter Abbruch, aber Terminal meldet genehmigt -> approved',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-5b'}),
          // Die Nachfrage widerspricht dem quittierten Abbruch.
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5b'}),
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5b'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5b');
      expect(res.outcome, HpsOutcome.approved,
          reason: 'ein 2xx auf dem Abbruchweg darf eine echte Belastung nicht '
              'zu "nichts belastet" erklaeren');
      expect(t.callsOn('abort'), 1);
    });

    test(
        'quittierter Abbruch, danach "laeuft noch", dann genehmigt '
        '-> approved', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-5d'}),
          // Direkt nach dem quittierten Abbruch weiss das Terminal noch
          // nichts. Das ist KEINE Aussage ueber Nichtbelastung.
          (_) => json({'transactionId': 'TX-5d'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5d'}),
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5d'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5d');
      expect(res.outcome, HpsOutcome.approved,
          reason: '"laeuft noch" darf nach einem quittierten Abbruch nicht zu '
              'declined werden -- das hiesse "gefahrlos wiederholbar" fuer '
              'einen laufenden Vorgang');
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 3);
    });

    test('quittierter Abbruch, danach nur noch "laeuft noch" -> unresolved',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-5e'})
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5e'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 5))
          .pay(amount: 25, transactionId: 'TX-5e');
      expect(res.outcome, HpsOutcome.unresolved,
          reason: 'ohne Ergebniscode steht nichts fest, auch nicht nach einem '
              'quittierten Abbruch');
      expect(res.mayRetrySafely, isFalse);
      expect(res.transactionId, 'TX-5e');
      expect(res.response, isNull,
          reason: 'ein "laeuft noch" darf nicht als Beleg mitgegeben werden');
    });

    test('quittierter Abbruch, Nachfrage scheitert -> unresolved', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-5c'}),
          boom
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5c'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5c');
      expect(res.outcome, HpsOutcome.unresolved,
          reason: 'ohne Ergebniscode bleibt der Ausgang offen, er wird nicht '
              'zu declined geraten');
      expect(res.transactionId, 'TX-5c');
    });

    test('laeuft noch, Abbruch scheitert, danach genehmigt -> approved',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-6'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-6'}),
        ],
        abort: [(_) => fehler(400, 'already tapped')],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6');
      expect(res.outcome, HpsOutcome.approved);
    });

    test('der Abbruch wird nur ein einziges Mal versucht', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-6b'}),
          (_) => json({'transactionId': 'TX-6b'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-6b'}),
        ],
        abort: [(_) => fehler(400, 'already tapped')],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6b');
      expect(res.outcome, HpsOutcome.approved);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 3);
    });

    test('Budget erschoepft -> unresolved, niemals declined', () async {
      final pausen = <Duration>[];
      final t = FakeTerminal(
        payment: [boom],
        // Das Terminal sagt dauerhaft "laeuft noch" und lehnt den Abbruch ab:
        // die Klaerung kommt zu keinem Ergebnis und laeuft ins Budget.
        status: [
          (_) => json({'transactionId': 'TX-7'})
        ],
        abort: [(_) => fehler(400, 'already tapped')],
      );
      final res = await paymentsFor(t,
              budget: const Duration(seconds: 5), pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-7');
      expect(res.outcome, HpsOutcome.unresolved);
      expect(res.transactionId, 'TX-7');
      expect(res.mayRetrySafely, isFalse);
      expect(t.callsOn('status'), 3,
          reason: 'es muss wirklich geklaert worden sein, nicht nur das '
              'Budget geprueft');
      expect(t.callsOn('abort'), 1);
      // Die letzte Pause waere 4 s gewesen; nach 3 s verbrauchtem Budget
      // bleiben nur 2 s. Die Klaerung ueberzieht also nicht.
      expect(pausen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 2),
      ]);
      expect(pausen.fold(Duration.zero, (a, b) => a + b),
          const Duration(seconds: 5));
    });

    test('Terminal durchgehend unerreichbar -> unresolved, nicht declined',
        () async {
      final t = FakeTerminal(payment: [boom], status: [boom]);
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-8');
      expect(res.outcome, HpsOutcome.unresolved,
          reason: 'ein Transportfehler beweist nicht, dass nichts gestartet '
              'wurde');
      expect(res.transactionId, 'TX-8');
      // Nach drei erfolglosen Statusabfragen in Folge wird vorzeitig beendet,
      // damit ein offensichtlich totes Terminal niemanden 90 Sekunden bindet.
      expect(t.callsOn('status'), 3);
    });

    test('ohne uebergebene Kennung wird eine erzeugt und zurueckgegeben',
        () async {
      final t = FakeTerminal(payment: [boom], status: [boom]);
      final res = await paymentsFor(t).pay(amount: 25);
      expect(res.transactionId, isNotEmpty);
      expect(res.transactionId.length, lessThanOrEqualTo(18));
      expect(res.outcome, HpsOutcome.unresolved);
    });

    test('die erzeugte Kennung steht schon im ersten Request', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '0'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25);
      final gesendet = jsonDecode(t.log.single.body) as Map<String, dynamic>;
      final tx = gesendet['transaction'] as Map<String, dynamic>;
      expect(tx['transactionId'], res.transactionId);
    });

    test('Antwort ohne Ergebniscode wird geklaert, nicht abgelehnt', () async {
      final t = FakeTerminal(
        // Die Zahlung antwortet, aber ohne responseCode -- das entscheidet
        // nichts und darf keinesfalls als Ablehnung gelten.
        payment: [
          (_) => json({'transactionId': 'TX-9'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-9'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-9');
      expect(res.outcome, HpsOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('Trinkgeld und Referenz gehen mit hinaus', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-10'})
        ],
      );
      await paymentsFor(t)
          .pay(amount: 25, tip: 2, reference: 'B-42', transactionId: 'TX-10');
      final gesendet = jsonDecode(t.log.single.body) as Map<String, dynamic>;
      final tx = gesendet['transaction'] as Map<String, dynamic>;
      expect(tx['amount'], 25);
      expect(tx['tip'], 2);
      expect(tx['reference'], 'B-42');
      expect(tx['transactionId'], 'TX-10');
    });

    test('der Verlauf wird mitgeschrieben', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-11'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-11');
      expect(res.steps, isNotEmpty);
      expect(res.steps.length, greaterThanOrEqualTo(2));
    });

    test('der Beobachter erfaehrt von Klaerung und Ausgang', () async {
      final ereignisse = <HpsEvent>[];
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-12'})
        ],
      );
      await paymentsFor(t, observer: ereignisse.add)
          .pay(amount: 25, transactionId: 'TX-12');
      expect(ereignisse.any((e) => e.kind == HpsEventKind.resolving), isTrue);
      expect(ereignisse.any((e) => e.kind == HpsEventKind.resolved), isTrue);
      expect(
        ereignisse.every((e) => e.transactionId == 'TX-12'),
        isTrue,
        reason: 'jedes Ereignis muss die Kennung tragen',
      );
    });

    test('unlesbarer Rumpf trotz 200 -> Ergebnis mit Kennung, kein Wurf',
        () async {
      final t = FakeTerminal(
        // 200, aber kein JSON: das Auswerten wirft eine FormatException,
        // NACHDEM der Zahlungs-Request draussen und beantwortet war.
        payment: [(_) => http.Response('<html>Fehlerseite</html>', 200)],
        status: [(_) => http.Response('<html>Fehlerseite</html>', 200)],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-14');
      expect(res.outcome, HpsOutcome.unresolved);
      expect(res.transactionId, 'TX-14',
          reason: 'ohne Kennung waere der Vorgang unauffindbar -- genau der '
              'Vorfall');
    });

    test('unerwarteter Feldtyp -> Ergebnis mit Kennung, kein Wurf', () async {
      final t = FakeTerminal(
        // transactionId als Zahl: der harte Cast in TransactionResponse wirft
        // einen TypeError, keine HpsException.
        payment: [
          (_) => json({'transactionId': 12345})
        ],
        status: [
          (_) => json({'transactionId': 12345})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-15');
      expect(res.outcome, HpsOutcome.unresolved);
      expect(res.transactionId, 'TX-15');
    });

    test('unlesbare Abbruch-Antwort reisst die Klaerung nicht mit', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-16'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-16'}),
        ],
        // 200, aber die Auswertung wirft.
        abort: [(_) => http.Response('kein JSON', 200)],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-16');
      expect(res.outcome, HpsOutcome.approved);
      // Der Verlauf darf hier keine Ursache behaupten: dass die Karte anlag,
      // ist gerade NICHT belegt -- es kam nur keine lesbare Antwort.
      expect(
        res.steps.any((s) => s.contains('Karte lag bereits an')),
        isFalse,
      );
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test('nur eine echte Ablehnung des Terminals nennt die Karte als Ursache',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'transactionId': 'TX-16b'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-16b'}),
        ],
        abort: [(_) => fehler(400, 'already tapped')],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-16b');
      expect(res.outcome, HpsOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Karte lag bereits an')),
        isTrue,
      );
    });

    test('ein eigener Auswertungsfehler bleibt nicht stumm', () async {
      final ereignisse = <HpsEvent>[];
      final t = FakeTerminal(
        payment: [(_) => http.Response('<html>Fehlerseite</html>', 200)],
        status: [(_) => http.Response('<html>Fehlerseite</html>', 200)],
      );
      await paymentsFor(t, observer: ereignisse.add)
          .pay(amount: 25, transactionId: 'TX-17');
      final eigen = ereignisse.where((e) => e.error is FormatException);
      expect(eigen, isNotEmpty,
          reason: 'ein Fehler im eigenen Auswerten darf nicht lautlos zu '
              'einem Klaerungslauf werden');
      expect(eigen.every((e) => e.kind == HpsEventKind.requestFailed), isTrue);
      expect(eigen.every((e) => e.transactionId == 'TX-17'), isTrue);
    });

    test('eine zu lange Kennung wirft weiterhin -- da ging nichts hinaus',
        () async {
      final t = FakeTerminal(payment: [boom]);
      await expectLater(
        paymentsFor(t).pay(amount: 25, transactionId: '1234567890123456789'),
        throwsA(isA<ArgumentError>()),
      );
      expect(t.log, isEmpty,
          reason: 'die Laengenpruefung schlaegt zu, bevor etwas gesendet wird');
    });

    test('ein werfender Beobachter reisst den Zahlweg nicht mit', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-13'})
        ],
      );
      final res = await paymentsFor(
        t,
        observer: (_) => throw StateError('Protokoll kaputt'),
      ).pay(amount: 25, transactionId: 'TX-13');
      expect(res.outcome, HpsOutcome.approved);
    });
  });

  group('Backoff zwischen den Statusabfragen', () {
    /// Ein Terminal, das [runden] mal "laeuft noch" sagt und danach genehmigt;
    /// der Abbruch wird abgelehnt, damit die Klaerung wirklich weiterlaeuft.
    FakeTerminal zaeh(int runden) => FakeTerminal(
          payment: [boom],
          status: [
            for (var i = 0; i < runden; i++)
              (_) => json({'transactionId': 'TX-B'}),
            (_) => json({'responseCode': '0', 'transactionId': 'TX-B'}),
          ],
          abort: [(_) => fehler(400, 'already tapped')],
        );

    test('die erste Abfrage laeuft sofort, dann wird verdoppelt', () async {
      final pausen = <Duration>[];
      final res = await paymentsFor(zaeh(4), pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-B');
      expect(res.outcome, HpsOutcome.approved);
      expect(pausen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
    });

    test('maxBackoff deckelt die Verdopplung', () async {
      final pausen = <Duration>[];
      final res = await paymentsFor(zaeh(6), pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-B');
      expect(res.outcome, HpsOutcome.approved);
      expect(pausen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        // 16 s waeren an der Reihe, die Vorgabe deckelt auf 10 s.
        Duration(seconds: 10),
        Duration(seconds: 10),
      ]);
    });

    test('ein eigener maxBackoff wird beachtet', () async {
      final pausen = <Duration>[];
      final res = await paymentsFor(
        zaeh(4),
        maxBackoff: const Duration(seconds: 3),
        pausen: pausen,
      ).pay(amount: 25, transactionId: 'TX-B');
      expect(res.outcome, HpsOutcome.approved);
      expect(pausen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 3),
      ]);
    });

    test('auch gescheiterte Statusabfragen warten laenger', () async {
      final pausen = <Duration>[];
      final t = FakeTerminal(payment: [boom], status: [boom]);
      final res = await paymentsFor(t, pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-B2');
      expect(res.outcome, HpsOutcome.unresolved);
      // Drei Versuche, dazwischen zwei Pausen.
      expect(pausen, const [Duration(seconds: 1), Duration(seconds: 2)]);
    });
  });

  group('Rueckerstattung und Storno', () {
    test('refund: genehmigt -> approved, Referenz auf die Originalzahlung',
        () async {
      final t = FakeTerminal(
        refund: [
          (_) => json({'responseCode': '0', 'transactionId': 'RF-1'})
        ],
      );
      final res = await paymentsFor(t).refund(
        amount: 25,
        transactionId: 'RF-1',
        originalTransactionId: 'TX-1',
      );
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'RF-1');
      expect(txBodyOf(t.log.single)['originalTransactionId'], 'TX-1');
    });

    test('refund: Abbruch wird geklaert, nicht als Fehlschlag gemeldet',
        () async {
      final t = FakeTerminal(
        refund: [boom],
        status: [
          (_) => json({'responseCode': '0'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: 'RF-2');
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'RF-2');
    });

    test('refund: abgelehnte Antwort -> declined', () async {
      final t = FakeTerminal(
        refund: [
          (_) => json({'responseCode': '51'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: 'RF-3');
      expect(res.outcome, HpsOutcome.declined);
    });

    test(
        'refund: eine zu lange Kennung wirft weiterhin -- da ging nichts '
        'hinaus', () async {
      final t = FakeTerminal(refund: [boom]);
      await expectLater(
        paymentsFor(t).refund(amount: 25, transactionId: '1234567890123456789'),
        throwsA(isA<ArgumentError>()),
      );
      expect(t.log, isEmpty,
          reason: 'die Laengenpruefung schlaegt zu, bevor etwas gesendet '
              'wird');
    });

    test(
        'cancel: eine zu lange Kennung wirft weiterhin -- da ging nichts '
        'hinaus', () async {
      final t = FakeTerminal(cancel: [boom]);
      await expectLater(
        paymentsFor(t).cancel(transactionId: '1234567890123456789', amount: 25),
        throwsA(isA<ArgumentError>()),
      );
      expect(t.log, isEmpty,
          reason: 'die Laengenpruefung schlaegt zu, bevor etwas gesendet '
              'wird');
    });

    test('cancel: direkte Ablehnung -> declined', () async {
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '51', 'responseText': 'abgelehnt'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-9b', amount: 25);
      expect(res.outcome, HpsOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, 'TX-9b');
    });

    test(
        'cancel: direkte Genehmigung -> approved, Kennung bleibt die '
        'urspruengliche', () async {
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-9'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-9', amount: 25);
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'TX-9');
      expect(t.log.single.url.path, contains('TX-9'));
    });

    test('cancel: Abbruch wird ueber den VOID-Status der Nachfrage geklaert',
        () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'responseCode': '0', 'state': 'VOID'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-10', amount: 25);
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'TX-10');
    });

    test(
      'cancel: die genehmigte ORIGINALZAHLUNG darf nicht als erfolgreiche '
      'Aufhebung durchgehen',
      () async {
        final t = FakeTerminal(
          cancel: [boom],
          // Genau die Falle: responseCode '0', weil DAS die Originalzahlung
          // war -- kein 'state', also keine Aussage ueber die Aufhebung.
          status: [
            (_) => json({'responseCode': '0', 'transactionId': 'TX-11'}),
          ],
        );
        final res =
            await paymentsFor(t, budget: const Duration(milliseconds: 50))
                .cancel(transactionId: 'TX-11', amount: 25);
        expect(res.outcome, HpsOutcome.unresolved);
        expect(res.transactionId, 'TX-11');
      },
    );

    test(
        'cancel: state fehlt komplett (ausserhalb Status v2) -> unresolved, '
        'kein Raten', () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'transactionId': 'TX-12'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: 'TX-12', amount: 25);
      expect(res.outcome, HpsOutcome.unresolved);
    });

    test('cancel: state FAILED entscheidet nichts -- kein geratenes declined',
        () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'responseCode': '0', 'state': 'FAILED'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: 'TX-12b', amount: 25);
      expect(res.outcome, HpsOutcome.unresolved);
    });

    test('cancel: Transportfehler durchgehend -> unresolved', () async {
      final t = FakeTerminal(cancel: [boom], status: [boom]);
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-13', amount: 25);
      expect(res.outcome, HpsOutcome.unresolved);
      expect(res.transactionId, 'TX-13');
    });

    test('cancel: kein abort-Versuch waehrend der Klaerung', () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          // Erst die Originalzahlung ohne state, dann VOID.
          (_) => json({'responseCode': '0'}),
          (_) => json({'responseCode': '0', 'state': 'VOID'}),
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-14', amount: 25);
      expect(res.outcome, HpsOutcome.approved);
      // callsOn('abort') waere hier immer 0 -- auch wenn abort() versucht
      // wuerde, denn ohne abort-Handler wirft FakeTerminal einen StateError,
      // BEVOR der Zaehler hochgeht, und dieser Fehler wuerde als
      // Transportfehler geschluckt. Der Log ist der einzige verlaessliche
      // Beleg: er wird schon vor diesem Wurf gefuellt.
      expect(t.log.where((r) => r.url.path.contains('/abort/')), isEmpty);
    });
  });

  group('HpsClient.newTransactionId', () {
    test('ist oeffentlich, numerisch und hoechstens 18 Stellen lang', () {
      final id = HpsClient.newTransactionId();
      expect(id.length, 18);
      expect(RegExp(r'^\d{18}$').hasMatch(id), isTrue);
    });

    test('zwei Kennungen in derselben Millisekunde sind verschieden', () {
      final ids = List.generate(200, (_) => HpsClient.newTransactionId());
      expect(ids.toSet().length, greaterThan(190));
    });
  });
}
