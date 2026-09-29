/// Zahlbetrag eines Belegs in ganzen Cent: Zwilling von `receiptDueCents` in
/// `@kreiseck/kasseneck-api` 1.0 (`src/receipt/due.ts`) und damit von
/// `createReceipt` im Backend, also `receipt-toepfe.belegToepfe(...).zaehlerDeltaCents`
/// plus `payments-core.wertgutscheinFlussCents`, mit den Trinkgeld-Positionen,
/// die `tip-core.buildTipItems` aus `tip` bzw. aus `payments[].tipCents` baut.
///
/// `createReceipt` hat keinen Probelauf. Unter `/v3` ist `payments[]` Pflicht,
/// und die Summe der Zahlungen muss genau diesen Betrag treffen; wer die
/// Zahlungen baut (Kartenterminal, Rueckgeld), rechnet ihn hier vorher aus.
/// Trifft die Summe nicht, antwortet der Server mit `payments_sum_mismatch` und
/// `expectedCents`, ohne eine Belegnummer zu verbrauchen; das Paket wiederholt
/// nie selbst.
///
/// **Bewusst dieselbe Rechnung wie der Server, nicht die exakte.** Das Backend
/// rechnet die RKSV-Toepfe in Euro-Gleitkomma (Einzelpreis `Math.round(cents)/100`,
/// je Topf `priceOne * amount` in Positionsreihenfolge, Trinkgeld-Positionen
/// hinten angehaengt, gerundet mit `Math.round(euro * 100)`, Rabatt-Deckel in
/// Euro). Diese Reihenfolge ist signiert und aendert sich nicht; ein exakter
/// Zwilling wiche bei Bruchmengen auf halbem Cent ab (0,5 x 29 ct: Server 14,
/// exakt 15). Darum steht hier dieselbe Arithmetik, Schritt fuer Schritt, mit
/// IEEE-Doubles wie in JavaScript. Gerundet wird wie `Math.round` (halbe Werte
/// Richtung plus unendlich), nicht wie Darts `round()` (von null weg): am
/// Storno sind die Betraege negativ, und dort unterscheiden sich die beiden.
///
/// Geprueft gegen die 20 Vertragsfaelle aus `v3/zahlbetrag-faelle.json` und
/// gegen die 1206 mit dem echten Backend-Code erzeugten Faelle aus
/// `receipt-due-generated.json`.
///
/// **Trinkgeld-Empfaenger:** Ohne `recipients` bucht der Server das Trinkgeld
/// auf den angemeldeten Kassen-Benutzer, und dessen Inhaber-Kennzeichen
/// entscheidet: Inhaber-Trinkgeld ist Umsatz (anteilig auf die Saetze der Ware,
/// mitrabattiert), Personal-Trinkgeld ein durchlaufender Posten (nie
/// rabattiert). Das weiss nur die Kasse; darum ist [ReceiptDueTipRecipient]
/// Pflicht, sobald Trinkgeld ohne `recipients` vorkommt. Ohne angemeldeten
/// Benutzer (Geraete-Schluessel) gilt `staff`.
library;

import '../../enums/keck_payment_method.dart';
import '../../enums/receipt_type.dart';
import '../../enums/voucher_action.dart';
import '../../enums/voucher_type.dart';
import '../../models/kasseneck_item.dart';
import '../../models/keck_payment.dart';
import '../../models/keck_tip.dart';
import '../../models/keck_voucher.dart';
import '../register/fehler.dart' show ErrorOutcome;

/// Stabiler Code von [ReceiptDueError], gleich fuer jede Ursache.
const String receiptDueErrorCode = 'receipt_due_unavailable';

/// Warum sich der Zahlbetrag nicht rechnen laesst ([ReceiptDueError.reason]).
/// Fest wie ein Backend-Code; dieselbe Liste im npm-Paket
/// (`RECEIPT_DUE_ERROR_REASONS`) und in `receipt-due-errors.json`.
///
/// `unknown_receipt_type` kann hier nicht entstehen: der Belegtyp ist ein
/// [ReceiptType], ein fremder Wert laesst sich gar nicht uebergeben. Der Name
/// steht trotzdem in der Liste, damit beide Pakete dieselben Gruende fuehren.
const List<String> receiptDueErrorReasons = [
  'unknown_receipt_type',
  'tip_not_allowed',
  'invalid_item',
  'invalid_voucher',
  'invalid_tip',
  'unknown_payment_method',
  'tip_conflict',
  'tip_recipient_missing',
  'tip_without_goods',
];

