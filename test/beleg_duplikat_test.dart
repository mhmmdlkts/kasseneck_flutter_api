import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/kasseneck_api.dart' as barrel show markAsDuplicate;
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

/// Belegduplikat (Erlass BMF-AV Nr. 2/2026, Abschnitt 4.5.6): ein Nachdruck
/// traegt oben den Aufdruck „DUPLIKAT“, alles andere bleibt wie beim
/// Erstdruck.
///
/// Zwilling von `markAsDuplicate` im npm-Paket: die Faelle samt erwartetem
/// Layout und den Bytes des Nachdrucks kommen aus dessen Vertragsdatei
/// `duplicate-cases.json` (gezogen mit `tool/zwillinge.sh ziehen`, echt nach
/// `tool/zwillinge.sh pruefen`). Weicht der Aufdruck hier ab (anderer Text,
/// anderer Ton, andere Stelle), wird dieser Test rot.
const _vertrag = 'test/fixtures/vertrag';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;
ReceiptLayout _golden(String name) => ReceiptLayout.fromJson(_json('$_vertrag/expected/$name.lines.json'))!;

/// Die Zeile in der Form des Vertrags, ueber JSON gegangen (wie die Datei).
Object? _draht(ReceiptLayout layout) => jsonDecode(jsonEncode(layout.toJson()));

const _aufdruck = {'kind': 'banner', 'text': 'DUPLIKAT', 'tone': 'receipt_type'};

/// Alle Golden-Layouts des Vertrags: jede Belegart, die das Layout kennt, dazu die Schicht-Bons.
final List<String> _goldens = (Directory('$_vertrag/expected')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((d) => d.endsWith('.lines.json') && !d.startsWith('code-table-'))
        .map((d) => d.substring(0, d.length - '.lines.json'.length))
        .toList())
  ..sort();

