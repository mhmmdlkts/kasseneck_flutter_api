import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Die Belegliste: Zeitraum, Filter, Tagesgruppen — Zwilling von `belege.ts`
/// der Browser-Kasse.
///
/// Gerechnet wird in **Wiener Kalendertagen**, nicht in denen des Geräts. Ein
/// Tablet mit falsch gestellter Zeitzone darf den Kassenschluss nicht
/// verschieben.

/// 19.08.2026, 00:30 Wiener Wanduhrzeit (also 22:30 UTC am 18.8.).
final jetzt = DateTime.utc(2026, 8, 18, 22, 30);

Belegzusammenfassung beleg({
  String receiptId = 'KASSE1-ID-1',
  String belegart = 'standard',
  String zeitstempel = '2026-08-19T10:15:00',
  int summeCents = 500,
  KeckPaymentMethod zahlungsart = KeckPaymentMethod.cash,
  String? storniertBeleg,
  String bediener = 'Ali',
}) =>
    Belegzusammenfassung(
      receiptId: receiptId,
      belegart: belegart,
      zeitstempel: zeitstempel,
      summeCents: summeCents,
      zahlungsart: zahlungsart,
      signaturOk: true,
      positionen: const [],
      stornoStand: StornoStand.offen,
      storniertBeleg: storniertBeleg,
      bediener: Belegbediener(uid: 'u1', name: bediener),
    );

void main() {
  group('Zeitfenster', () {
    test('heute ist der Wiener Kalendertag — auch kurz nach Mitternacht', () {
      // Um 00:30 Wien ist es UTC noch der Vortag. Wer hier UTC nimmt, zeigt
      // dem Kassier um halb eins die Belege von gestern.
      expect(zeitfenster(Zeitraum.heute, jetzt), (von: '2026-08-19', bis: '2026-08-19'));
    });

    test('gestern ist genau ein Tag', () {
      expect(zeitfenster(Zeitraum.gestern, jetzt), (von: '2026-08-18', bis: '2026-08-18'));
    });

    test('sieben Tage schließen heute mit ein', () {
      expect(zeitfenster(Zeitraum.siebenTage, jetzt), (von: '2026-08-13', bis: '2026-08-19'));
    });

    test('dreißig Tage ebenso', () {
      expect(zeitfenster(Zeitraum.dreissigTage, jetzt), (von: '2026-07-21', bis: '2026-08-19'));
    });
  });

  group('Belegart lesbar', () {
    test('Verkauf, Storno, Startbeleg', () {
      expect(belegartText(beleg()), 'Verkauf');
      expect(belegartText(beleg(belegart: 'cancellation')), 'Storno');
      expect(belegartText(beleg(storniertBeleg: 'KASSE1-ID-1')), 'Storno');
      expect(belegartText(beleg(belegart: 'start')), 'Startbeleg');
      expect(belegartText(beleg(belegart: 'training')), 'Trainingsbeleg');
    });

    test('Nullbelege nennen ihren Anlass', () {
      Belegzusammenfassung null_(String anlass) => Belegzusammenfassung(
            receiptId: 'x',
            belegart: 'zero',
            zeitstempel: '2026-08-19T10:15:00',
            summeCents: 0,
            zahlungsart: KeckPaymentMethod.cash,
            signaturOk: true,
            positionen: const [],
            stornoStand: StornoStand.offen,
            nullbelegAnlass: anlass,
          );
      expect(belegartText(null_('monthly')), 'Monatsbeleg');
      expect(belegartText(null_('annual')), 'Jahresbeleg');
      expect(belegartText(null_('annual_replacement')), 'Jahresbeleg (Ersatz)');
      expect(belegartText(null_('outage_end')), 'Nullbeleg nach Ausfall');
      expect(belegartText(null_('final')), 'Schlussbeleg');
      expect(belegartText(null_('manual')), 'Nullbeleg (Prüfbeleg)');
      // Ein künftiger, hier unbekannter Anlass bleibt trotzdem ein Nullbeleg.
      expect(belegartText(null_('was_neues')), 'Nullbeleg (Prüfbeleg)');
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
      expect(gefiltert(liste, const Belegfilter()).length, 4);
    });

    test('nur Verkäufe', () {
      final aus = gefiltert(liste, const Belegfilter(belegart: BelegartFilter.verkauf));
      expect(aus.map((b) => b.receiptId), ['a', 'd']);
    });

    test('nur Stornos', () {
      expect(gefiltert(liste, const Belegfilter(belegart: BelegartFilter.storno)).map((b) => b.receiptId), ['b']);
    });

    test('sonstige ist alles, was weder Verkauf noch Storno ist', () {
      expect(gefiltert(liste, const Belegfilter(belegart: BelegartFilter.sonstige)).map((b) => b.receiptId), ['c']);
    });

    test('nach Zahlungsart', () {
      expect(gefiltert(liste, const Belegfilter(zahlung: ZahlungFilter.karte)).map((b) => b.receiptId), ['d']);
      expect(gefiltert(liste, const Belegfilter(zahlung: ZahlungFilter.bar)).length, 3);
    });

    test('nach Bediener', () {
      expect(gefiltert(liste, const Belegfilter(wer: 'Bea')).map((b) => b.receiptId), ['d']);
    });

    test('die Bedienerliste ist sortiert und ohne Doppelte', () {
      expect(bediener(liste), ['Ali', 'Bea']);
    });
  });

  group('Tagesgruppen', () {
    test('nach Wiener Kalendertag, neueste zuerst', () {
      final aus = tagesgruppen([
        beleg(receiptId: 'a', zeitstempel: '2026-08-18T09:00:00'),
        beleg(receiptId: 'b', zeitstempel: '2026-08-19T08:00:00'),
        beleg(receiptId: 'c', zeitstempel: '2026-08-19T10:00:00'),
      ]);

      expect(aus.map((g) => g.datum), ['2026-08-19', '2026-08-18']);
      expect(aus.first.belege.map((b) => b.receiptId), ['c', 'b'], reason: 'innerhalb des Tages auch neueste zuerst');
    });

    test('die Uhrzeit kommt in Wiener Wanduhrzeit', () {
      expect(uhrzeit('2026-08-19T08:05:00'), '08:05');
    });
  });
}
