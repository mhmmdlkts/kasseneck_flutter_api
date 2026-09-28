import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/pos.dart' show ReceiptSummary, PosSettings, CheckoutState, CartItemDraft, VatRate, Cart, cashPayment, checkoutTotals;
import 'package:kasseneck_api/kasseneck_api.dart' show KeckPayment, KeckPaymentInput, isPaymentErrorCode, paymentErrorCodes, paymentsError;
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/printer_service.dart';

import 'helpers/test_receipts.dart';

/// Mehrere Zahlungen je Beleg — Zwilling von `models/receipt-payment.ts`,
/// `models/payment-errors.ts` und der Zahlungsregeln in `client/receipts.ts`.

const _sumup = {
  'cardType': 'MASTERCARD',
  'cardLastDigits': '4720',
  'paymentType': 'CONTACTLESS',
  'amount': 2000,
  'currency': 'EUR',
  'transactionCode': 'TEZBA9K7QK',
  'entryMode': 'contactless',
};

const _hobex = {
  'date': '25.09.2026 10:15',
  'tid': 'T1',
  'no': '17',
  'type': 'Verkauf',
  'cardBrand': 'VISA',
  'cardNumber': '4111******1111',
  'responseCode': '0',
};

Map<String, dynamic> _kartenzahlung(String provider, Map<String, dynamic> daten, {String id = 'p1', int betrag = 2000}) => {
      'id': id,
      'method': 'creditCard',
      'amountCents': betrag,
      'provider': provider,
      'providerPaymentId': 'X-$id',
      'providerData': daten,
    };

/// Beleg in der Antwortgestalt, die `fromJson` liest.
KasseneckReceipt _beleg(Map<String, dynamic> felder, {Map<String, dynamic>? layout}) {
  final roh = buildReceipt().toJson();
  return KasseneckReceipt.fromJson({
    ...roh,
    'receipt': {...(roh['receipt'] as Map<String, dynamic>), ...felder},
    'layout': ?layout,
  });
}

ReceiptLayout _layoutMit(List<String> texte) => ReceiptLayout.fromJson({
      'paperSize': 'mm80',
      'ruleset': 2,
      'lines': [
        for (final t in texte) {'kind': 'text', 'text': t, 'align': 'center', 'bold': false},
      ],
    })!;

Future<String> _gedruckt(KasseneckReceipt receipt) async {
  final paper = await KeckPrinterService.getPaperFromReceipt(receipt, KeckPaperSize.mm80);
  return latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
}

