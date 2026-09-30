import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasseneck_api.dart' show KeckReceiptSheetWidget, SheetLine;
import 'package:kasseneck_api/printing.dart';

/// Das Testblatt am Bildschirm: dasselbe Blatt-Widget wie der Beleg, die
/// Nummern doppelt gross und fett wie am Papier (`GS !` + `ESC E`).
void main() {
  final blatt = codeTableTestSheet(cashregisterLabel: 'Kasse KECK-1', time: DateTime.utc(2026, 9, 30, 12, 5), paper: KeckPaperSize.mm58);

  Widget huelle(Widget kind) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: kind)));

  testWidgets('jede Zeile steht zeichengleich; Nummernzeilen zwei Zeilen hoch, Nummer doppelt gross und fett', (tester) async {
    await tester.pumpWidget(huelle(KeckReceiptSheetWidget.fromSheet(sheet: blatt, fontSize: 12)));
    final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
    final cw = breite / blatt.charsPerLine;

    for (final (i, b) in blatt.blocks.indexed) {
      final zeile = b as SheetLine;
      final f = find.byKey(Key('keck-blatt-zeile-$i'));
      expect(f, findsOneWidget);
      final texte = tester.widgetList<Text>(find.descendant(of: f, matching: find.byType(Text))).toList();
      final lead = zeile.doubleSizeLead;
      if (lead == null) {
        expect(texte.single.data, zeile.text);
        expect(tester.getSize(f).height, closeTo(2 * cw, 0.01));
        continue;
      }
      expect(tester.getSize(f).height, closeTo(4 * cw, 0.01), reason: 'Zeile $i zwei Zeilen hoch');
      expect(texte, hasLength(2));
      expect(texte[0].data, zeile.text.substring(0, lead).trim());
      expect(texte[0].style!.fontSize, 24);
      expect(texte[0].style!.fontWeight, FontWeight.bold);
      expect(texte[1].data, zeile.text.substring(lead));
      expect(texte[1].style!.fontSize, 12);
      // Die Nummernzelle ist so breit wie ihre Spalten: der Rest steht darum
      // unter denselben Spalten wie die Vorlage.
      expect(tester.getSize(find.byKey(Key('keck-blatt-zeile-$i-nummer'))).width, closeTo(lead * cw, 0.01));
    }
  });

  testWidgets('doubleSizeLead laenger als der Text: kein Absturz, der ganze Text steht in der Nummernzelle', (tester) async {
    final kurz = CodeTableTestSheet(
      charsPerLine: 32,
      rows: const [],
      blocks: const [SheetLine(text: ' 7', bold: false, blank: false, doubleSizeLead: 5)],
    );
    await tester.pumpWidget(huelle(KeckReceiptSheetWidget.fromSheet(sheet: kurz)));
    expect(tester.takeException(), isNull);
    final texte = tester.widgetList<Text>(find.descendant(of: find.byKey(const Key('keck-blatt-zeile-0')), matching: find.byType(Text))).toList();
    expect(texte.map((t) => t.data), ['7', '']);
  });

  testWidgets('ein Beleg ohne das Feld zeichnet wie bisher (einfach gross)', (tester) async {
    final einfach = ReceiptSheetOhneLead.aus(blatt);
    await tester.pumpWidget(huelle(KeckReceiptSheetWidget.fromSheet(sheet: einfach)));
    final f = find.byKey(const Key('keck-blatt-zeile-7'));
    expect(tester.widgetList<Text>(find.descendant(of: f, matching: find.byType(Text))).single.data, (blatt.blocks[7] as SheetLine).text);
  });
}

/// Dasselbe Blatt, aber ohne `doubleSizeLead` an den Zeilen.
extension ReceiptSheetOhneLead on CodeTableTestSheet {
  static CodeTableTestSheet aus(CodeTableTestSheet b) => CodeTableTestSheet(
        charsPerLine: b.charsPerLine,
        rows: b.rows,
        blocks: [for (final z in b.blocks) SheetLine(text: (z as SheetLine).text, bold: z.bold, blank: z.blank)],
      );
}
