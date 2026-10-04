import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/receipt/codes.dart';

/// Textkataloge seit 1.0: Schluessel und Platzhalter englisch, Texte
/// unveraendert.
///
/// Alt ist der Stand des letzten 0.x-Pakets, eingefroren unter
/// `test/fixtures/vor-1.0/` (`kasse-texte.json` und `rechnung-texte.json` aus
/// dem Tarball von `@kreiseck/kasseneck-api@0.31.0`, byteweise). Neu sind
/// `pos-texts.json` und `invoice-texts.json` aus dem Vertrag, die Zuordnung
/// steht in `renames-1.0.json` (`texts`, `placeholders`, `structure`).
///
/// Beweis: jeder Text wird alt und neu mit denselben Probewerten gefuellt, alt
/// unter den alten, neu unter den neuen Platzhalternamen. Die Ergebnisse
/// muessen Zeichen fuer Zeichen gleich sein. Gefuellt wird wie im JS-Paket
/// (`messageText`/`labelText`: `{[a-z]+}`, `invoiceText`: `{[a-zA-Z]+}`); ein
/// Platzhalter ohne Wert wirft. Wer also noch die alten Namen uebergibt (etwa
/// `{betrag}` statt `{amount}`), bekommt einen Fehler statt eines halb
/// gefuellten Satzes.

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _altKasse = _json('test/fixtures/vor-1.0/kasse-texte.json');
final _altRechnung = _json('test/fixtures/vor-1.0/rechnung-texte.json');
final _neuKasse = _json('test/fixtures/vertrag/pos-texts.json');
final _neuRechnung = _json('test/fixtures/vertrag/invoice-texts.json');
final _tabelle = _json('test/fixtures/vertrag/renames-1.0.json');

final _platzhalter = (_tabelle['placeholders'] as Map).cast<String, String>();
final _texteKasse = ((_tabelle['texts'] as Map)['pos'] as Map).cast<String, dynamic>();
final _texteRechnung = ((_tabelle['texts'] as Map)['invoice'] as Map).cast<String, String>();
final _strukturKasse = ((_tabelle['structure'] as Map)['pos-texts.json'] as Map).cast<String, dynamic>();

/// Was nach 1.0 dazukam und darum keinen alten Namen hat (wie `NACH_1_0` in
/// `umbenennung-1.0.test.ts` des npm-Pakets): drei Saetze und drei
/// Beschriftungen aus 1.0.0-rc.5, die Texte des Zeichensatz-Tests aus 1.1.0
/// und 1.1.1,
/// dazu die Verfeinerungen der Fehlerregeln als eigene Dateischluessel neben
/// `errorRules`.
const _nach10 = (
  messages: {
    'network.outcome_unknown', 'server.connection_disturbed', 'server.response_unreadable',
    'codetable.question', 'codetable.instruction', 'codetable.question_hint', 'codetable.instruction_none',
  },
  labels: {
    'register.device_unnamed', 'login.locked_seconds', 'split.remaining_with_rounding',
    'codetable.title', 'codetable.reference', 'codetable.replacement_note', 'codetable.missing',
    'codetable.print_again', 'codetable.not_checked', 'codetable.check', 'codetable.current',
    'codetable.instruction_title', 'codetable.preview_title', 'codetable.apply', 'codetable.other_row',
  },
  fileKeys: ['errorCodeRules', 'errorOutcomeRules', 'callsWithEffect'],
  placeholders: {'cents', 'chars'},
);

Set<String> _nach10In(String abschnitt) => abschnitt == 'messages' ? _nach10.messages : _nach10.labels;

final _kassenMuster = RegExp(r'\{([a-z]+)\}');
final _rechnungsMuster = RegExp(r'\{([a-zA-Z]+)\}');