void main() {
  group('Zahlungsart mixed', () {
    test('Enum: Wert mixed, keine Karte, Label wie im Backend', () {
      expect(KeckPaymentMethod.mixed.name, 'mixed');
      expect(KeckPaymentMethod.mixed.needsCreditCard, isFalse);
      expect(KeckPaymentMethod.mixed.label, 'Mehrere Zahlungsarten');
    });

    test('der Beleg liest mixed als mixed -- unbekannte Werte fallen weiter auf cash', () {
      expect(_beleg({'paymentMethod': 'mixed'}).paymentMethod, KeckPaymentMethod.mixed);
      expect(_beleg({'paymentMethod': 'tauschhandel'}).paymentMethod, KeckPaymentMethod.cash);
    });

    test('die Belegliste liest mixed als mixed und nimmt die Zahlungen mit', () {
      final z = ReceiptSummary.fromJson({
        'receiptId': 'K-1',
        'paymentMethod': 'mixed',
        'payments': [
          {'id': 'p1', 'method': 'creditCard', 'amountCents': 2000, 'provider': 'sumup'},
          {'id': 'p2', 'method': 'cash', 'amountCents': 500, 'tenderedCents': 1000, 'changeCents': 500},
        ],
      });
      expect(z.paymentMethod, KeckPaymentMethod.mixed);
      expect(z.payments!.length, 2);
      expect(z.payments![1].changeCents, 500);
      expect(ReceiptSummary.fromJson({'paymentMethod': 'zauberei'}).paymentMethod, KeckPaymentMethod.cash);
      expect(ReceiptSummary.fromJson({'paymentMethod': 'cash'}).payments, isNull);
    });
  });

  group('KeckPayment lesen', () {
    test('nur vorhandene Felder, nichts ergaenzt', () {
      final p = KeckPayment.fromJson({
        'id': 'p3',
        'method': 'cash',
        'amountCents': 1045,
        'tenderedCents': 2000,
        'changeCents': 955,
        'tipCents': 45,
      });
      expect(p.id, 'p3');
      expect(p.method, KeckPaymentMethod.cash);
      expect(p.amountCents, 1045);
      expect(p.tenderedCents, 2000);
      expect(p.changeCents, 955);
      expect(p.tipCents, 45);
      expect(p.provider, isNull);
      expect(p.providerData, isNull);
      expect(p.refundOf, isNull);
      expect(p.toJson(), {'id': 'p3', 'method': 'cash', 'amountCents': 1045, 'tenderedCents': 2000, 'changeCents': 955, 'tipCents': 45});
    });

    test('Karte samt Anbieter und Terminaldaten; unbekannte Werte bleiben roh erhalten', () {
      final p = KeckPayment.fromJson(_kartenzahlung('sumup', _sumup));
      expect(p.method, KeckPaymentMethod.creditCard);
      expect(p.provider, CreditCardProvider.sumup);
      expect(p.providerPaymentId, 'X-p1');
      expect(p.providerData, _sumup);

      final fremd = KeckPayment.fromJson({'method': 'tauschhandel', 'amountCents': 1, 'provider': 'neuland'});
      expect(fremd.method, isNull);
      expect(fremd.provider, isNull);
      expect(fremd.toJson(), {'method': 'tauschhandel', 'amountCents': 1, 'provider': 'neuland'});
    });

    test('Storno: negativer Betrag und refundOf', () {
      final p = KeckPayment.fromJson({'id': 'p1', 'method': 'cash', 'amountCents': -500, 'refundOf': 'p2'});
      expect(p.amountCents, -500);
      expect(p.refundOf, 'p2');
    });

    test('der Beleg traegt payments, Altbelege nicht; toReceiptJson gibt sie zurueck', () {
      final b = _beleg({
        'paymentMethod': 'mixed',
        'payments': [
          _kartenzahlung('sumup', _sumup),
          {'id': 'p2', 'method': 'cash', 'amountCents': 500},
        ],
      });
      expect(b.payments!.length, 2);
      expect(b.payments!.first.provider, CreditCardProvider.sumup);
      expect((b.toReceiptJson()['payments'] as List).length, 2);

      final alt = _beleg({'paymentMethod': 'cash'});
      expect(alt.payments, isNull);
      expect(alt.toReceiptJson().containsKey('payments'), isFalse);
      // payments: null gilt als fehlend
      expect(_beleg({'payments': null}).payments, isNull);
    });
  });

  group('KeckPaymentInput -- Formregeln wie npm gepruefteZahlungen', () {
    test('Nutzlast: nur gesetzte Felder, Enum-Namen als Drahtformat', () {
      expect(
        const KeckPaymentInput(
          method: KeckPaymentMethod.creditCard,
          amountCents: 2000,
          provider: CreditCardProvider.hobexHps,
          providerPaymentId: 'T-1',
          providerData: {'tid': 'T1'},
          tipCents: 200,
        ).toJson(),
        {
          'method': 'creditCard',
          'amountCents': 2000,
          'tipCents': 200,
          'provider': 'hobexHps',
          'providerPaymentId': 'T-1',
          'providerData': {'tid': 'T1'},
        },
      );
      expect(const KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, tenderedCents: 1000).toJson(),
          {'method': 'cash', 'amountCents': 500, 'tenderedCents': 1000});
    });

    test('Verkauf: gueltige Liste hat keinen Fehler', () {
      expect(
          paymentsError([
            const KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 2000, provider: CreditCardProvider.sumup, providerPaymentId: 'S-1'),
            const KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 1045, tenderedCents: 2000),
          ], cancellation: false),
          isNull);
      expect(paymentsError(const [], cancellation: false), isNull);
    });

    test('mixed wird nie gesendet', () {
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 100)], cancellation: false),
          contains('mixed'));
    });

    test('Betrag: am Verkauf > 0, am Storno < 0', () {
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 0)], cancellation: false),
          'Zahlung 1: amountCents muss eine ganze Zahl groesser als 0 sein.');
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1)], cancellation: false), isNotNull);
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 1)], cancellation: true),
          'Zahlung 1: amountCents muss eine ganze Zahl kleiner als 0 sein.');
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1)], cancellation: true), isNull);
    });

    test('tenderedCents: nur am Verkauf, mindestens der Betrag', () {
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, tenderedCents: 499)], cancellation: false),
          contains('tenderedCents'));
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, tenderedCents: 500)], cancellation: false), isNull);
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -500, tenderedCents: 500)], cancellation: true),
          contains('tenderedCents'));
    });

    test('tipCents > 0', () {
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, tipCents: 0)], cancellation: false),
          'Zahlung 1: tipCents muss eine ganze Zahl groesser als 0 sein.');
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, tipCents: 50)], cancellation: false), isNull);
    });

    test('providerPaymentId nicht leer', () {
      expect(
          paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 500, provider: CreditCardProvider.sumup, providerPaymentId: '')],
              cancellation: false),
          contains('providerPaymentId'));
    });

    test('refundOf nur am Storno und nicht leer', () {
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500, refundOf: 'p1')], cancellation: false),
          contains('refundOf'));
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -500, refundOf: '')], cancellation: true),
          contains('refundOf'));
      expect(paymentsError(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -500, refundOf: 'p1')], cancellation: true), isNull);
    });

    test('hoechstens 20 Zahlungen; die Nummer im Fehler zaehlt ab 1', () {
      final viele = List.generate(21, (_) => const KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 1));
      expect(paymentsError(viele, cancellation: false), 'payments: es sind hoechstens 20 Eintraege erlaubt.');
      expect(
          paymentsError(const [
            KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 1),
            KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 0),
          ], cancellation: false),
          startsWith('Zahlung 2:'));
    });
  });

  group('Fehlercodes', () {
    test('beginnt mit den 18 Codes der Zahlungen, klein wie unter /v3 (Rest: receipt_v3_codes_test)', () {
      expect(paymentErrorCodes.take(18), [
        'payments_invalid',
        'payment_method_invalid',
        'payment_amount_invalid',
        'payment_tendered_invalid',
        'payment_provider_invalid',
        'payment_provider_not_allowed',
        'payments_sum_mismatch',
        'payments_due_negative',
        'payments_not_allowed',
        'payments_conflict',
        'payments_required',
        'payment_method_not_supported',
        'tip_payment_method_invalid',
        'tip_payment_method_required',
        'tip_exceeds_payment',
        'payment_refund_not_allowed',
        'payment_tip_invalid',
        'tip_conflict',
      ]);
    });

    test('istZahlungFehlercode: exakt klein (/v3), kein grosser /v1-Code, kein Anzeigetext, kein null', () {
      expect(isPaymentErrorCode('payments_sum_mismatch'), isTrue);
      expect(isPaymentErrorCode('PAYMENTS_SUM_MISMATCH'), isFalse);
      expect(isPaymentErrorCode('Die Summe der Zahlungen stimmt nicht.'), isFalse);
      expect(isPaymentErrorCode(null), isFalse);
      expect(isPaymentErrorCode(7), isFalse);
    });
  });

  group('Kartenbloecke je Zahlung', () {
    test('mit Zahlungsliste: je Zahlung mit Anbieter und Daten ein Block, in Reihenfolge', () {
      final b = _beleg({
        'paymentMethod': 'creditCard',
        'payments': [
          _kartenzahlung('hobexHps', _hobex, id: 'p1'),
          _kartenzahlung('hobexHps', {..._hobex, 'no': '18'}, id: 'p2'),
          {'id': 'p3', 'method': 'cash', 'amountCents': 500},
        ],
      });
      final bloecke = b.cardPayments;
      expect(bloecke.length, 2);
      expect(bloecke.map((k) => k.provider), [CreditCardProvider.hobexHps, CreditCardProvider.hobexHps]);
      expect(bloecke.map((k) => k.data['no']), ['17', '18']);
      expect(bloecke.map((k) => k.paymentId), ['X-p1', 'X-p2']);
    });

    test('mit Zahlungsliste zaehlen die alten Einzelfelder nicht', () {
      final b = _beleg({
        'creditCardProvider': 'stripe',
        'cardPaymentData': {'cardBrand': 'visa'},
        'payments': [
          _kartenzahlung('sumup', _sumup, id: 'p1'),
          {'id': 'p2', 'method': 'cash', 'amountCents': 500},
        ],
      });
      expect(b.cardPayments.map((k) => k.provider), [CreditCardProvider.sumup]);
    });

    test('eine Zahlung ohne Terminaldaten neben gesetzten Altfeldern: der Altblock', () {
      final b = _beleg({
        'creditCardProvider': 'sumup',
        'cardPaymentId': 'alt-1',
        'cardPaymentData': _sumup,
        'payments': [
          {'id': 'p1', 'method': 'creditCard', 'amountCents': 2000, 'provider': 'sumup', 'providerPaymentId': 'S'},
        ],
      });
      expect(b.cardPayments.single.paymentId, 'alt-1');
    });

    test('ohne Liste: der bisherige Block aus den Einzelfeldern', () {
      final b = buildReceipt(paymentMethod: KeckPaymentMethod.creditCard, cardProvider: CreditCardProvider.sumup, cardPaymentData: _sumup, cardPaymentId: 'S-1');
      expect(b.cardPayments.single.provider, CreditCardProvider.sumup);
      expect(buildReceipt().cardPayments, isEmpty);
    });

    test('unbekannter Anbieter in der Liste bekommt keinen Block', () {
      final b = _beleg({
        'payments': [_kartenzahlung('neuland', _sumup), _kartenzahlung('sumup', _sumup, id: 'p2')],
      });
      expect(b.cardPayments.map((k) => k.provider), [CreditCardProvider.sumup]);
    });
  });

  group('layoutIstVollstaendig mit Zahlungsliste', () {
    final zweiKarten = {
      'paymentMethod': 'creditCard',
      'payments': [
        _kartenzahlung('sumup', _sumup, id: 'p1'),
        _kartenzahlung('hobexHps', _hobex, id: 'p2'),
      ],
    };

    test('jeder Anbieter-Kopf muss im Layout stehen', () {
      expect(_beleg(zweiKarten, layout: _layoutMit(['Sumup Beleg', 'Hobex Beleg']).toJsonForTest()).isLayoutComplete, isTrue);
      // Nur der erste Block -- so saehe ein Layout eines Pakets vor der Aufschluesselung aus.
      expect(_beleg(zweiKarten, layout: _layoutMit(['Sumup Beleg']).toJsonForTest()).isLayoutComplete, isFalse);
    });

    test('zwei Karten desselben Anbieters brauchen zwei Koepfe', () {
      final gleich = {
        'paymentMethod': 'creditCard',
        'payments': [
          _kartenzahlung('hobexHps', _hobex, id: 'p1'),
          _kartenzahlung('hobexHps', _hobex, id: 'p2'),
        ],
      };
      expect(_beleg(gleich, layout: _layoutMit(['Hobex Beleg']).toJsonForTest()).isLayoutComplete, isFalse);
      expect(_beleg(gleich, layout: _layoutMit(['Hobex Beleg', 'Hobex Beleg']).toJsonForTest()).isLayoutComplete, isTrue);
    });

    test('Altfelder allein bleiben wie bisher', () {
      final b = buildReceipt(paymentMethod: KeckPaymentMethod.creditCard, cardProvider: CreditCardProvider.sumup, cardPaymentData: _sumup)
        ..layout = _layoutMit(['Sumup Beleg']);
      expect(b.isLayoutComplete, isTrue);
      b.layout = _layoutMit(['nichts']);
      expect(b.isLayoutComplete, isFalse);
    });
  });

  group('Rueckfall-Bauer (ohne Layout)', () {
    test('Bon: Label der Zahlungsart und je Zahlung ein Kartenblock, in Reihenfolge', () async {
      final b = _beleg({
        'paymentMethod': 'mixed',
        'payments': [
          _kartenzahlung('sumup', _sumup, id: 'p1'),
          _kartenzahlung('hobexHps', _hobex, id: 'p2'),
          {'id': 'p3', 'method': 'cash', 'amountCents': 500},
        ],
      });
      final text = await _gedruckt(b);
      expect(text, contains('Mehrere Zahlungsarten'));
      final sumup = text.indexOf('Sumup Beleg');
      final hobex = text.indexOf('Hobex Beleg');
      expect(sumup, greaterThan(0));
      expect(hobex, greaterThan(sumup));
    });

    test('Bon: zwei Karten desselben Anbieters, keiner verschluckt', () async {
      final b = _beleg({
        'paymentMethod': 'creditCard',
        'payments': [
          _kartenzahlung('hobexHps', _hobex, id: 'p1'),
          _kartenzahlung('hobexHps', {..._hobex, 'tid': 'T2'}, id: 'p2'),
        ],
      });
      final text = await _gedruckt(b);
      expect('Hobex Beleg'.allMatches(text).length, 2);
    });
  });

  group('Kassierrechnung -> Barzahlung', () {
    final betrieb = PosSettings.fromJson({'betrieb': {}}).business;
    Cart korb(int cents) => const Cart.empty().added(
          CartItemDraft(name: 'Ware', unitPriceCents: cents, vatRate: VatRate.vat20),
        );

    test('bar mit Gegebenem: tenderedCents geht mit', () {
      final r = checkoutTotals(korb(1045), betrieb, const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 2000));
      expect(cashPayment(r).toJson(), {'method': 'cash', 'amountCents': 1045, 'tenderedCents': 2000});
    });

    test('ohne oder mit zu wenig Gegebenem: kein tenderedCents', () {
      final ohne = checkoutTotals(korb(1045), betrieb, const CheckoutState(paymentMethod: KeckPaymentMethod.cash));
      expect(cashPayment(ohne).toJson(), {'method': 'cash', 'amountCents': 1045});
      final wenig = checkoutTotals(korb(1045), betrieb, const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 1000));
      expect(cashPayment(wenig).tenderedCents, isNull);
    });

    test('Restbetrag nach Karten: gegeben gilt gegen den Rest', () {
      final r = checkoutTotals(korb(4545), betrieb, const CheckoutState(paymentMethod: KeckPaymentMethod.cash, tenderedCents: 2000));
      final p = cashPayment(r, amountCents: 1045);
      expect(p.toJson(), {'method': 'cash', 'amountCents': 1045, 'tenderedCents': 2000});
    });
  });
}

extension on ReceiptLayout {
  /// Rohgestalt fuer `fromJson` -- nur Textzeilen, wie [_layoutMit] sie baut.
  Map<String, dynamic> toJsonForTest() => {
        'paperSize': 'mm80',
        'ruleset': 2,
        'lines': [
          for (final z in lines.whereType<LayoutTextLine>()) {'kind': 'text', 'text': z.text, 'align': 'center', 'bold': false},
        ],
      };
}
