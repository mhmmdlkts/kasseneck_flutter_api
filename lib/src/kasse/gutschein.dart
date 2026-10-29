/// Gutscheine der neuen Form an der Kasse: pruefen (`checkVoucher`), Etikett
/// nachdrucken (`reprintVoucherLabel`), die Gutschein-Einstellung der Kasse
/// (Block `vouchers` aus `getKasseSettings`, seit 11.8.0 mit den
/// Gutschein-Sorten) und die Gutschein-Rechte. Zwilling von `pos/gutschein.ts`
/// im npm-Paket, gleiche Namen.
///
/// Der Klartext-Code lebt nur im Speicher des Aufrufs: er wird weder
/// protokolliert noch in einer Fehlermeldung genannt. Die Kasse bekommt nach
/// dem Pruefen nur die letzten vier Zeichen ([VoucherCheck.codeSuffix]).
library;

import 'package:kreiseck_validator/kreiseck_validator.dart' show Valid, VoucherCode;

import '../../enums/voucher_type.dart';
import '../../models/keck_voucher.dart';
import '../aufrufe.dart';
import '../receipt/due.dart' show VoucherDueType;
import '../register/fehler.dart';
import '../register/transport.dart';

/// Stand eines Gutscheins nach dem Code-Eingeben.
enum VoucherStatus {
  active('active'),
  usedUp('used_up'),
  expired('expired'),
  paidOut('paid_out'),
  cancelled('cancelled'),
  blocked('blocked');

  const VoucherStatus(this.wire);

  /// Der Wert am Draht (`/v3`).
  final String wire;

