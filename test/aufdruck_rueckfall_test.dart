import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/registration_info.dart' show CancellationOf;
import 'package:kasseneck_api/services/printer_service.dart';
import 'package:kasseneck_api/src/receipt/aufdruck.dart';

import 'helpers/test_receipts.dart';

/// Der Rueckfall ohne Server-Layout (`setKeckReceipt`) druckt denselben
/// Aufdruck wie das Server-Layout: Warnrahmen TESTKASSE/TESTSIGNATUR und die
/// Belegart. Die Regeln werden gegen die 40 Golden-Belege des npm-Pakets
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
    test('alle 40 Eingaben da', () => expect(dateien, hasLength(40)));
    for (final datei in dateien) {
      final name = datei.uri.pathSegments.last.replaceAll('.json', '');
      test(name, () {
        final ein = _json(datei.path);
        final optionen = ein['options'] as Map<String, dynamic>;
        final beleg = KasseneckReceipt.fromMetadata(ein['receipt'], {'company': (ein['company'] as Map)['companyName']})
          ..testCashregister = optionen['testCashregister'] == true
          ..testSignature = optionen['testSignature'] == true;
        final erwartet = BelegLayout.fromJson(_json('${_wurzel.path}/expected/$name.lines.json'))!;
        final zeilen = [for (final z in erwartet.lines) z.toJson()];

        final warn = [for (final b in warnrahmen(beleg)) b.toJson()];
        final warnErwartet = zeilen.where((z) => z['kind'] == 'banner' && z['tone'] == 'warning').toList();
        // Oben und unten derselbe Rahmen.
        expect([...warn, ...warn], warnErwartet);
        expect(zeilen.take(warn.length).toList(), warn, reason: 'Warnrahmen ueber dem Kopf');

        final art = [for (final z in belegartBlock(beleg)) z.toJson()];
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
      });
    }
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
        ..layout = BelegLayout.fromJson(_json('${_wurzel.path}/expected/test-cashregister-sale.lines.json'));
      expect(beleg.layoutIstVollstaendig, isFalse);
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