/// Der Zahlbetrag laesst sich aus dieser Eingabe nicht rechnen, etwa
/// Trinkgeld mit Betrag ohne Ware ([reason] `tip_without_goods`). Zwilling von
/// `ReceiptDueError` im npm-Paket.
///
/// Eindeutig **nicht gesendet**: die Rechnung laeuft ganz im Paket, vor jedem
/// Aufruf. [outcome] ist darum immer [ErrorOutcome.rejected]; nichts ist
/// geschehen, keine Belegnummer verbraucht, keine Karte belastet. Die Kasse
/// sagt das dem Kassier, bevor sie ein Terminal anspricht. Entscheiden am
/// [code] bzw. [reason], nie an [message] (die ist fuers Protokoll).
///
/// Bis 10.0.0-rc.1 warf die Rechnung hier einen `ArgumentError` ohne Code.
class ReceiptDueError implements Exception {
  const ReceiptDueError(this.reason, this.message);

  /// Die Ursache im Einzelnen, ein Wert aus [receiptDueErrorReasons].
  final String reason;

  /// Fuers Protokoll, nie zum Entscheiden.
  final String message;

  /// Immer [receiptDueErrorCode].
  String get code => receiptDueErrorCode;

  /// Immer [ErrorOutcome.rejected]: es ging nichts hinaus.
  ErrorOutcome get outcome => ErrorOutcome.rejected;

  @override
  String toString() => 'ReceiptDueError($reason): Zahlbetrag: $message';
}

/// Ist [error] ein [ReceiptDueError]?
bool isReceiptDueError(Object? error) => error is ReceiptDueError;

/// Wer das Trinkgeld ohne `recipients` bekommt (Kennzeichen des angemeldeten
/// Kassen-Benutzers). Auch die Art einer fertigen Trinkgeld-Position.
enum ReceiptDueTipRecipient { owner, staff }

/// Ein Anteil am Trinkgeld samt Inhaber-Kennzeichen des Empfaengers.
class ReceiptDueTipShare {
  const ReceiptDueTipShare({required this.cents, required this.owner});

  final int cents;
  final bool owner;
}

/// Trinkgeld wie `tip` am Verkauf: Betrag, optional mit Empfaengern samt
/// Inhaber-Kennzeichen (das Kennzeichen kennt nur die Kasse).
class ReceiptDueTip {
  const ReceiptDueTip(this.cents, {this.recipients});

  /// Bruecke vom Trinkgeld am Verkauf ([KeckTip], wie es `sellReceipt`
  /// nimmt) zum Trinkgeld der Rechnung. Ob ein Empfaenger Inhaber ist, weiss
  /// nur die Kasse: [isOwner] ist Pflicht, sobald [tip] Empfaenger nennt.
  /// Ohne Empfaenger entscheidet `tipRecipient` an [receiptDueCents].
  factory ReceiptDueTip.fromKeckTip(KeckTip tip, {bool Function(String registerUserId)? isOwner}) {
    final empfaenger = tip.recipients;
    if (empfaenger == null || empfaenger.isEmpty) return ReceiptDueTip(tip.cents);
    if (isOwner == null) {
      throw ArgumentError('isOwner ist Pflicht, wenn das Trinkgeld Empfaenger nennt.');
    }
    return ReceiptDueTip(tip.cents, recipients: [
      for (final r in empfaenger) ReceiptDueTipShare(cents: r.cents, owner: isOwner(r.registerUserId)),
    ]);
  }

  final int cents;
  final List<ReceiptDueTipShare>? recipients;
}

/// Eine Position fuer die Rechnung. Anders als [KasseneckItem] darf die Menge
/// hier ein Bruch sein (0,375 kg) und der Steuersatz jeder Wert, den ein
/// Beleg tragen kann; [ReceiptDueLine.of] macht aus einer Position eine Zeile.
class ReceiptDueLine {
  const ReceiptDueLine({required this.quantity, required this.priceCents, required this.vatRate, this.tip});

