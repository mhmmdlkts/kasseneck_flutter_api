// ignore_for_file: avoid_print
//
// Example usage of the kasseneck_api package.
//
// You need an API key and a cashregister token from Kreiseck to operate a
// register — request yours at office@kreiseck.com (https://kreiseck.com).

import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';

// Local Hobex terminal (HPS) — see cardSale() below.
import 'package:kasseneck_api/hobex_hps.dart';

Future<void> main() async {
  final kasseneck = KasseneckApi(
    apiKey: 'YOUR_API_KEY',
    cashregisterToken: 'YOUR_CASHREGISTER_TOKEN',
  );

  // 1) A simple cash sale with two items.
  final receipt = await kasseneck.sellReceipt(
    paymentMethod: KeckPaymentMethod.cash,
    customerDetails: ['Max Mustermann'],
    items: [
      KasseneckItem(name: 'Coffee', quantity: 2, vat: VatRate.vat20, singlePrice: 3.20),
      KasseneckItem(name: 'Bread', quantity: 1, vat: VatRate.vat4komma9, singlePrice: 2.40),
    ],
  );
  print('Receipt ${receipt?.receiptId} — signed: ${receipt?.signatureSuccess}');

  // 2) Print it via a Bluetooth ESC/POS printer.
  await kasseneck.initBluetoothPrinter(printerAddress: 'AA:BB:CC:DD:EE:FF');
  await receipt?.printReceiptBluetooth();

  // 3) Cancel it again (RKSV cancellation receipt).
  if (receipt != null) {
    await kasseneck.cancelReceipt(receipt: receipt);
  }
}

/// Charges a card on a local Hobex terminal (HPS) and turns the result into a
/// signed Kasseneck receipt. Any other terminal works the same way — or use
/// `CreditCardProvider.custom` to pass your own card data.
Future<void> cardSale(KasseneckApi kasseneck) async {
  final hps = HpsClient(tid: '3600335'); // TID without leading zero
  final res = await hps.payment(amount: 12.50);
  if (!res.isApproved) return; // declined -> res.responseCode / res.responseText

  final card = HobexReceipt.fromHps(res);
  await kasseneck.sellReceipt(
    paymentMethod: KeckPaymentMethod.creditCard,
    creditCardProvider: card.creditCardProvider,
    cardPaymentId: card.transactionId,
    cardPaymentData: card.toCardPaymentData(),
    items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, singlePrice: 12.50)],
  );
}
