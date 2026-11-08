import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kreiseck_validator/kreiseck_validator.dart' show VoucherCode;

/// Form-Erkennung eigener Codes im Feld „Code eingeben oder scannen“
/// (11.22.0), dieselben Beispiele wie `test/eigener-code-form.test.ts` im npm-Paket.
void main() {
  // Ein gueltiger eigener Code (Pruefzeichen V) und derselbe mit falschem Pruefzeichen.
  const code = '1234-5678-9ABV';
  const falsch = '1234-5678-9AB0';

  test('gueltiger eigener Code in jeder Schreibweise der Kasse', () {
    expect(VoucherCode.isValid(code), isTrue);
    for (final t in [code, code.toLowerCase(), '1234.5678.9ABV', '1234_5678/9ABV', ' $code ', ' 123456789ABV　', '1234 5678 9ABV']) {
      expect(ownVoucherCodeShape(t), 'valid', reason: t);
    }
  });

  test('12 Zeichen des Alphabets mit falschem Pruefzeichen = checksum', () {
    expect(VoucherCode.isValid(falsch), isFalse);
    for (final t in [falsch, '123456789AB0', '100000000000', 'ABCD-EFGH-IJKL', 'oooo-llll-iiii']) {
      expect(ownVoucherCodeShape(t), 'checksum', reason: t);
    }
  });

  test('Muster 4-4-x mit eigenen Bindestrichen, falsche Laenge = length', () {
    for (final t in ['7148-FGQA-935', '7148-FGQA-935KX', '7148.FGQA.93', 'abcd-efgh-j']) {
      expect(ownVoucherCodeShape(t), 'length', reason: t);
    }
  });

  test('keine Aehnlichkeit = none', () {
    // Ohne Bindestriche zaehlt nur die genaue Laenge; Zeichen ausserhalb des Alphabets (U, +) passen nie.
    for (final t in ['W-77', '123456789', '12345678901234', '12345678901U', 'ABCD-EFGH', 'abcd-efgh-ij+k', '7148--FGQA-935', 'UUUU-UUUU-UU', '', '   ']) {
      expect(ownVoucherCodeShape(t), 'none', reason: '"$t"');
    }
    for (final w in <Object?>[null, 123456789012, {}]) {
      expect(ownVoucherCodeShape(w), 'none', reason: '$w');
    }
  });

  test('valid genau dann, wenn der Server die Nummer als eigenen Code abweist', () {
    for (final t in [code, falsch, '7148.FGQA.935K', '7148-FGQA-935', 'W-77', '100000000000']) {
      final c = checkExternalVoucherNumber(t);
      expect(ownVoucherCodeShape(t) == 'valid', !c.ok && c.code == 'external_voucher_number_is_own_code', reason: t);
    }
  });

  test('Formen wie surface.json (npm OWN_VOUCHER_CODE_SHAPES)', () {
    final pos = (jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map)['pos'] as Map;
    expect(ownVoucherCodeShapes, pos['ownVoucherCodeShapes']);
    expect(ownVoucherCodeShapes, ['valid', 'checksum', 'length', 'none']);
  });

  test('Texte der Nachfrage', () {
    expect(messageText('external_voucher.looks_like_own_code'), 'Sieht aus wie ein Kasseneck-Code, ist aber keiner. Als fremden Gutschein verwenden?');
    expect(labelText('external_voucher.use_as_external'), 'Als fremden Gutschein');
  });
}