  /// Die Zeile einer Position; eine Trinkgeld-Position (`kind: 'tip'`) behaelt
  /// ihre Art (Inhaber, wenn `recipient.owner == true`, sonst Personal).
  ///
  /// Gemeint sind lokal gebaute Positionen. Eine vom Server gelesene Position
  /// mit Bruchmenge oder unbekanntem Satz hat [KasseneckItem.fromJson] nicht
  /// exakt uebernehmen koennen; dann wirft dieser Aufruf, statt still falsch zu
  /// rechnen. Solche Positionen gehen ueber [ReceiptDueLine.fromJson] und
  /// [receiptDueBreakdownForLines].
  factory ReceiptDueLine.of(KasseneckItem item) {
    final ungenau = item.lossyRead;
    if (ungenau != null) {
      throw ReceiptDueError('invalid_item', 'Position "${item.name}" ist nicht exakt gelesen ($ungenau); '
          'Serverpositionen ueber ReceiptDueLine.fromJson und receiptDueBreakdownForLines rechnen.');
    }
    return ReceiptDueLine(
        quantity: item.quantity,
        priceCents: item.priceCents,
        vatRate: item.vat.rate,
        tip: item.isTip ? (item.isOwnerTip ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff) : null,
      );
  }

  /// Eine Position, wie der Server sie liefert (v1- oder v2-Form), roh: Menge
  /// als Bruch, Satz wie geliefert, Cent-Preis. Fehlt etwas oder ist es kein
  /// Zahlenwert, wirft der Aufruf.
  factory ReceiptDueLine.fromJson(Map<String, dynamic> json) {
    final menge = json['quantity'] ?? json['amount'];
    final cents = json['unitPriceCents'] ?? json['priceOneCents'];
    final satz = json['vatRate'] ?? json['vat'];
    if (menge is! num || cents is! num || cents != cents.toInt() || satz is! num) {
      throw ReceiptDueError('invalid_item', 'Position "${json['name']}" ohne Menge, ganzen Cent-Preis oder Steuersatz.');
    }
    final recipient = json['recipient'];
    final owner = recipient is Map && recipient['owner'] == true;
    return ReceiptDueLine(
      quantity: menge,
      priceCents: cents.toInt(),
      vatRate: satz,
      tip: json['kind'] == 'tip' ? (owner ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff) : null,
    );
  }

  final num quantity;
  final int priceCents;
  final num vatRate;

  /// `null` fuer Ware; sonst die Art der Trinkgeld-Position.
  final ReceiptDueTipRecipient? tip;
}

/// Ergebnis von [receiptDueBreakdown].
class ReceiptDueBreakdown {
  const ReceiptDueBreakdown({
    required this.dueCents,
    required this.counterDeltaCents,
    required this.valueVoucherFlowCents,
    required this.bucketsCents,
  });

  /// Was die Zahlungen zusammen ergeben muessen.
  final int dueCents;

  /// Delta des Umsatzzaehlers (Summe der Toepfe).
  final int counterDeltaCents;

  /// Anteil der Wertgutscheine am Zahlbetrag.
  final int valueVoucherFlowCents;

  /// Die sechs RKSV-Toepfe je auf Cent gerundet, Namen wie am Beleg des
  /// Backends (`amountRateStandard` … `amountRatOthers`); `null` bei Start-
  /// und Nullbeleg.
  final Map<String, int>? bucketsCents;
}

/// Zahlbetrag in Cent, siehe Bibliothekskommentar.
int receiptDueCents(
  List<KasseneckItem> items,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
}) =>
    receiptDueBreakdown(items, vouchers, receiptType, tip: tip, payments: payments, tipRecipient: tipRecipient).dueCents;

/// Wie [receiptDueCents], dazu Zaehler-Delta, Wertgutschein-Anteil und Toepfe.
ReceiptDueBreakdown receiptDueBreakdown(
  List<KasseneckItem> items,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
}) =>
    receiptDueBreakdownForLines([for (final i in items) ReceiptDueLine.of(i)], vouchers, receiptType,
        tip: tip, payments: payments, tipRecipient: tipRecipient);

