// Die Dart-Beispiele der READMEs muessen gegen die aktuelle Oberflaeche
// uebersetzen. Ohne diesen Test veraltet ein Beispiel still, sobald ein Name
// wechselt (so geschehen beim Umbau auf 10.0: die README nannte noch
// `paymentMethod` und den alten Storno-Weg, als der Code beides nicht mehr
// kannte).
//
// Jeder ```dart-Block wird zu einer eigenen Datei: oben die `import`-Zeilen
// dieses und aller frueheren Bloecke derselben README (so liest sie ein
// Mensch von oben nach unten), der Rest als Rumpf einer async-Funktion. Freie Namen, die ein Beispiel aus
// dem umgebenden Text voraussetzt (`kasseneck`, `receipt`, `transport` ...),
// liefert eine Stub-Bibliothek mit festen Typen. Sie exportiert nichts weiter:
// fehlt ein Import in der ganzen README, faellt das auf.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:flutter_test/flutter_test.dart';

/// Freie Namen der Beispiele und ihr Typ. Wer ein Beispiel mit einem neuen
/// freien Namen schreibt, traegt ihn hier ein.
const String _stubs = '''
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/invoice.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/printing.dart';
import 'package:kasseneck_api/register.dart';

class FirebaseUserStub {
  Future<String> getIdToken() async => '';
}

late KasseneckApi kasseneck;
late FirebaseUserStub firebaseUser;
late String currentSessionId;
late PairedRegisterDevice device;
late RegisterTransport transport;
late RegisterReceiptClient client;
late KasseneckReceipt receipt;
late KasseneckReceipt original;
late String id;
late String crId;
late String receiptId;
late DateTime start;
late DateTime end;
late int orderNumber;
late InvoiceApi invoices;
late Customer customer;
late Map<String, dynamic> storedMap;
late KeckPrinter printer;
late IssueResult issued;
''';

/// Befunde, die an einem Ausschnitt nichts bedeuten (ein Beispiel legt
/// Variablen an, um sie zu zeigen, nicht um sie zu benutzen).
const Set<String> _egal = {
  'unused_local_variable',
  'unused_import',
  'unused_element',
  'dead_code',
  'unnecessary_import',
};

final RegExp _block = RegExp(r'^[ \t]*```dart[ \t]*\n(.*?)^[ \t]*```', multiLine: true, dotAll: true);

List<String> dartBloecke(String markdown) => [
      for (final m in _block.allMatches(markdown))
        // Eingerueckte Bloecke (in Listen) um ihre Einrueckung kuerzen.
        _ausruecken(m.group(1)!),
    ];

String _ausruecken(String text) {
  final zeilen = text.split('\n');
  final einzug = zeilen
      .where((z) => z.trim().isNotEmpty)
      .map((z) => z.length - z.trimLeft().length)
      .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
  if (einzug == null || einzug == 0) return text;
  return zeilen.map((z) => z.length >= einzug ? z.substring(einzug) : z.trimLeft()).join('\n');
}

String alsDatei(String block, int nummer, Set<String> importe) {
  final rumpf = <String>[];
  for (final zeile in block.split('\n')) {
    if (zeile.startsWith('import ')) {
      // Ohne Kommentar dahinter, sonst zaehlte derselbe Import zweimal.
      importe.add(zeile.substring(0, zeile.indexOf(';') + 1));
    } else {
      rumpf.add(zeile);
    }
  }
  return [
    ...importe,
    "import 'stubs.dart';",
    '',
    'Future<void> beispiel$nummer() async {',
    ...rumpf.map((z) => '  $z'),
    '}',
    '',
  ].join('\n');
}

