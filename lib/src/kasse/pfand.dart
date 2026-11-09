/// Pfand & Leergut an der Kasse: Pfandarten und Einstellungen aus
/// `getKasseSettings` (Block `deposit`), Pfandliste am Artikel und an der
/// Gruppe (`deposits`), die Pfand-Angaben des Kassenobjekts aus
/// `listRegisterUsersForDevice`, die Vorschau-Rechnung (dieselben Pfand- und
/// Leergutzeilen wie der Server) und die Zuordnung eines Leergut-Scans.
///
/// Zwilling von `pos/pfand.ts` und `pos/leergut.ts` im JS-Paket. Vertrag sind
/// die Pruefaelle `test/fixtures/vertrag/deposit-cases.json` (Vorschau) und
/// `return-code-cases.json` (Scan).
library;

import 'package:kreiseck_validator/kreiseck_validator.dart' show Gtin;

import '../../enums/vat_rate.dart';
import '../../models/kasseneck_item.dart';
import '../../services/vienna_time.dart';
import '../register/fehler.dart' show KasseneckValidationError;
import 'artikel.dart';

/// Art einer Pfandart: Einweg oder Mehrweg.
const List<String> depositKinds = ['single_use', 'reusable'];

/// Gebindetyp einer Pfandart (frei, nur zur Anzeige).
const List<String> depositContainerTypes = ['bottle', 'crate', 'keg', 'cup', 'glass', 'other'];

/// Wer nimmt Leergut an der Kasse zurueck: diese Kasse, eine gemeinsame Stelle
/// oder niemand.
const List<String> depositReturnModes = ['here', 'shared', 'none'];

/// Vorbelegung, ob Getraenke vor Ort getrunken oder mitgenommen werden.
const List<String> depositOnPremisesDefaults = ['on_premises', 'takeaway', 'ask'];

/// EWP-GTIN der Einweg-Pfandzeile (gesetzlich festgelegt).
const String _ewpGtin = '9010945000011';

bool _istGanz(Object? w, int min) => w is num && w.isFinite && w == w.truncate() && w >= min;

int _ganz(num w) => w.toInt();

String? _aus(List<String> liste, Object? value) => value is String && liste.contains(value) ? value : null;

/// Ein Pfandbetrag ab einem Tag (`from`, Wiener Tag `YYYY-MM-DD`), in Cent je
/// Stueck.
class DepositAmount {
  const DepositAmount({required this.from, required this.cents});

  final String from;
  final int cents;

  /// `null`, wenn der Eintrag nicht lesbar ist.
  static DepositAmount? fromJson(Object? value) {
    if (value is! Map || value['from'] is! String || !_istGanz(value['cents'], 0)) return null;
    return DepositAmount(from: value['from'] as String, cents: _ganz(value['cents'] as num));
  }

  Map<String, dynamic> toJson() => {'from': from, 'cents': cents};
}

/// Eine Pfandart des Betriebs.
class DepositType {
  /// Die Felder der Antwort `/v3`, die dieses Modell liest.
  static const Set<String> fields = {'id', 'kind', 'name', 'type', 'amounts', 'returnRate', 'used', 'active'};

  const DepositType({
    required this.id,
    required this.kind,
    required this.name,
    this.type,
    this.amounts = const [],
    this.returnRate,
    this.used = false,
    this.active = true,
  });

  final String id;

  /// Ein Wert aus [depositKinds].
  final String kind;
  final String name;

  /// Ein Wert aus [depositContainerTypes] oder `null`.
  final String? type;

  /// Betraege nach Gueltigkeit, wie vom Server geliefert (aufsteigend nach `from`).
  final List<DepositAmount> amounts;

  /// Steuersatz in Prozent, mit dem Mehrweg-Leergut zurueckgenommen wird
  /// (Rueckgabesatz), oder `null` (noch nie ausgegeben; dann scheitert
  /// Mehrweg-Leergut mit `invalid_deposit`).
  final num? returnRate;

  /// Die Pfandart steht an mindestens einem Artikel oder Beleg.
  final bool used;
  final bool active;

