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
      expect(res.outcome, CardPaymentOutcome.approved);
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
      expect(res.outcome, CardPaymentOutcome.declined);
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
      expect(res.outcome, CardPaymentOutcome.approved);
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
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
    });

    test('Abbruch gelingt (0) -> declined, ganz ohne Statusabfrage', () async {
      // Gemessen am 26.08.2026: der Abbruch gelingt nur, solange der Vorgang
      // noch abbrechbar ist. Das ist die positive Aussage, aus der declined
      // entstehen darf -- und sie macht jede Statusabfrage ueberfluessig, die
      // ohnehin nur 9027 antworten wuerde.
      final t = FakeTerminal(
        payment: [boom],
        abort: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, 'TX-5');
      expect(res.response, isNotNull);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 0,
          reason: 'ein bewiesener Abbruch braucht keine Nachfrage mehr');
    });

    test('der Abbruch kommt VOR der ersten Statusabfrage', () async {
      // Die alte Reihenfolge (erst pollen, abbrechen nur wenn der Status
      // "laeuft noch" meldet) lief ins Leere: diesen Zustand meldet die
      // Statusabfrage nie.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5r'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5r');
      final wege = t.log
          .map((r) => r.url.path)
          .where((p) => p.contains('/abort/') || p.contains('/api/v2/'))
          .toList();
      expect(wege.first, contains('/abort/'));
    });

    test('Abbruch abgelehnt (100010) -> pollen, dann echtes Ergebnis', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          // 9027 ist keine Aussage -- weiter klaeren.
          (_) => json({'responseCode': '9027'}),
          // Erst dieser Code entscheidet.
          (_) => json({'responseCode': '100003', 'responseText': 'no card'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5a');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 2);
    });

    test('Abbruch abgelehnt (100010), Terminal meldet genehmigt -> approved',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5b'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5b');
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: 'ein gescheiterter Abbruch heisst, dass der Vorgang ueber '
              'den abbrechbaren Punkt hinaus ist -- er darf eine echte '
              'Belastung nicht zu "nichts belastet" erklaeren');
      expect(t.callsOn('abort'), 1);
    });

    test('ein mit 200 quittierter Abbruch OHNE Ergebniscode beweist nichts',
        () async {
      // Die alte Fassung von HpsClient.abort() las nur die transactionId und
      // warf nur bei Nicht-2xx. Eine solche Antwort ist keine Aussage.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-5d'}),
        ],
        abort: [
          (_) => json({'transactionId': 'TX-5d'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5d');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 2);
    });

    test('9027 bis zum Budgetende -> unresolved, niemals declined', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027', 'responseText': 'not found'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 5))
          .pay(amount: 25, transactionId: 'TX-5e');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: '9027 steht gleichermassen fuer "laeuft gerade", "nie '
              'gesehen" und "abgebrochen" -- daraus darf nie "gefahrlos '
              'wiederholbar" werden');
      expect(res.mayRetrySafely, isFalse);
      expect(res.transactionId, 'TX-5e');
      expect(res.response, isNull,
          reason: 'eine Nicht-Aussage darf nicht als Beleg mitgegeben werden');
    });

    test('Abbruch abgelehnt, Nachfrage scheitert -> unresolved', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          boom
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5c');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'ohne Ergebniscode bleibt der Ausgang offen, er wird nicht '
              'zu declined geraten');
      expect(res.transactionId, 'TX-5c');
    });

    test('HTTP-Fehler beim Abbruch -> pollen, kein geratenes Ergebnis',
        () async {
      // Ein Nicht-2xx ist keine Aussage ueber den Vorgang. Gemessen meldet das
      // Terminal ein gescheitertes Abbrechen ohnehin mit 200 und 100010.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-6h'}),
        ],
        abort: [(_) => fehler(400, 'bad request')],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6h');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test('Transportfehler beim Abbruch -> pollen, kein geratenes Ergebnis',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-6'}),
        ],
        abort: [boom],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test(
        'ein am Transport gescheiterter Abbruch kostet keine Klaerrunde',
        () async {
      // Der Transportfehler-Zaehler gilt der Statusabfrage. Zaehlte der
      // Abbruch mit, bliebe nach zwei Abfragen Schluss -- obwohl ueber die
      // Erreichbarkeit der Statusabfrage noch nichts bekannt war.
      final t = FakeTerminal(payment: [boom], status: [boom], abort: [boom]);
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6t');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(t.callsOn('status'), 3);
    });

    test('der Abbruch wird nur ein einziges Mal versucht', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-6b'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-6b');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 3);
    });

    test('Budget erschoepft -> unresolved, niemals declined', () async {
      final pausen = <Duration>[];
      final t = FakeTerminal(
        payment: [boom],
        // Das Terminal gibt dauerhaft keine Auskunft und ist nicht mehr
        // abbrechbar: die Klaerung kommt zu keinem Ergebnis und laeuft ins
        // Budget.
        status: [
          (_) => json({'responseCode': '9027'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t,
              budget: const Duration(seconds: 5), pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-7');
      expect(res.outcome, CardPaymentOutcome.unresolved);
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
      expect(res.outcome, CardPaymentOutcome.unresolved,
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
      expect(res.outcome, CardPaymentOutcome.unresolved);
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
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-9');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('9027 schon in der Zahlungsantwort wird geklaert, nicht abgelehnt',
        () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '9027', 'transactionId': 'TX-9c'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-9c'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-9c');
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: '9027 ist auch als direkte Antwort keine Ablehnung');
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('Antwort mit LEEREM Ergebniscode wird geklaert, nicht abgelehnt',
        () async {
      // Ein "responseCode": "" vom Terminal ist kein Ergebniscode -- er darf
      // nicht wie ein vorhandener, nicht-"0"-Code als Ablehnung gelesen
      // werden. Genau das war C-2: TransactionResponse.isInProgress prueft
      // auf null, und ein Leerstring ist nicht null.
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '', 'transactionId': 'TX-9b'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': 'TX-9b'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: 'TX-9b');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0),
          reason: 'ein leerer Code muss wie ein fehlender weiter geklaert '
              'werden, nicht sofort als declined durchgehen');
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
      expect(res.outcome, CardPaymentOutcome.unresolved);
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
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-15');
    });

    test('unlesbare Abbruch-Antwort reisst die Klaerung nicht mit', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-16'}),
        ],
        // 200, aber die Auswertung wirft.
        abort: [(_) => http.Response('kein JSON', 200)],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-16');
      expect(res.outcome, CardPaymentOutcome.approved);
      // Der Verlauf darf hier keine Ursache behaupten: ob der Abbruch wirkte,
      // ist gerade NICHT belegt -- es kam nur keine lesbare Antwort.
      expect(
        res.steps.any((s) => s.contains('nicht mehr abbrechbar')),
        isFalse,
      );
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test('nur ein Ergebniscode des Terminals nennt den Abbruch abgelehnt',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': 'TX-16b'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010', 'responseText': 'not abortable'})
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-16b');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Abbruch abgelehnt (100010)')),
        isTrue,
      );
      expect(
        res.steps.any(
            (s) => s.contains('keine Auskunft (9027)')),
        isTrue,
        reason: 'der Verlauf muss zeigen, dass 9027 nichts entschieden hat',
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
      expect(res.outcome, CardPaymentOutcome.approved);
    });
  });

  group('Backoff zwischen den Statusabfragen', () {
    /// Ein Terminal, das [runden] mal keine Auskunft gibt (9027) und danach
    /// genehmigt meldet; der Abbruch wird abgelehnt (100010), damit die
    /// Klaerung wirklich in die Statusabfrage laeuft.
    FakeTerminal zaeh(int runden) => FakeTerminal(
          payment: [boom],
          status: [
            for (var i = 0; i < runden; i++) (_) => json({'responseCode': '9027'}),
            (_) => json({'responseCode': '0', 'transactionId': 'TX-B'}),
          ],
          abort: [
            (_) => json({'responseCode': '100010'})
          ],
        );

    test('die erste Abfrage laeuft sofort, dann wird verdoppelt', () async {
      final pausen = <Duration>[];
      final res = await paymentsFor(zaeh(4), pausen: pausen)
          .pay(amount: 25, transactionId: 'TX-B');
      expect(res.outcome, CardPaymentOutcome.approved);
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
      expect(res.outcome, CardPaymentOutcome.approved);
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
      expect(res.outcome, CardPaymentOutcome.approved);
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
      expect(res.outcome, CardPaymentOutcome.unresolved);
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
      expect(res.outcome, CardPaymentOutcome.approved);
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
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: 'RF-2');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'RF-2');
    });

    test('refund: derselbe Klaerweg wie bei pay -- Abbruch zuerst', () async {
      // Die Kennung ist die des NEUEN Vorgangs, und der Abbruch-Endpunkt
      // kennt keinen Transaktionstyp. Ohne den Abbruch haette die Klaerung
      // einer Gutschrift gar keinen Diskriminator und endete fast immer bei
      // unresolved -- die Statusabfrage antwortet auch hier 9027.
      final t = FakeTerminal(
        refund: [boom],
        abort: [
          (_) => json({'responseCode': '0', 'transactionId': 'RF-4'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: 'RF-4');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 0);
      expect(t.log.any((r) => r.url.path.contains('/abort/3600335/RF-4')),
          isTrue,
          reason: 'der Abbruch adressiert die Kennung der GUTSCHRIFT');
    });

    test('refund: 9027 bis zum Budgetende -> unresolved', () async {
      final t = FakeTerminal(
        refund: [boom],
        status: [
          (_) => json({'responseCode': '9027'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 5))
          .refund(amount: 25, transactionId: 'RF-5');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.mayRetrySafely, isFalse);
    });

    test('refund: abgelehnte Antwort -> declined', () async {
      final t = FakeTerminal(
        refund: [
          (_) => json({'responseCode': '51'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: 'RF-3');
      expect(res.outcome, CardPaymentOutcome.declined);
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
      expect(res.outcome, CardPaymentOutcome.declined);
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
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-9');
      expect(t.log.single.url.path, contains('TX-9'));
    });

    test('cancel: Abbruch wird ueber 9011 auf der Originalkennung geklaert',
        () async {
      // Am 26.08.2026 gemessen: nach einem erfolgreichen Void antwortet die
      // Statusabfrage auf die Kennung der ORIGINALZAHLUNG mit 9011
      // "Transaction Canceled" -- und 'state' bleibt dabei null.
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({
                'responseCode': '9011',
                'responseText': 'Transaction Canceled',
                'transactionType': 'S',
              })
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-10', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, 'TX-10');
    });

    test(
      'cancel: die genehmigte ORIGINALZAHLUNG darf nicht als erfolgreiche '
      'Aufhebung durchgehen',
      () async {
        final t = FakeTerminal(
          cancel: [boom],
          // Genau die Falle: responseCode '0', weil DAS die Originalzahlung
          // ist. Sie steht damit unveraendert da -- die Aufhebung hat NICHT
          // gegriffen.
          status: [
            (_) => json({'responseCode': '0', 'transactionId': 'TX-11'}),
          ],
        );
        final res =
            await paymentsFor(t, budget: const Duration(milliseconds: 50))
                .cancel(transactionId: 'TX-11', amount: 25);
        expect(res.outcome, CardPaymentOutcome.declined,
            reason: 'declined heisst hier "die Aufhebung hat nicht gegriffen" '
                '-- keinesfalls "die Aufhebung war erfolgreich"');
        expect(res.isApproved, isFalse);
        expect(res.transactionId, 'TX-11');
        expect(
          res.steps.any((s) => s.contains('steht unveraendert')),
          isTrue,
        );
      },
    );

    test('cancel: 9027 entscheidet nichts -> unresolved, kein Raten', () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'responseCode': '9027'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: 'TX-12', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
    });

    test('cancel: Antwort ohne Ergebniscode -> unresolved, kein Raten',
        () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'transactionId': 'TX-12b'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: 'TX-12b', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
    });

    test(
        'cancel: state VOID gilt zusaetzlich, ist aber nie notwendig',
        () async {
      // Auf HPS 1.10.0 / FW 7.3.6 ist 'state' in JEDER Antwort null -- dieser
      // Weg ist dort tot und steht nur fuer eine Firmware, die das Feld
      // fuellt. Massgeblich ist 9011, siehe oben.
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'state': 'VOID'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-12c', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
    });

    test('cancel: Transportfehler durchgehend -> unresolved', () async {
      final t = FakeTerminal(cancel: [boom], status: [boom]);
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-13', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, 'TX-13');
    });

    test('cancel: kein abort-Versuch waehrend der Klaerung', () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          // Erst keine Auskunft, dann die bestaetigte Aufhebung.
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9011'}),
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: 'TX-14', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
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
      // Streng statt "greaterThan(190)": der Erzeuger ist deterministisch
      // kollisionsfrei (Snowflake-Verfahren, siehe HpsClient.newTransactionId),
      // kein Zufallsverfahren mehr. Eine lockere Toleranz bliebe auch dann
      // gruen, wenn er auf Zufall zurueckfiele -- ausgerechnet bei der
      // Eigenschaft, deren Verletzung den Vorfall vom 24.08.2026 ausgeloest
      // hat.
      final ids = List.generate(200, (_) => HpsClient.newTransactionId());
      expect(ids.toSet().length, 200);
    });
  });
}
