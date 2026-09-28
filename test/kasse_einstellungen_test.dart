import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
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
    final ist = const PosSettings.standard().toJson();

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
    final ist = const PosSettings.standard().toJson();
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
    final e = PosSettings.fromJson({
      'business': {'theme': 'night', 'payCard': true, 'cardProvider': 'hobex', 'quatsch': 1},
      'device': {'layout': 'left', 'printerEnabled': true, 'printerType': 'network', 'printerIp': '192.168.0.136'},
    });

    expect(e.business.theme, PosTheme.night);
    expect(e.business.payCard, isTrue);
    expect(e.business.cardProvider, PosCardProvider.hobex);
    expect(e.business.payCash, isTrue, reason: 'nicht Genanntes bleibt beim Standard');
    expect(e.device.layout, PosLayout.left);
    expect(e.device.printerType, PosPrinterType.network);
    expect(e.device.printerIp, '192.168.0.136');
    expect(e.toJson()['business'], isNot(contains('quatsch')));
  });

  test('Landkarten werden je Schlüssel gemischt, neue Steuersätze kommen beim Altbestand an', () {
    final e = PosSettings.fromJson({
      'business': {
        // Ein Altbestand kennt 4,9 % noch nicht und hat 19 % eingeschaltet.
        'vatRates': {'19': true, '20': false},
      },
    });
    expect(e.business.vatRates['4.9'], isTrue, reason: 'neuer Satz kommt aus dem Standard');
    expect(e.business.vatRates['19'], isTrue, reason: 'eigener Wert gewinnt');
    expect(e.business.vatRates['20'], isFalse);
  });

  group('unbekannte Werte des Servers', () {
    test('die Kasse arbeitet mit dem Standard, der Wert bleibt wörtlich erhalten', () {
      final e = PosSettings.fromJson({
        'business': {'theme': 'sepia', 'fontSize': 'XXL', 'receiptOutput': 'pigeon', 'autoLogoutMinutes': 7},
        'device': {'printerType': 'star', 'paperSize': 'a4', 'printerPort': -1},
      });
      expect(e.business.theme, PosTheme.clear);
      expect(e.business.fontSize, PosFontSize.m);
      expect(e.business.receiptOutput, PosReceiptOutput.ask);
      expect(e.business.autoLogoutMinutes, 0);
      expect(e.device.printerType, PosPrinterType.sdp);
      expect(e.device.paperSize, PosPaperSize.mm80);
      expect(e.device.printerPort, 9100, reason: 'ausserhalb des Bereichs arbeitet die Kasse mit dem Standard');

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
      final vorher = PosSettings.fromJson({'business': {'theme': 'sepia'}}).business;
      final nachher = vorher.merge({'fontSize': 'L'});
      expect(nachher.toJson()['theme'], 'sepia', reason: 'mit() behält den fremden Wert');
      expect(posSettingsChanges(vorher.toJson(), nachher.toJson()), {'fontSize': 'L'});
    });

    test('eine unbekannte Tasten-Aktion bleibt stehen und wird genannt', () {
      final e = PosSettings.fromJson({
        'device': {'shortcuts': {'teleport': ['Mod+T']}},
      });
      expect(e.device.shortcuts['teleport'], ['Mod+T']);
      expect(unknownPosSettingValues(e), ['device.shortcuts.teleport']);
    });

    test('Zahlen ausserhalb des Bereichs und abweichende Chips werden genannt, nie still ersetzt', () {
      // Ein neueres Backend erlaubt vielleicht extraColumns 6: die Kasse zeigt
      // dann nicht 0 als eingestellt, und ein Schreiben anderer Felder
      // ueberschreibt die 6 nicht.
      final e = PosSettings.fromJson({
        'business': {'watermarkX': 150, 'tipChips': [1, 2, 3, 4, 5, 6], 'discountChips': [5, 5]},
        'device': {'extraColumns': 6, 'terminalPort': 70000},
      });
      expect(e.business.watermarkX, 50);
      expect(e.business.tipChips, [1, 2, 3, 4, 5]);
      expect(e.device.extraColumns, 0);
      expect(unknownPosSettingValues(e), unorderedEquals([
        'business.watermarkX', 'business.tipChips', 'business.discountChips',
        'device.extraColumns', 'device.terminalPort',
      ]));
      expect(e.toJson()['device']['extraColumns'], 6);
      expect(e.toJson()['business']['tipChips'], [1, 2, 3, 4, 5, 6]);
      final nachher = e.device.merge({'touch': true});
      expect(posSettingsChanges(e.device.toJson(), nachher.toJson()), {'touch': true});
      expect(unknownPosSettingValues(const PosSettings.standard()), isEmpty);
    });

    test('ein bekannter Wert ersetzt den fremden', () {
      final e = PosSettings.fromJson({'business': {'theme': 'sepia'}}).business.merge({'theme': 'night'});
      expect(e.theme, PosTheme.night);
      expect(e.unknownValues, isEmpty);
    });
  });

  test('Werte der inneren Form 0.x fallen auf den Standard, nie ins Modell', () {
    // layout und terminalVia heissen innen und aussen gleich: ein
    // zwischengespeicherter Mischstand trüge sonst 'rechts' ins Modell.
    final e = PosSettings.fromJson({
      'business': {'theme': 'nacht', 'cardProvider': 'keiner'},
      'device': {
        'layout': 'rechts',
        'terminalVia': 'direkt',
        'shortcuts': {'kassieren': ['F9'], 'cash': ['F2']},
      },
    });
    expect(e.business.theme, PosTheme.clear);
    expect(e.business.cardProvider, PosCardProvider.none);
    expect(e.device.layout, PosLayout.right);
    expect(e.device.terminalVia, PosTerminalVia.direct);
    expect(e.device.shortcuts.containsKey('kassieren'), isFalse);
    expect(e.device.shortcuts['cash'], ['F2']);
    expect(unknownPosSettingValues(e), isEmpty, reason: 'ein deutscher Wert ist kein fremder Wert');
  });

  group('Zwischenspeicher der Version 9.x (innere Form)', () {
    test('die Standardwerte der inneren Form ergeben die Standardwerte des Drahts', () {
      // stored/pos-settings-defaults.json ist die deutsche Form, die toJson bis
      // 9.x schrieb und die Flutter-Kasse zwischenspeichert.
      final stored = jsonDecode(File('test/fixtures/vertrag/stored/pos-settings-defaults.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(PosSettings.fromJson(stored).toJson(), golden());
    });

    test('ein eingestellter 9.x-Stand bleibt nach dem Update erhalten', () {
      final e = PosSettings.fromJson({
        'betrieb': {
          'stil': 'nacht', 'zahlKarte': true, 'kartenanbieter': 'extern', 'kassierenModus': 'seite',
          'belegAusgabe': 'druck', 'saetze': {'19': true}, 'tgChips': [7.5], 'zahlGetrennt': true,
        },
        'geraet': {
          'layout': 'links', 'druckerArt': 'bt', 'druckerBt': 'AA:BB', 'ladeAuto': 'immer',
          'tasten': {'bar': ['F2'], 'getrennt': ['F4']}, 'qrModus': 'escpos', 'terminalArt': 'hps',
        },
      });
      expect(e.business.theme, PosTheme.night);
      expect(e.business.payCard, isTrue);
      expect(e.business.cardProvider, PosCardProvider.external);
      expect(e.business.checkoutMode, PosCheckoutMode.page);
      expect(e.business.receiptOutput, PosReceiptOutput.print);
      expect(e.business.vatRates['19'], isTrue);
      expect(e.business.tipChips, [7.5]);
      expect(e.business.paySplit, isTrue);
      expect(e.device.layout, PosLayout.left);
      expect(e.device.printerType, PosPrinterType.bluetooth);
      expect(e.device.printerBluetoothId, 'AA:BB');
      expect(e.device.drawerAutoOpen, PosDrawerAutoOpen.always);
      expect(e.device.shortcuts['cash'], ['F2']);
      expect(e.device.shortcuts['splitPayment'], ['F4']);
      expect(e.device.qrMode, PosQrMode.escpos);
      expect(e.device.terminalType, PosTerminalType.hps);
      expect(unknownPosSettingValues(e), isEmpty);
    });

    test('der 9.x-Tastenstandard ergibt keine Doppelbelegung (entwirrt wie der Server)', () {
      // So schrieb 9.x toJson die Tasten eines Geraets ohne eigene Belegung.
      const tasten9x = {
        'kassieren': ['Enter'], 'abschliessen': ['Enter'], 'abbrechen': ['Escape'], 'frei': ['Mod+F'],
        'bar': ['Mod+B'], 'karte': ['Mod+K'], 'passend': ['Mod+P'], 'belege': ['Mod+E'],
        'letzteZurueck': ['Mod+Backspace'],
      };
      final e = PosSettings.fromJson({'geraet': {'tasten': tasten9x}});
      final karte = e.device.shortcuts;
      expect(posShortcutConflict(karte), isNull);
      expect(karte['customAmount'], ['Mod+F'], reason: 'die gespeicherte Wahl gewinnt');
      expect(karte['fullscreen'], isEmpty, reason: 'die beanspruchte Vorgabe-Taste faellt');
      expect(karte['receipts'], ['Mod+E']);
      expect(karte['settings'], ['Mod+S'], reason: 'nicht beanspruchte Vorgaben bleiben');
      // Die Taste ist damit am Geraet frei vergebbar, ohne Abweisung.
      final neu = e.device.merge({'shortcuts': {'splitPayment': ['F4']}});
      expect(posShortcutConflict(neu.shortcuts), isNull);
    });

    test('entwirreTasten: Paare duerfen teilen, fremde Aktionen verlieren die Taste', () {
      const gespeichert = {'clearTendered': ['Mod+C'], 'cash': ['Mod+K']};
      final raus = untangleShortcuts({...posShortcutDefaults, ...gespeichert}, gespeichert);
      expect(raus['clearCart'], ['Mod+C'], reason: 'clearTendered und clearCart duerfen teilen');
      expect(raus['card'], isEmpty, reason: 'Mod+K gehoert jetzt cash');
      expect(raus['cash'], ['Mod+K']);
    });

    test('dokumentiert: die uebrigen 9.x-Standardwerte gelten bis zur ersten Serverantwort', () {
      // Der 9.x-Stand ist der gemischte Stand samt der damaligen Vorgaben.
      // terminalPort 20008 und kassierenModus seite bleiben darum bis zur
      // ersten Antwort von getKasseSettings bzw. der Benutzerliste stehen
      // (Entscheidung Koordinator, Runde 1: nur Tasten werden entwirrt).
      final e = PosSettings.fromJson({
        'betrieb': {'kassierenModus': 'seite'},
        'geraet': {'terminalPort': 20008},
      });
      expect(e.business.checkoutMode, PosCheckoutMode.page);
      expect(e.device.terminalPort, 20008);
    });

    test('die Übersetzungstabellen sind renames-1.0.json', () {
      final r = jsonDecode(File('test/fixtures/vertrag/renames-1.0.json').readAsStringSync()) as Map<String, dynamic>;
      final struktur = r['structure']['pos-settings-defaults.json'] as Map<String, dynamic>;
      expect(legacyBusinessKeys, struktur['business']);
      expect(legacyDeviceKeys, struktur['device']);
      expect(legacyShortcutActions, struktur['shortcuts']);
      final werte = r['values']['pos-settings-defaults.json'] as Map<String, dynamic>;
      final soll = <String, Map<String, String>>{
        for (final e in werte.entries)
          (e.key.split('.').last): {
            for (final w in (e.value as Map<String, dynamic>).entries)
              if (w.key != w.value) w.key: w.value as String,
          },
      }..removeWhere((_, v) => v.isEmpty);
      expect(legacyValues, soll);
    });
  });

  test('was hereinkam, kommt wieder heraus, hin und zurück ohne Verlust', () {
    final roh = {
      'business': {'color': '#AABBCC', 'tipChips': [7.5, 12.0], 'vatRates': {'20': false}, 'doneScreenSeconds': 15},
      'device': {'shortcuts': {'cash': ['Mod+B', 'F2']}, 'extraColumns': 2, 'terminalPort': 20009},
    };
    final einmal = PosSettings.fromJson(roh);
    final zweimal = PosSettings.fromJson(einmal.toJson());
    expect(zweimal.toJson(), einmal.toJson());
    expect(zweimal.business.tipChips, [7.5, 12.0]);
    expect(zweimal.device.shortcuts['cash'], ['Mod+B', 'F2']);
    expect(zweimal.business.doneScreenSeconds, 15);
    expect(zweimal.device.terminalPort, 20009);
  });

  test('QR-Modus: unbestimmt als Vorgabe, beide Modi lesbar, Unsinn faellt zurueck', () {
    // Welchen QR-Befehl ein Thermodrucker versteht, entscheidet das Modell an
    // dieser einen Kasse. Die Vorgabe ist auto und nicht einer der beiden
    // Modi: sonst haette jedes Geraet, das nie durch den Wizard laeuft,
    // ploetzlich anders gedruckt als bisher.
    expect(const PosSettings.standard().device.qrMode, PosQrMode.auto,
        reason: 'ohne Entscheidung bleibt jede Kasse bei ihrer bisherigen Praxis');
    expect(PosSettings.fromJson({'device': {'qrMode': 'escpos'}}).device.qrMode, PosQrMode.escpos);
    expect(PosSettings.fromJson({'device': {'qrMode': 'raster'}}).device.qrMode, PosQrMode.raster);
    expect(PosSettings.fromJson({'device': {'qrMode': 'telepathie'}}).device.qrMode, PosQrMode.auto);
  });

  test('der eingestellte QR-Modus wird zum Druckbefehl, der Bon entsteht nicht im Raten', () {
    expect(PosQrMode.raster.printModeOr(QrPrintMode.native), QrPrintMode.imageRaster);
    expect(PosQrMode.escpos.printModeOr(QrPrintMode.imageRaster), QrPrintMode.native);
  });

  test('unbestimmt heisst: die Vorgabe des Aufrufers gilt, jede Kasse bleibt bei ihrer Praxis', () {
    expect(PosQrMode.auto.printModeOr(QrPrintMode.imageRaster), QrPrintMode.imageRaster);
    expect(PosQrMode.auto.printModeOr(QrPrintMode.native), QrPrintMode.native);
  });

  test('Karte gibt es nur mit eingerichtetem Anbieter', () {
    expect(const PosSettings.standard().business.cardPaymentEnabled, isFalse);
    expect(PosSettings.fromJson({'business': {'payCard': true}}).business.cardPaymentEnabled, isFalse,
        reason: 'ohne Anbieter nützt der Schalter nichts');
    expect(PosSettings.fromJson({'business': {'payCard': true, 'cardProvider': 'external'}}).business.cardPaymentEnabled, isTrue);
    expect(PosSettings.fromJson({'business': {'payCard': false, 'cardProvider': 'hobex'}}).business.cardPaymentEnabled, isFalse);
  });

  test('eingeschaltete Steuersätze in fester Reihenfolge, der Bildschirm rät die Ordnung nicht', () {
    expect(const PosSettings.standard().business.activeVatRates, [20.0, 13.0, 10.0, 4.9, 0.0]);
    final e = PosSettings.fromJson({'business': {'vatRates': {'19': true, '10': false}}});
    expect(e.business.activeVatRates, [20.0, 19.0, 13.0, 4.9, 0.0]);
  });

  test('Standard: Kassieren im Panel (npm 0.31: checkoutMode panel)', () {
    expect(const PosSettings.standard().business.checkoutMode, PosCheckoutMode.panel);
  });

  group('posSettingsChanges', () {
    test('nur geänderte Felder; vatRates ganz, tipSteps je Eintrag', () {
      const vorher = PosBusinessSettings();
      final nachher = vorher.merge({'clock': false, 'vatRates': {'19': true}, 'tipSteps': {'15': true}});
      expect(posSettingsChanges(vorher.toJson(), nachher.toJson()), {
        'clock': false,
        'vatRates': {'20': true, '19': true, '13': true, '10': true, '4.9': true, '0': true},
        'tipSteps': {'15': true},
      });
    });

    test('shortcuts geht bei jeder Änderung ganz hinaus, aber nur mit bekannten Aktionen', () {
      final vorher = PosSettings.fromJson({'device': {'shortcuts': {'teleport': ['F9']}}}).device;
      final nachher = vorher.merge({'shortcuts': {'splitPayment': ['F4']}});
      final aenderung = posSettingsChanges(vorher.toJson(), nachher.toJson());
      expect(aenderung.keys, ['shortcuts']);
      final karte = aenderung['shortcuts'] as Map;
      expect(karte.keys.toSet(), posShortcutActions.toSet());
      expect(karte['splitPayment'], ['F4']);
      expect(karte['cash'], ['Mod+B']);
    });

    test('keine Änderung, keine Nutzlast', () {
      const g = PosDeviceSettings();
      expect(posSettingsChanges(g.toJson(), g.toJson()), isEmpty);
    });
  });

  group('Tasten: Doppelbelegung', () {
    test('die Vorgabe ist frei von Konflikten (Paare dürfen teilen)', () {
      expect(posShortcutConflict(posShortcutDefaults), isNull);
    });

    test('eine fremde Doppelbelegung wird gefunden', () {
      final k = posShortcutConflict({...posShortcutDefaults, 'card': ['Mod+B']});
      expect(k, isNotNull);
      expect(k!.key, 'Mod+B');
      expect({k.action, k.heldBy}, {'cash', 'card'});
    });
  });

  group('mit()', () {
    test('mischt eine Änderung in den Stand', () {
      // Gebraucht, wo eine Einstellung sofort gelten soll, während der Server
      // noch antwortet.
      const stand = PosBusinessSettings();
      final neu = stand.merge({'clock': false});
      expect(neu.clock, isFalse);
      expect(neu.payCash, stand.payCash, reason: 'alles Übrige bleibt');
    });

    test('lässt den Ausgangsstand unberührt', () {
      // Sonst gäbe es nichts, worauf man zurückspringen könnte.
      const stand = PosBusinessSettings();
      stand.merge({'clock': false});
      expect(stand.clock, isTrue);
    });

    test('auch am Gerät, Tasten je Aktion', () {
      const g = PosDeviceSettings();
      final neu = g.merge({'touch': true, 'shortcuts': {'cash': ['F2']}});
      expect(neu.touch, isTrue);
      expect(neu.shortcuts['cash'], ['F2']);
      expect(neu.shortcuts['card'], ['Mod+K'], reason: 'die übrigen Tasten bleiben');
      expect(g.touch, isFalse);
    });
  });
}
