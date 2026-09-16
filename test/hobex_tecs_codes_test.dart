import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Jeder Code der TECS-Liste, wie hobex sie am 16.09.2026 geschickt hat --
/// in der Schreibweise der Liste (vierstellig). Steht hier bewusst als
/// nackte Liste: faellt ein Code aus der Tabelle, faellt dieser Test.
const _tecsListe = <String>[
  '0000', '9002', '9003', '9011', '9027', '9900', '0055', '0001', '0002',
  '0003', '0004', '0005', '0006', '0007', '0008', '0009', '0010', '0011',
  '0012', '0013', '0014', '0015', '0016', '0017', '0018', '0019', '0020',
  '0021', '0022', '0023', '0024', '0025', '0026', '0027', '0028', '0029',
  '0030', '0031', '0032', '0033', '0034', '0035', '0036', '0037', '0038',
  '0040', '0041', '0042', '0043', '0044', '0051', '0052', '0053', '0054',
  '0056', '0057', '0058', '0059', '0060', '0061', '0062', '0063', '0064',
  '0065', '0066', '0067', '0068', '0075', '0076', '0077', '0080', '0081',
  '0082', '0083', '0086', '0087', '0088', '0089', '0090', '0091', '0092',
  '0093', '0094', '0095', '0096', '0097', '0098', '0099', '0117', '3018',
  '3019', '3021', '3030', '3031', '3032', '3033', '3034', '3035', '3036',
  '3037', '3038', '3039', '3050', '3051', '3052', '3053', '3054', '3055',
  '3056', '3057', '3058', '3059', '3060', '3061', '3062', '3063', '3064',
  '3065', '3066', '3531', '3532', '3533', '3534', '3537', '3539', '3547',
  '3549', '3559', '3569', '3579', '3589', '3590', '3596', '3597', '3598',
  '3693', '3694', '3695', '3696', '3697', '3699', '3993', '3994', '3995',
  '3996', '4000', '4001', '4002', '4003', '4004', '4005', '4006', '4007',
  '4011', '4012', '4013', '4020', '4021', '4022', '4023', '4024', '4025',
  '4026', '4027', '4028', '4029', '4030', '4060', '4061', '4062', '4063',
  '4064', '4065', '5127', '5158', '5256', '5271', '5272', '5273', '5274',
  '5275', '5276', '5277', '5278', '6000', '6001', '6002', '6003', '7777',
  '7001', '7002', '7005', '7006', '7007', '7008', '7009', '7010', '7011',
  '7012', '7013', '7014', '7015', '7016', '7017', '7018', '7019', '7020',
  '7021', '7022', '7023', '7024', '7100', '7101', '7102', '8001', '8002',
  '8003', '8004', '8005', '8006', '8007', '8008', '8009', '8010', '8011',
  '8012', '8013', '8014', '8015', '8016', '8017', '8018', '8019', '8020',
  '81xx', '8201', '8202', '8203', '8500', '8501', '8502', '8503', '8504',
  '8505', '8506', '8507', '8508', '8509', '8510', '8511', '8512', '8513',
  '8514', '8515', '8516', '8517', '8518', '8519', '8520', '8521', '8522',
  '8523', '8530', '8531', '8532', '8533', '8534', '8537', '8538', '8539',
  '8540', '8547', '8548', '8549', '8550', '8559', '8560', '8561', '8562',
  '8563', '8564', '8565', '8566', '8567', '8568', '8569', '8570', '8571',
  '8809', '8999', '9001', '9004', '9005', '9006', '9007', '9008', '9009',
  '9010', '9012', '9013', '9014', '9015', '9016', '9017', '9018', '9019',
  '9020', '9021', '9022', '9023', '9024', '9025', '9026', '9028', '9029',
  '9031', '9032', '9033', '9034', '9096', '9222', '9901', '9902', '9905',
  '9906', '9907', '9908', '9909', '30091', '30093', '30094', '30095',
  '30096', '30099'
];

TransactionResponse _mit(String code) =>
    TransactionResponse.fromJson({'responseCode': code});

