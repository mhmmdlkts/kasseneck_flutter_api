import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Eine Antwort des Terminal-Doppels auf genau einen Request.
///
/// `FutureOr`, damit ein Weg auch HAENGEN kann (eine nie erfuellte Zusage) --
/// anders liesse sich ein haengendes Terminal nicht nachbilden.
typedef Responder = FutureOr<http.Response> Function(http.Request request);

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
        return await handler(request);
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

/// Gemessene Form von HTTP 409 "Terminal is busy": `text/plain`, kein JSON --
/// siehe `doc/kartenzahlung.md`, "Das Terminal serialisiert".
http.Response busy(http.Request _) => http.Response(
      'Terminal is busy',
      409,
      headers: {'content-type': 'text/plain'},
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
          (_) => json({'responseCode': '0', 'transactionId': '81000800'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81000800');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81000800');
      expect(res.response, isNotNull);
    });

    test('abgelehnte Antwort (gemessener Code) -> declined', () async {
      // '51' war ein erfundener Platzhalter -- seit dem Umbau auf
      // ausschliesslich GEMESSENE Codes (siehe TransactionResponse.isConclusive)
      // ist ein nie gemessener Code kein Beleg fuer eine Ablehnung mehr.
      final t = FakeTerminal(
        payment: [
          (_) => json({
                'responseCode': TransactionResponse.cardNotPresentCode,
                'responseText': 'no card',
              }),
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002500');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, '81002500');
    });

    test('Zahlung bricht ab, Status sagt genehmigt -> approved', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81002600'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002600');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81002600');
    });

    test('Zahlung bricht ab, Status sagt abgelehnt (gemessen) -> declined',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': TransactionResponse.abortedCode})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002700');
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
        // Ein hinterlegter Status-Weg, der das Ergebnis KIPPEN wuerde, falls
        // er doch abgefragt wird. Ohne ihn koennte die Zusicherung "keine
        // Statusabfrage" gar nicht fehlschlagen: FakeTerminal wirft fuer einen
        // Weg ohne Responder, BEVOR der Zaehler hochgeht.
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81002800'})
        ],
        abort: [
          (_) => json({'responseCode': '0', 'transactionId': '81002800'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002800');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, '81002800');
      expect(res.response, isNotNull);
      expect(t.callsOn('abort'), 1);
      // Gegen den Log geprueft, nicht gegen den Zaehler.
      expect(t.log.where((r) => r.url.path.contains('/api/v2/')), isEmpty,
          reason: 'ein bewiesener Abbruch braucht keine Nachfrage mehr');
    });

    test('der Abbruch kommt VOR der ersten Statusabfrage', () async {
      // Die alte Reihenfolge (erst pollen, abbrechen nur wenn der Status
      // "laeuft noch" meldet) lief ins Leere: diesen Zustand meldet die
      // Statusabfrage nie.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81003400'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      await paymentsFor(t).pay(amount: 25, transactionId: '81003400');
      final wege = t.log
          .map((r) => r.url.path)
          .where((p) => p.contains('/abort/') || p.contains('/api/v2/'))
          .toList();
      expect(wege.first, contains('/abort/'));
    });

    test('Abbruch abgelehnt (100010) -> pollen, dann echtes Ergebnis',
        () async {
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
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002900');
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
          (_) => json({'responseCode': '0', 'transactionId': '81003000'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003000');
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
          (_) => json({'responseCode': '0', 'transactionId': '81003200'}),
        ],
        abort: [
          (_) => json({'transactionId': '81003200'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003200');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('abort'), 1);
      expect(t.callsOn('status'), 2);
    });

    test('Abbruch mit HTTP 404 wird als solcher benannt, nicht als Abriss', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '100015', 'responseText': 'unbekannt'}),
        ],
        abort: [(_) => http.Response('Not Found', 404)],
        status: [
          (_) => json({'responseCode': TransactionResponse.noStatementCode}),
          (_) => json({'responseCode': TransactionResponse.noStatementCode}),
        ],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: '81000800');

      expect(res.steps.any((s) => s.contains('HTTP 404')), isTrue);
      expect(
        res.steps.any((s) => s.contains('Abbruch-Endpunkt')),
        isTrue,
        reason: 'beide Lesarten des 404 muessen im Nachweis stehen',
      );
      expect(res.outcome, isNot(CardPaymentOutcome.approved));
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
          .pay(amount: 25, transactionId: '81003300');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: '9027 steht gleichermassen fuer "laeuft gerade", "nie '
              'gesehen" und "abgebrochen" -- daraus darf nie "gefahrlos '
              'wiederholbar" werden');
      expect(res.mayRetrySafely, isFalse);
      expect(res.transactionId, '81003300');
      expect(res.response, isNull,
          reason: 'eine Nicht-Aussage darf nicht als Beleg mitgegeben werden');
    });

    test(
        '9900 bis zum Budgetende -> unresolved, NIEMALS declined '
        '(Mutationsprobe)', () async {
      // Am 27.08.2026 gemessen: eine Statusabfrage auf eine nicht rein
      // numerische Kennung antwortet DAUERHAFT mit 9900 "Technical Error
      // Database" -- auch dann, wenn unter dem Vorgang eine echte Zahlung
      // lief. Ueber die fruehere Fassung von isConclusive ("jeder Code ausser
      // null und 9027 ist schluessig") waere das declined geworden -- fuer
      // einen Vorgang, unter dem Geld geflossen sein kann. Genau DAS ist die
      // Mutationsprobe: wird isConclusive wieder auf diese Weise gebaut, wird
      // dieser Test rot.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({
                'responseCode': '9900',
                'responseText': 'Technical Error Database',
              })
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 5))
          .pay(amount: 25, transactionId: '81005000');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: '9900 ist ein technischer Fehler des Terminals, keine '
              'Aussage ueber den Vorgang -- niemals "gefahrlos wiederholbar"');
      expect(res.mayRetrySafely, isFalse);
      expect(res.transactionId, '81005000');
      expect(
        res.steps.any((s) => s.contains('technischer Fehler (9900)')),
        isTrue,
        reason: 'der Nachweistext muss 9900 von 9027 UND von einem '
            'schlicht unbekannten Code unterscheiden',
      );
    });

    test(
        'unbekannter Code direkt, dann zweimal 9027 -> declined '
        '(Mutationsprobe)', () async {
      // Am 28.08.2026 gemessen: hat das Terminal die Zahlung mit einem
      // Ergebniscode beantwortet, ist der Vorgang dort BEENDET. Die
      // Statusabfrage unterscheidet dann sehr wohl: eine genehmigte Zahlung
      // antwortet "0" (Beleg 408811, dreimal geprueft), eine abgelehnte
      // antwortet 9027 (bei 100003 zweimal, bei 9003 einmal gemessen).
      //
      // Genau das deckt den Alltagsfall ab, dessen Code wir nicht kennen --
      // "keine Deckung", "Karte abgelaufen". Ohne die Regel endet er bei
      // unresolved: Warnung, stehender Merker, kein einfaches Nochmal.
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '5555', 'responseText': 'Unbekannt'})
        ],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9027'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 30))
          .pay(amount: 25, transactionId: '81009100');

      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, '81009100');
      expect(
        res.steps.any((s) => s.contains('zweimal ohne Auskunft')),
        isTrue,
        reason: 'der Nachweis muss benennen, WORAUF die Ablehnung beruht',
      );
    });

    test('unbekannter Code direkt, aber nur EINE Statusabfrage -> unresolved',
        () async {
      // Die erste Abfrage laeuft unmittelbar nach der Antwort -- das Fenster,
      // in dem der Datensatz am Terminal noch nicht stehen koennte. Wer sie
      // allein entscheiden laesst, baut die Doppelbelastung vom 24.08.2026 an
      // einer neuen Stelle nach.
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '5555', 'responseText': 'Unbekannt'})
        ],
        status: [
          (_) => json({'responseCode': '9027'}),
          boom,
          boom,
          boom,
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 30))
          .pay(amount: 25, transactionId: '81009200');

      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'eine einzelne 9027 entscheidet nicht');
      expect(res.mayRetrySafely, isFalse);
    });

    test(
        'GAR KEINE Antwort, dann zweimal 9027 -> bleibt unresolved '
        '(Mutationsprobe)', () async {
      // Der Vorfall vom 24.08.2026 selbst: die Antwort geht verloren, die
      // Zahlung laeuft am Terminal weiter. Hier ist NICHT bekannt, dass der
      // Vorgang beendet ist -- 9027 bleibt eine reine Nicht-Aussage, weil sie
      // auch "laeuft noch" heissen kann.
      //
      // Wird die Regel je so gebaut, dass sie ohne die vorangegangene Antwort
      // mit Code greift, wird dieser Test rot -- und genau das muss er.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9027'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 30))
          .pay(amount: 25, transactionId: '81009300');

      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.mayRetrySafely, isFalse);
    });

    test('eine genehmigte Zahlung bleibt genehmigt, auch nach 9027 davor',
        () async {
      // Die Reihenfolge, vor der die Zwei-Abfragen-Regel schuetzt: der
      // Datensatz steht beim ersten Blick noch nicht, beim zweiten schon.
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '5555', 'responseText': 'Unbekannt'})
        ],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'receipt': '408811'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 30))
          .pay(amount: 25, transactionId: '81009400');

      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.response?.receipt, '408811');
    });

    test('9003, 100019 und 100108 sind gemessene Ablehnungen -> declined',
        () async {
      // Alle drei weist das Terminal ab, BEVOR es eine Karte verlangt
      // (27./28.08.2026). Sie sind damit positive Aussagen ueber den Ausgang,
      // keine Wissensluecken -- eine Klaerungsrunde waere reine Wartezeit.
      for (final fall in <List<String>>[
        <String>['9003', 'Invalid Amount', '81009500'],
        <String>['100019', 'Amount is not in a valid range', '81009600'],
        <String>['100108', 'Invalid TID', '81009700'],
      ]) {
        final t = FakeTerminal(
          payment: [
            (_) => json({'responseCode': fall[0], 'responseText': fall[1]})
          ],
        );
        final res = await paymentsFor(t).pay(amount: 25, transactionId: fall[2]);

        expect(res.outcome, CardPaymentOutcome.declined,
            reason: '${fall[0]} ist gemessen: nichts belastet');
        expect(res.mayRetrySafely, isTrue);
        expect(t.log.where((r) => r.url.path.contains('v2/transactions')),
            isEmpty,
            reason: 'ein gemessener Code braucht keine Klaerungsrunde');
      }
    });

    test(
        'zwei 9027 mit etwas dazwischen zaehlen nicht als zwei in Folge '
        '(Mutationsprobe)', () async {
      // "Zweimal" heisst HINTEREINANDER. Antwortet das Terminal dazwischen
      // ohne Ergebniscode -- also "laeuft noch" --, faengt das Zaehlen von
      // vorn an. Wer den Zaehler nicht zuruecksetzt, sammelt 9027 quer ueber
      // die ganze Klaerung ein und entscheidet auf einer Grundlage, die es so
      // nie gab.
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '5555', 'responseText': 'Unbekannt'})
        ],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json(<String, dynamic>{}),
          (_) => json({'responseCode': '9027'}),
          boom,
          boom,
          boom,
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 30))
          .pay(amount: 25, transactionId: '81009800');

      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.mayRetrySafely, isFalse);
    });

    test(
        'HTTP 409 auf die Zahlung selbst -> sofort declined, ohne '
        'Klaerung (Mutationsprobe)', () async {
      // Am 27.08.2026 gemessen: laeuft bereits ein Vorgang und wird ein
      // zweiter gestartet, kommt 409 "Terminal is busy" nach 87 ms. Der
      // abgewiesene Vorgang hinterlaesst KEINE Spur -- die Statusabfrage auf
      // seine Kennung liefert 9027, zweimal geprueft. Das ist eine positive
      // Aussage: sofort declined, ohne Abbruchversuch und ohne Polling.
      final t = FakeTerminal(payment: [busy]);
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81005100');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, '81005100');
      expect(
        res.steps.any((s) => s.contains('Terminal beschaeftigt (HTTP 409)')),
        isTrue,
      );
      expect(t.callsOn('abort'), 0,
          reason: 'die Anfrage wurde nachweislich nicht angenommen -- eine '
              'Klaerung waere ueberfluessig');
      expect(t.log.where((r) => r.url.path.contains('/api/v2/')), isEmpty);
    });

    test(
        'HTTP 409 auf den Abbruchversuch bleibt ein Transportfehler -- '
        'NIEMALS declined (Mutationsprobe)', () async {
      // 409 gilt AUSDRUECKLICH nur fuer die ERZEUGENDE Anfrage. Hier scheitert
      // die Zahlung generisch (Leitungsabriss), die Klaerung versucht einen
      // Abbruch -- UND DER bekommt 409. Das sagt nichts ueber die Zahlung
      // selbst aus und darf sie nicht zu declined machen.
      final t = FakeTerminal(
        payment: [boom],
        abort: [busy],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81005200'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81005200');
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: 'ein 409 auf den Abbruch darf die tatsaechlich genehmigte '
              'Zahlung nicht als declined ausweisen');
      expect(
        res.steps.any((s) => s.contains('Terminal beschaeftigt')),
        isFalse,
        reason: 'die 409-Sonderbehandlung gilt nicht fuer den Abbruch',
      );
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test(
        'HTTP 409 beim Pollen der Statusabfrage bleibt ein Transportfehler '
        '-- NIEMALS declined (Mutationsprobe)', () async {
      // Dieselbe Vorsicht wie beim Abbruch: 409 auf eine STATUSABFRAGE sagt
      // nur, dass DIESE Abfrage nicht durchkam -- nichts ueber den Vorgang.
      final t = FakeTerminal(
        payment: [boom],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
        status: [busy, busy, busy],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81005300');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'ein 409 auf die Statusabfrage ist ein Transportfehler wie '
              'jeder andere, kein Beleg fuer irgendeinen Ausgang');
      expect(
        res.steps.any((s) => s.contains('Terminal beschaeftigt')),
        isFalse,
      );
      expect(t.callsOn('status'), 3,
          reason: 'drei aufeinanderfolgende Fehlschlaege beenden die '
              'Klaerung vorzeitig -- wie bei jedem anderen Transportfehler');
    });

    test('refund: HTTP 409 -> sofort declined', () async {
      final t = FakeTerminal(refund: [busy]);
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: '81005400');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(
        res.steps.any((s) => s.contains('Terminal beschaeftigt (HTTP 409)')),
        isTrue,
      );
      expect(t.callsOn('abort'), 0);
    });

    test(
        'cancel: HTTP 409 auf den direkten Aufhebungs-Request -> sofort '
        'declined', () async {
      // Fuer cancel heisst declined "die Aufhebung hat nicht gegriffen" --
      // exakt das, was 409 hier aussagt: der Void-Request wurde nicht
      // angenommen, es ist nichts geschehen, ein erneuter Versuch ist
      // gefahrlos.
      final t = FakeTerminal(cancel: [busy]);
      final res =
          await paymentsFor(t).cancel(transactionId: '81005500', amount: 25);
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.transactionId, '81005500');
      expect(
        res.steps.any((s) => s.contains('Terminal beschaeftigt (HTTP 409)')),
        isTrue,
      );
      expect(t.log.where((r) => r.url.path.contains('/api/v2/')), isEmpty);
    });

    test('ein UNGEMESSENER Abbruch-Fehlercode behauptet keine Ursache',
        () async {
      // Gemessen ist nur 100010 ("nicht mehr abbrechbar"). Fuer jeden anderen
      // Code darf [steps] -- der Nachweis im Belastungsstreit -- keine Ursache
      // erfinden.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81003500'})
        ],
        abort: [
          (_) => json({'responseCode': '77777'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003500');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.steps.any((s) => s.contains('nicht mehr abbrechbar')), isFalse,
          reason: 'die Ursache ist fuer diesen Code nicht belegt');
      expect(res.steps.any((s) => s.contains('Grund unbekannt')), isTrue);
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
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003100');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'ohne Ergebniscode bleibt der Ausgang offen, er wird nicht '
              'zu declined geraten');
      expect(res.transactionId, '81003100');
    });

    test('HTTP-Fehler beim Abbruch -> pollen, kein geratenes Ergebnis',
        () async {
      // Ein Nicht-2xx ist keine Aussage ueber den Vorgang. Gemessen meldet das
      // Terminal ein gescheitertes Abbrechen ohnehin mit 200 und 100010.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': '81003900'}),
        ],
        abort: [(_) => fehler(400, 'bad request')],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003900');
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
          (_) => json({'responseCode': '0', 'transactionId': '81003600'}),
        ],
        abort: [boom],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003600');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test('ein am Transport gescheiterter Abbruch kostet keine Klaerrunde',
        () async {
      // Der Transportfehler-Zaehler gilt der Statusabfrage. Zaehlte der
      // Abbruch mit, bliebe nach zwei Abfragen Schluss -- obwohl ueber die
      // Erreichbarkeit der Statusabfrage noch nichts bekannt war.
      final t = FakeTerminal(payment: [boom], status: [boom], abort: [boom]);
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004000');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(t.callsOn('status'), 3);
    });

    test('ein haengender Abbruch frisst nicht das ganze Klaerbudget', () async {
      // Der Abbruch startet bei elapsed == 0 und haette ohne eigenen Deckel
      // das VOLLE Budget im Ruecken. Danach waere die Schleife sofort vorbei,
      // ohne eine einzige Statusabfrage -- der Klaerweg komplett verloren.
      // Hier: Budget 600 ms, Abbruch also auf 100 ms gedeckelt.
      //
      // Einziger Test mit echter (aber gedeckelter) Wartezeit, ~100 ms.
      // Der Grund ist genauer als "geht nicht": mit den Naehten DIESES
      // Doppels geht es nicht, weil Future.timeout an einem echten Timer
      // haengt -- die injizierte Uhr rueckt nur durch Pausen vor und sieht
      // eine Frist nie. Sauber loesen liesse sich das mit package:fake_async
      // (virtuelle Zeit fuer genau solche Timer). Bewusst nicht gemacht:
      // fake_async liegt zwar transitiv ueber flutter_test im Paketgraph,
      // aber direkt importieren duerfte man es erst als eigenes
      // dev_dependency -- ein neues Abhaengigkeitsglied fuer einen einzigen
      // Test, dessen Wanduhrzeit gedeckelt und deterministisch ist. Die
      // Reserve ist bewusst grosszuegig (600 ms Budget gegen ~100 ms
      // Frist), damit eine ausgelastete Maschine den Test nicht kippt.
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81003800'})
        ],
        abort: [(_) => Completer<http.Response>().future],
      );
      final zahlweg = HpsPayments(
        HpsClient(
          tid: '3600335',
          httpClient: t.client,
          timeout: const Duration(seconds: 2),
        ),
        resolveBudget: const Duration(milliseconds: 600),
        sleep: (_) async {},
      );
      final res = await zahlweg.pay(amount: 25, transactionId: '81003800');
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: 'nach dem gedeckelten Abbruch muss noch Budget fuer die '
              'Statusabfrage uebrig sein');
      expect(t.callsOn('status'), 1);
      expect(
        res.steps.any((s) => s.contains('Abbruch nicht bestaetigt')),
        isTrue,
      );
    });

    test('der Abbruch wird nur ein einziges Mal versucht', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': '81003700'}),
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81003700');
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
          .pay(amount: 25, transactionId: '81004100');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, '81004100');
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
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004200');
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'ein Transportfehler beweist nicht, dass nichts gestartet '
              'wurde');
      expect(res.transactionId, '81004200');
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
          (_) => json({'transactionId': '81004300'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81004300'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004300');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('9027 schon in der Zahlungsantwort wird geklaert, nicht abgelehnt',
        () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '9027', 'transactionId': '81004500'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81004500'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004500');
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
          (_) => json({'responseCode': '', 'transactionId': '81004400'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81004400'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004400');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0),
          reason: 'ein leerer Code muss wie ein fehlender weiter geklaert '
              'werden, nicht sofort als declined durchgehen');
    });

    test('der Verlauf behauptet bei 9027 keinen fehlenden Ergebniscode',
        () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '9027', 'transactionId': '81004600'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81004600'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004600');
      expect(res.steps.any((s) => s.contains('ohne Ergebniscode')), isFalse,
          reason: 'ein 9027 IST ein Ergebniscode -- er traegt nur keine '
              'Aussage');
      expect(res.steps.any((s) => s.contains('ohne Aussage (9027)')), isTrue);
    });

    test('der Verlauf nennt einen wirklich fehlenden Code als solchen',
        () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'transactionId': '81004700'})
        ],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81004700'})
        ],
        abort: [
          (_) => json({'responseCode': '100010'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81004700');
      expect(res.steps.any((s) => s.contains('ohne Ergebniscode')), isTrue);
    });

    test('Trinkgeld und Referenz gehen mit hinaus', () async {
      final t = FakeTerminal(
        payment: [
          (_) => json({'responseCode': '0', 'transactionId': '81000900'})
        ],
      );
      await paymentsFor(t).pay(
          amount: 25, tip: 2, reference: 'B-42', transactionId: '81000900');
      final gesendet = jsonDecode(t.log.single.body) as Map<String, dynamic>;
      final tx = gesendet['transaction'] as Map<String, dynamic>;
      expect(tx['amount'], 25);
      expect(tx['tip'], 2);
      expect(tx['reference'], 'B-42');
      expect(tx['transactionId'], '81000900');
    });

    test('der Verlauf wird mitgeschrieben', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81001000'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81001000');
      expect(res.steps, isNotEmpty);
      expect(res.steps.length, greaterThanOrEqualTo(2));
    });

    test('der Beobachter erfaehrt von Klaerung und Ausgang', () async {
      final ereignisse = <HpsEvent>[];
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81001300'})
        ],
      );
      await paymentsFor(t, observer: ereignisse.add)
          .pay(amount: 25, transactionId: '81001300');
      expect(ereignisse.any((e) => e.kind == HpsEventKind.resolving), isTrue);
      expect(ereignisse.any((e) => e.kind == HpsEventKind.resolved), isTrue);
      expect(
        ereignisse.every((e) => e.transactionId == '81001300'),
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
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002000');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, '81002000',
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
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002100');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, '81002100');
    });

    test('unlesbare Abbruch-Antwort reisst die Klaerung nicht mit', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [
          (_) => json({'responseCode': '9027'}),
          (_) => json({'responseCode': '0', 'transactionId': '81002200'}),
        ],
        // 200, aber die Auswertung wirft.
        abort: [(_) => http.Response('kein JSON', 200)],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002200');
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
          (_) => json({'responseCode': '0', 'transactionId': '81002300'}),
        ],
        abort: [
          (_) =>
              json({'responseCode': '100010', 'responseText': 'not abortable'})
        ],
      );
      final res =
          await paymentsFor(t).pay(amount: 25, transactionId: '81002300');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(
        res.steps.any((s) => s.contains('Abbruch abgelehnt (100010)')),
        isTrue,
      );
      expect(
        res.steps.any((s) => s.contains('keine Auskunft (9027)')),
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
          .pay(amount: 25, transactionId: '81002400');
      final eigen = ereignisse.where((e) => e.error is FormatException);
      expect(eigen, isNotEmpty,
          reason: 'ein Fehler im eigenen Auswerten darf nicht lautlos zu '
              'einem Klaerungslauf werden');
      expect(eigen.every((e) => e.kind == HpsEventKind.requestFailed), isTrue);
      expect(eigen.every((e) => e.transactionId == '81002400'), isTrue);
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
          (_) => json({'responseCode': '0', 'transactionId': '81001600'})
        ],
      );
      final res = await paymentsFor(
        t,
        observer: (_) => throw StateError('Protokoll kaputt'),
      ).pay(amount: 25, transactionId: '81001600');
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
            for (var i = 0; i < runden; i++)
              (_) => json({'responseCode': '9027'}),
            (_) => json({'responseCode': '0', 'transactionId': '81004800'}),
          ],
          abort: [
            (_) => json({'responseCode': '100010'})
          ],
        );

    test('die erste Abfrage laeuft sofort, dann wird verdoppelt', () async {
      final pausen = <Duration>[];
      final res = await paymentsFor(zaeh(4), pausen: pausen)
          .pay(amount: 25, transactionId: '81004800');
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
          .pay(amount: 25, transactionId: '81004800');
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
      ).pay(amount: 25, transactionId: '81004800');
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
          .pay(amount: 25, transactionId: '81004900');
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
          (_) => json({'responseCode': '0', 'transactionId': '81000300'})
        ],
      );
      final res = await paymentsFor(t).refund(
        amount: 25,
        transactionId: '81000300',
        originalTransactionId: '81000800',
      );
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81000300');
      expect(txBodyOf(t.log.single)['originalTransactionId'], '81000800');
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
          await paymentsFor(t).refund(amount: 25, transactionId: '81000400');
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81000400');
    });

    test('refund: derselbe Klaerweg wie bei pay -- Abbruch zuerst', () async {
      // Die Kennung ist die des NEUEN Vorgangs, und der Abbruch-Endpunkt
      // kennt keinen Transaktionstyp. Ohne den Abbruch haette die Klaerung
      // einer Gutschrift gar keinen Diskriminator und endete fast immer bei
      // unresolved -- die Statusabfrage antwortet auch hier 9027.
      final t = FakeTerminal(
        refund: [boom],
        // Ein Status-Weg, der das Ergebnis kippen wuerde, falls doch gepollt
        // wird -- siehe die gleiche Begruendung beim Zahlweg.
        status: [
          (_) => json({'responseCode': '0', 'transactionId': '81000600'})
        ],
        abort: [
          (_) => json({'responseCode': '0', 'transactionId': '81000600'})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: '81000600');
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(t.callsOn('abort'), 1);
      expect(t.log.where((r) => r.url.path.contains('/api/v2/')), isEmpty);
      expect(t.log.any((r) => r.url.path.contains('/abort/3600335/81000600')),
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
          .refund(amount: 25, transactionId: '81000700');
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.mayRetrySafely, isFalse);
    });

    test('refund: abgelehnte Antwort (gemessener Code) -> declined', () async {
      final t = FakeTerminal(
        refund: [
          (_) => json({'responseCode': TransactionResponse.abortedCode})
        ],
      );
      final res =
          await paymentsFor(t).refund(amount: 25, transactionId: '81000500');
      expect(res.outcome, CardPaymentOutcome.declined);
    });

    test(
        'refund: 9002 (ungueltige Original-Kennung) -> declined, so '
        'gemessen', () async {
      // Am 27.08.2026 gemessen: eine Gutschrift auf eine unbekannte, rein
      // numerische Original-Kennung antwortet mit 9002 -- kein Kartenfluss,
      // keine Auszahlung.
      final t = FakeTerminal(
        refund: [
          (_) => json({
                'responseCode': TransactionResponse.invalidTransactionCode,
                'responseText': 'Invalid Transaction',
              })
        ],
      );
      final res = await paymentsFor(t).refund(
        amount: 25,
        transactionId: '81005600',
        originalTransactionId: '999999999999999999',
      );
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
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

    test('cancel: direkte Ablehnung (gemessener Code) -> declined', () async {
      final t = FakeTerminal(
        cancel: [
          (_) => json({
                'responseCode': TransactionResponse.cardNotPresentCode,
                'responseText': 'no card',
              })
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: '81004400', amount: 25);
      expect(res.outcome, CardPaymentOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
      expect(res.transactionId, '81004400');
    });

    test(
        'cancel: direkte Genehmigung -> approved, Kennung bleibt die '
        'urspruengliche', () async {
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '0', 'transactionId': '81004300'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: '81004300', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81004300');
      expect(t.log.single.url.path, contains('81004300'));
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
          await paymentsFor(t).cancel(transactionId: '81000900', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
      expect(res.transactionId, '81000900');
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
            (_) => json({'responseCode': '0', 'transactionId': '81001000'}),
          ],
        );
        final res = await paymentsFor(t, budget: const Duration(seconds: 5))
            .cancel(transactionId: '81001000', amount: 25);
        expect(res.outcome, CardPaymentOutcome.declined,
            reason: 'declined heisst hier "die Aufhebung hat nicht gegriffen" '
                '-- keinesfalls "die Aufhebung war erfolgreich"');
        expect(res.isApproved, isFalse);
        expect(res.transactionId, '81001000');
        expect(
          res.steps.any((s) => s.contains('steht unveraendert')),
          isTrue,
        );
        expect(t.callsOn('status'), 2,
            reason: 'ein einzelnes "0" entscheidet nicht -- es wird '
                'bestaetigt');
      },
    );

    test(
      'cancel: ein einzelnes "0" entscheidet nichts -- der Void kann noch '
      'unterwegs sein',
      () async {
        // Die erste Abfrage laeuft ohne Pause, unmittelbar nachdem der
        // Void-Request abgerissen ist. Genau in diesem Fenster kann der Void
        // noch unterwegs sein. Ein voreiliges "hat nicht gegriffen" ist NICHT
        // harmlos: nach dem Tagesabschluss ist die Folgehandlung eine
        // Rueckerstattung, und der Kunde bekaeme sein Geld zweimal.
        final t = FakeTerminal(
          cancel: [boom],
          status: [
            (_) => json({'responseCode': '0', 'transactionId': '81001100'})
          ],
        );
        final res =
            await paymentsFor(t, budget: const Duration(milliseconds: 50))
                .cancel(transactionId: '81001100', amount: 25);
        expect(res.outcome, CardPaymentOutcome.unresolved,
            reason: 'reicht das Budget nur fuer eine Abfrage, sagen wir, dass '
                'wir es nicht wissen');
        expect(t.callsOn('status'), 1);
      },
    );

    test('cancel: der Void landet zwischen erster und zweiter Abfrage',
        () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          // Noch unterwegs: die Originalzahlung sieht unveraendert aus.
          (_) => json({'responseCode': '0', 'transactionId': '81001200'}),
          // Eine Sekunde spaeter ist er verbucht.
          (_) => json({'responseCode': '9011'}),
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: '81001200', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: 'die Karenz faengt genau diesen Fall');
    });

    test('cancel: 9027 entscheidet nichts -> unresolved, kein Raten', () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'responseCode': '9027'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: '81001300', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
    });

    test('cancel: Antwort ohne Ergebniscode -> unresolved, kein Raten',
        () async {
      final t = FakeTerminal(
        cancel: [boom],
        status: [
          (_) => json({'transactionId': '81001400'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(milliseconds: 50))
          .cancel(transactionId: '81001400', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
    });

    test('cancel: state VOID gilt zusaetzlich, ist aber nie notwendig',
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
          await paymentsFor(t).cancel(transactionId: '81001500', amount: 25);
      expect(res.outcome, CardPaymentOutcome.approved);
    });

    test('cancel: 9011 auf dem DIREKTEN Weg wird nie zu declined', () async {
      // Ueber das generische _fromResponse waere 9011 ein "Code ungleich 0"
      // und damit declined = "weiterhin belastet". Das ist das Gegenteil
      // dessen, was _fromCancelStatus aus demselben Code ableitet -- und die
      // teure Richtung: es laedt zu einer Rueckerstattung ein.
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '9011'})
        ],
        status: [
          (_) => json({'responseCode': '9011'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: '81001700', amount: 25);
      expect(res.outcome, isNot(CardPaymentOutcome.declined));
      expect(res.outcome, CardPaymentOutcome.approved,
          reason: 'der mehrdeutige Direktcode wird nicht geraten, sondern am '
              'Zustand der Originalzahlung geklaert');
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('cancel: der Verlauf behauptet bei 9011 keinen fehlenden Code',
        () async {
      // [steps] ist der Nachweis, der im Belastungsstreit angezeigt wird.
      // "Antwort ohne Ergebniscode" waere dort unwahr: ein Code WAR da, er
      // war nur mehrdeutig.
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '9011'})
        ],
        status: [
          (_) => json({'responseCode': '9011'})
        ],
      );
      final res =
          await paymentsFor(t).cancel(transactionId: '81001900', amount: 25);
      expect(res.steps.any((s) => s.contains('ohne Ergebniscode')), isFalse);
      expect(res.steps.any((s) => s.contains('mehrdeutig')), isTrue);
    });

    test('cancel: 9011 direkt, aber die Klaerung findet nichts -> unresolved',
        () async {
      final t = FakeTerminal(
        cancel: [
          (_) => json({'responseCode': '9011'})
        ],
        status: [
          (_) => json({'responseCode': '9027'})
        ],
      );
      final res = await paymentsFor(t, budget: const Duration(seconds: 5))
          .cancel(transactionId: '81001800', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved,
          reason: 'was 9011 auf dem Direktweg heisst, ist ungemessen -- es '
              'darf auch keinen Erfolg vortaeuschen');
    });

    test('cancel: Transportfehler durchgehend -> unresolved', () async {
      final t = FakeTerminal(cancel: [boom], status: [boom]);
      final res =
          await paymentsFor(t).cancel(transactionId: '81001600', amount: 25);
      expect(res.outcome, CardPaymentOutcome.unresolved);
      expect(res.transactionId, '81001600');
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
          await paymentsFor(t).cancel(transactionId: '81002000', amount: 25);
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
