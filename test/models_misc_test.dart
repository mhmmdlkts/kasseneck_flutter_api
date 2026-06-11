import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_invoice_payment_methode.dart';
import 'package:kasseneck_api/enums/keck_month.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/models/keck_invoice.dart';
import 'package:kasseneck_api/models/keck_user.dart';
import 'package:kasseneck_api/models/report_month.dart';
import 'package:kasseneck_api/models/stripe_url_seesion.dart';
import 'package:kasseneck_api/models/sumup_checkout_response.dart';

/// Firestore-Timestamp-Ersatz: alles mit toDate() wird akzeptiert (dynamic dispatch).
class FakeTimestamp {
  final DateTime dt;
  FakeTimestamp(this.dt);
  DateTime toDate() => dt;
}

void main() {
  group('ReportMonth', () {
    test('fromDateTime + toDateTime', () {
      final rm = ReportMonth.fromDateTime(DateTime(2026, 6, 15));
      expect(rm.month, KeckMonth.june);
      expect(rm.year, 2026);
      expect(rm.toDateTime(), DateTime(2026, 6));
    });
    test('previousMonth ueber Jahresgrenze: Jan -> Dez Vorjahr', () {
      final rm = const ReportMonth(KeckMonth.january, 2026).previousMonth();
      expect(rm.month, KeckMonth.december);
      expect(rm.year, 2025);
    });
    test('nextMonth ueber Jahresgrenze: Dez -> Jan Folgejahr', () {
      final rm = const ReportMonth(KeckMonth.december, 2026).nextMonth();
      expect(rm.month, KeckMonth.january);
      expect(rm.year, 2027);
    });
    test('previous/next sind invers', () {
      const rm = ReportMonth(KeckMonth.june, 2026);
      expect(rm.nextMonth().previousMonth(), rm);
    });
    test('== / readable / toString', () {
      expect(const ReportMonth(KeckMonth.may, 2026), const ReportMonth(KeckMonth.may, 2026));
      expect(const ReportMonth(KeckMonth.may, 2026).readable, 'Mai 2026');
      expect(const ReportMonth(KeckMonth.may, 2026).toString(), 'may_2026');
    });
  });

  group('KeckMonth / KeckPaperSize / ReceiptType (Enum-Kontrakte)', () {
    test('KeckMonth: 12 Monate, ids 1-12, deutsche Namen', () {
      expect(KeckMonth.values.length, 12);
      expect(KeckMonth.january.id, 1);
      expect(KeckMonth.december.id, 12);
      expect(KeckMonth.march.germanName, 'März');
    });
    test('KeckPaperSize: Vergleichsoperatoren + Kennzahlen', () {
      expect(KeckPaperSize.mm80 > KeckPaperSize.mm58, isTrue);
      expect(KeckPaperSize.mm80 >= KeckPaperSize.mm80, isTrue);
      expect(KeckPaperSize.mm58 < KeckPaperSize.mm80, isTrue);
      expect(KeckPaperSize.mm58.defaultCharCount, 32);
      expect(KeckPaperSize.mm80.defaultCharCount, 48);
    });
    test('ReceiptType-Matrix: needsItems/allowsVouchers', () {
      expect(ReceiptType.standard.needsItems, isTrue);
      expect(ReceiptType.standard.allowsVouchers, isTrue);
      expect(ReceiptType.cancellation.needsItems, isTrue);
      expect(ReceiptType.training.needsItems, isTrue);
      expect(ReceiptType.zero.needsItems, isFalse);
      expect(ReceiptType.zero.isZero, isTrue);
      expect(ReceiptType.start.needsItems, isFalse);
      expect(ReceiptType.start.allowsVouchers, isFalse);
    });
  });

  group('KeckInvoice', () {
    Map<String, dynamic> invoiceJson() => {
          'invoiceNumber': 'R-41',
          'invoiceDate': FakeTimestamp(DateTime(2026, 5, 16)),
          'serviceDateStart': FakeTimestamp(DateTime(2026, 5, 16)),
          'serviceDateEnd': null,
          'vatIncluded': true,
          'isTaxFree': false,
          'paymentMethod': 'bankTransferUnpaid',
          'company': 'taxi',
          'customerName': 'Nico',
          'customerPhone': '+43',
          'customerAddressStreetName': 'Strasse',
          'customerAddressStreetNumber': '2D',
          'customerAddressCountryCode': 'AT',
          'customerAddressZIP': '4020',
          'customerAddressCity': 'Linz',
          'payUntil': 10,
          'downloadUrl': 'https://x',
        };

    test('fromJson happy path', () {
      final inv = KeckInvoice.fromJson(invoiceJson());
      expect(inv.invoiceNumber, 'R-41');
      expect(inv.invoiceDate, DateTime(2026, 5, 16));
      expect(inv.serviceDateEnd, isNull);
      expect(inv.payUntil, 10);
      expect(inv.paymentMethod, KeckInvoicePaymentMethode.bankTransferUnpaid);
    });
    test('unbekannte paymentMethod -> bankTransferUnpaid-Fallback', () {
      final j = invoiceJson()..['paymentMethod'] = 'xyz';
      expect(KeckInvoice.fromJson(j).paymentMethod, KeckInvoicePaymentMethode.bankTransferUnpaid);
    });
    test('payUntil optional', () {
      final j = invoiceJson()..remove('payUntil');
      expect(KeckInvoice.fromJson(j).payUntil, isNull);
    });
  });

  group('KeckUser', () {
    Map<String, dynamic> userJson() => {
          'email': 'test@kreiseck.com',
          'company_name': 'Kreiseck',
          'phone': '+43',
          'create_time': FakeTimestamp(DateTime(2026, 1, 1)),
          'production': true,
          'api_key': 'key-123',
          'logo_url': null,
          'thanks_message': 'Danke',
          'metadata': {'cashregister_count': 2, 'signature_count': 1},
          'tax_details': {'is_small_business': false, 'taxnr': '12/345', 'uid': 'ATU1', 'gln': null},
          'webservice_user': {'benid': 'ben', 'tid': 'tid', 'pin': 'pin'},
          'address': {'city': 'Wien', 'street': 'Strasse', 'zip': '1010'},
          'footer': {'footer1': 'f1', 'footer2': 'f2', 'footer3': null, 'footer4': null},
        };

    test('fromJson happy path + receiptMetadata', () {
      final u = KeckUser.fromJson(userJson(), 'uid-1');
      expect(u.userId, 'uid-1');
      expect(u.isProduction, isTrue);
      expect(u.cashregisterCount, 2);
      expect(u.uid, 'ATU1');
      final meta = u.receiptMetadata();
      expect(meta['company'], 'Kreiseck');
      expect(meta['is_small_business'], false);
      expect(meta['footer1'], 'f1');
    });
    test('fehlendes webservice_user crasht (dokumentierte Fragilitaet)', () {
      // null['benid'] -> NoSuchMethodError. Bei einer kuenftigen Haertung von
      // KeckUser.fromJson auf null-sichere Zugriffe darf dieser Test kippen.
      final j = userJson()..remove('webservice_user');
      expect(() => KeckUser.fromJson(j, 'uid-1'), throwsA(isA<NoSuchMethodError>()));
    });
  });

  group('StripeUrlSession / SumupCheckoutResponse', () {
    test('StripeUrlSession.fromJson', () {
      final s = StripeUrlSession.fromJson({
        'id': 'cs_1',
        'url': 'https://checkout.stripe.com/x',
        'shorten_payment_url': 'https://k.eck/x',
        'expires_at': '2026-06-12T10:00:00',
      });
      expect(s.id, 'cs_1');
      expect(s.shortenUrl, 'https://k.eck/x');
      expect(s.expiresAt, DateTime(2026, 6, 12, 10));
    });
    test('SumupCheckoutResponse.fromMap inkl. installments-String', () {
      final r = SumupCheckoutResponse.fromMap({
        'success': true,
        'transactionCode': 'TX',
        'amount': 12.5,
        'installments': '3',
        'cardLastDigits': '1234',
      });
      expect(r.success, isTrue);
      expect(r.amount, 12.5);
      expect(r.installments, 3);
      expect(r.cardLastDigits, '1234');
      expect(r.toJson()['installments'], '3');
    });
  });
}
