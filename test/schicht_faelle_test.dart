import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Die Helfer der Kasse fuer Schicht und Kassenstand gegen die gemeinsamen
/// Prueffaelle des Vertrags (`shift-cases.json`, 1:1 wie im npm-Paket 1.9.0).
final _faelle = jsonDecode(File('test/fixtures/vertrag/shift-cases.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('sumDenominations: alle Faelle des Vertrags', () {
    final liste = (_faelle['sumDenominations'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(19));
    for (final f in liste) {
      expect(sumDenominations(f['denominations']), f['expected'], reason: jsonEncode(f['denominations']));
    }
  });

  test('sumDenominations: Schluessel duerfen auch Zahlen sein, wie Record<string | number> im JS-Zwilling', () {
    expect(sumDenominations({2000: 1, 500: 3}), 3500);
    expect(sumDenominations({300: 1}), isNull);
  });

  test('parseCentsAllowZero: alle Faelle des Vertrags', () {
    final liste = (_faelle['parseCentsAllowZero'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(27));
    for (final f in liste) {
      expect(parseCentsAllowZero(f['text'] as String), f['expected'], reason: '"${f['text']}"');
    }
  });

  test('parseCentsAllowZero: Leerraum wie String.trim in JS, nur ASCII-Ziffern', () {
    expect(parseCentsAllowZero(' 12,5　'), 1250);
    expect(parseCentsAllowZero('\u008512'), isNull, reason: 'NEL ist in JS kein Leerraum');
    expect(parseCentsAllowZero('１２'), isNull);
    expect(parseCentsAllowZero('90071992547409,91'), 9007199254740991);
    expect(parseCentsAllowZero('90071992547409,92'), isNull);
  });

  test('newIdempotencyKey: kasse- und 32 Hex, jedes Mal neu', () {
    final schluessel = {for (var i = 0; i < 200; i++) newIdempotencyKey()};
    expect(schluessel, hasLength(200));
    for (final k in schluessel) {
      expect(k, matches(RegExp(r'^kasse-[0-9a-f]{32}$')));
    }
  });

  test('Kataloge sind die des Vertrags', () {
    final pos = (jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map)['pos'] as Map;
    expect(eurDenominations, pos['eurDenominations']);
    expect(movementTypes, pos['movementTypes']);
    expect(manualMovementTypes, pos['manualMovementTypes']);
    expect(cashLocations, pos['cashLocations']);
    expect(openingReasons, pos['openingReasons']);
    expect(manualOpeningReasons, pos['manualOpeningReasons']);
    expect(shiftReceiptKinds, ['shift_close', 'shift_interim', 'cash_movement']);
    expect(posDeviceOptionalFields, pos['posDeviceOptionalFields']);
    expect(manualMovementTypes, movementTypes.take(8));
  });
}
