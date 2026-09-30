/// Katalog der Code-Tabellen fuer Bondrucker und die Umwandlung von Text in
/// Bytes je Tabelle (Zwilling von `code-tables.ts` im npm-Paket ab 1.1.0).
///
/// Warum ein Katalog: `ESC t n` waehlt die Zeichentabelle, aber die Nummer n
/// ist nicht einheitlich. Epson legt WPC1252 auf 16, viele guenstige Drucker
/// nummerieren anders oder kennen die Tabelle gar nicht. Wer am Testblatt
/// sieht, welche Nummer seine Umlaute richtig druckt, waehlt hier die
/// passende Tabelle. Gemeinsamer Prueffall mit dem npm-Paket:
/// `test/fixtures/vertrag/code-tables.json`.
///
/// Jede Tabelle setzt die zehn deutschen Zeichen (Umlaute, ß, €, §, °) auf
/// ein Byte oder, wo die Tabelle das Zeichen nicht hat, auf Ersatzbuchstaben
/// (`€` -> `EUR`). Fuer diese zehn Zeichen kommt nie `?` heraus.
library;

import 'dart:typed_data' show Uint8List;

import '../kasse/einstellungen.dart' show PosCodePage;

/// Kennung einer Code-Tabelle. `name` ist der Wert, den das npm-Paket fuehrt
/// und den eine Kasse je Drucker speichert.
enum CodeTableId {
  wpc1252,
  pc858,
  pc850,
  pc437,
  // Der Name ist der Wert des npm-Pakets und der gespeicherten Wahl.
  // ignore: constant_identifier_names
  iso8859_15,
  replacement,
}

/// Eine Code-Tabelle des Katalogs.
class CodeTable {
  /// Kennung.
  final CodeTableId id;

  /// Nummer auf dem Testblatt (1-6).
  final int number;

  /// n fuer `ESC t n`.
  final int escT;

  /// Zeichen der zehn, die diese Tabelle nicht hat und durch Ersatzbuchstaben druckt.
  final List<String> missing;

  const CodeTable._(this.id, this.number, this.escT, this.missing);
}