/// Wie [receiptDueBreakdown], mit Zeilen statt Positionen (Bruchmengen).
///
/// [payments] zaehlen nur, soweit sie Trinkgeld tragen (`tipCents`): der
/// Server bucht je Zahlart so, als waere `tip` mit der Summe und dieser
/// Zahlart geschickt worden. [tip] und `payments[].tipCents` gehen nie
/// zugleich (`tip_conflict`).
ReceiptDueBreakdown receiptDueBreakdownForLines(
  List<ReceiptDueLine> lines,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
}) {
  final trinkgelder = _trinkgeldAuftraege(tip, payments);
  if (trinkgelder.isNotEmpty && !_trinkgeldErlaubt.contains(receiptType)) {
    throw ReceiptDueError('tip_not_allowed', 'Trinkgeld gibt es nur bei standard und training, nicht bei "${receiptType.name}".');
  }
  if (!_umsatz.contains(receiptType)) {
    return const ReceiptDueBreakdown(dueCents: 0, counterDeltaCents: 0, valueVoucherFlowCents: 0, bucketsCents: null);
  }

  final positionen = [for (final (i, z) in lines.indexed) _innen(z, i)];
  final gutscheine = [for (final (i, v) in vouchers.indexed) _gutscheinInnen(v, i)];
  // index.js createReceipt: erst `tip`, dann je Zahlart aus payments[].tipCents;
  // jede Runde haengt ihre Positionen hinten an (die Basis bleibt die Ware).
  for (final auftrag in trinkgelder) {
    positionen.addAll(_trinkgeldPositionen(auftrag, positionen, tipRecipient));
  }

  final t = _belegToepfe(positionen, gutscheine);
  final fluss = _wertgutscheinFlussCents(gutscheine, receiptType);
  return ReceiptDueBreakdown(
    dueCents: t.zaehlerDeltaCents + fluss,
    counterDeltaCents: t.zaehlerDeltaCents,
    valueVoucherFlowCents: fluss,
    bucketsCents: {for (final n in _alleToepfe) n: _euroToCent(t.toepfe[n]!)},
  );
}

const _umsatz = {ReceiptType.standard, ReceiptType.cancellation, ReceiptType.training};
const _trinkgeldErlaubt = {ReceiptType.standard, ReceiptType.training};
const _zahlarten = {
  KeckPaymentMethod.cash,
  KeckPaymentMethod.creditCard,
  KeckPaymentMethod.online,
  KeckPaymentMethod.uberApp,
  KeckPaymentMethod.uberCard,
  KeckPaymentMethod.uberCash,
  KeckPaymentMethod.boltApp,
  KeckPaymentMethod.boltCard,
  KeckPaymentMethod.boltCash,
};

/// `Math.round` aus JavaScript: naechste ganze Zahl, halbe Werte Richtung plus
/// unendlich. Der Nachkommaanteil `x - floor(x)` ist bei Doubles exakt.
double _jsRound(double x) {
  if (!x.isFinite) return x;
  final unten = x.floorToDouble();
  return x - unten >= 0.5 ? unten + 1 : unten;
}

/// `receipt-toepfe.euroToCent`.
int _euroToCent(double euro) => _jsRound(euro * 100).toInt();

/// Position in der inneren Form des Backends (`receipt-toepfe.interneForm`).
class _Innen {
  const _Innen(this.amount, this.priceOne, this.vat, this.tip);
  final double amount;
  final double priceOne;
  final double vat;
  final ReceiptDueTipRecipient? tip;
}

class _Gutschein {
  const _Gutschein(this.action, this.type, this.value);
  final VoucherAction action;
  final VoucherType type;
  final double value;
}

/// Einzelpreis `Math.round(cents) / 100` wie `interneForm`; `-0` wird `0`
/// (in JavaScript fallen beide Saetze als Schluessel `"0"` zusammen).
_Innen _innen(ReceiptDueLine z, int i) {
  final satz = z.vatRate.toDouble();
  if (!satz.isFinite) throw ReceiptDueError('invalid_item', 'Position ${i + 1} ohne Steuersatz.');
  final menge = z.quantity.toDouble();
  if (!menge.isFinite) throw ReceiptDueError('invalid_item', 'Position ${i + 1} hat keine gueltige Menge.');
  return _Innen(menge, z.priceCents / 100, satz == 0 ? 0.0 : satz, z.tip);
}

_Gutschein _gutscheinInnen(KeckVoucher v, int i) {
  final cents = v.valueCents;
  if (cents == null) throw ReceiptDueError('invalid_voucher', 'Gutschein ${i + 1} hat keinen ganzen Cent-Wert.');
  return _Gutschein(v.action, v.type, cents / 100);
}

/// Empfaenger eines Trinkgeld-Auftrags; `owner == null` heisst: wie der angemeldete Benutzer.
typedef _Auftrag = List<({int cents, bool? owner})>;

