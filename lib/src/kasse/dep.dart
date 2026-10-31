/// Pruefung (DEP) bei der Kassennachschau an der Kasse: der Ordner, in den
/// Web-Kasse und Kassen-App DEP, Uebergabeprotokoll und Positionen auf den
/// USB-Stick legen. Zwilling von `pos/dep.ts` im npm-Paket; die Prueffaelle
/// stehen im Vertrag (`dep-folder-cases.json`), damit beide Kassen den Ordner
/// gleich benennen. Die Aufrufe selbst stehen an `RegisterReceiptClient`.
library;

/// Zeichen, die FAT32 und exFAT in Namen nicht nehmen, dazu Steuerzeichen und
/// Leerraum (`\s` wie in JavaScript, auch geschuetzte und breite Leerzeichen).
final RegExp _unerlaubt = RegExp(r'[\\/:*?"<>|\u0000-\u001f\u007f\s]');

String _teil(String s) => s.trim().replaceAll(_unerlaubt, '_');

/// Der Ordner auf dem Stick: `DEP_<Kassen-ID>_<from>_<to>` (Tage
/// `YYYY-MM-DD`, wie der Export sie nennt). Ohne Anfang `DEP_<id>_bis_<to>`,
/// ohne Ende `DEP_<id>_ab_<from>`, ohne beides `DEP_<id>_alles`; leer oder nur
/// Leerraum zaehlt wie fehlend, eine leere Kassen-ID wird `Kasse`. Was ein
/// Stick nicht als Namen nimmt, wird `_`.
String depFolderName(String cashregisterId, {String? from, String? to}) {
  final id = _teil(cashregisterId);
  final kasse = id.isEmpty ? 'Kasse' : id;
  final von = from != null && from.trim().isNotEmpty ? _teil(from) : null;
  final bis = to != null && to.trim().isNotEmpty ? _teil(to) : null;
  if (von != null && bis != null) return 'DEP_${kasse}_${von}_$bis';
  if (bis != null) return 'DEP_${kasse}_bis_$bis';
  if (von != null) return 'DEP_${kasse}_ab_$von';
  return 'DEP_${kasse}_alles';
}
