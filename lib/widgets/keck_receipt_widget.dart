import 'package:flutter/material.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class KeckReceiptWidget extends StatefulWidget {
  final Color paperColor;
  final KasseneckReceipt receipt;

  const KeckReceiptWidget({required this.receipt, this.paperColor = Colors.white10, super.key});

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


    for (VatRate key in widget.receipt.vatCategories) {
      double brutto = 0;
      for (KasseneckItem element in widget.receipt.items) {
        if (element.vat == key) {
          brutto += element.priceOne * element.amount;
        }
      }
      int mwstSatz = key.rate;
      double netto = brutto / (1 + (mwstSatz / 100));
      double mwst = brutto - netto;
      temp[0].add('${key.category} $mwstSatz%');
      temp[1].add(mwst.toStringAsFixed(2));
      temp[2].add(netto.toStringAsFixed(2));
      temp[3].add(brutto.toStringAsFixed(2));
    }
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
            Text(widget.receipt.uid, style: textStyle),
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
                    child: Text('${item.amount} x ${item.name}', style: textStyle),
                  ),
                  Text('${(item.priceOne * item.amount).toStringAsFixed(2)} ${item.vat.category}', style: textStyle),
                ],
              ),

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
            Divider(color: Theme.of(context).dividerColor),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total:', style: textStyle),
                Text('${widget.receipt.sum.toStringAsFixed(2)} EUR', style: textStyle)
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
              foregroundColor: Theme.of(context).colorScheme.onBackground,
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
      case CreditCardProvider.hobexCloudApi:
        return _hobexApiPart(widget.receipt.cardPaymentData!);
      case CreditCardProvider.custom:
        return Container();
    }
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
        Text('Batch: ${inquire['batchNumber']}', style: textStyle),
        Text('Receipt: ${inquire['externalTransactionID']}', style: textStyle),
        Text('TID: ${inquire['terminalID']}', style: textStyle),
        Text('${inquire['emvAid']}', style: textStyle),
        Text('${inquire['emvAppLable']} ${inquire['cardDataEntry']}', style: textStyle),
        Text(inquire['cardNumber'], style: textStyle),
        Text('$transactionType Amount ${inquire['currencyCode']} ${inquire['amount'].toStringAsFixed(2)}', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
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
