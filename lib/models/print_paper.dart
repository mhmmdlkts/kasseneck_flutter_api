import 'dart:convert';

import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:my_pos/models/my_pos_paper.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../enums/credit_card_provider.dart';
import '../enums/vat_rate.dart';
import '../enums/voucher_action.dart';
import '../enums/voucher_type.dart';
import '../services/rksv_service.dart';
import 'kasseneck_item.dart';
import 'package:image/image.dart';

import 'keck_voucher.dart';

class PrintPaper {
  final KeckPaperSize paperSize;
  final List<Map<String, dynamic>> commands = [];
  final Generator generator;
  List<Uint8List> bytes = [];
  final MyPosPaper myPosPaper = MyPosPaper();

  PrintPaper({required this.paperSize, required CapabilityProfile profile}) : generator = Generator(paperSize.paperSize, profile) {
    reset();
  }

  void addBytes(Uint8List byte) {
    bytes.add(byte);
    // myPosPaper does not support raw bytes
  }

  void addText(String text, {PosStyles styles = const PosStyles()}) {
    bytes.add(Uint8List.fromList(generator.text(text, styles: styles)));
    myPosPaper.addText(text, alignment: styles.myposAlign);
  }

  void addCut() {
    bytes.add(Uint8List.fromList(generator.cut()));
    // myPosPaper does not support cut
  }

  void addFeed({int lines = 1}) {
    if (lines < 1) {
      lines = 1;
    }
    bytes.add(Uint8List.fromList(generator.feed(lines)));
    myPosPaper.addSpace(lines);
  }

  void addReverseFeed({int lines = 1}) {
    if (lines < 1) {
      lines = 1;
    }
    bytes.add(Uint8List.fromList(generator.reverseFeed(lines)));
    // myPosPaper does not support reverse feed
  }

  void addFullHorizontalLine({String ch = '-'}) {
    bytes.add(Uint8List.fromList(generator.hr(ch: ch)));
    myPosPaper.addText(ch * 32, alignment: PrinterAlignment.left);
  }

  void addImage(Image image, {PosAlign align = PosAlign.center}) {
    bytes.add(Uint8List.fromList(generator.imageRaster(image)));

    final pngBytes = encodePng(image); // oder encodeJpg(src, quality: 90)
    myPosPaper.addImage(pngBytes);
  }

  void addBase64Image(String base64, {PosAlign align = PosAlign.center}) {
    Image image = decodeImage(base64Decode(base64))!;
    addImage(image, align: align);
  }

  void addUint8ListImage(Uint8List image, {PosAlign align = PosAlign.center}) {
    Image img = decodeImage(image)!;
    addImage(img, align: align);
  }

  void addQrCode(String data, {QRSize size = QRSize.Size6}) {
    bytes.add(Uint8List.fromList(generator.qrcode(data, size: size)));
    myPosPaper.addQrCode(data, size: 280);
  }