/// Fuellt wie das JS-Paket; fehlt ein Wert, wirft es.
String _fuelle(String wo, String text, RegExp muster, Map<String, Object> werte) =>
    text.replaceAllMapped(muster, (m) {
      final wert = werte[m[1]];
      if (wert == null) throw ArgumentError('$wo: Platzhalter {${m[1]}} ohne Wert');
      return '$wert';
    });

/// Der Probewert haengt am NEUEN Namen: vertauschte Platzhalter fielen auf.
String _probe(String neuerName) => '<${neuerName.toUpperCase()}:${neuerName.length}>';

Map<String, Object> _werteAlt() => {for (final e in _platzhalter.entries) e.key: _probe(e.value)};
Map<String, Object> _werteNeu() => {for (final neu in _platzhalter.values) neu: _probe(neu)};

Map<String, dynamic> _abschnitt(Map<String, dynamic> datei, String name) =>
    (datei[name] as Map).cast<String, dynamic>();

String _neuerAbschnitt(String alt) => ((_strukturKasse['file'] as Map)[alt] as String);

void main() {
  test('die eingefrorenen 0.x-Dateien sind die aus 0.31.0', () {
    // Aus dem Registry-Tarball @kreiseck/kasseneck-api@0.31.0 (npm pack),
    // byteweise -- bis auf rechnung-texte.json: dort stehen seit npm 1.2.1 fuenf
    // Texte je Sprache mit Halbgeviertstrich statt Geviertstrich (Typografie),
    // wie im neuen Katalog; der Hash ist der des nachgezogenen Standes, sonst
    // liefe der Zeichenvergleich alt/neu auseinander. NICHT aus npm test/fixtures/vor-1.0/ auffrischen: dort sind
    // die Storno-Zahlungscodes schon englisch, das wurde nie ausgeliefert.
    String sha(String pfad) => sha256.convert(File(pfad).readAsBytesSync()).toString();
    expect(sha('test/fixtures/vor-1.0/kasse-texte.json'),
        '9e14e8488be5803668fad94238bb1478615cf844388c7d4ef75bca0ae23d1b93');
    expect(sha('test/fixtures/vor-1.0/rechnung-texte.json'),
        'd592073a227435078114a5b9bc20ea3fcd1b7ef211c0deb3fa0ccf4f0bba38bf');
    expect(_altKasse['version'], '0.31.0');
    expect(_altRechnung['version'], '0.31.0');
    expect(_neuKasse['version'], startsWith('1.'));
  });

  group('Kassentexte', () {
    for (final alt in ['meldungen', 'beschriftungen']) {
      final neu = _neuerAbschnitt(alt);

      test('$alt -> $neu: jeder alte Schluessel genau einmal, keiner zu viel', () {
        final altKatalog = _abschnitt(_altKasse, alt);
        final zuordnung = (_texteKasse[neu] as Map).cast<String, String>();
        expect(zuordnung.keys.toSet(), altKatalog.keys.toSet());
        expect(zuordnung.values.toSet(), hasLength(zuordnung.length), reason: 'neue Schluessel eindeutig');
        final neuKatalog = _abschnitt(_neuKasse, neu).keys.toSet();
        expect(zuordnung.values.toSet(), neuKatalog.difference(_nach10In(neu)));
        // Was nach 1.0 dazukam, steht wirklich im Katalog und traegt keinen alten Namen.
        expect(neuKatalog, containsAll(_nach10In(neu)));
        expect(zuordnung.values.toSet().intersection(_nach10In(neu)), isEmpty);
        for (final k in zuordnung.values) {
          expect(k, matches(RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$')), reason: k);
        }
      });

      test('$alt -> $neu: jeder Text alt und neu gefuellt Zeichen fuer Zeichen gleich', () {
        final altKatalog = _abschnitt(_altKasse, alt);
        final neuKatalog = _abschnitt(_neuKasse, neu);
        final zuordnung = (_texteKasse[neu] as Map).cast<String, String>();
        var mitPlatzhalter = 0;
        for (final e in zuordnung.entries) {
          final a = (altKatalog[e.key] as Map).cast<String, dynamic>();
          final n = (neuKatalog[e.value] as Map).cast<String, dynamic>();
          final altPlatz = ((a['platzhalter'] as List?) ?? const []).cast<String>();
          final neuPlatz = ((n['placeholders'] as List?) ?? const []).cast<String>();
          expect(neuPlatz, [for (final p in altPlatz) _platzhalter[p]], reason: '${e.value} placeholders');
          expect(n['only'], a['nur'], reason: '${e.value} only');
          final gefuelltAlt = _fuelle(e.key, a['text'] as String, _kassenMuster, _werteAlt());
          final gefuelltNeu = _fuelle(e.value, n['text'] as String, _kassenMuster, _werteNeu());
          expect(gefuelltNeu, gefuelltAlt, reason: e.value);
          if (altPlatz.isNotEmpty) mitPlatzhalter++;
        }
        // Untergrenzen nach dem Stand 0.31.0 (Meldungen 30, Beschriftungen 15
        // mit Platzhalter): eine versehentlich leere Pruefung faellt auf.
        expect(mitPlatzhalter, greaterThanOrEqualTo(alt == 'meldungen' ? 25 : 12));
      });
    }

    test('Dateischluessel: die 0.x-Abschnitte umbenannt, die Verfeinerungen nach 1.0 eigens', () {
      final datei = (_strukturKasse['file'] as Map).cast<String, String>();
      final neu = _neuKasse.keys.toList();
      expect(neu.where((k) => !_nach10.fileKeys.contains(k)).toList(), [for (final k in _altKasse.keys) datei[k]]);
      expect(neu.where(_nach10.fileKeys.contains).toList(), _nach10.fileKeys);
    });

    test('Belegmail-Fehler: Schluessel sind die /v3-Codes, Ziel der umbenannte Text', () {
      final alt = _abschnitt(_altKasse, 'belegMailFehler');
      final neu = _abschnitt(_neuKasse, 'receiptEmailErrors');
      final codes = (_strukturKasse['receiptEmailErrors'] as Map).cast<String, String>();
      final texte = (_texteKasse['messages'] as Map).cast<String, String>();
      expect({for (final e in alt.entries) codes[e.key]: texte[e.value]}, neu);
      // Genau die Versandcodes, die dieses Paket kennt.
      expect(neu.keys.toSet(), receiptEmailSendErrorCodes.toSet());
    });

    test('Storno-Zahlungsfehler: Schluessel sind die /v3-Codes, Ziel der umbenannte Text', () {
      final alt = _abschnitt(_altKasse, 'stornoZahlungFehler');
      final neu = _abschnitt(_neuKasse, 'cancellationPaymentErrors');
      final codes = (_strukturKasse['cancellationPaymentErrors'] as Map).cast<String, String>();
      final texte = (_texteKasse['messages'] as Map).cast<String, String>();
      expect({for (final e in alt.entries) codes[e.key]: texte[e.value]}, neu);
      for (final code in neu.keys) {
        expect([...cancellationErrorCodes, ...paymentErrorCodes], contains(code), reason: code);
      }
    });

    test('Fehlerregeln: dieselben Regeln, Arten und Verhalten umbenannt', () {
      final werte = ((_tabelle['values'] as Map)['pos-texts.json'] as Map).cast<String, dynamic>();
      final arten = (werte['errorRules[].kind'] as Map).cast<String, String>();
      final verhalten = (werte['errorRules[].behavior'] as Map).cast<String, String>();
      final texte = (_texteKasse['messages'] as Map).cast<String, String>();
      final alt = (_altKasse['fehlerregeln'] as List).cast<Map<String, dynamic>>();
      expect(_neuKasse['errorRules'], [
        for (final r in alt)
          {
            'kind': arten[r['art']],
            if (r.containsKey('verhalten')) 'behavior': verhalten[r['verhalten']],
            if (r.containsKey('schluessel')) 'key': texte[r['schluessel']],
          },
      ]);
    });
  });

  group('Rechnungstexte', () {
    test('Sprachen und Einheiten unveraendert', () {
      expect(_neuRechnung['languages'], _altRechnung['sprachen']);
      expect(_neuRechnung['units'], _altRechnung['einheiten']);
    });

    test('jeder alte Schluessel genau einmal, in jeder Sprache', () {
      expect(_texteRechnung.values.toSet(), hasLength(_texteRechnung.length));
      for (final sprache in (_altRechnung['sprachen'] as List).cast<String>()) {
        final alt = ((_altRechnung['texte'] as Map)[sprache] as Map).cast<String, dynamic>();
        final neu = ((_neuRechnung['texts'] as Map)[sprache] as Map).cast<String, dynamic>();
        expect(_texteRechnung.keys.toSet(), alt.keys.toSet(), reason: sprache);
        expect(_texteRechnung.values.toSet(), neu.keys.toSet(), reason: sprache);
      }
      // Schreibweise wie npm: jeder Teil klein mit Unterstrich, nur
      // Laendercodes gross (`country.AT`).
      for (final k in _texteRechnung.values) {
        expect(k, matches(RegExp(r'^[a-z0-9_]+(\.([a-z0-9_]+|[A-Z]{2}))+$')), reason: k);
      }
    });

    test('jeder Text alt und neu gefuellt Zeichen fuer Zeichen gleich, de und en', () {
      var mitPlatzhalter = 0;
      for (final sprache in (_altRechnung['sprachen'] as List).cast<String>()) {
        final alt = ((_altRechnung['texte'] as Map)[sprache] as Map).cast<String, dynamic>();
        final neu = ((_neuRechnung['texts'] as Map)[sprache] as Map).cast<String, dynamic>();
        for (final e in _texteRechnung.entries) {
          final a = alt[e.key] as String;
          final gefuelltAlt = _fuelle(e.key, a, _rechnungsMuster, _werteAlt());
          final gefuelltNeu = _fuelle(e.value, neu[e.value] as String, _rechnungsMuster, _werteNeu());
          expect(gefuelltNeu, gefuelltAlt, reason: '$sprache ${e.value}');
          if (_rechnungsMuster.hasMatch(a)) mitPlatzhalter++;
        }
      }
      expect(mitPlatzhalter, greaterThan(10));
    });
  });

  group('Platzhalter', () {
    test('die Tabelle nennt genau diese 30 Namen', () {
      expect(_platzhalter, {
        'an': 'recipient', 'antwort': 'response', 'beleg': 'receipt', 'betrag': 'amount', 'betrieb': 'business',
        'code': 'code', 'datum': 'date', 'gegeben': 'tendered', 'gesamt': 'total', 'grund': 'reason',
        'kaeufer': 'buyer', 'kennung': 'reference', 'link': 'link', 'meldung': 'message', 'n': 'n', 'name': 'name',
        'netto': 'net', 'nummer': 'number', 'offen': 'open', 'ort': 'place', 'prozent': 'percent',
        'rueckgeld': 'change', 'satz': 'rate', 'sekunden': 'seconds', 'status': 'status', 'uid': 'vatId',
        'verkaeufer': 'seller', 'weg': 'channel', 'zeit': 'time', 'ziel': 'target',
      });
    });

    test('jeder alte Name kommt in den 0.31.0-Texten vor', () {
      final gefunden = <String>{};
      void sammle(String text, RegExp muster) => gefunden.addAll(muster.allMatches(text).map((m) => m[1]!));
      for (final abschnitt in ['meldungen', 'beschriftungen']) {
        for (final eintrag in _abschnitt(_altKasse, abschnitt).values) {
          sammle((eintrag as Map)['text'] as String, _kassenMuster);
        }
      }
      for (final texte in (_altRechnung['texte'] as Map).values) {
        for (final t in (texte as Map).values) {
          sammle(t as String, _rechnungsMuster);
        }
      }
      expect(gefunden, _platzhalter.keys.toSet());
    });

    test('eins zu eins, kein neuer Name ist ein alter', () {
      expect(_platzhalter.values.toSet(), hasLength(_platzhalter.length));
      final umbenannt = {for (final e in _platzhalter.entries) if (e.key != e.value) e.key};
      // 30 Namen, 25 umbenannt; code, link, n, name und status bleiben.
      expect(umbenannt, hasLength(25));
      expect(_platzhalter.values.toSet().intersection(umbenannt), isEmpty);
    });

    test('jeder Platzhalter der neuen Texte steht in der Tabelle, kein alter Name mehr', () {
      final umbenannt = {for (final e in _platzhalter.entries) if (e.key != e.value) e.key};
      final gefunden = <String>{};
      void sammle(String text, RegExp muster) => gefunden.addAll(muster.allMatches(text).map((m) => m[1]!));
      for (final abschnitt in ['messages', 'labels']) {
        for (final eintrag in _abschnitt(_neuKasse, abschnitt).values) {
          sammle((eintrag as Map)['text'] as String, _kassenMuster);
        }
      }
      for (final texte in (_neuRechnung['texts'] as Map).values) {
        for (final t in (texte as Map).values) {
          sammle(t as String, _rechnungsMuster);
        }
      }
      // Neu nach 1.0 sind nur `{cents}` (split.remaining_with_rounding) und
      // `{chars}` (codetable.missing); sie haben keinen alten Namen.
      expect(gefunden, {..._platzhalter.values, ..._nach10.placeholders}, reason: 'jeder neue Name kommt in den 1.0-Texten vor');
      expect(_platzhalter.keys.toSet().intersection(_nach10.placeholders), isEmpty);
      for (final abschnitt in ['messages', 'labels']) {
        for (final e in _abschnitt(_neuKasse, abschnitt).entries) {
          final namen = _kassenMuster.allMatches((e.value as Map)['text'] as String).map((m) => m[1]!).toSet();
          if (namen.intersection(_nach10.placeholders).isNotEmpty) expect(_nach10In(abschnitt), contains(e.key));
        }
      }
      expect(gefunden.intersection(umbenannt), isEmpty);
    });

    test('wer die alten Namen uebergibt, bekommt einen Fehler', () {
      // Nur die alten Namen als Werte: jeder neue Text mit einem umbenannten
      // Platzhalter muss werfen, keiner darf halb gefuellt durchgehen.
      final nurAlt = {for (final e in _platzhalter.entries) if (e.key != e.value) e.key: 'x'};
      final neueNamen = {for (final e in _platzhalter.entries) if (e.key != e.value) e.value};
      var geworfen = 0;
      void pruefe(String wo, String text, RegExp muster) {
        final namen = muster.allMatches(text).map((m) => m[1]!).toSet();
        if (namen.intersection(neueNamen).isEmpty) return;
        expect(() => _fuelle(wo, text, muster, nurAlt), throwsArgumentError, reason: wo);
        geworfen++;
      }

      for (final abschnitt in ['messages', 'labels']) {
        for (final e in _abschnitt(_neuKasse, abschnitt).entries) {
          pruefe(e.key, (e.value as Map)['text'] as String, _kassenMuster);
        }
      }
      for (final e in ((_neuRechnung['texts'] as Map)['de'] as Map).entries) {
        pruefe('${e.key}', e.value as String, _rechnungsMuster);
      }
      expect(geworfen, greaterThan(20));
      expect(
        () => _fuelle('item.amount', 'Betrag {amount}', _kassenMuster, {'betrag': '1,00'}),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'Meldung', contains('{amount} ohne Wert'))),
      );
    });
  });
}
