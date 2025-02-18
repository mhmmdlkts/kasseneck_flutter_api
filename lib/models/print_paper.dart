import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';

import '../enums/credit_card_provider.dart';
import '../enums/vat_rate.dart';
import '../services/rksv_service.dart';
import 'kasseneck_item.dart';
import 'package:image/image.dart';
import 'dart:convert';

class PrintPaper {
  final PaperSize paperSize;
  final List<Map<String, dynamic>> commands = [];
  List<int> bytes = [];

  PrintPaper({required this.paperSize});

  Future setKeckReceipt(KasseneckReceipt receipt) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    bytes.clear();

    if (receipt.logo != null) {
      Image image = decodeImage(receipt.logo!)!;
      Image resized = copyResize(image, width: 500);
      bytes += generator.image(resized);
      bytes += generator.feed(1);
    }

    bytes += generator.text(receipt.companyName, styles: PosStyles(align: PosAlign.center, bold: true)); // fontSize 32
    bytes += generator.text(receipt.street, styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('${receipt.zip} ${receipt.city}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text(receipt.uid, styles: PosStyles(align: PosAlign.center));
    bytes += generator.text(receipt.phone, styles: PosStyles(align: PosAlign.center));

    if (receipt.customerDetails.isNotEmpty) {
      bytes += generator.feed(1);

      for (int i = 0; i < receipt.customerDetails.length; i++) {
        if (i == 0) {
          bytes += _addDoubleText(generator, 'Kunde:', receipt.customerDetails[i]);
        } else {
          bytes += generator.text(receipt.customerDetails[i], styles: PosStyles(align: PosAlign.right));
        }
      }
    }

    bytes += generator.feed(1);
    bytes += _addDoubleText(generator, 'Datum:', receipt.readableTime);
    bytes += _addDoubleText(generator, 'Kassen-ID:', receipt.cashregisterId);
    bytes += _addDoubleText(generator, 'Beleg-ID:', receipt.receiptId);
    bytes += generator.feed(1);

    Map<VatRate, List<KasseneckItem>> itemsByVat = {};
    for (KasseneckItem item in receipt.items) {
      if (itemsByVat[item.vat] == null) {
        itemsByVat[item.vat] = [];
      }
      itemsByVat[item.vat]!.add(item);
      String amount = item.amount.toString().padRight(2);
      if (item.amount
          .toString()
          .length > 2) {
        amount += ' x';
      } else {
        amount += ' x ';
      }
      bytes += _addDoubleText(generator, '$amount${item.name.check() * 12}', '${item.priceOne.toStringAsFixed(2)} ${item.vat.category}', leftWidth: 7, rightWidth: 5);
    }
    bytes += generator.feed(1);

    bytes += _addTable(generator, 'MwSt%', 'MwSt', 'Netto', 'Brutto');

    itemsByVat.forEach((key, value) {
      double brutto = 0;
      for (KasseneckItem element in value) {
        brutto += element.priceOne * element.amount;
      }
      int mwstSatz = key.rate;

      double netto = brutto / (1 + (mwstSatz / 100));

      double mwst = brutto - netto;

      bytes += _addTable(generator, '${key.category} ${key.rate}%', mwst.toStringAsFixed(2), netto.toStringAsFixed(2), brutto.toStringAsFixed(2));
    });

    bytes += generator.hr(ch: '-');
    bytes += _addDoubleText(generator, 'Gesamt:', '${receipt.sum.toStringAsFixed(2)} EUR');


    if (receipt.customerDetails.isNotEmpty) {
      bytes += generator.feed(1);

      for (int i = 0; i < receipt.customerDetails.length; i++) {
        if (i == 0) {
          bytes += _addDoubleText(generator, 'Kunde:', receipt.customerDetails[i]);
        } else {
          bytes += generator.text(receipt.customerDetails[i], styles: PosStyles(align: PosAlign.right));
        }
      }
    }

    bytes += generator.feed(1);

    if (receipt.legalMessage.isNotEmpty) {
      for (String line in receipt.legalMessage) {
        bytes += generator.text(line, styles: PosStyles(align: PosAlign.center));
      }
      bytes += generator.feed(1);
    }
    if (receipt.isSigFailed || true) {
      bytes += generator.text(RKSVService.signatureDeviceDamagedKey, styles: PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
    }

    bytes += generator.qrcode(receipt.qr, size: QRSize.size6);
    bytes += generator.feed(1);

    if (receipt.cardPaymentData != null) {
      try {
        switch (receipt.creditCardProvider) {
          case CreditCardProvider.gpTomAndroid:
          case CreditCardProvider.gpTomIos:
            bytes += _gpTom(generator, receipt.cardPaymentData!);
            break;
          case CreditCardProvider.hobexCloudApi:
            bytes += _hobexApi(generator, receipt.cardPaymentData!);
            break;
          default:
            break;
        }
        generator.feed(1);
      } catch (e) {}
    }

    if (receipt.thanksMessage.isNotEmpty) {
      bytes += generator.feed(1);
      for (String message in receipt.thanksMessage) {
        bytes += generator.text(message, styles: PosStyles(align: PosAlign.center));
      }
    }

    bytes += generator.text(receipt.footer1, styles: PosStyles(align: PosAlign.center));
    bytes += generator.text(receipt.footer2, styles: PosStyles(align: PosAlign.center));
    if (receipt.footer3 != null) {
      bytes += generator.text(receipt.footer3!, styles: PosStyles(align: PosAlign.center));
    }
    if (receipt.footer4 != null) {
      bytes += generator.text(receipt.footer4!, styles: PosStyles(align: PosAlign.center));
    }
    bytes += generator.cut();
  }

  List<int> _addTable(Generator generator, String val1, String val2, String val3, String val4) {
    return generator.row([
      PosColumn(
        text: val1,
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val2,
        width: 4,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val3,
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val4,
        width: 2,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  List<int> _addDoubleText(Generator generator, String leftValue, String rightValue, {leftWidth = 6, rightWidth = 6}) {
    return generator.row([
      PosColumn(
        text: leftValue,
        width: leftWidth,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: rightValue,
        width: rightWidth,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  List<int> _hobexApi(Generator generator, Map<String, dynamic> data) {
    List<int> bytes = [];
    bytes += _addDoubleText(generator, 'Datum:', data['date']);
    bytes += _addDoubleText(generator, 'TID:', data['tid']);
    bytes += _addDoubleText(generator, 'Nr.:', data['no']);
    bytes += _addDoubleText(generator, 'Art:', data['type']);
    bytes += _addDoubleText(generator, 'Karte:', data['cardBrand']);
    bytes += _addDoubleText(generator, 'PAN:', data['cardNumber']);
    bytes += _addDoubleText(generator, 'RC:', data['responseCode']);
    if (data['cvm'] == '1') {
      bytes += generator.feed(2);
      bytes += generator.text('------------------', styles: PosStyles(align: PosAlign.center));
      bytes += generator.text('Unterschrift', styles: PosStyles(align: PosAlign.center));
    }
    bytes += generator.feed(1);
    return bytes;
  }

  List<int> _gpTom(Generator generator, Map<String, dynamic> data) {
    List<int> bytes = [];
    bytes += generator.text('Batch: ${data['batchNumber']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('Receipt: ${data['externalTransactionID']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('TID: ${data['terminalID']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('${data['emvAid']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('${data['emvAppLabel']} ${data['cardDataEntry']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('${data['cardNumber']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('${data['transactionType']} Amount ${data['currencyCode']} ${data['amount']?.toStringAsFixed(2)}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text(data['pinOk'] ? 'PIN OK' : 'PIN NOT OK', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('Authorization Code ${data['approvedCode']}', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('Sequence Number: ${data['sequenceNumber']}', styles: PosStyles(align: PosAlign.center));
    return bytes;
  }
}

extension CP437Checker on String {
  // Offizielle CP437-Zeichen als Set für schnelle Überprüfung
  static final Set<int> cp437Set = {
    0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
    0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F,
    0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F,
    0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F,
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0xA0,
    0xC7, 0xFC, 0xE9, 0xE2, 0xE4, 0xE0, 0xE5, 0xE7, 0xEA, 0xEB, 0xE8, 0xEF, 0xEE, 0xEC, 0xC4, 0xC5,
    0xC9, 0xE6, 0xC6, 0xF4, 0xF6, 0xF2, 0xFB, 0xF9, 0xFF, 0xD6, 0xDC, 0xA2, 0xA3, 0xA5, 0x20A7, 0x192,
    0xE1, 0xED, 0xF3, 0xFA, 0xF1, 0xD1, 0xAA, 0xBA, 0xBF, 0x2310, 0xAC, 0xBD, 0xBC, 0xA1, 0xAB, 0xBB,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D,
    0x255C, 0x255B, 0x2510, 0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554,
    0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567, 0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553,
    0x256B, 0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, 0x3B1, 0xDF, 0x393, 0x3C0, 0x3A3,
    0x3C3, 0xB5, 0x3C4, 0x3A6, 0x398, 0x3A9, 0x3B4, 0x221E, 0x3C6, 0x3B5, 0x2229, 0x2261, 0xB1, 0x2265,
    0x2264, 0x2320, 0x2321, 0xF7, 0x2248, 0xB0, 0x2219, 0xB7, 0x221A, 0x207F, 0xB2, 0x25A0, 0xA0
  };

  String check() {
    return runes.map((r) => cp437Set.contains(r) ? String.fromCharCode(r) : '?').join();
  }
}