import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
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

  // SumUp Solo (npm 1.43.0): eine Zahlung ueber die Cloud-API (`providerData.channel == 'cloud'`) druckt wie eine
  // ueber das SDK, aber nur die Zeilen, deren Wert sie kennt (nie „n/a“, nie den Autorisierungscode). Ohne
  // Transaktionscode und ohne Endziffern (Handbeleg einer ungeklaerten Zahlung, Rueckbuchung am Storno) steht gar
  // kein SumUp-Block da. Die Golden-Belege `card-sumup-cloud*` und `cancellation-sumup-cloud` sind der Vertrag.
  group('SumUp Cloud (Solo): nur vorhandene Zeilen, duenne Zahlung ohne Block', () {
    const sumupLinks = {'Kartentyp:', 'Kartennummer:', 'Zahlungstyp:', 'Gesamtbetrag:', 'Transaktionscode:', 'Modus:'};
    Map<String, dynamic> datei(String pfad) =>
        jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;

    /// Der Beleg des Vertrags, wahlweise mit dem Layout eines Golden-Belegs (sonst druckt der Rueckfall).
    KasseneckReceipt beleg(String name, {String? layoutVon}) {
      final f = datei('receipts/$name.json');
      final firma = f['company'] as Map<String, dynamic>;
      return KasseneckReceipt.fromJson({
        'receipt': {...(f['receipt'] as Map<String, dynamic>), 'customerDetails': '', 'legalMessage': ''},
        'company': firma['companyName'],
        'street': firma['street'],
        'zip': firma['zip'],
        'city': firma['city'],
        'is_small_business': false,
        'footer1': firma['footer1'] ?? '',
        'footer2': firma['footer2'] ?? '',
        'layout': ?(layoutVon == null ? null : datei('expected/$layoutVon.lines.json')),
      });
    }

    List<({String left, String right})> sumupPaare(PrintPaper p) =>
        [for (final d in doubles(p)) if (sumupLinks.contains(d.left)) d];

    test('card-sumup-cloud: der Rueckfall druckt den Block des Golden-Belegs, ohne Zahlungstyp', () async {
      final golden = datei('expected/card-sumup-cloud.lines.json')['lines'] as List;
      final start = golden.indexWhere((z) => (z as Map)['text'] == 'Sumup Beleg');
      final soll = <({String left, String right})>[];
      for (final z in golden.skip(start + 1)) {
        if ((z as Map)['kind'] != 'columns') break;
        final spalten = z['columns'] as List;
        soll.add((left: (spalten[0] as Map)['text'] as String, right: (spalten[1] as Map)['text'] as String));
      }
      expect(soll.map((x) => x.left), isNot(contains('Zahlungstyp:')));
      final p = await render(beleg('card-sumup-cloud'));
      expect(texts(p).where((t) => t == 'Sumup Beleg'), hasLength(1));
      expect(sumupPaare(p), soll);
      // Der Autorisierungscode steht in den Anbieterdaten, aber nie auf dem Bon.
      expect([...texts(p), for (final d in doubles(p)) '${d.left} ${d.right}'].join('\n'), isNot(contains('Q7X2K9')));
    });

    for (final name in ['card-sumup-cloud-hand', 'cancellation-sumup-cloud']) {
      test('$name: kein SumUp-Block (ohne Transaktionscode und Endziffern)', () async {
        final golden = (datei('expected/$name.lines.json')['lines'] as List).map((z) => (z as Map)['text']);
        expect(golden, isNot(contains('Sumup Beleg')));
        final p = await render(beleg(name));
        expect(texts(p), isNot(contains('Sumup Beleg')));
        expect(sumupPaare(p), isEmpty);
      });
    }

    test('das gelieferte Layout gilt als vollstaendig, auch ohne Block der duennen Zahlung', () {
      for (final name in ['card-sumup-cloud', 'card-sumup-cloud-hand', 'cancellation-sumup-cloud']) {
        expect(beleg(name, layoutVon: name).isLayoutComplete, isTrue, reason: name);
      }
      // Die volle Cloud-Zahlung braucht ihren Block: ein Layout ohne ihn druckt der Rueckfall.
      expect(beleg('card-sumup-cloud', layoutVon: 'sale-cash').isLayoutComplete, isFalse);
      expect(beleg('card-sumup-cloud-hand').cardPayments, isEmpty);
      expect(beleg('card-sumup-cloud').cardPayments, hasLength(1));
    });

    test('fehlende Werte fallen als Zeile weg, nie „n/a“', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'channel': 'cloud', 'transactionCode': 'TC1', 'amount': 12.5, 'currency': 'EUR', 'authCode': 'Q7X2K9'},
      ));
      expect(texts(p), contains('Sumup Beleg'));
      expect(sumupPaare(p), [(left: 'Gesamtbetrag:', right: '12,50 EUR'), (left: 'Transaktionscode:', right: 'TC1')]);
      final p2 = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'channel': 'cloud', 'cardLastDigits': '4242', 'paymentType': 'POS', 'entryMode': 'chip'},
      ));
      expect(sumupPaare(p2), [
        (left: 'Kartennummer:', right: '**** **** **** 4242'),
        (left: 'Zahlungstyp:', right: 'POS'),
        (left: 'Modus:', right: 'CHIP'),
      ]);
      for (final d in [...doubles(p), ...doubles(p2)]) {
        expect(d.right, isNot(contains('n/a')));
        expect(d.right, isNot(contains('Q7X2K9')));
      }
    });

    test('SDK-Zahlung bleibt, wie sie war (Zahlungstyp mit n/a)', () async {
      final p = await render(buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'cardLastDigits': '1234', 'amount': 12.5, 'currency': 'EUR', 'transactionCode': 'TC1'},
      ));
      expect(sumupPaare(p), [
        (left: 'Kartentyp:', right: 'n/a'),
        (left: 'Kartennummer:', right: '**** **** **** 1234'),
        (left: 'Zahlungstyp:', right: 'n/a'),
        (left: 'Gesamtbetrag:', right: '12,50 EUR'),
        (left: 'Transaktionscode:', right: 'TC1'),
        (left: 'Modus:', right: ''),
      ]);
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

  group('MyPos-Textfallback der MwSt-Tabelle', () {
    /// Die Tabellenzeile aus der MyPos-Textrepraesentation, ohne Kopfzeile.
    Future<List<String>> tabelle(int bruttoCents, KeckPaperSize size) async {
      final paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
      await paper.setKeckReceipt(
        buildReceipt(items: [
          KasseneckItem(name: 'Ware', quantity: 1, vat: VatRate.vat20, priceCents: bruttoCents),
        ]),
        qrMode: QrPrintMode.native,
      );
      return texts(paper).where((t) => t.trimLeft().startsWith('A 20%')).toList();
    }

    test('grosse Betraege werden nicht mehr abgeschnitten', () async {
      // 100.000,00 EUR sind neun Zeichen; padLeft(8).substring(0, 8) machte
      // daraus "100000,0" -- die letzte Stelle des Betrags fiel weg.
      final zeile = (await tabelle(10000000, KeckPaperSize.mm58)).single;
      expect(zeile, contains('100000,00'));
      expect(zeile, contains('83333,33')); // Netto
      expect(zeile, contains('16666,67')); // MwSt
    });

    test('80 mm nutzt 48 Zeichen statt der fest verdrahteten 32', () async {
      final schmal = (await tabelle(1999, KeckPaperSize.mm58)).single;
      final breit = (await tabelle(1999, KeckPaperSize.mm80)).single;
      expect(schmal.length, 32);
      expect(breit.length, 48);
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
