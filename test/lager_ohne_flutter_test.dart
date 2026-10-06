// Waechter: `package:kasseneck_api/inventory.dart` bleibt frei von Flutter.
//
// Das Paket als Ganzes braucht das Flutter-SDK zum Aufloesen (pubspec:
// `flutter: sdk: flutter`), die Lager-API aber laeuft auf einem Server (etwa
// dem Backend eines Shops). Dort gibt es kein `dart:ui`; ein einziger Import
// von `package:flutter` oder `dart:ui` irgendwo hinter `inventory.dart` liesse
// ein reines Dart-Programm nicht mehr uebersetzen. Der Test folgt jedem
// `import`, `export` und `part` (auch bedingten) innerhalb dieses Pakets.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alle URIs, die [einstieg] (Pfad unter `lib/`) transitiv einbindet, mit der
/// Datei, in der sie stehen.
Map<String, String> einbindungen(String einstieg) {
  final gefunden = <String, String>{};
  final offen = <String>[einstieg];
  final besucht = <String>{};
  while (offen.isNotEmpty) {
    final pfad = File(offen.removeLast()).absolute.path;
    if (!besucht.add(pfad)) continue;
    final einheit = parseString(content: File(pfad).readAsStringSync(), path: pfad).unit;
    for (final d in einheit.directives.whereType<UriBasedDirective>()) {
      final uris = [
        d.uri.stringValue!,
        if (d is NamespaceDirective) for (final k in d.configurations) k.uri.stringValue!,
      ];
      for (final uri in uris) {
        gefunden.putIfAbsent(uri, () => pfad);
        if (uri.startsWith('package:kasseneck_api/')) {
          offen.add('lib/${uri.substring('package:kasseneck_api/'.length)}');
        } else if (!uri.contains(':')) {
          offen.add(File(pfad).parent.uri.resolve(uri).toFilePath());
        }
      }
    }
  }
  return gefunden;
}

List<String> flutterFunde(String einstieg) => [
      for (final e in einbindungen(einstieg).entries)
        if (e.key.startsWith('package:flutter/') || e.key.startsWith('package:flutter_') || e.key == 'dart:ui')
          '${e.key} in ${e.value}',
    ];

void main() {
  test('inventory.dart bindet transitiv weder package:flutter noch dart:ui ein', () {
    final alle = einbindungen('lib/inventory.dart');
    // Der Waechter laeuft wirklich durch: er erreicht den Transport und das HTTP-Paket.
    expect(alle.keys, containsAll(['package:http/http.dart', 'package:crypto/crypto.dart']));
    expect(flutterFunde('lib/inventory.dart'), isEmpty);
  });

  test('der Waechter findet Flutter, wo es steht (Rot-Probe)', () {
    // pos.dart zieht Widgets und Themes nach sich.
    expect(flutterFunde('lib/pos.dart'), isNotEmpty);
  });
}
