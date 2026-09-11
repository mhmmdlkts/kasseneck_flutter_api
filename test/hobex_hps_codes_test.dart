import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Die Antwortcodeliste von hobex, wie sie am 11.09.2026 kam -- Code, Titel
/// und die Einordnung, die wir daraus gezogen haben. Steht hier bewusst noch
/// einmal wortwoertlich statt aus [HpsCodes.all] abgeleitet: wer die Tabelle
/// aendert, soll an genau dieser Liste vorbei muessen und sehen, welcher
/// dokumentierte Code dadurch anders wirkt.
const _hobexListe = <(String, String, HpsCodeEffect, HpsCodeReason)>[
  ('0', 'Authorized', HpsCodeEffect.conclusive, HpsCodeReason.approved),
  ('100001', 'Bad Request', HpsCodeEffect.conclusive,
      HpsCodeReason.requestRejected),
  ('100002', 'Aborted', HpsCodeEffect.conclusive, HpsCodeReason.aborted),
  ('100003', 'Card not present', HpsCodeEffect.conclusive,
      HpsCodeReason.noCard),
  ('100004', 'Card read failed', HpsCodeEffect.conclusive,
      HpsCodeReason.cardReadFailed),
  ('100005', 'App select failed', HpsCodeEffect.conclusive,
      HpsCodeReason.cardReadFailed),
  ('100006', 'Communication with TecsXml failed', HpsCodeEffect.hostUncertain,
      HpsCodeReason.hostFault),
  ('100007', 'Processing of TecsXml step failed', HpsCodeEffect.hostUncertain,
      HpsCodeReason.hostFault),
  ('100008', 'Invalid TID', HpsCodeEffect.conclusive,
      HpsCodeReason.terminalSetup),
  ('100009', 'Invalid Tx Type', HpsCodeEffect.conclusive,
      HpsCodeReason.requestRejected),
  ('100010', 'Unable to abort transaction', HpsCodeEffect.conclusive,
      HpsCodeReason.notAbortable),
  ('100011', 'Not Found', HpsCodeEffect.noStatement,
      HpsCodeReason.noStatement),
  ('100012', 'Max retries exceeded', HpsCodeEffect.conclusive,
      HpsCodeReason.cardReadFailed),
  ('100013', 'Diagnosis failed', HpsCodeEffect.conclusive,
      HpsCodeReason.terminalFault),
  ('100014', "Card information wasn't entered", HpsCodeEffect.conclusive,
      HpsCodeReason.noCard),
  ('100015', 'Card declined', HpsCodeEffect.conclusive,
      HpsCodeReason.cardDeclined),
  ('100017', 'Card Not Supported', HpsCodeEffect.conclusive,
      HpsCodeReason.cardDeclined),
  ('100018', 'Scep enrollment failed', HpsCodeEffect.conclusive,
      HpsCodeReason.terminalSetup),
  ('100019', 'Amount is not in a valid range', HpsCodeEffect.conclusive,
      HpsCodeReason.amountInvalid),
  ('100020', 'Refund password is invalid', HpsCodeEffect.conclusive,
      HpsCodeReason.refundPassword),
  ('100021', 'Failed to enter the password', HpsCodeEffect.conclusive,
      HpsCodeReason.refundPassword),
  ('100022', 'Terminal is blocked', HpsCodeEffect.conclusive,
      HpsCodeReason.terminalBlocked),
  ('100023', 'Invalid message type', HpsCodeEffect.hostUncertain,
      HpsCodeReason.hostFault),
  ('100024', 'Transaction completion has failed', HpsCodeEffect.hostUncertain,
      HpsCodeReason.hostFault),
  ('100025', 'Refund transactions are disabled', HpsCodeEffect.conclusive,
      HpsCodeReason.refundDisabled),
  ('100026', 'Transaction was declined.', HpsCodeEffect.hostUncertain,
      HpsCodeReason.hostFault),
  ('100027', 'Unsupported UserData in TecsXml Response',
      HpsCodeEffect.hostUncertain, HpsCodeReason.hostFault),
  ('100028', 'Tip selection process has failed.', HpsCodeEffect.conclusive,
      HpsCodeReason.tipNotSelected),
  ('100029', 'Communication with TecsXml timeout', HpsCodeEffect.conclusive,
      HpsCodeReason.hostTimeoutReversed),
  ('100998', 'Terminal is busy', HpsCodeEffect.conclusive,
      HpsCodeReason.terminalBusy),
  ('100999', 'Internal Error', HpsCodeEffect.hostUncertain,
      HpsCodeReason.internalError),
];

