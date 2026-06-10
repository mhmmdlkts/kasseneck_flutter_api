# Kasseneck Flutter API

A Flutter package providing a simple interface to the Austrian **Kasseneck** cash register system.  
You will need a valid **API Key** and **Cashregister Token** to operate your Kasseneck cash register via this API.

## Installation

Add the following line to the `dependencies` section of your `pubspec.yaml`:

```yaml
dependencies:
  kasseneck_api: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Usage

```dart
import 'package:kasseneck_api/kasseneck_api.dart';

void main() async {
  // Create an instance with your Kasseneck credentials
  final kasseneck = KasseneckApi(
    apiKey: 'YOUR_API_KEY',
    cashregisterToken: 'YOUR_CASHREGISTER_TOKEN',
  );

  // Example: Create a standard receipt
  try {
    final receipt = await kasseneck.createReceipt(
      receiptType: 'standard',
      paymentMethod: 'cash',
      items: [
        KasseneckItem(name: 'Trip', amount: 1, vat: 10, priceOne: 19.99),
      ],
      customerDetails: 'John Doe',
    );

    print('Receipt created: ${receipt?.receiptId}');
  } catch (error) {
    print('Error creating receipt: $error');
  }
}
```

## hobex Payment Service (HPS)

Direct driver for a **local hobex terminal** (REST API on `http://127.0.0.1:8080` when the
app runs on the terminal itself). Deliberately separate from the older cloud-based Hobex
(`KasseneckApi.hobexPay` / `hobexRefund`).

```dart
import 'package:kasseneck_api/hobex_hps.dart'; // HpsClient, TransactionResponse, HobexReceipt

final hps = HpsClient(tid: '3600335'); // TID without leading zero

// 1) Trigger the card payment on the terminal
final res = await hps.payment(amount: 12.50);
if (!res.isApproved) {
  // declined -> res.responseCode / res.responseText
  return;
}

// 2) Turn the terminal result into Kasseneck card-payment data
final hobexReceipt = HobexReceipt.fromHps(res);

// 3) Create the RKSV receipt (the card data is rendered on the printout)
final receipt = await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: hobexReceipt.creditCardProvider, // hobexHps
  cardPaymentId: hobexReceipt.transactionId,
  cardPaymentData: hobexReceipt.toCardPaymentData(),
  items: [KasseneckItem(name: 'Brot', quantity: 1, vat: VatRate.vat10, singlePrice: 1.20)],
);
```

Further operations: `hps.refund(...)`, `hps.cancel(...)`, `hps.transactionStatus(...)`,
`hps.diagnosis()` (health check). Errors are thrown as `HpsException` / `HpsHttpException` /
`HpsConnectionException`; a **declined** payment is not an exception but `res.isApproved == false`.

Support

For questions or support inquiries, feel free to contact office@kreiseck.com.

Happy coding with the Kasseneck Flutter API!