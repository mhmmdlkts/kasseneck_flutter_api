/// Macht Text fuer den Bondrucker druckbar (Zwilling von `escPosPrintableText`
/// im npm-Paket ab 1.1.0).
///
/// Warum getrennt vom Erzeuger: die Ersetzung **aendert die Laenge** ("€"
/// wird zu "EUR", ein Emoji verschwindet). Das Raster rechnet Spalten am
/// fertigen Text, darum wird vorher ersetzt und der Erzeuger bekommt Text,
/// der Zeichen fuer Zeichen ein Byte ist.
library;

import 'code_tables.dart';

/// Ersetzungen, Schluessel sind Unicode-Codepunkte.
const Map<int, String> _ersetzungen = {
  0x2013: '-', 0x2014: '-', 0x2011: '-', 0x2212: '-', // Striche, Minus
  0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"', // doppelte Anfuehrungszeichen
  0x2018: "'", 0x2019: "'", 0x201A: "'", 0x2032: "'", // einfache Anfuehrungszeichen
  0x2026: '...', 0x2022: '*', // Auslassungspunkte, Aufzaehlungspunkt
  0x2713: 'x', 0x2714: 'x', // Haken
  0x20AC: 'EUR', 0x2122: 'TM', 0x20BA: 'TL', // Euro, Markenzeichen, Lira
};

/// Emoji-, Modifier- und Nullbreiten-/Steuerzeichen, die auf dem Beleg nichts
/// verloren haben. Sie werden entfernt statt zu `?` gemacht: ein einzelnes
/// Emoji besteht oft aus mehreren Codepunkten.
bool _istEmojiOderNullbreite(int r) {
  return r == 0x200D || // Zero-Width Joiner
      (r >= 0x200B && r <= 0x200F) ||
      r == 0x2060 ||
      r == 0xFEFF ||
      (r >= 0xFE00 && r <= 0xFE0F) || // Variantenselektoren
      (r >= 0x1F3FB && r <= 0x1F3FF) || // Hautton-Modifier
      (r >= 0x1F000 && r <= 0x1FAFF) || // Emoji-Bloecke
      (r >= 0x2600 && r <= 0x27BF) || // Symbole und Dingbats
      (r >= 0x2B00 && r <= 0x2BFF) || // Symbole und Pfeile
      (r >= 0x2300 && r <= 0x23FF); // technische Symbole
}

/// Ersetzt alles, was der Bondrucker nicht darstellen kann.
///
/// Ohne [codeTable]: genau wie bis 10.0 (Latin-1 bleibt, `€` -> `EUR`), die
/// Bons ohne gewaehlte Tabelle bleiben byte-gleich.
///
/// Mit [codeTable] wird der Text fuer genau diese Tabelle fertig gemacht: `€`
/// bleibt stehen, wenn die Tabelle es hat (der Drucker bekommt das echte
/// Byte), sonst `EUR`; jedes der zehn Zeichen, das der Tabelle fehlt (`§` auf
/// pc437, alle Umlaute auf `replacement` ...), wird schon hier zu seinen
/// Ersatzbuchstaben. Danach ist jedes Zeichen genau ein Byte.
String printableText(String text, {CodeTableId? codeTable}) {
  final List<String> fehlend = codeTable == null ? const [] : codeTableById(codeTable).missing;
  final bool echtesEuro = codeTable != null && !fehlend.contains('€');
  final StringBuffer sb = StringBuffer();
  for (final int rune in text.runes) {
    final String zeichen = String.fromCharCode(rune);
    if (fehlend.contains(zeichen)) {
      sb.write(ersatzBuchstaben(zeichen));
      continue;
    }
    if (rune == 0x20AC && echtesEuro) {
      sb.write(zeichen);
      continue;
    }
    final String? ersatz = _ersetzungen[rune];
    if (ersatz != null) {
      sb.write(ersatz);
    } else if (rune <= 0xFF) {
      sb.writeCharCode(rune); // Latin-1 (inkl. Umlaute) bleibt unveraendert
    } else if (_istEmojiOderNullbreite(rune)) {
      // ersatzlos entfernen
    } else {
      sb.write('?');
    }
  }
  return sb.toString();
}