/// Trinkgeld-Auftraege in der Reihenfolge des Servers: `tip`, dann je Zahlart die Summe der `tipCents`.
List<_Auftrag> _trinkgeldAuftraege(ReceiptDueTip? tip, List<KeckPaymentInput>? payments) {
  final raus = <_Auftrag>[];
  final mitTipCents = (payments ?? const []).any((z) => z.tipCents != null);
  if (tip != null && mitTipCents) {
    throw const ReceiptDueError('tip_conflict', 'tip und payments[].tipCents gehen nicht zugleich (tip_conflict).');
  }
  if (tip != null) {
    _pruefeCent(tip.cents, 'Trinkgeld');
    final recipients = tip.recipients;
    if (recipients != null) {
      if (recipients.isEmpty) throw const ReceiptDueError('invalid_tip', 'recipients darf nicht leer sein.');
      var summe = 0;
      for (final r in recipients) {
        _pruefeCent(r.cents, 'Trinkgeld-Anteil');
        summe += r.cents;
      }
      if (summe != tip.cents) throw const ReceiptDueError('invalid_tip', 'die Anteile des Trinkgelds ergeben nicht den Betrag.');
      raus.add([for (final r in recipients) (cents: r.cents, owner: r.owner)]);
    } else {
      raus.add([(cents: tip.cents, owner: null)]);
    }
  }
  // zahlungen-core.tipsJeZahlart: Summe je bekannter Zahlart, Reihenfolge des ersten Auftretens.
  final je = <KeckPaymentMethod, int>{};
  for (final z in payments ?? const <KeckPaymentInput>[]) {
    final cents = z.tipCents;
    if (cents == null) continue;
    _pruefeCent(cents, 'tipCents');
    if (!_zahlarten.contains(z.method)) throw ReceiptDueError('unknown_payment_method', 'unbekannte Zahlart "${z.method.name}".');
    je[z.method] = (je[z.method] ?? 0) + cents;
  }
  for (final cents in je.values) {
    raus.add([(cents: cents, owner: null)]);
  }
  return raus;
}

void _pruefeCent(int wert, String was) {
  if (wert <= 0) throw ReceiptDueError('invalid_tip', '$was muss eine ganze Zahl in Cent > 0 sein.');
}

/// `tip-core.buildTipItems`: Personal in den Null-%-Satz, Inhaber anteilig auf die Saetze der Ware.
List<_Innen> _trinkgeldPositionen(_Auftrag auftrag, List<_Innen> positionen, ReceiptDueTipRecipient? standard) {
  final basis = _warenCentsJeSatz(positionen);
  final summe = basis.values.fold<int>(0, (s, c) => s + c);
  if (summe <= 0) throw const ReceiptDueError('tip_without_goods', 'Trinkgeld braucht mindestens eine Position mit Betrag.');
  final raus = <_Innen>[];
  for (final e in auftrag) {
    var owner = e.owner;
    if (owner == null) {
      if (standard == null) {
        throw const ReceiptDueError(
            'tip_recipient_missing', "tipRecipient fehlt ('owner' oder 'staff', wie der angemeldete Kassen-Benutzer).");
      }
      owner = standard == ReceiptDueTipRecipient.owner;
    }
    if (!owner) {
      raus.add(_Innen(1, e.cents / 100, 0, ReceiptDueTipRecipient.staff));
      continue;
    }
    final teile = _splitOwnerTip(e.cents, basis);
    if (teile.isEmpty) throw const ReceiptDueError('tip_without_goods', 'Inhaber-Trinkgeld braucht mindestens eine Position mit Betrag.');
    for (final teil in teile) {
      if (teil.cents != 0) raus.add(_Innen(1, teil.cents / 100, teil.vat, ReceiptDueTipRecipient.owner));
    }
  }
  return raus;
}

/// `tip-core.warenCentsJeSatz`: Summe je Satz in Euro, dann einmal runden.
Map<double, int> _warenCentsJeSatz(List<_Innen> positionen) {
  final roh = <double, double>{};
  for (final p in positionen) {
    if (p.tip != null) continue;
    roh[p.vat] = (roh[p.vat] ?? 0) + p.amount * p.priceOne;
  }
  return {for (final MapEntry(:key, :value) in roh.entries) key: _euroToCent(value)};
}

