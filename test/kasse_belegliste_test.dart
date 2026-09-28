import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Die Belegliste: Zeitraum, Filter, Tagesgruppen — Zwilling von `belege.ts`
/// der Browser-Kasse.
///
/// Gerechnet wird in **Wiener Kalendertagen**, nicht in denen des Geräts. Ein
/// Tablet mit falsch gestellter Zeitzone darf den Kassenschluss nicht
/// verschieben.

/// 19.08.2026, 00:30 Wiener Wanduhrzeit (also 22:30 UTC am 18.8.).
final jetzt = DateTime.utc(2026, 8, 18, 22, 30);

ReceiptSummary beleg({
  String receiptId = 'KASSE1-ID-1',
  String belegart = 'standard',
  String zeitstempel = '2026-08-19T10:15:00',
  int summeCents = 500,
  KeckPaymentMethod zahlungsart = KeckPaymentMethod.cash,
  String? storniertBeleg,
  String bediener = 'Ali',
}) =>
    ReceiptSummary(
      receiptId: receiptId,
      receiptType: belegart,
      timeStamp: zeitstempel,
      totalCents: summeCents,
      paymentMethod: zahlungsart,
      signatureOk: true,
      items: const [],
      cancellationState: CancellationState.none,
      cancellationOfReceiptId: storniertBeleg,
      operator: ReceiptOperator(uid: 'u1', name: bediener),
    );

void main() {
  group('Zeitfenster', () {
    test('heute ist der Wiener Kalendertag — auch kurz nach Mitternacht', () {
      // Um 00:30 Wien ist es UTC noch der Vortag. Wer hier UTC nimmt, zeigt
      // dem Kassier um halb eins die Belege von gestern.
      expect(periodRange(ReceiptPeriod.today, jetzt), (from: '2026-08-19', to: '2026-08-19'));
    });

    test('gestern ist genau ein Tag', () {
      expect(periodRange(ReceiptPeriod.yesterday, jetzt), (from: '2026-08-18', to: '2026-08-18'));
    });

    test('sieben Tage schließen heute mit ein', () {
      expect(periodRange(ReceiptPeriod.last7Days, jetzt), (from: '2026-08-13', to: '2026-08-19'));
    });

    test('dreißig Tage ebenso', () {
      expect(periodRange(ReceiptPeriod.last30Days, jetzt), (from: '2026-07-21', to: '2026-08-19'));
    });
  });

  group('Belegart lesbar', () {
    test('Verkauf, Storno, Startbeleg', () {
      expect(receiptTypeLabel(beleg()), 'Verkauf');
      expect(receiptTypeLabel(beleg(belegart: 'cancellation')), 'Storno');
      expect(receiptTypeLabel(beleg(storniertBeleg: 'KASSE1-ID-1')), 'Storno');
      expect(receiptTypeLabel(beleg(belegart: 'start')), 'Startbeleg');
      expect(receiptTypeLabel(beleg(belegart: 'training')), 'Trainingsbeleg');
    });

    test('Nullbelege nennen ihren Anlass', () {
      ReceiptSummary null_(String anlass) => ReceiptSummary(
            receiptId: 'x',
            receiptType: 'zero',
            timeStamp: '2026-08-19T10:15:00',
            totalCents: 0,
            paymentMethod: KeckPaymentMethod.cash,
            signatureOk: true,
            items: const [],
            cancellationState: CancellationState.none,
            zeroKind: anlass,
          );
      expect(receiptTypeLabel(null_('monthly')), 'Monatsbeleg');
      expect(receiptTypeLabel(null_('annual')), 'Jahresbeleg');
      expect(receiptTypeLabel(null_('annual_replacement')), 'Jahresbeleg (Ersatz)');
      expect(receiptTypeLabel(null_('outage_end')), 'Nullbeleg nach Ausfall');
      expect(receiptTypeLabel(null_('final')), 'Schlussbeleg');
      expect(receiptTypeLabel(null_('manual')), 'Nullbeleg (Prüfbeleg)');
      // Ein künftiger, hier unbekannter Anlass bleibt trotzdem ein Nullbeleg.
      expect(receiptTypeLabel(null_('was_neues')), 'Nullbeleg (Prüfbeleg)');
    });
  });

  group('Filter', () {
    final liste = [
      beleg(receiptId: 'a'),
      beleg(receiptId: 'b', belegart: 'cancellation', summeCents: -500),
      beleg(receiptId: 'c', belegart: 'zero', summeCents: 0),
      beleg(receiptId: 'd', zahlungsart: KeckPaymentMethod.creditCard, bediener: 'Bea'),
    ];

    test('ohne Filter alles', () {
      expect(filterReceipts(liste, const ReceiptFilter()).length, 4);
    });

    test('nur Verkäufe', () {
      final aus = filterReceipts(liste, const ReceiptFilter(receiptType: ReceiptTypeFilter.sale));
      expect(aus.map((b) => b.receiptId), ['a', 'd']);
    });

    test('nur Stornos', () {
      expect(filterReceipts(liste, const ReceiptFilter(receiptType: ReceiptTypeFilter.cancellation)).map((b) => b.receiptId), ['b']);
    });

    test('sonstige ist alles, was weder Verkauf noch Storno ist', () {
      expect(filterReceipts(liste, const ReceiptFilter(receiptType: ReceiptTypeFilter.other)).map((b) => b.receiptId), ['c']);
    });

    test('nach Zahlungsart', () {
      expect(filterReceipts(liste, const ReceiptFilter(payment: PaymentFilter.card)).map((b) => b.receiptId), ['d']);
      expect(filterReceipts(liste, const ReceiptFilter(payment: PaymentFilter.cash)).length, 3);
    });

    test('nach Bediener', () {
      expect(filterReceipts(liste, const ReceiptFilter(operator: 'Bea')).map((b) => b.receiptId), ['d']);
    });

    test('die Bedienerliste ist sortiert und ohne Doppelte', () {
      expect(operatorNames(liste), ['Ali', 'Bea']);
    });
  });

  group('Tagesgruppen', () {
    test('nach Wiener Kalendertag, neueste zuerst', () {
      final aus = groupByDay([
        beleg(receiptId: 'a', zeitstempel: '2026-08-18T09:00:00'),
        beleg(receiptId: 'b', zeitstempel: '2026-08-19T08:00:00'),
        beleg(receiptId: 'c', zeitstempel: '2026-08-19T10:00:00'),
      ]);

      expect(aus.map((g) => g.date), ['2026-08-19', '2026-08-18']);
      expect(aus.first.receipts.map((b) => b.receiptId), ['c', 'b'], reason: 'innerhalb des Tages auch neueste zuerst');
    });

    test('die Uhrzeit kommt in Wiener Wanduhrzeit', () {
      expect(receiptTime('2026-08-19T08:05:00'), '08:05');
    });
  });
}
