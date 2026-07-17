/// Minimales Ersatz-Profil fuer den ESC/POS-Generator. Statt der 66-KB-
/// capabilities.json nur die tatsaechlich genutzten Codepages.
class CapabilityProfile {
  CapabilityProfile();

  static const Map<String, int> _codePages = {
    'CP437': 0,
    'CP1252': 16,
  };

  int getCodePageId(String? codePage) => _codePages[codePage] ?? 0;
}
