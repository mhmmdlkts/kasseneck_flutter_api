import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:my_pos/models/my_pos_paper.dart';
import 'package:qr/qr.dart';

import '../enums/credit_card_provider.dart';
import '../enums/qr_print_mode.dart';
import '../enums/vat_rate.dart';
import '../enums/voucher_action.dart';
import '../enums/voucher_type.dart';
import '../services/rksv_service.dart';
import 'kasseneck_item.dart';

import 'keck_voucher.dart';

class PrintPaper {
  final KeckPaperSize paperSize;
  final List<Map<String, dynamic>> commands = [];
  final EscPosGenerator generator;
  List<Uint8List> bytes = [];
  final MyPosPaper myPosPaper = MyPosPaper();

  PrintPaper({required this.paperSize, required CapabilityProfile profile})
      : generator = EscPosGenerator(paperSize.paperSize, profile) {
    reset();
  }

  void addBytes(Uint8List byte) {
    bytes.add(byte);
    // myPosPaper does not support raw bytes
  }

  void addText(String text, {PosStyles styles = const PosStyles()}) {
    // ESC/POS kodiert per latin1 -> Zeichen > 0xFF wuerden werfen und den
    // gesamten Druck abbrechen. Daher fuer den Generator entschaerfen; MyPos
    // vertraegt Unicode und bekommt den Originaltext.
    bytes.add(Uint8List.fromList(generator.text(_printable(text), styles: styles)));
    myPosPaper.addText(text, alignment: styles.myposAlign);
  }

  /// Macht Text fuer den ESC/POS-Drucker sicher: der Generator kodiert per
  /// latin1 und wirft bei Zeichen ausserhalb (typografische Anfuehrungszeichen,
  /// Gedankenstriche, Euro, Emoji, ...). Gaengige Zeichen werden auf ein
  /// ASCII-Aequivalent gemappt, alles andere durch '?' ersetzt -> der Druck
  /// laeuft durch statt komplett auszufallen. Latin-1-Zeichen (inkl. Umlaute,
  /// 0..0xFF) bleiben unveraendert.
  static String _printable(String text) {
    const Map<int, String> repl = {
      0x2013: '-', 0x2014: '-', 0x2011: '-', 0x2212: '-', // – — ‑ −
      0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"', // “ ” „ ‟
      0x2018: "'", 0x2019: "'", 0x201A: "'", 0x2032: "'", // ‘ ’ ‚ ′
      0x2026: '...', 0x2022: '*', // … •
      0x2713: 'x', 0x2714: 'x', // ✓ ✔
      0x20AC: 'EUR', 0x2122: 'TM', 0x20BA: 'TL', // € ™ ₺
    };
    final StringBuffer sb = StringBuffer();
    for (final int rune in text.runes) {
      final String? mapped = repl[rune];
      if (mapped != null) {
        sb.write(mapped);
      } else if (rune <= 0xFF) {
        sb.writeCharCode(rune); // Latin-1 (inkl. Umlaute) -> unveraendert
      } else if (_isEmojiOrZeroWidth(rune)) {
        // Emoji/Modifier/Nullbreiten-Zeichen ersatzlos entfernen – sonst wuerde
        // ein einzelnes (oft aus mehreren Code-Points bestehendes) Emoji als
        // ein oder mehrere '?' auf dem Bon landen.
      } else {
        sb.write('?'); // sonstiges Zeichen (z.B. andere Schrift) -> Platzhalter
      }
    }
    return sb.toString();
  }