  /// `null`, wenn die Pfandart nicht lesbar ist (keine Kennung, unbekannte Art).
  static DepositType? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || (value['id'] as String).isEmpty) return null;
    final kind = _aus(depositKinds, value['kind']);
    if (kind == null) return null;
    final rate = value['returnRate'];
    final betraege = value['amounts'];
    return DepositType(
      id: value['id'] as String,
      kind: kind,
      name: value['name'] is String ? value['name'] as String : '',
      type: _aus(depositContainerTypes, value['type']),
      amounts: betraege is List ? [for (final b in betraege) ?DepositAmount.fromJson(b)] : const [],
      returnRate: rate is num && rate.isFinite ? rate : null,
      used: value['used'] == true,
      active: value['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'type': type,
        'amounts': [for (final b in amounts) b.toJson()],
        'returnRate': returnRate,
        'used': used,
        'active': active,
      };
}

/// Block `deposit` aus `getKasseSettings`; fehlt bei ausgeschaltetem Pfand.
class DepositSettings {
  static const Set<String> fields = {'singleUse', 'reusable', 'depositTypes'};

  const DepositSettings({this.singleUse = false, this.reusable = false, this.depositTypes = const []});

  final bool singleUse;
  final bool reusable;
  final List<DepositType> depositTypes;

  /// Den Block lesen. Kein Objekt (Pfand aus, alter Server) -> `null`: das
  /// Feld fehlt dann am Modell, es wird nichts erfunden. Eine Pfandart in
  /// unbekannter Form faellt weg.
  static DepositSettings? fromJson(Object? value) {
    if (value is! Map) return null;
    final arten = value['depositTypes'];
    return DepositSettings(
      singleUse: value['singleUse'] == true,
      reusable: value['reusable'] == true,
      depositTypes: arten is List ? [for (final a in arten) ?DepositType.fromJson(a)] : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'singleUse': singleUse,
        'reusable': reusable,
        'depositTypes': [for (final a in depositTypes) a.toJson()],
      };
}

/// Eine Pfandangabe an Artikel oder Gruppe (`deposits[]`).
class DepositEntry {
  static const Set<String> fields = {'depositTypeId', 'quantity', 'gtin', 'ownFilling'};

  const DepositEntry({required this.depositTypeId, required this.quantity, this.gtin, this.ownFilling});

  final String depositTypeId;
  final int quantity;
  final String? gtin;
  final bool? ownFilling;

  /// Die Pfandliste eines Artikels oder einer Gruppe; keine Liste -> `null`,
  /// unlesbare Eintraege fallen weg. Eine leere Liste bleibt leer (= ausdruecklich
  /// ohne Pfand).
  static List<DepositEntry>? listFromJson(Object? value) {
    if (value is! List) return null;
    final raus = <DepositEntry>[];
    for (final e in value) {
      if (e is! Map || e['depositTypeId'] is! String || (e['depositTypeId'] as String).isEmpty || !_istGanz(e['quantity'], 1)) continue;
      raus.add(DepositEntry(
        depositTypeId: e['depositTypeId'] as String,
        quantity: _ganz(e['quantity'] as num),
        gtin: e['gtin'] is String && (e['gtin'] as String).isNotEmpty ? e['gtin'] as String : null,
        ownFilling: e['ownFilling'] is bool ? e['ownFilling'] as bool : null,
      ));
    }
    return raus;
  }

  Map<String, dynamic> toJson() => {
        'depositTypeId': depositTypeId,
        'quantity': quantity,
        'gtin': ?gtin,
        'ownFilling': ?ownFilling,
      };
}

/// Gemeinsame Rueckgabestelle (Kassen-Pfandangaben).
class DepositSharedReturnPoint {
  const DepositSharedReturnPoint({required this.name, this.address = ''});

  final String name;
  final String address;

  /// Liest die Stelle eines Belegs (`sharedReturnPoint`); `null`, wenn weder
  /// Name noch Anschrift als Text da sind (wie `pfandStelleFeld` im npm-Paket).
  static DepositSharedReturnPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'] is String ? raw['name'] as String : '';
    final address = raw['address'] is String ? raw['address'] as String : '';
    return name.isEmpty && address.isEmpty ? null : DepositSharedReturnPoint(name: name, address: address);
  }

