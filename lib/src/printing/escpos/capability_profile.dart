import '../code_tables.dart' show codeTables;

/// Minimales Ersatz-Profil fuer den ESC/POS-Generator. Statt der 66-KB-
/// capabilities.json nur die tatsaechlich genutzten Codepages: die alten
/// Namen `CP437`/`CP1252` und jede Tabelle des Katalogs unter ihrem Namen
/// (`pc858` -> 19 ...).
class CapabilityProfile {
  CapabilityProfile();

  static final Map<String, int> _codePages = {
    'CP437': 0,
    'CP1252': 16,
    for (final t in codeTables) t.id.name: t.escT,
  };

  int getCodePageId(String? codePage) => _codePages[codePage] ?? 0;
}
