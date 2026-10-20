/// Gutscheine der neuen Form an der Kasse: pruefen (`checkVoucher`), Etikett
/// nachdrucken (`reprintVoucherLabel`), die Gutschein-Einstellung der Kasse
/// (Block `vouchers` aus `getKasseSettings`) und die Gutschein-Rechte.
/// Zwilling von `pos/gutschein.ts` im npm-Paket, gleiche Namen.
///
/// Der Klartext-Code lebt nur im Speicher des Aufrufs: er wird weder
/// protokolliert noch in einer Fehlermeldung genannt. Die Kasse bekommt nach
/// dem Pruefen nur die letzten vier Zeichen ([VoucherCheck.codeSuffix]).
library;

import 'package:kreiseck_validator/kreiseck_validator.dart' show Valid, VoucherCode;

import '../../enums/voucher_type.dart';
import '../../models/keck_voucher.dart';
import '../aufrufe.dart';
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
const List<String> voucherValidityPatterns = ['unlimited', '1+3', 'custom'];

/// Gueltigkeit eines Gutscheins; Daten als `YYYY-MM-DD` (Wiener Tag). Was der
/// Server nicht nennt, ist `null`.
class VoucherValidity {
  const VoucherValidity({required this.pattern, this.redeemableUntil, this.refundableUntil, this.validUntil});

  /// Ein Wert aus [voucherValidityPatterns].
  final String pattern;
  final String? redeemableUntil;
  final String? refundableUntil;
  final String? validUntil;

  @override
  bool operator ==(Object other) =>
      other is VoucherValidity &&
      other.pattern == pattern &&
      other.redeemableUntil == redeemableUntil &&
      other.refundableUntil == refundableUntil &&
      other.validUntil == validUntil;

  @override
  int get hashCode => Object.hash(pattern, redeemableUntil, refundableUntil, validUntil);
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
}

/// Gutschein-Einstellung der Kasse (Block `vouchers` aus `getKasseSettings`).
class PosVoucherSettings {
  const PosVoucherSettings({required this.sale, required this.valueVoucherType, required this.vatRateBp});

  /// Ohne Block (alter Server, Konto ohne Schalter) oder bei einem unstimmigen
  /// Block: Verkaufen ist aus.
  static const off = PosVoucherSettings(sale: false, valueVoucherType: null, vatRateBp: null);

  /// Gutscheine verkaufen ist eingeschaltet.
  final bool sale;

  /// Die bestaetigte Art des Wertgutscheins: [VoucherType.multiPurpose],
  /// [VoucherType.singlePurpose] oder `null`.
  final VoucherType? valueVoucherType;

  /// Satz des Einzweckgutscheins in Basispunkten; bei Mehrzweck `null`.
  final int? vatRateBp;

  /// Block `vouchers`, geschlossen im Zweifel: ist irgendein Feld unstimmig,
  /// gilt der ganze Block als nicht gelesen und Verkaufen bleibt aus (kein
  /// Wurf, sonst ginge das Laden aller Einstellungen verloren). Stimmig
  /// heisst: `sale` ein Wahrheitswert, die Art `multi_purpose`,
  /// `single_purpose` oder `null`, der Satz eine ganze Zahl >= 0 oder `null`;
  /// Mehrzweck traegt keinen Satz, Einzweck braucht einen, und ein
  /// eingeschalteter Verkauf braucht eine Art. Ein ausgeschalteter Verkauf
  /// darf eine Art behalten.
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
    return PosVoucherSettings(sale: sale, valueVoucherType: art, vatRateBp: satz as int?);
  }

  Map<String, dynamic> toJson() => {'sale': sale, 'valueVoucherType': valueVoucherType?.wire, 'vatRateBp': vatRateBp};

  @override
  bool operator ==(Object other) =>
      other is PosVoucherSettings &&
      other.sale == sale &&
      other.valueVoucherType == valueVoucherType &&
      other.vatRateBp == vatRateBp;

  @override
  int get hashCode => Object.hash(sale, valueVoucherType, vatRateBp);
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

  return VoucherValidity(
    pattern: muster,
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
  );
}
