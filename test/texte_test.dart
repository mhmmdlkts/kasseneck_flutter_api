import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/src/register/fehler.dart';

/// Waechter ueber den Textkatalog der Kasse, Zwilling der entsprechenden
/// Tests in `test/texte.test.ts` des npm-Pakets: die Regeln, die Saetze fuer
/// Rand-Codes und unklaren Ausgang, beide Kassen, die neuen Beschriftungen.

/// Woran ein Satz das Wiederholen empfiehlt.
final RegExp raetZumWiederholen = RegExp('erneut|nochmal|noch einmal|wiederhol|neu senden', caseSensitive: false);

/// Woran ein Satz eine Seite, einen Browser oder die App meint.
final RegExp nenntEineSeite = RegExp(r'seite|browser|\bapp\b|neu laden|tab\b|fenster', caseSensitive: false);

List<ErrorRule> get _alleRegeln => [...errorRules, ...errorCodeRules, ...errorOutcomeRules];

void main() {
  test('die Fehlerregeln enden mit other und nennen nur bekannte Schluessel, genau eine Regel je Art', () {
    expect(errorRules.last.kind, ErrorKind.other);
    for (final r in _alleRegeln) {
      if (r.key case final k?) expect(posMessages, contains(k));
      expect((r.key == null) != (r.behavior == null), isTrue, reason: 'Satz oder Verhalten, nie beides: ${r.toJson()}');
    }
    expect([for (final r in errorRules) r.kind], ErrorKind.values);
    expect([for (final r in errorRules) if (r.behavior != null) r.behavior],
        [ErrorRuleBehavior.serverText, ErrorRuleBehavior.ownText, ErrorRuleBehavior.fallback]);
    expect(errorRules.every((r) => r.codes == null && r.outcome == null), isTrue);
    expect(errorCodeRules.every((r) => r.codes!.isNotEmpty && r.outcome == null && r.key != null), isTrue);
    expect(errorOutcomeRules.every((r) => r.outcome != null && r.codes == null && r.key != null), isTrue);
  });

  test('errorRules ist der Stand von rc.4: wer nur nach der Art sucht, zeigt denselben Satz wie vorher', () {
    expect([for (final r in errorRules) r.toJson()], [
      {'kind': 'api', 'behavior': 'server_text'},
      {'kind': 'plain_text', 'behavior': 'own_text'},
      {'kind': 'timeout', 'key': 'network.timeout'},
      {'kind': 'network', 'key': 'network.no_connection'},
      {'kind': 'unexpected', 'key': 'server.unexpected'},
      {'kind': 'other', 'behavior': 'fallback'},
    ]);
    expect(messageText('network.timeout'), 'Der Server antwortet nicht. Bitte die Internetverbindung prüfen und erneut versuchen.');
    expect(messageText('network.no_connection'),
        'Keine Verbindung zum Server. Bitte die Internetverbindung prüfen und erneut versuchen.');
  });

  test('Rand-Codes zeigen dem Kassier einen Menschentext, nie den technischen Satz', () {
    const rand = ['route_missing', 'dialect_mismatch', 'not_found', 'internal_translation_error', 'response_translation_failed', 'response_unreadable'];
    for (final code in rand) {
      final key = findErrorRule(ErrorKind.api, code: code).key;
      expect(key, isNotNull, reason: code);
      final text = messageText(key!);
      expect(text, contains('Kassenserver'), reason: code);
      expect(text, isNot(matches(RegExp('v3|HTML|Route|Kennzeichen|translation|unreadable', caseSensitive: false))), reason: code);
    }
    for (final code in ['route_missing', 'not_found', 'internal_translation_error']) {
      expect(findErrorRule(ErrorKind.api, code: code).key, 'server.connection_disturbed', reason: code);
    }
    // Jeder andere Code und ein Fehler ohne Code: der Satz des Backends, auch bei unklarem Ausgang.
    for (final code in ['session_expired', 'validation', 'receipt_outcome_unknown', null]) {
      expect(findErrorRule(ErrorKind.api, code: code), same(errorRules.first), reason: '$code');
      expect(findErrorRule(ErrorKind.api, code: code, outcome: ErrorOutcome.unknown), same(errorRules.first), reason: '$code');
    }
    // Ein Code an einer anderen Art aendert nichts; nur timeout und network kennen eine Ausgangs-Regel.
    expect(findErrorRule(ErrorKind.network, code: 'route_missing').key, 'network.no_connection');
    expect(findErrorRule(ErrorKind.timeout, outcome: ErrorOutcome.unknown).key, 'network.outcome_unknown');
    expect(findErrorRule(ErrorKind.timeout, outcome: ErrorOutcome.rejected).key, 'network.timeout');
    expect(findErrorRule(ErrorKind.unexpected, outcome: ErrorOutcome.unknown).key, 'server.unexpected');
    expect(findErrorRule(ErrorKind.network).key, 'network.no_connection');
  });

  test('die gemeinsamen Regeln passen fuer beide Kassen: kein Satz nennt eine Seite, jeder gilt auf beiden Seiten', () {
    for (final probe in ['Bitte die Webseite neu laden.', 'Im BROWSER.', 'Die App neu starten.', 'Den Tab schliessen.', 'Fenster neu öffnen.']) {
      expect(probe, matches(nenntEineSeite), reason: probe);
    }
    for (final r in _alleRegeln) {
      final k = r.key;
      if (k == null) continue;
      expect(posMessages[k]!.text, isNot(matches(nenntEineSeite)), reason: k);
      expect(posMessages[k]!.only, isNull, reason: k);
    }
  });

  test('Ausgang unklar: kein Code, der auf irgendeinem Aufruf mit Wirkung unklar ist, bekommt einen Satz, der zum Wiederholen raet', () {
    for (final probe in ['Bitte erneut senden.', 'Nochmal versuchen.', 'Noch einmal drücken.', 'Bitte wiederholen.', 'Neu senden.']) {
      expect(probe, matches(raetZumWiederholen), reason: probe);
    }
    // Alle Codes, die ein KasseneckApiError tragen kann: der Vertrag und die
    // des Pakets. Ob unklar, entscheidet der Fehler selbst, je Aufruf: auf den
    // Geldwegen ist jeder Code ausserhalb von paymentCallRejectedCodes unklar.
    final vokabular = jsonDecode(File('test/fixtures/vertrag/v3/v3-vokabular.json').readAsStringSync()) as Map<String, dynamic>;
    final codes = {...((vokabular['errorCodes'] as Map)['all'] as List).cast<String>(), ...clientErrorCodes, 'dialect_mismatch'};
    bool unklarAuf(String call, String code) =>
        KasseneckApiError(call, 'x', code: code).outcome == ErrorOutcome.unknown;
    expect(callsWithEffect, containsAll(['hobexPayApi', 'createReceipt']));
    var geprueft = 0;
    for (final code in codes) {
      final aufrufe = [for (final c in callsWithEffect) if (unklarAuf(c, code)) c];
      if (aufrufe.isEmpty) continue;
      final regel = findErrorRule(ErrorKind.api, code: code, outcome: ErrorOutcome.unknown);
      if (regel.key case final k?) {
        expect(messageText(k), isNot(matches(raetZumWiederholen)), reason: '$code ($aufrufe) -> $k');
        geprueft++;
      } else {
        expect(regel.behavior, ErrorRuleBehavior.serverText, reason: code);
      }
    }
    expect(geprueft, greaterThanOrEqualTo(3));
    // Jede Code-Regel mit Rat zum Wiederholen gilt nur fuer Codes, die auf KEINEM Aufruf mit Wirkung unklar sind.
    for (final regel in errorCodeRules) {
      if (!raetZumWiederholen.hasMatch(messageText(regel.key!))) continue;
      for (final code in regel.codes!) {
        expect([for (final c in callsWithEffect) if (unklarAuf(c, code)) c], isEmpty,
            reason: '$code ist unklar, ${regel.key} raet aber zum Wiederholen');
      }
    }
    // Auf createReceipt tragen nur diese beiden unklaren Codes den Satz des
    // Backends (der Vorgang hat seinen eigenen Satz); jeder weitere unklare
    // Code braucht eine Regel.
    final ohneEigenenSatz = [
      for (final c in codes)
        if (unklarAuf('createReceipt', c) && findErrorRule(ErrorKind.api, code: c, outcome: ErrorOutcome.unknown).key == null) c,
    ]..sort();
    expect(ohneEigenenSatz, ['cancellation_outcome_unknown', 'receipt_outcome_unknown']);
    // Der Satz fuer den sicheren Fall raet dagegen ausdruecklich zum neuen Versuch.
    expect(messageText('server.connection_disturbed'), matches(raetZumWiederholen));
  });

  test('Frist und Netzfehler: unklarer Ausgang raet nie zum Wiederholen, sonst der Satz von rc.4', () {
    for (final art in [ErrorKind.timeout, ErrorKind.network]) {
      final unklar = findErrorRule(art, outcome: ErrorOutcome.unknown).key!;
      expect(messageText(unklar), isNot(matches(raetZumWiederholen)), reason: art.wire);
      expect(messageText(unklar), isNot(matches(nenntEineSeite)), reason: art.wire);
      for (final ausgang in [ErrorOutcome.rejected, null]) {
        expect(findErrorRule(art, outcome: ausgang), same(errorRules.firstWhere((r) => r.kind == art)), reason: '$art $ausgang');
      }
    }
  });

  test('neue Beschriftungen: Geraet ohne Namen, Restzeit der PIN-Sperre, letzte Runde mit Rundung', () {
    expect(labelText('register.device_unnamed'), 'Kasse');
    expect(labelText('login.locked_seconds', {'seconds': 27}), 'Noch 27 s gesperrt');
    expect(labelText('split.remaining_with_rounding', {'amount': '19,99 €', 'cents': '−1'}), 'Rest inkl. Rundung 19,99 € (−1 ct)');
    expect(() => labelText('login.locked_seconds'), throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('{seconds}'))));
    expect(() => labelText('split.remaining_with_rounding', {'amount': '1,00 €'}),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('{cents}'))));
  });

  test('messageText ersetzt Platzhalter, wirft bei fehlendem Wert und unbekanntem Schluessel', () {
    expect(messageText('server.unexpected', {'status': 404}),
        'Der Server hat unerwartet geantwortet (HTTP 404). Bitte den Support verständigen.');
    expect(() => messageText('server.unexpected'), throwsArgumentError);
    expect(() => messageText('gibt.es_nicht'), throwsArgumentError);
    expect(() => labelText('gibt.es_nicht'), throwsArgumentError);
    expect(messageAppliesTo('device.browser_storage', PosSurface.web), isTrue);
    expect(messageAppliesTo('device.browser_storage', PosSurface.app), isFalse);
    expect(messageAppliesTo('network.timeout', PosSurface.app), isTrue);
  });

  test('Platzhalter im Text und in der Liste sind dieselben, kein Geviertstrich', () {
    final muster = RegExp(r'\{([a-z]+)\}');
    for (final katalog in [posMessages, posLabels]) {
      for (final e in katalog.entries) {
        final imText = {for (final m in muster.allMatches(e.value.text)) m[1]!};
        expect(imText, (e.value.placeholders ?? const []).toSet(), reason: e.key);
        expect(e.value.text, isNot(contains('\u2014')), reason: e.key);
      }
    }
  });

  test('Belegmail und Storno: ein unbekannter Code bekommt den allgemeinen Satz', () {
    expect(receiptEmailErrorMessage('invalid_address'), 'receipt.mail_address_invalid');
    expect(receiptEmailErrorMessage('etwas_neues'), 'receipt.mail_failed');
    expect(receiptEmailErrorMessage(null), 'receipt.mail_failed');
    expect(cancellationPaymentErrorMessage('cancellation_outcome_unknown'), 'cancellation.outcome_unknown');
    expect(cancellationPaymentErrorMessage('etwas_neues'), 'cancellation.failed');
    for (final k in [...receiptEmailErrorMessages.values, ...cancellationPaymentErrorMessages.values]) {
      expect(posMessages, contains(k));
    }
  });

  test('Rueckgabe beim Storno: jede Wahl zeigt auf eine Beschriftung, die es gibt', () {
    expect(returnDispositionLabels.keys, ['restock', 'defective', 'disposed']);
    for (final k in returnDispositionLabels.values) {
      expect(posLabels, contains(k));
    }
    expect(labelText(returnDispositionLabels['restock']!), 'Zurück ins Lager');
  });
}
