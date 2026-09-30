import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/printing.dart' show CapabilityProfile, CodeTableId, codeTables;

/// Bons mit gewaehlter Code-Tabelle: jeder Fall aus
/// `code-table-receipts.json` mit jeder Tabelle, Byte fuer Byte wie die
/// Hex-Dateien des npm-Pakets (`expected/code-table-receipt.<fall>.<tabelle>.hex`).
/// Druckoptionen wie dort: QR nativ, voller Schnitt, kein Logo, keine Marke.
///
/// Der Fall `special-characters` steht im Vertrag nur als Eingabe (Firma,
/// Beleg); das Layout baut das npm-Paket (`fromReceiptPayload` +
/// `buildReceiptLayout`), dieses Paket hat keinen Layout-Bauer.
/// `test/fixtures/zeichensatz/special-characters.lines.json` ist dieses Layout,
/// erzeugt mit `tool/zeichensatz_layout.sh` aus dem angehefteten npm-Paket;
/// die Herkunft (Version, shasum des Tarballs, sha256) steht daneben in
/// `special-characters.source.json`. Echt ist es, weil es hier fuer alle
/// sechs Tabellen die Hex-Dateien trifft.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vertrag = 'test/fixtures/vertrag';
  final bons = jsonDecode(File('$vertrag/code-table-receipts.json').readAsStringSync()) as Map<String, dynamic>;
  final tabellen = (bons['tables'] as List).cast<String>();
  final faelle = (bons['cases'] as List).cast<Map<String, dynamic>>();

  ReceiptLayout layoutAus(String pfad) => ReceiptLayout.fromJson(jsonDecode(File(pfad).readAsStringSync()))!;

  ReceiptLayout bonLayout(Map<String, dynamic> fall) => fall['receipt'] != null
      ? layoutAus('$vertrag/expected/${fall['receipt']}.lines.json')
      : layoutAus('test/fixtures/zeichensatz/${fall['name']}.lines.json');

  Future<List<int>> bytes(ReceiptLayout layout, {CodeTableId? codeTable}) async {
    final paper = PrintPaper(
      paperSize: layout.paperSize == 'mm58' ? KeckPaperSize.mm58 : KeckPaperSize.mm80,
      profile: CapabilityProfile(),
      codeTable: codeTable,
    );
    await paper.setReceiptSheet(layout, qrMode: QrPrintMode.native);
    return paper.bytes.expand((e) => e).toList();
  }

  String hexZeilen(List<int> bytes) {
    final teile = <String>[];
    for (var i = 0; i < bytes.length; i += 32) {
      teile.add(bytes.sublist(i, i + 32 > bytes.length ? bytes.length : i + 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    }
    return '${teile.join('\n')}\n';
  }

  test('abgeleitetes Layout: Hash wie aufgezeichnet, aus der angehefteten npm-Version', () {
    final herkunft = jsonDecode(File('test/fixtures/zeichensatz/special-characters.source.json').readAsStringSync()) as Map<String, dynamic>;
    final datei = File('test/fixtures/zeichensatz/special-characters.lines.json').readAsBytesSync();
    expect(sha256.convert(datei).toString(), herkunft['sha256'],
        reason: 'von Hand geaendert? Neu erzeugen mit tool/zeichensatz_layout.sh');
    final angeheftet = RegExp(r'^npm_version:\s*"?([^"\s]+)', multiLine: true).firstMatch(File('zwillinge.yaml').readAsStringSync())![1];
    expect(herkunft['npmVersion'], angeheftet, reason: 'npm_version geaendert: tool/zeichensatz_layout.sh erneut laufen lassen');
    expect(herkunft['tarballShasum'], matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('Prueffall: alle sechs Tabellen, jede Hex-Datei gehoert zu einem Fall', () {
    expect(tabellen, codeTables.map((t) => t.id.name).toList());
    final namen = faelle.map((f) => f['name']).toList();
    for (final pflicht in ['sale-cash', 'test-cashregister-sale', 'special-characters']) {
      expect(namen, contains(pflicht));
    }
    final dateien = Directory('$vertrag/expected')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((d) => d.startsWith('code-table-receipt.'))
        .toList()
      ..sort();
    final soll = [for (final f in faelle) for (final t in tabellen) 'code-table-receipt.${f['name']}.$t.hex']..sort();
    expect(dateien, soll);
  });

  for (final fall in faelle) {
    test('${fall['name']}: Bytes je Tabelle wie die Hex-Datei des npm-Pakets', () async {
      final layout = bonLayout(fall);
      for (final t in tabellen) {
        final soll = File('$vertrag/expected/code-table-receipt.${fall['name']}.$t.hex').readAsStringSync();
        expect(hexZeilen(await bytes(layout, codeTable: CodeTableId.values.byName(t))), soll, reason: '${fall['name']}.$t');
      }
    });
  }

  test('special-characters: echte Bytes, wo die Tabelle das Zeichen hat, sonst Ersatz', () async {
    final layout = layoutAus('test/fixtures/zeichensatz/special-characters.lines.json');
    Future<bool> hat(CodeTableId t, List<int> folge) async {
      final b = await bytes(layout, codeTable: t);
      outer:
      for (var i = 0; i <= b.length - folge.length; i++) {
        for (var j = 0; j < folge.length; j++) {
          if (b[i + j] != folge[j]) continue outer;
        }
        return true;
      }
      return false;
    }

    expect(await hat(CodeTableId.wpc1252, [...'19,90 '.codeUnits, 0x80]), isTrue);
    expect(await hat(CodeTableId.pc858, [...'19,90 '.codeUnits, 0xd5]), isTrue);
    expect(await hat(CodeTableId.pc858, [...'Pfand '.codeUnits, 0xf5]), isTrue);
    expect(await hat(CodeTableId.iso8859_15, [...'19,90 '.codeUnits, 0xa4]), isTrue);
    expect(await hat(CodeTableId.pc850, '19,90 EUR'.codeUnits), isTrue);
    expect(await hat(CodeTableId.pc437, 'Pfand Par. 3'.codeUnits), isTrue);
    expect(await hat(CodeTableId.replacement, 'Kuerbis Groesse XL'.codeUnits), isTrue);
    expect(await hat(CodeTableId.replacement, 'Tee 80Grad'.codeUnits), isTrue);
  });

  test('ohne Wahl: byte-gleich zum Bytestrom-Zwilling (Tabelle 16, EUR statt €)', () async {
    final layout = layoutAus('$vertrag/expected/sale-cash.lines.json');
    // Derselbe Digest wie in test/printing/zwilling_bytestrom_test.dart (80 mm ohne Marke).
    expect(sha256.convert(await bytes(layout)).toString(), '76d9c93b23f062ffa53ff1a0cba53a2b2f0db3dd9bd36ad6cced638c20e547d8');
  });
}