  Map<String, dynamic> toJson() => {'name': name, 'address': address};
}

/// Pfand-Angaben des Kassenobjekts aus `listRegisterUsersForDevice`; fehlt bei
/// ausgeschaltetem Pfand.
class CashRegisterDeposit {
  static const Set<String> fields = {'returns', 'onPremisesDefault', 'usualQuantity', 'sharedReturnPoint'};

  const CashRegisterDeposit({
    required this.returns,
    required this.onPremisesDefault,
    this.usualQuantity = 1,
    this.sharedReturnPoint,
  });

  /// Ein Wert aus [depositReturnModes].
  final String returns;

  /// Ein Wert aus [depositOnPremisesDefaults].
  final String onPremisesDefault;
  final int usualQuantity;
  final DepositSharedReturnPoint? sharedReturnPoint;

  /// Fehlt der Block oder ist er unbrauchbar -> `null`.
  static CashRegisterDeposit? fromJson(Object? value) {
    if (value is! Map) return null;
    final returns = _aus(depositReturnModes, value['returns']);
    final vorgabe = _aus(depositOnPremisesDefaults, value['onPremisesDefault']);
    if (returns == null || vorgabe == null) return null;
    final stelle = value['sharedReturnPoint'];
    return CashRegisterDeposit(
      returns: returns,
      onPremisesDefault: vorgabe,
      usualQuantity: _istGanz(value['usualQuantity'], 1) ? _ganz(value['usualQuantity'] as num) : 1,
      sharedReturnPoint: stelle is Map && stelle['name'] is String
          ? DepositSharedReturnPoint(name: stelle['name'] as String, address: stelle['address'] is String ? stelle['address'] as String : '')
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'returns': returns,
        'onPremisesDefault': onPremisesDefault,
        'usualQuantity': usualQuantity,
        'sharedReturnPoint': sharedReturnPoint?.toJson(),
      };
}

// ---------------------------------------------------------------------------------------------------------------
// Vorschau-Rechnung
// ---------------------------------------------------------------------------------------------------------------

/// Pfandangaben, wirksam fuer einen Artikel: Artikel vor Gruppe, `[]` = kein
/// Pfand, `null`/fehlend = wie die Gruppe. Ein Fremdgutschein-Artikel traegt nie
/// Pfand, auch nicht von der Gruppe.
List<DepositEntry> depositsFor(PosArticle? article, ArticleGroup? group) {
  if (article == null) return const [];
  if (article.externalVoucher != null) return const [];
  final eigene = article.deposits;
  if (eigene != null) return eigene;
  return group?.deposits ?? const [];
}

/// Pfandbetrag in Cent am Wiener Tag [day] (`YYYY-MM-DD`): letzter Eintrag mit
/// `from <= day`, sonst `null`.
int? depositAmountOn(DepositType type, String day) {
  int? cents;
  for (final e in type.amounts) {
    if (e.from.compareTo(day) <= 0) {
      cents = e.cents;
    } else {
      break;
    }
  }
  return cents;
}

/// Wiener Kalendertag `YYYY-MM-DD` zum Zeitpunkt [nowMs] (Millisekunden seit
/// 1970 UTC; nie der UTC-Tag).
String viennaDay(int nowMs) => ViennaTime.dayKey(DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true));

/// Fehlercodes der Vorschau (die `/v3`-Codes von `createReceipt`).
const List<String> depositPreviewErrorCodes = [
  'invalid_deposit',
  'deposit_set_by_server',
  'deposit_type_not_found',
  'invalid_deposit_quantity',
  'deposit_return_not_offered',
  'deposit_type_not_issued',
  'not_permitted',
];

/// Eingabe der Vorschau (ohne die Positionen): was der Server aus Konto, Kasse
/// und Beleg wuesste.
class DepositPreviewInput {
  const DepositPreviewInput({
    required this.auto,
    required this.articles,
    required this.groups,
    required this.depositTypes,
    required this.day,
    required this.onPremises,
    required this.smallBusiness,
    required this.mayReturn,
    this.cashRegister,
  });

