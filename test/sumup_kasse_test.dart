import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/sumup_checkout_response.dart';
import 'package:kasseneck_api/pos.dart';

/// SumUp in der Kassen-App (Spec 2026-11-14-sumup-kasse): Anbieter `sumup`,
/// Händlernummer als optionale Betriebs-Einstellung, Kartenterminal-Block mit
/// dem Affiliate Key und eine SumUp-Antwort, die jede Form verträgt.
void main() {
  group('Kartenanbieter und Händlernummer', () {
    test('sumup ist ein Kartenanbieter', () {
      expect(PosCardProvider.sumup.value, 'sumup');
      expect(PosBusinessSettings.fromJson({'cardProvider': 'sumup'}).cardProvider, PosCardProvider.sumup);
    });

    test('sumupMerchantCode: optional, nur eine gültige Nummer kommt durch', () {
      expect(const PosBusinessSettings().sumupMerchantCode, isNull);
      expect(const PosBusinessSettings().toJson().containsKey('sumupMerchantCode'), isFalse);
      expect(PosBusinessSettings.fromJson({'sumupMerchantCode': 'MCAB12CD'}).sumupMerchantCode, 'MCAB12CD');
      for (final falsch in ['x', 'MC-1234', 42, null]) {
        expect(PosBusinessSettings.fromJson({'sumupMerchantCode': falsch}).sumupMerchantCode, isNull, reason: '$falsch');
      }
      expect(PosBusinessSettings.fromJson({'sumupMerchantCode': 'MCAB12CD'}).toJson()['sumupMerchantCode'], 'MCAB12CD');
      expect(posBusinessOptionalIds, ['sumupMerchantCode']);
    });

    test('merge: Nummer setzen, null löst, eine ungültige wird abgewiesen', () {
      final gebunden = const PosBusinessSettings().merge({'sumupMerchantCode': 'MCAB12CD'});
      expect(gebunden.sumupMerchantCode, 'MCAB12CD');
      expect(gebunden.merge({'sumupMerchantCode': null}).sumupMerchantCode, isNull);
      expect(() => const PosBusinessSettings().merge({'sumupMerchantCode': 'MC-1'}), throwsArgumentError);
    });
  });

  group('Kartenterminal-Block', () {
    test('affiliateKey wird gelesen, ohne Block fehlt er', () {
      final mit = PosSettings.fromJson({
        'business': {'cardProvider': 'sumup'},
        'cardTerminal': {
          'sumup': {'affiliateKey': 'sup_afk_ABC123'},
        },
      });
      expect(mit.cardTerminal?.sumup?.affiliateKey, 'sup_afk_ABC123');
      expect(mit.toJson()['cardTerminal'], {
        'sumup': {'affiliateKey': 'sup_afk_ABC123'},
      });
      expect(PosSettings.fromJson({'business': {}}).cardTerminal, isNull);
      expect(PosSettings.fromJson({'business': {}}).toJson().containsKey('cardTerminal'), isFalse);
    });

    test('ein unbrauchbarer Block zählt als fehlend', () {
      for (final kaputt in <Object?>[
        null,
        'x',
        {'sumup': null},
        {
          'sumup': {'affiliateKey': 42},
        },
        {
          'sumup': {'affiliateKey': ''},
        },
      ]) {
        expect(PosSettings.fromJson({'cardTerminal': kaputt}).cardTerminal, isNull, reason: '$kaputt');
      }
    });
  });

  group('SumupCheckoutResponse', () {
    test('Betrag als Zahl oder Zeichenkette, leer ist null', () {
      expect(SumupCheckoutResponse.fromMap({'success': true, 'amount': 25}).amount, 25.0);
      expect(SumupCheckoutResponse.fromMap({'success': true, 'amount': 14.09}).amount, 14.09);
      expect(SumupCheckoutResponse.fromMap({'success': true, 'amount': '14.09'}).amount, 14.09);
      expect(SumupCheckoutResponse.fromMap({'success': true, 'amount': ''}).amount, isNull);
      expect(SumupCheckoutResponse.fromMap({'success': true, 'transactionCode': ''}).transactionCode, isNull);
    });

    test('fehlt success, gilt kein Erfolg (kein Wurf)', () {
      expect(SumupCheckoutResponse.fromMap({}).success, isFalse);
    });

    test('Kennung und Händlernummer: gelesen und nur geschrieben, wenn gesetzt', () {
      final r = SumupCheckoutResponse.fromMap({'success': true, 'foreignTransactionId': 'kk-1', 'merchantCode': 'MCAB12CD'});
      expect(r.foreignTransactionId, 'kk-1');
      expect(r.merchantCode, 'MCAB12CD');
      expect(r.toJson()['foreignTransactionId'], 'kk-1');
      final ohne = SumupCheckoutResponse(success: true).toJson();
      expect(ohne.containsKey('foreignTransactionId'), isFalse);
      expect(ohne.containsKey('merchantCode'), isFalse);
    });
  });
}
