import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/services/rksv_service.dart';

import 'helpers/test_receipts.dart';

/// Detail-Tests des Druck-Renderings ueber die myPosPaper-Textrepraesentation
/// und die rohen ESC/POS-Bytes. Plain tests (kein FakeAsync) -> echtes
/// Asset-/Bild-I/O funktioniert direkt.

Future<PrintPaper> render(KasseneckReceipt receipt, {QrPrintMode qrMode = QrPrintMode.native}) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(receipt, qrMode: qrMode);
  return paper;
}

List<String> texts(PrintPaper p) =>
    p.myPosPaper.commands.where((c) => c['type'] == 'text').map((c) => c['value'] as String).toList();

List<({String left, String right})> doubles(PrintPaper p) => p.myPosPaper.commands
    .where((c) => c['type'] == 'doubleText')
    .map((c) => (left: c['leftValue'] as String, right: c['rightValue'] as String))
    .toList();

List<int> allBytes(PrintPaper p) => [for (final b in p.bytes) ...b];

bool containsSeq(List<int> haystack, List<int> needle) {
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    bool hit = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) { hit = false; break; }
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Karten-Bloecke je Provider (Druck)', () {
    test('hobexHps: alle Zeilen inkl. bedingter Gueltig/Genehmigung + Unterschrift bei cvm=1', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.hobexHps,
        cardPaymentData: {
          'date': '2026-06-12 10:00:00', 'tid': '3600335', 'no': '42', 'type': 'SELL',
          'cardBrand': 'Visa', 'cardNumber': '************1234', 'responseCode': '0',
          'cvm': '1', 'approvalCode': 'ABC123', 'cardExpiry': '2612',
        },
      ));
      final d = doubles(p);
      expect(texts(p), contains('Hobex Beleg'));
      expect(d.firstWhere((x) => x.left == 'PAN:').right, '************1234');
      expect(d.firstWhere((x) => x.left == 'Gueltig:').right, '2612');
      expect(d.firstWhere((x) => x.left == 'Genehmigung:').right, 'ABC123');
      expect(texts(p), contains('Unterschrift'));
    });

    test('hobexHps: ohne Expiry/Approval fehlen die Zeilen, ohne cvm=1 keine Unterschrift', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.hobexHps,
        cardPaymentData: {
          'date': 'x', 'tid': 'x', 'no': 'x', 'type': 'x',
          'cardBrand': 'x', 'cardNumber': 'x', 'responseCode': '0', 'cvm': '2',
        },
      ));
      expect(doubles(p).where((x) => x.left == 'Gueltig:'), isEmpty);
      expect(doubles(p).where((x) => x.left == 'Genehmigung:'), isEmpty);
      expect(texts(p), isNot(contains('Unterschrift')));
    });

    test('myposPro: yyMMddHHmmss-Datum wird formatiert', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.myposPro,
        cardPaymentData: {
          'TID': 'T1', 'date_time': '260612104530', 'application_name': 'VISA DEBIT',
          'pan': '**1234', 'signature_required': false, 'STAN': 7,
          'authorization_code': 'A1', 'reference_number': 'R1', 'AID': 'AID1',
        },
      ));
      final d = doubles(p);
      expect(texts(p), contains('MyPos Beleg'));
      expect(d.firstWhere((x) => x.left == 'DATUM:').right, '12.06.2026 10:45:30');
      expect(d.firstWhere((x) => x.left == 'STAN:').right, '000007');
    });

    test('sumup: Betrag formatiert + Kartennummer maskiert', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'cardType': 'VISA', 'cardLastDigits': '1234', 'paymentType': 'POS',
          'amount': 12.5, 'currency': 'EUR', 'transactionCode': 'TC1', 'entryMode': 'nfc'},
      ));
      final d = doubles(p);
      expect(texts(p), contains('Sumup Beleg'));
      expect(d.firstWhere((x) => x.left == 'Kartennummer:').right, '**** **** **** 1234');
      expect(d.firstWhere((x) => x.left == 'Gesamtbetrag:').right, '12,50 EUR');
      expect(d.firstWhere((x) => x.left == 'Modus:').right, 'NFC');
    });

    test('kaputte cardPaymentData: Beleg wird trotzdem fertig gedruckt (Footer da)', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.myposPro,
        cardPaymentData: {'TID': 'T1'}, // date_time fehlt -> wirft im Block
      ));
      expect(texts(p), contains('Footer Eins'));
      expect(texts(p), contains('Footer Zwei'));
    });

    test('stripe (Karte): alle Zeilen in der richtigen Reihenfolge', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_3Txxxxxxxxxxxxxx',
        cardPaymentData: {
          'paymentMethodType': 'card',
          'amount': 1250,
          'currency': 'eur',
          'receiptUrl': 'https://pay.stripe.com/receipts/xyz',
          'paidAt': 1784300000,
          'statementDescriptor': 'KASSENECK',
          'cardBrand': 'visa',
          'cardLastDigits': '4242',
          'wallet': 'apple_pay',
          'cardFunding': 'debit',
          'threeDSecure': 'authenticated',
        },
      ));
      final all = texts(p);
      final int idx = all.indexOf('Online-Zahlung (Stripe)');
      expect(idx, greaterThanOrEqualTo(0));
      expect(all.sublist(idx, idx + 8), [
        'Online-Zahlung (Stripe)',
        'visa Debitkarte (Apple Pay)',
        '**** **** **** 4242',
        '3-D Secure: ja',
        'Gesamtbetrag 12,50 EUR',
        'Bezahlt: ${expectedStripePaidAt(1784300000)}',
        'Abrechnung: KASSENECK',
        'Referenz: pi_3Txxxxxxxxxxxxxx',
      ]);
      // receiptUrl wird nie gerendert
      expect(all.any((t) => t.contains('pay.stripe.com')), isFalse);
    });

    test('stripe (EPS): EPS-Zeile statt Kartenzeilen', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_epsxxxxxxxxxxxx',
        cardPaymentData: {
          'paymentMethodType': 'eps',
          'epsBank': 'bank_austria',
          'amount': 500,
          'currency': 'eur',
          'statementDescriptor': 'KASSENECK',
        },
      ));
      final all = texts(p);
      final int idx = all.indexOf('Online-Zahlung (Stripe)');
      expect(idx, greaterThanOrEqualTo(0));
      expect(all.sublist(idx, idx + 5), [
        'Online-Zahlung (Stripe)',
        'EPS - Bank Austria',
        'Gesamtbetrag 5,00 EUR',
        'Abrechnung: KASSENECK',
        'Referenz: pi_epsxxxxxxxxxxxx',
      ]);
      expect(all, isNot(contains('**** **** **** ')));
      expect(all.where((t) => t.startsWith('3-D Secure')), isEmpty);
    });

    test('stripe minimal: nur Titel + Referenz', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_minimal1',
        // Nur ein irrelevantes Feld (receiptUrl) — belegt zusaetzlich, dass es
        // ignoriert wird, ohne dass die Zeile fehlt.
        cardPaymentData: {'receiptUrl': 'https://pay.stripe.com/receipts/min'},
      ));
      final all = texts(p);
      final int idx = all.indexOf('Online-Zahlung (Stripe)');
      expect(idx, greaterThanOrEqualTo(0));
      expect(all.sublist(idx, idx + 2), [
        'Online-Zahlung (Stripe)',
        'Referenz: pi_minimal1',
      ]);
    });

    test('stripe: kaputte cardPaymentData crasht den Druck nicht', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_broken1',
        cardPaymentData: {
          'paymentMethodType': 'card',
          'amount': 'nicht-numerisch',
          'paidAt': 'nicht-numerisch',
          'cardFunding': 12345,
          'wallet': ['unerwartet'],
          'cardLastDigits': 4242, // int statt String
        },
      ));
      expect(texts(p), contains('Footer Eins'));
      expect(texts(p), contains('Footer Zwei'));
    });
  });

  group('RKSV-Ausfall & Beleg-Bausteine', () {
    test('isSigFailed -> Ausfalltext am Beleg', () async {
      final marker = RKSVService.signatureDeviceDamagedKey;
      final damagedSig = 'h.p.${helperMarker()}';
      final p = await render(buildReceipt(items: cartA().items, sig: damagedSig));
      expect(texts(p), contains(marker));
    });
    test('intakte Signatur -> kein Ausfalltext', () async {
      final p = await render(buildReceipt(items: cartA().items));
      expect(texts(p), isNot(contains(RKSVService.signatureDeviceDamagedKey)));
    });
    test('customerDetails erzeugen den Kunde-Block, leere nicht', () async {
      final withCustomer = await render(buildReceipt(items: cartA().items)..customerDetails = ['Max', 'Zeile 2']);
      expect(doubles(withCustomer).firstWhere((x) => x.left == 'Kunde:').right, 'Max');
      expect(doubles(withCustomer).map((x) => x.right), contains('Zeile 2'));
      final without = await render(buildReceipt(items: cartA().items));
      expect(doubles(without).where((x) => x.left == 'Kunde:'), isEmpty);
    });
    test('legalMessage + thanksMessage als Zeilen', () async {
      final p = await render(buildReceipt(items: cartA().items)
        ..legalMessage = ['Fahrzeug: W-1']
        ..thanksMessage = ['Danke!']);
      expect(texts(p), contains('Fahrzeug: W-1'));
      expect(texts(p), contains('Danke!'));
    });
  });

  group('QR-Druckmodi erzeugen die richtigen ESC/POS-Befehle', () {
    test('native -> GS ( k, imageRaster -> GS v 0, imageBitImage -> ESC *', () async {
      final receipt = buildReceipt(items: cartA().items);
      final native = allBytes(await render(receipt, qrMode: QrPrintMode.native));
      final raster = allBytes(await render(receipt, qrMode: QrPrintMode.imageRaster));
      final bitImage = allBytes(await render(receipt, qrMode: QrPrintMode.imageBitImage));

      expect(containsSeq(native, [0x1D, 0x28, 0x6B]), isTrue, reason: 'GS ( k fehlt im native-Modus');
      expect(containsSeq(raster, [0x1D, 0x76, 0x30]), isTrue, reason: 'GS v 0 fehlt im Raster-Modus');
      expect(containsSeq(bitImage, [0x1B, 0x2A]), isTrue, reason: 'ESC * fehlt im BitImage-Modus');
      // Raster-Modus darf den alten ESC*-QR nicht zusaetzlich enthalten und umgekehrt
      expect(raster.length == native.length, isFalse);
    });
  });

  group('Format-Helfer & CP437', () {
    test('formatCents/formatAmount', () {
      expect(formatCents(1999), '19,99');
      expect(formatCents(-50), '-0,50');
      expect(formatCents(0), '0,00');
      expect(formatAmount(12.5), '12,50');
    });
    test('euroToCent rundet, centToEuro teilt', () {
      expect(euroToCent(19.99), 1999);
      expect(euroToCent(0.1 + 0.2), 30);
      expect(euroToCent(-1.005), -100);
      expect(centToEuro(1999), 19.99);
    });
    test('CP437Checker: Umlaute bleiben, Euro-Zeichen und Emoji werden ?', () {
      expect('äöüÄÖÜß'.check(), 'äöüÄÖÜß');
      expect('Preis: 5€'.check(), 'Preis: 5?');
      expect('Hi 🙂'.check(), 'Hi ?'); // runes: das Emoji ist EINE Rune -> ein ?
    });
  });
}

/// base64url-kodierter Ausfall-Marker (3. JWS-Segment), wie RKSVService ihn prueft.
String helperMarker() {
  return base64Encode(utf8.encode(RKSVService.signatureDeviceDamagedKey))
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'=+$'), '');
}

/// Erwarteter 'DD.MM.YYYY HH:mm'-String fuer einen Stripe-`paidAt` (Unix-Sekunden)
/// in WIENER Zeit (Geschaeftszeitzone, identisch zum Backend-Beleg-PDF) — als
/// feste Konstante je Fixture, unabhaengig von Geraete-Zeitzone und
/// Produktionslogik, damit der Test eine echte Spezifikation ist.
String expectedStripePaidAt(int paidAtSeconds) {
  const known = {
    1784300000: '17.07.2026 16:53', // = 2026-07-17T14:53:20Z, Wien Sommerzeit UTC+2
  };
  final s = known[paidAtSeconds];
  if (s == null) {
    throw ArgumentError('Kein erwarteter Wien-String fuer paidAt=$paidAtSeconds hinterlegt');
  }
  return s;
}
