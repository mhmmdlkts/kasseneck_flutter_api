import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Die Kassen-Einstellungen sind ein Zwilling: dieselben Felder und dieselben
/// Standardwerte wie im Backend (`kasse-settings-core.js`) und in der
/// Browser-Kasse (`@kreiseck/kasseneck-api`). Die Golden-Datei ist die Zusage —
/// weicht sie ab, steht am Tresen ein Schalter anders als im Panel.

Map<String, dynamic> golden() => jsonDecode(
      File('test/fixtures/kasse/kasse-settings-standard.json').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  test('Golden: Standardwerte Feld für Feld wie im JS-Paket', () {
    final soll = golden();
    final ist = const KasseSettings.standard().toJson();

    // Erst die Feldnamen: fehlt hier eines, fehlt es auch der Kasse.
    expect(
      (ist['betrieb'] as Map).keys.toSet(),
      (soll['betrieb'] as Map).keys.toSet(),
      reason: 'Betriebsfelder weichen ab',
    );
    expect(
      (ist['geraet'] as Map).keys.toSet(),
      (soll['geraet'] as Map).keys.toSet(),
      reason: 'Gerätefelder weichen ab',
    );
    expect(ist, soll);
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
    expect(e.betrieb.belegAusgabe, KasseBelegAusgabe.qr);
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
}
