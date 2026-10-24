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
/// traegt im Kennungsblock direkt unter `Beleg-ID:` die Zeile
/// `Duplikat am: TT.MM.JJJJ HH:MM:SS` (Wiener Zeit des Nachdrucks), alles
/// andere bleibt wie beim Erstdruck.
///
/// Zwilling von `markAsDuplicate` im npm-Paket: die Faelle samt erwartetem
/// Layout und den Bytes des Nachdrucks kommen aus dessen Vertragsdatei
/// `duplicate-cases.json` (gezogen mit `tool/zwillinge.sh ziehen`, echt nach
/// `tool/zwillinge.sh pruefen`). Weicht die Zeile hier ab (anderer Text,
/// andere Stelle, andere Zeit), wird dieser Test rot.
const _vertrag = 'test/fixtures/vertrag';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;
ReceiptLayout _golden(String name) => ReceiptLayout.fromJson(_json('$_vertrag/expected/$name.lines.json'))!;

/// Das Layout in der Form des Vertrags, ueber JSON gegangen (wie die Datei).
Object? _draht(ReceiptLayout layout) => jsonDecode(jsonEncode(layout.toJson()));

/// 24.10.2026 14:10:05 in Wien (Sommerzeit, UTC+2).
final _nachdruck = DateTime.utc(2026, 10, 24, 12, 10, 5);
const _soll32 = 'Duplikat am: 24.10.2026 14:10:05';
final _soll48 = 'Duplikat am:${' ' * 17}24.10.2026 14:10:05';

/// Die Zeile, wie das Layout sie traegt (nicht fett, Wert rechtsbuendig).
Map<String, Object> _zeile(String zeit) => {
      'kind': 'columns',
      'columns': [
        {'text': 'Duplikat am:', 'width': 5, 'align': 'left'},
        {'text': zeit, 'width': 7, 'align': 'right'},
      ],
    };

bool _istBelegId(Object? z) => z is Map && z['kind'] == 'columns' && (z['columns'] as List).first['text'] == 'Beleg-ID:';

/// Der Erstdruck mit der Zeile an ihrer Stelle: direkt nach `Beleg-ID:`, ohne diese Zeile ganz oben.
Object? _erwartet(ReceiptLayout erst, String zeit) {
  final draht = _draht(erst) as Map<String, dynamic>;
  final lines = [...draht['lines'] as List];
  lines.insert(lines.indexWhere(_istBelegId) + 1, _zeile(zeit));
  return {...draht, 'lines': lines};
}

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

/// Dasselbe Probe-Logo wie im npm-Test (`test/duplikat.test.ts`) und in den
/// Vertragsfaellen mit `logo`: Stufe M, 300x120 px, jeder Punkt schwarz.
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

