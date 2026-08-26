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
      // Preise in Cent (320 = 3,20 EUR) — alternativ KasseneckItem.euro(singlePrice: 3.20)
      KasseneckItem(name: 'Coffee', quantity: 2, vat: VatRate.vat20, priceCents: 320),
      KasseneckItem(name: 'Bread', quantity: 1, vat: VatRate.vat4komma9, priceCents: 240),
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
///
/// Use [HpsPayments], not [HpsClient.payment] directly. Two reasons, both paid
/// for in real money on 2026-08-24:
///
///  * It fixes the transaction id **before** the first request goes out. Let
///    the client generate it and you only learn it from the response — so if
///    the response never arrives, you cannot query or void the transaction,
///    and every retry is a second, independent charge.
///  * It answers the only question a caller has — may I retry? — with three
///    values instead of a boolean. `!isApproved` lumps "declined" together
///    with "still running" and with "no idea".
Future<void> cardSale(KasseneckApi kasseneck) async {
  final payments = HpsPayments(
    HpsClient(tid: '3600335'), // TID without leading zero
  );

  // Fix the id first; persist it if you want to survive an app restart.
  final txId = HpsClient.newTransactionId();
  final res = await payments.pay(amount: 12.50, transactionId: txId);

  switch (res.outcome) {
    case CardPaymentOutcome.declined:
      // Proven: nothing was charged. Retrying is safe.
      print('Declined (${res.response?.responseCode}) — safe to retry');
      return;
    case CardPaymentOutcome.unresolved:
      // NOT the same as declined. The card may well have been charged.
      // Never retry silently: warn, and keep res.transactionId — it is the
      // only handle left for transactionStatus() or cancel().
      print('Outcome unknown for ${res.transactionId} — do NOT charge again');
      print(res.steps.join('\n'));
      return;
    case CardPaymentOutcome.approved:
      break;
  }

  final card = HobexReceipt.fromHps(res.response!);
  await kasseneck.sellReceipt(
    paymentMethod: KeckPaymentMethod.creditCard,
    creditCardProvider: card.creditCardProvider,
    cardPaymentId: card.transactionId,
    cardPaymentData: card.toCardPaymentData(),
    items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
  );
}
