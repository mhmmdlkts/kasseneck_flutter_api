import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';

import 'helpers/test_receipts.dart';

/// Die Logo-Stufe kommt mit der Beleg-Antwort (`logo_skala`) -- sie ist die
/// einzige Quelle der App fuer die Groesse des Firmenlogos. Fehlt sie oder ist
/// sie unbekannt, gilt M wie bisher.
void main() {
  test('fromJson liest logo_skala; fehlt oder unbekannt: M', () {
    final basis = cartA().toJson();
    for (final (roh, soll) in [('XL', LogoStufe.xl), ('S', LogoStufe.s), (null, LogoStufe.m), ('riesig', LogoStufe.m)]) {
      final json = Map<String, dynamic>.from(basis)..remove('logo_skala');
      if (roh != null) json['logo_skala'] = roh;
      expect(KasseneckReceipt.fromJson(json).logoStufe, soll, reason: 'logo_skala=$roh');
    }
  });

  test('toMetadataJson schreibt logo_skala, fromMetadata liest es zurueck', () {
    final beleg = cartA()..logoStufe = LogoStufe.l;
    final meta = beleg.toMetadataJson();
    expect(meta['logo_skala'], 'L');
    expect(KasseneckReceipt.fromMetadata(beleg.toJson()['receipt'], meta).logoStufe, LogoStufe.l);
  });
}
