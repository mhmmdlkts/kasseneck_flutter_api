import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

/// Zwilling von `belegBlatt` (npm 0.14.0): fuer jede Golden-Fixture muss das
/// Blatt mit Probe-Logo (M, 300x120) und Marke Block fuer Block der
/// `blatt32.json` bzw. `blatt48.json` des Pakets entsprechen.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, Object?> _alsJson(BlattBlock b) => switch (b) {
      BlattZeile() => {'art': 'zeile', 'text': b.text, 'fett': b.fett, 'leer': b.leer},
      BlattLogoBlock() => {'art': 'logo', 'breiteAnteil': b.breiteAnteil, 'hoeheZeilen': b.hoeheZeilen},
      BlattQr() => {'art': 'qr', 'nutzlast': b.nutzlast, 'breiteAnteil': b.breiteAnteil},
    };

void _gleich(Object? ist, Object? soll, String wo) {
  if (soll is num) {
    expect(ist, isA<num>(), reason: wo);
    expect((ist as num).toDouble(), closeTo(soll.toDouble(), 1e-12), reason: wo);
  } else if (soll is Map) {
    expect((ist as Map).keys.toSet(), soll.keys.toSet(), reason: wo);
    for (final k in soll.keys) {
      _gleich(ist[k], soll[k], '$wo.$k');
    }
  } else if (soll is List) {
    expect((ist as List).length, soll.length, reason: wo);
    for (var i = 0; i < soll.length; i++) {
      _gleich(ist[i], soll[i], '$wo[$i]');
    }
  } else {
    expect(ist, soll, reason: wo);
  }
}

void main() {
  final manifest = jsonDecode(File('${_wurzel.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final namen = (manifest['belege'] as Map<String, dynamic>).keys.toList()..sort();

  test('Golden: Blatt aller Fixtures mit Probe-Logo und Marke (32 und 48 Zeichen)', () {
    expect(namen.length, greaterThanOrEqualTo(31));
    for (final n in namen) {
      final layout = BelegLayout.fromJson(jsonDecode(File('${_wurzel.path}/erwartet/$n.lines.json').readAsStringSync()))!;
      for (final zeichen in [32, 48]) {
        final soll = jsonDecode(File('${_wurzel.path}/erwartet/$n.blatt$zeichen.json').readAsStringSync());
        final blatt = belegBlatt(layout, zeichen: zeichen, logo: const BlattLogo(stufe: LogoStufe.m, pxBreite: 300, pxHoehe: 120), marke: true);
        _gleich({'zeichen': blatt.zeichen, 'bloecke': blatt.bloecke.map(_alsJson).toList()}, soll, '$n@$zeichen');
      }
    }
  });

  test('Rot-Probe: ein Blatt ohne Marke ist nicht das Golden', () {
    final layout = BelegLayout.fromJson(jsonDecode(File('${_wurzel.path}/erwartet/verkauf-bar.lines.json').readAsStringSync()))!;
    final soll = jsonDecode(File('${_wurzel.path}/erwartet/verkauf-bar.blatt48.json').readAsStringSync()) as Map;
    final ohne = belegBlatt(layout, zeichen: 48, logo: const BlattLogo(stufe: LogoStufe.m, pxBreite: 300, pxHoehe: 120));
    expect(ohne.bloecke.length, isNot((soll['bloecke'] as List).length));
  });

  test('logoMass nie hochgerechnet, Stufen wie npm, ausKuerzel faellt auf M', () {
    final klein = logoMass(const BlattLogo(stufe: LogoStufe.xl, pxBreite: 100, pxHoehe: 50), 48);
    expect(klein.breiteAnteil, closeTo(100 / 576, 1e-12));
    expect(klein.hoeheZeilen, closeTo(50 / 24, 1e-12));
    expect(logoRasterMass(klein, 48), (breite: 100, hoehe: 50));
    expect(LogoStufe.values.map((s) => '${s.kuerzel}:${s.breiteAnteil}x${s.hoeheZeilen}').toList(), ['S:0.42x5', 'M:0.62x8', 'L:0.8x12', 'XL:0.94x16']);
    expect(LogoStufe.ausKuerzel('XL'), LogoStufe.xl);
    expect(LogoStufe.ausKuerzel(null), LogoStufe.m);
    expect(() => logoMass(const BlattLogo(stufe: LogoStufe.m, pxBreite: 0, pxHoehe: 1), 48), throwsArgumentError);
  });

  test('qrBlattAnteil wie npm: 109 Byte -> 45 Module, 80 mm auto 6 Punkte (auto heisst in beiden Paketen dasselbe)', () {
    const qr = '_R1-AT1_KASSE1_AT0-KASSE1-42_2026-08-13T00:30:00_5,00_2,70_0,00_0,00_0,00_UMSATZ_VORGAENGER_6F0404F0_SIGNATUR';
    expect(qrModulAnzahlWieNpm(qr), 45);
    expect(qrBlattAnteil(qr, KeckPaperSize.mm80), 53 * 6 / 576);
    expect(qrBlattAnteil(qr, KeckPaperSize.mm80, groesse: QrModulGroesse.klein), 53 * 4 / 576);
    expect(qrBlattAnteil('', KeckPaperSize.mm58), 0);
    expect(papierFuerZeichen(32, 'mm80'), KeckPaperSize.mm58);
    expect(papierFuerZeichen(40, 'mm80'), KeckPaperSize.mm80);
  });

  test('zwei Modulzaehler, eine Zahl: qrModulAnzahlWieNpm == QrMass.modulAnzahl an jeder Versionsgrenze', () {
    // Die Grenzen werden aus der Tabelle des Blatts abgelesen, nicht
    // abgeschrieben: wo die Modulzahl springt, liegt die Kapazitaet. An
    // Kapazitaet und Kapazitaet + 1 (v1..v39) muss die QR-Bibliothek dasselbe
    // sagen -- sonst rechnete das Blatt mit einem anderen Symbol, als Bon und
    // Schirm zeichnen. ASCII-Nutzlast, also Byte-Modus wie beim Beleg-QR.
    String nutzlast(int n) => 'a' * n;
    final kapazitaeten = <int>[
      for (var n = 1; n < 2331; n++)
        if (qrModulAnzahlWieNpm(nutzlast(n + 1)) != qrModulAnzahlWieNpm(nutzlast(n))) n,
      2331,
    ];
    expect(kapazitaeten, hasLength(40));
    expect(kapazitaeten.first, 14);
    for (final (i, kap) in kapazitaeten.indexed) {
      final version = i + 1;
      expect(qrModulAnzahlWieNpm(nutzlast(kap)), 17 + 4 * version, reason: 'v$version, Kapazitaet $kap');
      expect(QrMass.modulAnzahl(nutzlast(kap)), qrModulAnzahlWieNpm(nutzlast(kap)), reason: 'v$version: $kap Byte');
      if (version < 40) {
        expect(QrMass.modulAnzahl(nutzlast(kap + 1)), qrModulAnzahlWieNpm(nutzlast(kap + 1)), reason: 'v$version: ${kap + 1} Byte');
      }
    }
    // Hinter v40 gibt es kein Symbol: das Blatt lehnt ab. `QrMass.modulAnzahl`
    // meldet dort (qr 3.0.2) noch 177 Module statt abzulehnen -- ausserhalb
    // jeder druckbaren Groesse, aber keine gemeinsame Zahl mehr.
    expect(() => qrModulAnzahlWieNpm(nutzlast(2332)), throwsArgumentError);
  });
}
