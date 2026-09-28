import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Storno-Regeln der Kasse — Zwilling von `models/cancellation.ts` und der
/// Storno-Regeln in `belege.ts` der Browser-Kasse.
///
/// **Die Wahrheit hat der Server.** Er hält die Restmengen und die Reichweite
/// des Rechts. Hier wird nur entschieden, was die Kasse überhaupt anbietet —
/// ein Knopf, der sicher auf einen Fehler läuft, gehört nicht auf den Schirm.

const jetzt = 1787000000000;

KasseneckReceipt belegMit({List<Map<String, dynamic>>? stornos, int menge = 3}) {
  return KasseneckReceipt.fromJson({
    'receipt': {
      'receiptId': 'KASSE1-ID-42',
      'fullReceiptId': 'voll-42',
      'receiptType': 'standard',
      'cashregisterId': 'KASSE1',
      'timeStamp': '2026-08-19T10:15:00',
      'paymentMethod': 'cash',
      'items': [
        {'name': 'Kaffee', 'quantity': menge, 'unitPriceCents': 280, 'vatRate': 20},
        {'name': 'Semmel', 'quantity': 2, 'unitPriceCents': 150, 'vatRate': 10},
      ],
      'cancellations': ?stornos,
      'qr': 'q',
      'sig': 'kopf.rumpf.sig',
      'certificateSerialNumber': 'cert',
      'signaturePreviousReceipt': 'prev',
      'turnoverCounterAES256ICM': 'aes',
      'signatureSuccess': true,
    },
    'company': 'Testbetrieb',
    'is_small_business': false,
    'vatId': null,
    'taxNumber': '12/345',
    'phone': '',
    'street': '',
    'zip': '',
    'city': '',
    'footer1': '',
    'footer2': '',
    'thanks_message': '',
  });
}

ReceiptSummary zusammenfassung({
  String belegart = 'standard',
  String? storniertBeleg,
  CancellationState? stand = CancellationState.none,
  String? bedienerUid = 'u1',
}) =>
    ReceiptSummary(
      receiptId: 'KASSE1-ID-42',
      receiptType: belegart,
      timeStamp: '2026-08-19T10:15:00',
      totalCents: 840,
      paymentMethod: KeckPaymentMethod.cash,
      signatureOk: true,
      items: const [],
      cancellationState: stand,
      cancellationOfReceiptId: storniertBeleg,
      operator: ReceiptOperator(uid: bedienerUid, name: 'Ali'),
    );