void main() {
  group('Antwortcodeliste von hobex (11.09.2026)', () {
    test('jeder Code der Liste steht in der Tabelle, so eingeordnet', () {
      for (final (code, titel, wirkung, grund) in _hobexListe) {
        final info = HpsCodes.lookup(code);
        expect(info, isNotNull, reason: '$code fehlt');
        expect(info!.title, titel, reason: code);
        expect(info.effect, wirkung, reason: code);
        expect(info.reason, grund, reason: code);
        expect(
          info.source,
          anyOf(HpsCodeSource.documented, HpsCodeSource.measuredAndDocumented),
          reason: '$code steht in der Liste von hobex',
        );
      }
    });

    test('kein Code doppelt', () {
      final codes = HpsCodes.all.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('gemessene Codes behalten ihre Wirkung', () {
      // Die Messungen vom 26.08.-02.09.2026 werden durch die Liste nicht
      // ueberstimmt: sie stehen weiter so da, wie sie gemessen wurden.
      expect(HpsCodes.lookup('9027')!.effect, HpsCodeEffect.noStatement);
      expect(HpsCodes.lookup('9900')!.effect, HpsCodeEffect.noStatement);
      for (final code in ['9002', '9003', '9011', '55', '100108']) {
        expect(HpsCodes.lookup(code)!.conclusive, isTrue, reason: code);
        expect(HpsCodes.lookup(code)!.source, HpsCodeSource.measured,
            reason: code);
      }
    });

    test('jede Stoerung beim Host fuehrt auf einen ungewissen Grund', () {
      for (final c in HpsCodes.all) {
        expect(c.hostUncertain, c.reason.hostUncertain, reason: c.code);
      }
    });

    test('jeder Grund hat einen Satz fuer den Bediener', () {
      for (final r in HpsCodeReason.values) {
        expect(r.hint.trim(), isNotEmpty, reason: r.name);
        expect(r.hint.endsWith('.'), isTrue, reason: r.name);
      }
    });
  });

  group('TransactionResponse mit der Tabelle', () {
    TransactionResponse mit(String code) =>
        TransactionResponse.fromJson({'responseCode': code});

    test('die drei Betriebs-Codes vom 28.08.2026 sind jetzt Ablehnungen', () {
      // 100004, 100005, 100015 kamen im Betrieb (TID 3556988) und blieben bis
      // heute ungedeutet -- jede Zahlung damit lief 90 Sekunden in die Klaerung
      // oder endete offen. Laut hobex scheitern alle drei VOR dem Host.
      for (final code in ['100004', '100005', '100015']) {
        final r = mit(code);
        expect(r.isConclusive, isTrue, reason: code);
        expect(r.isApproved, isFalse, reason: code);
        expect(r.isUnknownCode, isFalse, reason: code);
      }
    });

    test('eine Stoerung beim Host ist KEINE Aussage', () {
      for (final code in [
        '100006',
        '100007',
        '100023',
        '100024',
        '100026',
        '100027',
        '100999',
      ]) {
        final r = mit(code);
        expect(r.isConclusive, isFalse, reason: code);
        expect(r.isHostUncertain, isTrue, reason: code);
        expect(r.isUnknownCode, isFalse, reason: code);
        expect(r.isNoStatement, isFalse, reason: code);
      }
    });

    test('100011 ist keine Aussage und traegt nicht die 9027-Regel', () {
      final r = mit(TransactionResponse.notFoundCode);
      expect(r.isConclusive, isFalse);
      expect(r.isNoStatement, isFalse,
          reason: 'die Zwei-9027-Regel ist nur fuer 9027 gemessen');
      expect(r.isUnknownCode, isFalse);
      expect(r.reason, HpsCodeReason.noStatement);
    });

    test('ein Code ausserhalb der Tabelle bleibt unbekannt', () {
      for (final code in ['05', '51', '100016', '100030', '100100']) {
        final r = mit(code);
        expect(r.isConclusive, isFalse, reason: code);
        expect(r.isUnknownCode, isTrue, reason: code);
        expect(r.reason, HpsCodeReason.unknown, reason: code);
      }
    });

    test('ohne Code kein Grund', () {
      expect(TransactionResponse.fromJson(const {}).reason, isNull);
    });

    test('toString nennt die Stoerung', () {
      expect(mit('100007').toString(), contains('HOST_UNCERTAIN(100007)'));
    });
  });
}