  /// Emoji-, Modifier- und Nullbreiten-/Steuerzeichen, die auf dem Beleg nichts
  /// verloren haben und sonst als '?' erscheinen wuerden.
  static bool _isEmojiOrZeroWidth(int r) {
    return r == 0x200D || // Zero-Width Joiner
        (r >= 0x200B && r <= 0x200F) ||
        r == 0x2060 ||
        r == 0xFEFF ||
        (r >= 0xFE00 && r <= 0xFE0F) || // Variation Selectors
        (r >= 0x1F3FB && r <= 0x1F3FF) || // Hautton-Modifier
        (r >= 0x1F000 && r <= 0x1FAFF) || // Emoji-Bloecke
        (r >= 0x2600 && r <= 0x27BF) || // Symbole + Dingbats
        (r >= 0x2B00 && r <= 0x2BFF) || // Symbole & Pfeile
        (r >= 0x2300 && r <= 0x23FF); // technische Symbole (z.B. ⌚⏰)
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

  Future<void> addImage(RasterImage image, {PosAlign align = PosAlign.center}) async {
    final RasterImage flat = compositeOnWhite(image);
    bytes.add(Uint8List.fromList(generator.imageRaster(flat)));
    final pngBytes = await encodePng(flat);
    myPosPaper.addImage(pngBytes);
  }

  Future<void> addBase64Image(String base64, {PosAlign align = PosAlign.center}) async {
    final image = await decodePng(base64Decode(base64));
    await addImage(image, align: align);
  }

  Future<void> addUint8ListImage(Uint8List image, {PosAlign align = PosAlign.center}) async {
    final img = await decodePng(image);
    await addImage(img, align: align);
  }

  void addQrCode(String data, {QRSize size = QRSize.size6}) {
    bytes.add(Uint8List.fromList(generator.qrcode(data, size: size)));
    myPosPaper.addQrCode(data, size: 280);
  }

  /// QR als Bild. [raster] true → GS v 0 (imageRaster), false → ESC * (image).
  /// Welcher Befehl funktioniert, hängt vom Drucker ab — daher umschaltbar.
  ///
  /// Der QR wird direkt aus der Modul-Matrix gerastert: jedes Modul wird auf ein
  /// ganzzahliges `scale×scale`-Quadrat abgebildet (rein schwarz/weiss, kein
  /// Anti-Aliasing). Dadurch sind die Kanten scharf per Konstruktion und das
  /// Bild ist deutlich kleiner/schneller ueber Bluetooth als der fruehere
  /// QrPainter→PNG-Roundtrip.
  Future<void> addQrCodeAsImage(String data, {int size = 280, bool raster = true}) async {
    try {
      final RasterImage img = renderQrMatrix(data, size: size);
      bytes.add(Uint8List.fromList(
        raster ? generator.imageRaster(img) : generator.image(img),
      ));
      myPosPaper.addImage(await encodePng(img));
    } catch (e) {
      if (kDebugMode) print('Error in addQrCodeAsImage: $e');
    }
  }

  /// Rastert die QR-Modul-Matrix von [data] in ein reines schwarz/weiss-Bild
  /// (RGBA, Werte nur 0 oder 255 — kein Anti-Aliasing, keine Graustufen).
  ///
  /// Quiet-Zone = 4 Module rundum. Der ganzzahlige Modul-Scale wird aus [size]
  /// abgeleitet (`floor`, mind. 2, max. 64), sodass jedes Modul exakt
  /// `scale×scale` Pixel belegt. Ergebnis ist quadratisch mit Kantenlaenge
  /// `(moduleCount + 8) * scale`.
  static RasterImage renderQrMatrix(String data, {int size = 280}) {
    final QrCode qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final QrImage qi = QrImage(qr);
    final int n = qr.moduleCount;
    const int quiet = 4; // Module Quiet-Zone rundum
    final int full = n + quiet * 2;
    final int scale = (size / full).floor().clamp(2, 64);
    final int dim = full * scale;

    final RasterImage img = RasterImage.filled(dim, dim, 255, 255, 255, 255);
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (!qi.isDark(r, c)) continue;
        final int x0 = (c + quiet) * scale;
        final int y0 = (r + quiet) * scale;
        for (int dy = 0; dy < scale; dy++) {
          int idx = ((y0 + dy) * dim + x0) * 4;
          for (int dx = 0; dx < scale; dx++) {
            img.rgba[idx] = 0; // R
            img.rgba[idx + 1] = 0; // G
            img.rgba[idx + 2] = 0; // B
            img.rgba[idx + 3] = 255; // A (voll deckend schwarz)
            idx += 4;
          }
        }
      }
    }
    return img;
  }

  void reset() {
    bytes.clear();
    bytes.add(Uint8List.fromList(generator.reset()));
    bytes.add(Uint8List.fromList(generator.setGlobalCodeTable('CP1252')));
    myPosPaper.commands.clear();
  }

  Future setKeckReceipt(KasseneckReceipt receipt, {QrPrintMode qrMode = QrPrintMode.imageRaster}) async {
    reset();

    if (receipt.logo != null) {
      final RasterImage image = await decodePng(receipt.logo!);
      final RasterImage resized = resizeWidth(image, paperSize.imageWidth);
      await addImage(resized);
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
      addDoubleText('$amount${item.name.check()}${item.quantity > 1 ? ' je ${formatAmount(item.singlePrice)}' : ''}', '${formatCents(item.totalCents)} ${item.vat.category}', leftWidth: 7, rightWidth: 5);
    }

    int totalPromoVoucherValueCents = 0;
    for (KeckVoucher voucher in receipt.vouchers??[]) {

      if (voucher.isValid && voucher.action == VoucherAction.sell) {
        itemsByVat[VatRate.vat0] ??= [];
        itemsByVat[VatRate.vat0]!.add(KasseneckItem(
          name: voucher.receiptText,
          quantity: 1,
          priceCents: voucher.valueCents ?? 0,
          vat: VatRate.vat0
        ));
      }
      if (voucher.action == VoucherAction.sell && voucher.type == VoucherType.value) {
        String amount = '1  x ';
        addDoubleText('$amount${voucher.receiptText}', '${formatCents(voucher.valueCents??0)} ${VatRate.vat0.category}', leftWidth: 7, rightWidth: 5);
      }
      if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.promo) {
        totalPromoVoucherValueCents += voucher.valueCents ?? 0;
        addDoubleText(voucher.receiptText, '-${formatCents(voucher.valueCents??0)} EUR', leftWidth: 7, rightWidth: 5);
      }
    }

    final Map<VatRate, int> vatTableBruttoByVatCents = {
      for (final VatRate key in itemsByVat.keys) key: 0,
    };

    itemsByVat.forEach((key, value) {
      int bruttoCents = 0;
      for (final KasseneckItem element in value) {
        bruttoCents += element.totalCents;
      }
      vatTableBruttoByVatCents[key] = bruttoCents;
    });

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
      final num mwstSatz = key.rate;
      final double netto = brutto / (1 + (mwstSatz / 100));
      final double mwst = brutto - netto;

      _addTable('${key.category} ${key.rate.toString().replaceAll('.', ',')}%', formatAmount(mwst), formatAmount(netto), formatAmount(brutto));
    });

    addFullHorizontalLine();

    if (receipt.sumCents != receipt.subSumCents) {
      addDoubleText('Zwischensumme', '${formatCents(receipt.subSumCents)} EUR');

      for (KeckVoucher voucher in receipt.vouchers??[]) {
        if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.value) {
          addDoubleText(voucher.receiptText, '-${formatCents(voucher.valueCents??0)} EUR');
        }
      }

      addFullHorizontalLine();
    }
    addDoubleText('Gesamt:', '${formatCents(receipt.sumCents)} EUR');

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


    switch (qrMode) {
      case QrPrintMode.imageRaster:
        await addQrCodeAsImage(receipt.qr, raster: true);
        break;
      case QrPrintMode.imageBitImage:
        await addQrCodeAsImage(receipt.qr, raster: false);
        break;
      case QrPrintMode.native:
        addQrCode(receipt.qr);
        break;
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
          case CreditCardProvider.hobexHps:
            _hobexHps(receipt.cardPaymentData!);
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
      } catch (_) {
        // Fehlerhafte cardPaymentData darf den Beleg-Druck nicht abbrechen
      }
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

    if (receipt.showKreiseckLogo) {
      await _addKreiseckBranding();
    }

    addCut();
  }

  /// Dezentes Kreiseck-Branding als allerletzter Block vor dem Cut.
  /// Das s/w-Logo liegt als Package-Asset bei (Druck funktioniert offline,
  /// das Backend liefert nur das Flag `kreiseck_logo`).
  static RasterImage? _kreiseckLogo;

  Future<void> _addKreiseckBranding() async {
    if (_kreiseckLogo == null) {
      // Asset-Key unterscheidet sich je nach Kontext (eigenes Paket vs. App).
      for (final key in [
        'packages/kasseneck_api/assets/kreiseck_logo_print.png',
        'assets/kreiseck_logo_print.png',
      ]) {
        try {
          final data = await rootBundle.load(key);
          _kreiseckLogo = await decodePng(data.buffer.asUint8List());
          break;
        } catch (_) {
          // naechsten Key probieren
        }
      }
    }
    final logo = _kreiseckLogo;
    if (logo == null) return; // Branding darf den Druck nie verhindern

    addFeed();
    addText('powered by', styles: PosStyles(align: PosAlign.center));
    // Breite muss ein Vielfaches von 8 sein — sonst crasht die Rasterisierung
    // des ESC/POS-Generators beim Byte-Padding (fixed-length list).
    final int width = ((paperSize.imageWidth * 0.85) ~/ 8) * 8;
    await addImage(resizeWidth(logo, width));
  }

  void _addTable(String val1, String val2, String val3, String val4) {
    bool isBig = paperSize >= KeckPaperSize.mm80;
    List<int> bytes = generator.row([
      PosColumn(
        text: _printable(val1),
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: _printable(val2),
        width: isBig ? 4 : 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: _printable(val3),
        width: 3,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: _printable(val4),
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
        text: _printable(leftValue),
        width: leftWidth,
        styles: PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: _printable(rightValue),
        width: rightWidth,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);

    this.bytes.add(Uint8List.fromList(bytes));
    myPosPaper.addDoubleText(leftValue, rightValue);
  }



  void _hobexHps(Map<String, dynamic> data) {
    addText('Hobex Beleg', styles: PosStyles(align: PosAlign.center, bold: true));
    addDoubleText('Datum:', data['date']);
    addDoubleText('TID:', data['tid']);
    addDoubleText('Nr.:', data['no']);
    addDoubleText('Art:', data['type']);
    addDoubleText('Karte:', data['cardBrand']);
    addDoubleText('PAN:', data['cardNumber']);
    if ((data['cardExpiry'] ?? '').toString().isNotEmpty) {
      addDoubleText('Gueltig:', data['cardExpiry']);
    }
    if ((data['approvalCode'] ?? '').toString().isNotEmpty) {
      addDoubleText('Genehmigung:', data['approvalCode']);
    }
    addDoubleText('RC:', data['responseCode']);
    if (data['cvm'] == '1') {
      addFeed(lines: 2);
      addText('------------------', styles: PosStyles(align: PosAlign.center));
      addText('Unterschrift', styles: PosStyles(align: PosAlign.center));
    }
    addFeed();
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
    final String transactionType = gpTomTransactionType(data);
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
    addText('${transactionType!=''?'$transactionType ':''}Amount ${data['currencyCode']} ${formatGpTomAmount(data['amount'])}', styles: PosStyles(align: PosAlign.center));
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

/// Formatiert einen Cent-Betrag als Euro-String (z. B. 1999 -> "19,99").
String formatCents(int cents) {
  return formatAmount(cents / 100);
}

/// Betrag aus GP-Tom-`cardPaymentData`: das Plugin liefert ab 0.1.0 Cent
/// (int), auf älteren gespeicherten Belegen steht Euro (double). null → '-'.
String formatGpTomAmount(dynamic value) {
  if (value == null) return '-';
  final num n = value as num;
  return n is int ? formatCents(n) : formatAmount(n);
}

/// GP-Tom-`transactionType` aus `cardPaymentData`: das Plugin-`toMap`
/// schreibt den Key mit Tippfehler (`transacitonType`), ältere Daten ohne.
String gpTomTransactionType(Map<String, dynamic> data) {
  switch (data['transactionType'] ?? data['transacitonType']) {
    case 1: return 'Sale';
    case 2: return 'Void';
    case 3: return 'Refund';
    case 4: return 'Close Batch';
  }
  return '';
}