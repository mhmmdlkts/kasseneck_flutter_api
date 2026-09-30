import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart' show PosCodePage;
import 'package:kasseneck_api/printing.dart';

/// Katalog der Code-Tabellen gegen den gemeinsamen Prueffall des npm-Pakets
/// (`code-tables.json`) und dieselben Einzelfaelle wie `code-tables.test.ts`.
void main() {
  final fixture = jsonDecode(File('test/fixtures/vertrag/code-tables.json').readAsStringSync()) as Map<String, dynamic>;
  final zeichen = (fixture['characters'] as List).cast<String>();
  final tabellen = (fixture['tables'] as List).cast<Map<String, dynamic>>();

  String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  test('Reihenfolge, Nummern und ESC t wie im Prueffall', () {
    expect(codeTables.map((t) => t.id.name).toList(), tabellen.map((t) => t['id']).toList());
    expect(codeTables.map((t) => t.number).toList(), tabellen.map((t) => t['number']).toList());
    expect(codeTables.map((t) => t.escT).toList(), tabellen.map((t) => t['escT']).toList());
    expect(CodeTableId.values.map((t) => t.name).toList(), tabellen.map((t) => t['id']).toList());
  });

  for (final t in tabellen) {
    test('${t['id']} setzt die zehn Zeichen wie der Prueffall, fehlende stehen in missing', () {
      final id = CodeTableId.values.byName(t['id'] as String);
      final bytes = (t['bytes'] as Map).cast<String, String>();
      expect(bytes.keys.toList(), zeichen);
      for (final z in zeichen) {
        expect(hex(encodeForCodeTable(z, id)), bytes[z], reason: '${t['id']} $z');
      }
      // Ein Zeichen fehlt genau dann, wenn der Prueffall mehr als ein Byte nennt.
      expect(codeTableById(id).missing, [for (final z in zeichen) if (bytes[z]!.length > 2) z]);
    });

    test('${t['id']} laesst ASCII unveraendert', () {
      final id = CodeTableId.values.byName(t['id'] as String);
      final ascii = String.fromCharCodes([for (var c = 0x20; c < 0x7f; c++) c]);
      // ’ und • stehen nicht im ASCII-Bereich; der Text geht also 1:1 hinaus.
      expect(encodeForCodeTable(ascii, id), ascii.codeUnits);
    });
  }

  test('ein ganzer Satz wird Zeichen fuer Zeichen umgewandelt', () {
    expect(hex(encodeForCodeTable('Grüße 5 €', CodeTableId.pc437)), '${hex('Gr'.codeUnits)}81E1${hex('e 5 EUR'.codeUnits)}');
    expect(hex(encodeForCodeTable('Grüße 5 €', CodeTableId.replacement)), hex('Gruesse 5 EUR'.codeUnits));
  });

  test('uebrige Zeichen ab 0x80 je Tabelle', () {
    expect(hex(encodeForCodeTable('é«»', CodeTableId.wpc1252)), 'E9ABBB');
    expect(hex(encodeForCodeTable('éàçñÅÉøØ', CodeTableId.pc850)), '828587A48F909B9D');
    expect(hex(encodeForCodeTable('ñÅÉøØÐ', CodeTableId.pc858)), 'A48F909B9DD1');
    expect(hex(encodeForCodeTable('ñÅÉøØÐ', CodeTableId.pc850)), 'A48F909B9DD1');
    expect(hex(encodeForCodeTable('éÐ', CodeTableId.pc437)), '823F');
    expect(hex(encodeForCodeTable('é', CodeTableId.replacement)), '3F');
    for (final t in codeTables) {
      expect(hex(encodeForCodeTable('a’b•c', t.id)), '6127622A63', reason: t.id.name);
      expect(hex(encodeForCodeTable('あ', t.id)), '3F', reason: t.id.name);
      expect(hex(encodeForCodeTable('x\u{1F600}y', t.id)), '783F79', reason: '${t.id.name}: ausserhalb der BMP ein Byte');
    }
  });

  test('iso8859_15: Latin-1 auf sein Byte, die acht anders belegten Stellen fehlen, die neuen Zeichen stehen', () {
    const anders = {0xa4, 0xa6, 0xa8, 0xb4, 0xb8, 0xbc, 0xbd, 0xbe};
    for (var c = 0xa0; c <= 0xff; c++) {
      final ist = hex(encodeForCodeTable(String.fromCharCode(c), CodeTableId.iso8859_15));
      final soll = c == 0xb4 ? '27' : (anders.contains(c) ? '3F' : c.toRadixString(16).toUpperCase());
      expect(ist, soll, reason: 'U+${c.toRadixString(16)}');
    }
    expect(hex(encodeForCodeTable('½¼¾¤¦¨¸', CodeTableId.iso8859_15)), '3F3F3F3F3F3F3F');
    expect(hex(encodeForCodeTable('œŠšŽžŒŸ', CodeTableId.iso8859_15)), 'BDA6A8B4B8BCBE');
    expect(hex(encodeForCodeTable('\u0080\u0085\u009f', CodeTableId.iso8859_15)), '3F3F3F', reason: 'C1-Steuerzeichen nie roh');
  });

  test('wpc1252: die Windows-Zeichen 0x80-0x9F, C1-Steuerzeichen nie roh', () {
    expect(hex(encodeForCodeTable('„Kaffee“ – 2…', CodeTableId.wpc1252)), '844B6166666565932096203285');
    expect(hex(encodeForCodeTable('‚ƒ†‡ˆ‰Š‹ŒŽ‘”—˜™š›œžŸ', CodeTableId.wpc1252)), '8283868788898A8B8C8E91949798999A9B9C9E9F');
    for (var c = 0x80; c < 0xa0; c++) {
      expect(hex(encodeForCodeTable(String.fromCharCode(c), CodeTableId.wpc1252)), '3F', reason: 'U+${c.toRadixString(16)}');
    }
  });

  test('codeTableFromSetting bildet die gespeicherte Einstellung ab', () {
    expect(codeTableFromSetting(PosCodePage.cp437), CodeTableId.pc437);
    expect(codeTableFromSetting(PosCodePage.cp1252), CodeTableId.wpc1252);
    expect(codeTableFromSetting(null), CodeTableId.wpc1252);
  });
}
