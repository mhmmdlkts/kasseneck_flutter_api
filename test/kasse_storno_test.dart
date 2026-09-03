import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

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
    'uid': null,
    'taxnr': '12/345',
    'phone': '',
    'street': '',
    'zip': '',
    'city': '',
    'footer1': '',
    'footer2': '',
    'thanks_message': '',
  });
}

Belegzusammenfassung zusammenfassung({
  String belegart = 'standard',
  String? storniertBeleg,
  StornoStand stand = StornoStand.offen,
  String? bedienerUid = 'u1',
}) =>
    Belegzusammenfassung(
      receiptId: 'KASSE1-ID-42',
      belegart: belegart,
      zeitstempel: '2026-08-19T10:15:00',
      summeCents: 840,
      zahlungsart: KeckPaymentMethod.cash,
      signaturOk: true,
      positionen: const [],
      stornoStand: stand,
      storniertBeleg: storniertBeleg,
      bediener: Belegbediener(uid: bedienerUid, name: 'Ali'),
    );

void main() {
  group('Restmengen', () {
    test('ohne Storno ist alles offen', () {
      expect(restmengen(belegMit(), jetzt: jetzt), [3, 2]);
    });

    test('ein Teilstorno mindert genau seine Position', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(restmengen(beleg, jetzt: jetzt), [2, 2]);
    });

    test('mehrere Stornos zählen zusammen, nie unter null', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 9000, 'items': [{'index': 0, 'quantity': 2}]},
        {'at': jetzt - 5000, 'items': [{'index': 0, 'quantity': 5}]},
      ]);
      expect(restmengen(beleg, jetzt: jetzt), [0, 2]);
    });

    test('eine frische Reservierung zählt mit', () {
      // Sonst böte die Kasse eine Menge an, die der Server gerade wegbucht.
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'pending': true, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(restmengen(beleg, jetzt: jetzt), [2, 2]);
    });

    test('eine liegengebliebene Reservierung zählt nicht mehr', () {
      // Sonst bliebe eine Position für immer gesperrt, weil ein Abbruch
      // irgendwann einmal eine Reservierung stehen ließ.
      final beleg = belegMit(stornos: [
        {'at': jetzt - 200000, 'pending': true, 'items': [{'index': 0, 'quantity': 1}]},
      ]);
      expect(restmengen(beleg, jetzt: jetzt), [3, 2]);
    });

    test('ein Eintrag auf eine Position, die es nicht gibt, stört nicht', () {
      final beleg = belegMit(stornos: [
        {'at': jetzt - 5000, 'items': [{'index': 9, 'quantity': 1}]},
      ]);
      expect(restmengen(beleg, jetzt: jetzt), [3, 2]);
    });
  });

  group('Storno-Gründe', () {
    test('der Katalog stimmt mit dem Backend überein', () {
      expect(stornogruende.keys.toList(), [
        'fehleingabe',
        'kunde_storniert',
        'falsche_zahlart',
        'doppelt_erfasst',
        'sonstiges',
      ]);
      expect(stornogruende['fehleingabe'], 'Fehleingabe');
    });
  });

  group('darf storniert werden?', () {
    test('ein Verkauf mit Vollrecht ja', () {
      expect(stornoErlaubt(zusammenfassung(), RegisterScope.all, 'u2'), isTrue);
    });

    test('ohne Recht nie', () {
      expect(stornoErlaubt(zusammenfassung(), RegisterScope.none, 'u1'), isFalse);
    });

    test('mit „eigene" nur die eigenen', () {
      expect(stornoErlaubt(zusammenfassung(bedienerUid: 'u1'), RegisterScope.own, 'u1'), isTrue);
      expect(stornoErlaubt(zusammenfassung(bedienerUid: 'u2'), RegisterScope.own, 'u1'), isFalse);
    });

    test('kein Storno von einem Storno', () {
      expect(
        stornoErlaubt(zusammenfassung(belegart: 'cancellation'), RegisterScope.all, 'u1'),
        isFalse,
      );
      expect(
        stornoErlaubt(zusammenfassung(storniertBeleg: 'KASSE1-ID-41'), RegisterScope.all, 'u1'),
        isFalse,
      );
    });

    test('kein Storno von Null- oder Startbelegen', () {
      for (final art in ['zero', 'start', 'training']) {
        expect(stornoErlaubt(zusammenfassung(belegart: art), RegisterScope.all, 'u1'), isFalse, reason: art);
      }
    });

    test('ein voll stornierter Beleg ist erledigt', () {
      expect(
        stornoErlaubt(zusammenfassung(stand: StornoStand.voll), RegisterScope.all, 'u1'),
        isFalse,
      );
    });

    test('ein teilweise stornierter Beleg geht weiter', () {
      expect(
        stornoErlaubt(zusammenfassung(stand: StornoStand.teil), RegisterScope.all, 'u1'),
        isTrue,
      );
    });
  });

  group('welche Belege sieht der Kassier?', () {
    test('mit „alle" alle', () {
      expect(belegSichtbar(zusammenfassung(bedienerUid: 'u2'), RegisterScope.all, 'u1'), isTrue);
    });

    test('mit „eigene" nur die eigenen', () {
      expect(belegSichtbar(zusammenfassung(bedienerUid: 'u1'), RegisterScope.own, 'u1'), isTrue);
      expect(belegSichtbar(zusammenfassung(bedienerUid: 'u2'), RegisterScope.own, 'u1'), isFalse);
    });

    test('ohne Recht keine', () {
      expect(belegSichtbar(zusammenfassung(), RegisterScope.none, 'u1'), isFalse);
    });
  });

  group('Beleg-Kennung', () {
    test('die Nummer lässt sich aus der vollen Kennung lesen', () {
      expect(idNummer('KASSE1-ID-809'), '809');
      expect(idNummer('etwas-anderes'), 'etwas-anderes');
    });

    test('aus getippter Nummer wird die volle Kennung', () {
      expect(volleId('KASSE1', '809'), 'KASSE1-ID-809');
      // Nur Ziffern, höchstens sieben — der Rest fällt weg.
      expect(volleId('KASSE1', '8a0b9'), 'KASSE1-ID-809');
      expect(volleId('KASSE1', ''), isNull);
      expect(volleId('KASSE1', 'abc'), isNull);
    });
  });
}