/// Pfad des Dart-SDK, auch unter `flutter test` (dort ist die laufende
/// Binaerdatei nicht `dart`).
String? _sdkPfad() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final kandidaten = [
    if (flutterRoot != null) '$flutterRoot/bin/cache/dart-sdk',
    File(Platform.resolvedExecutable).parent.parent.path,
  ];
  for (final k in kandidaten) {
    if (File('$k/version').existsSync() && Directory('$k/lib/core').existsSync()) return k;
  }
  final which = Process.runSync('which', ['flutter']);
  if (which.exitCode == 0) {
    final flutter = File((which.stdout as String).trim()).resolveSymbolicLinksSync();
    final sdk = '${File(flutter).parent.path}/cache/dart-sdk';
    if (Directory(sdk).existsSync()) return sdk;
  }
  return null;
}

void main() {
  final wurzel = Directory.current.path;
  final readmes = ['README.md', 'README.de.md'];

  test('die READMEs enthalten Dart-Beispiele (sonst prueft der Test nichts)', () {
    expect(dartBloecke(File('$wurzel/README.md').readAsStringSync()).length, greaterThanOrEqualTo(15));
    expect(dartBloecke(File('$wurzel/README.de.md').readAsStringSync()), isNotEmpty);
  });

  test('ein eingeschleuster Fehler im Beispiel faellt auf (Rot-Probe)', () async {
    final befunde = await _analysiere({
      'probe': ["import 'package:kasseneck_api/kasseneck_api.dart';\nawait kasseneck.sellReceipt(paymentMethod: 1);"],
    });
    expect(befunde, isNotEmpty);
  });

  test('jedes Dart-Beispiel der READMEs uebersetzt gegen die aktuelle Oberflaeche', () async {
    final befunde = await _analysiere({
      for (final r in readmes) r: dartBloecke(File('$wurzel/$r').readAsStringSync()),
    });
    expect(befunde, isEmpty, reason: befunde.join('\n'));
  });

  test('die Versionsangabe im README entspricht pubspec.yaml', () {
    final pubspec = File('$wurzel/pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    for (final r in readmes) {
      final text = File('$wurzel/$r').readAsStringSync();
      final angaben = RegExp(r'^\s*kasseneck_api:\s*(\S+)', multiLine: true).allMatches(text).map((m) => m.group(1));
      expect(angaben, everyElement('^$version'), reason: r);
      expect(angaben, isNotEmpty, reason: r);
    }
  });
}

/// Schreibt die Bloecke nach `.dart_tool/readme_beispiele/` (dort gilt die
/// package_config des Pakets) und liefert alle Fehler und Warnungen.
Future<List<String>> _analysiere(Map<String, List<String>> bloecke) async {
  final ordner = Directory('${Directory.current.path}/.dart_tool/readme_beispiele');
  if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  ordner.createSync(recursive: true);
  File('${ordner.path}/stubs.dart').writeAsStringSync(_stubs);

  final dateien = <String, String>{};
  var nummer = 0;
  bloecke.forEach((quelle, liste) {
    final importe = <String>{};
    for (var i = 0; i < liste.length; i++) {
      nummer++;
      final pfad = '${ordner.path}/beispiel_$nummer.dart';
      File(pfad).writeAsStringSync(alsDatei(liste[i], nummer, importe));
      dateien[pfad] = '$quelle, Block ${i + 1}';
    }
  });

  final sammlung = AnalysisContextCollection(includedPaths: [ordner.path], sdkPath: _sdkPfad());
  final befunde = <String>[];
  for (final pfad in [...dateien.keys, '${ordner.path}/stubs.dart']) {
    final ergebnis = await sammlung.contextFor(pfad).currentSession.getResolvedUnit(pfad);
    if (ergebnis is! ResolvedUnitResult) {
      befunde.add('$pfad: nicht analysierbar ($ergebnis)');
      continue;
    }
    for (final d in ergebnis.diagnostics) {
      final art = d.severity.name;
      if (art != 'error' && art != 'warning') continue;
      final code = d.diagnosticCode.lowerCaseName;
      if (_egal.contains(code)) continue;
      final zeile = ergebnis.lineInfo.getLocation(d.offset).lineNumber;
      befunde.add('${dateien[pfad] ?? 'stubs.dart'} (Zeile $zeile der erzeugten Datei): $code ${d.message}');
    }
  }
  await sammlung.dispose();
  return befunde;
}
