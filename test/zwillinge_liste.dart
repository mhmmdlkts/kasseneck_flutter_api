/// Liest die benannten Abweichungen aus `zwillinge.yaml`.
///
/// Zwei Abschnitte, **eine** Strenge:
///   * `ausnahmen` — was der Vertrag führt und dieses Paket nicht (Werte,
///     Rechte, Aufrufe, Tasten-Aktionen); geprüft von `zwillinge_test.dart`.
///   * `wert_ausnahmen` — Felder, die es hier gibt, deren Standardwert aber
///     abweicht; geprüft von `kasse_einstellungen_test.dart`.
///
/// Beide gehen durch dieselbe Prüfung. Sonst wäre die eine Hälfte der
/// Buchführung lascher als die andere — und die lasche Hälfte würde zum
/// Ablageort für alles, was gerade stört.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

YamlMap zwillingeDoc() =>
    loadYaml(File('zwillinge.yaml').readAsStringSync()) as YamlMap;

/// Eine benannte Abweichung, so wie sie in `zwillinge.yaml` steht.
class Ausnahme {
  const Ausnahme({
    required this.eintrag,
    required this.art,
    this.grund,
    this.issue,
  });

  final String eintrag;

  /// `offen` (Schuld, mit Issue-Nummer) oder `nicht_zutreffend` (dauerhaft,
  /// mit Grund).
  final String art;
  final String? grund;
  final int? issue;

  bool get istOffen => art == 'offen';

  /// Kurzform für Fehlermeldungen: die Issue-Nummer bzw. der Grund.
  String get beleg => istOffen ? 'Issue #$issue' : grund!;
}

/// Liest einen Abschnitt und lehnt jede unvollständige Zeile ab: ohne Grund
/// bzw. ohne Issue-Nummer ist eine Ausnahme nur ein stiller Verzicht.
Map<String, Ausnahme> ausnahmenAus(String abschnitt) {
  final liste = (zwillingeDoc()[abschnitt] as YamlList?) ?? YamlList();
  final erlaubt = <String, Ausnahme>{};
  for (final e in liste) {
    final m = e as YamlMap;
    final eintrag = m['eintrag'] as String?;
    final art = m['art'] as String?;
    if (eintrag == null || art == null) {
      fail('Ausnahme ohne "eintrag" oder "art" in zwillinge.yaml ($abschnitt): $e');
    }
    if (art == 'nicht_zutreffend' && (m['grund'] as String?)?.isNotEmpty != true) {
      fail('Ausnahme "$eintrag" ist nicht_zutreffend, nennt aber keinen Grund');
    }
    if (art == 'offen' && m['issue'] == null) {
      fail('Ausnahme "$eintrag" ist offen, nennt aber keine Issue-Nummer');
    }
    if (art != 'nicht_zutreffend' && art != 'offen') {
      fail('Ausnahme "$eintrag" hat unbekannte art "$art"');
    }
    // Eine zweite Zeile zum selben Eintrag würde die erste stillschweigend
    // überschreiben — dann stünde in der Liste etwas anderes, als gilt.
    if (erlaubt.containsKey(eintrag)) {
      fail('zwillinge.yaml nennt "$eintrag" in "$abschnitt" zweimal');
    }
    erlaubt[eintrag] = Ausnahme(
      eintrag: eintrag,
      art: art,
      grund: m['grund'] as String?,
      issue: m['issue'] as int?,
    );
  }
  return erlaubt;
}
