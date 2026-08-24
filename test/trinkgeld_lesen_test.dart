// ── Trinkgeld am fertigen Beleg ─────────────────────────────────────────────
// Die Gegenrichtung zu trinkgeld_test.dart: Was vom Server zurueckkommt, muss
// sich auch auslesen lassen — getrennt nach Mitarbeiter (durchlaufender
// Posten) und Inhaber (Entgelt), denn nur der erste Betrag muss weitergegeben
// werden.
//
// Gerechnet wird an den Golden-Belegen des JS-Pakets, nicht an selbst
// gebastelten Zeilen: So steht hier dasselbe Trinkgeld wie in Browser-Kasse,
// Bondrucker und Beleg-PDF.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';

final _wurzel = Directory('test/fixtures/belege');

Map<String, dynamic> _json(String pfad) =>
    jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

/// Baut aus einem Golden-Beleg die Antwortgestalt, die `fromJson` erwartet.
KasseneckReceipt _beleg(String name) {
  final f = _json('${_wurzel.path}/belege/$name.json');
  final firma = f['company'] as Map<String, dynamic>;
  return KasseneckReceipt.fromJson({
    'receipt': {
      ...(f['receipt'] as Map<String, dynamic>),
      'customerDetails': '',
      'legalMessage': '',
    },
    'company': firma['companyName'],
    'street': firma['street'],
    'zip': firma['zip'],
    'city': firma['city'],
    'phone': firma['phone'],
    'uid': firma['uid'],
    'taxnr': firma['taxnr'],
    'is_small_business': false,
    'footer1': firma['footer1'] ?? '',
    'footer2': firma['footer2'] ?? '',
  });
}

void main() {
  group('Mitarbeiter-Trinkgeld', () {
    late KasseneckReceipt beleg;

    setUp(() => beleg = _beleg('rabatt-trinkgeld'));

    test('wird als Trinkgeld erkannt und mit 0 % gefuehrt', () {
      expect(beleg.tipItems.length, 1);
      final pos = beleg.tipItems.single;
      expect(pos.isTip, isTrue);
      expect(pos.vat.rate, 0); // durchlaufender Posten, kein Umsatz
      expect(pos.totalCents, 100);
    });

    test('zaehlt zum Mitarbeiter-Topf, nicht zum Inhaber', () {
      expect(beleg.tipCents, 100);
      expect(beleg.staffTipCents, 100);
      expect(beleg.ownerTipCents, 0);
      expect(beleg.tip, 1.0);
    });

    test('nennt den Empfaenger', () {
      final pos = beleg.tipItems.single;
      expect(pos.isOwnerTip, isFalse);
      expect(pos.tipRecipientId, 'ru1');
      expect(pos.tipRecipientName, 'Anna');
      expect(pos.paymentMethod, 'cash');
    });
  });

  group('Inhaber-Trinkgeld', () {
    late KasseneckReceipt beleg;

    setUp(() => beleg = _beleg('rabatt-chef-trinkgeld'));

    test('faellt anteilig auf die Steuersaetze der Ware', () {
      // 2,00 € auf 10 % und 20 % verteilt — beides Entgelt, keine Null-Zeile.
      expect(beleg.tipItems.length, 2);
      expect(beleg.tipItems.map((i) => i.vat.rate).toList(), [10, 20]);
      expect(beleg.tipItems.map((i) => i.totalCents).toList(), [106, 94]);
    });

    test('zaehlt zum Inhaber-Topf, nicht zum Mitarbeiter', () {
      expect(beleg.tipCents, 200);
      expect(beleg.ownerTipCents, 200);
      expect(beleg.staffTipCents, 0);
    });

    test('traegt den Inhaber-Vermerk an jeder Zeile', () {
      for (final pos in beleg.tipItems) {
        expect(pos.isOwnerTip, isTrue);
        expect(pos.tipRecipientId, 'ru2');
        expect(pos.tipRecipientName, 'Chef');
      }
    });
  });

  group('Belege ohne Trinkgeld', () {
    test('bleiben bei null — auch der mit Rabattzeilen', () {
      for (final name in ['verkauf-bar', 'verkauf-karte', 'rabatt-einfach']) {
        final beleg = _beleg(name);
        expect(beleg.tipItems, isEmpty, reason: name);
        expect(beleg.tipCents, 0, reason: name);
        expect(beleg.staffTipCents, 0, reason: name);
        expect(beleg.ownerTipCents, 0, reason: name);
      }
    });

    test('eine Rabattzeile ist kein Trinkgeld', () {
      final beleg = _beleg('rabatt-einfach');
      expect(beleg.items.any((i) => i.isDiscount), isTrue);
      expect(beleg.items.any((i) => i.isTip), isFalse);
    });
  });

  group('Storno', () {
    test('negative Trinkgeld-Zeilen zaehlen vorzeichengetreu', () {
      // So wie die Spiegelung eines Trinkgeld-Belegs aussieht: dieselbe
      // Kennzeichnung, negativer Betrag. Sonst kaeme das Trinkgeld beim
      // Zuruecknehmen als gewoehnliche Warenzeile an und der Topf bliebe voll.
      final pos = KasseneckItem.fromJson({
        'name': 'Trinkgeld Personal',
        'quantity': 1,
        'unitPriceCents': -100,
        'vatRate': 0,
        'kind': 'tip',
        'recipient': {'registerUserId': 'ru1', 'name': 'Anna'},
        'paymentMethod': 'cash',
      });
      expect(pos.isTip, isTrue);
      expect(pos.totalCents, -100);
      expect(pos.tipRecipientId, 'ru1');
      // Die Kennzeichnung reist auch wieder hinaus (Spiegelung zum Backend).
      expect(pos.toJson()['kind'], 'tip');
      expect(
          pos.toJson()['recipient'], {'registerUserId': 'ru1', 'name': 'Anna'});
    });
  });

  group('Unvollstaendige Angaben', () {
    test(
        'nicht zugeordnetes Trinkgeld hat keinen Empfaenger, bleibt aber Trinkgeld',
        () {
      final pos = KasseneckItem.fromJson({
        'name': 'Trinkgeld Personal',
        'quantity': 1,
        'unitPriceCents': 100,
        'vatRate': 0,
        'kind': 'tip',
        'recipient': null,
      });
      expect(pos.isTip, isTrue);
      expect(pos.isOwnerTip, isFalse);
      expect(pos.tipRecipientId, isNull);
      expect(pos.tipRecipientName, isNull);
    });

    test('ein leerer Name ist kein Name', () {
      final pos = KasseneckItem.fromJson({
        'name': 'Trinkgeld Personal',
        'quantity': 1,
        'unitPriceCents': 100,
        'vatRate': 0,
        'kind': 'tip',
        'recipient': {'registerUserId': '', 'name': ''},
      });
      expect(pos.tipRecipientId, isNull);
      expect(pos.tipRecipientName, isNull);
    });
  });
}
