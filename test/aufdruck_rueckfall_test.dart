import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/registration_info.dart' show CancellationOf;
import 'package:kasseneck_api/pos.dart' show cancellationErrorCodes, cancellationErrorMessage, messageText;
import 'package:kasseneck_api/services/printer_service.dart';
import 'package:kasseneck_api/src/receipt/aufdruck.dart';

import 'helpers/test_receipts.dart';

/// Der Rueckfall ohne Server-Layout (`setKeckReceipt`) druckt denselben
/// Aufdruck wie das Server-Layout: Warnrahmen TESTKASSE/TESTSIGNATUR und die
/// Belegart bzw. die Nacherfassung. Die Regeln werden gegen die 89 Golden-Belege des npm-Pakets
/// geprueft (Eingabe `receipts/*.json`, Erwartung `expected/*.lines.json`).
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

Future<String> _gedruckt(KasseneckReceipt receipt, {KeckPaperSize papier = KeckPaperSize.mm80}) async {
  final paper = await KeckPrinterService.getPaperFromReceipt(receipt, papier);
  return latin1.decode(paper.bytes.expand((b) => b).toList(), allowInvalid: true);
}

void main() {
  group('Aufdruck-Regeln gegen die Golden-Belege', () {
    final dateien = Directory('${_wurzel.path}/receipts').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    // 48 bis 11.8, dazu 23 Nacherfassungen (manual-receipt-*) und zero-outage-end-period (11.9.0),
    // add-ons (11.18.0), deposit und deposit-return (npm 1.32.0), dazu acht Zahlungsbelege auf Rechnung
    // (invoice-payment-*, npm 1.38.0).
    test('alle 89 Eingaben da', () => expect(dateien, hasLength(89)));
    for (final datei in dateien) {
      final name = datei.uri.pathSegments.last.replaceAll('.json', '');
      test(name, () {
        final ein = _json(datei.path);
        final optionen = ein['options'] as Map<String, dynamic>;
        final firma = ein['company'] as Map;
        final beleg = KasseneckReceipt.fromMetadata(ein['receipt'], {'company': firma['companyName'], 'is_small_business': firma['isSmallBusiness'] == true})
          ..testCashregister = optionen['testCashregister'] == true
          ..testSignature = optionen['testSignature'] == true;
        final erwartet = ReceiptLayout.fromJson(_json('${_wurzel.path}/expected/$name.lines.json'))!;
        final zeilen = [for (final z in erwartet.lines) z.toJson()];

        final warn = [for (final b in warnrahmen(beleg)) b.toJson()];
        final warnErwartet = zeilen.where((z) => z['kind'] == 'banner' && z['tone'] == 'warning').toList();
        // Oben und unten derselbe Rahmen.
        expect([...warn, ...warn], warnErwartet);
        expect(zeilen.take(warn.length).toList(), warn, reason: 'Warnrahmen ueber dem Kopf');

        // Belegart und Nacherfassung: nie beide an einem Beleg (manualReceipt nur am Verkaufsbeleg).
        final art = [for (final z in [...belegartBlock(beleg), ...nacherfassungBlock(beleg)]) z.toJson()];
        final start = zeilen.indexWhere((z) => z['kind'] == 'banner' && z['tone'] == 'receipt_type');
        if (start < 0) {
          expect(art, isEmpty);
        } else {
          expect(art, isNotEmpty, reason: 'Belegart fehlt im Rueckfall');
          expect(art, zeilen.sublist(start, start + art.length));
          final danach = start + art.length;
          expect(danach < zeilen.length && zeilen[danach]['kind'] == 'text' && zeilen[danach]['align'] == 'center', isFalse,
              reason: 'Block vollstaendig: keine weitere zentrierte Zeile direkt danach');
        }

        // „Sicherheitseinrichtung ausgefallen“: genau dann eine zentrierte Zeile, wenn die Signatur ausgefallen ist.
        final ausfall = [for (final z in signaturausfallBlock(beleg)) z.toJson()];
        final ausfallErwartet = zeilen.where((z) => z['kind'] == 'text' && z['text'] == 'Sicherheitseinrichtung ausgefallen').toList();
        expect(ausfall, ausfallErwartet);
        expect(ausfall.isNotEmpty, beleg.isSigFailed);
      });
    }
  });

  group('Zahlung auf Rechnung (npm 1.38.0)', () {
    KasseneckReceipt laden(String name) {
      final ein = _json('${_wurzel.path}/receipts/$name.json');
      final firma = ein['company'] as Map;
      return KasseneckReceipt.fromMetadata(ein['receipt'], {'company': firma['companyName'], 'is_small_business': firma['isSmallBusiness'] == true});
    }

    test('Position und Bezug werden gelesen', () {
      final beleg = laden('invoice-payment-normal');
      expect(beleg.items.single.isInvoicePayment, isTrue);
      expect(beleg.items.single.toJson()['kind'], 'invoice_payment');
      expect(beleg.invoicePayments, hasLength(1));
      expect(beleg.invoicePayments!.single.invoiceNumber, '2026-0042');
      expect(beleg.invoicePayments!.single.amountCents, 156960);
      expect(beleg.invoicePayments!.single.taxNote, 'incl_vat');
      // Speichern und wieder lesen (Zwischenspeicher): Position und Bezug bleiben.
      final zurueck = KasseneckReceipt.fromJson(jsonDecode(jsonEncode(beleg.toJson())) as Map<String, dynamic>);
      expect(zurueck.items.single.isInvoicePayment, isTrue);
      expect(zurueck.invoicePayments!.single.toJson(), beleg.invoicePayments!.single.toJson());
      // Gewoehnliche Belege tragen den Bezug nicht.
      expect(laden('manual-receipt-range-network-outage-count').invoicePayments, isNull);
    });

    test('taxNote gilt nur mit einem der drei Werte', () {
      final ein = _json('${_wurzel.path}/receipts/invoice-payment-normal.json');
      final roh = ein['receipt'] as Map<String, dynamic>;
      KasseneckReceipt mit(Object? wert) {
        final bezug = Map<String, dynamic>.from((roh['invoicePayments'] as List).single as Map)..['taxNote'] = wert;
        return KasseneckReceipt.fromMetadata({...roh, 'invoicePayments': [bezug, 'kaputt', {'invoiceId': 'x'}]}, {'company': 'Testbetrieb'});
      }

      expect(mit('incl_vat').invoicePayments, hasLength(1));
      expect(mit('zero_percent').invoicePayments!.single.taxNote, 'zero_percent');
      expect(mit('see_invoice').invoicePayments!.single.taxNote, 'see_invoice');
      for (final v in <Object?>['ja', true, 'inkl_ust', '', 7, null]) {
        expect(mit(v).invoicePayments!.single.taxNote, isNull, reason: '$v');
      }
    });

    test('Rueckfall: Steuerhinweis je Wert, „0 %“ nur bei zero_percent', () async {
      KasseneckReceipt mit(Object? wert) {
        final ein = _json('${_wurzel.path}/receipts/invoice-payment-normal.json');
        final roh = ein['receipt'] as Map<String, dynamic>;
        final bezug = Map<String, dynamic>.from((roh['invoicePayments'] as List).single as Map);
        wert == '__fehlt__' ? bezug.remove('taxNote') : bezug['taxNote'] = wert;
        return KasseneckReceipt.fromMetadata({...roh, 'invoicePayments': [bezug]}, {'company': 'Testbetrieb'});
      }

      final inkl = await _gedruckt(mit('incl_vat'));
      expect(inkl, contains('inkl. USt'));
      expect(inkl, isNot(contains('0 % USt')));
      expect(inkl, isNot(contains('siehe Rechnung')));
      final null0 = await _gedruckt(mit('zero_percent'));
      expect(null0, contains('0 % USt'));
      expect(null0, isNot(contains('inkl. USt')));
      expect(null0, isNot(contains('MwSt')));
      final siehe = await _gedruckt(mit('see_invoice'));
      expect(siehe, contains('Steuerangaben siehe Rechnung'));
      expect(siehe, isNot(contains('0 %')));
      expect(siehe, isNot(contains('inkl. USt')));
      for (final v in <Object?>['__fehlt__', null, 'unbekannt']) {
        final t = await _gedruckt(mit(v));
        expect(t, contains('Zahlung auf Rechnung'), reason: '$v');
        expect(t, isNot(contains('inkl. USt')), reason: '$v');
        expect(t, isNot(contains('0 %')), reason: '$v');
        expect(t, isNot(contains('siehe Rechnung')), reason: '$v');
        expect(t, isNot(contains('MwSt')), reason: '$v');
      }
    });

    test('Rueckfall: Zahlung ohne Satzkennzeichen und ohne Steuertabelle', () async {
      final mit = await _gedruckt(laden('invoice-payment-normal'));
      expect(mit, contains('Zahlung auf Rechnung'));
      expect(mit, contains('1569,60'));
      expect(mit, contains('inkl. USt'));
      expect(mit, isNot(contains('MwSt')));
      expect(mit, isNot(contains('0%')));
      expect(mit, isNot(contains('1 x')));
      final ohne = await _gedruckt(laden('invoice-payment-without-vat'));
      expect(ohne, contains('Zahlung auf Rechnung'));
      expect(ohne, isNot(contains('inkl. USt')));
      expect(ohne, isNot(contains('MwSt')));
    });

    test('Rueckfall: ausgefallene Signatur steht auf dem Zahlungsbeleg', () async {
      final text = await _gedruckt(laden('invoice-payment-outage'));
      expect(text, contains('Sicherheitseinrichtung ausgefallen'));
      expect(text, contains('inkl. USt'));
    });

    test('Rueckfall: ein gewoehnlicher Verkauf bleibt mit Satzkennzeichen und Steuertabelle', () async {
      final text = await _gedruckt(buildReceipt());
      expect(text, contains('MwSt'));
      expect(text, isNot(contains('inkl. USt')));
    });

    test('Nacherfassung eines Zahlungsbelegs ohne „USt: Duplikat …“', () {
      final zahlung = laden('invoice-payment-manual-receipt');
      expect([for (final z in nacherfassungBlock(zahlung)) z.toJson()].any((z) => '${z['text']}'.startsWith('USt:')), isFalse);
      final verkauf = laden('manual-receipt-range-network-outage-count');
      expect([for (final z in nacherfassungBlock(verkauf)) z.toJson()].any((z) => '${z['text']}'.startsWith('USt:')), isTrue);
    });

    test('Storno eines Zahlungsbelegs: Code, Satz der Kasse und Fehlerregel', () {
      expect(cancellationErrorCodes, contains('invoice_payment_not_cancellable'));
      expect(cancellationErrorMessage('invoice_payment_not_cancellable'), 'cancellation.invoice_payment_not_cancellable');
      expect(messageText('cancellation.invoice_payment_not_cancellable'),
          'Diese Zahlung gehört zu einer Rechnung. Storniere sie im Kundenbereich bei der Rechnung.');
      // Die uebrigen Storno-Codes bleiben, wo sie waren.
      expect(cancellationErrorMessage('cancellation_outcome_unknown'), 'cancellation.outcome_unknown');
      expect(cancellationErrorMessage('refund_as_voucher_reason'), 'cancellation.voucher_reason');
      expect(cancellationErrorMessage('not_found'), 'cancellation.failed');
      expect(cancellationErrorMessage(null), 'cancellation.failed');
    });
  });


  group('Rueckfall druckt den Aufdruck', () {
    test('Storno einer Testkasse ohne Server-Layout (storno.json): STORNOBELEG und Test-Warnung', () async {
      final fall = (_json('${_wurzel.path}/v3/antworten/storno.json')['cases'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((f) => f['name'] == 'cancel_full_card_refund' && f['channel'] == 'app');
      final daten = (fall['response'] as Map)['data'] as Map<String, dynamic>;
      expect(daten.containsKey('layout'), isFalse);
      final beleg = KasseneckReceipt.fromMetadata(daten['receipt'], {'company': 'Testbetrieb'});
      final text = await _gedruckt(beleg);
      expect(text, contains('STORNOBELEG'));
      expect(text, contains('Stornobuchung zu Beleg'));
      // Die Antwort traegt kein Kennzeichen, der QR aber die Test-Signatur.
      expect(text, contains('TESTSIGNATUR - kein gültiger Beleg'));
    });

    test('Storno mit Testkassen-Kennzeichen ohne Layout: TESTKASSE oben und unten, Grund und Bezug', () async {
      final beleg = buildReceipt(receiptType: ReceiptType.cancellation)
        ..testCashregister = true
        ..cancellationOf = const CancellationOf(receiptId: 'TEST-ID-0', timeStamp: '2026-06-11T09:02:17')
        ..cancellationReason = 'input_error';
      expect(beleg.layout, isNull);
      final text = await _gedruckt(beleg, papier: KeckPaperSize.mm58);
      expect('TESTKASSE - kein gültiger Beleg'.allMatches(text), hasLength(2));
      expect(text, contains('STORNOBELEG'));
      expect(text, contains('Stornobuchung zu Beleg TEST-ID-0'));
      expect(text, contains('vom 11.06.2026, 09:02 Uhr'));
      expect(text, contains('Grund: Fehleingabe'));
      expect(text, isNot(contains('TESTSIGNATUR')));
    });

    test('Testkasse mit unvollstaendigem Layout: das Server-Layout gewinnt, TESTKASSE steht drauf', () async {
      final beleg = buildReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentData: const {'paymentMethodType': 'card', 'cardBrand': 'Visa', 'cardLastDigits': '4242'},
        cardPaymentId: 'pi_1',
      )
        ..testCashregister = true
        ..layout = ReceiptLayout.fromJson(_json('${_wurzel.path}/expected/test-cashregister-sale.lines.json'));
      expect(beleg.isLayoutComplete, isFalse);
      final text = await _gedruckt(beleg);
      expect(text, contains('TESTKASSE'));
      expect(text, contains('Bäckerei Muster'));
    });

    test('gewoehnlicher Verkauf ohne Layout: kein Aufdruck', () async {
      final text = await _gedruckt(buildReceipt());
      for (final wort in ['TESTKASSE', 'TESTSIGNATUR', 'STORNOBELEG', 'NULLBELEG', 'TRAININGSBELEG']) {
        expect(text, isNot(contains(wort)));
      }
    });
  });
}
