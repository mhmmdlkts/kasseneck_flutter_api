import 'package:flutter_test/flutter_test.dart';
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
}
