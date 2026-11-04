/// Kachel mit Betrag und Referenz: eine Kachel fragt beim Antippen den Betrag
/// (`askPrice`) und/oder eine Referenz (Honorarnote, Auftragsnummer) ab.
/// Zwilling von `pos/kachel-referenz.ts`; Vertrag sind die Pruefaelle
/// `test/fixtures/vertrag/reference-cases.json` (gleich Backend und npm).
library;

/// `optional` = darf leer bleiben, `required` = Pflicht.
enum ReferenceMode { optional, required }

/// Einstellung am Artikel (Draht `reference`).
class PosReference {
  /// Die Felder von `reference` am Draht.
  static const Set<String> fields = {'mode', 'label', 'hint', 'pattern', 'patternStrict'};

  const PosReference({
    required this.mode,
    required this.label,
    this.hint,
    this.pattern,
    this.patternStrict = false,
  });

  final ReferenceMode mode;

  /// Titel des Eingabefelds („Honorarnote Nr.“); steht nie am Beleg.
  final String label;

  /// Platzhalter/Hilfetext („z. B. 2026/0123“); `null` = keiner.
  final String? hint;

  /// Regulaerer Ausdruck fuer die ganze Eingabe (ohne ^/$); `null` = keiner.
  final String? pattern;

  /// `true` = falsches Format sperrt, `false` = nur Warnung.
  final bool patternStrict;

  /// Liest `reference` vom Draht; alles Unbrauchbare -> `null`.
  static PosReference? fromJson(Object? json) {
    if (json is! Map) return null;
    final mode = switch (json['mode']) {
      'optional' => ReferenceMode.optional,
      'required' => ReferenceMode.required,
      _ => null,
    };
    final label = json['label'];
    if (mode == null || label is! String || label.isEmpty) return null;
    final pattern = json['pattern'] is String && (json['pattern'] as String).isNotEmpty ? json['pattern'] as String : null;
    final hint = json['hint'] is String && (json['hint'] as String).isNotEmpty ? json['hint'] as String : null;
    return PosReference(mode: mode, label: label, hint: hint, pattern: pattern, patternStrict: pattern != null && json['patternStrict'] == true);
  }

  Map<String, dynamic> toJson() => {'mode': mode.name, 'label': label, 'hint': hint, 'pattern': pattern, 'patternStrict': patternStrict};
}

/// Hoechstlaenge der Eingabe an der Kasse.
const int referenceInputMax = 40;
const int referenceLabelMax = 30;
const int referenceHintMax = 60;
const int referencePatternMax = 200;

/// Vorlagen fuer das Musterfeld (Panel).
const Map<String, String> referencePatternTemplates = {
  'digits': r'\d+',
  'year_number': r'\d{4}/\d{1,6}',
  'letters_digits': r'[A-Za-z]{1,4}-?\d{1,8}',
};

final RegExp _steuerzeichen = RegExp('[\u0000-\u001f\u007f-\u009f​-‏  ‪-‮⁠-⁤﻿]');
final RegExp _leerraum = RegExp(r'\s+');

/// Eingabe an der Kasse: ohne Steuer- und Formatzeichen, Leerraum
/// zusammengezogen und getrimmt (ohne NFC, wie im JS-Zwilling).
String cleanReferenceText(String text) => text.replaceAll(_steuerzeichen, '').replaceAll(_leerraum, ' ').trim();

// Konstrukte, die JS und Dart nicht garantiert gleich auswerten.
final List<RegExp> _gesperrt = [RegExp(r'\(\?<[=!]'), RegExp(r'\(\?<[A-Za-z]'), RegExp(r'\\[1-9]'), RegExp(r'\\k<'), RegExp(r'\(\?[a-zA-Z]')];

RegExp? _ganz(String pattern) {
  try {
    return RegExp('^(?:$pattern)\$');
  } on FormatException {
    return null;
  }
}

/// Ist das Muster erlaubt (kompilierbar, ohne gesperrte Konstrukte)?
bool isValidReferencePattern(String? pattern) {
  if (pattern == null || pattern.isEmpty || pattern.length > referencePatternMax) return false;
  if (_gesperrt.any((r) => r.hasMatch(pattern))) return false;
  return _ganz(pattern) != null;
}

/// Reines Ziffernmuster -> die Kasse zeigt die Zifferntastatur.
bool isDigitsOnlyPattern(String? pattern) {
  if (pattern == null || pattern.isEmpty || !isValidReferencePattern(pattern)) return false;
  final rest = pattern
      .replaceAll(r'\d', '')
      .replaceAll('[0-9]', '')
      .replaceAll(RegExp(r'\{\d+(,\d*)?\}'), '')
      .replaceAll('(?:', '')
      .replaceAll(RegExp(r'[()|?*+^$]'), '');
  return rest.isEmpty;
}

/// Ergebnis der Pruefung: `empty` und `error` sperren, `warning` zeigt den Hinweis.
enum ReferenceCheckResult { ok, empty, warning, error }

/// Pruefung einer Eingabe mit dem gesaeuberten Wert.
typedef ReferenceCheck = ({ReferenceCheckResult result, String value});

/// Prueft die Eingabe an der Kasse. Ein ungueltiges Muster gilt wie keines.
ReferenceCheck checkReference(String? input, PosReference? reference) {
  var value = cleanReferenceText(input ?? '');
  if (value.length > referenceInputMax) value = value.substring(0, referenceInputMax);
  if (reference == null) return (result: ReferenceCheckResult.ok, value: value);
  if (value.isEmpty) {
    return (result: reference.mode == ReferenceMode.required ? ReferenceCheckResult.empty : ReferenceCheckResult.ok, value: value);
  }
  final p = reference.pattern;
  if (p != null && isValidReferencePattern(p) && !_ganz(p)!.hasMatch(value)) {
    return (result: reference.patternStrict ? ReferenceCheckResult.error : ReferenceCheckResult.warning, value: value);
  }
  return (result: ReferenceCheckResult.ok, value: value);
}

/// Positionsname am Beleg: Artikelname + Leerzeichen + Referenz (leer = nur der Name).
String referenceLineName(String articleName, String? value) =>
    value == null || value.isEmpty ? articleName : '$articleName $value';
