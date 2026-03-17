import 'package:flutter/material.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/sumup_checkout_response.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../enums/voucher_type.dart';
import '../models/keck_voucher.dart';
import '../models/print_paper.dart';


class KeckReceiptWidget extends StatefulWidget {
  final Color paperColor;
  final Color qrColor;
  final KasseneckReceipt receipt;

  const KeckReceiptWidget({required this.receipt, this.paperColor = Colors.white10, this.qrColor = Colors.black, super.key});

  @override
  State<KeckReceiptWidget> createState() => _KeckReceiptWidgetState();
}

class _KeckReceiptWidgetState extends State<KeckReceiptWidget> {

  List<List<dynamic>> temp = [];

  @override
  Widget build(BuildContext context) {
    return receiptWidget();
  }

  setTemp() {
    temp = [
      [CrossAxisAlignment.start, 'MwSt%'],
      [CrossAxisAlignment.start, 'MwSt'],
      [CrossAxisAlignment.end, 'Netto'],
      [CrossAxisAlignment.end, 'Brutto'],
    ];

    final double totalPromoVoucherValue = widget.receipt.totalPromoVoucherValue;

    final Map<VatRate, int> bruttoByVatCents = {
      for (final VatRate key in widget.receipt.vatCategories) key: 0,
    };

    for (final KasseneckItem element in widget.receipt.items) {
      if (bruttoByVatCents.containsKey(element.vat)) {
        bruttoByVatCents[element.vat] =
            (bruttoByVatCents[element.vat] ?? 0) +
                euroToCent(element.singlePrice * element.quantity);
      }
    }

    if (bruttoByVatCents.containsKey(VatRate.vat0)) {
      for (final KeckVoucher voucher in widget.receipt.vouchers ?? []) {
        if (voucher.action == VoucherAction.sell && voucher.type == VoucherType.value) {
          bruttoByVatCents[VatRate.vat0] =
              (bruttoByVatCents[VatRate.vat0] ?? 0) + euroToCent(voucher.value ?? 0);
        }
      }
    }

    final int totalPromoVoucherValueCents = euroToCent(totalPromoVoucherValue);
    final int totalAmountCents = bruttoByVatCents.values.fold(0, (sum, value) => sum + value);
    final int totalRedeemPromoVoucherUsableValueCents =
        totalPromoVoucherValueCents > totalAmountCents ? totalAmountCents : totalPromoVoucherValueCents;

    final Map<VatRate, int> promoByVatCents = {
      for (final VatRate key in widget.receipt.vatCategories) key: 0,
    };

    if (totalRedeemPromoVoucherUsableValueCents > 0 && totalAmountCents > 0) {
      int usedPromoCents = 0;

      for (final VatRate key in widget.receipt.vatCategories) {
        final int bruttoCents = bruttoByVatCents[key] ?? 0;
        final int proportionalCents =
            (totalRedeemPromoVoucherUsableValueCents * bruttoCents) ~/ totalAmountCents;
        promoByVatCents[key] = proportionalCents;
        usedPromoCents += proportionalCents;
      }

      final int remainingPromoCents = totalRedeemPromoVoucherUsableValueCents - usedPromoCents;
      if (remainingPromoCents > 0) {
        final List<VatRate> sortedKeys = [...widget.receipt.vatCategories]
          ..sort((a, b) => (bruttoByVatCents[b] ?? 0).compareTo(bruttoByVatCents[a] ?? 0));

        if (sortedKeys.isNotEmpty && (bruttoByVatCents[sortedKeys.first] ?? 0) > 0) {
          promoByVatCents[sortedKeys.first] =
              (promoByVatCents[sortedKeys.first] ?? 0) + remainingPromoCents;
        }
      }
    }

    for (VatRate key in widget.receipt.vatCategories) {
      final int bruttoCentsBeforePromo = bruttoByVatCents[key] ?? 0;
      final int promoCents = promoByVatCents[key] ?? 0;
      final int bruttoCents = bruttoCentsBeforePromo - promoCents;
      final double brutto = centToEuro(bruttoCents);
      int mwstSatz = key.rate;
      double netto = brutto / (1 + (mwstSatz / 100));
      double mwst = brutto - netto;
      temp[0].add('${key.category} $mwstSatz%');
      temp[1].add(formatAmount(mwst));
      temp[2].add(formatAmount(netto));
      temp[3].add(formatAmount(brutto));
    }
  }

  int euroToCent(double euro) {
    return (euro * 100).round();
  }

  double centToEuro(int cent) {
    return cent / 100;
  }

  TextStyle textStyle = TextStyle(
      fontFamily: 'Courier'
  );

