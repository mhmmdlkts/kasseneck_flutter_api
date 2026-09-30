import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

/// Die Vorschau im Drucker-Wizard gegen den gemeinsamen Prueffall des
/// npm-Pakets (`code-table-preview.json`) und dieselben Einzelfaelle wie
/// `code-table-preview.test.ts`.
void main() {
  final fall = jsonDecode(File('test/fixtures/vertrag/code-table-preview.json').readAsStringSync()) as Map<String, dynamic>;
  final beispiel = (fall['sample'] as List).cast<String>();
  final tabellen = (fall['tables'] as Map).cast<String, String>();

  test('je Tabelle genau der Text aus dem gemeinsamen Prueffall', () {
    expect(tabellen.keys.toList(), [for (final t in codeTables) t.id.name]);
    for (final t in codeTables) {
      expect(codeTablePreviewText(t.id), tabellen[t.id.name], reason: t.id.name);
    }
  });

  test('fehlende Zeichen als Ersatzbuchstaben, vorhandene unveraendert', () {
    expect(codeTablePreviewText(CodeTableId.pc437), 'Käsekrainer 3,50 EUR\nTee 80°');
    expect(codeTablePreviewText(CodeTableId.replacement), 'Kaesekrainer 3,50 EUR\nTee 80Grad');
    expect(codeTablePreviewText(CodeTableId.wpc1252), beispiel.join('\n'));
  });

  test('dieselben Bytes, die der Drucker mit der Tabelle wirklich bekommt', () {
    for (final t in codeTables) {
      final bon = [for (final z in beispiel) encodeForCodeTable(z, t.id).toList()];
      final vorschau = [for (final z in codeTablePreviewText(t.id).split('\n')) encodeForCodeTable(z, t.id).toList()];
      expect(vorschau, bon, reason: t.id.name);
    }
  });
}
