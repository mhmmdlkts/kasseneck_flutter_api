/// Aus dem Textkatalog der Kasse im Vertrag
/// (`test/fixtures/vertrag/pos-texts.json`, aus dem npm-Paket gezogen) wird
/// `lib/src/kasse/texte_katalog.dart`.
///
/// Aufruf aus der Paketwurzel, nach `tool/zwillinge.sh ziehen`:
///
///     dart run tool/texte_erzeugen.dart
///
/// Von Hand wird die erzeugte Datei nie geaendert: `test/texte_vertrag_test.dart`
/// erzeugt sie im Test neu und vergleicht Zeichen fuer Zeichen. So steht in
/// Dart genau der Satz, den auch die Web-Kasse zeigt.
library;

import 'dart:convert';
import 'dart:io';

const String textQuelle = 'test/fixtures/vertrag/pos-texts.json';
const String textZiel = 'lib/src/kasse/texte_katalog.dart';

/// Die Schluessel der Datei in der Reihenfolge des Vertrags. Ein neuer
/// Schluessel bricht das Erzeugen ab, statt still wegzufallen.
const List<String> _dateiSchluessel = [
  'version',
  'messages',
  'errorRules',
  'errorCodeRules',
  'errorOutcomeRules',
  'callsWithEffect',
  'receiptEmailErrors',
  'cancellationPaymentErrors',
  'labels',
];

/// `plain_text` -> `plainText`: der Name des Enum-Werts zum Drahtwert.
String dartName(String wire) {
  final teile = wire.split('_');
  return teile.first + teile.skip(1).map((t) => t[0].toUpperCase() + t.substring(1)).join();
}

String _literal(String text) {
  final innen = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$innen'";
}

String _liste(List<String> werte) => '[${werte.map(_literal).join(', ')}]';

String _eintrag(String schluessel, Map<String, dynamic> e) {
  final unbekannt = e.keys.where((k) => !const {'text', 'placeholders', 'only'}.contains(k));
  if (unbekannt.isNotEmpty) throw FormatException('$schluessel: unbekanntes Feld ${unbekannt.first}');
  final teile = [_literal(e['text'] as String)];
  final platzhalter = (e['placeholders'] as List?)?.cast<String>();
  if (platzhalter != null) teile.add('placeholders: ${_liste(platzhalter)}');
  final nur = (e['only'] as List?)?.cast<String>();
  if (nur != null) teile.add('only: [${nur.map((s) => 'PosSurface.${dartName(s)}').join(', ')}]');
  return '  ${_literal(schluessel)}: PosText(${teile.join(', ')}),';
}

String _regel(Map<String, dynamic> r) {
  final unbekannt = r.keys.where((k) => !const {'kind', 'behavior', 'key', 'codes', 'outcome'}.contains(k));
  if (unbekannt.isNotEmpty) throw FormatException('Regel mit unbekanntem Feld ${unbekannt.first}');
  final teile = ['kind: ErrorKind.${dartName(r['kind'] as String)}'];
  if (r.containsKey('codes')) teile.add('codes: ${_liste((r['codes'] as List).cast<String>())}');
  if (r.containsKey('outcome')) teile.add('outcome: ErrorOutcome.${dartName(r['outcome'] as String)}');
  if (r.containsKey('behavior')) teile.add('behavior: ErrorRuleBehavior.${dartName(r['behavior'] as String)}');
  if (r.containsKey('key')) teile.add('key: ${_literal(r['key'] as String)}');
  return '  ErrorRule(${teile.join(', ')}),';
}

/// Der Inhalt von [textZiel] zu einem Vertrag.
String erzeugeKatalog(Map<String, dynamic> vertrag) {
  if (vertrag.keys.join(',') != _dateiSchluessel.join(',')) {
    throw FormatException('pos-texts.json: Schluessel ${vertrag.keys.toList()} statt $_dateiSchluessel');
  }
  final sb = StringBuffer()
    ..writeln('// ERZEUGT aus test/fixtures/vertrag/pos-texts.json')
    ..writeln('// (@kreiseck/kasseneck-api ${vertrag['version']}). Nicht von Hand aendern;')
    ..writeln('// neu erzeugen: dart run tool/texte_erzeugen.dart')
    ..writeln('// dart format off')
    ..writeln()
    ..writeln("part of 'texte.dart';")
    ..writeln()
    ..writeln('/// Version des Vertrags, aus dem dieser Katalog erzeugt ist.')
    ..writeln('const String posTextsVersion = ${_literal(vertrag['version'] as String)};')
    ..writeln()
    ..writeln('/// Was die Kasse selbst sagt: ein Satz je Schluessel (`bereich.name`), gleich wie im Web.')
    ..writeln('const Map<String, PosText> posMessages = {');
  for (final e in (vertrag['messages'] as Map).cast<String, dynamic>().entries) {
    sb.writeln(_eintrag(e.key, (e.value as Map).cast<String, dynamic>()));
  }
  sb
    ..writeln('};')
    ..writeln()
    ..writeln('/// Beschriftungen: Knoepfe, Ueberschriften, Zeilennamen, was kein Satz ist.')
    ..writeln('const Map<String, PosText> posLabels = {');
  for (final e in (vertrag['labels'] as Map).cast<String, dynamic>().entries) {
    sb.writeln(_eintrag(e.key, (e.value as Map).cast<String, dynamic>()));
  }
  sb
    ..writeln('};')
    ..writeln();
  void regeln(String name, String doku) {
    sb
      ..writeln('/// $doku')
      ..writeln('const List<ErrorRule> $name = [');
    for (final r in (vertrag[name] as List).cast<Map<String, dynamic>>()) {
      sb.writeln(_regel(r));
    }
    sb
      ..writeln('];')
      ..writeln();
  }

  regeln('errorRules', 'Genau eine Regel je Art, der Stand von 1.0.0-rc.4; siehe [findErrorRule].');
  regeln('errorCodeRules', 'Regeln je Code, vor der Regel der Art; siehe [findErrorRule].');
  regeln('errorOutcomeRules', 'Regeln je Ausgang, nach den Code-Regeln; siehe [findErrorRule] und [messageOutcome].');
  sb
    ..writeln('/// Kassen-Aufrufe mit Wirkung: nach Frist oder Netzfehler nie „erneut versuchen“; siehe [messageOutcome].')
    ..writeln('const List<String> callsWithEffect = ${_liste((vertrag['callsWithEffect'] as List).cast<String>())};')
    ..writeln();
  void zuordnung(String name, String quelle, String doku) {
    sb
      ..writeln('/// $doku')
      ..writeln('const Map<String, String> $name = {');
    for (final e in (vertrag[quelle] as Map).cast<String, String>().entries) {
      sb.writeln('  ${_literal(e.key)}: ${_literal(e.value)},');
    }
    sb
      ..writeln('};')
      ..writeln();
  }

  zuordnung('receiptEmailErrorMessages', 'receiptEmailErrors', 'Beleg per E-Mail: Code des Backends -> Schluessel des Satzes.');
  zuordnung('cancellationPaymentErrorMessages', 'cancellationPaymentErrors',
      'Storno mit mehreren Zahlungen: Code des Backends -> Schluessel des Satzes.');
  return sb.toString().replaceFirst(RegExp(r'\n+$'), '\n');
}

void main() {
  final vertrag = jsonDecode(File(textQuelle).readAsStringSync()) as Map<String, dynamic>;
  File(textZiel).writeAsStringSync(erzeugeKatalog(vertrag));
  stdout.writeln('$textZiel aus $textQuelle (${vertrag['version']}) erzeugt.');
}
