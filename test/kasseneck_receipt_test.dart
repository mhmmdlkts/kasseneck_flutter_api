import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/kasse.dart' show KasseneckReceiptFormatError;
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import 'helpers/test_receipts.dart';

void main() {
  group('JSON-Roundtrip (kompletter Beleg)', () {
    test('toJson -> fromJson erhaelt alle Felder', () {
      final original = cartB()
        ..customerDetails = ['Max Mustermann', 'Zeile 2']
        ..legalMessage = ['Fahrzeug: W-1', 'Toyota']
        ..cardPaymentId = 'TX-1'
        ..creditCardProvider = CreditCardProvider.hobexHps
        ..cardPaymentData = {'tid': '123', 'cardNumber': '****1234'}
        ..signatureSuccess = true;

      final back = KasseneckReceipt.fromJson(original.toJson());

      expect(back.receiptId, original.receiptId);
      expect(back.cashregisterId, original.cashregisterId);
      // timeStamp ist ein Zeitpunkt (UTC-Instant) — der Roundtrip erhält den
      // Zeitpunkt, nicht das DateTime-Flag des Eingabewerts.
      expect(back.timeStamp, original.timeStamp.toUtc());
      expect(back.receiptType, original.receiptType);
      expect(back.paymentMethod, original.paymentMethod);
      expect(back.sig, original.sig);
      expect(back.qr, original.qr);
      expect(back.turnoverCounterAES256ICM, original.turnoverCounterAES256ICM);
      expect(back.signaturePreviousReceipt, original.signaturePreviousReceipt);
      expect(back.certificateSerialNumber, original.certificateSerialNumber);
      expect(back.fullReceiptId, original.fullReceiptId);
      expect(back.companyName, original.companyName);
      expect(back.phone, original.phone);
      expect(back.isSmallBusiness, original.isSmallBusiness);
      expect(back.uid, original.uid);
      expect(back.taxnr, original.taxnr);
      expect(back.street, original.street);
      expect(back.zip, original.zip);
      expect(back.city, original.city);
      expect(back.footer1, original.footer1);
      expect(back.footer2, original.footer2);
      expect(back.customerDetails, original.customerDetails);
      expect(back.legalMessage, original.legalMessage);
      expect(back.cardPaymentId, original.cardPaymentId);
      expect(back.creditCardProvider, original.creditCardProvider);
      expect(back.cardPaymentData, original.cardPaymentData);
      expect(back.signatureSuccess, original.signatureSuccess);
      // Geld: identische Cents nach Roundtrip
      expect(back.items.length, original.items.length);
      for (int i = 0; i < back.items.length; i++) {
        expect(back.items[i].priceCents, original.items[i].priceCents);
        expect(back.items[i].quantity, original.items[i].quantity);
        expect(back.items[i].vat, original.items[i].vat);
      }
      expect(back.vouchers!.length, original.vouchers!.length);
      for (int i = 0; i < back.vouchers!.length; i++) {
        expect(back.vouchers![i].valueCents, original.vouchers![i].valueCents);
      }
      expect(back.sumCents, original.sumCents);
      expect(back.subSumCents, original.subSumCents);
    });

    test('ueber jsonEncode/jsonDecode (echte Serialisierung)', () {
      final original = cartA();
      final back = KasseneckReceipt.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(back.sumCents, 6086);
    });
  });

  group('fromJson-Fallbacks (Robustheit gegen Backend-Aenderungen)', () {
    Map<String, dynamic> baseJson() => cartA().toJson();

    test('unbekannte paymentMethod -> cash', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['paymentMethod'] = 'bitcoin';
      expect(KasseneckReceipt.fromJson(j).paymentMethod, KeckPaymentMethod.cash);
    });
    test('unbekannter receiptType -> standard', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['receiptType'] = 'xyz';
      expect(KasseneckReceipt.fromJson(j).receiptType, ReceiptType.standard);
    });
    test('unbekannter creditCardProvider -> custom (kein Crash)', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['creditCardProvider'] = 'neuerAnbieter2030';
      expect(KasseneckReceipt.fromJson(j).creditCardProvider, CreditCardProvider.custom);
    });
    test('fehlende fullReceiptId -> leer', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>).remove('fullReceiptId');
      expect(KasseneckReceipt.fromJson(j).fullReceiptId, '');
    });
    test('Nullbeleg ohne items parst', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['items'] = null;
      (j['receipt'] as Map<String, dynamic>)['vouchers'] = null;
      final r = KasseneckReceipt.fromJson(j);
      expect(r.items, isEmpty);
      expect(r.sumCents, 0);
    });
    test('customerDetails/legalMessage: null -> leere Liste, mehrzeilig -> Split', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['customerDetails'] = null;
      (j['receipt'] as Map<String, dynamic>)['legalMessage'] = 'Zeile1\nZeile2';
      final r = KasseneckReceipt.fromJson(j);
      expect(r.customerDetails, isEmpty);
      expect(r.legalMessage, ['Zeile1', 'Zeile2']);
    });
  });

  group('Antwort unvollstaendig — der Beleg ist da, die Antwort nicht', () {
    // Der Beleg ist an dieser Stelle signiert und in der Kette. Ein roher
    // TypeError waere hier der schlimmste Fall: nicht von „Verkauf
    // fehlgeschlagen" zu unterscheiden, und mit der verworfenen Antwort ginge
    // die Kennung verloren — es bliebe nichts zum Nachholen.
    Map<String, dynamic> baseJson() => cartA().toJson();

    Matcher lesefehler(String feld, String? kennung) => isA<KasseneckReceiptFormatError>()
        .having((e) => e.field, 'field', feld)
        .having((e) => e.receiptId, 'receiptId', kennung);

    for (final feld in [
      'qr',
      'sig',
      'certificateSerialNumber',
      'signaturePreviousReceipt',
      'turnoverCounterAES256ICM',
      'cashregisterId',
      'timeStamp',
    ]) {
      test('fehlendes $feld: benannter Fehler MIT Kennung, kein TypeError', () {
        final j = baseJson();
        (j['receipt'] as Map<String, dynamic>).remove(feld);
        expect(() => KasseneckReceipt.fromJson(j), throwsA(lesefehler(feld, 'TEST-ID-1')));
      });

      test('$feld mit falschem Typ: ebenso', () {
        final j = baseJson();
        (j['receipt'] as Map<String, dynamic>)[feld] = 42;
        expect(() => KasseneckReceipt.fromJson(j), throwsA(lesefehler(feld, 'TEST-ID-1')));
      });
    }

    test('unlesbarer timeStamp wird zum Lesefehler, nicht zur FormatException', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>)['timeStamp'] = 'kein Datum';
      expect(() => KasseneckReceipt.fromJson(j), throwsA(lesefehler('timeStamp', 'TEST-ID-1')));
    });

    test('fehlende receiptId: der Faden ist ab — und das steht im Fehler', () {
      final j = baseJson();
      (j['receipt'] as Map<String, dynamic>).remove('receiptId');
      expect(() => KasseneckReceipt.fromJson(j), throwsA(lesefehler('receiptId', null)));
    });

    test('kein receipt-Objekt: Fehler ohne Kennung', () {
      expect(() => KasseneckReceipt.fromJson({'receipt': null}),
          throwsA(lesefehler('receipt', null)));
      expect(() => KasseneckReceipt.fromJson({'receipt': <dynamic>[]}),
          throwsA(lesefehler('receipt', null)));
    });

    test('Kopf- und Fusszeilen duerfen fehlen — dafuer wird kein Beleg verworfen', () {
      // Rein darstellend: null und '' drucken gleich. Einen signierten Beleg
      // wegen einer fehlenden Fusszeile zu verlieren waere die teurere
      // Verwechslung.
      final j = baseJson()
        ..remove('taxnr')
        ..remove('company')
        ..remove('phone')
        ..remove('street')
        ..remove('zip')
        ..remove('city')
        ..remove('footer1')
        ..remove('footer2')
        ..remove('is_small_business');

      final r = KasseneckReceipt.fromJson(j);
      expect(r.receiptId, 'TEST-ID-1');
      expect(r.taxnr, '');
      expect(r.companyName, '');
      expect(r.footer1, '');
      expect(r.isSmallBusiness, isFalse);
    });

    group('Pflichtangaben nach § 132a Abs. 3 BAO', () {
      test('fehlende Firma ist ein Mangel — der Beleg bleibt trotzdem erhalten', () {
        // Z 1 verlangt die eindeutige Bezeichnung des leistenden
        // Unternehmers. Bis hierher entstand daraus stumm ein Pflichtbeleg
        // mit leerer erster Zeile. Werfen ist keine Antwort: der Beleg ist
        // signiert und in der Kette.
        final r = KasseneckReceipt.fromJson(baseJson()..remove('company'));

        expect(r.receiptId, 'TEST-ID-1', reason: 'der Beleg kommt heraus');
        expect(r.fehlendePflichtangaben, ['company']);
        expect(r.pflichtangabenVollstaendig, isFalse);
      });

      test('eine Firma aus lauter Leerzeichen zaehlt nicht als Bezeichnung', () {
        final r = KasseneckReceipt.fromJson(baseJson()..['company'] = '   ');
        expect(r.fehlendePflichtangaben, ['company']);
      });

      test('falsch getippte Firma ebenso', () {
        final r = KasseneckReceipt.fromJson(baseJson()..['company'] = 42);
        expect(r.fehlendePflichtangaben, ['company']);
      });

      test('fromMetadata fuehrt dieselbe Pruefung', () {
        final receipt = baseJson()['receipt'] as Map<String, dynamic>;
        expect(KasseneckReceipt.fromMetadata(receipt, const {}).fehlendePflichtangaben, ['company']);
        expect(
            KasseneckReceipt.fromMetadata(receipt, {'company': 'Kasseneck Test GmbH'})
                .fehlendePflichtangaben,
            isEmpty);
      });

      test('ein vollstaendiger Beleg meldet keinen Mangel', () {
        expect(cartA().fehlendePflichtangaben, isEmpty);
        expect(cartA().pflichtangabenVollstaendig, isTrue);
      });

      test('Anschrift, Steuerangabe und Fusszeilen bleiben Zierde', () {
        // Auf einem Beleg sind sie keine Pflichtangaben — erst auf einer
        // Rechnung nach § 11 UStG. Ein Mangel hier wuerde jeden Beleg eines
        // Betriebs ohne Fusszeile als unvollstaendig melden.
        final j = baseJson()
          ..remove('taxnr')
          ..remove('street')
          ..remove('zip')
          ..remove('city')
          ..remove('footer1')
          ..remove('footer2');
        expect(KasseneckReceipt.fromJson(j).fehlendePflichtangaben, isEmpty);
      });
    });

    test('logo_url mit falschem Typ kippt den Beleg nicht', () {
      final j = baseJson()..['logo_url'] = 42;
      expect(KasseneckReceipt.fromJson(j).logoUrl, isNull);
    });

    test('fromMetadata: kaputte Metadaten kippen den Beleg nicht, kaputter Beleg schon', () {
      final receipt = baseJson()['receipt'] as Map<String, dynamic>;
      final r = KasseneckReceipt.fromMetadata(receipt, {'company': 7, 'is_small_business': 'ja'});
      expect(r.companyName, '');
      expect(r.isSmallBusiness, isFalse);

      expect(() => KasseneckReceipt.fromMetadata('kein Beleg', const {}),
          throwsA(lesefehler('receipt', null)));
    });
  });

  group('vatCategories', () {
    test('dedupliziert + Sell-Voucher ergaenzt 0%', () {
      final r = buildReceipt(
        items: [
          KasseneckItem(name: 'a', quantity: 1, vat: VatRate.vat20, priceCents: 100),
          KasseneckItem(name: 'b', quantity: 1, vat: VatRate.vat20, priceCents: 200),
        ],
        vouchers: [KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 500)],
      );
      expect(r.vatCategories, containsAll([VatRate.vat20, VatRate.vat0]));
      expect(r.vatCategories.length, 2);
    });
    test('INVALIDER Sell-Voucher ergaenzt KEIN 0%', () {
      final r = buildReceipt(
        items: [KasseneckItem(name: 'a', quantity: 1, vat: VatRate.vat20, priceCents: 100)],
        vouchers: [KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: null)],
      );
      expect(r.vatCategories, [VatRate.vat20]);
    });
  });

  group('Helfer & Vergleiche', () {
    test('compareTo: neueste zuerst', () {
      final alt = buildReceipt(timeStamp: DateTime(2026, 1, 1));
      final neu = buildReceipt(timeStamp: DateTime(2026, 6, 1));
      final list = [alt, neu]..sort();
      expect(list.first.timeStamp, neu.timeStamp);
    });
    test('== und hashCode nur ueber receiptId', () {
      final a = buildReceipt(timeStamp: DateTime(2026, 1, 1));
      final b = buildReceipt(timeStamp: DateTime(2026, 2, 2));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
    test('readableTime mit fuehrenden Nullen (Wiener Zeit)', () {
      // readableTime zeigt Wiener Wanduhrzeit — unabhängig von der Geräte-Zeitzone.
      final wien = ViennaTime.fromWallClock(DateTime(2026, 6, 1, 9, 5, 3));
      expect(buildReceipt(timeStamp: wien).readableTime, '01.06.2026 09:05:03');
    });
    test('taxInfo: UID bevorzugt, sonst Steuernummer', () {
      expect(buildReceipt(uid: 'ATU99999999').taxInfo, 'ATU99999999');
      expect(buildReceipt(uid: null).taxInfo, '12 345/6789');
      expect(buildReceipt(uid: '').taxInfo, '12 345/6789');
    });
    test('downloadUrl ist beleg-Domain mit Token im Pfad', () {
      expect(buildReceipt().downloadUrl, 'https://beleg.kasseneck.at/enc-full-id');
    });
  });

  group('isSigFailed (RKSV-Ausfallerkennung)', () {
    final damagedMarker = base64Encode(utf8.encode(RKSVService.signatureDeviceDamagedKey))
        .replaceAll('+', '-').replaceAll('/', '_').replaceAll(RegExp(r'=+$'), '');

    test('echte Signatur -> kein Ausfall', () {
      expect(buildReceipt(sig: 'h.p.echteSig').isSigFailed, isFalse);
    });
    test('Ausfall-Marker im 3. JWS-Segment -> Ausfall', () {
      expect(buildReceipt(sig: 'h.p.$damagedMarker').isSigFailed, isTrue);
    });
    test('RKSVService.isSigSuccess direkt', () {
      expect(RKSVService.isSigSuccess('h.p.$damagedMarker'), isFalse);
      expect(RKSVService.isSigSuccess('h.p.xyz'), isTrue);
    });
    test('eine Signatur ohne drei Teile stuerzt nicht ab, sondern gilt als nicht bestaetigt', () {
      // Sie kommt so nie vom Backend — aber wenn doch, darf der Belegbildschirm
      // nicht abstuerzen. Und „nicht pruefbar" ist naeher an „ausgefallen" als
      // an „in Ordnung".
      for (final kaputt in ['', 'sig', 'h.p', 'h..']) {
        expect(RKSVService.isSigSuccess(kaputt), isFalse, reason: 'sig=$kaputt');
      }
    });
  });
}