void main() {
  main2();
  group('Restmengen', () {
    test('ohne Storno ist alles offen', () {
      expect(remainingQuantities(belegMit(), nowMs: jetzt), [3, 2]);
    });

    test('ein Teilstorno mindert genau seine Position', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(remainingQuantities(beleg, nowMs: jetzt), [2, 2]);
    });

    test('mehrere Stornos zählen zusammen, nie unter null', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 9000, 'items': [{'index': 0, 'quantity': 2}]},
        {'at': jetzt - 5000, 'items': [{'index': 0, 'quantity': 5}]},
      ]);
      expect(remainingQuantities(beleg, nowMs: jetzt), [0, 2]);
    });

    test('eine frische Reservierung zählt mit', () {
      // Sonst böte die Kasse eine Menge an, die der Server gerade wegbucht.
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'pending': true, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(remainingQuantities(beleg, nowMs: jetzt), [2, 2]);
    });

    test('eine liegengebliebene Reservierung zählt nicht mehr', () {
      // Sonst bliebe eine Position für immer gesperrt, weil ein Abbruch
      // irgendwann einmal eine Reservierung stehen ließ.
      final beleg = belegMit(stornos: [
        {'at': jetzt - 200000, 'pending': true, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(remainingQuantities(beleg, nowMs: jetzt), [3, 2]);
    });

    test('ein Eintrag auf eine Position, die es nicht gibt, stört nicht', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'items': [{'index': 9, 'quantity': 1}]},
      ]);
      expect(remainingQuantities(beleg, nowMs: jetzt), [3, 2]);
    });
  });

  group('Storno-Gründe', () {
    test('der Katalog stimmt mit dem Backend überein', () {
      expect(cancellationReasons.keys.toList(), [
        'input_error',
        'customer_cancelled',
        'wrong_payment_method',
        'duplicate',
        'other',
      ]);
      // Die Beschriftung bleibt deutsch, sie steht so am Bon.
      expect(cancellationReasons['input_error'], 'Fehleingabe');
    });
  });

  group('darf storniert werden?', () {
    test('ein Verkauf mit Vollrecht ja', () {
      expect(canCancel(zusammenfassung(), RegisterScope.all, 'u2'), isTrue);
    });

    test('ohne Recht nie', () {
      expect(canCancel(zusammenfassung(), RegisterScope.none, 'u1'), isFalse);
    });

    test('mit „eigene" nur die eigenen', () {
      expect(canCancel(zusammenfassung(bedienerUid: 'u1'), RegisterScope.own, 'u1'), isTrue);
      expect(canCancel(zusammenfassung(bedienerUid: 'u2'), RegisterScope.own, 'u1'), isFalse);
    });

    test('kein Storno von einem Storno', () {
      expect(
        canCancel(zusammenfassung(belegart: 'cancellation'), RegisterScope.all, 'u1'),
        isFalse,
      );
      expect(
        canCancel(zusammenfassung(storniertBeleg: 'KASSE1-ID-41'), RegisterScope.all, 'u1'),
        isFalse,
      );
    });

    test('kein Storno von Null- oder Startbelegen', () {
      for (final art in ['zero', 'start', 'training']) {
        expect(canCancel(zusammenfassung(belegart: art), RegisterScope.all, 'u1'), isFalse, reason: art);
      }
    });

    test('ein voll stornierter Beleg ist erledigt', () {
      expect(
        canCancel(zusammenfassung(stand: CancellationState.full), RegisterScope.all, 'u1'),
        isFalse,
      );
    });

    test('ein unbekannter Stornostand bietet keinen Storno an, ein fehlender laesst den Server entscheiden', () {
      expect(canCancel(zusammenfassung(stand: CancellationState.unknown), RegisterScope.all, 'u1'), isFalse);
      expect(canCancel(zusammenfassung(stand: null), RegisterScope.all, 'u1'), isTrue);
    });

    test('ein teilweise stornierter Beleg geht weiter', () {
      expect(
        canCancel(zusammenfassung(stand: CancellationState.partial), RegisterScope.all, 'u1'),
        isTrue,
      );
    });
  });

  group('welche Belege sieht der Kassier?', () {
    test('mit „alle" alle', () {
      expect(isReceiptVisible(zusammenfassung(bedienerUid: 'u2'), RegisterScope.all, 'u1'), isTrue);
    });

    test('mit „eigene" nur die eigenen', () {
      expect(isReceiptVisible(zusammenfassung(bedienerUid: 'u1'), RegisterScope.own, 'u1'), isTrue);
      expect(isReceiptVisible(zusammenfassung(bedienerUid: 'u2'), RegisterScope.own, 'u1'), isFalse);
    });

    test('ohne Recht keine', () {
      expect(isReceiptVisible(zusammenfassung(), RegisterScope.none, 'u1'), isFalse);
    });
  });

  group('Beleg-Kennung', () {
    test('die Nummer lässt sich aus der vollen Kennung lesen', () {
      expect(receiptNumber('KASSE1-ID-809'), '809');
      expect(receiptNumber('etwas-anderes'), 'etwas-anderes');
    });

    test('aus getippter Nummer wird die volle Kennung', () {
      expect(fullReceiptIdFromNumber('KASSE1', '809'), 'KASSE1-ID-809');
      // Nur Ziffern, höchstens sieben — der Rest fällt weg.
      expect(fullReceiptIdFromNumber('KASSE1', '8a0b9'), 'KASSE1-ID-809');
      expect(fullReceiptIdFromNumber('KASSE1', ''), isNull);
      expect(fullReceiptIdFromNumber('KASSE1', 'abc'), isNull);
    });
  });
}

// Fehlercodes von cancelReceipt -- die Liste gegen das Vokabular pruefen die
// Tests in receipt_v3_codes_test.dart; hier nur die Erkennung.
void main2() {
  group('Fehlercodes', () {
    test('istStornoFehlercode nimmt Katalog-Codes an, keinen Anzeigetext, kein null, keinen alten Code', () {
      expect(cancellationErrorCodes.first, 'receipt_not_found');
      expect(isCancellationErrorCode('quantity_exceeds_remaining'), isTrue);
      expect(isCancellationErrorCode('cancellation_outcome_unknown'), isTrue);
      expect(isCancellationErrorCode('Storno-Menge übersteigt die verbleibende Menge (Position 1).'), isFalse);
      expect(isCancellationErrorCode(null), isFalse);
      // Die alten Codes aus /v1 (deutsch bzw. gross) sind keine /v3-Codes mehr.
      expect(isCancellationErrorCode('menge_ueber_rest'), isFalse);
      expect(isCancellationErrorCode('STORNO_PAYMENTS_REQUIRED'), isFalse);
    });
  });
}
