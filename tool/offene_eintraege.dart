// Zählt die benannten Abweichungen in zwillinge.yaml und schreibt sie in den
// CI-Bericht.
//
// Geparst statt gegrept: eine Textsuche nach "art: offen" zählt auch, was in
// einem Kommentar oder einer Beschreibung steht — die sichtbare Schuld ließe
// sich damit versehentlich (oder absichtlich) verstellen. Gezählt werden beide
// Abschnitte, sonst meldet die CI weniger, als benannt ist.
import 'dart:io';

import 'package:yaml/yaml.dart';

const _abschnitte = ['ausnahmen', 'wert_ausnahmen'];

void main() {
  final doc = loadYaml(File('zwillinge.yaml').readAsStringSync()) as YamlMap;
  var offen = 0;
  var dauerhaft = 0;
  for (final abschnitt in _abschnitte) {
    for (final e in (doc[abschnitt] as YamlList?) ?? YamlList()) {
      switch ((e as YamlMap)['art']) {
        case 'offen':
          offen++;
        case 'nicht_zutreffend':
          dauerhaft++;
        case final unbekannt:
          stderr.writeln('zwillinge.yaml: unbekannte art "$unbekannt" '
              'bei "${e['eintrag']}"');
          exit(1);
      }
    }
  }
  stdout.writeln('Offene Einträge gegenüber dem JS-Paket: $offen');
  stdout.writeln('Dauerhaft ausgenommen: $dauerhaft');
}
