import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

import 'credentials.dart';

void main() {
  final creds = DemoCredentials.tryLoad();

  group('Kasseneck-Demo', () {
    late KasseneckApi api;

    setUp(() {
      api = KasseneckApi(
        apiKey: creds!.apiKey,
        cashregisterToken: creds.cashregisterToken,
      );
    });

    test('Nullbeleg wird ausgestellt und signiert', () async {
      final receipt = await api.zeroReceipt();
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, isNotEmpty);
      expect(receipt.receiptType, ReceiptType.zero);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: creds == null
          ? 'test/integration/credentials.local.json fehlt — Demo-Integrationstests übersprungen'
          : null);
}