  /// Pfand zu Artikeln selbst ableiten (`autoDeposits`).
  final bool auto;

  /// Artikel nach Kennung.
  final Map<String, PosArticle> articles;

  /// Gruppen nach Kennung.
  final Map<String, ArticleGroup> groups;

  /// Pfandarten nach Kennung.
  final Map<String, DepositType> depositTypes;

  /// Wiener Tag des Belegs.
  final String day;

  /// Vor Ort getrunken: Einweg entfaellt.
  final bool onPremises;

  /// Pfand-Angaben der Kasse (nur `returns` zaehlt); ohne Angabe nimmt die
  /// Kasse kein Leergut zurueck.
  final CashRegisterDeposit? cashRegister;
  final bool smallBusiness;

  /// Der Benutzer darf Leergut zuruecknehmen (`depositReturnOf`).
  final bool mayReturn;
}

/// Ergebnis der Vorschau: die Positionen oder ein Fehlercode.
class DepositPreviewResult {
  const DepositPreviewResult.ok(List<Object?> this.items) : code = null;
  const DepositPreviewResult.error(String this.code) : items = null;

  /// Die Positionen in der Leitungsform (Maps, unveraenderte Positionen als
  /// dasselbe Objekt), `null` bei einem Fehler.
  final List<Object?>? items;

  /// Ein Wert aus [depositPreviewErrorCodes], `null` bei Erfolg.
  final String? code;

  bool get ok => items != null;
}

typedef _Obj = Map<String, Object?>;

const List<String> _ohnePfand = ['tip', 'discount', 'voucher', 'voucher_float', 'deposit', 'deposit_return'];

_Obj? _alsObjekt(Object? v) => v is Map ? v.cast<String, Object?>() : null;

bool _istHaupt(Object? it) {
  final o = _alsObjekt(it);
  return o != null && !_ohnePfand.contains(o['kind']);
}

Object? _mengeVon(_Obj it) => it['amount'] ?? it['quantity'];
Object? _satzVon(_Obj it) => it['vat'] ?? it['vatRate'];
bool _hatVerweis(_Obj it) => it['addOnOf'] != null;
bool _istGanzZahl(Object? v) => v is num && v.isFinite && v == v.truncate();

DepositType? _aktiv(Map<String, DepositType> arten, Object? id) {
  final a = id is String ? arten[id] : null;
  return a != null && a.active ? a : null;
}

_Obj _zeile(String kind, DepositType art, String name, int quantity, int cents, num vatRate) => {
      'kind': kind,
      'name': name,
      'quantity': quantity,
      'amount': quantity,
      'unitPriceCents': cents,
      'priceOneCents': cents,
      'priceOne': cents / 100,
      'vatRate': vatRate,
      'vat': vatRate,
      'depositTypeId': art.id,
      'depositKind': art.kind,
    };

({int cents, num vatRate})? _pfandPreis(DepositType art, _Obj haupt, String day, bool smallBusiness) {
  final cents = depositAmountOn(art, day);
  if (cents == null) return null;
  if (art.kind == 'single_use') return (cents: cents, vatRate: 0);
  if (smallBusiness) return (cents: cents, vatRate: 0);
  final satz = _satzVon(haupt);
  return satz is num && satz.isFinite ? (cents: cents, vatRate: satz) : null;
}

List<DepositEntry> _abgeleitet(Object? it, DepositPreviewInput input) {
  if (!input.auto || !_istHaupt(it)) return const [];
  final o = _alsObjekt(it)!;
  final id = o['articleId'];
  if (id is! String || id.isEmpty) return const [];
  final a = input.articles[id];
  if (a == null) return const [];
  final g = a.groupId != null ? input.groups[a.groupId] : null;
  return depositsFor(a, g);
}

bool _gtinOk(Object? v) => v is String && Gtin.isValid(v);

