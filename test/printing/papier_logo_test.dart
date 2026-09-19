import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/druck_logo.dart';
import 'package:kasseneck_api/services/printer_service.dart';

import '../helpers/test_receipts.dart';

/// Vollflaechig schwarzes RGBA-Bild -- wie in `druck_logo_test.dart`.
({int breite, int hoehe, Uint8List rgba}) schwarz(int b, int h) {
  final rgba = Uint8List(b * h * 4);
  for (var i = 3; i < rgba.length; i += 4) {
    rgba[i] = 255;
  }
  return (breite: b, hoehe: h, rgba: rgba);
}

/// Ein Beleg, wie das Backend ihn seit dem Beleg-Blatt liefert: mit Layout,
/// Logo-Adresse und Stufe (nachgewiesen im Log vom 18.09.2026).
KasseneckReceipt belegMitLogo() => buildReceipt()
  ..layout = const BelegLayout(
      lines: [BelegText(text: 'Danke', align: BelegAlign.center)],
      paperSize: 'mm80',
      regelwerk: 2)
  ..logoUrl = 'https://beispiel.test/logo.png'
  ..logoStufe = LogoStufe.m;

KasseneckReceipt belegOhneLogo() => belegMitLogo()..logoUrl = null;

void main() {
  setUp(druckLogoSpeicherLeeren);
  tearDown(() => KeckPrinterService.logoLader = ladeDruckLogo);

  test('das hinterlegte Logo kommt aufs Papier, ohne dass es jemand uebergibt', () async {
    String? gefragteAdresse;
    KeckPrinterService.logoLader = (url, stufe, papier) {
      gefragteAdresse = url;
      return ladeDruckLogo(url, stufe, papier, pixel: (_) async => schwarz(400, 100));
    };

    final papier = await KeckPrinterService.getPaperFromReceipt(
        belegMitLogo(), KeckPaperSize.mm80);

    expect(gefragteAdresse, 'https://beispiel.test/logo.png');
    // Ein Rasterbild geht als `GS v 0` hinaus; ohne Logo steht der Befehl nicht im Strom.
    final bytes = <int>[for (final t in papier.bytes) ...t];
    expect(bytes, containsAllInOrder([0x1D, 0x76, 0x30]),
        reason: 'der Bildbefehl fehlt -- das Logo wurde nicht gesetzt');
  });

  test('ohne Logo-Adresse wird nichts geholt', () async {
    var gerufen = 0;
    KeckPrinterService.logoLader = (url, stufe, papier) async {
      gerufen += 1;
      return null;
    };

    await KeckPrinterService.getPaperFromReceipt(belegOhneLogo(), KeckPaperSize.mm80);

    expect(gerufen, 0, reason: 'ohne Adresse gibt es nichts zu holen');
  });

  test('ein Ladefehler laesst den Beleg trotzdem hinausgehen', () async {
    KeckPrinterService.logoLader = (url, stufe, papier) async => throw Exception('Netz weg');

    final papier = await KeckPrinterService.getPaperFromReceipt(
        belegMitLogo(), KeckPaperSize.mm80);

    expect(papier.bytes, isNotEmpty, reason: 'das Logo ist Zierde, der Beleg ist Pflicht');
  });

  test('traegt der Beleg eine Adresse, springt ein uebergebenes Logo nicht ein', () async {
    // Ein gueltiges Logo unter einer ANDEREN Adresse -- so, wie es ein
    // Aufrufer heute noch ueber den veralteten Parameter mitgeben koennte.
    final uebergebenesLogo = await ladeDruckLogo(
        'https://beispiel.test/anderes-logo.png', LogoStufe.m, KeckPaperSize.mm80,
        pixel: (_) async => schwarz(400, 100));
    expect(uebergebenesLogo, isNotNull, reason: 'Vorbedingung: das uebergebene Logo ist gueltig');

    KeckPrinterService.logoLader = (url, stufe, papier) async => throw Exception('Netz weg');

    final papier = await KeckPrinterService.getPaperFromReceipt(
        belegMitLogo(), KeckPaperSize.mm80,
        logo: uebergebenesLogo);

    final bytes = <int>[for (final t in papier.bytes) ...t];
    expect(bytes, isNot(containsAllInOrder([0x1D, 0x76, 0x30])),
        reason: 'der Beleg traegt eine Adresse -- das uebergebene Logo darf nicht einspringen, '
            'auch wenn ihr eigener Abruf scheitert');
  });
}
