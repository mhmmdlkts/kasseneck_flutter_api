import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

import '../tool/texte_erzeugen.dart';

/// Der Textkatalog der Kasse gegen den Vertrag (`pos-texts.json`) und die
/// gemeinsamen Faelle (`pos-message-cases.json`), dieselben Dateien wie im
/// npm-Paket (`test/texte-vertrag.test.ts`).

Map<String, dynamic> _lies(String name) =>
    jsonDecode(File('test/fixtures/vertrag/$name').readAsStringSync()) as Map<String, dynamic>;

final _vertrag = _lies('pos-texts.json');
final _faelle = (_lies('pos-message-cases.json')['cases'] as List).cast<Map<String, dynamic>>();

ErrorKind _art(String wire) => ErrorKind.values.firstWhere((k) => k.wire == wire);

ErrorOutcome? _ausgang(Object? wire) => wire == null ? null : ErrorOutcome.values.byName(wire as String);

ErrorRule _trifft(Map<String, dynamic> fall) {
  final e = (fall['error'] as Map).cast<String, dynamic>();
  return findErrorRule(_art(e['kind'] as String), code: e['code'] as String?, outcome: _ausgang(e['outcome']));
}

/// Was eine Kasse mit der Regel macht (Web: `bildschirmtext`, hier dasselbe in Dart).
String _bildschirm(Map<String, dynamic> fall) {
  final e = (fall['error'] as Map).cast<String, dynamic>();
  final regel = _trifft(fall);
  if (regel.key case final key?) {
    return messageText(key, key == 'server.unexpected' ? {'status': e['status'] ?? 0} : const {});
  }
  return switch (regel.behavior!) {
    ErrorRuleBehavior.serverText => (e['serverMessage'] as String?) ?? '',
    ErrorRuleBehavior.ownText => (e['text'] as String?) ?? '',
    ErrorRuleBehavior.fallback => fall['fallback'] as String,
  };
}

String _erwartet(Map<String, dynamic> fall) {
  final soll = fall['expected'];
  if (soll is String) return soll;
  final m = (soll as Map).cast<String, dynamic>();
  return messageText(m['key'] as String, ((m['values'] as Map?) ?? const {}).cast<String, Object>());
}

void main() {
  test('der Katalog ist aus dem Vertrag erzeugt, nicht von Hand', () {
    final erzeugt = erzeugeKatalog(_vertrag);
    expect(File(textZiel).readAsStringSync(), erzeugt,
        reason: 'lib/src/kasse/texte_katalog.dart ist veraltet: dart run tool/texte_erzeugen.dart');
  });

  test('der Katalog ist der Vertrag, Schluessel fuer Schluessel und in derselben Reihenfolge', () {
    expect(posTextsVersion, _vertrag['version']);
    final zwillinge = File('zwillinge.yaml').readAsStringSync();
    expect(zwillinge, contains('npm_version: ${_vertrag['version']}'));
    Map<String, Object> alsJson(Map<String, PosText> k) => {for (final e in k.entries) e.key: e.value.toJson()};
    expect(jsonEncode(alsJson(posMessages)), jsonEncode(_vertrag['messages']));
    expect(jsonEncode(alsJson(posLabels)), jsonEncode(_vertrag['labels']));
    expect(jsonEncode([for (final r in errorRules) r.toJson()]), jsonEncode(_vertrag['errorRules']));
    expect(jsonEncode([for (final r in errorCodeRules) r.toJson()]), jsonEncode(_vertrag['errorCodeRules']));
    expect(jsonEncode([for (final r in errorOutcomeRules) r.toJson()]), jsonEncode(_vertrag['errorOutcomeRules']));
    expect(callsWithEffect, _vertrag['callsWithEffect']);
    expect(receiptEmailErrorMessages, _vertrag['receiptEmailErrors']);
    expect(cancellationPaymentErrorMessages, _vertrag['cancellationPaymentErrors']);
    expect(returnDispositionLabels, _vertrag['returnDispositionLabels']);
  });

  test('callsWithEffect steht gleich in surface.json (pos.callsWithEffect)', () {
    final oberflaeche = _lies('surface.json');
    expect(callsWithEffect, (oberflaeche['pos'] as Map)['callsWithEffect']);
  });

  test('die Faelle decken jede Fehlerart ab und erwarten nur, was der Katalog hergibt', () {
    final datei = _lies('pos-message-cases.json');
    expect(datei.keys.toList(), ['version', 'cases']);
    expect(datei['version'], 2);
    expect({for (final f in _faelle) (f['error'] as Map)['kind']}, {for (final k in ErrorKind.values) k.wire});
    for (final fall in _faelle) {
      expect(fall.keys.toList(), ['name', 'error', 'fallback', 'expected'], reason: fall['name'] as String);
      expect((fall['error'] as Map).keys.where((k) => !const {'kind', 'code', 'outcome', 'serverMessage', 'text', 'status'}.contains(k)),
          isEmpty,
          reason: fall['name'] as String);
      expect(() => _erwartet(fall), returnsNormally, reason: fall['name'] as String);
    }
  });

  test('jeder Fall ergibt ueber findErrorRule genau seinen erwarteten Satz', () {
    for (final fall in _faelle) {
      expect(_bildschirm(fall), _erwartet(fall), reason: fall['name'] as String);
    }
  });

  test('jede Regel hat einen Fall, jeder Code und jeder Ausgang einer Regel ebenso', () {
    for (final regel in errorRules) {
      expect(_faelle.any((f) => identical(_trifft(f), regel)), isTrue, reason: 'kein Fall fuer ${regel.kind.wire}');
    }
    for (final regel in errorCodeRules) {
      for (final code in regel.codes!) {
        expect(_faelle.any((f) => (f['error'] as Map)['code'] == code && identical(_trifft(f), regel)), isTrue,
            reason: 'kein Fall fuer ${regel.kind.wire} $code');
      }
    }
    for (final regel in errorOutcomeRules) {
      expect(_faelle.any((f) => (f['error'] as Map)['outcome'] == regel.outcome!.name && identical(_trifft(f), regel)), isTrue,
          reason: 'kein Fall fuer ${regel.kind.wire} ${regel.outcome!.name}');
    }
  });
}
