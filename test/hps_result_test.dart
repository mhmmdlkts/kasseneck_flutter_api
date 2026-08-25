import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';

void main() {
  group('HpsResult', () {
    test('approved: bezahlt, keine Wiederholung', () {
      const r = HpsResult(outcome: HpsOutcome.approved, transactionId: 'TX-1');
      expect(r.isApproved, isTrue);
      expect(r.mayRetrySafely, isFalse);
      expect(r.isUnresolved, isFalse);
    });

    test('declined: nichts belastet, Wiederholung gefahrlos', () {
      const r = HpsResult(outcome: HpsOutcome.declined, transactionId: 'TX-2');
      expect(r.isApproved, isFalse);
      expect(r.mayRetrySafely, isTrue);
    });

    test('unresolved: Wiederholung ist NICHT gefahrlos', () {
      const r = HpsResult(outcome: HpsOutcome.unresolved, transactionId: 'TX-3');
      expect(r.isApproved, isFalse);
      expect(r.mayRetrySafely, isFalse);
      expect(r.isUnresolved, isTrue);
    });

    test('die Kennung ist in jedem Ausgang gesetzt', () {
      for (final outcome in HpsOutcome.values) {
        final r = HpsResult(outcome: outcome, transactionId: 'TX-4');
        expect(r.transactionId, isNotEmpty);
      }
    });
  });
}
