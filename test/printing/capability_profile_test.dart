import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart' show codeTables;
import 'package:kasseneck_api/src/printing/escpos/capability_profile.dart';

void main() {
  test('getCodePageId kennt CP1252 und CP437', () {
    final p = CapabilityProfile();
    expect(p.getCodePageId('CP437'), 0);
    expect(p.getCodePageId('CP1252'), 16);
  });

  test('unbekannte Codepage faellt auf 0 zurueck', () {
    expect(CapabilityProfile().getCodePageId('CP999'), 0);
  });

  test('jede Tabelle des Katalogs hat ihre ESC-t-Nummer unter ihrem Namen', () {
    final p = CapabilityProfile();
    for (final t in codeTables) {
      expect(p.getCodePageId(t.id.name), t.escT, reason: t.id.name);
    }
    // Die Nummer 0 der Rueckfallebene darf nicht zufaellig richtig sein:
    // pc858 (19) und iso8859_15 (40) liegen woanders.
    expect(p.getCodePageId('pc858'), 19);
    expect(p.getCodePageId('iso8859_15'), 40);
  });
}