/// `tip-core.splitOwnerTip`.
List<({double vat, int cents})> _splitOwnerTip(int cents, Map<double, int> jeSatz) {
  final saetze = [
    for (final MapEntry(key: vat, value: basis) in jeSatz.entries)
      if (basis > 0) (vat: vat, basis: basis),
  ]..sort((a, b) => b.vat.compareTo(a.vat));
  final basis = saetze.fold<int>(0, (s, x) => s + x.basis);
  if (basis <= 0) return const [];
  var vergeben = 0;
  final verteilt = <({double vat, int cents, double frac})>[];
  for (final s in saetze) {
    final exakt = (cents * s.basis) / basis;
    final anteil = exakt.floor();
    vergeben += anteil;
    verteilt.add((vat: s.vat, cents: anteil, frac: exakt - anteil));
  }
  final rest = cents - vergeben;
  if (rest > 0) {
    var bester = 0;
    for (var i = 0; i < verteilt.length; i++) {
      final e = verteilt[i];
      final b = verteilt[bester];
      if (e.frac > b.frac || (e.frac == b.frac && e.vat > b.vat)) bester = i;
    }
    final b = verteilt[bester];
    verteilt[bester] = (vat: b.vat, cents: b.cents + rest, frac: b.frac);
  }
  return [for (final e in verteilt) (vat: e.vat, cents: e.cents)];
}

const _standard = 'amountRateStandard';
const _reduced1 = 'amountRateReduced1';
const _reduced2 = 'amountRateReduced2';
const _zero = 'amountRateZero';
const _special = 'amountRateSpecial';
const _others = 'amountRatOthers';
const _fuenf = [_standard, _reduced1, _reduced2, _zero, _special];
const _alleToepfe = [..._fuenf, _others];

/// `vat-buckets.bucketFuerSatz`.
String _topfFuerSatz(double vat) {
  if (vat == 20) return _standard;
  if (vat == 10) return _reduced1;
  if (vat == 13) return _reduced2;
  if (vat == 0) return _zero;
  if (vat == 19 || vat == 4.9) return _special;
  return _others;
}

/// `receipt-toepfe.belegToepfe`, Schritt fuer Schritt.
({Map<String, double> toepfe, int zaehlerDeltaCents}) _belegToepfe(List<_Innen> positionen, List<_Gutschein> gutscheine) {
  final t = {for (final n in _alleToepfe) n: 0.0};
  var personal = 0.0;
  for (final p in positionen) {
    if (p.tip == ReceiptDueTipRecipient.staff) {
      personal += p.amount * p.priceOne;
    } else {
      final n = _topfFuerSatz(p.vat);
      t[n] = t[n]! + p.priceOne * p.amount;
    }
  }
  final gesamt = t[_standard]! + t[_reduced1]! + t[_reduced2]! + t[_zero]! + t[_special]!;

  if (gutscheine.isNotEmpty) {
    var rabatt = 0.0;
    for (final v in gutscheine) {
      if (v.action == VoucherAction.redeem && v.type == VoucherType.promo) rabatt += v.value;
    }
    final nutzbarCents = _euroToCent(rabatt > gesamt ? gesamt : rabatt);
    final cents = [for (final n in _fuenf) _euroToCent(t[n]!)];
    final basis = cents.fold<int>(0, (s, c) => s + c);
    final anteil = List<int>.filled(cents.length, 0);
    if (basis > 0 && nutzbarCents > 0) {
      for (var i = 0; i < cents.length; i++) {
        anteil[i] = ((nutzbarCents * cents[i]) / basis).floor();
      }
      final rest = nutzbarCents - anteil.fold<int>(0, (s, a) => s + a);
      if (rest > 0) {
        // Groesster Topf; bei Gleichstand der erste.
        var groesster = 0;
        for (var i = 1; i < cents.length; i++) {
          if (cents[i] > cents[groesster]) groesster = i;
        }
        if (cents[groesster] > 0) anteil[groesster] += rest;
      }
    }
    for (var i = 0; i < _fuenf.length; i++) {
      t[_fuenf[i]] = (cents[i] - anteil[i]) / 100;
    }
  }
  t[_zero] = t[_zero]! + personal;
  var delta = 0;
  for (final n in _alleToepfe) {
    delta += _euroToCent(t[n]!);
  }
  return (toepfe: t, zaehlerDeltaCents: delta);
}

/// `payments-core.wertgutscheinFlussCents`.
int _wertgutscheinFlussCents(List<_Gutschein> gutscheine, ReceiptType art) {
  final vz = art == ReceiptType.cancellation ? -1 : 1;
  var cents = 0;
  for (final v in gutscheine) {
    if (v.type != VoucherType.value || !v.value.isFinite) continue;
    final c = _euroToCent(v.value);
    if (v.action == VoucherAction.sell) {
      cents += c;
    } else if (v.action == VoucherAction.redeem) {
      cents -= c;
    }
  }
  return vz * cents;
}
