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

Support

For questions or support inquiries, feel free to contact office@kreiseck.com.

Happy coding with the Kasseneck Flutter API!