void main() {
  group('TECS-Liste (16.09.2026)', () {
    test('jeder Code der Liste ist benannt und traegt seinen TECS-Titel', () {
      for (final code in _tecsListe) {
        final info = HpsCodes.lookup(code);
        expect(info, isNotNull, reason: '$code fehlt');
        expect(info!.tecsTitle, isNotNull, reason: code);
        expect(info.source, isNot(HpsCodeSource.measured), reason: code);
      }
    });

    test('die Familie 81xx deckt jedes Feld ab', () {
      for (final code in ['8100', '8105', '8199']) {
        expect(HpsCodes.lookup(code)?.code, '81xx', reason: code);
        expect(_mit(code).isConclusive, isTrue, reason: code);
        expect(_mit(code).isConclusiveAsStatus, isFalse, reason: code);
      }
      expect(HpsCodes.lookup('81')!.title, 'Message flow error');
      expect(HpsCodes.lookup('810'), isNull);
      expect(HpsCodes.lookup('81000'), isNull);
    });

    test('kein Code doppelt, auch nicht ueber die Schreibweise', () {
      final codes = HpsCodes.all.map((c) => HpsCodes.normalize(c.code));
      expect(codes.toSet().length, HpsCodes.all.length);
    });

    test('Schreibweise: vierstellig und ohne Nullen sind derselbe Code', () {
      expect(HpsCodes.normalize('0055'), '55');
      expect(HpsCodes.normalize('0000'), '0');
      expect(HpsCodes.normalize('0'), '0');
      expect(HpsCodes.normalize(' 9908 '), '9908');
      expect(HpsCodes.normalize('81xx'), '81xx');
      expect(_mit('0000').isApproved, isTrue,
          reason: 'sonst waere eine Genehmigung eine Ablehnung');
      expect(_mit('0000').responseCode, '0');
      expect(_mit('0055').reason, HpsCodeReason.wrongPin);
      expect(_mit('0117').reason, HpsCodeReason.wrongPin);
    });

    test('eine Genehmigung, die nicht 0 ist, wird nie zur Ablehnung', () {
      for (final code in ['0008', '0010', '0011', '0016', '0032']) {
        final r = _mit(code);
        expect(r.isConclusive, isFalse, reason: code);
        expect(r.isApproved, isFalse, reason: code);
        expect(r.isHostUncertain, isTrue, reason: code);
        expect(r.reason, HpsCodeReason.approvedWithCondition, reason: code);
        expect(r.needsReversal, isFalse, reason: code);
      }
    });

    test('9908 ist ein Timeout wie jeder andere: offen, mit Storno', () {
      final r = _mit('9908');
      expect(r.isConclusive, isFalse);
      expect(r.isHostUncertain, isTrue);
      expect(r.needsReversal, isTrue);
      expect(r.reason, HpsCodeReason.hostTimeout);
      for (final code in ['0068', '9905', '9906', '9907', '9909', '3051']) {
        expect(_mit(code).needsReversal, isTrue, reason: code);
      }
    });

    test('die HPS-Codes ohne auto-reversal bekommen ebenfalls ein Storno', () {
      for (final code in [
        '100006',
        '100007',
        '100023',
        '100024',
        '100026',
        '100027',
      ]) {
        expect(_mit(code).needsReversal, isTrue, reason: code);
      }
      expect(_mit('100029').needsReversal, isFalse,
          reason: 'storniert laut hobex selbst');
      expect(_mit('100999').needsReversal, isFalse);
    });

    test('Storno nur bei ungewissem Ausgang und ausgebliebener Antwort', () {
      for (final c in HpsCodes.all) {
        final ausgeblieben = c.reason == HpsCodeReason.hostFault ||
            c.reason == HpsCodeReason.hostTimeout;
        expect(c.sendReversal, ausgeblieben, reason: c.code);
        if (c.sendReversal) {
          expect(c.effect, HpsCodeEffect.hostUncertain, reason: c.code);
        }
      }
    });

    test('Host-Ablehnungen sind schluessig und nennen den Grund', () {
      const erwartet = <String, HpsCodeReason>{
        '0005': HpsCodeReason.issuerDeclined,
        '0051': HpsCodeReason.insufficientFunds,
        '0054': HpsCodeReason.cardExpired,
        '0043': HpsCodeReason.cardBlocked,
        '0075': HpsCodeReason.pinTriesExceeded,
        '0077': HpsCodeReason.pinRequired,
        '0091': HpsCodeReason.hostUnavailable,
        '0096': HpsCodeReason.hostUnavailable,
        '0003': HpsCodeReason.acquirerSetup,
        '0030': HpsCodeReason.hostRejected,
        '9018': HpsCodeReason.cardBlocked,
        '9032': HpsCodeReason.reversedByHost,
        '8009': HpsCodeReason.hostTimeoutReversed,
      };
      erwartet.forEach((code, grund) {
        final r = _mit(code);
        expect(r.isConclusive, isTrue, reason: code);
        expect(r.isApproved, isFalse, reason: code);
        expect(r.isConclusiveAsStatus, isTrue, reason: code);
        expect(r.reason, grund, reason: code);
      });
    });

    test('Codes anderer TECS-Produkte sagen nichts ueber die Zahlung', () {
      for (final code in [
        '3537',
        '3697',
        '4012',
        '7001',
        '7011',
        '7777',
        '8515',
        '8570',
        '9024',
        '30096',
      ]) {
        final r = _mit(code);
        expect(r.isConclusive, isFalse, reason: code);
        expect(r.isHostUncertain, isFalse, reason: code);
        expect(r.isUnknownCode, isFalse, reason: code);
        expect(r.codeInfo!.effect, HpsCodeEffect.noStatement, reason: code);
      }
    });

    test('Aufhebung: abgelehnt heisst nur dort "bleibt belastet", wo es stimmt',
        () {
      expect(_mit('9023').reason, HpsCodeReason.cancelDenied);
      expect(_mit('9023').isConclusive, isTrue);
      // 9033: die Originalzahlung war abgelehnt. Als "Aufhebung hat nicht
      // gegriffen" gelesen, laed das zu einer Gutschrift fuer Geld ein, das
      // nie geflossen ist.
      expect(_mit('9033').isConclusive, isFalse);
      expect(_mit('9033').reason, HpsCodeReason.originalDeclined);
    });

    test('gemessene Codes tragen den TECS-Titel, behalten aber ihren', () {
      final pin = HpsCodes.lookup('55')!;
      expect(pin.title, 'PIN falsch');
      expect(pin.tecsTitle, 'Incorrect PIN');
      expect(pin.source, HpsCodeSource.measuredAndDocumented);
      expect(HpsCodes.lookup('0')!.tecsTitle, 'Approved Transaction / OK');
      expect(HpsCodes.lookup('100003')!.tecsTitle, isNull);
    });
  });
}
