import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

void main() {
  final faelle = jsonDecode(File('test/fixtures/vertrag/reference-cases.json').readAsStringSync()) as Map<String, dynamic>;

  test('Pruefaelle: Muster gueltig und Ziffernfeld', () {
    for (final f in (faelle['patterns'] as List).cast<Map<String, dynamic>>()) {
      expect(isValidReferencePattern(f['pattern'] as String), f['valid'], reason: f['pattern'] as String);
      expect(isDigitsOnlyPattern(f['pattern'] as String), f['digitsOnly'], reason: f['pattern'] as String);
    }
  });

  test('Pruefaelle: Eingabe pruefen', () {
    for (final f in (faelle['inputs'] as List).cast<Map<String, dynamic>>()) {
      final r = f['reference'] as Map<String, dynamic>?;
      final ref = r == null
          ? null
          : PosReference(
              mode: r['mode'] == 'required' ? ReferenceMode.required : ReferenceMode.optional,
              label: 'Nr.',
              pattern: r['pattern'] as String?,
              patternStrict: r['patternStrict'] == true,
            );
      final c = checkReference(f['input'] as String, ref);
      expect(c.result.name, f['result'], reason: f['name'] as String);
      expect(c.value, f['value'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Positionsname', () {
    for (final f in (faelle['lineNames'] as List).cast<Map<String, dynamic>>()) {
      expect(referenceLineName(f['articleName'] as String, f['value'] as String), f['lineName']);
    }
  });

  test('Vorlagen sind gueltige Muster', () {
    for (final v in referencePatternTemplates.values) {
      expect(isValidReferencePattern(v), isTrue, reason: v);
    }
  });

  test('Leser: askPrice und reference vom Draht, Rundreise ueber toJson', () {
    final a = PosArticle.fromJson({
      'id': 'a', 'name': 'Honorarnote', 'unitPriceCents': null, 'askPrice': true,
      'reference': {'mode': 'required', 'label': 'Honorarnote Nr.', 'hint': 'z. B. 2026/0123', 'pattern': r'\d+', 'patternStrict': true},
    });
    expect(a.askPrice, isTrue);
    expect(a.reference!.mode, ReferenceMode.required);
    expect(a.reference!.patternStrict, isTrue);
    expect(isBookableArticle(a), isTrue);
    expect(tilePrompts(a), (amount: true, reference: true, quantity: false));
    final zurueck = PosArticle.fromJson(a.toJson());
    expect(zurueck.reference!.toJson(), a.reference!.toJson());
    final alt = PosArticle.fromJson({'id': 'b', 'name': 'Semmel'});
    expect(alt.askPrice, isFalse);
    expect(alt.reference, isNull);
    expect(isBookableArticle(alt), isFalse);
  });

  test('Leser: unbrauchbare reference wird null, patternStrict ohne Muster false', () {
    expect(PosReference.fromJson({'mode': 'immer', 'label': 'x'}), isNull);
    expect(PosReference.fromJson({'mode': 'optional', 'label': ''}), isNull);
    expect(PosReference.fromJson('x'), isNull);
    expect(PosReference.fromJson({'mode': 'optional', 'label': 'Nr.', 'patternStrict': true})!.patternStrict, isFalse);
  });
}
