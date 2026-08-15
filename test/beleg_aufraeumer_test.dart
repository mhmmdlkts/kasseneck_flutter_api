import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/enums/stripe_link_mode.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';
import 'package:kasseneck_api/src/printing/escpos/generator.dart';
import 'package:kasseneck_api/src/printing/escpos/enums.dart';
import 'package:kasseneck_api/src/printing/escpos/capability_profile.dart';

import 'helpers/test_receipts.dart';

// Drei Abnahme-Befunde vom 14.8. (Abnahmeprotokoll, "Nebenbei gefunden"):
// die USt-Zeile des Beleg-Widgets ging nicht auf, das oeffnende « blieb auf
// Papier stehen, und der Stripe-Zahllink verlor E-Mail und Telefon still an
// falsche Feldnamen.

void main() {
  testWidgets('USt-Zeile geht auf: 39 Cent zu 20 % zeigt 0,33 / 0,06', (tester) async {
    // Getrennt aus Gleitkommazahlen gerundet stand hier 0,33 / 0,07 -- Netto
    // plus MwSt ergab 0,40 statt 0,39, und die Browser-Kasse zeigte fuer
    // DENSELBEN Beleg andere Werte. (In Dart kippen andere Betraege als im
    // JS-Zwilling -- 39 und 45 Cent sind hier die kleinsten Faelle.)
    final receipt = buildReceipt(
      items: [KasseneckItem(name: 'Grenzfall', quantity: 1, vat: VatRate.vat20, priceCents: 39)],
    );
    // Belegbreite braucht Platz -- das Standard-Testfenster laesst den Beleg
    // ueberlaufen, und eine Overflow-Ausnahme faellte den Test statt der
    // Zusage, um die es geht.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Der Beleg ueberlaeuft unter dem Ahem-Testfont sein eigenes Row-Layout --
    // geprueft wird hier der ZAHLENWERT der USt-Zeile, nicht das Layout.
    // Overflow-Meldungen werden deshalb fuer diesen Test verschluckt.
    final vorher = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      vorher?.call(details);
    };
    addTearDown(() => FlutterError.onError = vorher);
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(child: KeckReceiptWidget(receipt: receipt)),
    ));

    expect(find.textContaining('0,33'), findsWidgets);
    expect(find.textContaining('0,06'), findsWidgets);
    expect(find.textContaining('0,07'), findsNothing);
  });

  test('beide Guillemets werden zum geraden Anfuehrungszeichen', () {
    // Nur das schliessende » wurde ersetzt -- auf Papier stand ein schiefes
    // Paar («x"). Im JS-Zwilling laengst behoben.
    final gen = EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());
    final bytes = gen.text('«x»');
    expect(bytes.join(','), contains('"x"'.codeUnits.join(',')));
  });

  test('Stripe-Zahllink sendet customer_email und customer_phone -- die Namen des Backends', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        json.encode({'status': 'success', 'message': '', 'data': {'id': 's', 'url': 'u', 'expires_at': 1}}),
        200,
      );
    });
    final api = KasseneckApi(
      apiKey: 'kr_test_x',
      cashregisterToken: 'cb_test_x',
      httpClient: client,
    );

    try {
      await api.createStripeLink(
        items: [KasseneckItem(name: 'Kaffee', quantity: 1, vat: VatRate.vat20, priceCents: 350)],
        createReceiptAfterPayment: true,
        mode: StripeLinkMode.payment,
        customerEmail: 'gast@example.org',
        customerPhone: '+43 660 0000000',
      );
    } catch (_) {
      // Das Antwort-Parsen darf scheitern -- gemessen wird die ANFRAGE.
    }

    final params = (json.decode(captured.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
    expect(params['customer_email'], 'gast@example.org');
    expect(params['customer_phone'], '+43 660 0000000');
    expect(params.containsKey('customerEmail'), isFalse,
        reason: 'Der alte Name fiel im Backend still unter den Tisch -- der Gast bekam keine Bestaetigung.');
    expect(params.containsKey('customerPhone'), isFalse);
  });
}
