import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/printing.dart';

import 'helpers/test_receipts.dart';
import 'keck_printer_test.dart' show FakeTransport;

/// Papierschnitt am Bon (seit 11.15), Zwilling der Option `cut` von
/// `escPosLayoutBytes` im npm-Paket: Vorgabe ein voller Schnitt, `cutMode:
/// PosCutMode.partial` teilweise, `cut: false` gar keiner (Geraete-Einstellung
/// `cut: none`). Die Bytes stehen im Vertrag (`print-cut-cases.json`,
/// `expected/print-cut.<fall>.hex`); alles andere bleibt Byte fuer Byte gleich.

const _vertrag = 'test/fixtures/vertrag';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _faelle = (_json('$_vertrag/print-cut-cases.json')['cases'] as List).cast<Map<String, dynamic>>();

/// Fuenf Leerzeilen und `GS V 0` (voll) bzw. `GS V 1` (teilweise).
const _schnittVoll = [0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0x30];
const _schnittTeil = [0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0x31];

String _hexZeilen(List<int> bytes) {
  final teile = <String>[];
  for (var i = 0; i < bytes.length; i += 32) {
    teile.add(bytes.sublist(i, i + 32 > bytes.length ? bytes.length : i + 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join());
  }
  return '${teile.join('\n')}\n';
}

ReceiptLayout _layout(String receipt, String? paperSize) {
  final roh = _json('$_vertrag/expected/$receipt.lines.json');
  return ReceiptLayout.fromJson(paperSize == null ? roh : {...roh, 'paperSize': paperSize})!;
}

/// Die npm-Option `cut` (fehlt, `true`, `'full'`, `'partial'`, `false`) als die zwei Dart-Parameter.
({bool cut, PosCutMode cutMode}) _option(Object? npm) => switch (npm) {
      null || true || 'full' => (cut: true, cutMode: PosCutMode.full),
      'partial' => (cut: true, cutMode: PosCutMode.partial),
      false => (cut: false, cutMode: PosCutMode.full),
      _ => throw ArgumentError.value(npm, 'cut'),
    };

/// Wie `escPosLayoutBytes` mit Vorgaben: QR nativ, ohne Logo und Marke.
Future<List<int>> _bytes(ReceiptLayout layout, {bool cut = true, PosCutMode cutMode = PosCutMode.full}) async {
  final papier = layout.paperSize == 'mm58' ? KeckPaperSize.mm58 : KeckPaperSize.mm80;
  final paper = PrintPaper(paperSize: papier, profile: CapabilityProfile());
  await paper.setReceiptSheet(layout, cut: cut, cutMode: cutMode, qrMode: QrPrintMode.native);
  return paper.bytes.expand((e) => e).toList();
}

KasseneckReceipt _mitLayout(String name) {
  final f = _json('$_vertrag/receipts/$name.json');
  final firma = f['company'] as Map<String, dynamic>;
  return KasseneckReceipt.fromJson({
    'receipt': {...(f['receipt'] as Map<String, dynamic>), 'customerDetails': '', 'legalMessage': ''},
    'company': firma['companyName'],
    'street': firma['street'],
    'zip': firma['zip'],
    'city': firma['city'],
    'phone': firma['phone'],
    'vatId': firma['vatId'],
    'taxNumber': firma['taxNumber'],
    'is_small_business': false,
    'footer1': firma['footer1'] ?? '',
    'footer2': firma['footer2'] ?? '',
    'layout': _json('$_vertrag/expected/$name.lines.json'),
  });
}

/// Ohne Schnitt = Vorgabe ohne die letzten acht Bytes; teilweise = dasselbe mit `GS V 1`.
void _pruefeDrei(List<int> voll, List<int> ohne, List<int> teil, String wo) {
  expect(voll.sublist(voll.length - _schnittVoll.length), _schnittVoll, reason: '$wo: Vorgabe schneidet voll');
  expect(ohne, voll.sublist(0, voll.length - _schnittVoll.length), reason: '$wo: ohne Schnitt');
  expect(teil, [...ohne, ..._schnittTeil], reason: '$wo: teilweise');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('print-cut-cases.json', () {
    test('jeder Fall hat seine Hex-Datei und keine mehr; alle Werte der npm-Option kommen vor', () {
      final dateien = Directory('$_vertrag/expected')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((d) => d.startsWith('print-cut.'))
          .toList()
        ..sort();
      expect(dateien, [for (final f in _faelle) 'print-cut.${f['name']}.hex']..sort());
      expect({for (final f in _faelle) jsonEncode(f['cut'])}, {'null', 'true', '"full"', '"partial"', 'false'});
    });

    for (final f in _faelle) {
      test('${f['name']}: Bytes wie die Hex-Datei des npm-Pakets', () async {
        final o = _option(f['cut']);
        final soll = File('$_vertrag/expected/print-cut.${f['name']}.hex').readAsStringSync();
        final layout = _layout(f['receipt'] as String, f['paperSize'] as String?);
        expect(_hexZeilen(await _bytes(layout, cut: o.cut, cutMode: o.cutMode)), soll);
      });
    }
  });

  group('jeder Weg zum Bon', () {
    test('PrintPaper.setReceiptSheet und setReceiptLayout: ohne Schnitt fehlen genau Leerzeilen und GS V', () async {
      for (final name in ['sale-cash', 'zero-start', 'cancellation-full']) {
        for (final papier in ['mm58', 'mm80']) {
          final layout = _layout(name, papier);
          _pruefeDrei(await _bytes(layout), await _bytes(layout, cut: false),
              await _bytes(layout, cutMode: PosCutMode.partial), '$name/$papier');
        }
      }
      final papier = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
      await papier.setReceiptLayout(_layout('sale-cash', 'mm80'), cut: false, qrMode: QrPrintMode.native);
      expect(papier.bytes.expand((e) => e).toList(), await _bytes(_layout('sale-cash', 'mm80'), cut: false));
    });

    test('KeckPrinterService.getPaperFromReceipt, getBytesFromReceipt und getPrintBytes (Layout des Servers)', () async {
      final beleg = _mitLayout('sale-cash');
      expect(beleg.isLayoutComplete, isTrue);
      Future<List<int>> papier({bool cut = true, PosCutMode cutMode = PosCutMode.full}) async =>
          (await KeckPrinterService.getPaperFromReceipt(beleg, KeckPaperSize.mm80, cut: cut, cutMode: cutMode))
              .bytes
              .expand((e) => e)
              .toList();
      _pruefeDrei(await papier(), await papier(cut: false), await papier(cutMode: PosCutMode.partial), 'getPaperFromReceipt');
      final ohne = await papier(cut: false);
      expect((await KeckPrinterService.getBytesFromReceipt(beleg, KeckPaperSize.mm80, cut: false)).expand((e) => e).toList(),
          ohne);
      expect((await beleg.getPrintBytes(paperSize: KeckPaperSize.mm80, cut: false)).expand((e) => e).toList(), ohne);
    });

    test('der alte Weg ohne Layout (setKeckReceipt) und KeckPrinter.printReceipt', () async {
      final beleg = cartA();
      expect(beleg.isLayoutComplete, isFalse);
      final fake = FakeTransport();
      Future<List<int>> drucken({bool cut = true, PosCutMode cutMode = PosCutMode.full}) async {
        await KeckPrinter(fake, size: KeckPaperSize.mm58).printReceipt(beleg, cut: cut, cutMode: cutMode);
        return List<int>.of(fake.captured);
      }

      _pruefeDrei(await drucken(), await drucken(cut: false), await drucken(cutMode: PosCutMode.partial), 'printReceipt');
      final papier = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
      await papier.setKeckReceipt(beleg, cut: false);
      expect(papier.bytes.expand((e) => e).toList(), await drucken(cut: false));
    });
  });
}