/// Die zehn Zeichen, fuer die jede Tabelle eine feste Antwort hat.
const List<String> _zehnZeichen = ['ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '€', '§', '°'];

/// Ersatzbuchstaben, wenn die Tabelle das Zeichen nicht hat.
const Map<String, String> _ersatzBuchstaben = {
  'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue', 'ß': 'ss', '€': 'EUR', '§': 'Par.', '°': 'Grad',
};

/// Byte je Zeichen und Tabelle; fehlt ein Zeichen, gilt der Ersatz. Werte aus
/// den Zeichentabellen (Windows-1252, IBM 858/850/437, ISO 8859-15).
const Map<CodeTableId, Map<String, int>> _bytesJeTabelle = {
  CodeTableId.wpc1252: {'ä': 0xe4, 'ö': 0xf6, 'ü': 0xfc, 'Ä': 0xc4, 'Ö': 0xd6, 'Ü': 0xdc, 'ß': 0xdf, '€': 0x80, '§': 0xa7, '°': 0xb0},
  CodeTableId.pc858: {'ä': 0x84, 'ö': 0x94, 'ü': 0x81, 'Ä': 0x8e, 'Ö': 0x99, 'Ü': 0x9a, 'ß': 0xe1, '€': 0xd5, '§': 0xf5, '°': 0xf8},
  CodeTableId.pc850: {'ä': 0x84, 'ö': 0x94, 'ü': 0x81, 'Ä': 0x8e, 'Ö': 0x99, 'Ü': 0x9a, 'ß': 0xe1, '§': 0xf5, '°': 0xf8},
  CodeTableId.pc437: {'ä': 0x84, 'ö': 0x94, 'ü': 0x81, 'Ä': 0x8e, 'Ö': 0x99, 'Ü': 0x9a, 'ß': 0xe1, '°': 0xf8},
  CodeTableId.iso8859_15: {'ä': 0xe4, 'ö': 0xf6, 'ü': 0xfc, 'Ä': 0xc4, 'Ö': 0xd6, 'Ü': 0xdc, 'ß': 0xdf, '€': 0xa4, '§': 0xa7, '°': 0xb0},
  CodeTableId.replacement: {},
};

CodeTable _tabelle(CodeTableId id, int number, int escT) => CodeTable._(
      id,
      number,
      escT,
      List.unmodifiable(_zehnZeichen.where((z) => !_bytesJeTabelle[id]!.containsKey(z))),
    );

/// Alle Code-Tabellen in der Reihenfolge des Testblatts (Nummer 1-6).
final List<CodeTable> codeTables = List.unmodifiable([
  _tabelle(CodeTableId.wpc1252, 1, 16),
  _tabelle(CodeTableId.pc858, 2, 19),
  _tabelle(CodeTableId.pc850, 3, 2),
  _tabelle(CodeTableId.pc437, 4, 0),
  _tabelle(CodeTableId.iso8859_15, 5, 40),
  _tabelle(CodeTableId.replacement, 6, 0),
]);

/// Die Tabelle zu einer Kennung.
CodeTable codeTableById(CodeTableId id) => codeTables.firstWhere((t) => t.id == id);

/// Tabelle aus der gespeicherten Einstellung `codePage` (`CP1252`/`CP437`).
/// Keine Einstellung ist die Vorgabe `wpc1252`.
///
/// Anders als npm (`'cp1252' | 'cp437'`) nimmt diese Seite [PosCodePage]:
/// die Einstellungen der Kasse tragen in Dart schon diesen Enum (Drahtwerte
/// `CP1252`/`CP437`), ein Text muesste erst wieder zurueckuebersetzt werden.
CodeTableId codeTableFromSetting(PosCodePage? setting) =>
    setting == PosCodePage.cp437 ? CodeTableId.pc437 : CodeTableId.wpc1252;

/// Ersatzbuchstaben fuer eines der zehn Zeichen (paketintern, fuer den
/// Druckweg mit gewaehlter Tabelle).
String ersatzBuchstaben(String zeichen) {
  final ersatz = _ersatzBuchstaben[zeichen];
  if (ersatz == null) throw ArgumentError('Kein Ersatz fuer $zeichen');
  return ersatz;
}

/// Zeichen, die vor dem Kodieren ersetzt werden, auf jeder Tabelle gleich
/// (`ZEICHEN_ERSATZ` im npm-Paket; `•` wird `*` wie in `PrintPaper`).
const List<(String, String)> _zeichenErsatz = [
  ('’', "'"), // typografisches Apostroph
  ('´', "'"), // Akut
  ('•', '*'), // Aufzaehlungspunkt
];

/// Latin-1-Byte -> CP437-Byte fuer die Zeichen, die CP437 kennt. Alles
/// andere ab 0x80 hat in CP437 keinen Platz und wird zu "?".
const Map<int, int> _cp437AusLatin1 = {
  0xc7: 0x80, 0xfc: 0x81, 0xe9: 0x82, 0xe2: 0x83, 0xe4: 0x84, 0xe0: 0x85, 0xe5: 0x86, 0xe7: 0x87,
  0xea: 0x88, 0xeb: 0x89, 0xe8: 0x8a, 0xef: 0x8b, 0xee: 0x8c, 0xec: 0x8d, 0xc4: 0x8e, 0xc5: 0x8f,
  0xc9: 0x90, 0xe6: 0x91, 0xc6: 0x92, 0xf4: 0x93, 0xf6: 0x94, 0xf2: 0x95, 0xfb: 0x96, 0xf9: 0x97,
  0xff: 0x98, 0xd6: 0x99, 0xdc: 0x9a, 0xa2: 0x9b, 0xa3: 0x9c, 0xa5: 0x9d, 0xe1: 0xa0, 0xed: 0xa1,
  0xf3: 0xa2, 0xfa: 0xa3, 0xf1: 0xa4, 0xd1: 0xa5, 0xaa: 0xa6, 0xba: 0xa7, 0xbf: 0xa8, 0xac: 0xaa,
  0xbd: 0xab, 0xbc: 0xac, 0xa1: 0xad, 0xab: 0xae, 0xbb: 0xaf, 0xdf: 0xe1, 0xb5: 0xe6, 0xb1: 0xf1,
  0xf7: 0xf6, 0xb0: 0xf8, 0xb7: 0xfa, 0xb2: 0xfd, 0xa0: 0xff,
};

/// Latin-1-Byte -> PC850-Byte (IBM 850, gleich fuer 858 bis auf das €, das
/// die zehn Zeichen schon setzen). PC850 hat fuer jedes Latin-1-Zeichen ab
/// 0xA0 einen Platz; die Steuerzeichen 0x80-0x9F werden zu "?".
const Map<int, int> _pc850AusLatin1 = {
  0xa0: 0xff, 0xa1: 0xad, 0xa2: 0xbd, 0xa3: 0x9c, 0xa4: 0xcf, 0xa5: 0xbe, 0xa6: 0xdd, 0xa7: 0xf5,
  0xa8: 0xf9, 0xa9: 0xb8, 0xaa: 0xa6, 0xab: 0xae, 0xac: 0xaa, 0xad: 0xf0, 0xae: 0xa9, 0xaf: 0xee,
  0xb0: 0xf8, 0xb1: 0xf1, 0xb2: 0xfd, 0xb3: 0xfc, 0xb4: 0xef, 0xb5: 0xe6, 0xb6: 0xf4, 0xb7: 0xfa,
  0xb8: 0xf7, 0xb9: 0xfb, 0xba: 0xa7, 0xbb: 0xaf, 0xbc: 0xac, 0xbd: 0xab, 0xbe: 0xf3, 0xbf: 0xa8,
  0xc0: 0xb7, 0xc1: 0xb5, 0xc2: 0xb6, 0xc3: 0xc7, 0xc4: 0x8e, 0xc5: 0x8f, 0xc6: 0x92, 0xc7: 0x80,
  0xc8: 0xd4, 0xc9: 0x90, 0xca: 0xd2, 0xcb: 0xd3, 0xcc: 0xde, 0xcd: 0xd6, 0xce: 0xd7, 0xcf: 0xd8,
  0xd0: 0xd1, 0xd1: 0xa5, 0xd2: 0xe3, 0xd3: 0xe0, 0xd4: 0xe2, 0xd5: 0xe5, 0xd6: 0x99, 0xd7: 0x9e,
  0xd8: 0x9d, 0xd9: 0xeb, 0xda: 0xe9, 0xdb: 0xea, 0xdc: 0x9a, 0xdd: 0xed, 0xde: 0xe8, 0xdf: 0xe1,
  0xe0: 0x85, 0xe1: 0xa0, 0xe2: 0x83, 0xe3: 0xc6, 0xe4: 0x84, 0xe5: 0x86, 0xe6: 0x91, 0xe7: 0x87,
  0xe8: 0x8a, 0xe9: 0x82, 0xea: 0x88, 0xeb: 0x89, 0xec: 0x8d, 0xed: 0xa1, 0xee: 0x8c, 0xef: 0x8b,
  0xf0: 0xd0, 0xf1: 0xa4, 0xf2: 0x95, 0xf3: 0xa2, 0xf4: 0x93, 0xf5: 0xe4, 0xf6: 0x94, 0xf7: 0xf6,
  0xf8: 0x9b, 0xf9: 0x97, 0xfa: 0xa3, 0xfb: 0x96, 0xfc: 0x81, 0xfd: 0xec, 0xfe: 0xe7, 0xff: 0x98,
};

const int _fragezeichen = 0x3f;

/// Windows-1252 belegt 0x80-0x9F mit eigenen Zeichen (Latin-1 hat dort nur
/// Steuerzeichen). € setzen die zehn Zeichen, ’ und • ersetzt
/// [_zeichenErsatz] vorher; der Rest steht hier.
const Map<int, int> _wpc1252Neu = {
  0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88,
  0x2030: 0x89, 0x0160: 0x8a, 0x2039: 0x8b, 0x0152: 0x8c, 0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92,
  0x201c: 0x93, 0x201d: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02dc: 0x98, 0x2122: 0x99,
  0x0161: 0x9a, 0x203a: 0x9b, 0x0153: 0x9c, 0x017e: 0x9e, 0x0178: 0x9f,
};

/// ISO 8859-15 belegt acht Stellen anders als Latin-1: dort stehen € Š š Ž ž
/// Œ œ Ÿ statt ¤ ¦ ¨ ´ ¸ ¼ ½ ¾. Die acht Latin-1-Zeichen fehlen der Tabelle
/// (Ersetzung, sonst `?`), die neuen stehen hier mit ihrem Byte.
const Set<int> _iso885915Anders = {0xa4, 0xa6, 0xa8, 0xb4, 0xb8, 0xbc, 0xbd, 0xbe};
const Map<int, int> _iso885915Neu = {
  0x0160: 0xa6, 0x0161: 0xa8, 0x017d: 0xb4, 0x017e: 0xb8, 0x0152: 0xbc, 0x0153: 0xbd, 0x0178: 0xbe,
};

/// Byte fuer ein Zeichen ab 0x80, das nicht zu den zehn gehoert.
int _uebrigesZeichen(int codepunkt, CodeTableId id) {
  switch (id) {
    case CodeTableId.wpc1252:
      if (codepunkt < 0xa0) return _fragezeichen; // C1-Steuerzeichen
      if (codepunkt <= 0xff) return codepunkt;
      return _wpc1252Neu[codepunkt] ?? _fragezeichen;
    case CodeTableId.iso8859_15:
      if (codepunkt < 0xa0) return _fragezeichen; // C1-Steuerzeichen
      if (codepunkt <= 0xff) return _iso885915Anders.contains(codepunkt) ? _fragezeichen : codepunkt;
      return _iso885915Neu[codepunkt] ?? _fragezeichen;
    case CodeTableId.pc437:
      return _cp437AusLatin1[codepunkt] ?? _fragezeichen;
    case CodeTableId.pc858:
    case CodeTableId.pc850:
      return _pc850AusLatin1[codepunkt] ?? _fragezeichen;
    case CodeTableId.replacement:
      return _fragezeichen;
  }
}

/// Wandelt Text in die Bytes einer Code-Tabelle: erst die vorhandenen
/// Ersetzungen (’ ´ •), dann die zehn deutschen Zeichen je Tabelle (Byte oder
/// Ersatzbuchstaben), ASCII unveraendert, alles uebrige ueber die Abbildung
/// der Tabelle, sonst `?`. Ein Zeichen, das die Tabelle nicht kennt, ist
/// genau ein Byte (auch ausserhalb der BMP); nur die Ersatzbuchstaben machen
/// aus einem Zeichen mehrere. Spalten darum immer an den fertigen Bytes messen.
Uint8List encodeForCodeTable(String text, CodeTableId table) {
  var aufbereitet = text;
  for (final (von, nach) in _zeichenErsatz) {
    aufbereitet = aufbereitet.replaceAll(von, nach);
  }
  final bytesDerTabelle = _bytesJeTabelle[table]!;
  final bytes = <int>[];
  for (final codepunkt in aufbereitet.runes) {
    if (codepunkt < 0x80) {
      bytes.add(codepunkt);
      continue;
    }
    final zeichen = String.fromCharCode(codepunkt);
    final byte = bytesDerTabelle[zeichen];
    if (byte != null) {
      bytes.add(byte);
      continue;
    }
    final ersatz = _ersatzBuchstaben[zeichen];
    if (ersatz != null) {
      bytes.addAll(ersatz.codeUnits);
      continue;
    }
    bytes.add(_uebrigesZeichen(codepunkt, table));
  }
  return Uint8List.fromList(bytes);
}