/// Ohne Stilbefehle `ESC E n` (fett) und `ESC a n` (Ausrichtung): was als Zeichen aufs Papier kommt.
String _ohneStil(String s) => s.replaceAll(RegExp(r'\x1bE[\x00\x01]|\x1ba[\x00-\x02\x30-\x32]'), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('markAsDuplicate', () {
    test('Zeile direkt unter „Beleg-ID:“ – 32 und 48 Zeichen genau wie vereinbart, nicht fett', () {
      final erst = _golden('sale-cash');
      final dup = markAsDuplicate(erst, printedAt: _nachdruck);
      expect(_draht(dup), _erwartet(erst, '24.10.2026 14:10:05'));
      for (final (zeichen, soll) in [(32, _soll32), (48, _soll48)]) {
        final raster = ReceiptGrid.render(dup, charsPerLine: zeichen).lines;
        final i = raster.indexWhere((z) => z.text.startsWith('Beleg-ID:'));
        expect(i, greaterThanOrEqualTo(0), reason: '$zeichen: Beleg-ID-Zeile');
        expect(raster[i + 1].text, soll, reason: '$zeichen: Zeile darunter');
        expect(raster[i + 1].text.length, zeichen);
        expect(raster[i + 1].bold, isFalse, reason: '$zeichen: nicht fett');
        expect(raster[i + 2].kind, GridLineKind.space, reason: '$zeichen: kein Umbruch');
      }
    });

    test('ueber die oeffentliche Bibliothek erreichbar', () {
      expect(_draht(barrel.markAsDuplicate(_golden('sale-cash'), printedAt: _nachdruck)), _draht(markAsDuplicate(_golden('sale-cash'), printedAt: _nachdruck)));
    });

    test('jede Belegart des Vertrags (Standard, Storno, Null-/Startbeleg, Gutschein, Schicht) – genau eine Zeile mehr, kein Aufdruck', () {
      for (final pflicht in ['sale-cash', 'cancellation-full', 'training', 'zero-start', 'zero-monthly', 'voucher-multi-purpose-redeem', 'voucher-single-purpose-sale', 'shift-close', 'cash-movement']) {
        expect(_goldens, contains(pflicht));
      }
      for (final name in _goldens) {
        final erst = _golden(name);
        final dup = markAsDuplicate(erst, printedAt: _nachdruck);
        expect(_draht(dup), _erwartet(erst, '24.10.2026 14:10:05'), reason: name);
        expect(dup.bannerTexts.any((t) => t.contains('DUPLIKAT')), isFalse, reason: '$name: kein Aufdruck');
        for (final (zeichen, soll) in [(32, _soll32), (48, _soll48)]) {
          final a = ReceiptGrid.render(erst, charsPerLine: zeichen).lines.map((z) => z.text).toList();
          final b = ReceiptGrid.render(dup, charsPerLine: zeichen).lines.map((z) => z.text).toList();
          final i = a.indexWhere((t) => t.startsWith('Beleg-ID:')) + 1;
          expect(b, [...a.sublist(0, i), soll, ...a.sublist(i)], reason: '$name/$zeichen');
        }
      }
    });

    test('Layout ohne „Beleg-ID:“ – die Zeile steht ganz oben', () {
      final schicht = _golden('shift-close');
      expect(((_draht(schicht) as Map)['lines'] as List).any(_istBelegId), isFalse);
      expect((_draht(markAsDuplicate(schicht, printedAt: _nachdruck)) as Map)['lines'], [_zeile('24.10.2026 14:10:05'), ...((_draht(schicht) as Map)['lines'] as List)]);
      expect(_draht(markAsDuplicate(const ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: []), printedAt: _nachdruck)), {
        'paperSize': 'mm80',
        'ruleset': 2,
        'lines': [_zeile('24.10.2026 14:10:05')],
      });
      // Ein „Beleg-ID:“ als Text (nicht als Spaltenzeile) zaehlt nicht.
      const text = ReceiptLayout(paperSize: 'mm58', ruleset: 2, lines: [LayoutTextLine(text: 'Beleg-ID:')]);
      expect((_draht(markAsDuplicate(text, printedAt: _nachdruck)) as Map)['lines'], [_zeile('24.10.2026 14:10:05'), text.lines.single.toJson()]);
    });

    test('noch einmal nachgedruckt – eine Zeile, die spaetere Zeit, an derselben Stelle', () {
      for (final name in ['sale-cash', 'zero-start', 'shift-close']) {
        final erst = _golden(name);
        final einmal = markAsDuplicate(erst, printedAt: _nachdruck);
        final zweimal = markAsDuplicate(einmal, printedAt: DateTime.utc(2026, 10, 24, 13, 45));
        expect(_draht(zweimal), _erwartet(erst, '24.10.2026 15:45:00'), reason: name);
        expect(_draht(markAsDuplicate(einmal, printedAt: _nachdruck)), _draht(einmal), reason: name);
      }
      // Eine Duplikat-Zeile an anderer Stelle bleibt dort; eine zweite faellt weg.
      final doppelt = ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: [
        const LayoutTextLine(text: 'Bäckerei Kornblum', align: LayoutAlign.center, bold: true),
        LayoutLine.fromJson(_zeile('01.01.2026 08:00:00'))!,
        const LayoutColumnsLine([LayoutColumn(text: 'Beleg-ID:', width: 6), LayoutColumn(text: 'AT0-KASSE1-42', width: 6, align: LayoutAlign.right)]),
        LayoutLine.fromJson(_zeile('02.01.2026 08:00:00'))!,
      ]);
      expect((_draht(markAsDuplicate(doppelt, printedAt: _nachdruck)) as Map)['lines'], [
        doppelt.lines[0].toJson(),
        _zeile('24.10.2026 14:10:05'),
        doppelt.lines[2].toJson(),
      ]);
    });

    test('Wiener Zeit des Nachdrucks, auch an den Umstellungen (nie die Zeitzone des Geraets)', () {
      String zeit(DateTime t) {
        final z = markAsDuplicate(const ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: []), printedAt: t).lines.first as LayoutColumnsLine;
        return z.columns[1].text;
      }

      // Ende der Sommerzeit: 03:00 MESZ wird 02:00 MEZ.
      expect(zeit(DateTime.utc(2026, 10, 25, 0, 59, 59)), '25.10.2026 02:59:59');
      expect(zeit(DateTime.utc(2026, 10, 25, 1)), '25.10.2026 02:00:00');
      // Beginn der Sommerzeit: 02:00 MEZ wird 03:00 MESZ.
      expect(zeit(DateTime.utc(2026, 3, 29, 0, 59, 59)), '29.03.2026 01:59:59');
      expect(zeit(DateTime.utc(2026, 3, 29, 1)), '29.03.2026 03:00:00');
      // Winter, Jahreswechsel, Bruchteile werden abgeschnitten (nicht gerundet).
      expect(zeit(DateTime.utc(2026, 12, 31, 23, 30)), '01.01.2027 00:30:00');
      expect(zeit(DateTime.utc(2026, 10, 24, 12, 10, 5, 999, 999)), '24.10.2026 14:10:05');
      // Eine Wiener Uhrzeit, die es in New York nicht gibt (dort Sommerzeitbeginn 08.03. 02:00).
      expect(zeit(DateTime.utc(2026, 3, 8, 1, 30)), '08.03.2026 02:30:00');
      // Ein lokaler Zeitpunkt zaehlt als derselbe Augenblick.
      expect(zeit(DateTime.utc(2026, 10, 25, 1).toLocal()), '25.10.2026 02:00:00');
    });

    test('die Eingabe bleibt unangetastet, das Ergebnis ist eine eigene Kopie', () {
      final erst = _golden('voucher-multi-purpose-redeem');
      final vorher = jsonEncode(erst.toJson());
      final dup = markAsDuplicate(erst, printedAt: _nachdruck);
      expect(jsonEncode(erst.toJson()), vorher);
      expect(identical(dup, erst), isFalse);
      expect(identical(dup.lines, erst.lines), isFalse);
      // Wer an der Liste oder an den Spalten des Duplikats dreht, dreht nicht am Erstdruck.
      for (final z in dup.lines.whereType<LayoutColumnsLine>()) {
        z.columns[0] = const LayoutColumn(text: 'verändert', width: 12);
        z.columns.add(const LayoutColumn(text: 'dazu', width: 1));
      }
      dup.lines.removeLast();
      expect(jsonEncode(erst.toJson()), vorher);
      // Auch ueber ein schon gekennzeichnetes Layout.
      final einmal = markAsDuplicate(erst, printedAt: _nachdruck);
      final einmalVorher = jsonEncode(einmal.toJson());
      final zweit = markAsDuplicate(einmal, printedAt: DateTime.utc(2026, 10, 24, 13, 45));
      expect(jsonEncode(einmal.toJson()), einmalVorher);
      expect(identical(zweit.lines, einmal.lines), isFalse);
      zweit.lines.whereType<LayoutColumnsLine>().first.columns.clear();
      expect(einmal.lines.whereType<LayoutColumnsLine>().first.columns, isNotEmpty);
    });
  });

  group('Zwilling (duplicate-cases.json aus dem npm-Paket)', () {
    final zwilling = _json('$_vertrag/duplicate-cases.json');
    final faelle = (zwilling['cases'] as List).cast<Map<String, dynamic>>();

    ReceiptLayout eingabe(Map<String, dynamic> fall) {
      final basis = fall['receipt'] != null ? _golden(fall['receipt'] as String) : ReceiptLayout.fromJson(fall['input'])!;
      final papier = fall['paperSize'] as String?;
      return papier == null ? basis : ReceiptLayout(lines: basis.lines, paperSize: papier, ruleset: basis.ruleset);
    }

    test('Prueffaelle decken Belegarten, Breiten und Umstellungen ab', () {
      expect(zwilling['version'], 2);
      expect(zwilling['label'], 'Duplikat am:');
      final namen = faelle.map((f) => f['receipt'] ?? f['name']).toList();
      for (final pflicht in ['sale-cash', 'cancellation-full', 'zero-start', 'voucher-multi-purpose-redeem', 'shift-close']) {
        expect(namen, contains(pflicht));
      }
      final gedruckt = faelle.where((f) => f['print'] == true).toList();
      expect(gedruckt.map((f) => eingabe(f).paperSize).toSet(), {'mm58', 'mm80'});
      expect(gedruckt.any((f) => f['logo'] == true), isTrue, reason: 'ein Fall mit Logo');
      expect(faelle.any((f) => (f['printedAt'] as List).length > 1), isTrue, reason: 'ein Fall zweimal angewandt');
      expect(faelle.any((f) => !((_draht(eingabe(f)) as Map)['lines'] as List).any(_istBelegId)), isTrue, reason: 'ein Fall ohne Beleg-ID');
      for (final (iso, anzeige) in [('2026-10-25T00:59:59Z', '25.10.2026 02:59:59'), ('2026-10-25T01:00:00Z', '25.10.2026 02:00:00'), ('2026-03-29T01:00:00Z', '29.03.2026 03:00:00')]) {
        expect(faelle.any((f) => (f['printedAt'] as List).last == iso && f['display'] == anzeige), isTrue, reason: iso);
      }
      final hex = Directory('$_vertrag/expected').listSync().map((e) => e.uri.pathSegments.last).where((d) => d.startsWith('duplicate.')).toList()..sort();
      expect(hex, [for (final f in gedruckt) 'duplicate.${f['name']}.hex']..sort());
    });

    for (final fall in faelle) {
      test('${fall['name']}: Layout${fall['print'] == true ? ' und Bytes' : ''} wie im npm-Paket', () async {
        var layout = eingabe(fall);
        for (final iso in (fall['printedAt'] as List).cast<String>()) {
          layout = markAsDuplicate(layout, printedAt: DateTime.parse(iso));
        }
        expect(_draht(layout), fall['expected']);
        final zeile = layout.lines.whereType<LayoutColumnsLine>().firstWhere((z) => z.columns.first.text == 'Duplikat am:');
        expect(zeile.columns[1].text, fall['display']);
        if (fall['print'] == true) {
          final papier = _papier(layout.paperSize);
          final logo = fall['logo'] == true ? _probeLogo(papier == KeckPaperSize.mm58 ? 32 : 48) : null;
          final soll = File('$_vertrag/expected/duplicate.${fall['name']}.hex').readAsStringSync();
          expect(_hexZeilen(await _bytes(layout, papier, logo: logo)), soll);
        }
      });
    }
  });

  /// Der Nachdruck am Drucker ist der Erstdruck mit genau einer Zeile mehr:
  /// dieselben Bytes bis einschliesslich der Zeile `Beleg-ID:`, dann derselbe
  /// Zeichensatz-Vorspann wie vor jeder Zeile, `Duplikat am: …` und der
  /// Zeilenvorschub, dann wieder dieselben Bytes bis zum Schnitt (Logo, QR,
  /// Signaturtext). Die Zeile steht im selben Stil wie `Beleg-ID:` (nicht
  /// fett, linksbuendig), darum kommt kein Stilbefehl dazu. Wie im npm-Test.
  test('ESC/POS: Nachdruck = Erstdruck plus genau die Zeile „Duplikat am:“ (Byte fuer Byte)', () async {
    for (final name in ['sale-cash', 'voucher-multi-purpose-redeem', 'zero-start', 'cancellation-full', 'test-cashregister-sale', 'cancellation-partial', 'voucher-service-redeem']) {
      for (final papier in [KeckPaperSize.mm58, KeckPaperSize.mm80]) {
        final zeichen = papier == KeckPaperSize.mm58 ? 32 : 48;
        for (final logo in [null, _probeLogo(zeichen)]) {
          final fall = '$name/${papier.name}/${logo == null ? 'ohne Logo' : 'Logo'}';
          final erst = _golden(name);
          final a = latin1.decode(await _bytes(erst, papier, logo: logo));
          final b = latin1.decode(await _bytes(markAsDuplicate(erst, printedAt: _nachdruck), papier, logo: logo));
          final beleg = a.indexOf('Beleg-ID:');
          expect(beleg, greaterThan(0), reason: '$fall: Beleg-ID im Erstdruck');
          final ende = a.indexOf('\n', beleg) + 1;
          final zeilenVorspann = a.substring(a.lastIndexOf('\n', beleg) + 1, beleg);
          expect(zeilenVorspann, '\x1c.\x1bt\x10', reason: fall);
          expect(b, '${a.substring(0, ende)}$zeilenVorspann${zeichen == 32 ? _soll32 : _soll48}\n${a.substring(ende)}', reason: fall);
        }
      }
    }
  });

  test('ESC/POS: ohne „Beleg-ID:“ steht die Zeile vor der ersten Zeile des Erstdrucks', () async {
    for (final name in ['shift-close', 'cash-movement']) {
      for (final papier in [KeckPaperSize.mm58, KeckPaperSize.mm80]) {
        final soll = papier == KeckPaperSize.mm58 ? _soll32 : _soll48;
        final erst = _golden(name);
        final a = latin1.decode(await _bytes(erst, papier));
        final b = latin1.decode(await _bytes(markAsDuplicate(erst, printedAt: _nachdruck), papier));
        final vorspann = latin1.decode(await _bytes(ReceiptLayout(lines: const [], paperSize: erst.paperSize, ruleset: erst.ruleset), papier, cut: false));
        expect(a.startsWith(vorspann) && b.startsWith(vorspann), isTrue, reason: '$name/${papier.name}: Vorspann');
        final kopf = b.substring(vorspann.length, b.indexOf('\n', vorspann.length) + 1);
        expect(_ohneStil(kopf), '\x1c.\x1bt\x10$soll\n', reason: '$name/${papier.name}: Zeile zuerst');
        expect(kopf.contains('\x1bE\x01'), isFalse, reason: '$name/${papier.name}: nicht fett');
        expect(_ohneStil(b.substring(vorspann.length + kopf.length)), _ohneStil(a.substring(vorspann.length)), reason: '$name/${papier.name}: Rest');
      }
    }
  });
}