  Future<void> addQrCodeAsImage(String data, {int size = 280}) async {
    try {
      final QrPainter painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: false,
      );
      final ByteData? byteData = await painter.toImageData(size.toDouble());
      if (byteData == null) {
        print('Error: QR ByteData is null');
        return;
      }

      final Uint8List qrBytes = byteData.buffer.asUint8List();
      final Image? img = decodeImage(qrBytes);
      if (img == null) {
        print('Error decoding QR image');
        return;
      }

      // Wenn dein Drucker Probleme mit image hat, kannst du auch imageRaster probieren:
      bytes.add(Uint8List.fromList(generator.image(img)));
      myPosPaper.addImage(encodePng(img));
    } catch (e) {
      print('Error in addQrCodeAsImage: $e');
    }
  }

  void reset() {
    bytes.clear();
    bytes.add(Uint8List.fromList(generator.reset()));
    bytes.add(Uint8List.fromList(generator.setGlobalCodeTable('CP1252')));
    myPosPaper.commands.clear();
  }

  Future setKeckReceipt(KasseneckReceipt receipt, {bool qrAsImage = false}) async {
    reset();

    if (receipt.logo != null) {
      Image image = decodeImage(receipt.logo!)!;
      Image resized = copyResize(image, width: paperSize.imageWidth);

      addImage(resized);
      addFeed();
    }

    addText(receipt.companyName, styles: PosStyles(align: PosAlign.center, bold: true));
    addText(receipt.street, styles: PosStyles(align: PosAlign.center));
    addText('${receipt.zip} ${receipt.city}', styles: PosStyles(align: PosAlign.center));
    addText(receipt.taxInfo, styles: PosStyles(align: PosAlign.center));
    addText(receipt.phone, styles: PosStyles(align: PosAlign.center));

    if (receipt.customerDetails.isNotEmpty) {
      addFeed();

      for (int i = 0; i < receipt.customerDetails.length; i++) {
        if (i == 0) {
          addDoubleText('Kunde:', receipt.customerDetails[i], leftWidth: 5, rightWidth: 7);
        } else {
          addDoubleText('', receipt.customerDetails[i], leftWidth: 1, rightWidth: 11);
        }
      }
    }

    addFeed();
    addDoubleText('Datum:', receipt.readableTime, leftWidth: 4, rightWidth: 8);
    addDoubleText('Kassen-ID:', receipt.cashregisterId);
    addDoubleText('Beleg-ID:', receipt.receiptId);
    addFeed();

    Map<VatRate, List<KasseneckItem>> itemsByVat = {};
    for (KasseneckItem item in receipt.items) {
      if (itemsByVat[item.vat] == null) {
        itemsByVat[item.vat] = [];
      }
      itemsByVat[item.vat]!.add(item);
      String amount = item.quantity.toString().padRight(2);
      if (item.quantity
          .toString()
          .length > 2) {
        amount += ' x';
      } else {
        amount += ' x ';
      }
      addDoubleText('$amount${item.name.check()}${item.quantity > 1 ? ' je ${formatAmount(item.singlePrice)}' : ''}', '${formatAmount(item.singlePrice * item.quantity)} ${item.vat.category}', leftWidth: 7, rightWidth: 5);
    }

    double totalPromoVoucherValue = 0;
    for (KeckVoucher voucher in receipt.vouchers??[]) {

      if (voucher.isValid && voucher.action == VoucherAction.sell) {
        itemsByVat[VatRate.vat0] ??= [];
        itemsByVat[VatRate.vat0]!.add(KasseneckItem(
          name: voucher.receipText,
          quantity: 1,
          singlePrice: voucher.value ?? 0,
          vat: VatRate.vat0
        ));
      }
      if (voucher.action == VoucherAction.sell && voucher.type == VoucherType.value) {
        String amount = '1  x ';
        addDoubleText('$amount${voucher.receipText}', '${formatAmount(voucher.value??0)} ${VatRate.vat0.category}', leftWidth: 7, rightWidth: 5);
      }
      if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.promo) {
        totalPromoVoucherValue += voucher.value ?? 0;
        addDoubleText(voucher.receipText, '-${formatAmount(voucher.value??0)} EUR', leftWidth: 7, rightWidth: 5);
      }
    }

    final Map<VatRate, int> vatTableBruttoByVatCents = {
      for (final VatRate key in itemsByVat.keys) key: 0,
    };

    itemsByVat.forEach((key, value) {
      int bruttoCents = 0;
      for (final KasseneckItem element in value) {
        bruttoCents += euroToCent(element.singlePrice * element.quantity);
      }
      vatTableBruttoByVatCents[key] = bruttoCents;
    });

    final int totalPromoVoucherValueCents = euroToCent(totalPromoVoucherValue);
    final int totalAmountCents = vatTableBruttoByVatCents.values.fold(0, (sum, value) => sum + value);
    final int usablePromoVoucherValueCents =
        totalPromoVoucherValueCents > totalAmountCents ? totalAmountCents : totalPromoVoucherValueCents;

    if (usablePromoVoucherValueCents > 0 && totalAmountCents > 0) {
      final Map<VatRate, int> promoByVatCents = {
        for (final VatRate key in vatTableBruttoByVatCents.keys) key: 0,
      };

      int usedPromoCents = 0;
      vatTableBruttoByVatCents.forEach((key, bruttoCents) {
        final int proportionalCents = (usablePromoVoucherValueCents * bruttoCents) ~/ totalAmountCents;
        promoByVatCents[key] = proportionalCents;
        usedPromoCents += proportionalCents;
      });

      final int remainingPromoCents = usablePromoVoucherValueCents - usedPromoCents;
      if (remainingPromoCents > 0) {
        final List<MapEntry<VatRate, int>> sortedGroups = vatTableBruttoByVatCents.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (sortedGroups.isNotEmpty && sortedGroups.first.value > 0) {
          promoByVatCents[sortedGroups.first.key] =
              (promoByVatCents[sortedGroups.first.key] ?? 0) + remainingPromoCents;
        }
      }

      promoByVatCents.forEach((key, promoCents) {
        vatTableBruttoByVatCents[key] = (vatTableBruttoByVatCents[key] ?? 0) - promoCents;
      });
    }

    addFeed();

    _addTable('MwSt%', 'MwSt', 'Netto', 'Brutto');

    vatTableBruttoByVatCents.forEach((key, bruttoCents) {
      final double brutto = centToEuro(bruttoCents);
      final int mwstSatz = key.rate;
      final double netto = brutto / (1 + (mwstSatz / 100));
      final double mwst = brutto - netto;

      _addTable('${key.category} ${key.rate}%', formatAmount(mwst), formatAmount(netto), formatAmount(brutto));
    });

    addFullHorizontalLine();

    if (receipt.sum != receipt.subSum) {
      addDoubleText('Zwischensumme', '${formatAmount(receipt.subSum)} EUR');

      for (KeckVoucher voucher in receipt.vouchers??[]) {
        if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.value) {
          addDoubleText(voucher.receipText, '-${formatAmount(voucher.value??0)} EUR');
        }
      }

      addFullHorizontalLine();
    }
    addDoubleText('Gesamt:', '${formatAmount(receipt.sum)} EUR');

    addFeed();

    if (receipt.legalMessage.isNotEmpty) {
      for (String line in receipt.legalMessage) {
        addText(line, styles: PosStyles(align: PosAlign.center));
      }
      addFeed();
    }
    if (receipt.isSigFailed) {
      addText(RKSVService.signatureDeviceDamagedKey, styles: PosStyles(align: PosAlign.center));
      addFeed();
    }


    if (qrAsImage) {
      await addQrCodeAsImage(receipt.qr);
    } else {
      addQrCode(receipt.qr);
    }

    addFeed();

    if (receipt.cardPaymentData != null && receipt.creditCardProvider != null) {
      try {
        switch (receipt.creditCardProvider!) {
          case CreditCardProvider.gpTomAndroid:
          case CreditCardProvider.gpTomIos:
            _gpTom(receipt.cardPaymentData!);
            break;
          case CreditCardProvider.hobexCloudApi:
            _hobexApi(receipt.cardPaymentData!);
            break;
          case CreditCardProvider.sumup:
            _sumup(receipt.cardPaymentData!);
            break;
          case CreditCardProvider.custom:
            break;
          case CreditCardProvider.myposPro:
            _mypos(receipt.cardPaymentData!);
            break;
        }
        addFeed();
      } catch (e) {}
    }

    if (receipt.thanksMessage.isNotEmpty) {
      addFeed();
      for (String message in receipt.thanksMessage) {
        addText(message, styles: PosStyles(align: PosAlign.center));
      }
    }

    addText(receipt.footer1, styles: PosStyles(align: PosAlign.center));
    addText(receipt.footer2, styles: PosStyles(align: PosAlign.center));
    if (receipt.footer3 != null) {
      addText(receipt.footer3!, styles: PosStyles(align: PosAlign.center));
    }
    if (receipt.footer4 != null) {
      addText(receipt.footer4!, styles: PosStyles(align: PosAlign.center));
    }
    addCut();
  }

  void _addTable(String val1, String val2, String val3, String val4) {
    bool isBig = paperSize >= KeckPaperSize.mm80;
    List<int> bytes = generator.row([
      PosColumn(
        text: val1,
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val2,
        width: isBig ? 4 : 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val3,
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: val4,
        width: isBig ? 2 : 3,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);

    this.bytes.add(Uint8List.fromList(bytes));
    int len = 32~/4;
    val1 = val1.padRight(len).substring(0, len);
    val2 = val2.padLeft(len).substring(0, len);
    val3 = val3.padLeft(len).substring(0, len);
    val4 = val4.padLeft(len).substring(0, len);
    myPosPaper.addText('$val1$val2$val3$val4');
  }

  void addDoubleText(String leftValue, String rightValue, {int leftWidth = 6, int rightWidth = 6}) {
    List<int> bytes = generator.row([
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

    this.bytes.add(Uint8List.fromList(bytes));
    myPosPaper.addDoubleText(leftValue, rightValue);
  }



  void _hobexApi(Map<String, dynamic> data) {
    addText('Hobex Beleg', styles: PosStyles(align: PosAlign.center, bold: true));
    addDoubleText('Datum:', data['date']);
    addDoubleText('TID:', data['tid']);
    addDoubleText('Nr.:', data['no']);
    addDoubleText('Art:', data['type']);
    addDoubleText('Karte:', data['cardBrand']);
    addDoubleText('PAN:', data['cardNumber']);
    addDoubleText('RC:', data['responseCode']);
    if (data['cvm'] == '1') {
      addFeed(lines: 2);
      addText('------------------', styles: PosStyles(align: PosAlign.center));
      addText('Unterschrift', styles: PosStyles(align: PosAlign.center));
    }
    addFeed();
  }

  void _sumup(Map<String, dynamic> data) {
    addText('Sumup Beleg', styles: PosStyles(align: PosAlign.center, bold: true));
    addDoubleText('Kartentyp:', data['cardType'] ?? 'n/a');
    addDoubleText('Kartennummer:', '**** **** **** ${data['cardLastDigits'] ?? ''}');
    addDoubleText('Zahlungstyp:', data['paymentType'] ?? 'n/a');
    addDoubleText('Gesamtbetrag:', '${data['amount'] != null ? formatAmount(data['amount'] as num) : '-'} ${data['currency'] ?? ''}');
    addDoubleText('Transaktionscode:', data['transactionCode'] ?? '-');
    addDoubleText('Modus:', (data['entryMode'] ?? '').toUpperCase());
    addFeed();
  }

  void _mypos(Map<String, dynamic> data) {
    addText('MyPos Beleg', styles: PosStyles(align: PosAlign.center, bold: true));
    addDoubleText('TERMINAL ID:', data['TID'] ?? '-');
    String dateTime = data['date_time'];
    String day = dateTime.substring(4, 6);
    String month = dateTime.substring(2, 4);
    String year = '20${dateTime.substring(0, 2)}';
    String hour = dateTime.substring(6, 8);
    String minute = dateTime.substring(8, 10);
    String second = dateTime.substring(10, 12);
    String formattedDate = '$day.$month.$year $hour:$minute:$second';
    addDoubleText('DATUM:', formattedDate);
    addText(data['application_name'] ?? '', styles: PosStyles(align: PosAlign.center, bold: true));
    addDoubleText('KARTE:', data['pan'] ?? '-');
    if (data['signature_required'] == true) {
      addFeed(lines: 2);
      addText('------------------', styles: PosStyles(align: PosAlign.center));
      addText('Unterschrift', styles: PosStyles(align: PosAlign.center));
    }
    addDoubleText('STAN:', data['STAN']?.toString().padLeft(6, '0') ?? '-');
    addDoubleText('AUTH. CODE:', data['authorization_code'] ?? '-');
    addDoubleText('RRN:', data['reference_number'] ?? '-');
    addDoubleText('AID:', data['AID'] ?? '-');
  }

  void _gpTom(Map<String, dynamic> data) {
    addText('GP Tom Beleg', styles: PosStyles(align: PosAlign.center, bold: true));
    addText('Batch: ${data['batchNumber']}', styles: PosStyles(align: PosAlign.center));
    addText('Receipt: ${data['externalTransactionID']}', styles: PosStyles(align: PosAlign.center));
    addText('TID: ${data['terminalID']}', styles: PosStyles(align: PosAlign.center));
    addText('${data['emvAid']}', styles: PosStyles(align: PosAlign.center));
    if (data['emvAppLable'] != null || data['cardDataEntry'] != null) {
      addText('${data['emvAppLable'] ?? ''} ${data['cardDataEntry'] ?? ''}', styles: PosStyles(align: PosAlign.center));
    }
    if (data['cardNumber'] != null) {
      addText('${data['cardNumber']}', styles: PosStyles(align: PosAlign.center));
    }
    addText('${data['transactionType']} Amount ${data['currencyCode']} ${data['amount'] != null ? formatAmount(data['amount'] as num) : '-'}', styles: PosStyles(align: PosAlign.center));
    addText(data['pinOk'] ? 'PIN OK' : 'PIN NOT OK', styles: PosStyles(align: PosAlign.center));
    addText('Authorization Code ${data['approvedCode']}', styles: PosStyles(align: PosAlign.center));
    addText('Sequence Number: ${data['sequenceNumber']}', styles: PosStyles(align: PosAlign.center));
  }
}

extension on PosStyles {
  PrinterAlignment get myposAlign {
    switch (align) {
      case PosAlign.left:
        return PrinterAlignment.left;
      case PosAlign.center:
        return PrinterAlignment.center;
      case PosAlign.right:
        return PrinterAlignment.right;
    }
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
    0x2264, 0x2320, 0x2321, 0xF7, 0x2248, 0xB0, 0x2219, 0xB7, 0x221A, 0x207F, 0xB2, 0x25A0
  };

  String check() {
    return runes.map((r) => cp437Set.contains(r) ? String.fromCharCode(r) : '?').join();
  }
}

int euroToCent(num value) {
  return (value * 100).round();
}

double centToEuro(int value) {
  return value / 100;
}

String formatAmount(num value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}