import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/register/fehler.dart';
import 'package:kasseneck_api/src/v3.dart';

/// Frist und Netzfehler am echten Transport ([v3Post], durch den jeder Aufruf
/// dieses Pakets laeuft): welcher Satz kommt auf den Kassenschirm? Auf einem
/// Aufruf mit Wirkung raet er nie zum Wiederholen (der Vorgang kann gebucht
/// sein); auf allen anderen bleibt der Satz von 1.0.0-rc.4. Zwilling von
/// `test/meldung-ausgang.test.ts` im npm-Paket.

final RegExp raetZumWiederholen = RegExp('erneut|nochmal|noch einmal|wiederhol|neu senden', caseSensitive: false);

Future<Object> _fehlerBei(String call, http.Client client, {Duration timeout = const Duration(seconds: 5)}) async {
  try {
    await v3Post(
      client,
      functionName: call,
      basis: kPosBaseUrl,
      name: call,
      headers: const {'Content-Type': 'application/json'},
      kasseneck: V3Headers(call),
      body: '{}',
      timeout: timeout,
    );
  } on Object catch (e) {
    return e;
  }
  fail('$call: kein Fehler');
}

final http.Client _netzWeg = MockClient((_) async => throw const SocketException('weg'));
final http.Client _antwortetNie = MockClient((_) => Completer<http.Response>().future);

String _satz(Object e) {
  expect(e, isA<KasseneckHttpError>());
  final f = e as KasseneckHttpError;
  final art = f.reason == KasseneckHttpError.reasonTimeout ? ErrorKind.timeout : ErrorKind.network;
  final regel = findErrorRule(art, outcome: messageOutcome(e));
  expect(regel.key, isNotNull);
  return messageText(regel.key!);
}

void main() {
  test('callsWithEffect sind echte Aufrufe und enthalten jeden, dessen Ausgang der Transport als unklar fuehrt', () async {
    for (final c in callsWithEffect) {
      expect(Aufrufe.alle, contains(c));
    }
    // Druckjob und Belegmail fuehrt der Transport als abgelehnt; ihr zweiter
    // Versuch druckt bzw. mailt doppelt.
    expect(callsWithEffect, containsAll(['createPrintJob', 'sendReceiptEmail']));
    expect(callsWithEffect, containsAll(unknownOutcomeCalls));
    for (final call in Aufrufe.alle) {
      final e = await _fehlerBei(call, _netzWeg);
      expect(e, isA<KasseneckHttpError>(), reason: call);
      if ((e as KasseneckHttpError).outcome == ErrorOutcome.unknown) {
        expect(callsWithEffect, contains(call), reason: '$call ist unklar, fehlt in callsWithEffect');
      }
    }
  });

  test('Netzfehler: auf einem Aufruf mit Wirkung nie „erneut versuchen“, sonst der Satz von rc.4', () async {
    final rc4 = errorRules.firstWhere((r) => r.kind == ErrorKind.network).key!;
    var mitWirkung = 0;
    for (final call in Aufrufe.alle) {
      final e = await _fehlerBei(call, _netzWeg);
      if (callsWithEffect.contains(call)) {
        mitWirkung++;
        expect(messageOutcome(e), ErrorOutcome.unknown, reason: call);
        expect(_satz(e), isNot(matches(raetZumWiederholen)), reason: call);
      } else {
        expect(_satz(e), messageText(rc4), reason: call);
      }
    }
    expect(mitWirkung, callsWithEffect.length);
  });

  test('Frist: auf einem Aufruf mit Wirkung nie „erneut versuchen“, sonst der Satz von rc.4', () async {
    final rc4 = errorRules.firstWhere((r) => r.kind == ErrorKind.timeout).key!;
    for (final call in ['createReceipt', 'createPrintJob', 'sendReceiptEmail', 'hobexPayApi', 'listMyArticles', 'getReceipt']) {
      final e = await _fehlerBei(call, _antwortetNie, timeout: const Duration(milliseconds: 5));
      expect(e, isA<KasseneckHttpError>().having((f) => f.reason, 'reason', KasseneckHttpError.reasonTimeout), reason: call);
      if (callsWithEffect.contains(call)) {
        expect(_satz(e), isNot(matches(raetZumWiederholen)), reason: call);
      } else {
        expect(_satz(e), messageText(rc4), reason: call);
      }
    }
  });

  test('messageOutcome: der Vorgang hinter dem Namen zaehlt, fremde Fehler haben keinen Ausgang', () {
    const druck = KasseneckHttpError('createPrintJob', 0, KasseneckHttpError.reasonNetwork);
    expect(druck.outcome, ErrorOutcome.rejected, reason: 'der Transport bleibt bei seinem Ausgang');
    expect(messageOutcome(druck), ErrorOutcome.unknown);
    expect(messageOutcome(const KasseneckHttpError('financeWebService/status_cashbox', 0, KasseneckHttpError.reasonTimeout)),
        ErrorOutcome.unknown);
    // Eine andere Art des HTTP-Fehlers auf einem Aufruf mit Wirkung behaelt ihren Ausgang.
    expect(messageOutcome(const KasseneckHttpError('createPrintJob', 404, 'server-error')), ErrorOutcome.rejected);
    expect(messageOutcome(const KasseneckHttpError('listMyArticles', 0, KasseneckHttpError.reasonNetwork)), ErrorOutcome.rejected);
    expect(messageOutcome(const KasseneckApiError('createReceipt', 'x', code: 'receipt_outcome_unknown')), ErrorOutcome.unknown);
    expect(messageOutcome(const KasseneckApiError('listMyArticles', 'x', code: 'validation')), ErrorOutcome.rejected);
    expect(messageOutcome(Exception('x')), isNull);
    expect(messageOutcome(null), isNull);
  });
}
