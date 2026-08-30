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
import 'package:kasseneck_api/partner.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/register/pairing.dart';

import 'zwillinge_liste.dart';

Map<String, dynamic> _vertrag() => jsonDecode(
      File('test/fixtures/vertrag/oberflaeche.json').readAsStringSync(),
    ) as Map<String, dynamic>;

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
///
/// [fehltNicht] sieht in **beide** Richtungen: eine Lücke ohne Eintrag ist ein
/// Fehler, ein Eintrag ohne Lücke aber auch. Sonst bliebe die Ausnahmeliste
/// stehen, nachdem die Arbeit getan ist, und die Zahl in der CI sänke nie.
class _Funde {
  _Funde(this._ausnahmen) {
    addTearDown(() {
      expect(_liste, isEmpty,
          reason: 'Diese Prüfung hat Abweichungen gesammelt und nie gemeldet — '
              'der Aufruf von melden() am Ende fehlt');
    });
  }

  final Map<String, Ausnahme> _ausnahmen;
  final List<String> _liste = [];

  void fehltNicht(String eintrag, bool vorhanden, String was) {
    final ausnahme = _ausnahmen[eintrag];
    if (vorhanden) {
      if (ausnahme != null) {
        _liste.add('$was gibt es hier — die Lücke ist geschlossen, die Ausnahme '
            'steht aber weiter in zwillinge.yaml (${ausnahme.beleg}) und '
            'gehört gestrichen — Eintrag: $eintrag');
      }
      return;
    }
    if (ausnahme != null) return;
    _liste.add('$was fehlt in diesem Paket und steht nicht in zwillinge.yaml '
        '— Eintrag: $eintrag');
  }

  /// Am Ende jeder Prüfung: alles Gefundene auf einmal melden.
  void melden() {
    if (_liste.isEmpty) return;
    final gefunden = List<String>.from(_liste);
    _liste.clear();
    fail('${gefunden.length} Punkt(e) zwischen Vertrag, Paket und '
        'zwillinge.yaml. Was fehlt, gehört nachgebaut oder benannt; was nicht '
        'mehr fehlt, gehört aus der Liste gestrichen:\n'
        '${gefunden.join('\n')}');
  }
}

void main() {
  final vertrag = _vertrag();
  final ausnahmen = ausnahmenAus('ausnahmen');

  test('Vertrag und Anheftung nennen dieselbe Version', () {
    expect(vertrag['version'], zwillingeDoc()['npm_version'],
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

  group('Partner-Listen', () {
    // Die vierte Prüfung deckte den Partner-Teil nur als Namensliste ab: die
    // 18 Aufrufe standen im Vertrag, die Fehlercodes, Webhook-Ereignisse,
    // Vertragswege und der Wiederholungsplan nicht — und genau die pflegt
    // dieses Paket von Hand nach. Ein Code, den der Zwilling kennt und dieses
    // Paket nicht, hätte hier keinen Handlungssatz und wäre für einen
    // Aufrufer nicht unterscheidbar von „gibt es nicht".
    //
    // Die Zuordnung Vertragsschlüssel → Liste steht hier ausgeschrieben. Sie
    // ist selbst eine Zweitliste — deshalb ist ein Schlüssel, den sie nicht
    // kennt, ein Fehlschlag und kein stilles Überspringen. Nur so fällt eine
    // neue Liste im JS-Paket hier auf.
    final zuordnung = <String, List<Object>>{
      'avvModi': AvvModus.values.map((m) => m.name).toList(),
      'avvStatus': kAvvStatus,
      'partnerFehlerCodes': kPartnerFehlerCodes,
      'partnerWebhookEvents': kPartnerWebhookEreignisse,
      'webhookRetryPlanSec': kWebhookWiederholungSek,
    };

    test('jede Liste des Vertrags gibt es hier — mit denselben Werten', () {
      final partner = (vertrag['partner'] as Map<String, dynamic>?) ?? const {};
      expect(partner, isNotEmpty,
          reason: 'der Vertrag führt keinen Partner-Teil mehr — dann prüft dieser Test nichts');
      final funde = _Funde(ausnahmen);
      for (final eintrag in partner.entries) {
        final hier = zuordnung[eintrag.key];
        if (hier == null) {
          fail('Der Vertrag führt die Partner-Liste "${eintrag.key}", die Zuordnung in '
              'zwillinge_test.dart kennt sie nicht. Entweder die Liste hier nachbauen '
              'und eintragen, oder — wenn sie hier nicht hingehört — begründet in die '
              'Zuordnung aufnehmen.');
        }
        for (final wert in (eintrag.value as List)) {
          funde.fehltNicht('partner.${eintrag.key}.$wert', hier.contains(wert),
              'Der Wert "$wert" aus ${eintrag.key}');
        }
      }
      funde.melden();
    });

    test('keine Liste führt hier mehr, als der Vertrag kennt', () {
      // Die andere Richtung, und hier ausnahmsweise geprüft: ein Fehlercode,
      // den nur dieses Paket kennt, wäre ein toter Handlungssatz — das Backend
      // sendet ihn nie. Anders als bei den Aufrufen gibt es hier keinen Grund,
      // mehr zu können als der Zwilling.
      final partner = (vertrag['partner'] as Map<String, dynamic>?) ?? const {};
      for (final eintrag in zuordnung.entries) {
        final dort = ((partner[eintrag.key] as List?) ?? const []).toList();
        expect(eintrag.value.where((w) => !dort.contains(w)), isEmpty,
            reason: '${eintrag.key}: dieses Paket führt Werte, die der Vertrag nicht kennt');
      }
    });
  });

  test('keine Ausnahme ohne Gegenstück im Vertrag', () {
    // Zweite Hälfte des Aufräumens: hier faellt auf, wenn der Vertrag einen
    // Eintrag gar nicht mehr kennt (das JS-Paket hat ihn abgeschafft). Dass
    // eine Lücke geschlossen wurde und die Zeile trotzdem stehen blieb, findet
    // die jeweilige Prüfung selbst — siehe _Funde.fehltNicht.
    final alle = <String>{
      for (final e in ((vertrag['partner'] as Map<String, dynamic>?) ?? const {}).entries)
        for (final w in (e.value as List)) 'partner.${e.key}.$w',
      for (final e in (vertrag['enums'] as Map<String, dynamic>).entries)
        for (final w in (e.value as List)) 'enums.${e.key}.$w',
      for (final r in (vertrag['rechte'] as List)) 'rechte.$r',
      for (final a in (vertrag['aufrufe'] as List)) 'aufrufe.$a',
      for (final t in (vertrag['tastenAktionen'] as List)) 'tastenAktionen.$t',
    };
    for (final e in ausnahmen.keys) {
      expect(alle, contains(e),
          reason: 'zwillinge.yaml nennt "$e" — den Eintrag gibt es im Vertrag nicht (mehr)');
    }
  });
}