String _hexZeilen(List<int> bytes) {
  final teile = <String>[];
  for (var i = 0; i < bytes.length; i += 32) {
    teile.add(bytes.sublist(i, i + 32 > bytes.length ? bytes.length : i + 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join());
  }
  return '${teile.join('\n')}\n';
}

KeckPaperSize _papier(String paperSize) => paperSize == 'mm58' ? KeckPaperSize.mm58 : KeckPaperSize.mm80;

/// Dasselbe Probe-Logo wie im npm-Test (`test/duplikat.test.ts`).
PrintLogo _probeLogo(int zeichen) {
  const probe = SheetLogo(size: SheetLogoSize.m, pixelWidth: 300, pixelHeight: 120);
  final m = logoRasterSize(logoDimensions(probe, zeichen), zeichen);
  return PrintLogo(
    size: probe.size,
    pixelWidth: probe.pixelWidth,
    pixelHeight: probe.pixelHeight,
    raster: LogoRaster(width: m.width, height: m.height, dots: Uint8List(m.width * m.height)..fillRange(0, m.width * m.height, 1)),
  );
}

/// Bytes mit den Vorgaben des Druckwegs, QR nativ (wie npm `escPosLayoutBytes`).
Future<List<int>> _bytes(ReceiptLayout layout, KeckPaperSize papier, {PrintLogo? logo, bool cut = true}) async {
  final paper = PrintPaper(paperSize: papier, profile: CapabilityProfile());
  await paper.setReceiptSheet(layout, logo: logo, cut: cut, qrMode: QrPrintMode.native);
  return paper.bytes.expand((e) => e).toList();
}

/// Der Bytestrom, wie der Drucker ihn ausfuehrt: jedes Byte ausser den
/// Stilbefehlen `ESC E n` (fett) und `ESC a n` (Ausrichtung), jeweils mit dem
/// Stil, der in diesem Moment wirkt. Der Druckweg sendet einen Stil nur, wenn
/// er sich aendert; nach dem fetten Aufdruck faellt darum das `ESC E 1` des
/// fetten Firmennamens weg (vor dem Logo kommt ein `ESC E 0` dazu). Auf dem
/// Papier ist das dasselbe, und genau das vergleicht diese Form. (Gilt fuer
/// diese Prueffaelle: weder das Probe-Logo noch die QR-Nutzlast enthalten die
/// Folge 1B 45 / 1B 61.) Wie `wirksam` im npm-Test.
List<String> _wirksam(List<int> b) {
  var fett = false;
  var ausrichtung = 0x30;
  final aus = <String>[];
  for (var i = 0; i < b.length; i++) {
    if (b[i] == 0x1b && i + 2 < b.length && b[i + 1] == 0x45) {
      fett = b[i + 2] == 1;
      i += 2;
      continue;
    }
    if (b[i] == 0x1b && i + 2 < b.length && b[i + 1] == 0x61) {
      ausrichtung = b[i + 2];
      i += 2;
      continue;
    }
    aus.add('${b[i]}|${fett ? 'fett' : 'normal'}|${String.fromCharCode(ausrichtung)}');
  }
  return aus;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('markAsDuplicate', () {
    test('neue erste Zeile „DUPLIKAT“ als Aufdruck (zentriert, fett, gerahmt), der Rest unveraendert', () {
      final erst = _golden('sale-cash');
      final dup = markAsDuplicate(erst);
      expect(dup.lines.first.toJson(), _aufdruck);
      expect(_draht(dup), {
        ...(_draht(erst) as Map),
        'lines': [_aufdruck, ...((_draht(erst) as Map)['lines'] as List)],
      });
      expect(dup.paperSize, erst.paperSize);
      expect(dup.ruleset, erst.ruleset);
      final raster = ReceiptGrid.render(dup, charsPerLine: 32).lines.take(3).toList();
      expect(raster.map((z) => z.text), ['=' * 32, '${' ' * 12}DUPLIKAT${' ' * 12}', '=' * 32]);
      expect(raster.every((z) => z.bold), isTrue);
    });

    test('ueber die oeffentliche Bibliothek erreichbar', () {
      expect(_draht(barrel.markAsDuplicate(_golden('sale-cash'))), _draht(markAsDuplicate(_golden('sale-cash'))));
    });

    test('jede Belegart des Vertrags (Standard, Storno, Null-/Startbeleg, Gutschein, Schicht): QR, Betraege, Signatur unveraendert', () {
      for (final pflicht in ['sale-cash', 'cancellation-full', 'training', 'zero-start', 'zero-monthly', 'voucher-multi-purpose-redeem', 'voucher-single-purpose-sale', 'shift-close', 'cash-movement']) {
        expect(_goldens, contains(pflicht));
      }
      for (final name in _goldens) {
        final erst = _golden(name);
        final dup = markAsDuplicate(erst);
        expect(dup.lines.skip(1).toList(), erst.lines, reason: name);
        for (final zeichen in [32, 48]) {
          final a = ReceiptGrid.render(erst, charsPerLine: zeichen).lines.map((z) => z.text).toList();
          final b = ReceiptGrid.render(dup, charsPerLine: zeichen).lines.map((z) => z.text).toList();
          final mitte = ' ' * ((zeichen - 8) ~/ 2);
          expect(b, ['=' * zeichen, '${mitte}DUPLIKAT$mitte', '=' * zeichen, ...a], reason: '$name/$zeichen');
        }
      }
    });

    test('die Eingabe bleibt unangetastet, das Ergebnis ist eine eigene Kopie', () {
      final erst = _golden('voucher-multi-purpose-redeem');
      final vorher = jsonEncode(erst.toJson());
      final dup = markAsDuplicate(erst);
      expect(jsonEncode(erst.toJson()), vorher);
      expect(identical(dup, erst), isFalse);
      expect(identical(dup.lines, erst.lines), isFalse);
      // Wer an der Liste des Duplikats dreht, dreht nicht am Erstdruck.
      dup.lines.removeLast();
      expect(jsonEncode(erst.toJson()), vorher);
      final zweit = markAsDuplicate(dup);
      expect(identical(zweit.lines, dup.lines), isFalse);
    });

    test('idempotent: zweimal angewandt wie einmal (Erkennung an der eigenen ersten Zeile)', () {
      for (final name in _goldens) {
        final einmal = markAsDuplicate(_golden(name));
        expect(_draht(markAsDuplicate(einmal)), _draht(einmal), reason: name);
        expect(_draht(markAsDuplicate(markAsDuplicate(einmal))), _draht(einmal), reason: name);
      }
      // Ein „DUPLIKAT“ weiter unten (etwa im Artikelnamen) ist keine Kennzeichnung.
      const artikel = ReceiptLayout(paperSize: 'mm58', ruleset: 2, lines: [LayoutTextLine(text: 'DUPLIKAT', align: LayoutAlign.center, bold: true)]);
      expect((_draht(markAsDuplicate(artikel)) as Map)['lines'], [_aufdruck, artikel.lines.single.toJson()]);
    });

    test('leeres Layout wirft nicht', () {
      expect(_draht(markAsDuplicate(const ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: []))), {
        'paperSize': 'mm80',
        'ruleset': 2,
        'lines': [_aufdruck],
      });
    });
  });

  group('Zwilling (duplicate-cases.json aus dem npm-Paket)', () {
    final zwilling = _json('$_vertrag/duplicate-cases.json');
    final faelle = (zwilling['cases'] as List).cast<Map<String, dynamic>>();

    test('Prueffaelle decken die Belegarten ab und nennen den Aufdruck', () {
      expect(zwilling['text'], 'DUPLIKAT');
      final namen = faelle.map((f) => f['receipt'] ?? f['name']).toList();
      for (final pflicht in ['sale-cash', 'cancellation-full', 'zero-start', 'voucher-multi-purpose-redeem', 'test-cashregister-sale', 'shift-close']) {
        expect(namen, contains(pflicht));
      }
      expect(faelle.any((f) => (f['times'] as int) > 1), isTrue, reason: 'ein Fall wendet mehrfach an (Idempotenz)');
      final hex = Directory('$_vertrag/expected').listSync().map((e) => e.uri.pathSegments.last).where((d) => d.startsWith('duplicate.')).toList()..sort();
      expect(hex, [for (final f in faelle) if (f['print'] == true) 'duplicate.${f['name']}.hex']..sort());
      expect(hex.length, greaterThanOrEqualTo(2));
    });

    for (final fall in faelle) {
      test('${fall['name']}: Layout${fall['print'] == true ? ' und Bytes' : ''} wie im npm-Paket', () async {
        var layout = fall['receipt'] != null ? _golden(fall['receipt'] as String) : ReceiptLayout.fromJson(fall['input'])!;
        for (var i = 0; i < (fall['times'] as int); i++) {
          layout = markAsDuplicate(layout);
        }
        expect(_draht(layout), fall['expected']);
        if (fall['print'] == true) {
          final soll = File('$_vertrag/expected/duplicate.${fall['name']}.hex').readAsStringSync();
          expect(_hexZeilen(await _bytes(layout, _papier(layout.paperSize))), soll);
        }
      });
    }
  });

  /// Der Nachdruck am Drucker: derselbe Vorspann (Initialisierung,
  /// Druckbereich, Codepage), dann der Aufdruck (drei fette Zeilen; mit Logo
  /// dazu die Leerzeile vor dem Logo, die das Blatt nach jedem fuehrenden
  /// Rahmen setzt), dann der Erstdruck ab dem Ende des Vorspanns, samt Logo,
  /// QR und Schnitt: Byte fuer Byte im selben wirksamen Stil.
  test('ESC/POS: Nachdruck beginnt nach dem Vorspann mit „DUPLIKAT“, der Rest ist der Erstdruck (gleiche Bytes, gleicher Stil)', () async {
    for (final name in ['sale-cash', 'voucher-multi-purpose-redeem', 'zero-start', 'cancellation-full', 'test-cashregister-sale', 'shift-close']) {
      for (final papier in [KeckPaperSize.mm58, KeckPaperSize.mm80]) {
        final zeichen = papier == KeckPaperSize.mm58 ? 32 : 48;
        for (final logo in [null, _probeLogo(zeichen)]) {
          final fall = '$name/${papier.name}/${logo == null ? 'ohne Logo' : 'Logo'}';
          final erst = _golden(name);
          final a = await _bytes(erst, papier, logo: logo);
          final b = await _bytes(markAsDuplicate(erst), papier, logo: logo);
          final vorspann = await _bytes(ReceiptLayout(lines: const [], paperSize: erst.paperSize, ruleset: erst.ruleset), papier, cut: false);
          expect(a.sublist(0, vorspann.length), vorspann, reason: fall);
          expect(b.sublist(0, vorspann.length), vorspann, reason: fall);

          final wa = _wirksam(a);
          final wb = _wirksam(b);
          final nv = _wirksam(vorspann).length;
          final rest = wa.length - nv;
          expect(wb.length, greaterThan(wa.length), reason: fall);
          expect(wb.sublist(wb.length - rest), wa.sublist(nv), reason: '$fall: Rest wie der Erstdruck');

          // Der Kopf dazwischen: drei fette Zeilen, mit Logo dazu ein Vorschub, kein Bild.
          final kopf = wb.sublist(nv, wb.length - rest);
          final text = String.fromCharCodes(kopf.map((t) => int.parse(t.split('|').first)));
          final zeilen = text.replaceAll(RegExp(r'\x1c\x2e|\x1bt[\x00-\xff]'), '').split('\n');
          final mitte = ' ' * ((zeichen - 8) ~/ 2);
          expect(zeilen.take(3).toList(), ['=' * zeichen, '${mitte}DUPLIKAT', '=' * zeichen], reason: fall);
          final mitVorschub = logo != null && erst.lines.first is! LayoutBannerLine;
          expect(zeilen.skip(3).toList(), mitVorschub ? ['\x1bd\x01'] : [''], reason: '$fall: nach dem Aufdruck');
          expect(
            kopf.where((t) => '=DUPLIKAT'.contains(String.fromCharCode(int.parse(t.split('|').first)))).every((t) => t.endsWith('|fett|0')),
            isTrue,
            reason: '$fall: Aufdruck fett',
          );
          expect(text.contains('\x1dv0'), isFalse, reason: '$fall: kein Bild im Kopf');
        }
      }
    }
  });
}
