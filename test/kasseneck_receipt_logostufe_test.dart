import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';

import 'helpers/test_receipts.dart';

/// Die Logo-Stufe kommt mit der Beleg-Antwort (`logo_scale`) -- sie ist die
/// einzige Quelle der App fuer die Groesse des Firmenlogos. Fehlt sie oder ist
/// sie unbekannt, gilt M wie bisher.
void main() {
  test('fromJson liest logo_scale; fehlt oder unbekannt: M', () {
    final basis = cartA().toJson();
    for (final (roh, soll) in [('XL', SheetLogoSize.xl), ('S', SheetLogoSize.s), (null, SheetLogoSize.m), ('riesig', SheetLogoSize.m)]) {
      final json = Map<String, dynamic>.from(basis)..remove('logo_scale');
      if (roh != null) json['logo_scale'] = roh;
      expect(KasseneckReceipt.fromJson(json).logoScale, soll, reason: 'logo_scale=$roh');
    }
  });

  test('toMetadataJson schreibt logo_scale, fromMetadata liest es zurueck', () {
    final beleg = cartA()..logoScale = SheetLogoSize.l;
    final meta = beleg.toMetadataJson();
    expect(meta['logo_scale'], 'L');
    expect(KasseneckReceipt.fromMetadata(beleg.toJson()['receipt'], meta).logoScale, SheetLogoSize.l);
  });
}
