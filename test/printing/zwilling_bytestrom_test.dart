import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

/// **Der Zwilling am Bytestrom.** Die bindende Zusage der beiden Pakete lautet:
/// derselbe Beleg, derselbe Bytestrom -- egal ob ihn das npm- oder das
/// Dart-Paket setzt. Geprueft wurde das bisher nur von Hand, mit einem Skript
/// neben dem Repo; damit war die Gleichheit eine Behauptung, die jede spaetere
/// Aenderung still brechen konnte. `tool/zwillinge.sh pruefen` deckt die
/// Vertragsdateien ab, nicht den Strom, und die gemeinsamen Pruef-Faelle
/// vergleichen Raster, Zeilen und Blatt -- alles Stufen VOR den Bytes.
///
/// Darum stehen die vier Digests unten **wortgleich** im npm-Paket
/// (`test/qr-bestandsschutz.test.ts` fuer die beiden ohne Marke,
/// `test/zwilling-bytestrom.test.ts` fuer alle vier). Wer in einem der beiden
/// Pakete am Druckweg dreht, macht dort oder hier rot -- und die CI beider
/// Repos faehrt diese Datei.
///
/// Grundlage ist die gezogene Vertragsdatei `verkauf-bar.lines.json`, also
/// buchstaeblich dasselbe Layout auf beiden Seiten. Der QR laeuft im nativen
/// Modus, weil nur der ohne gerastertes Bild auskommt und damit in beiden
/// Paketen aus derselben Quelle entsteht (das gerasterte Symbol baut jede Seite
/// mit ihrer eigenen QR-Bibliothek -- dort ist Byte-Gleichheit weder zugesagt
/// noch moeglich).
///
/// Die Marke ist bewusst mit dabei: ihr Raster entsteht beim Bauen im
/// npm-Paket und reist als Vertragsdatei ins Dart-Paket. Die Kette hat zwei
/// Glieder, und jedes hat seine eigene Pruefung -- hier steht das zweite:
/// `test/marke_test.dart` haelt Vertragsdatei gegen `lib/models/marke_daten.dart`
/// (verbiegt man `marke.json` um ein Bit, wird DORT rot, hier nicht -- selbst
/// nachgestellt), und dieser Digest haelt das Raster, das der Druckweg
/// wirklich benutzt, gegen das npm-Paket. Belegt: ein einzelnes gekipptes Bit
/// in `marke_daten.dart` macht genau den betroffenen Fall (80 mm mit Marke)
/// rot, die anderen drei bleiben gruen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final BelegLayout layout = BelegLayout.fromJson(jsonDecode(
      File('test/fixtures/vertrag/erwartet/verkauf-bar.lines.json').readAsStringSync()))!;

  Future<String> digest(KeckPaperSize size, {required bool marke}) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setBelegBlatt(layout, marke: marke, qrMode: QrPrintMode.native);
    return sha256.convert(paper.bytes.expand((e) => e).toList()).toString();
  }

  test('58 mm ohne Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm58, marke: false),
        '7589f2fa8b9de73efddf4095add15b6d54b7e8638f02532c0498701e5df28a1d');
  });

  test('80 mm ohne Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: false),
        'fb1520fb7705c9ef486c3aa2ff302bbedb79832ed9665de9afc668939beef2a8');
  });

  test('58 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm58, marke: true),
        'b85ee5c1e9f69ce0e566596d06b4415115b2b13ac756fb87fae3b072be81e858');
  });

  test('80 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: true),
        '77f594a7205004164233ced3cd3da8263d3325634d25610253b23c9c9d12aed7');
  });
}
