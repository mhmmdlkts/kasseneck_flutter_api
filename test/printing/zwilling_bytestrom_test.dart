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
/// Die vier Digests sind mit dieser Fassung einmal neu gezogen worden: seither
/// traegt der Vorspann den Druckbereich des Blatts (`GS L` / `GS W`, acht
/// Bytes) -- ohne ihn mittelte der Drucker Bilder in SEINER Flaeche.
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
        '42a673115d099035009a72aa171d0785f1ec697bd9042a669720e3b416d6d749');
  });

  test('80 mm ohne Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: false),
        '76d9c93b23f062ffa53ff1a0cba53a2b2f0db3dd9bd36ad6cced638c20e547d8');
  });

  test('58 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm58, marke: true),
        '98e98cfdbd54741634a6b2189970c72ea01594c97f193ca8f69c6df4b5013a34');
  });

  test('80 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: true),
        '31fee883750041872ce63d07e5f4ba819be78892f6569611b4bdc98f66913fe6');
  });
}
