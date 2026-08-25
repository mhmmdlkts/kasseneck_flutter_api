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
  });

  /// POST /api/transaction/payment
  final List<Responder> payment;

  /// GET /api/v2/transactions/{tid}/{transactionId}
  final List<Responder> status;

  /// POST /api/transaction/abort/{tid}/{transactionId}
  final List<Responder> abort;

  /// POST /api/transaction/refund
  final List<Responder> refund;

  /// Alle gesehenen Requests, in Reihenfolge.
  final List<http.Request> log = <http.Request>[];

  final Map<String, int> _calls = <String, int>{};

  http.Client get client => MockClient((request) async {
        log.add(request);
        final route = _routeOf(request.url.path);
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

  static String _routeOf(String path) {
    // Reihenfolge zaehlt: der Abbruch-Pfad enthaelt 'transaction', der
    // Storno-Pfad enthaelt 'payment'.
    if (path.contains('/api/v2/transactions/')) return 'status';
    if (path.contains('/api/transaction/abort/')) return 'abort';
    if (path.contains('/api/transaction/refund')) return 'refund';
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
      default:
        return const <Responder>[];
    }
  }
}

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

HpsPayments paymentsFor(
  FakeTerminal terminal, {
  Duration? budget,
  HpsObserver? observer,
}) {
  final client = HpsClient(
    tid: '3600335',
    httpClient: terminal.client,
    timeout: const Duration(milliseconds: 200),
  );
  return HpsPayments(
    client,
    resolveBudget: budget ?? const Duration(seconds: 5),
    // Kein echtes Warten im Test -- der Backoff laeuft, aber ohne Zeitverlust.
    sleep: (_) async {},
    observer: observer,
  );
}

void main() {
  group('Zahlung mit geklaertem Ausgang', () {
    test('genehmigte Antwort -> approved, Kennung kommt zurueck', () async {
      final t = FakeTerminal(
        payment: [(_) => json({'responseCode': '0', 'transactionId': 'TX-1'})],
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
        status: [(_) => json({'responseCode': '0', 'transactionId': 'TX-3'})],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-3');
      expect(res.outcome, HpsOutcome.approved);
      expect(res.transactionId, 'TX-3');
    });

    test('Zahlung bricht ab, Status sagt abgelehnt -> declined', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [(_) => json({'responseCode': '51'})],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-4');
      expect(res.outcome, HpsOutcome.declined);
      expect(res.mayRetrySafely, isTrue);
    });

    test('laeuft noch, Abbruch gelingt -> declined (keine Karte aufgelegt)',
        () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [(_) => json({'transactionId': 'TX-5'})],
        abort: [(_) => json({'transactionId': 'TX-5'})],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-5');
      expect(res.outcome, HpsOutcome.declined);
      expect(
        t.log.any((r) => r.url.path.contains('/api/transaction/abort/')),
        isTrue,
      );
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
      final t = FakeTerminal(
        payment: [boom],
        status: [(_) => json({'transactionId': 'TX-7'})],
        abort: [(_) => fehler(400, 'nope')],
      );
      final res = await paymentsFor(t, budget: Duration.zero)
          .pay(amount: 25, transactionId: 'TX-7');
      expect(res.outcome, HpsOutcome.unresolved);
      expect(res.transactionId, 'TX-7');
      expect(res.mayRetrySafely, isFalse);
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
        payment: [(_) => json({'responseCode': '0'})],
      );
      final res = await paymentsFor(t).pay(amount: 25);
      final gesendet =
          jsonDecode(t.log.single.body) as Map<String, dynamic>;
      final tx = gesendet['transaction'] as Map<String, dynamic>;
      expect(tx['transactionId'], res.transactionId);
    });

    test('Antwort ohne Ergebniscode wird geklaert, nicht abgelehnt', () async {
      final t = FakeTerminal(
        // Die Zahlung antwortet, aber ohne responseCode -- das entscheidet
        // nichts und darf keinesfalls als Ablehnung gelten.
        payment: [(_) => json({'transactionId': 'TX-9'})],
        status: [(_) => json({'responseCode': '0', 'transactionId': 'TX-9'})],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-9');
      expect(res.outcome, HpsOutcome.approved);
      expect(t.callsOn('status'), greaterThan(0));
    });

    test('Trinkgeld und Referenz gehen mit hinaus', () async {
      final t = FakeTerminal(
        payment: [(_) => json({'responseCode': '0', 'transactionId': 'TX-10'})],
      );
      await paymentsFor(t)
          .pay(amount: 25, tip: 2, reference: 'B-42', transactionId: 'TX-10');
      final gesendet =
          jsonDecode(t.log.single.body) as Map<String, dynamic>;
      final tx = gesendet['transaction'] as Map<String, dynamic>;
      expect(tx['amount'], 25);
      expect(tx['tip'], 2);
      expect(tx['reference'], 'B-42');
      expect(tx['transactionId'], 'TX-10');
    });

    test('der Verlauf wird mitgeschrieben', () async {
      final t = FakeTerminal(
        payment: [boom],
        status: [(_) => json({'responseCode': '0', 'transactionId': 'TX-11'})],
      );
      final res = await paymentsFor(t).pay(amount: 25, transactionId: 'TX-11');
      expect(res.steps, isNotEmpty);
      expect(res.steps.length, greaterThanOrEqualTo(2));
    });

    test('der Beobachter erfaehrt von Klaerung und Ausgang', () async {
      final ereignisse = <HpsEvent>[];
      final t = FakeTerminal(
        payment: [boom],
        status: [(_) => json({'responseCode': '0', 'transactionId': 'TX-12'})],
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

    test('ein werfender Beobachter reisst den Zahlweg nicht mit', () async {
      final t = FakeTerminal(
        payment: [(_) => json({'responseCode': '0', 'transactionId': 'TX-13'})],
      );
      final res = await paymentsFor(
        t,
        observer: (_) => throw StateError('Protokoll kaputt'),
      ).pay(amount: 25, transactionId: 'TX-13');
      expect(res.outcome, HpsOutcome.approved);
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
