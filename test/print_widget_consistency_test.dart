import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

/// Print- und Widget-Rendering berechnen die MwSt-Tabelle UNABHAENGIG
/// voneinander (print_paper.setKeckReceipt vs. keck_receipt_widget.setTemp).
/// Diese Tests stellen sicher, dass beide fuer denselben Beleg dieselben
/// Werte zeigen — Drift zwischen den beiden Implementierungen fliegt auf.
///
/// Print-Seite wird ueber myPosPaper.commands ausgelesen (Text-Repraesentation
/// des Drucks — kein Drucker noetig).

class VatRow {
  final String label; // z. B. 'A 20%'
  final String mwst, netto, brutto;
  VatRow(this.label, this.mwst, this.netto, this.brutto);
  @override
  String toString() => '$label | $mwst | $netto | $brutto';
}

Future<({List<VatRow> rows, List<({String left, String right})> doubles, List<String> texts})>
    renderPrint(KasseneckReceipt receipt) async {
  final profile = await CapabilityProfile.load();
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: profile);
  // native QR -> kein Bild-Rendering noetig; auf die Werte hat das keinen Einfluss
  await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);

  final texts = paper.myPosPaper.commands
      .where((c) => c['type'] == 'text')
      .map((c) => c['value'] as String)
      .toList();
  final doubles = paper.myPosPaper.commands
      .where((c) => c['type'] == 'doubleText')
      .map((c) => (left: c['leftValue'] as String, right: c['rightValue'] as String))
      .toList();

  final rowPattern = RegExp(r'^([A-G]) (\d+(?:,\d+)?%)\s+([\d,.-]+)\s+([\d,.-]+)\s+([\d,.-]+)\s*$');
  final rows = <VatRow>[];
  for (final t in texts) {
    final m = rowPattern.firstMatch(t);
    if (m != null) {
      rows.add(VatRow('${m.group(1)} ${m.group(2)}', m.group(3)!, m.group(4)!, m.group(5)!));
    }
  }
  return (rows: rows, doubles: doubles, texts: texts);
}

Future<List<String>> renderWidget(WidgetTester tester, KasseneckReceipt receipt) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: receipt))),
  ));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
}

void main() {
  testWidgets('Warenkorb A: Print == Widget (MwSt-Tabelle, Gesamt, Promo)', (tester) async {
    final receipt = cartA();
    // runAsync: CapabilityProfile.load() macht echtes Asset-I/O, das in der
    // FakeAsync-Zone von testWidgets sonst nie completed (Deadlock).
    final print = (await tester.runAsync(() => renderPrint(receipt)))!;
    final widgetTexts = await renderWidget(tester, receipt);

    // Anker: erwartete Brutto-Werte (verifizierte Geraete-Sollwerte)
    expect(print.rows.map((r) => '${r.label}=${r.brutto}'),
        containsAll(['A 20%=58,52', 'G 4,9%=0,29', 'B 10%=2,05']));
    expect(print.rows.length, 3);

    // Kreuzvergleich: jede Print-Zeile muss 1:1 im Widget auftauchen
    for (final row in print.rows) {
      expect(widgetTexts, contains(row.label), reason: 'Label fehlt im Widget: $row');
      expect(widgetTexts, contains(row.mwst), reason: 'MwSt fehlt im Widget: $row');
      expect(widgetTexts, contains(row.netto), reason: 'Netto fehlt im Widget: $row');
      expect(widgetTexts, contains(row.brutto), reason: 'Brutto fehlt im Widget: $row');
    }
    // Widget hat exakt gleich viele MwSt-Zeilen (keine zusaetzlichen Kategorien)
    final widgetLabels = widgetTexts.where((t) => RegExp(r'^[A-G] \d+(,\d+)?%$').hasMatch(t));
    expect(widgetLabels.length, print.rows.length);

    // Gesamt identisch
    final gesamtPrint = print.doubles.firstWhere((d) => d.left == 'Gesamt:').right;
    expect(gesamtPrint, '60,86 EUR');
    expect(widgetTexts, contains('Gesamt:'));
    expect(widgetTexts, contains(gesamtPrint));

    // Promo-Zeile: gleicher Abzug auf beiden Seiten
    final promoPrint = print.doubles.firstWhere((d) => d.left.startsWith('Promotionsgutschein'));
    expect(promoPrint.right, '-1,50 EUR');
    expect(widgetTexts, contains('-1,50 EUR'));

    // Kein Zwischensummen-Block (sum == subSum)
    expect(print.doubles.where((d) => d.left == 'Zwischensumme'), isEmpty);
    expect(widgetTexts, isNot(contains('Zwischensumme')));
  });

  testWidgets('Warenkorb B: Print == Widget (Zwischensumme, Wertgutscheine, 0%-Zeile)', (tester) async {
    final receipt = cartB();
    final print = (await tester.runAsync(() => renderPrint(receipt)))!;
    final widgetTexts = await renderWidget(tester, receipt);

    expect(print.rows.map((r) => '${r.label}=${r.brutto}'),
        containsAll(['A 20%=59,97', 'G 4,9%=0,29', 'B 10%=2,10', 'D 0%=10,00']));
    expect(print.rows.length, 4);

    for (final row in print.rows) {
      expect(widgetTexts, contains(row.label), reason: 'Label fehlt im Widget: $row');
      expect(widgetTexts, contains(row.mwst), reason: 'MwSt fehlt im Widget: $row');
      expect(widgetTexts, contains(row.netto), reason: 'Netto fehlt im Widget: $row');
      expect(widgetTexts, contains(row.brutto), reason: 'Brutto fehlt im Widget: $row');
    }

    // Zwischensumme + Einloesung + Gesamt identisch
    expect(print.doubles.firstWhere((d) => d.left == 'Zwischensumme').right, '72,36 EUR');
    expect(widgetTexts, contains('Zwischensumme'));
    expect(widgetTexts, contains('72,36 EUR'));
    expect(print.doubles.firstWhere((d) => d.left == 'Gesamt:').right, '67,36 EUR');
    expect(widgetTexts, contains('67,36 EUR'));
    expect(widgetTexts, contains('-5,00 EUR'));

    // Item-Zeilensummen (rechte Spalte) identisch
    for (final right in ['59,97 A', '0,29 G', '2,10 B', '10,00 D']) {
      expect(print.doubles.map((d) => d.right), contains(right), reason: 'Print: $right');
      expect(widgetTexts, contains(right), reason: 'Widget: $right');
    }
  });

  testWidgets('Kopf/Fuss konsistent: Firma, Beleg-ID, Footer auf beiden Seiten', (tester) async {
    final receipt = cartA();
    final print = (await tester.runAsync(() => renderPrint(receipt)))!;
    final widgetTexts = await renderWidget(tester, receipt);

    for (final value in ['Kasseneck Test GmbH', 'Footer Eins', 'Footer Zwei']) {
      expect(print.texts, contains(value));
      expect(widgetTexts, contains(value));
    }
    expect(print.doubles.firstWhere((d) => d.left == 'Beleg-ID:').right, 'TEST-ID-1');
    expect(widgetTexts, contains('TEST-ID-1'));
  });
}
