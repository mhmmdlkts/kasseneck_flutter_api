/// Wortweiser Umbruch mit haengendem Einzug (Zwilling der Regel in
/// `renderReceiptGrid`, npm ab 1.12.0): die fuehrenden Leerzeichen eines
/// linksbuendigen Textes werden zum Einzug jeder Folgezeile, auf 32 wie auf
/// 48 Zeichen. Ohne fuehrende Leerzeichen, nur aus Leerzeichen oder mit einem
/// Einzug ab der vollen Breite gilt der gewoehnliche Umbruch [wrap]. Passt
/// der Text in eine Zeile, ergibt das dieselben Zeichen wie ohne die Regel.
///
/// Eine Stelle fuer Raster, Rueckfall-Druck und Bildschirm: Vermerke unter
/// einer Gutscheinzeile („  Einzweck, versteuert mit Beleg …“, „  Grund: …“)
/// brechen ueberall gleich um.
List<String> wrapWithIndent(String text, int chars, List<String> Function(String text, int max) wrap) {
  final einzug = leadingIndent(text);
  if (einzug == 0 || einzug >= chars) return wrap(text, chars);
  final vorn = ' ' * einzug;
  return [for (final t in wrap(text.substring(einzug), chars - einzug)) '$vorn$t'];
}

/// Zahl der fuehrenden Leerzeichen eines Textes, 0 fuer einen Text nur aus
/// Leerzeichen (der hat keinen Inhalt, der einzuruecken waere).
int leadingIndent(String text) {
  final ohne = text.trimLeft();
  return ohne.isEmpty ? 0 : text.length - ohne.length;
}
