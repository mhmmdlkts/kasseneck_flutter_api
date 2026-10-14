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

  test('shiftTipLines: alle Faelle des Vertrags (Nachtrag 3, R50/R51)', () {
    final liste = (_faelle['shiftTipLines'] as List).cast<Map<String, dynamic>>();
    expect(liste.length, greaterThanOrEqualTo(8));
    for (final f in liste) {
      final t = f['tip'] as Map<String, dynamic>;
      final tip = ShiftTip(
        registerUserId: t['registerUserId'] as String,
        name: t['name'] as String?,
        receivedImmediatelyCents: t['receivedImmediatelyCents'] as int,
        retainedCents: t['retainedCents'] as int,
        paidOutCents: t['paidOutCents'] as int,
        refundedByEmployeeCents: (t['refundedByEmployeeCents'] as int?) ?? 0,
        carriedOverCents: (t['carriedOverCents'] as int?) ?? 0,
        openCents: t['openCents'] as int,
      );
      final zeilen = shiftTipLines(tip);
      expect([for (final z in zeilen) {'key': z.key, 'cents': z.cents}], f['expected'], reason: jsonEncode(t));
      for (final z in zeilen) {
        expect(z.text, labelText(z.key));
      }
    }
  });

  test('shiftTipLines: Laufstand ohne openCents zaehlt offen als 0; Woerter fuer Menschen', () {
    const laufstand = ShiftTipTotals(registerUserId: 'ru_kellner', receivedImmediatelyCents: 400, retainedCents: 150, paidOutCents: 250);
    expect([for (final z in shiftTipLines(laufstand)) z.text], ['verdient', 'über Lohn', 'schon genommen']);
    const voll = ShiftTip(registerUserId: 'ru_kellner', receivedImmediatelyCents: 400, retainedCents: 150, paidOutCents: 250, openCents: 150);
    expect([for (final z in shiftTipLines(voll)) z.text], ['verdient', 'über Lohn', 'schon genommen', 'offen']);
  });

  test('shiftTipLines: selbst zurueckgegeben als eigene Zeile (Fix-Runde 1, R62)', () {
    const tip = ShiftTip(registerUserId: 'ru_kellner', receivedImmediatelyCents: 400, retainedCents: 0, paidOutCents: 0, refundedByEmployeeCents: 200, openCents: 600);
    expect([for (final z in shiftTipLines(tip)) z.text], ['verdient', 'selbst zurückgegeben', 'offen']);
    expect(tip.toJson()['refundedByEmployeeCents'], 200);
  });

  test('shiftTipLines: aus frueheren Schichten als erste Zeile (Fix-Runde 2, R64)', () {
    const tip = ShiftTip(registerUserId: 'ru_kellner', receivedImmediatelyCents: 900, retainedCents: 0, paidOutCents: 0, carriedOverCents: 600, openCents: 1500);
    expect([for (final z in shiftTipLines(tip)) z.text], ['aus früheren Schichten', 'verdient', 'offen']);
    expect(tip.toJson()['carriedOverCents'], 600);
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