({_Obj? line, String? code}) _leergut(_Obj it, DepositPreviewInput input) {
  final kasse = input.cashRegister;
  if (kasse == null || kasse.returns != 'here') return (line: null, code: 'deposit_return_not_offered');
  if (!input.mayReturn) return (line: null, code: 'not_permitted');
  final art = _aktiv(input.depositTypes, it['depositTypeId']);
  if (art == null) return (line: null, code: 'deposit_type_not_found');
  if (art.kind == 'reusable' && !art.used) return (line: null, code: 'deposit_type_not_issued');
  final menge = it['quantity'];
  if (!_istGanzZahl(menge) || (menge as num) < 1 || menge > 1000) return (line: null, code: 'invalid_deposit');
  final quantity = _ganz(menge);
  Map<String, int>? codes;
  final rohCodes = it['codes'];
  if (rohCodes != null) {
    if (rohCodes is! Map) return (line: null, code: 'invalid_deposit');
    if (rohCodes.length > 50) return (line: null, code: 'invalid_deposit');
    var summe = 0;
    for (final e in rohCodes.entries) {
      final n = e.value;
      if (!_gtinOk(e.key) || !_istGanzZahl(n) || (n as num) < 1 || n > 1000) return (line: null, code: 'invalid_deposit');
      summe += _ganz(n);
    }
    if (summe != quantity) return (line: null, code: 'invalid_deposit');
    codes = {for (final e in rohCodes.entries) e.key as String: _ganz(e.value as num)};
  }
  final cents = depositAmountOn(art, input.day);
  if (cents == null) return (line: null, code: 'invalid_deposit');
  // Mehrweg-Leergut rechnet mit dem Rueckgabesatz der Pfandart (`returnRate` = Steuersatz), bei Kleinunternehmern 0.
  num vatRate = 0;
  if (art.kind == 'reusable' && !input.smallBusiness) {
    final satz = art.returnRate;
    if (satz == null || !satz.isFinite) return (line: null, code: 'invalid_deposit');
    vatRate = satz;
  }
  final z = _zeile('deposit_return', art, 'Leergut ${art.name.replaceFirst(RegExp(r'^Pfand '), '')}', quantity, -cents, vatRate);
  if (art.kind == 'single_use') z['ean'] = _ewpGtin;
  if (codes != null) z['codes'] = codes;
  return (line: z, code: null);
}