  Widget receiptWidget() {
    setTemp();
    return SizedBox(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
          color: widget.paperColor,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (widget.receipt.logo != null)
              ...[
                Image.memory(widget.receipt.logo!),
                const SizedBox(height: 16),
              ],
            Text(widget.receipt.companyName, style: textStyle),
            Text(widget.receipt.street, style: textStyle),
            Text('${widget.receipt.zip} ${widget.receipt.city}', style: textStyle),
            Text(widget.receipt.taxInfo, style: textStyle),
            Text(widget.receipt.phone, style: textStyle),
            const SizedBox(height: 32),

            if (widget.receipt.customerDetails.isNotEmpty)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kunde:', style: textStyle),
                      Text(widget.receipt.customerDetails.first, style: textStyle),
                    ],
                  ),
                  for (int i = 1; i < widget.receipt.customerDetails.length; i++)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(),
                        Text(widget.receipt.customerDetails[i], style: textStyle),
                      ],
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Datum:', style: textStyle),
                Text(widget.receipt.readableTime, style: textStyle)
              ],
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kassen-ID:', style: textStyle),
                Text(widget.receipt.cashregisterId, style: textStyle)
              ],
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Beleg-ID:', style: textStyle),
                Text(widget.receipt.receiptId, style: textStyle)
              ],
            ),
            const SizedBox(height: 32),

            for (KasseneckItem item in widget.receipt.items)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('${item.quantity} x ${item.name}${item.quantity > 1 ? ' je ${formatAmount(item.singlePrice)}' : ''}', style: textStyle),
                  ),
                  Text('${formatAmount(item.singlePrice * item.quantity)} ${item.vat.category}', style: textStyle),
                ],
              ),
            for (KeckVoucher voucher in widget.receipt.vouchers??[])
              if (voucher.action == VoucherAction.sell && voucher.type == VoucherType.value)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text('1 x ${voucher.receipText}', style: textStyle),
                    ),
                    Text('${formatAmount(voucher.value??0)} ${VatRate.vat0.category}', style: textStyle),
                  ],
                )
              else if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.promo)
                ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(voucher.receipText, style: textStyle),
                      ),
                      Text('-${formatAmount(voucher.value??0)} EUR', style: textStyle),
                    ],
                  ),
                ],

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: temp.map((e) => Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: e[0],
                children: e.where((element) => element.runtimeType==String).map((e) => Text(e, style: textStyle)).toList(),
              )).toList(),
            ),
            Divider(color: widget.qrColor),
            if (widget.receipt.sum != widget.receipt.subSum)
              ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Zwischensumme', style: textStyle),
                    Text('${formatAmount(widget.receipt.subSum)} EUR', style: textStyle)
                  ],
                ),
                for (KeckVoucher voucher in widget.receipt.vouchers??[])
                  if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.value)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(voucher.receipText, style: textStyle),
                        ),
                        Text('-${formatAmount(voucher.value??0)} EUR', style: textStyle),
                      ],
                    ),
                Divider(color: widget.qrColor),
              ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Gesamt:', style: textStyle),
                Text('${formatAmount(widget.receipt.sum)} EUR', style: textStyle)
              ],
            ),
            const SizedBox(height: 32),
            if (widget.receipt.legalMessage.isNotEmpty)
              ...[
                for (String line in widget.receipt.legalMessage)
                  Text(line, style: textStyle, textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
            if (widget.receipt.isSigFailed)
              ...[
                Text(RKSVService.signatureDeviceDamagedKey, style: textStyle, textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
            QrImageView(
              data: widget.receipt.qr,
              size: 200,
              foregroundColor: widget.qrColor,
              backgroundColor: Colors.transparent,
            ),
            if (widget.receipt.creditCardProvider != null && widget.receipt.creditCardProvider != CreditCardProvider.custom && widget.receipt.cardPaymentData != null && widget.receipt.cardPaymentData!.isNotEmpty)
              ...[
                const SizedBox(height: 32),
                _creditCardPart(),
              ],
            if (widget.receipt.thanksMessage.isNotEmpty)
              ...[
                const SizedBox(height: 16),
                for (String line in widget.receipt.thanksMessage)
                  Text(line, style: textStyle, textAlign: TextAlign.center),
              ],
            const SizedBox(height: 32),
            Text(widget.receipt.footer1, style: textStyle),
            Text(widget.receipt.footer2, style: textStyle),
            if (widget.receipt.footer3 != null)
              Text(widget.receipt.footer3!, style: textStyle),
            if (widget.receipt.footer4 != null)
              Text(widget.receipt.footer4!, style: textStyle),
          ],
        ),
      ),
    );
  }

  Widget _creditCardPart() {
    if (widget.receipt.creditCardProvider == null) {
      return Container();
    }
    switch (widget.receipt.creditCardProvider!) {
      case CreditCardProvider.gpTomAndroid:
      case CreditCardProvider.gpTomIos:
        return _gpTomPart(widget.receipt.cardPaymentData!);
      case CreditCardProvider.sumup:
        return _sumupPart(SumupCheckoutResponse.fromMap(widget.receipt.cardPaymentData!));
      case CreditCardProvider.myposPro:
        return _myPosProPart(widget.receipt.cardPaymentData!);
      case CreditCardProvider.hobexCloudApi:
        return _hobexApiPart(widget.receipt.cardPaymentData!);
      case CreditCardProvider.custom:
        return Container();
    }
  }

  Widget _sumupPart(SumupCheckoutResponse sumup) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // add prowider name
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SumUp Beleg', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Kartentyp:', style: textStyle),
            Text(sumup.cardType ?? 'Unbekannt', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Kartennummer:', style: textStyle),
            Text('**** ${sumup.cardLastDigits ?? ''}', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Zahlungstyp:', style: textStyle),
            Text(sumup.paymentType ?? 'n/a', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Gesamtbetrag:'),
            Text('${sumup.amount != null ? formatAmount(sumup.amount!) : '-'} ${sumup.currency ?? ''}'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Transaktionscode:', style: textStyle),
            Text(sumup.transactionCode ?? '-', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Modus:', style: textStyle),
            Text(sumup.entryMode?.toUpperCase() ?? '-', style: textStyle),
          ],
        ),
      ],
    );
  }

  Widget _myPosProPart(Map<String, dynamic> data) {

    String dateTime = data['date_time'];
    String day = dateTime.substring(4, 6);
    String month = dateTime.substring(2, 4);
    String year = '20${dateTime.substring(0, 2)}';
    String hour = dateTime.substring(6, 8);
    String minute = dateTime.substring(8, 10);
    String second = dateTime.substring(10, 12);
    String formattedDate = '$day.$month.$year $hour:$minute:$second';

    bool isSignatureRequired = data['signature_required'] == true;

    return Column(
      children: [

        Text('MyPos Beleg', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TERMINAL ID:', style: textStyle),
            Text(data['TID'] ?? '-', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DATUM:', style: textStyle),
            Text(formattedDate, style: textStyle),
          ],
        ),
        Text(data['application_name'], style: textStyle.copyWith(fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('KARTE:', style: textStyle),
            Text(data['pan'] ?? '-', style: textStyle),
          ],
        ),
        if (isSignatureRequired)
          ...[
            const SizedBox(height: 32),
            Text('------------------', style: textStyle),
            Text('Unterschrift', style: textStyle),
          ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('STAN:', style: textStyle),
            Text(data['STAN']?.toString().padLeft(6, '0') ?? '-', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('AUTH. CODE:', style: textStyle),
            Text(data['authorization_code'] ?? '-', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RRN:', style: textStyle),
            Text(data['reference_number'] ?? '-', style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('AID:', style: textStyle),
            Text(data['AID'] ?? '-', style: textStyle),
          ],
        ),
      ],
    );
  }

  Widget _gpTomPart(Map<String, dynamic> inquire) {
    String transactionType = '';
    switch (inquire[transactionType]) {
      case 1: transactionType = 'Sale'; break;
      case 2: transactionType = 'Void'; break;
      case 4: transactionType = 'Close Batch'; break;
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('GP Tom Beleg', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        Text('Batch: ${inquire['batchNumber']}', style: textStyle),
        Text('Receipt: ${inquire['externalTransactionID']}', style: textStyle),
        Text('TID: ${inquire['terminalID']}', style: textStyle),
        Text('${inquire['emvAid']}', style: textStyle),
        if (inquire['emvAppLable'] != null || inquire['cardDataEntry'] != null)
          Text('${inquire['emvAppLable']??''} ${inquire['cardDataEntry']??''}', style: textStyle),
        if (inquire['cardNumber'] != null)
          Text('Card Number: ${inquire['cardNumber']}', style: textStyle),
        Text('$transactionType Amount ${inquire['currencyCode']} ${formatAmount(inquire['amount'] as num)}', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
        Text(inquire['pinOk'] == true ? 'PIN OK' : 'PIN NOT OK', style: textStyle),
        Text('Authorization Code ${inquire['approvedCode']}', style: textStyle),
        Text('Sequence Number: ${inquire['sequenceNumber']}', style: textStyle),
      ],
    );
  }

  Widget _hobexApiPart(Map<String, dynamic> data) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Hobex Beleg', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Datum:', style: textStyle),
            Text(data['date'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TID:', style: textStyle),
            Text(data['tid'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Nr.:', style: textStyle),
            Text(data['no'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Art:', style: textStyle),
            Text(data['type'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Karte:', style: textStyle),
            Text(data['cardBrand'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PAN:', style: textStyle),
            Text(data['cardNumber'], style: textStyle),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RC:', style: textStyle),
            Text(data['responseCode'], style: textStyle),
          ],
        ),
        if (data['cvm'] == '1')
          ...[
            const SizedBox(height: 32),
            Text('------------------', style: textStyle),
            Text('Unterschrift', style: textStyle),
          ],
      ],
    );
  }
}
