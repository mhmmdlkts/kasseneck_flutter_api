import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/printing.dart';

import 'zwillinge_liste.dart';

/// Die Kassen-Einstellungen sind ein Zwilling: dieselben Felder und dieselben
/// Standardwerte wie im Backend (`kasse-settings-core.js`) und in der
/// Browser-Kasse (`@kreiseck/kasseneck-api`). Die Golden-Datei ist die Zusage —
/// weicht sie ab, steht am Tresen ein Schalter anders als im Panel.

Map<String, dynamic> golden() => jsonDecode(
      File('test/fixtures/vertrag/pos-settings-defaults.json').readAsStringSync(),
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
    for (final teil in const ['business', 'device']) {
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

  test('Gespeichertes gewinnt über den Standard, unbekannte Schlüssel bleiben draußen', () {
    final e = KasseSettings.aus({
      'business': {'theme': 'night', 'payCard': true, 'cardProvider': 'hobex', 'quatsch': 1},
      'device': {'layout': 'left', 'printerEnabled': true, 'printerType': 'network', 'printerIp': '192.168.0.136'},
    });

    expect(e.betrieb.theme, KasseStil.night);
    expect(e.betrieb.payCard, isTrue);
    expect(e.betrieb.cardProvider, KasseKartenanbieter.hobex);
    expect(e.betrieb.payCash, isTrue, reason: 'nicht Genanntes bleibt beim Standard');
    expect(e.geraet.layout, KasseLayout.left);
    expect(e.geraet.printerType, KasseDruckerArt.network);
    expect(e.geraet.printerIp, '192.168.0.136');
    expect(e.toJson()['business'], isNot(contains('quatsch')));
  });

  test('Landkarten werden je Schlüssel gemischt, neue Steuersätze kommen beim Altbestand an', () {
    final e = KasseSettings.aus({
      'business': {
        // Ein Altbestand kennt 4,9 % noch nicht und hat 19 % eingeschaltet.
        'vatRates': {'19': true, '20': false},
      },
    });
    expect(e.betrieb.vatRates['4.9'], isTrue, reason: 'neuer Satz kommt aus dem Standard');
    expect(e.betrieb.vatRates['19'], isTrue, reason: 'eigener Wert gewinnt');
    expect(e.betrieb.vatRates['20'], isFalse);
  });

  group('unbekannte Werte des Servers', () {
    test('die Kasse arbeitet mit dem Standard, der Wert bleibt wörtlich erhalten', () {
      final e = KasseSettings.aus({
        'business': {'theme': 'sepia', 'fontSize': 'XXL', 'receiptOutput': 'pigeon', 'autoLogoutMinutes': 7},
        'device': {'printerType': 'star', 'paperSize': 'a4', 'printerPort': -1},
      });
      expect(e.betrieb.theme, KasseStil.clear);
      expect(e.betrieb.fontSize, KasseSchrift.m);
      expect(e.betrieb.receiptOutput, KasseBelegAusgabe.ask);
      expect(e.betrieb.autoLogoutMinutes, 0);
      expect(e.geraet.printerType, KasseDruckerArt.sdp);
      expect(e.geraet.paperSize, KassePapier.mm80);
      expect(e.geraet.printerPort, 9100, reason: 'ausserhalb des Bereichs arbeitet die Kasse mit dem Standard');

      final json = e.toJson();
      expect(json['business']['theme'], 'sepia');
      expect(json['business']['fontSize'], 'XXL');
      expect(json['business']['receiptOutput'], 'pigeon');
      expect(json['business']['autoLogoutMinutes'], 7);
      expect(json['device']['printerType'], 'star');
      expect(json['device']['paperSize'], 'a4');
      expect(unknownPosSettingValues(e), unorderedEquals([
        'business.theme', 'business.fontSize', 'business.receiptOutput', 'business.autoLogoutMinutes',
        'device.printerType', 'device.paperSize', 'device.printerPort',
      ]));
      expect(json['device']['printerPort'], -1);
    });

    test('eine Änderung an einem anderen Feld sendet den fremden Wert nicht mit', () {
      // Rundweg des npm-Berichts: lesen mit sepia, fontSize ändern, schreiben;
      // die Anfrage enthält kein theme, der Wert bleibt am Server stehen.
      final vorher = KasseSettings.aus({'business': {'theme': 'sepia'}}).betrieb;
      final nachher = vorher.mit({'fontSize': 'L'});
      expect(nachher.toJson()['theme'], 'sepia', reason: 'mit() behält den fremden Wert');
      expect(posSettingsChanges(vorher.toJson(), nachher.toJson()), {'fontSize': 'L'});
    });

    test('eine unbekannte Tasten-Aktion bleibt stehen und wird genannt', () {
      final e = KasseSettings.aus({
        'device': {'shortcuts': {'teleport': ['Mod+T']}},
      });
      expect(e.geraet.shortcuts['teleport'], ['Mod+T']);
      expect(unknownPosSettingValues(e), ['device.shortcuts.teleport']);
    });

    test('Zahlen ausserhalb des Bereichs und abweichende Chips werden genannt, nie still ersetzt', () {
      // Ein neueres Backend erlaubt vielleicht extraColumns 6: die Kasse zeigt
      // dann nicht 0 als eingestellt, und ein Schreiben anderer Felder
      // ueberschreibt die 6 nicht.
      final e = KasseSettings.aus({
        'business': {'watermarkX': 150, 'tipChips': [1, 2, 3, 4, 5, 6], 'discountChips': [5, 5]},
        'device': {'extraColumns': 6, 'terminalPort': 70000},
      });
      expect(e.betrieb.watermarkX, 50);
      expect(e.betrieb.tipChips, [1, 2, 3, 4, 5]);
      expect(e.geraet.extraColumns, 0);
      expect(unknownPosSettingValues(e), unorderedEquals([
        'business.watermarkX', 'business.tipChips', 'business.discountChips',
        'device.extraColumns', 'device.terminalPort',
      ]));
      expect(e.toJson()['device']['extraColumns'], 6);
      expect(e.toJson()['business']['tipChips'], [1, 2, 3, 4, 5, 6]);
      final nachher = e.geraet.mit({'touch': true});
      expect(posSettingsChanges(e.geraet.toJson(), nachher.toJson()), {'touch': true});
      expect(unknownPosSettingValues(const KasseSettings.standard()), isEmpty);
    });

    test('ein bekannter Wert ersetzt den fremden', () {
      final e = KasseSettings.aus({'business': {'theme': 'sepia'}}).betrieb.mit({'theme': 'night'});
      expect(e.theme, KasseStil.night);
      expect(e.fremdeWerte, isEmpty);
    });
  });

  test('Werte der inneren Form 0.x fallen auf den Standard, nie ins Modell', () {
    // layout und terminalVia heissen innen und aussen gleich: ein
    // zwischengespeicherter Mischstand trüge sonst 'rechts' ins Modell.
    final e = KasseSettings.aus({
      'business': {'theme': 'nacht', 'cardProvider': 'keiner'},
      'device': {
        'layout': 'rechts',
        'terminalVia': 'direkt',
        'shortcuts': {'kassieren': ['F9'], 'cash': ['F2']},
      },
    });
    expect(e.betrieb.theme, KasseStil.clear);
    expect(e.betrieb.cardProvider, KasseKartenanbieter.none);
    expect(e.geraet.layout, KasseLayout.right);
    expect(e.geraet.terminalVia, KasseTerminalVia.direct);
    expect(e.geraet.shortcuts.containsKey('kassieren'), isFalse);
    expect(e.geraet.shortcuts['cash'], ['F2']);
    expect(unknownPosSettingValues(e), isEmpty, reason: 'ein deutscher Wert ist kein fremder Wert');
  });

  group('Zwischenspeicher der Version 9.x (innere Form)', () {
    test('die Standardwerte der inneren Form ergeben die Standardwerte des Drahts', () {
      // stored/pos-settings-defaults.json ist die deutsche Form, die toJson bis
      // 9.x schrieb und die Flutter-Kasse zwischenspeichert.
      final stored = jsonDecode(File('test/fixtures/vertrag/stored/pos-settings-defaults.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(KasseSettings.aus(stored).toJson(), golden());
    });

    test('ein eingestellter 9.x-Stand bleibt nach dem Update erhalten', () {
      final e = KasseSettings.aus({
        'betrieb': {
          'stil': 'nacht', 'zahlKarte': true, 'kartenanbieter': 'extern', 'kassierenModus': 'seite',
          'belegAusgabe': 'druck', 'saetze': {'19': true}, 'tgChips': [7.5], 'zahlGetrennt': true,
        },
        'geraet': {
          'layout': 'links', 'druckerArt': 'bt', 'druckerBt': 'AA:BB', 'ladeAuto': 'immer',
          'tasten': {'bar': ['F2'], 'getrennt': ['F4']}, 'qrModus': 'escpos', 'terminalArt': 'hps',
        },
      });
      expect(e.betrieb.theme, KasseStil.night);
      expect(e.betrieb.payCard, isTrue);
      expect(e.betrieb.cardProvider, KasseKartenanbieter.external);
      expect(e.betrieb.checkoutMode, KasseKassierenModus.page);
      expect(e.betrieb.receiptOutput, KasseBelegAusgabe.print);
      expect(e.betrieb.vatRates['19'], isTrue);
      expect(e.betrieb.tipChips, [7.5]);
      expect(e.betrieb.paySplit, isTrue);
      expect(e.geraet.layout, KasseLayout.left);
      expect(e.geraet.printerType, KasseDruckerArt.bluetooth);
      expect(e.geraet.printerBluetoothId, 'AA:BB');
      expect(e.geraet.drawerAutoOpen, KasseLadeAuto.always);
      expect(e.geraet.shortcuts['cash'], ['F2']);
      expect(e.geraet.shortcuts['splitPayment'], ['F4']);
      expect(e.geraet.qrMode, KasseQrModus.escpos);
      expect(e.geraet.terminalType, KasseTerminalArt.hps);
      expect(unknownPosSettingValues(e), isEmpty);
    });

    test('der 9.x-Tastenstandard ergibt keine Doppelbelegung (entwirrt wie der Server)', () {
      // So schrieb 9.x toJson die Tasten eines Geraets ohne eigene Belegung.
      const tasten9x = {
        'kassieren': ['Enter'], 'abschliessen': ['Enter'], 'abbrechen': ['Escape'], 'frei': ['Mod+F'],
        'bar': ['Mod+B'], 'karte': ['Mod+K'], 'passend': ['Mod+P'], 'belege': ['Mod+E'],
        'letzteZurueck': ['Mod+Backspace'],
      };
      final e = KasseSettings.aus({'geraet': {'tasten': tasten9x}});
      final karte = e.geraet.shortcuts;
      expect(posShortcutConflict(karte), isNull);
      expect(karte['customAmount'], ['Mod+F'], reason: 'die gespeicherte Wahl gewinnt');
      expect(karte['fullscreen'], isEmpty, reason: 'die beanspruchte Vorgabe-Taste faellt');
      expect(karte['receipts'], ['Mod+E']);
      expect(karte['settings'], ['Mod+S'], reason: 'nicht beanspruchte Vorgaben bleiben');
      // Die Taste ist damit am Geraet frei vergebbar, ohne Abweisung.
      final neu = e.geraet.mit({'shortcuts': {'splitPayment': ['F4']}});
      expect(posShortcutConflict(neu.shortcuts), isNull);
    });

    test('entwirreTasten: Paare duerfen teilen, fremde Aktionen verlieren die Taste', () {
      const gespeichert = {'clearTendered': ['Mod+C'], 'cash': ['Mod+K']};
      final raus = entwirreTasten({...kasseTastenStandard, ...gespeichert}, gespeichert);
      expect(raus['clearCart'], ['Mod+C'], reason: 'clearTendered und clearCart duerfen teilen');
      expect(raus['card'], isEmpty, reason: 'Mod+K gehoert jetzt cash');
      expect(raus['cash'], ['Mod+K']);
    });

    test('dokumentiert: die uebrigen 9.x-Standardwerte gelten bis zur ersten Serverantwort', () {
      // Der 9.x-Stand ist der gemischte Stand samt der damaligen Vorgaben.
      // terminalPort 20008 und kassierenModus seite bleiben darum bis zur
      // ersten Antwort von getKasseSettings bzw. der Benutzerliste stehen
      // (Entscheidung Koordinator, Runde 1: nur Tasten werden entwirrt).
      final e = KasseSettings.aus({
        'betrieb': {'kassierenModus': 'seite'},
        'geraet': {'terminalPort': 20008},
      });
      expect(e.betrieb.checkoutMode, KasseKassierenModus.page);
      expect(e.geraet.terminalPort, 20008);
    });

    test('die Übersetzungstabellen sind renames-1.0.json', () {
      final r = jsonDecode(File('test/fixtures/vertrag/renames-1.0.json').readAsStringSync()) as Map<String, dynamic>;
      final struktur = r['structure']['pos-settings-defaults.json'] as Map<String, dynamic>;
      expect(altformBetriebSchluessel, struktur['business']);
      expect(altformGeraetSchluessel, struktur['device']);
      expect(altformTastenAktionen, struktur['shortcuts']);
      final werte = r['values']['pos-settings-defaults.json'] as Map<String, dynamic>;
      final soll = <String, Map<String, String>>{
        for (final e in werte.entries)
          (e.key.split('.').last): {
            for (final w in (e.value as Map<String, dynamic>).entries)
              if (w.key != w.value) w.key: w.value as String,
          },
      }..removeWhere((_, v) => v.isEmpty);
      expect(altformWerte, soll);
    });
  });

  test('was hereinkam, kommt wieder heraus, hin und zurück ohne Verlust', () {
    final roh = {
      'business': {'color': '#AABBCC', 'tipChips': [7.5, 12.0], 'vatRates': {'20': false}, 'doneScreenSeconds': 15},
      'device': {'shortcuts': {'cash': ['Mod+B', 'F2']}, 'extraColumns': 2, 'terminalPort': 20009},
    };
    final einmal = KasseSettings.aus(roh);
    final zweimal = KasseSettings.aus(einmal.toJson());
    expect(zweimal.toJson(), einmal.toJson());
    expect(zweimal.betrieb.tipChips, [7.5, 12.0]);
    expect(zweimal.geraet.shortcuts['cash'], ['Mod+B', 'F2']);
    expect(zweimal.betrieb.doneScreenSeconds, 15);
    expect(zweimal.geraet.terminalPort, 20009);
  });

  test('QR-Modus: unbestimmt als Vorgabe, beide Modi lesbar, Unsinn faellt zurueck', () {
    // Welchen QR-Befehl ein Thermodrucker versteht, entscheidet das Modell an
    // dieser einen Kasse. Die Vorgabe ist auto und nicht einer der beiden
    // Modi: sonst haette jedes Geraet, das nie durch den Wizard laeuft,
    // ploetzlich anders gedruckt als bisher.
    expect(const KasseSettings.standard().geraet.qrMode, KasseQrModus.auto,
        reason: 'ohne Entscheidung bleibt jede Kasse bei ihrer bisherigen Praxis');
    expect(KasseSettings.aus({'device': {'qrMode': 'escpos'}}).geraet.qrMode, KasseQrModus.escpos);
    expect(KasseSettings.aus({'device': {'qrMode': 'raster'}}).geraet.qrMode, KasseQrModus.raster);
    expect(KasseSettings.aus({'device': {'qrMode': 'telepathie'}}).geraet.qrMode, KasseQrModus.auto);
  });

  test('der eingestellte QR-Modus wird zum Druckbefehl, der Bon entsteht nicht im Raten', () {
    expect(KasseQrModus.raster.druckmodusOder(QrPrintMode.native), QrPrintMode.imageRaster);
    expect(KasseQrModus.escpos.druckmodusOder(QrPrintMode.imageRaster), QrPrintMode.native);
  });

  test('unbestimmt heisst: die Vorgabe des Aufrufers gilt, jede Kasse bleibt bei ihrer Praxis', () {
    expect(KasseQrModus.auto.druckmodusOder(QrPrintMode.imageRaster), QrPrintMode.imageRaster);
    expect(KasseQrModus.auto.druckmodusOder(QrPrintMode.native), QrPrintMode.native);
  });

  test('Karte gibt es nur mit eingerichtetem Anbieter', () {
    expect(const KasseSettings.standard().betrieb.kartenAktiv, isFalse);
    expect(KasseSettings.aus({'business': {'payCard': true}}).betrieb.kartenAktiv, isFalse,
        reason: 'ohne Anbieter nützt der Schalter nichts');
    expect(KasseSettings.aus({'business': {'payCard': true, 'cardProvider': 'external'}}).betrieb.kartenAktiv, isTrue);
    expect(KasseSettings.aus({'business': {'payCard': false, 'cardProvider': 'hobex'}}).betrieb.kartenAktiv, isFalse);
  });

  test('eingeschaltete Steuersätze in fester Reihenfolge, der Bildschirm rät die Ordnung nicht', () {
    expect(const KasseSettings.standard().betrieb.aktiveSaetze, [20.0, 13.0, 10.0, 4.9, 0.0]);
    final e = KasseSettings.aus({'business': {'vatRates': {'19': true, '10': false}}});
    expect(e.betrieb.aktiveSaetze, [20.0, 19.0, 13.0, 4.9, 0.0]);
  });

  test('Standard: Kassieren im Panel (npm 0.31: checkoutMode panel)', () {
    expect(const KasseSettings.standard().betrieb.checkoutMode, KasseKassierenModus.panel);
  });

  group('posSettingsChanges', () {
    test('nur geänderte Felder; vatRates ganz, tipSteps je Eintrag', () {
      const vorher = KasseSettingsBetrieb();
      final nachher = vorher.mit({'clock': false, 'vatRates': {'19': true}, 'tipSteps': {'15': true}});
      expect(posSettingsChanges(vorher.toJson(), nachher.toJson()), {
        'clock': false,
        'vatRates': {'20': true, '19': true, '13': true, '10': true, '4.9': true, '0': true},
        'tipSteps': {'15': true},
      });
    });

    test('shortcuts geht bei jeder Änderung ganz hinaus, aber nur mit bekannten Aktionen', () {
      final vorher = KasseSettings.aus({'device': {'shortcuts': {'teleport': ['F9']}}}).geraet;
      final nachher = vorher.mit({'shortcuts': {'splitPayment': ['F4']}});
      final aenderung = posSettingsChanges(vorher.toJson(), nachher.toJson());
      expect(aenderung.keys, ['shortcuts']);
      final karte = aenderung['shortcuts'] as Map;
      expect(karte.keys.toSet(), kasseTastenAktionen.toSet());
      expect(karte['splitPayment'], ['F4']);
      expect(karte['cash'], ['Mod+B']);
    });

    test('keine Änderung, keine Nutzlast', () {
      const g = KasseSettingsGeraet();
      expect(posSettingsChanges(g.toJson(), g.toJson()), isEmpty);
    });
  });

  group('Tasten: Doppelbelegung', () {
    test('die Vorgabe ist frei von Konflikten (Paare dürfen teilen)', () {
      expect(posShortcutConflict(kasseTastenStandard), isNull);
    });

    test('eine fremde Doppelbelegung wird gefunden', () {
      final k = posShortcutConflict({...kasseTastenStandard, 'card': ['Mod+B']});
      expect(k, isNotNull);
      expect(k!.key, 'Mod+B');
      expect({k.action, k.heldBy}, {'cash', 'card'});
    });
  });

  group('mit()', () {
    test('mischt eine Änderung in den Stand', () {
      // Gebraucht, wo eine Einstellung sofort gelten soll, während der Server
      // noch antwortet.
      const stand = KasseSettingsBetrieb();
      final neu = stand.mit({'clock': false});
      expect(neu.clock, isFalse);
      expect(neu.payCash, stand.payCash, reason: 'alles Übrige bleibt');
    });

    test('lässt den Ausgangsstand unberührt', () {
      // Sonst gäbe es nichts, worauf man zurückspringen könnte.
      const stand = KasseSettingsBetrieb();
      stand.mit({'clock': false});
      expect(stand.clock, isTrue);
    });

    test('auch am Gerät, Tasten je Aktion', () {
      const g = KasseSettingsGeraet();
      final neu = g.mit({'touch': true, 'shortcuts': {'cash': ['F2']}});
      expect(neu.touch, isTrue);
      expect(neu.shortcuts['cash'], ['F2']);
      expect(neu.shortcuts['card'], ['Mod+K'], reason: 'die übrigen Tasten bleiben');
      expect(g.touch, isFalse);
    });
  });
}
