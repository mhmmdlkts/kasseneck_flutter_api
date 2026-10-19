import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart' show receiptDueCents;
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

/// Die Zweispalter des Drucks (links, rechts).
Future<List<({String left, String right})>> gedruckt(dynamic beleg) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(beleg);
  return paper.myPosPaper.commands
      .where((c) => c['type'] == 'doubleText')
      .map((c) => (left: c['leftValue'] as String, right: c['rightValue'] as String))
      .toList();
}

/// Storno eines Belegs mit Wertgutschein. Das Backend spiegelt die
/// Wertgutscheine beim Vollstorno mit UNVERAENDERTER action und positivem Wert
/// (storno-core.stornoVouchers); der Fluss dreht sich am Storno-Beleg um
/// (zahlungen-core.wertgutscheinFlussCents, hier `receiptDueCents`). Summe und
/// Bon muessen dasselbe sagen wie die Zahlungen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final einloesung = KeckVoucher(code: 'GS-7', action: VoucherAction.redeem, type: VoucherType.value, valueCents: 1750);
  final verkauf = KeckVoucher(code: 'GS-8', action: VoucherAction.sell, type: VoucherType.value, valueCents: 3000);

  test('Original mit Einloesung: Summe 4,90 wie bisher (Rot-Probe fuer den Storno)', () {
    final r = buildReceipt(
      items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: 2240)],
      vouchers: [einloesung],
    );
    expect(r.valueVoucherSign, 1);
    expect(r.subSumCents, 2240);
    expect(r.sumCents, 490);
  });

  test('Storno einer Einloesung: Gesamt -4,90 = Rueckzahlung', () {
    final r = buildReceipt(
      receiptType: ReceiptType.cancellation,
      items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: -2240)],
      vouchers: [einloesung],
    );
    expect(r.valueVoucherSign, -1);
    expect(r.subSumCents, -2240);
    expect(r.sumCents, -490);
    expect(r.sumCents, receiptDueCents(r.items, r.vouchers!, ReceiptType.cancellation));
  });

  test('Storno eines Gutschein-Verkaufs: Gesamt -30,00', () {
    final r = buildReceipt(receiptType: ReceiptType.cancellation, vouchers: [verkauf]);
    expect(r.subSumCents, -3000);
    expect(r.sumCents, -3000);
    expect(r.sumCents, receiptDueCents(r.items, r.vouchers!, ReceiptType.cancellation));
  });

  test('Druck: Storno einer Einloesung zeigt den Gutschein ohne Minus und Gesamt -4,90', () async {
    final r = buildReceipt(
      receiptType: ReceiptType.cancellation,
      items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: -2240)],
      vouchers: [einloesung],
    );
    final zeilen = await gedruckt(r);
    expect(zeilen.firstWhere((z) => z.left == 'Zwischensumme').right, '-22,40 EUR');
    expect(zeilen.firstWhere((z) => z.left.contains('Wertgutschein')).right, '17,50 EUR');
    expect(zeilen.firstWhere((z) => z.left == 'Gesamt:').right, '-4,90 EUR');
  });

  test('Druck: Storno eines Gutschein-Verkaufs zeigt -30,00 D und Gesamt -30,00', () async {
    final r = buildReceipt(receiptType: ReceiptType.cancellation, vouchers: [verkauf]);
    final zeilen = await gedruckt(r);
    expect(zeilen.firstWhere((z) => z.left.contains('Wertgutschein')).right, '-30,00 D');
    expect(zeilen.firstWhere((z) => z.left == 'Gesamt:').right, '-30,00 EUR');
  });

  test('Druck: Original mit Einloesung bleibt bei -17,50 und Gesamt 4,90', () async {
    final r = buildReceipt(
      items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: 2240)],
      vouchers: [einloesung],
    );
    final zeilen = await gedruckt(r);
    expect(zeilen.firstWhere((z) => z.left.contains('Wertgutschein')).right, '-17,50 EUR');
    expect(zeilen.firstWhere((z) => z.left == 'Gesamt:').right, '4,90 EUR');
  });

  testWidgets('Bildschirm: Storno einer Einloesung zeigt 17,50 und Gesamt -4,90', (tester) async {
    final r = buildReceipt(
      receiptType: ReceiptType.cancellation,
      items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: -2240)],
      vouchers: [einloesung],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: r))),
    ));
    final texte = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
    expect(texte, contains('17,50 EUR'));
    expect(texte, isNot(contains('-17,50 EUR')));
    expect(texte, contains('-4,90 EUR'));
  });

  // Aktionsgutschein (promo): der Server spiegelt ihn an den Storno, nimmt den
  // Rabatt aber ueber Ausgleichspositionen zurueck; der Eintrag mindert dort nichts.
  KasseneckReceipt stornoMitAktion() => buildReceipt(
        receiptType: ReceiptType.cancellation,
        items: [
          KasseneckItem(name: 'Geschenkkorb', quantity: 1, vat: VatRate.vat20, priceCents: -2240),
          KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: -1190),
          KasseneckItem(name: 'Gutschein-Ausgleich', quantity: 1, vat: VatRate.vat20, priceCents: 654, kind: 'discount'),
          KasseneckItem(name: 'Gutschein-Ausgleich', quantity: 1, vat: VatRate.vat10, priceCents: 346, kind: 'discount'),
        ],
        vouchers: [KeckVoucher(name: 'Aktion', action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 1000)],
      );

  test('Storno mit Aktionsgutschein: Gesamt -24,30 = Rueckzahlung', () async {
    final r = stornoMitAktion();
    expect(r.sumCents, -2430);
    expect(r.sumCents, receiptDueCents(r.items, r.vouchers!, ReceiptType.cancellation));
    final zeilen = await gedruckt(r);
    expect(zeilen.firstWhere((z) => z.left == 'Gesamt:').right, '-24,30 EUR');
    expect(zeilen.firstWhere((z) => z.left.contains('Aktion')).right, '');
  });
}
