import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/src/receipt/due.dart';

/// Pfand und Leergut im Korb (11.23.0): abgeleitete Pfandzeilen unter ihrer
/// Position, Leergut als Korbzeile, Zahlbetrag mit beidem. Die Artikel,
/// Pfandarten und Betraege kommen aus dem Vertrag (`deposit-cases.json`), der
/// Zahlbetrag wird gegen `receiptDueCents` (den Zwilling des Servers) geprueft.

Map<String, dynamic> _map(Object? w) => (w as Map).cast<String, dynamic>();

final _eingabe = _map(_map((jsonDecode(File('test/fixtures/vertrag/deposit-cases.json').readAsStringSync()) as Map)['cases'][0])['input']);

DepositPreviewContext _kontext({bool vorOrt = false, Map<String, DepositType>? arten}) => DepositPreviewContext(
      articles: {for (final e in _map(_eingabe['articles']).entries) e.key: PosArticle.fromJson(_map(e.value))},
      groups: {for (final e in _map(_eingabe['groups']).entries) e.key: ArticleGroup.fromJson(_map(e.value))},
      depositTypes: arten ?? {for (final e in _map(_eingabe['depositTypes']).entries) e.key: DepositType.fromJson(e.value)!},
      day: _eingabe['day'] as String,
      onPremises: vorOrt,
      cashRegister: CashRegisterDeposit.fromJson(_eingabe['cashRegister']),
    );

final _art = {for (final e in _map(_eingabe['depositTypes']).entries) e.key: DepositType.fromJson(e.value)!};

Cart _korb(List<(String name, int cents, String? article, int qty)> zeilen) {
  var korb = const Cart.empty();
  for (final z in zeilen) {
    korb = korb.added(CartItemDraft(name: z.$1, unitPriceCents: z.$2, vatRate: VatRate.vat20, articleId: z.$3));
    if (z.$4 != 1) korb = korb.withQuantity(korb.items.last.id, z.$4);
  }
  return korb;
}

List<String> _namen(List<CartLine> zeilen) => [for (final z in zeilen) '${z.derived ? '+' : ''}${z.quantity}x ${z.item.name}'];

