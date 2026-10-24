import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
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
/// Ersatzdaten (23.10.2026, npm 1.14.0): der Golden-Beleg traegt statt
/// `ATU12345678` die pruefziffernrichtige `ATU12345675`; die vier Digests sind
/// darum mit dem npm-Paket neu gezogen (nur die UID-Zeile aendert sich).
///
/// Grundlage ist die gezogene Vertragsdatei `sale-cash.lines.json`, also
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

  final ReceiptLayout layout = ReceiptLayout.fromJson(jsonDecode(
      File('test/fixtures/vertrag/expected/sale-cash.lines.json').readAsStringSync()))!;

  Future<String> digest(KeckPaperSize size, {required bool marke}) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setReceiptSheet(layout, brandMark: marke, qrMode: QrPrintMode.native);
    return sha256.convert(paper.bytes.expand((e) => e).toList()).toString();
  }

  test('58 mm ohne Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm58, marke: false),
        'a805e7a09063c9b8cf781d3dc03d5028a23b785c15a8101f0d589328ac6424fd');
  });

  test('80 mm ohne Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: false),
        'b62ab3a13df22fd6e507c4f685cb634c58933abf912d37188fa345001bacb287');
  });

  test('58 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm58, marke: true),
        'c70419bd79bed9a860f9f506bf72b4954b57050346ab344467f20c27d1edc9c3');
  });

  test('80 mm mit Marke: Byte fuer Byte wie das npm-Paket', () async {
    expect(await digest(KeckPaperSize.mm80, marke: true),
        '0e476d59f8ff4995869b4e084d4632040f313d5dfdc6a6254c457e0396e1cd3d');
  });

  // Bon der Schicht mit fetter Spaltenzeile („Bleibt in der Kassenlade“, Wechselgeld 11.2.0):
  // der einzige Weg, auf dem eine Spaltenzeile fett gedruckt wird. Ohne Marke;
  // dieselben Digests stehen im npm-Paket.
  final ReceiptLayout schichtBon = ReceiptLayout.fromJson(jsonDecode(
      File('test/fixtures/vertrag/expected/shift-close-take-out.lines.json').readAsStringSync()))!;

  Future<String> schichtDigest(KeckPaperSize size) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setReceiptSheet(schichtBon, brandMark: false, qrMode: QrPrintMode.native);
    return sha256.convert(paper.bytes.expand((e) => e).toList()).toString();
  }

  test('Z-Bon mit Entnahme, 58 mm: Byte fuer Byte wie das npm-Paket', () async {
    expect(await schichtDigest(KeckPaperSize.mm58), '289d0ec5dbdd72fdb0a4b93b316b6909a985e625c7c8845dc23f18a7a7baa9ca');
  });

  test('Z-Bon mit Entnahme, 80 mm: Byte fuer Byte wie das npm-Paket', () async {
    expect(await schichtDigest(KeckPaperSize.mm80), 'c0bb40b6c93e0f105d704283f6c997c5bba9878c03f94ea14eebab2d98e1e3ee');
  });
}