/// Pfand- und Leergutzeilen eines Belegs wie der Server: leitet Pfand zu
/// Artikeln ab (`auto`), prueft ausdrueckliche `deposit`-Zeilen und
/// `deposit_return`-Zeilen und rechnet `addOnOf` und `depositFor` auf die neuen
/// Positionen um. Ohne Pfand-/Leergutzeile und ohne Ableitung kommen die
/// Positionen unveraendert zurueck. Die Fehlercodes sind die von `createReceipt`.
///
/// Positionen und Zeilen sind Maps in der Leitungsform (`amount`/`quantity`,
/// `vat`/`vatRate`, `priceOne`, `addOnOf`, `depositFor` ...); ein Eintrag, der
/// keine Map ist (etwa eine Leerstelle), bleibt an seiner Stelle. Die Eingabe
/// wird nie veraendert. Zwilling von `withDepositLines` im npm-Paket; die
/// Zeilen entstehen mit denselben Gleitkomma-Schritten wie der Server
/// (`priceOne` = Cent / 100).
DepositPreviewResult withDepositLines(List<Object?> items, DepositPreviewInput input) {
  DepositPreviewResult fehler(String code) => DepositPreviewResult.error(code);
  final dahinter = <int, List<_Obj>>{};
  final ersetzt = <int, _Obj>{};
  void hinzu(int i, _Obj z) => (dahinter[i] ??= []).add(z);

  for (var i = 0; i < items.length; i += 1) {
    final it = _alsObjekt(items[i]);
    if (it == null) continue;
    if (it['kind'] == 'deposit_return') {
      final r = _leergut(it, input);
      if (r.line == null) return fehler(r.code!);
      ersetzt[i] = r.line!;
      continue;
    }
    if (it['kind'] == 'deposit') {
      final verweis = it['depositFor'];
      final haupt = _istGanzZahl(verweis) && (verweis as num) >= 0 && verweis < items.length ? items[_ganz(verweis)] : null;
      if (!_istHaupt(haupt)) return fehler('invalid_deposit');
      final hauptObj = _alsObjekt(haupt)!;
      if (_abgeleitet(haupt, input).isNotEmpty) return fehler('deposit_set_by_server');
      final art = _aktiv(input.depositTypes, it['depositTypeId']);
      if (art == null) return fehler('deposit_type_not_found');
      final menge = _mengeVon(hauptObj);
      if (!_istGanzZahl(menge) || menge == 0) return fehler('invalid_deposit_quantity');
      final m = _ganz(menge as num);
      final quantity = it['quantity'] ?? menge;
      if (!_istGanzZahl(quantity) || _ganz(quantity as num) % m != 0 || _ganz(quantity) / m < 1) return fehler('invalid_deposit_quantity');
      final preis = _pfandPreis(art, hauptObj, input.day, input.smallBusiness);
      if (preis == null) return fehler('invalid_deposit');
      final hatGtin = it['gtin'] != null;
      if (hatGtin && !_gtinOk(it['gtin'])) return fehler('invalid_deposit');
      if (it['ownFilling'] != null && it['ownFilling'] is! bool) return fehler('invalid_deposit');
      if (it['ownFilling'] == true && !hatGtin) return fehler('invalid_deposit');
      final q = _ganz(quantity);
      final z = _zeile('deposit', art, art.name, q, preis.cents, preis.vatRate);
      z['depositFor'] = _ganz(verweis as num);
      z['perUnit'] = q ~/ m;
      if (art.kind == 'single_use') z['ean'] = _ewpGtin;
      if (hatGtin) z['gtin'] = it['gtin'];
      if (it['ownFilling'] == true) z['ownFilling'] = true;
      ersetzt[i] = z;
      continue;
    }
    final eintraege = _abgeleitet(it, input);
    if (eintraege.isEmpty) continue;
    final menge = _mengeVon(it);
    final gelten = <({DepositEntry e, DepositType art})>[];
    for (final e in eintraege) {
      final art = _aktiv(input.depositTypes, e.depositTypeId);
      if (art == null) return fehler('deposit_type_not_found');
      if (art.kind == 'single_use' && input.onPremises) continue;
      gelten.add((e: e, art: art));
    }
    if (gelten.isEmpty) continue;
    if (!_istGanzZahl(menge)) return fehler('invalid_deposit_quantity');
    if (menge == 0) continue;
    final m = _ganz(menge as num);
    for (final g in gelten) {
      final preis = _pfandPreis(g.art, it, input.day, input.smallBusiness);
      if (preis == null) return fehler('invalid_deposit');
      final z = _zeile('deposit', g.art, g.art.name, g.e.quantity * m, preis.cents, preis.vatRate);
      z['depositFor'] = i;
      z['perUnit'] = g.e.quantity;
      if (g.art.kind == 'single_use') z['ean'] = _ewpGtin;
      if (g.e.gtin != null && g.e.gtin!.isNotEmpty) z['gtin'] = g.e.gtin;
      if (g.e.ownFilling == true) z['ownFilling'] = true;
      hinzu(i, z);
    }
  }

  if (ersetzt.isEmpty && dahinter.isEmpty) return DepositPreviewResult.ok(List<Object?>.of(items));

  final neu = <int>[];
  var verschiebung = 0;
  for (var i = 0; i < items.length; i += 1) {
    neu.add(i + verschiebung);
    verschiebung += dahinter[i]?.length ?? 0;
  }
  int? umgerechnet(Object? v) => v is num && v == v.truncate() && v >= 0 && v < neu.length ? neu[_ganz(v)] : null;

  final raus = <Object?>[];
  for (var i = 0; i < items.length; i += 1) {
    final original = _alsObjekt(items[i]);
    if (original == null) {
      raus.add(items[i]);
      continue;
    }
    var z = ersetzt[i] ?? original;
    if (z['kind'] == 'deposit' && umgerechnet(z['depositFor']) != null) {
      z = {...z, 'depositFor': umgerechnet(z['depositFor'])};
    } else if (_hatVerweis(z) && umgerechnet(z['addOnOf']) != null) {
      z = {...z, 'addOnOf': umgerechnet(z['addOnOf'])};
    }
    raus.add(z);
    for (final d in dahinter[i] ?? const <_Obj>[]) {
      raus.add({...d, 'depositFor': neu[i]});
    }
  }
  return DepositPreviewResult.ok(raus);
}