void main() {
  final business = const PosBusinessSettings();
  final bar = CheckoutState(paymentMethod: KeckPaymentMethod.cash);

  group('Korbzeilen mit Pfand', () {
    test('Dose x6 und Bier: drei Pfandzeilen, jede direkt unter ihrer Position', () {
      final korb = _korb([('Dose', 120, 'dose', 6), ('Bier Kiste', 1800, 'bier', 1)]);
      final zeilen = korb.lines(PosQuantity.x, deposit: _kontext());
      expect(_namen(zeilen), ['6x Dose', '+6x Pfand Einweg', '1x Bier Kiste', '+1x Pfand Kiste', '+20x Pfand Flasche']);
      expect([for (final z in zeilen) z.amountCents], [720, 150, 1800, 300, 400]);
      expect([for (final z in zeilen) z.item.depositOf], [null, korb.items[0].id, null, korb.items[1].id, korb.items[1].id]);
    });

    test('Menge aendern aendert das Pfand, Loeschen der Position loescht es', () {
      var korb = _korb([('Dose', 120, 'dose', 6)]);
      korb = korb.withQuantity(korb.items.single.id, 10);
      expect(_namen(korb.lines(PosQuantity.x, deposit: _kontext())), ['10x Dose', '+10x Pfand Einweg']);
      expect(korb.lines(PosQuantity.x, deposit: _kontext()).last.amountCents, 250);
      korb = korb.removed(korb.items.single.id);
      expect(korb.lines(PosQuantity.x, deposit: _kontext()), isEmpty);
    });

    test('die Pfandzeile selbst ist nicht aenderbar und nicht loeschbar', () {
      final korb = _korb([('Dose', 120, 'dose', 6)]);
      final pfand = korb.lines(PosQuantity.x, deposit: _kontext()).last;
      expect(pfand.derived, isTrue);
      expect(identical(korb.withQuantity(pfand.item.id, 1), korb), isTrue);
      expect(identical(korb.removed(pfand.item.id), korb), isTrue);
      expect(korb.items, hasLength(1));
    });

    test('ein Zusatz steht vor dem Pfand der Hauptposition; sein eigenes Pfand direkt unter ihm', () {
      var korb = _korb([('Dose', 120, 'dose', 2)]);
      korb = korb.added(CartItemDraft(name: 'Eis', unitPriceCents: 50, vatRate: VatRate.vat20, articleId: 'brot', addOnOf: korb.items.first.id));
      korb = korb.added(CartItemDraft(name: 'Bier Zusatz', unitPriceCents: 300, vatRate: VatRate.vat20, articleId: 'bier', addOnOf: korb.items.first.id));
      expect(_namen(korb.lines(PosQuantity.x, deposit: _kontext())),
          ['2x Dose', '1x Eis', '1x Bier Zusatz', '+1x Pfand Kiste', '+20x Pfand Flasche', '+2x Pfand Einweg']);
    });

    test('Mengenmodus aus: auch das Pfand je Stueck', () {
      final korb = _korb([('Dose', 120, 'dose', 3)]);
      final zeilen = korb.lines(PosQuantity.off, deposit: _kontext());
      expect(zeilen.map((z) => z.amountCents), [120, 120, 120, 25, 25, 25]);
      expect(zeilen.where((z) => z.derived), hasLength(3));
    });

    test('Einweg entfaellt vor Ort; ohne Kontext zeigt der Korb kein Pfand (wie bisher)', () {
      final korb = _korb([('Dose', 120, 'dose', 6)]);
      expect(_namen(korb.lines(PosQuantity.x, deposit: _kontext(vorOrt: true))), ['6x Dose']);
      expect(_namen(korb.lines(PosQuantity.x)), ['6x Dose']);
      expect(_namen(korb.lines(PosQuantity.off)), hasLength(6));
      expect(korb.totalCents, 720);
    });

    test('Artikel ohne Pfand und freie Positionen bleiben unberuehrt', () {
      final korb = _korb([('Brot', 350, 'brot', 2), ('Freie Position', 100, null, 1)]);
      final zeilen = korb.lines(PosQuantity.x, deposit: _kontext());
      expect(zeilen.map((z) => z.derived), [false, false]);
    });
  });

  group('Kassieren mit Pfand', () {
    // Der Zahlbetrag des Servers: alle Zeilen (Ware, Pfand, Leergut) durch den Zwilling.
    int serverBetrag(Cart korb, int rabatt, DepositPreviewContext k) {
      final pfand = korb.deposits(k).all.map((p) => p.toReceiptItem());
      return receiptDueCents([...receiptItems(korb, rabatt), ...pfand], const [], ReceiptType.standard);
    }

    test('Zahlbetrag mit Pfand = Zahlbetrag des Servers', () {
      final korb = _korb([('Dose', 120, 'dose', 6), ('Bier Kiste', 1800, 'bier', 1)]);
      final k = _kontext();
      final t = checkoutTotals(korb, business, bar, deposit: k);
      expect(t.subtotalCents, 2520);
      expect(t.depositCents, 850);
      expect(t.dueCents, 3370);
      expect(t.dueCents, serverBetrag(korb, 0, k));
      // Ohne Kontext zaehlt nur die Ware.
      expect(checkoutTotals(korb, business, bar).dueCents, 2520);
    });

    test('Belegrabatt 10 Prozent trifft das Pfand nie', () {
      final korb = _korb([('Dose', 120, 'dose', 6), ('Bier Kiste', 1800, 'bier', 1)]);
      final k = _kontext();
      final rabatt = discountCentsFor(DiscountKind.percent, 10, korb.goodsCents)!;
      expect(rabatt, 252);
      final t = checkoutTotals(korb, business, bar.copyWith(discountCents: rabatt), deposit: k);
      expect(t.discountCents, 252);
      expect(t.dueCents, 2520 - 252 + 850);
      expect(t.dueCents, serverBetrag(korb, 252, k));
      // Die Rabattzeilen rechnen nur auf die Ware.
      final rabattZeilen = receiptItems(korb, 252).where((i) => i.isDiscount);
      expect(rabattZeilen.fold<int>(0, (s, i) => s + i.totalCents), -252);
    });

    test('receiptItems: Pfand bucht der Server (nicht in der Liste), Leergut reist mit', () {
      var korb = _korb([('Dose', 120, 'dose', 6)]);
      korb = korb.addedReturn(_art['flasche']!, 4, day: _eingabe['day'] as String, smallBusiness: false);
      final items = receiptItems(korb, 0);
      expect(items.map((i) => i.kind), [null, 'deposit_return']);
      expect(items.last.depositTypeId, 'flasche');
      expect(items.last.quantity, 4);
      expect(items.last.priceCents, -20);
      expect(items.last.toJson()['kind'], 'deposit_return');
    });

    test('Fehler der Vorschau sperren das Kassieren mit dem Satz zum Code', () {
      final korb = _korb([('Dose', 120, 'dose', 6)]);
      final t = checkoutTotals(korb, business, bar, deposit: _kontext(arten: {}));
      expect(t.depositCode, 'deposit_type_not_found');
      expect(t.ready, isFalse);
      expect(t.reason, depositErrorMessage('deposit_type_not_found'));
      expect(t.depositCents, 0);
    });
  });

  group('Leergut im Korb', () {
    final tag = _eingabe['day'] as String;

    test('Leergut verrechnet sich mit dem Einkauf (wie der Server)', () {
      var korb = _korb([('Bier', 1000, null, 1)]);
      korb = korb.addedReturn(_art['flasche']!, 2, day: tag, smallBusiness: false);
      final k = _kontext();
      final t = checkoutTotals(korb, business, bar, deposit: k);
      expect(t.returnCents, -40);
      expect(t.dueCents, 960);
      expect(t.payoutCents, 0);
      expect(t.dueCents, receiptDueCents(receiptItems(korb, 0), const [], ReceiptType.standard));
      // Auch ohne Kontext zaehlt das Leergut.
      expect(checkoutTotals(korb, business, bar).dueCents, 960);
    });

    test('nur Leergut: negativer Betrag, Barauszahlung, kein Trinkgeld, bereit', () {
      var korb = const Cart.empty();
      korb = korb.addedReturn(_art['flasche']!, 2, day: tag, smallBusiness: false);
      korb = korb.addedReturn(_art['einweg']!, 10, day: tag, smallBusiness: false);
      final t = checkoutTotals(korb, const PosBusinessSettings(tip: true), bar.copyWith(tipCents: 100));
      expect(t.dueCents, -290);
      expect(t.payoutCents, 290);
      expect(t.tipCents, 0);
      expect(t.totalCents, -290);
      expect(t.ready, isTrue);
      expect(t.dueCents, receiptDueCents(receiptItems(korb, 0), const [], ReceiptType.standard));
      expect(cashPayment(t).amountCents, -290);
      expect(amountDue(korb, 0), -290);
    });

    test('der Belegrabatt trifft das Leergut nie und reicht nur ueber die Ware', () {
      var korb = _korb([('Bier', 1000, null, 1)]);
      korb = korb.addedReturn(_art['flasche']!, 5, day: tag, smallBusiness: false);
      final t = checkoutTotals(korb, business, bar.copyWith(discountCents: 5000));
      expect(t.discountCents, 1000);
      expect(t.dueCents, -100);
      expect(t.payoutCents, 100);
    });

    test('+/- und Loeschen: Menge aendern, auf null faellt die Zeile; gleiche Pfandart addiert sich', () {
      var korb = const Cart.empty();
      korb = korb.addedReturn(_art['flasche']!, 2, day: tag, smallBusiness: false, codes: {'4006381333931': 2});
      final id = korb.items.single.id;
      expect(korb.items.single.codes, {'4006381333931': 2});
      korb = korb.withQuantity(id, 3);
      expect(korb.items.single.quantity, 3);
      expect(korb.items.single.codes, isNull, reason: 'gelernte Codes gelten nur fuer ihre Menge');
      korb = korb.addedReturn(_art['flasche']!, 2, day: tag, smallBusiness: false);
      expect(korb.items, hasLength(1));
      expect(korb.items.single.quantity, 5);
      expect(() => korb.addedReturn(_art['flasche']!, 999, day: tag, smallBusiness: false), throwsStateError, reason: '5 + 999 wird nicht still gekappt');
      expect(korb.items.single.quantity, 5, reason: 'der Korb bleibt unveraendert');
      korb = korb.withQuantity(id, 1001);
      expect(korb.items.single.quantity, 1000, reason: 'hoechstens 1000 Stueck');
      expect(korb.hasReturns, isTrue);
      korb = korb.withQuantity(id, 0);
      expect(korb.isEmpty, isTrue);
    });

    test('Grenze 1000: genau 1000 einzeln ok, 1 + 999 mit Codes ok, darueber abgelehnt', () {
      final einzeln = const Cart.empty().addedReturn(_art['flasche']!, 1000, day: tag, smallBusiness: false);
      expect(einzeln.items.single.quantity, 1000);
      expect(() => const Cart.empty().addedReturn(_art['flasche']!, 1001, day: tag, smallBusiness: false), throwsStateError);
      var korb = const Cart.empty().addedReturn(_art['flasche']!, 1, day: tag, smallBusiness: false, codes: {'4006381333931': 1});
      korb = korb.addedReturn(_art['flasche']!, 999, day: tag, smallBusiness: false, codes: {'4006381333931': 999});
      expect(korb.items.single.quantity, 1000);
      expect(korb.items.single.codes, {'4006381333931': 1000});
      expect(() => korb.addedReturn(_art['flasche']!, 1, day: tag, smallBusiness: false), throwsStateError);
      expect(korb.items.single.quantity, 1000);
    });

    test('Leergut ohne Betrag am Tag oder mit unmoeglicher Menge gibt es nicht', () {
      expect(() => const Cart.empty().addedReturn(_art['flasche']!, 0, day: tag, smallBusiness: false), throwsStateError);
      expect(() => const Cart.empty().addedReturn(_art['flasche']!, 1, day: '2020-01-01', smallBusiness: false), throwsStateError);
    });

    test('Leergut ist keine Pfand-Ableitung: die Vorschau fasst es nicht an', () {
      var korb = const Cart.empty();
      korb = korb.addedReturn(_art['flasche']!, 2, day: tag, smallBusiness: false);
      final zeilen = korb.lines(PosQuantity.x, deposit: _kontext());
      expect(zeilen.single.isReturn, isTrue);
      expect(zeilen.single.derived, isFalse);
      expect(zeilen.single.amountCents, -40);
    });
  });
}
