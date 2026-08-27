import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';

/// Tests fuer die hobex-HPS-Schicht: CVM-Parsing, TransactionResponse,
/// und den Adapter HobexReceipt.fromHps -> toCardPaymentData (Render-Keys).
void main() {
  group('Cvm.fromValue', () {
    test('numerisch (Payment-Response)', () {
      expect(Cvm.fromValue(0), Cvm.unknown);
      expect(Cvm.fromValue(1), Cvm.signature);
      expect(Cvm.fromValue(2), Cvm.pin);
      expect(Cvm.fromValue(3), Cvm.noCvm);
    });
    test('string (Status-v2)', () {
      expect(Cvm.fromValue('SIGNATURE'), Cvm.signature);
      expect(Cvm.fromValue('PIN'), Cvm.pin);
    });
    test('null/unbekannt -> null', () {
      expect(Cvm.fromValue(null), isNull);
      expect(Cvm.fromValue('XYZ'), isNull);
    });
  });

  group('TransactionResponse.fromJson', () {
    test('approved (responseCode 0)', () {
      final r = TransactionResponse.fromJson({
        'transactionId': 'TX1',
        'responseCode': '0',
        'amount': 12.5,
        'cardNumber': '************1234',
        'cvm': 1,
        'brand': 'Visa',
      });
      expect(r.isApproved, isTrue);
      expect(r.isInProgress, isFalse);
      expect(r.amount, 12.5);
      expect(r.cardNumber, '************1234'); // maskierte PAN bleibt erhalten
      expect(r.cvm, Cvm.signature);
    });
    test('ein nie gemessener Code ist KEINE Aussage -- auch keine Ablehnung',
        () {
      // '05' SIEHT aus wie ein Ablehnungscode, ist aber nie gemessen worden.
      // Seit dem Umbau auf eine echte Positivliste (siehe isConclusive) reicht
      // "sieht aus wie" nicht mehr -- nur ein benannter, gemessener Code
      // entscheidet.
      final r = TransactionResponse.fromJson({'responseCode': '05'});
      expect(r.isApproved, isFalse);
      expect(r.isInProgress, isFalse);
      expect(r.isConclusive, isFalse);
      expect(r.isUnknownCode, isTrue);
      expect(r.isNoStatement, isFalse);
      expect(r.isTechnicalError, isFalse);
    });
    test('in progress (kein responseCode)', () {
      final r = TransactionResponse.fromJson({'transactionId': 'TX2'});
      expect(r.isInProgress, isTrue);
      expect(r.isConclusive, isFalse);
    });
    test('9027 ist KEIN Ergebnis -- weder genehmigt noch abgelehnt', () {
      // Am 26.08.2026 gemessen: die Statusabfrage antwortet mit 9027
      // gleichermassen auf einen laufenden, einen abgebrochenen und einen nie
      // gesehenen Vorgang. Ueber `!= "0"` als Ablehnung gelesen, ergaebe das
      // fuer einen LAUFENDEN Vorgang "gefahrlos wiederholbar".
      final r = TransactionResponse.fromJson({
        'responseCode': '9027',
        'responseText': 'Original Tx not found',
      });
      expect(r.responseCode, TransactionResponse.noStatementCode);
      expect(r.isNoStatement, isTrue);
      expect(r.isApproved, isFalse);
      expect(r.isConclusive, isFalse,
          reason: 'nur eine schluessige Antwort darf einen Ausgang '
              'festschreiben');
      expect(r.toString(), contains('NO_STATEMENT'));
    });
    test('9011 ist eine Aussage: der Vorgang wurde aufgehoben', () {
      final r = TransactionResponse.fromJson({
        'responseCode': '9011',
        'responseText': 'Transaction Canceled',
      });
      expect(r.isCanceled, isTrue);
      expect(r.isApproved, isFalse);
      expect(r.isConclusive, isTrue);
    });
    test('100010 ist der gemessene Fehlschlag eines Abbruchs', () {
      final r = TransactionResponse.fromJson({'responseCode': '100010'});
      expect(r.isNotAbortable, isTrue);
      expect(r.isApproved, isFalse);
      expect(r.isConclusive, isTrue);
      expect(
        TransactionResponse.fromJson({'responseCode': '77777'}).isNotAbortable,
        isFalse,
      );
    });
    test('ein echter Ablehnungscode bleibt schluessig', () {
      expect(
        TransactionResponse.fromJson({'responseCode': '100003'}).isConclusive,
        isTrue,
      );
      expect(
        TransactionResponse.fromJson({'responseCode': '100002'}).isConclusive,
        isTrue,
      );
    });
    test('9002 ist eine Aussage: der Vorgang wurde als ungueltig abgewiesen',
        () {
      // Am 27.08.2026 gemessen: eine Gutschrift auf eine unbekannte, REIN
      // NUMERISCHE Original-Kennung antwortet nach 1,2 s mit 9002 -- ohne
      // Kartenfluss, ohne Auszahlung. Anders als 9027 ("kein Eintrag") ist
      // das eine positive Aussage: der Vorgang wurde verworfen, nichts
      // geschah.
      final r = TransactionResponse.fromJson({
        'responseCode': '9002',
        'responseText': 'Invalid Transaction',
      });
      expect(r.responseCode, TransactionResponse.invalidTransactionCode);
      expect(r.isInvalid, isTrue);
      expect(r.isApproved, isFalse);
      expect(r.isConclusive, isTrue,
          reason: 'ein gemessener Ablehnungscode entscheidet den Ausgang');
      expect(r.isNoStatement, isFalse);
      expect(r.isTechnicalError, isFalse);
      expect(r.toString(), contains('DECLINED(9002)'));
    });
    test('9900 ist eine gemessene Wissensluecke, NIEMALS schluessig', () {
      // Am 27.08.2026 gemessen: die Statusabfrage antwortet mit 9900
      // "Technical Error Database" auf eine nicht rein numerische Kennung --
      // gleichermassen auf genehmigte, abgelehnte und nie existierende
      // Vorgaenge. Ueber die alte Fassung von isConclusive (jeder Code ausser
      // null/9027 ist schluessig) waere das declined geworden, obwohl unter
      // dem Vorgang Geld geflossen sein kann. DAS ist die Mutationsprobe:
      // wuerde isConclusive wieder "jeder Code ausser 9027" lauten, wird
      // dieser Test rot.
      final r = TransactionResponse.fromJson({
        'responseCode': '9900',
        'responseText': 'Technical Error Database',
      });
      expect(r.responseCode, TransactionResponse.technicalErrorCode);
      expect(r.isTechnicalError, isTrue);
      expect(r.isConclusive, isFalse,
          reason: 'ein technischer Fehler ist keine Aussage ueber den '
              'Vorgang');
      expect(r.isNoStatement, isFalse,
          reason: '9900 ist NICHT 9027 -- eigene, unterscheidbare '
              'Wissensluecke');
      expect(r.isUnknownCode, isFalse,
          reason: '9900 ist benannt, kein UNBEKANNTER Code');
      expect(r.toString(), contains('TECHNICAL_ERROR'));
    });
    test(
        'ein Code, dessen Bedeutung wir nie gemessen haben, bleibt eine '
        'Wissensluecke -- egal wie er aussieht', () {
      for (final code in ['9900', '77777', '05', '12345', 'ABC']) {
        final conclusive =
            TransactionResponse.fromJson({'responseCode': code}).isConclusive;
        expect(conclusive, isFalse,
            reason: '"$code" ist nicht in der Liste gemessener Codes -- '
                'isConclusive darf dafuer nicht wahr sein');
      }
    });
    test('amount als String wird geparst', () {
      final r = TransactionResponse.fromJson({'amount': '9.90'});
      expect(r.amount, 9.9);
    });
  });

  group('HobexReceipt.fromHps + toCardPaymentData', () {
    test('Felder gemappt, Provider hobexHps, Render-Keys vorhanden', () {
      final res = TransactionResponse.fromJson({
        'transactionId': 'TX1',
        'tid': '3600335',
        'receipt': '42',
        'transactionType': 'SELL',
        'brand': 'Visa',
        'cardNumber': '************1234',
        'cardExpiry': '2612',
        'cardIssuer': 'Bank',
        'approvalCode': 'ABC',
        'responseCode': '0',
        'amount': 12.5,
        'currency': 'EUR',
        'transactionDate': '2026-06-10T12:00:00.000',
        'cvm': 1,
      });
      final hr = HobexReceipt.fromHps(res);
      expect(hr.creditCardProvider, CreditCardProvider.hobexHps);
      expect(hr.transactionId, 'TX1');
      expect(hr.cardNumber, '************1234');

      final data = hr.toCardPaymentData();
      // Keys, die print_paper/_hobexHps + keck_receipt_widget/_hobexHpsPart lesen:
      for (final k in [
        'date',
        'tid',
        'no',
        'type',
        'cardBrand',
        'cardNumber',
        'responseCode',
        'cvm',
        'approvalCode',
        'cardExpiry'
      ]) {
        expect(data.containsKey(k), isTrue, reason: 'Render-Key fehlt: $k');
      }
      expect(data['no'], '42');
      expect(data['cardNumber'], '************1234');
      expect(data['cvm'], '1');
      expect(data['amount'], '12.50');
    });

    test('needSignature bei cvm == 1', () {
      final res = TransactionResponse.fromJson({'cvm': 1, 'responseCode': '0'});
      expect(HobexReceipt.fromHps(res).needSignature, isTrue);
    });
  });

  group('Diagnosis.fromJson', () {
    test('Status & Test-Umgebung erkannt', () {
      final d = Diagnosis.fromJson({
        'deviceStatus': 'IN_OPERATION',
        'responseCode': '0',
        'host': 'https://tecstest.hobex.at',
        'hps': '1.8.4',
        'tid': '3600335',
      });
      expect(d.isInOperation, isTrue);
      expect(d.isAuthorized, isTrue);
      expect(d.isTestEnvironment, isTrue);
    });
  });
}