/// Die Leergutzeile zu [quantity] Stueck einer Pfandart, wie [withDepositLines]
/// sie fuer eine `deposit_return`-Eingabe baut (fuer die Korb-Vorschau). Wirft
/// einen [StateError], wenn sich keine Zeile ergibt (Menge ausserhalb 1 bis
/// 1000, Mehrweg ohne Rueckgabesatz, Pfandart ohne Betrag am Tag, ungueltige
/// [codes], Steuersatz ausserhalb von [VatRate]); ob die Kasse Leergut annimmt,
/// prueft der Aufrufer. Zwilling von `depositReturnLine` im npm-Paket.
KasseneckItem depositReturnLine(
  DepositType type,
  int quantity, {
  required String day,
  required bool smallBusiness,
  Map<String, int>? codes,
}) {
  final r = _leergut(
    {'kind': 'deposit_return', 'depositTypeId': type.id, 'quantity': quantity, 'codes': ?codes},
    DepositPreviewInput(
      auto: false,
      articles: const {},
      groups: const {},
      depositTypes: {type.id: type},
      day: day,
      onPremises: false,
      smallBusiness: smallBusiness,
      mayReturn: true,
      cashRegister: const CashRegisterDeposit(returns: 'here', onPremisesDefault: 'ask'),
    ),
  );
  if (r.line == null) throw StateError('Leergutzeile nicht moeglich: ${r.code}');
  final l = r.line!;
  final satz = l['vatRate'] as num;
  final vat = VatRate.values.where((v) => v.rate == satz).firstOrNull;
  if (vat == null) throw StateError('Leergutzeile nicht moeglich: Steuersatz $satz ist unbekannt');
  return KasseneckItem(
    name: l['name'] as String,
    quantity: l['quantity'] as int,
    vat: vat,
    priceCents: l['unitPriceCents'] as int,
    kind: 'deposit_return',
    depositTypeId: l['depositTypeId'] as String,
    depositKind: type.kind,
    ean: l['ean'] as String?,
    codes: l['codes'] as Map<String, int>?,
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Leergut-Codes
// ---------------------------------------------------------------------------------------------------------------

/// Ein gelernter Leergut-Code: die GTIN und die Pfandart, der sie zugeordnet ist.
class ReturnCode {
  static const Set<String> fields = {'gtin', 'depositTypeId'};

  const ReturnCode({required this.gtin, required this.depositTypeId});

  final String gtin;
  final String depositTypeId;

  /// `null`, wenn der Eintrag nicht lesbar ist.
  static ReturnCode? fromJson(Object? value) {
    if (value is! Map || value['gtin'] is! String || value['depositTypeId'] is! String) return null;
    return ReturnCode(gtin: value['gtin'] as String, depositTypeId: value['depositTypeId'] as String);
  }

  Map<String, dynamic> toJson() => {'gtin': gtin, 'depositTypeId': depositTypeId};

  @override
  bool operator ==(Object other) => other is ReturnCode && other.gtin == gtin && other.depositTypeId == depositTypeId;

  @override
  int get hashCode => Object.hash(gtin, depositTypeId);
}

/// Die Nutzlast von `learnMyLeergutCode`: prueft die Form vor dem Senden (gueltige
/// GTIN, nichtleere Pfandart). Was der Server nicht annimmt, lehnt er mit
/// `invalid_deposit` oder `deposit_type_not_found` ab. Paketintern.
Map<String, Object?> returnCodeNutzlast(String name, ReturnCode code) {
  KasseneckValidationError anfrage(String grund) => KasseneckValidationError(name, grund, 'request');
  if (!Gtin.isValid(code.gtin)) throw anfrage('gtin ist keine gueltige GTIN');
  if (code.depositTypeId.isEmpty) throw anfrage('depositTypeId fehlt');
  return {'gtin': code.gtin, 'depositTypeId': code.depositTypeId};
}

/// Eine Zeile der Zuordnung: Pfandart und Stueckzahl, die ein Scan ins
/// Leergut-Blatt bringt.
class ReturnCodeEntry {
  const ReturnCodeEntry({required this.depositTypeId, required this.quantity});

  final String depositTypeId;
  final int quantity;

  @override
  bool operator ==(Object other) => other is ReturnCodeEntry && other.depositTypeId == depositTypeId && other.quantity == quantity;

  @override
  int get hashCode => Object.hash(depositTypeId, quantity);

  @override
  String toString() => 'ReturnCodeEntry($depositTypeId, $quantity)';
}

/// Ergebnis von [matchReturnCode]: die Eintraege oder `unknown` (der Code ist
/// keiner Pfandart zuzuordnen).
class ReturnCodeMatch {
  const ReturnCodeMatch.entries(List<ReturnCodeEntry> this.entries) : unknown = false;
  const ReturnCodeMatch.unknown()
      : entries = null,
        unknown = true;

  final List<ReturnCodeEntry>? entries;
  final bool unknown;
}

/// Ordnet einen Scan im Leergut-Blatt einer Pfandart zu. Reihenfolge: (1)
/// gelernter Code -> 1 Stueck; (2) `gtin` eines Pfandeintrags an Artikel oder
/// Gruppe -> 1 Stueck dieser Pfandart; (3) Artikel-EAN, -Nummer oder -Code mit
/// wirksamer Pfandliste -> jeder Eintrag mit seiner `quantity` (Kiste: 1 Kiste
/// + 20 Flaschen); sonst `unknown`. Es zaehlen nur aktive Pfandarten: ein
/// Treffer auf eine stillgelegte oder unbekannte Pfandart ist `unknown` (die
/// Suche endet am ersten Treffer, sie faellt nicht auf die naechste Stufe
/// zurueck). Der Code wird getrimmt, ein leerer ist `unknown`. Zwilling von
/// `matchReturnCode` im npm-Paket.
ReturnCodeMatch matchReturnCode(
  String code, {
  required List<PosArticle> articles,
  required List<ArticleGroup> groups,
  required List<ReturnCode> learned,
  required List<DepositType> depositTypes,
}) {
  const unbekannt = ReturnCodeMatch.unknown();
  final gesucht = code.trim();
  if (gesucht.isEmpty) return unbekannt;
  final aktiv = {for (final t in depositTypes) if (t.active) t.id};
  ReturnCodeMatch eins(String id) =>
      aktiv.contains(id) ? ReturnCodeMatch.entries([ReturnCodeEntry(depositTypeId: id, quantity: 1)]) : unbekannt;

  for (final l in learned) {
    if (l.gtin == gesucht) return eins(l.depositTypeId);
  }

  ArticleGroup? gruppeVon(PosArticle a) => groups.where((g) => g.id == a.groupId).firstOrNull;
  for (final a in articles) {
    for (final d in depositsFor(a, gruppeVon(a))) {
      if (d.gtin == gesucht) return eins(d.depositTypeId);
    }
  }
  for (final g in groups) {
    for (final d in g.deposits ?? const <DepositEntry>[]) {
      if (d.gtin == gesucht) return eins(d.depositTypeId);
    }
  }

  final artikel = articles.where((a) => a.ean == gesucht || a.number == gesucht || a.internalCode == gesucht).firstOrNull;
  if (artikel == null) return unbekannt;
  final liste = depositsFor(artikel, gruppeVon(artikel));
  if (liste.isEmpty || !liste.every((d) => aktiv.contains(d.depositTypeId))) return unbekannt;
  return ReturnCodeMatch.entries([for (final d in liste) ReturnCodeEntry(depositTypeId: d.depositTypeId, quantity: d.quantity)]);
}
