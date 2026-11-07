/// Artikel als fremder Gutschein (Fremdgutscheine an der Kasse, 11.22.0): der
/// Chef legt einen Artikel als Kachel „fremder Gutschein“ an. Die Kasse fragt
/// beim Antippen die Gutscheinnummer (und ohne Preis den Betrag) ab und sendet
/// statt einer Position einen Gutschein-Wunsch
/// `KeckVoucher(source: voucherSourceExternal, action: sell, type: externalVoucher.voucherType, number, amountCents, vatRateBp?)`.
///
/// Die Regeln am Artikel rechnet das Backend
/// (`functions-kasse/fremdgutschein-artikel-core.js`) beim Speichern, Code
/// `article_external_voucher_invalid` mit `data.grund`; ein Artikel-Editor
/// prueft vorher gleich. Zwilling von `pos/fremdgutschein-artikel.ts`; Vertrag
/// sind die Pruefaelle `test/fixtures/vertrag/external-voucher-article-cases.json`
/// (byte-gleich mit Backend und npm).
library;

import 'artikel.dart';
import 'gutschein.dart' show PosExternalVouchers;

/// Die Arten am Draht (Zwilling von `ARTICLE_EXTERNAL_VOUCHER_TYPES`).
final List<String> articleExternalVoucherTypes = List.unmodifiable([for (final a in ArticleExternalVoucher.values) a.wire]);

/// Fehlercode beim Speichern eines Artikels, intern und unter `/v3` gleich.
const String articleExternalVoucherInvalid = 'article_external_voucher_invalid';

/// Welche Regel verletzt ist (Antwortfeld `data.grund`), in der Reihenfolge,
/// in der der Server prueft.
const List<String> externalVoucherArticleReasons = [
  'invalid_type', 'service_voucher', 'add_ons', 'stock_tracked', 'reference', 'asks_quantity', 'rate_required', 'invalid_rate', 'price_required',
];

/// Saetze, mit denen ein Einzweckgutschein verkauft werden kann (Prozent wie
/// [PosArticle.vatRate]; 0 = befreit verkauft): die Saetze der Kasse, dieselben
/// wie `externalVoucherVatRatesBp` / 100.
const List<num> articleExternalVoucherVatRates = [20, 13, 10, 4.9, 0, 19];

/// Form des Werts beim Speichern: `null` heisst entfernen und ist gueltig.
/// Zwilling von `checkExternalVoucherValue` (Backend `pruefeWert`).
String? checkExternalVoucherValue(Object? value) =>
    value == null || ArticleExternalVoucher.fromWire(value) != null ? null : 'invalid_type';

/// Wahrheitswert wie in JavaScript (`if (wert)`): die Regel `reference` prueft
/// im Zwilling so, und ein leerer Text oder `0` darf dort nicht sperren.
bool _wahr(Object? wert) => switch (wert) {
      null || false => false,
      final String s => s.isNotEmpty,
      final num n => n != 0 && !n.isNaN,
      _ => true,
    };

/// Regeln am wirksamen Artikelstand (Bestand + Aenderung) in `/v3`-Form
/// (`externalVoucher`, `unitPriceCents`, `vatRate`, `askPrice`,
/// `serviceVoucher`, `addOns`, `stockTracked`, `reference`, `askQuantity`;
/// [PosArticle.toJson] liefert diese Form). `null` = passt, sonst ein Wert aus
/// [externalVoucherArticleReasons]. Ohne `externalVoucher` gilt keine Regel.
///
/// Einzweck verlangt einen Satz der Kasse (0 = befreit verkauft), Mehrzweck
/// ignoriert ihn; nie zusammen mit Leistungsgutschein, eigener Zusatzliste,
/// Lagerbestand, Referenz oder Mengenabfrage (die Kasse fragt die Nummer
/// selbst und bucht genau einen); ohne `askPrice` braucht er einen Preis ab
/// 1 Cent. Zwilling von `checkExternalVoucherArticle` (Backend `pruefeArtikel`).
String? checkExternalVoucherArticle(Map<String, Object?> article) {
  final wert = article['externalVoucher'];
  if (wert == null) return null;
  final art = ArticleExternalVoucher.fromWire(wert);
  if (art == null) return 'invalid_type';
  if (article['serviceVoucher'] == true) return 'service_voucher';
  final zusaetze = article['addOns'];
  if (zusaetze is List && zusaetze.isNotEmpty) return 'add_ons';
  if (article['stockTracked'] == true) return 'stock_tracked';
  if (_wahr(article['reference'])) return 'reference';
  if (article['askQuantity'] == true) return 'asks_quantity';
  if (art == ArticleExternalVoucher.singlePurpose) {
    final satz = article['vatRate'];
    if (satz is! num || !satz.isFinite) return 'rate_required';
    if (!articleExternalVoucherVatRates.contains(satz)) return 'invalid_rate';
  }
  final preis = article['unitPriceCents'];
  // Ganzzahlig wie Number.isInteger: 2500.0 aus einem Zwischenspeicher zaehlt.
  final preisOk = preis is num && preis.isFinite && preis == preis.roundToDouble() && preis >= 1;
  if (article['askPrice'] != true && !preisOk) return 'price_required';
  return null;
}

/// Warum die Kachel eines fremden Gutscheins gesperrt ist
/// (`not_enabled`, `type_not_enabled`; Saetze in `externalVoucherTileMessages`).
const List<String> externalVoucherTileBlocks = ['not_enabled', 'type_not_enabled'];

/// Darf die Kachel verkaufen? `null` = ja (auch fuer jeden Artikel ohne
/// [PosArticle.externalVoucher]), sonst ein Wert aus [externalVoucherTileBlocks].
/// Gesperrt bei Freigabe [PosExternalVouchers.off] (oder ohne Angabe, etwa
/// solange die Einstellungen nicht geladen sind) und bei Einzweck ohne
/// [PosExternalVouchers.all] -- dieselbe Regel, mit der der Server den Beleg
/// abweist (`external_voucher_not_enabled`, `external_voucher_type_not_enabled`).
String? externalVoucherTileBlock(PosArticle article, PosExternalVouchers? externalVouchers) {
  final art = article.externalVoucher;
  if (art == null) return null;
  if (externalVouchers == null || externalVouchers == PosExternalVouchers.off) return 'not_enabled';
  if (art == ArticleExternalVoucher.singlePurpose && externalVouchers != PosExternalVouchers.all) return 'type_not_enabled';
  return null;
}
