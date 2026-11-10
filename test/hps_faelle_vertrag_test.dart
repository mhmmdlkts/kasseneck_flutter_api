import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Die Prueffaelle aus dem Vertrag des npm-Zwillings
/// (`test/fixtures/vertrag/hobex-hps-cases.json`, gezogen ueber
/// `tool/zwillinge.sh`) -- dieselben Faelle rechnet
/// `test/hobex-hps-faelle.test.ts` im npm-Paket.
///
/// Das Terminal-Doppel antwortet je Weg aus dem Prueffall und weist wie das
/// echte HPS jeden Aufruf mit einer anderen TID als `hpsTid` mit der
/// gemessenen Antwort `invalidTid` ab. Eingetragen ist `clarifyTid`, also die
/// TID mit fuehrender Null wie auf dem Beleg.
void main() {
  final Map<String, dynamic> vertrag = jsonDecode(
    File('test/fixtures/vertrag/hobex-hps-cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final antworten = (vertrag['responses'] as Map).cast<String, dynamic>();
  final hpsTid = vertrag['hpsTid'] as String;
  final clarifyTid = vertrag['clarifyTid'] as String;

  /// Die Antwort [name] aus `responses`, ohne die Messvermerke (`_…`).
  Map<String, dynamic> antwort(String name) {
    final a = antworten[name] as Map<String, dynamic>?;
    if (a == null) {
      throw StateError('Prueffall nennt die Antwort "$name", die in responses fehlt');
    }
    return {
      for (final e in a.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
    };
  }

  test('Vertrag: Prueffaelle vorhanden', () {
    expect(vertrag['tid'] as List, isNotEmpty);
    expect(vertrag['receipts'] as List, isNotEmpty);
    expect(vertrag['clarify'] as List, isNotEmpty);
    expect(clarifyTid, isNot(hpsTid),
        reason: 'die eingetragene TID soll eine Umschreibung brauchen');
  });

  test('TID: welche Schreibweise hinausgeht (HpsClient.tid)', () {
    for (final f in (vertrag['tid'] as List).cast<Map<String, dynamic>>()) {
      final client = HpsClient(
        tid: f['input'] as String,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(client.tid, f['expected'],
          reason: f['name'] as String? ?? jsonEncode(f['input']));
    }
  });

  test(
      'TID 03600335 geht bei jedem Aufruf als 3600335 hinaus: Zahlung, '
      'Status, Abbruch, Aufhebung, Gutschrift, Diagnose', () async {
    final gesendet = <({String weg, String? tid})>[];
    final client = HpsClient(
      tid: '03600335',
      httpClient: MockClient((request) async {
        final tid = _tidOf(request);
        gesendet.add((weg: _wegOf(request), tid: tid));
        return _json(tid == hpsTid ? {'responseCode': '0'} : antwort('invalidTid'));
      }),
    );
    const zahlung = '261110033825505723';

    final ergebnisse = [
      await client.payment(amount: 0.01, transactionId: zahlung),
      await client.transactionStatus(transactionId: zahlung),
      await client.abort(transactionId: zahlung),
      await client.cancel(transactionId: zahlung, amount: 0.01),
      await client.refund(
        amount: 0.01,
        transactionId: '261110033825505729',
        originalTransactionId: zahlung,
      ),
    ];
    final diagnose = await client.diagnosis();

    expect(gesendet.map((g) => g.weg).toList(),
        ['payment', 'status', 'abort', 'cancel', 'refund', 'diagnosis']);
    for (final g in gesendet) {
      expect(g.tid, '3600335', reason: g.weg);
    }
    for (final e in ergebnisse) {
      expect(e.responseCode, '0');
    }
    expect(diagnose.responseCode, '0');
  });

  for (final fall
      in (vertrag['receipts'] as List).cast<Map<String, dynamic>>()) {
    test('Beleg: ${fall['name']}', () {
      final roh = {
        ...antwort(fall['response'] as String),
        ...((fall['overrides'] as Map<String, dynamic>?) ?? const {}),
      };
      final erwartet = fall['expected'] as Map<String, dynamic>;
      final beleg = HobexReceipt.fromHps(TransactionResponse.fromJson(roh));
      expect((beleg.amount * 100).round(), erwartet['amountCents'],
          reason: 'amountCents');
      expect((beleg.tip * 100).round(), erwartet['tipCents'],
          reason: 'tipCents');
      expect(beleg.toCardPaymentData(),
          (erwartet['cardPaymentData'] as Map).cast<String, String>());
    });
  }

  /// Fuehrt einen Klaerfall gegen das Terminal-Doppel aus. [zusatz] stellt
  /// Antworten bereit, die nicht in `responses` stehen (reversalAnswers).
  Future<({HpsResult res, List<({String weg, String? tid, int? cent})> aufrufe})>
      klaeren(Map<String, dynamic> fall,
          [Map<String, Map<String, dynamic>> zusatz = const {}]) async {
    final id = fall['transactionId'] as String;
    final laeuftWeiter = fall['abortWhilePaymentRuns'] == true;
    final status = (fall['status'] as List).cast<String>();
    final aufrufe = <({String weg, String? tid, int? cent})>[];
    final gesendet = Completer<void>();
    final freigabe = Completer<void>();
    var statusIndex = 0;

    final client = HpsClient(
      tid: clarifyTid,
      timeout: const Duration(seconds: 5),
      httpClient: MockClient((request) async {
        final weg = _wegOf(request);
        final tid = _tidOf(request);
        aufrufe.add((weg: weg, tid: tid, cent: _stornoCent(request)));
        if ((weg == 'payment' || weg == 'refund') &&
            laeuftWeiter &&
            !gesendet.isCompleted) {
          gesendet.complete();
        }
        // Wie das HPS: eine fremde TID wird sofort abgewiesen.
        if (tid != hpsTid) return _json(antwort('invalidTid'));
        final String name;
        switch (weg) {
          case 'payment' || 'refund':
            if (laeuftWeiter) await freigabe.future;
            name = fall['request'] as String;
          case 'abort':
            name = fall['abort'] as String;
          case 'cancel':
            final storno = fall['reversal'] as String?;
            if (storno == null) {
              throw StateError('Prueffall "${fall['name']}" sieht kein Storno vor');
            }
            name = storno;
          case 'status':
            name = status[statusIndex < status.length
                ? statusIndex
                : status.length - 1];
            statusIndex++;
          default:
            throw StateError('Prueffall sieht keinen Aufruf $weg vor');
        }
        if (name == _transport) throw const _Leitungsabriss();
        if (name == _http404) {
          return http.Response(jsonEncode({'message': 'Not Found'}), 404,
              headers: {'content-type': 'application/json'});
        }
        if (name == _http409) {
          // Gemessene Form: text/plain, kein JSON (doc/kartenzahlung.md).
          return http.Response('Terminal is busy', 409,
              headers: {'content-type': 'text/plain'});
        }
        return _json(zusatz[name] ?? antwort(name));
      }),
    );
    final uhr = _Uhr();
    final payments = HpsPayments(
      client,
      resolveBudget: Duration(milliseconds: fall['resolveBudgetMs'] as int),
      sleep: (d) async => uhr.vor(d),
      clock: () => uhr,
    );
    final betrag = (fall['amountCents'] as int) / 100;
    final trinkgeld = fall['tipCents'] as int?;
    final lauf = fall['operation'] == 'pay'
        ? payments.pay(
            amount: betrag,
            tip: trinkgeld == null ? null : trinkgeld / 100,
            transactionId: id,
          )
        : payments.refund(
            amount: betrag,
            transactionId: id,
            originalTransactionId: fall['originalTransactionId'] as String,
          );
    if (laeuftWeiter) {
      // Wie der Abbrechen-Knopf der Kasse: eigener Abbruch, waehrend pay()
      // noch auf die Antwort wartet.
      await gesendet.future;
      await client.abort(transactionId: id);
      freigabe.complete();
    }
    return (res: await lauf, aufrufe: aufrufe);
  }

  for (final fall
      in (vertrag['clarify'] as List).cast<Map<String, dynamic>>()) {
    test('Klaerung: ${fall['name']}', () async {
      final erwartet = fall['expected'] as Map<String, dynamic>;
      final id = fall['transactionId'] as String;
      final (:res, :aufrufe) = await klaeren(fall);

      expect(res.outcome.name, erwartet['outcome']);
      expect(res.reason?.name, erwartet['reason']);
      expect(res.transactionId, id);
      final felder = erwartet['response'] as Map<String, dynamic>?;
      if (felder == null) {
        expect(res.response, isNull, reason: 'ein offener Ausgang hat keinen Beleg');
      } else {
        expect(res.response, isNotNull, reason: 'die festschreibende Antwort fehlt');
        for (final e in felder.entries) {
          expect(_feld(res.response!, e.key), e.value, reason: e.key);
        }
      }
      if (erwartet.containsKey('lastResponseCode')) {
        expect(res.lastResponse?.responseCode, erwartet['lastResponseCode']);
      }
      expect(aufrufe.where((a) => a.weg == 'abort').length,
          erwartet['abortCalls'],
          reason: 'Abbrueche');
      expect(aufrufe.where((a) => a.weg == 'status').length,
          erwartet['statusCalls'],
          reason: 'Statusabfragen');
      final stornos = aufrufe.where((a) => a.weg == 'cancel').toList();
      expect(stornos.length, erwartet['reversalCalls'] ?? 0, reason: 'Stornos');
      if (erwartet.containsKey('reversalAmountCents')) {
        for (final s in stornos) {
          expect(s.cent, erwartet['reversalAmountCents'],
              reason: 'Stornobetrag in Cent');
        }
      }
      for (final a in aufrufe) {
        expect(a.tid, hpsTid, reason: 'TID beim Weg ${a.weg}');
      }
      final schritt = erwartet['stepIncludes'] as String?;
      if (schritt != null) {
        expect(res.steps.any((s) => s.contains(schritt)), isTrue,
            reason: res.steps.join(' | '));
      }
      if (erwartet['outcome'] != 'declined') {
        expect(res.steps.where((s) => s.contains('nichts belastet')), isEmpty,
            reason: 'der Nachweis behauptet "nichts belastet", obwohl der '
                'Ausgang es nicht sagt');
      }
    });
  }

  // reversalAnswers: dieselbe Zahlung (9908, Trinkgeld) je Antwort auf das
  // Storno. Was nach der Positivliste nicht ausgefuehrt wurde, laesst eine
  // Genehmigung im Status gelten; alles andere, auch jeder Storniert-Code,
  // nimmt ihr die Aussage.
  final stornoAntworten =
      (vertrag['reversalAnswers'] as Map).cast<String, dynamic>();
  for (final gruppe in const ['notExecuted', 'mayHaveWorked']) {
    final nichtAusgefuehrt = gruppe == 'notExecuted';
    for (final code in (stornoAntworten[gruppe] as List).cast<String>()) {
      ({Map<String, dynamic> fall, Map<String, Map<String, dynamic>> zusatz})
          stornoFall(String status) {
        final name = 'storno:$code';
        final sonder = const [_transport, _http404, _http409].contains(code);
        return (
          fall: {
            'name': 'Storno $code, Status $status',
            'operation': 'pay',
            'amountCents': 1000,
            'tipCents': 150,
            'transactionId': '261110033825505799',
            'resolveBudgetMs': 30000,
            'request': 'hostTimeout',
            'abort': 'abortAccepted',
            'reversal': sonder ? code : name,
            'status': [status],
          },
          zusatz: sonder
              ? const {}
              : {
                  name: code == _ohneCode
                      ? <String, dynamic>{}
                      : {'responseCode': code},
                },
        );
      }

      test('Storno-Antwort $code ($gruppe), Status genehmigt', () async {
        final f = stornoFall('statusApproved');
        final (:res, :aufrufe) = await klaeren(f.fall, f.zusatz);
        final stornos = aufrufe.where((a) => a.weg == 'cancel').toList();
        expect(stornos.length, 1);
        expect(stornos.single.cent, 1150);
        final status = aufrufe.where((a) => a.weg == 'status').length;
        if (nichtAusgefuehrt) {
          expect(res.outcome, CardPaymentOutcome.approved,
              reason: res.steps.join(' | '));
          expect(status, 1);
        } else {
          expect(res.outcome, CardPaymentOutcome.unresolved,
              reason: res.steps.join(' | '));
          expect(res.reason, HpsCodeReason.hostTimeout);
          expect(status, 2);
          expect(res.steps.where((s) => s.contains('nichts belastet')), isEmpty);
        }
      });

      test('Storno-Antwort $code ($gruppe), Status 9011', () async {
        final f = stornoFall('statusCanceled');
        final (:res, aufrufe: _) = await klaeren(f.fall, f.zusatz);
        expect(res.outcome, CardPaymentOutcome.declined,
            reason: res.steps.join(' | '));
        expect(
            res.reason,
            nichtAusgefuehrt
                ? HpsCodeReason.canceled
                : HpsCodeReason.voidedAfterHostFault);
      });
    }
  }
}

/// Name im Prueffall fuer "die Leitung reisst ab, keine Antwort".
const String _transport = 'transport';

/// Namen im Prueffall fuer "das Terminal antwortet mit diesem HTTP-Status".
const String _http404 = 'http404';
const String _http409 = 'http409';

/// Name in reversalAnswers fuer "Antwort ohne Ergebniscode".
const String _ohneCode = 'noCode';

class _Leitungsabriss implements Exception {
  const _Leitungsabriss();

  @override
  String toString() => 'Leitung abgerissen (Prueffall)';
}

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Welcher Weg des HPS -- dieselbe Unterscheidung wie im FakeTerminal von
/// `hps_payments_test.dart`: der Storno-Pfad teilt sich `payment` mit der
/// Zahlung, erst die Methode trennt beide.
String _wegOf(http.Request request) {
  final path = request.url.path;
  if (path.contains('/api/v2/transactions/')) return 'status';
  if (path.contains('/api/transaction/abort/')) return 'abort';
  if (path.contains('/api/transaction/refund')) return 'refund';
  if (request.method == 'DELETE' && path.contains('/api/transaction/payment/')) {
    return 'cancel';
  }
  if (path.contains('/api/transaction/payment')) return 'payment';
  if (path.endsWith('/diagnosis')) return 'diagnosis';
  return path;
}

/// Die TID, die dieser Aufruf traegt: im Rumpf (Zahlung, Gutschrift) oder im
/// Pfad (Status, Abbruch, Aufhebung, Diagnose).
String? _tidOf(http.Request request) {
  if (request.body.isNotEmpty) {
    final rumpf = jsonDecode(request.body) as Map<String, dynamic>;
    return (rumpf['transaction'] as Map<String, dynamic>)['tid'] as String?;
  }
  // Die TID steht im Pfad jeweils direkt hinter diesem Teil.
  final teile = request.url.pathSegments;
  for (final vor in const ['transactions', 'abort', 'payment', 'terminals']) {
    final i = teile.indexOf(vor);
    if (i >= 0 && i + 1 < teile.length) return teile[i + 1];
  }
  return null;
}

/// Der Betrag eines Stornos (DELETE, Betrag in Euro in der Query) in Cent,
/// sonst `null`.
int? _stornoCent(http.Request request) {
  if (request.method != 'DELETE') return null;
  final betrag = request.url.queryParameters['amount'];
  return betrag == null ? null : (double.parse(betrag) * 100).round();
}

/// Ein Feld der Antwort, wie der Vertrag es nennt.
String? _feld(TransactionResponse r, String name) => switch (name) {
      'responseCode' => r.responseCode,
      'approvalCode' => r.approvalCode,
      'receipt' => r.receipt,
      'brand' => r.brand,
      'cardNumber' => r.cardNumber,
      _ => throw StateError('Vertrag nennt das Feld $name, das dieser Test nicht kennt'),
    };

/// Eine Uhr, die nur durch die Pausen der Klaerung vorrueckt -- wie `TestUhr`
/// in `hps_payments_test.dart` und die Uhr des npm-Zwillings.
class _Uhr implements Stopwatch {
  Duration _elapsed = Duration.zero;

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
