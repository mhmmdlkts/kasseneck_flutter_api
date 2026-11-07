import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Artikel als fremder Gutschein (11.22.0) gegen dieselben Pruefaelle wie npm
/// und Backend (`external-voucher-article-cases.json`).
void main() {
  Map<String, dynamic> json(String pfad) => jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;
  final faelle = json('external-voucher-article-cases.json');
  List<Map<String, dynamic>> abschnitt(String name) => (faelle[name] as List).cast<Map<String, dynamic>>();
  final pos = (json('surface.json')['pos'] as Map).cast<String, dynamic>();

  test('Pruefaelle: Wert beim Speichern (gleich dem Backend)', () {
    expect(abschnitt('values'), isNotEmpty);
    for (final f in abschnitt('values')) {
      expect(checkExternalVoucherValue(f['value']), f['ok'] == true ? isNull : f['reason'], reason: f['name'] as String);
      if (f['ok'] != true) expect(f['code'], articleExternalVoucherInvalid, reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Regeln am Artikel (gleich dem Backend)', () {
    expect(abschnitt('articles'), isNotEmpty);
    for (final f in abschnitt('articles')) {
      final a = (f['article'] as Map).cast<String, Object?>();
      expect(checkExternalVoucherArticle(a), f['ok'] == true ? isNull : f['reason'], reason: f['name'] as String);
      if (f['ok'] != true) expect(f['code'], articleExternalVoucherInvalid, reason: f['name'] as String);
    }
    // Jeder Grund kommt in den Pruefaellen vor, und jeder Grund der Faelle ist bekannt.
    final gruende = {for (final f in [...abschnitt('values'), ...abschnitt('articles')]) if (f['ok'] != true) f['reason'] as String};
    expect(gruende, externalVoucherArticleReasons.toSet());
  });

  test('Pruefaelle ueber den Leser: PosArticle.toJson traegt die /v3-Form', () {
    // Nur Faelle mit bekannter Art: eine unbekannte wird beim Lesen null und
    // waere dann ein normaler Artikel (so gewollt, siehe Leser-Test).
    for (final f in abschnitt('articles')) {
      final roh = (f['article'] as Map).cast<String, dynamic>();
      if (roh['externalVoucher'] != null && ArticleExternalVoucher.fromWire(roh['externalVoucher']) == null) continue;
      final a = PosArticle.fromJson({'id': 'fg', 'name': 'Gutschein', ...roh});
      expect(checkExternalVoucherArticle(a.toJson()), f['ok'] == true ? isNull : f['reason'], reason: f['name'] as String);
    }
  });

  test('Vertrag: Arten, Saetze, Gruende und Zusatz-Gruende wie surface.json und der Katalog', () {
    expect(articleExternalVoucherTypes, pos['articleExternalVoucherTypes']);
    expect(articleExternalVoucherVatRates, pos['articleExternalVoucherVatRates']);
    expect(externalVoucherArticleReasons, pos['externalVoucherArticleReasons']);
    expect(addOnBlockReasons, pos['addOnBlockReasons']);
    final katalog = ((json('v3/v3-vokabular.json')['catalogs'] as Map)['ARTIKEL_FREMDGUTSCHEIN'] as Map).values.toList();
    expect(articleExternalVoucherTypes, katalog);
    // Dieselben Saetze wie der Fremdgutschein am Beleg (Basispunkte).
    expect([for (final p in articleExternalVoucherVatRates) (p * 100).round()]..sort(), [...externalVoucherVatRatesBp]..sort());
  });

  test('Art: Drahtwert und Gutschein-Art des Wunschs', () {
    expect(ArticleExternalVoucher.multiPurpose.voucherType, VoucherType.multiPurpose);
    expect(ArticleExternalVoucher.singlePurpose.voucherType, VoucherType.singlePurpose);
    expect(ArticleExternalVoucher.fromWire('multi_purpose'), ArticleExternalVoucher.multiPurpose);
    expect(ArticleExternalVoucher.fromWire('mehrzweck'), isNull);
  });

  test('Leser: externalVoucher vom Draht, Unbekanntes wird null, Rundreise ueber toJson', () {
    expect(PosArticle.fromJson({'id': 'a', 'name': 'Semmel'}).externalVoucher, isNull);
    expect(PosArticle.fromJson({'id': 'a', 'externalVoucher': 'multi_purpose'}).externalVoucher, ArticleExternalVoucher.multiPurpose);
    expect(PosArticle.fromJson({'id': 'a', 'externalVoucher': 'single_purpose'}).externalVoucher, ArticleExternalVoucher.singlePurpose);
    for (final w in <Object?>['value', 'einzweck', '', 1, true, null, {}]) {
      expect(PosArticle.fromJson({'id': 'a', 'externalVoucher': w}).externalVoucher, isNull, reason: '$w');
    }
    final a = PosArticle.fromJson({'id': 'fg', 'name': 'Gutschein Bäckerei Kornblum', 'unitPriceCents': 2500, 'externalVoucher': 'single_purpose', 'vatRate': 20});
    expect(a.toJson()['externalVoucher'], 'single_purpose');
    expect(PosArticle.fromJson(a.toJson()).externalVoucher, ArticleExternalVoucher.singlePurpose);
    expect(PosArticle.fromJson({'id': 'b'}).toJson()['externalVoucher'], isNull);
  });

  test('Zusatz: ein fremder Gutschein taugt nicht als Zusatz', () {
    final a = PosArticle.fromJson({'id': 'fg', 'name': 'Gutschein', 'unitPriceCents': 2500, 'active': true, 'externalVoucher': 'multi_purpose'});
    expect(isSelectableAddOn(a), 'external_voucher');
  });

  test('Kachel: gesperrt nach Freigabe und Art', () {
    final wert = PosArticle.fromJson({'id': 'w', 'externalVoucher': 'multi_purpose'});
    final leistung = PosArticle.fromJson({'id': 'l', 'externalVoucher': 'single_purpose'});
    final normal = PosArticle.fromJson({'id': 'n'});
    const erwartet = {
      PosExternalVouchers.off: ['not_enabled', 'not_enabled', null],
      PosExternalVouchers.multiPurpose: [null, 'type_not_enabled', null],
      PosExternalVouchers.all: [null, null, null],
    };
    for (final stufe in PosExternalVouchers.values) {
      expect([for (final a in [wert, leistung, normal]) externalVoucherTileBlock(a, stufe)], erwartet[stufe], reason: stufe.wire);
    }
    // Ohne Angabe (Einstellungen noch nicht geladen): zu.
    expect(externalVoucherTileBlock(wert, null), 'not_enabled');
    expect(externalVoucherTileBlock(normal, null), isNull);
    expect(externalVoucherTileBlocks, ['not_enabled', 'type_not_enabled']);
  });

  test('Texte: Saetze und Beschriftungen der Fremdgutscheine', () {
    expect(messageText(externalVoucherTileMessages['not_enabled']!), 'Fremde Gutscheine sind aus. Bitte im Panel freischalten.');
    expect(messageText(externalVoucherTileMessages['type_not_enabled']!), 'Fremde Leistungsgutscheine sind aus. Bitte im Panel freischalten.');
    expect(externalVoucherTileMessages.keys.toList(), externalVoucherTileBlocks);
    expect(messageText('cancellation.external_voucher_check'), 'Vorher im eigenen Gutscheinsystem prüfen, ob er schon benutzt wurde.');
    expect(labelText('external_voucher.line_name', {'number': 'W-77'}), 'Gutschein Nr. W-77');
    expect([for (final s in PosExternalVouchers.values) labelText(externalVouchersLabels[s.wire]!)], ['Aus', 'Nur Wertgutscheine', 'Wert- und Leistungsgutscheine']);
    expect([for (final t in ArticleExternalVoucher.values) labelText(externalVoucherKindLabels[t.wire]!)], ['Wertgutschein', 'Leistungsgutschein']);
    expect(externalVoucherArticleMessages.keys.toSet(), externalVoucherArticleReasons.toSet());
    for (final k in externalVoucherArticleMessages.values) {
      expect(posMessages, contains(k));
    }
  });

  test('Absage beim Speichern: Satz je Grund, nur fuer den eigenen Code', () {
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid, 'rate_required'), 'external_voucher_article.rate_required');
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid, 'price_required'), 'external_voucher_article.price_required');
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid, 'invalid_type'), 'external_voucher_article.invalid');
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid, 'neuer_grund'), 'external_voucher_article.invalid');
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid, 'toString'), 'external_voucher_article.invalid');
    expect(externalVoucherArticleErrorMessage(articleExternalVoucherInvalid), 'external_voucher_article.invalid');
    expect(externalVoucherArticleErrorMessage('validation', 'rate_required'), isNull);
    expect(externalVoucherArticleErrorMessage(null), isNull);
  });

  test('Referenz wie in JavaScript: leerer Text und 0 sperren nicht, ein Objekt schon', () {
    Map<String, Object?> mit(Object? ref) => {'externalVoucher': 'multi_purpose', 'unitPriceCents': 2500, 'reference': ref};
    expect(checkExternalVoucherArticle(mit('')), isNull);
    expect(checkExternalVoucherArticle(mit(0)), isNull);
    expect(checkExternalVoucherArticle(mit(false)), isNull);
    expect(checkExternalVoucherArticle(mit({'mode': 'optional'})), 'reference');
    expect(checkExternalVoucherArticle(mit('x')), 'reference');
    // Preis ganzzahlig wie Number.isInteger: 2500.0 zaehlt, 2500.5 nicht.
    expect(checkExternalVoucherArticle({'externalVoucher': 'multi_purpose', 'unitPriceCents': 2500.0}), isNull);
    expect(checkExternalVoucherArticle({'externalVoucher': 'multi_purpose', 'unitPriceCents': 2500.5}), 'price_required');
  });
}
