import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/printer_service.dart';

import 'helpers/test_receipts.dart';

/// Der Beleg wird an EINER Stelle gebaut -- im Backend, über
/// `@kreiseck/kasseneck-api`. Alles hier rendert nur noch.
///
/// WARUM DIESE DATEI EXISTIERT
///
/// Es gab zwei Bauer: das Zeilenmodell des Pakets und `setKeckReceipt` hier.
/// Wo sie sich unterschieden, zeigte derselbe Beleg je nach Oberfläche etwas
/// anderes — bei einer Stripe-Zahlung standen auf dem Bon Marke, letzte vier
/// Ziffern und Referenz, im PDF nur „Kartenzahlung". Der Druck geht jetzt über
/// das gelieferte Layout; `setKeckReceipt` ist nur noch Rückfall.
///
/// Zwei Dinge hält diese Datei fest: dass der Layout-Weg wirklich genommen
/// wird, und dass der Rückfall genau dann greift, wenn das Layout weniger
/// zeigt als der Beleg hergibt.
final _wurzel = Directory('test/fixtures/vertrag');

BelegLayout _layout(String name) =>
    BelegLayout.fromJson(jsonDecode(File('${_wurzel.path}/erwartet/$name.lines.json').readAsStringSync()))!;

/// Der gedruckte Text, wie ihn der Bon zeigt (ohne Steuerbytes).
Future<String> _gedruckt(KasseneckReceipt receipt) async {
  final paper = await KeckPrinterService.getPaperFromReceipt(receipt, KeckPaperSize.mm80);
  return latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
}

void main() {
  test('mit Layout druckt der Bon GENAU die gelieferten Zeilen', () async {
    // Das Layout gehört zu einem anderen Betrieb als der Beleg. Steht dessen
    // Firmenname auf dem Bon, kam er aus dem Layout -- und nicht aus dem
    // Beleg, den der alte Bauer gelesen hätte.
    final receipt = buildReceipt(paymentMethod: KeckPaymentMethod.cash)..layout = _layout('verkauf-bar');
    expect(await _gedruckt(receipt), contains('Bäckerei Muster'));
  });

  test('ohne Layout druckt weiterhin der alte Bauer', () async {
    // Älteres Backend: `layout` fehlt. Der Bon muss trotzdem entstehen --
    // ein Beleg darf nie am fehlenden Zeilenmodell scheitern.
    final receipt = buildReceipt(paymentMethod: KeckPaymentMethod.cash);
    expect(receipt.layout, isNull);
    expect(await _gedruckt(receipt), contains('TEST-ID-1'));
  });

  group('Rückfall bei unvollständigem Layout', () {
    final kartendaten = {
      'paymentMethodType': 'card',
      'cardBrand': 'Visa',
      'cardLastDigits': '4242',
      'amount': 12000,
      'currency': 'eur',
    };

    test('Kartendaten am Beleg, aber kein Block im Layout -> unvollstaendig', () {
      // So sah ein Layout bis Paket 0.8.0 aus: die Zahlung ist im Beleg, das
      // Zeilenmodell zeigt sie nicht.
      final receipt = buildReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentData: kartendaten,
        cardPaymentId: 'pi_3Qxx',
      )..layout = _layout('verkauf-bar');
      expect(receipt.layoutIstVollstaendig, isFalse);
    });

    test('ohne Kartendaten ist ein Layout ohne Block vollständig', () {
      // Sonst fiele JEDER Barbeleg auf den alten Bauer zurück.
      final receipt = buildReceipt(paymentMethod: KeckPaymentMethod.cash)..layout = _layout('verkauf-bar');
      expect(receipt.layoutIstVollstaendig, isTrue);
    });

    test('ohne Layout ist unvollstaendig', () {
      expect(buildReceipt().layoutIstVollstaendig, isFalse);
    });

    test('der Rückfall druckt die Kartenzahlung, statt sie zu verschweigen', () async {
      final receipt = buildReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentData: kartendaten,
        cardPaymentId: 'pi_3Qxx',
      )..layout = _layout('verkauf-bar');
      final text = await _gedruckt(receipt);
      expect(text, contains('Stripe'));
      expect(text, contains('4242'));
      // Und eben NICHT die Zeilen des fremden Layouts.
      expect(text, isNot(contains('Bäckerei Muster')));
    });
  });
}
