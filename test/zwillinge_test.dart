/// Prüft dieses Paket gegen den Vertrag des JS-Zwillings
/// `@kreiseck/kasseneck-api` (Version in zwillinge.yaml, Dateien unter
/// test/fixtures/vertrag).
///
/// Vier Prüfungen, absichtlich unterschiedlich streng — jede sagt selbst, was
/// sie beweist und was nicht. Was hier fehlschlägt, muss entweder nachgebaut
/// oder in zwillinge.yaml benannt werden; stillschweigend abweichen geht nicht.
///
/// **Die Richtung ist nur eine:** geprüft wird Vertrag ⊆ Paket — jeder Eintrag
/// des Zwillings muss hier ankommen. Der umgekehrte Weg bleibt ungeprüft: was
/// dieses Paket zusätzlich führt und der Vertrag nicht kennt, fällt nicht auf
/// (`Aufrufe.getReportV2` etwa). Das ist so gewollt — das Dart-Paket darf mehr
/// können —, aber wer hier nach einem Zuviel sucht, sucht vergeblich.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/register/pairing.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _vertrag() => jsonDecode(
      File('test/fixtures/vertrag/oberflaeche.json').readAsStringSync(),
    ) as Map<String, dynamic>;

/// Die benannten Abweichungen. Ein Eintrag ohne Grund bzw. ohne Issue ist ein
/// Fehler — sonst wird die Liste zum Ablageort für Unerledigtes.
Set<String> _ausnahmen() {
  final doc = loadYaml(File('zwillinge.yaml').readAsStringSync()) as YamlMap;
  final liste = (doc['ausnahmen'] as YamlList?) ?? YamlList();
  final erlaubt = <String>{};
  for (final e in liste) {
    final m = e as YamlMap;
    final eintrag = m['eintrag'] as String?;
    final art = m['art'] as String?;
    if (eintrag == null || art == null) {
      fail('Ausnahme ohne "eintrag" oder "art" in zwillinge.yaml: $e');
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
    erlaubt.add(eintrag);
  }
  return erlaubt;
}

/// Die Funde einer einzelnen Prüfung — gesammelt statt sofort gemeldet, weil
/// eine Prüfung, die beim ersten Fund abbricht, alles Dahinterliegende
/// verdeckt. Der rote Lauf soll die vollständige Arbeitsliste sein.
///
/// Zwei Vorkehrungen, beide gegen denselben Fehler — eine Prüfung, die grün
/// meldet und nichts hält:
///   * Eigene Liste je Prüfung. Eine geteilte würde Funde einer abgebrochenen
///     Schleife unter der Überschrift der nächsten Prüfung auftauchen lassen.
///   * [addTearDown] prüft am Ende jedes Tests, dass nichts Gesammeltes liegen
///     blieb. Wer [melden] vergisst, bekommt rot statt eines stillen Grüns.
class _Funde {
  _Funde(this._ausnahmen) {
    addTearDown(() {
      expect(_liste, isEmpty,
          reason: 'Diese Prüfung hat Abweichungen gesammelt und nie gemeldet — '
              'der Aufruf von melden() am Ende fehlt');
    });
  }

  final Set<String> _ausnahmen;
  final List<String> _liste = [];

  void fehltNicht(String eintrag, bool vorhanden, String was) {
    if (vorhanden || _ausnahmen.contains(eintrag)) return;
    _liste.add('$was fehlt in diesem Paket und steht nicht in zwillinge.yaml '
        '— Eintrag: $eintrag');
  }

  /// Am Ende jeder Prüfung: alles Gefundene auf einmal melden.
  void melden() {
    if (_liste.isEmpty) return;
    final gefunden = List<String>.from(_liste);
    _liste.clear();
    fail('${gefunden.length} Abweichung(en) gegenüber dem Vertrag. Entweder '
        'nachbauen oder als Ausnahme in zwillinge.yaml benennen:\n'
        '${gefunden.join('\n')}');
  }
}

void main() {
  final vertrag = _vertrag();
  final ausnahmen = _ausnahmen();

  test('Vertrag und Anheftung nennen dieselbe Version', () {
    final doc = loadYaml(File('zwillinge.yaml').readAsStringSync()) as YamlMap;
    expect(vertrag['version'], doc['npm_version'],
        reason: 'zwillinge.yaml zeigt auf eine andere Version als die gezogene Kopie — '
            'tool/zwillinge.sh ziehen');
  });

  group('Enum-Werte', () {
    // Beweist mehr als ein Namensvergleich: der Wert muss den Einlesevorgang
    // ueberleben. Kennt dieses Paket ihn nicht, faellt er auf den Standard
    // zurueck — und genau das sieht der Test. Woran die Pruefung scheitert:
    // an einem Wert, den `KasseSettings.aus` verwirft, und an einem Feld, das
    // es hier ueberhaupt nicht gibt (dann kommt gar nichts zurueck).
    //
    // Ihr blinder Fleck: je Feld genau ein Wert — der Dart-Standard. Faellt der
    // Parser auf den Standard zurueck, ist das Ergebnis fuer diesen einen Wert
    // nicht von echtem Einlesen zu unterscheiden (`druckerArt.sdp`,
    // `stil.klar`, `autoAbMin.0`). Ein kaputter Parser bliebe dort unentdeckt;
    // alle uebrigen Werte des Feldes wuerden ihn verraten.
    test('jeder Wert des Vertrags übersteht das Einlesen', () {
      final funde = _Funde(ausnahmen);
      final enums = vertrag['enums'] as Map<String, dynamic>;
      // Annahme, kein Beweis: welches Feld in welchem Teil steht. Fuer Felder,
      // die es hier noch gar nicht gibt (logoSkala, wzSkala, wzSeite,
      // wzStaerke -> betrieb; terminalArt, terminalVia -> geraet), nimmt diese
      // Liste die kuenftige Zuordnung vorweg. Baut ein spaeterer Task eines
      // davon in den anderen Teil, bleibt die Pruefung rot, obwohl die
      // Umsetzung stimmt — dann gehoert die Zuordnung hier korrigiert, nicht
      // die Umsetzung. Gefaehrlich ist das nicht: es entsteht hoechstens ein
      // falscher Roter, nie ein falscher Gruener.
      const betriebsfelder = {
        'stil', 'schrift', 'wasserzeichen', 'menge', 'tgModus', 'kassierenModus',
        'kartenanbieter', 'belegAusgabe',
        // Zehn weitere Betriebsfelder, deren Wertelisten erst spaeter entstanden sind.
        'logoGroesse', 'schriftEinst', 'kachelstil', 'autoAbMin', 'rabatt',
        'wzSeite', 'wzStaerke', 'logoSkala', 'wzSkala', 'fertigSekunden',
      };
      for (final feld in enums.keys) {
        // Nicht auf String einengen: der Vertrag fuehrt auch Zahlenlisten
        // (autoAbMin, wzStaerke, fertigSekunden). Ein Cast wuerde beim ersten
        // Zahlenfeld abbrechen und die restliche Liste verdecken.
        for (final wert in (enums[feld] as List)) {
          final teil = betriebsfelder.contains(feld) ? 'betrieb' : 'geraet';
          final gelesen = KasseSettings.aus({
            teil: {feld: wert},
          }).toJson();
          final zurueck = (gelesen[teil] as Map)[feld];
          funde.fehltNicht('enums.$feld.$wert', zurueck == wert, 'Der Wert "$wert" für $feld');
        }
      }
      funde.melden();
    });
  });

  group('Rechte-Schlüssel', () {
    // Ein Schluessel, den das Paket nur im Auffangbecken `weitere` haelt, gilt
    // NICHT als gekannt: die Oberflaeche kann ihn dann nicht abfragen. Woran
    // die Pruefung scheitert: an genau diesem Fall.
    test('kein Schlüssel des Vertrags landet im Auffangbecken', () {
      final funde = _Funde(ausnahmen);
      final rechte = (vertrag['rechte'] as List).cast<String>();
      final roh = <String, dynamic>{for (final r in rechte) r: r.endsWith('Scope') ? 'all' : true};
      final perms = RegisterUserPerms.aus(roh);
      for (final r in rechte) {
        funde.fehltNicht('rechte.$r', !perms.weitere.containsKey(r), 'Das Recht "$r"');
      }
      funde.melden();
    });
  });

  group('Aufrufnamen', () {
    // Die schwaechste der vier: sie beweist, dass das Paket den Namen KENNT,
    // nicht dass der Aufruf funktioniert. Trotzdem findet sie genau das, was
    // ein Wertevergleich nie findet — einen Aufruf, den es hier gar nicht gibt.
    test('jeder Aufruf des Vertrags ist hier bekannt', () {
      final funde = _Funde(ausnahmen);
      for (final name in (vertrag['aufrufe'] as List).cast<String>()) {
        funde.fehltNicht('aufrufe.$name', Aufrufe.alle.contains(name), 'Der Aufruf "$name"');
      }
      funde.melden();
    });
  });

  group('Tasten-Aktionen', () {
    // Woran sie scheitert: an einer Aktion, die der Zwilling einer Taste
    // zuordnen kann und dieses Paket nicht — die Belegung waere dann nicht
    // uebertragbar.
    test('jede Aktion des Vertrags ist hier bekannt', () {
      final funde = _Funde(ausnahmen);
      for (final aktion in (vertrag['tastenAktionen'] as List).cast<String>()) {
        funde.fehltNicht('tastenAktionen.$aktion', kasseTastenAktionen.contains(aktion),
            'Die Tasten-Aktion "$aktion"');
      }
      funde.melden();
    });
  });

  test('keine Ausnahme ohne Gegenstück — erledigte Einträge fliegen raus', () {
    // Sonst bleibt die Liste stehen, nachdem die Luecke geschlossen wurde, und
    // behauptet Schulden, die es nicht mehr gibt.
    final alle = <String>{
      for (final e in (vertrag['enums'] as Map<String, dynamic>).entries)
        for (final w in (e.value as List)) 'enums.${e.key}.$w',
      for (final r in (vertrag['rechte'] as List)) 'rechte.$r',
      for (final a in (vertrag['aufrufe'] as List)) 'aufrufe.$a',
      for (final t in (vertrag['tastenAktionen'] as List)) 'tastenAktionen.$t',
    };
    for (final e in ausnahmen) {
      expect(alle, contains(e),
          reason: 'zwillinge.yaml nennt "$e" — den Eintrag gibt es im Vertrag nicht (mehr)');
    }
  });
}
