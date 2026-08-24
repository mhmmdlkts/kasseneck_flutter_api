import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

import 'zwillinge_liste.dart';

/// Die Kassen-Einstellungen sind ein Zwilling: dieselben Felder und dieselben
/// Standardwerte wie im Backend (`kasse-settings-core.js`) und in der
/// Browser-Kasse (`@kreiseck/kasseneck-api`). Die Golden-Datei ist die Zusage —
/// weicht sie ab, steht am Tresen ein Schalter anders als im Panel.

Map<String, dynamic> golden() => jsonDecode(
      File('test/fixtures/vertrag/kasse-settings-standard.json').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  // Welche Felder im Standardwert abweichen dürfen, steht in zwillinge.yaml
  // (Abschnitt wert_ausnahmen) — nicht in diesem Testcode. Sie gehen durch
  // dieselbe Prüfung wie die Hauptliste: ohne Grund bzw. ohne Issue-Nummer
  // wird der Lauf abgewiesen, und wer eine Abweichung auflöst, muss die Zeile
  // streichen (siehe den zweiten Test).
  final wertAusnahmen = ausnahmenAus('wert_ausnahmen');

  test('Golden: Standardwerte Feld für Feld wie im JS-Paket', () {
    final soll = golden();
    final ist = const KasseSettings.standard().toJson();

    // Was diese Prüfung hält:
    //   * Jedes Feld, das dieses Paket führt, heißt wie im Vertrag und trägt
    //     denselben Standardwert — sonst steht am Tresen ein Schalter anders
    //     als im Panel.
    //   * Ein Feld, das nur dieses Paket führt, ist ein Fehler: der Vertrag
    //     kennt es nicht, die Browser-Kasse könnte es nicht auswerten.
    // Was sie NICHT mehr hält:
    //   * Fehlende Felder. Der Vertrag führt derzeit 15 mehr als dieses Paket
    //     (siehe zwillinge.yaml, Einträge mit art: offen); gemeldet werden sie
    //     von zwillinge_test.dart — dort gehören sie hin.
    //   * Die beiden Werte, die zwillinge.yaml unter wert_ausnahmen nennt.
    for (final teil in const ['betrieb', 'geraet']) {
      final hier = (ist[teil] as Map).keys.toSet();
      final dort = (soll[teil] as Map).keys.toSet();
      expect(hier.difference(dort), isEmpty,
          reason: 'Dieses Paket führt ein Feld in "$teil", das der Vertrag nicht kennt');
      for (final k in hier) {
        if (wertAusnahmen.containsKey('$teil.$k')) continue;
        expect((ist[teil] as Map)[k], (soll[teil] as Map)[k], reason: 'Feld $teil.$k');
      }
    }

    // Die Aufteilung selbst bleibt streng: ein dritter Teil neben Betrieb und
    // Gerät wäre eine Abweichung, die die Schleife oben nie sähe.
    expect(ist.keys.toSet(), soll.keys.toSet(), reason: 'Aufteilung der Einstellungen');
  });

  test('jede Wert-Ausnahme nennt ein Feld, das hier wirklich abweicht', () {
    // Sonst bleibt eine Ausnahme stehen, nachdem der Wert angeglichen wurde,
    // und schwächt die Prüfung für ein Feld, das längst stimmt.
    final ist = const KasseSettings.standard().toJson();
    final soll = golden();
    for (final a in wertAusnahmen.values) {
      final teil = a.eintrag.split('.').first;
      final feld = a.eintrag.split('.').last;
      expect((ist[teil] as Map?)?.containsKey(feld), isTrue,
          reason: 'zwillinge.yaml nennt "${a.eintrag}" unter wert_ausnahmen — '
              'das Feld gibt es hier nicht');
      expect((soll[teil] as Map?)?.containsKey(feld), isTrue,
          reason: 'zwillinge.yaml nennt "${a.eintrag}" unter wert_ausnahmen — '
              'das Feld kennt der Vertrag nicht (mehr)');
      expect((ist[teil] as Map)[feld], isNot((soll[teil] as Map)[feld]),
          reason: 'zwillinge.yaml nennt "${a.eintrag}" unter wert_ausnahmen, der '
              'Wert stimmt aber mit dem Vertrag überein — die Zeile gehört '
              'gestrichen (${a.beleg})');
    }
  });

  test('Gespeichertes gewinnt über den Standard, Unbekanntes bleibt draußen', () {
    final e = KasseSettings.aus({
      'betrieb': {'stil': 'nacht', 'zahlKarte': true, 'kartenanbieter': 'hobex', 'quatsch': 1},
      'geraet': {'layout': 'links', 'druckerAn': true, 'druckerArt': 'netz', 'druckerIp': '192.168.0.136'},
    });

    expect(e.betrieb.stil, KasseStil.nacht);
    expect(e.betrieb.zahlKarte, isTrue);
    expect(e.betrieb.kartenanbieter, KasseKartenanbieter.hobex);
    expect(e.betrieb.zahlBar, isTrue, reason: 'nicht Genanntes bleibt beim Standard');
    expect(e.geraet.layout, KasseLayout.links);
    expect(e.geraet.druckerIp, '192.168.0.136');
    expect(e.toJson()['betrieb'], isNot(contains('quatsch')));
  });

  test('Landkarten werden je Schlüssel gemischt — neue Steuersätze kommen beim Altbestand an', () {
    final e = KasseSettings.aus({
      'betrieb': {
        // Ein Altbestand kennt 4,9 % noch nicht und hat 19 % eingeschaltet.
        'saetze': {'19': true, '20': false},
      },
    });
    expect(e.betrieb.saetze['4.9'], isTrue, reason: 'neuer Satz kommt aus dem Standard');
    expect(e.betrieb.saetze['19'], isTrue, reason: 'eigener Wert gewinnt');
    expect(e.betrieb.saetze['20'], isFalse);
  });

  test('unbekannte Werte fallen auf den Standard zurück — die Kasse rät nicht', () {
    final e = KasseSettings.aus({
      'betrieb': {'stil': 'neonpink', 'schrift': 'XXL', 'belegAusgabe': 'brieftaube', 'autoAbMin': 7},
      'geraet': {'druckerArt': 'telepathie', 'papier': 'a4', 'druckerPort': -1},
    });
    expect(e.betrieb.stil, KasseStil.klar);
    expect(e.betrieb.schrift, KasseSchrift.m);
    expect(e.betrieb.belegAusgabe, KasseBelegAusgabe.fragen);
    expect(e.betrieb.autoAbMin, 0);
    expect(e.geraet.druckerArt, KasseDruckerArt.sdp);
    expect(e.geraet.papier, KassePapier.mm80);
    expect(e.geraet.druckerPort, 9100);
  });

  test('was hereinkam, kommt wieder heraus — hin und zurück ohne Verlust', () {
    final roh = {
      'betrieb': {'farbe': '#AABBCC', 'tgChips': [7.5, 12.0], 'saetze': {'20': false}, 'fertigSekunden': 15},
      'geraet': {'tasten': {'bar': ['Mod+B', 'F2']}, 'spaltenExtra': 2, 'terminalPort': 20009},
    };
    final einmal = KasseSettings.aus(roh);
    final zweimal = KasseSettings.aus(einmal.toJson());
    expect(zweimal.toJson(), einmal.toJson());
    expect(zweimal.betrieb.tgChips, [7.5, 12.0]);
    expect(zweimal.geraet.tasten['bar'], ['Mod+B', 'F2']);
    expect(zweimal.betrieb.fertigSekunden, 15);
  });

  test('Karte gibt es nur mit eingerichtetem Anbieter', () {
    expect(const KasseSettings.standard().betrieb.kartenAktiv, isFalse);
    expect(KasseSettings.aus({'betrieb': {'zahlKarte': true}}).betrieb.kartenAktiv, isFalse,
        reason: 'ohne Anbieter nützt der Schalter nichts');
    expect(KasseSettings.aus({'betrieb': {'zahlKarte': true, 'kartenanbieter': 'extern'}}).betrieb.kartenAktiv, isTrue);
    expect(KasseSettings.aus({'betrieb': {'zahlKarte': false, 'kartenanbieter': 'hobex'}}).betrieb.kartenAktiv, isFalse);
  });

  test('eingeschaltete Steuersätze in fester Reihenfolge — der Bildschirm rät die Ordnung nicht', () {
    expect(const KasseSettings.standard().betrieb.aktiveSaetze, [20.0, 13.0, 10.0, 4.9, 0.0]);
    final e = KasseSettings.aus({'betrieb': {'saetze': {'19': true, '10': false}}});
    expect(e.betrieb.aktiveSaetze, [20.0, 19.0, 13.0, 4.9, 0.0]);
  });

  group('mit()', () {
    test('mischt eine Änderung in den Stand', () {
      // Gebraucht, wo eine Einstellung sofort gelten soll, während der Server
      // noch antwortet.
      const stand = KasseSettingsBetrieb();
      final neu = stand.mit({'uhr': false});
      expect(neu.uhr, isFalse);
      expect(neu.zahlBar, stand.zahlBar, reason: 'alles Übrige bleibt');
    });

    test('lässt den Ausgangsstand unberührt', () {
      // Sonst gäbe es nichts, worauf man zurückspringen könnte.
      const stand = KasseSettingsBetrieb();
      stand.mit({'uhr': false});
      expect(stand.uhr, isTrue);
    });

    test('auch am Gerät', () {
      const g = KasseSettingsGeraet();
      expect(g.mit({'touch': true}).touch, isTrue);
      expect(g.touch, isFalse);
    });
  });
}