  /// Der Stand zum Drahtwert; `null` fuer einen unbekannten Wert.
  static VoucherStatus? fromWire(Object? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Die Arten, die `checkVoucher` liefert (Drahtwerte, wie `voucherKinds` im
/// Vertrag `surface.json`).
final List<String> voucherKinds = List.unmodifiable([
  for (final t in VoucherType.values)
    if (t.isNewForm) t.wire,
]);

/// Die Staende, die `checkVoucher` liefert (Drahtwerte, wie
/// `voucherStatuses` im Vertrag).
final List<String> voucherStatuses = List.unmodifiable([for (final s in VoucherStatus.values) s.wire]);

/// Die Gueltigkeitsmuster (`unlimited`, `1+3` = ein Jahr einloesbar, drei
/// rueckzahlbar, `custom`).
///
/// Nur die Muster, die der Server an Gutscheinen nach aussen gibt: eine Sorte
/// mit „N Jahre“ geht fuer jedes N als `1+3` mit den Daten und
/// [VoucherValidity.redeemableYears] = N hinaus (Nachtrag E1), damit Kassen
/// bis 11.7 beim Einloesen nicht an einem neuen Muster scheitern und
/// „einloesbar bis“ mit dem Datum drucken. Das Muster der Sorte selbst steht in
/// [voucherTypeValidityPatterns].
const List<String> voucherValidityPatterns = ['unlimited', '1+3', 'custom'];

/// Gueltigkeit eines Gutscheins; Daten als `YYYY-MM-DD` (Wiener Tag). Was der
/// Server nicht nennt, ist `null`.
class VoucherValidity {
  const VoucherValidity({required this.pattern, this.redeemableYears, this.redeemableUntil, this.refundableUntil, this.validUntil});

  /// Ein Wert aus [voucherValidityPatterns].
  final String pattern;

  /// Gutschein einer Sorte „N Jahre einloesbar, danach 3 Jahre Rueckzahlung“:
  /// die Zahl N (ab 1); [pattern] ist dann `1+3` fuer jedes N. Fehlt bei
  /// Gutscheinen ohne Sorte und bei unbefristeten; die Daten stehen trotzdem
  /// in [redeemableUntil] (+N) und [refundableUntil] (+N+3) und gelten.
  final int? redeemableYears;
  final String? redeemableUntil;
  final String? refundableUntil;
  final String? validUntil;

  @override
  bool operator ==(Object other) =>
      other is VoucherValidity &&
      other.pattern == pattern &&
      other.redeemableYears == redeemableYears &&
      other.redeemableUntil == redeemableUntil &&
      other.refundableUntil == refundableUntil &&
      other.validUntil == validUntil;

  @override
  int get hashCode => Object.hash(pattern, redeemableYears, redeemableUntil, refundableUntil, validUntil);
}

// ---------------------------------------------------------------- Sorten

/// Auszahlung eines Gutscheins bzw. einer Sorte: erlaubt oder nie (nur bei
/// unbefristeter Gueltigkeit). Bei [never] lehnt der Server jede Auszahlung
/// ab (`voucher_payout_not_allowed`); Einloesen geht unveraendert.
enum VoucherPayout {
  allowed('allowed'),
  never('never');

  const VoucherPayout(this.wire);

  /// Der Wert am Draht (`/v3`).
  final String wire;

  /// Die Auszahlung zum Drahtwert; `null` fuer einen unbekannten Wert.
  static VoucherPayout? fromWire(Object? wire) {
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

/// Betrag einer Gutschein-Sorte: frei an der Kasse eingegeben oder fest.
enum VoucherAmountMode {
  free('free'),
  fixed('fixed');

  const VoucherAmountMode(this.wire);

  /// Der Wert am Draht (`/v3`).
  final String wire;

  /// Der Modus zum Drahtwert; `null` fuer einen unbekannten Wert.
  static VoucherAmountMode? fromWire(Object? wire) {
    for (final m in values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
}

/// Gueltigkeit einer Gutschein-Sorte: unbefristet oder N Jahre (das Muster der
/// Sorte, nicht das eines Gutscheins, siehe [voucherValidityPatterns]).
enum VoucherTypeValidityPattern {
  unlimited('unlimited'),
  years('years');

  const VoucherTypeValidityPattern(this.wire);

  /// Der Wert am Draht (`/v3`).
  final String wire;

  /// Das Muster zum Drahtwert; `null` fuer einen unbekannten Wert.
  static VoucherTypeValidityPattern? fromWire(Object? wire) {
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

/// Die Arten einer Gutschein-Sorte (Drahtwerte, wie `voucherTypeKinds` im
/// Vertrag): nur Wertgutscheine, Leistung und Aktion sind keine Sorte.
final List<String> voucherTypeKinds = List.unmodifiable([VoucherType.multiPurpose.wire, VoucherType.singlePurpose.wire]);

/// Die Betragsarten einer Sorte (Drahtwerte, wie `voucherAmountModes` im Vertrag).
final List<String> voucherAmountModes = List.unmodifiable([for (final m in VoucherAmountMode.values) m.wire]);

/// Die Gueltigkeitsmuster einer Sorte (Drahtwerte, wie
/// `voucherTypeValidityPatterns` im Vertrag).
final List<String> voucherTypeValidityPatterns = List.unmodifiable([for (final p in VoucherTypeValidityPattern.values) p.wire]);

/// Die Auszahlungswerte (Drahtwerte, wie `voucherPayouts` im Vertrag).
final List<String> voucherPayouts = List.unmodifiable([for (final p in VoucherPayout.values) p.wire]);

/// Betrag einer Gutschein-Sorte: frei (Zahlenfeld an der Kasse) oder fest
/// (sofort in den Korb), Cent ganzzahlig.
class VoucherTypeAmount {
  /// Frei an der Kasse eingegeben.
  const VoucherTypeAmount.free()
      : mode = VoucherAmountMode.free,
        cents = null;

  /// Fester Betrag in Cent; ein Verkauf traegt genau ihn.
  const VoucherTypeAmount.fixed(int this.cents) : mode = VoucherAmountMode.fixed;

  final VoucherAmountMode mode;

  /// Der feste Betrag in Cent; `null` bei [VoucherAmountMode.free].
  final int? cents;

  Map<String, dynamic> toJson() => {'mode': mode.wire, 'cents': ?cents};

  @override
  bool operator ==(Object other) => other is VoucherTypeAmount && other.mode == mode && other.cents == cents;

  @override
  int get hashCode => Object.hash(mode, cents);
}

/// Gueltigkeit einer Gutschein-Sorte: unbefristet oder N Jahre einloesbar,
/// danach 3 Jahre Rueckzahlung.
class VoucherTypeValidity {
  /// Unbefristet.
  const VoucherTypeValidity.unlimited()
      : pattern = VoucherTypeValidityPattern.unlimited,
        years = null;

  /// N Jahre einloesbar (1 bis 30), danach 3 Jahre Rueckzahlung.
  const VoucherTypeValidity.years(int this.years) : pattern = VoucherTypeValidityPattern.years;

  final VoucherTypeValidityPattern pattern;

  /// Die Zahl N; `null` bei [VoucherTypeValidityPattern.unlimited].
  final int? years;

  Map<String, dynamic> toJson() => {'pattern': pattern.wire, 'years': ?years};

  @override
  bool operator ==(Object other) => other is VoucherTypeValidity && other.pattern == pattern && other.years == years;

  @override
  int get hashCode => Object.hash(pattern, years);
}

/// Etikett-Vorlage in der `/v3`-Form (Groesse, Layout, Drehung, Felder,
/// Freitext). Das Paket zeichnet keine Etiketten: es reicht die Vorlage als
/// Kopie durch, gezeichnet wird in der Kasse. Weitere Schluessel eines
/// neueren Servers bleiben erhalten ([toJson]).
class VoucherLabelTemplate {
  VoucherLabelTemplate._(this._json);

  /// Kopie der Vorlage, wenn sie Groesse und Layout als Text traegt; sonst
  /// `null`. Eine unbrauchbare Vorlage schliesst nie etwas: die Kasse druckt
  /// dann ihren Standard (ein Verkauf scheitert nie an der Vorlage).
  static VoucherLabelTemplate? fromJson(Object? json) {
    if (json is! Map || json['size'] is! String || json['layout'] is! String) return null;
    return VoucherLabelTemplate._(_tiefKopie(json) as Map<String, dynamic>);
  }

  /// Unveraenderliche Kopie der gelesenen Vorlage.
  final Map<String, dynamic> _json;

  /// Etikettgroesse `BxH` in mm, z. B. `40x30`.
  String get size => _json['size'] as String;
  String get layout => _json['layout'] as String;

  /// Drehung in Grad (0 oder 90); fehlt sie, 0.
  int get rotation {
    final r = _json['rotation'];
    return r is num ? r.toInt() : 0;
  }

  /// Die Felder (`logo`, `qr`, `business`, `value`, `validity`, `checkPage`,
  /// `designation` …) mit ihrem Schalter; Eintraege ohne Wahrheitswert fehlen.
  Map<String, bool> get fields {
    final f = _json['fields'];
    return Map.unmodifiable({
      if (f is Map)
        for (final e in f.entries)
          if (e.value is bool) '${e.key}': e.value as bool,
    });
  }

  /// Freitextzeilen; Eintraege ohne Text fehlen.
  List<String> get freeText {
    final t = _json['freeText'];
    return List.unmodifiable([
      if (t is List)
        for (final z in t)
          if (z is String) z,
    ]);
  }

  /// Die Vorlage, wie sie gelesen wurde (eine veraenderbare Kopie).
  Map<String, dynamic> toJson() => _veraenderbar(_json) as Map<String, dynamic>;

  @override
  bool operator ==(Object other) => other is VoucherLabelTemplate && _tiefGleich(other._json, _json);

  @override
  int get hashCode => _tiefHash(_json);
}

/// Gutschein-Sorte (Gutscheine Stufe 4b): eine Kachel im Reiter „Gutscheine“.
/// Die Kasse bekommt nur verkaufbare Sorten (aktiv und gueltig), in
/// Kachelfolge. Verkauft wird ein Wertgutschein nur ueber eine Sorte:
/// `KeckVoucher(action: sell, type: kind, typeId: id, amountCents: …)` (bei
/// [VoucherAmountMode.fixed] genau `amount.cents`); Art, Satz, Gueltigkeit und
/// Auszahlung nimmt der Server aus der Sorte und friert sie am Gutschein ein.
///
/// Eine Sorte ist zugleich eine [VoucherDueType]: die Sorten der Einstellung
/// gehen unveraendert an den Zahlbetrag (`voucherTypes`).
class PosVoucherType extends VoucherDueType {
  const PosVoucherType({
    required super.id,
    required this.name,
    required super.kind,
    super.vatRateBp,
    required super.amount,
    required this.validity,
    required this.payout,
    this.label,
    this.order = 0,
    this.active = true,
    this.soldCount = 0,
  });

  final String name;

  /// Unbefristet oder N Jahre einloesbar, danach 3 Jahre Rueckzahlung.
  final VoucherTypeValidity validity;
  final VoucherPayout payout;

  /// Wirksame Vorlage der Sorte (eigene, sonst die Standardvorlage); `null`,
  /// wenn die Antwort keine brauchbare traegt.
  final VoucherLabelTemplate? label;

  /// Kachelfolge.
  final int order;
  final bool active;

  /// Verkaufte Gutscheine dieser Sorte (nur zur Anzeige).
  final int soldCount;

  /// Eine Sorte aus `vouchers.types[]`, oder `null`, wenn sie nicht so ist,
  /// wie der Server eine verkaufbare Sorte liefert (dann bietet die Kasse sie
  /// nicht an): Kennung, Name, Art mit passendem Satz, Betrag, Gueltigkeit,
  /// Auszahlung (`never` nur unbefristet) und aktiv. Fehlende Reihenfolge oder
  /// Verkaufszahl gelten als 0; eine unbrauchbare Vorlage wird `null`.
  static PosVoucherType? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final art = VoucherType.fromWire(json['kind']);
    final satz = json['vatRateBp'];
    final betragRoh = json['amount'];
    final gueltigRoh = json['validity'];
    final auszahlung = VoucherPayout.fromWire(json['payout']);
    final reihenfolge = json['order'] ?? 0;
    final verkauft = json['soldCount'] ?? 0;
    if (id is! String || !_sorteId.hasMatch(id)) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (art != VoucherType.multiPurpose && art != VoucherType.singlePurpose) return null;
    if (art == VoucherType.singlePurpose ? !_ganzeZahl(satz, 1) : satz != null) return null;
    if (betragRoh is! Map || gueltigRoh is! Map) return null;
    final VoucherTypeAmount betrag;
    final modus = VoucherAmountMode.fromWire(betragRoh['mode']);
    final cents = betragRoh['cents'];
    if (modus == VoucherAmountMode.free) {
      betrag = const VoucherTypeAmount.free();
    } else if (modus == VoucherAmountMode.fixed && cents is int && cents >= _minFixCents && cents <= _maxBetragCents) {
      betrag = VoucherTypeAmount.fixed(cents);
    } else {
      return null;
    }
    final VoucherTypeValidity gueltig;
    final muster = VoucherTypeValidityPattern.fromWire(gueltigRoh['pattern']);
    final jahre = gueltigRoh['years'];
    if (muster == VoucherTypeValidityPattern.unlimited) {
      gueltig = const VoucherTypeValidity.unlimited();
    } else if (muster == VoucherTypeValidityPattern.years && jahre is int && jahre >= 1 && jahre <= _maxJahre) {
      gueltig = VoucherTypeValidity.years(jahre);
    } else {
      return null;
    }
    if (auszahlung == null) return null;
    if (auszahlung == VoucherPayout.never && gueltig.pattern != VoucherTypeValidityPattern.unlimited) return null;
    if (reihenfolge is! int || !_ganzeZahl(verkauft, 0)) return null;
    if (json['active'] != true) return null;
    return PosVoucherType(
      id: id,
      name: name,
      kind: art!,
      vatRateBp: satz as int?,
      amount: betrag,
      validity: gueltig,
      payout: auszahlung,
      label: VoucherLabelTemplate.fromJson(json['label']),
      order: reihenfolge,
      soldCount: verkauft as int,
    );
  }

  /// Die `/v3`-Form, aus der [fromJson] dieselbe Sorte liest (Zwischenspeicher).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.wire,
        'vatRateBp': vatRateBp,
        'amount': amount.toJson(),
        'validity': validity.toJson(),
        'payout': payout.wire,
        'label': label?.toJson(),
        'order': order,
        'active': active,
        'soldCount': soldCount,
      };

  @override
  bool operator ==(Object other) =>
      other is PosVoucherType &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.vatRateBp == vatRateBp &&
      other.amount == amount &&
      other.validity == validity &&
      other.payout == payout &&
      other.label == label &&
      other.order == order &&
      other.active == active &&
      other.soldCount == soldCount;

  @override
  int get hashCode => Object.hash(id, name, kind, vatRateBp, amount, validity, payout, label, order, active, soldCount);
}

/// Kennung wie am Server (gutschein-core.ID_MUSTER): reservierte `__…__` gibt es nie als Sorte.
final RegExp _sorteId = RegExp(r'^(?!__.*__$)[A-Za-z0-9_-]{1,128}$');

/// Grenzen des Servers (gutschein-core.pruefeSorte): Fixbetrag 1,00 bis 10.000,00 €, Gueltigkeit 1 bis 30 Jahre.
const int _minFixCents = 100;
const int _maxBetragCents = 1000000;
const int _maxJahre = 30;

bool _ganzeZahl(Object? w, int min) => w is int && w >= min;

/// Unveraenderliche Kopie eines JSON-Werts (Schluessel als Text).
Object? _tiefKopie(Object? w) {
  if (w is Map) return Map<String, dynamic>.unmodifiable({for (final e in w.entries) '${e.key}': _tiefKopie(e.value)});
  if (w is List) return List<dynamic>.unmodifiable([for (final x in w) _tiefKopie(x)]);
  return w;
}

/// Veraenderbare Kopie eines JSON-Werts (fuer `toJson`).
Object? _veraenderbar(Object? w) {
  if (w is Map) return <String, dynamic>{for (final e in w.entries) '${e.key}': _veraenderbar(e.value)};
  if (w is List) return <dynamic>[for (final x in w) _veraenderbar(x)];
  return w;
}

bool _tiefGleich(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && _tiefGleich(e.value, b[e.key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_tiefGleich(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Passend zu [_tiefGleich]: die Reihenfolge der Schluessel zaehlt nicht.
int _tiefHash(Object? w) {
  if (w is Map) return Object.hashAllUnordered([for (final e in w.entries) Object.hash(e.key, _tiefHash(e.value))]);
  if (w is List) return Object.hashAll([for (final x in w) _tiefHash(x)]);
  return w.hashCode;
}

bool _listeGleich(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Stand eines Gutscheins nach dem Code-Eingeben (`checkVoucher`). Felder,
/// die zur Art nicht passen oder die der Server nicht sendet, sind `null`.
class VoucherCheck {
  const VoucherCheck({
    required this.type,
    required this.status,
    required this.codeSuffix,
    this.balanceCents,
    this.faceValueCents,
    this.quantity,
    this.remainingQuantity,
    this.vatRateBp,
    this.article,
    this.discountCents,
    this.discountPercentBp,
    this.validity,
    this.exempt,
    this.typeName,
    this.payout,
  });

  /// Eine der vier Arten der neuen Form ([VoucherType.isNewForm]).
  final VoucherType type;
  final VoucherStatus status;

  /// Die letzten vier Zeichen des Codes, fuer Anzeige und Beleg.
  final String codeSuffix;
  final int? balanceCents;
  final int? faceValueCents;
  final int? quantity;
  final int? remainingQuantity;

  /// Steuersatz in Basispunkten (Einzweck, Leistung).
  final int? vatRateBp;
  final VoucherArticle? article;
  final int? discountCents;
  final int? discountPercentBp;
  final VoucherValidity? validity;

  /// Befreit verkauft (Kleinunternehmer beim Verkauf, Satz 0): eine
  /// Einloesung verteilt sich anteilig auf alle Saetze des Korbs, auch in
  /// einem inzwischen steuerpflichtigen Konto. Fehlt bei aelteren Servern.
  final bool? exempt;

  /// Name der Sorte, mit der der Gutschein verkauft wurde (beim Verkauf
  /// eingefroren); `null` ohne Sorte.
  final String? typeName;

  /// Auszahlung dieses Gutscheins (beim Verkauf eingefroren); `null` ohne
  /// Sorte. Bei [VoucherPayout.never] lehnt der Server jede Auszahlung ab
  /// (`voucher_payout_not_allowed`); Einloesen geht unveraendert.
  final VoucherPayout? payout;
}

/// Gutschein-Einstellung der Kasse (Block `vouchers` aus `getKasseSettings`).
///
/// Seit Gutscheine Stufe 4b (11.8.0) verkauft eine Kasse ueber Sorten: Reiter
/// und Kacheln zeigt sie mit [typeSale] (und dem Recht `voucherSell`), je
/// Sorte aus [types] und die feste Kachel „Leistungsgutschein“ mit
/// [serviceArticles]. [sale], [valueVoucherType] und [vatRateBp] gelten nur
/// Kassen vor 11.8; der Server schickt `sale` immer als `false`.
class PosVoucherSettings {
  const PosVoucherSettings({
    required this.sale,
    required this.valueVoucherType,
    required this.vatRateBp,
    this.typeSale = false,
    this.types = const [],
    this.serviceArticles = false,
    this.labelDefault,
  });

  /// Ohne Block (alter Server, Konto ohne Schalter) oder bei einem unstimmigen
  /// Block: Verkaufen ist aus.
  static const off = PosVoucherSettings(sale: false, valueVoucherType: null, vatRateBp: null);

  /// Gutscheine verkaufen ist eingeschaltet (Kassen vor 11.8).
  final bool sale;

  /// Die bestaetigte Art des Wertgutscheins: [VoucherType.multiPurpose],
  /// [VoucherType.singlePurpose] oder `null` (Kassen vor 11.8).
  final VoucherType? valueVoucherType;

  /// Satz des Einzweckgutscheins in Basispunkten; bei Mehrzweck `null`
  /// (Kassen vor 11.8).
  final int? vatRateBp;

  /// Gutscheine verkaufen (Reiter „Gutscheine“): Schalter des Servers und
  /// mindestens eine Sorte oder ein Leistungsartikel.
  final bool typeSale;

  /// Verkaufbare Sorten in Kachelfolge.
  final List<PosVoucherType> types;

  /// Es gibt aktive Artikel, die als Leistungsgutschein freigegeben sind
  /// (`PosArticle.serviceVoucher`).
  final bool serviceArticles;

  /// Standardvorlage des Etiketts (Leistungsgutschein, Notausgang); `null`
  /// ohne brauchbare Vorlage.
  final VoucherLabelTemplate? labelDefault;

  /// Block `vouchers`, geschlossen im Zweifel: ist irgendein Feld unstimmig,
  /// gilt der ganze Block als nicht gelesen und Verkaufen bleibt aus (kein
  /// Wurf, sonst ginge das Laden aller Einstellungen verloren). Stimmig
  /// heisst: `sale` ein Wahrheitswert, die Art `multi_purpose`,
  /// `single_purpose` oder `null`, der Satz eine ganze Zahl >= 0 oder `null`;
  /// Mehrzweck traegt keinen Satz, Einzweck braucht einen, und ein
  /// eingeschalteter Verkauf braucht eine Art. Ein ausgeschalteter Verkauf
  /// darf eine Art behalten. `typeSale` und `serviceArticles` sind
  /// Wahrheitswerte, `types` eine Liste (fehlen sie, antwortet ein aelterer
  /// Server: aus, leer).
  ///
  /// Sorten liest der Leser einzeln: eine unstimmige Sorte faellt weg
  /// ([PosVoucherType.fromJson]), die anderen bleiben, bei doppelter Kennung
  /// gilt die erste; ist danach weder eine Sorte noch ein Leistungsartikel da,
  /// ist `typeSale` aus (kein leerer Reiter). Eine unbrauchbare
  /// Etikett-Vorlage schliesst nichts: sie wird `null`. Das alte Feld `label`
  /// (Kassen vor 11.8) liest das Paket nicht.
  static PosVoucherSettings fromJson(Object? block) {
    if (block is! Map) return off;
    final sale = block['sale'];
    final artRoh = block['valueVoucherType'];
    final satz = block['vatRateBp'];
    if (sale is! bool) return off;
    if (artRoh != null && artRoh != 'multi_purpose' && artRoh != 'single_purpose') return off;
    final art = VoucherType.fromWire(artRoh);
    if (satz != null && !(satz is int && satz >= 0)) return off;
    if (sale && art == null) return off;
    if (art == VoucherType.singlePurpose && satz == null) return off;
    if (art == VoucherType.multiPurpose && satz != null) return off;
    final sortenVerkauf = block['typeSale'] ?? false;
    final rohSorten = block['types'] ?? const <Object?>[];
    final leistung = block['serviceArticles'] ?? false;
    if (sortenVerkauf is! bool || leistung is! bool || rohSorten is! List) return off;
    final types = <PosVoucherType>[];
    final gesehen = <String>{};
    for (final roh in rohSorten) {
      final t = PosVoucherType.fromJson(roh);
      if (t == null || !gesehen.add(t.id)) continue;
      types.add(t);
    }
    return PosVoucherSettings(
      sale: sale,
      valueVoucherType: art,
      vatRateBp: satz as int?,
      typeSale: sortenVerkauf && (types.isNotEmpty || leistung),
      types: List.unmodifiable(types),
      serviceArticles: leistung,
      labelDefault: VoucherLabelTemplate.fromJson(block['labelDefault']),
    );
  }

  Map<String, dynamic> toJson() => {
        'sale': sale,
        'valueVoucherType': valueVoucherType?.wire,
        'vatRateBp': vatRateBp,
        'typeSale': typeSale,
        'types': [for (final t in types) t.toJson()],
        'serviceArticles': serviceArticles,
        'labelDefault': labelDefault?.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is PosVoucherSettings &&
      other.sale == sale &&
      other.valueVoucherType == valueVoucherType &&
      other.vatRateBp == vatRateBp &&
      other.typeSale == typeSale &&
      _listeGleich(other.types, types) &&
      other.serviceArticles == serviceArticles &&
      other.labelDefault == labelDefault;

  @override
  int get hashCode =>
      Object.hash(sale, valueVoucherType, vatRateBp, typeSale, Object.hashAll(types), serviceArticles, labelDefault);
}

// ---------------------------------------------------------------- Aufrufe

/// Gutschein am Code pruefen (Gutschein-Recht `voucherRedeem`). Der Code wird
/// tolerant eingelesen (Gross/klein, Bindestriche, Leerzeichen, `O`/`0`,
/// `I`/`L`/`1`) und vor dem Senden auf sein Pruefzeichen geprueft: ein
/// Tippfehler geht nie ueber das Netz, sondern endet mit
/// [KasseneckValidationError]. Fachliche Fehler kommen als
/// [KasseneckApiError] mit dem Code des Servers (`voucher_not_found`,
/// `too_many_voucher_checks`, `not_permitted` …). Gesendet wird die
/// Normalform; kein Text dieses Aufrufs nennt den Code.
Future<VoucherCheck> checkVoucher(RegisterTransport transport, String code) async {
  const name = Aufrufe.checkVoucher;
  final geprueft = VoucherCode.validate(code);
  // Der Code steht bewusst nicht in der Meldung.
  if (geprueft is! Valid) throw const KasseneckValidationError(name, 'code ist kein gueltiger Gutscheincode', 'request');
  final normal = geprueft.normalized;
  final geheim = [normal, VoucherCode.format(normal)];
  final Map<String, dynamic> daten;
  try {
    daten = await transport.call(name, params: {'code': normal});
  } on KasseneckApiError catch (fehler) {
    // Ein Servertext, der den Code wiederholt, wird geschwaerzt; Code und
    // Daten bleiben, damit die Kasse am Code entscheidet.
    if (!geheim.any(fehler.message.contains)) rethrow;
    final text = geheim.fold(fehler.message, (t, g) => t.split(g).join('****'));
    throw KasseneckApiError(fehler.functionName, text, code: fehler.code, details: fehler.details);
  }
  return _pruefungLesen(name, daten);
}

/// Etikett eines Gutscheins noch einmal drucken (Gutschein-Recht
/// `voucherManage`). Liefert den Klartext-Code zum Drucken; er gehoert nur in
/// den Speicher bis zum Druck. Aufrufer duerfen ihn nicht protokollieren,
/// speichern oder in Meldungen nennen; Lesefehler dieser Antwort nennen ihn
/// nie.
Future<String> reprintVoucherLabel(RegisterTransport transport, String id) async {
  const name = Aufrufe.reprintVoucherLabel;
  if (id.trim().isEmpty) throw const KasseneckValidationError(name, 'id fehlt', 'request');
  final daten = await transport.call(name, params: {'id': id});
  final code = daten['code'];
  if (code is! String || code.isEmpty) throw const KasseneckValidationError(name, 'Antwort: data.code fehlt', 'response');
  return code;
}

// ---------------------------------------------------------------- Leser

KasseneckValidationError _lesefehler(String name, String grund) => KasseneckValidationError(name, 'Antwort: $grund', 'response');

bool _fehlt(Object? w) => w == null;

int? _ganzWennDa(String name, String pfad, Map<dynamic, dynamic> o, String feld) {
  final w = o[feld];
  if (_fehlt(w)) return null;
  if (w is! int) throw _lesefehler(name, '$pfad.$feld ist keine ganze Zahl');
  return w;
}

String _textPflicht(String name, String pfad, Map<dynamic, dynamic> o, String feld) {
  final w = o[feld];
  if (w is! String || w.isEmpty) throw _lesefehler(name, '$pfad.$feld fehlt');
  return w;
}

VoucherValidity _gueltigkeit(String name, Object? w) {
  if (w is! Map) throw _lesefehler(name, 'validity ist kein Objekt');
  final muster = w['pattern'];
  if (muster is! String || !voucherValidityPatterns.contains(muster)) throw _lesefehler(name, 'validity.pattern ist unbekannt');
  String? datum(String feld) {
    final t = w[feld];
    if (_fehlt(t)) return null;
    if (t is! String || t.isEmpty) throw _lesefehler(name, 'validity.$feld ist kein Datum');
    return t;
  }

  final jahre = w['redeemableYears'];
  if (!_fehlt(jahre) && (jahre is! int || jahre < 1)) throw _lesefehler(name, 'validity.redeemableYears ist keine Zahl von Jahren');

  return VoucherValidity(
    pattern: muster,
    redeemableYears: jahre as int?,
    redeemableUntil: datum('redeemableUntil'),
    refundableUntil: datum('refundableUntil'),
    validUntil: datum('validUntil'),
  );
}

VoucherArticle _artikel(String name, Object? w) {
  if (w is! Map) throw _lesefehler(name, 'article ist kein Objekt');
  final id = _textPflicht(name, 'article', w, 'id');
  final bezeichnung = _textPflicht(name, 'article', w, 'name');
  final satz = w['vatRateBp'];
  final preis = w['priceCents'];
  if (satz is! int) throw _lesefehler(name, 'article.vatRateBp ist keine ganze Zahl');
  if (preis is! int) throw _lesefehler(name, 'article.priceCents ist keine ganze Zahl');
  return VoucherArticle(id: id, name: bezeichnung, vatRateBp: satz, priceCents: preis);
}

/// Streng: eine unbekannte Art, ein unbekannter Stand oder eine Zahl, die
/// keine ganze ist, ist ein Lesefehler, nie still ein falscher Wert.
VoucherCheck _pruefungLesen(String name, Map<String, dynamic> o) {
  final art = VoucherType.fromWire(o['type']);
  if (art == null || !art.isNewForm) throw _lesefehler(name, 'data.type ist unbekannt');
  final stand = VoucherStatus.fromWire(o['status']);
  if (stand == null) throw _lesefehler(name, 'data.status ist unbekannt');
  final befreit = o['exempt'];
  if (!_fehlt(befreit) && befreit is! bool) throw _lesefehler(name, 'data.exempt ist kein Wahrheitswert');
  final sortenName = o['typeName'];
  if (!_fehlt(sortenName) && (sortenName is! String || sortenName.isEmpty)) throw _lesefehler(name, 'data.typeName ist kein Text');
  // Geschlossen im Zweifel, ohne Wurf: ein unbekannter Wert (neuerer Server)
  // gilt als `never`. Einloesen haengt nicht daran und darf nicht an einem
  // neuen Wert scheitern (die Lehre aus dem Gueltigkeitsmuster, Nachtrag E1).
  final auszahlung = _fehlt(o['payout']) ? null : (o['payout'] == VoucherPayout.allowed.wire ? VoucherPayout.allowed : VoucherPayout.never);
  return VoucherCheck(
    type: art,
    status: stand,
    codeSuffix: _textPflicht(name, 'data', o, 'codeSuffix'),
    balanceCents: _ganzWennDa(name, 'data', o, 'balanceCents'),
    faceValueCents: _ganzWennDa(name, 'data', o, 'faceValueCents'),
    quantity: _ganzWennDa(name, 'data', o, 'quantity'),
    remainingQuantity: _ganzWennDa(name, 'data', o, 'remainingQuantity'),
    vatRateBp: _ganzWennDa(name, 'data', o, 'vatRateBp'),
    discountCents: _ganzWennDa(name, 'data', o, 'discountCents'),
    discountPercentBp: _ganzWennDa(name, 'data', o, 'discountPercentBp'),
    article: _fehlt(o['article']) ? null : _artikel(name, o['article']),
    validity: _fehlt(o['validity']) ? null : _gueltigkeit(name, o['validity']),
    exempt: befreit as bool?,
    typeName: sortenName as String?,
    payout: auszahlung,
  );
}
