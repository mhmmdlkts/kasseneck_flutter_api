import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

void main() {
  final faelle =
      jsonDecode(
            File(
              'test/fixtures/vertrag/tip-round-up-cases.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('Pruefaelle: Aufrunden-Vorschlaege', () {
    for (final f in (faelle['cases'] as List).cast<Map<String, dynamic>>()) {
      expect(
        roundUpSuggestions(f['baseCents'] as int),
        (f['totals'] as List).cast<int>(),
        reason: '${f['baseCents']}',
      );
    }
  });

  test('Betrag <= 0 liefert keine Vorschlaege', () {
    expect(roundUpSuggestions(0), isEmpty);
    expect(roundUpSuggestions(-5), isEmpty);
  });

  test(
    'immer drei aufsteigende Gesamtbetraege ueber dem Bezugsbetrag, mindestens 2 Prozent und 20 Cent mehr',
    () {
      for (var t = 1; t <= 100000; t += 37) {
        final r = roundUpSuggestions(t);
        expect(r.length, 3, reason: '$t');
        expect(r[0] < r[1] && r[1] < r[2], isTrue, reason: '$t');
        expect(r.first >= t + 20, isTrue, reason: '$t');
        expect(r.first * 100 >= t * 102, isTrue, reason: '$t');
      }
    },
  );
}
