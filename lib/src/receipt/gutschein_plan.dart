/// Gutscheine der neuen Form im Zahlbetrag: Zwilling von `receipt/gutschein-plan.ts`
/// im npm-Paket und damit von `gutschein-beleg.plane` im Backend, soweit er
/// den Zahlbetrag bestimmt. Nur paketintern; oeffentlich ist allein, was
/// `due.dart` zeigt.
///
/// Der Server macht aus den Wuenschen zusaetzliche Positionen (`kind`
/// `voucher` bzw. `voucher_float`, hinten an Ware und Trinkgeld angehaengt, in
/// der Reihenfolge der Wuensche) und Eintraege in Belegform; nur Eintraege der
/// Art Wert (`value`) und Rabatt (`promo`) gehen danach in die Toepfe und in
/// den Wertgutschein-Fluss (`gutschein-beleg.zahlbetrag`). Genau das steht
/// hier, mit derselben Euro-Arithmetik (IEEE-Doubles wie in JavaScript, in
/// derselben Reihenfolge):
///
/// - Mehrzweck einloesen: Eintrag `value`, mindert den Zahlbetrag als Fluss.
/// - Mehrzweck verkaufen: Eintrag `value` (+Fluss); ab dem Stichtag des
///   0-%-Topfs stattdessen Position im 0-%-Satz ohne Fluss.
/// - Mehrzweck auszahlen: immer Position im 0-%-Satz (minus), kein Fluss.
/// - Einzweck: Position im Satz (Verkauf aus der Einstellung der Kasse,
///   Einloesung und Auszahlung aus der Pruefung des Gutscheins); als
///   Kleinunternehmer bzw. befreit verkauft eingeloest anteilig auf alle
///   Saetze des Korbs.
/// - Leistung verkaufen: Stueck mal Artikelpreis im Artikelsatz; einloesen: je
///   Satz eine Minuszeile ueber die gewaehlten Positionen.
/// - Aktion: Rabatt wie `promo`, Betrag aus der Pruefung, hoechstens die Summe.
///
/// Kein Fehler wird still geschluckt: was der Server mit einem Gutschein-Code
/// abwiese, liefert [PlanFehler] mit genau diesem Code (`voucher_*`). Der
/// Klartext-Code steht nie in einem Text.
library;

import 'package:kreiseck_validator/kreiseck_validator.dart' show Valid, VoucherCode;

import '../../enums/voucher_action.dart';
import '../../enums/voucher_type.dart';
import '../../models/keck_voucher.dart';
import '../kasse/gutschein.dart';

/// Stichtag des 0-%-Topfs fuer Mehrzweck-Verkaeufe (Backend
/// `gutschein-core.NULLTOPF_AB`).
const String nullTopfAb = '2099-12-31';

/// `Math.round` aus JavaScript: naechste ganze Zahl, halbe Werte Richtung plus
/// unendlich. Der Nachkommaanteil `x - floor(x)` ist bei Doubles exakt.
double jsRound(double x) {
  if (!x.isFinite) return x;
  final unten = x.floorToDouble();
  return x - unten >= 0.5 ? unten + 1 : unten;
}

/// Wer eine Trinkgeld-Position bekommt; `null` fuer jede andere Position.
enum TrinkgeldArt { owner, staff }

/// Position in der inneren Form des Backends (`beleg-toepfe.interneForm`).
class Innen {
  const Innen(this.amount, this.priceOne, this.vat, this.tip, {this.kind, this.articleId});
  final double amount;
  final double priceOne;
  final double vat;
  final TrinkgeldArt? tip;

  /// `kind` der Position (Trinkgeld, Rabatt, Gutscheinzeile); Ware hat keines.
  final String? kind;
  final String? articleId;
}

/// Gutschein-Eintrag in Belegform, soweit Toepfe und Fluss ihn lesen.
class PlanGutschein {
  PlanGutschein(this.action, this.type, this.value, {this.imNullTopf = false});
  final VoucherAction action;

  /// [VoucherType.value] oder [VoucherType.promo] (Belegform).
  final VoucherType type;
  final double value;

  /// Betrag steht schon als Position im 0-%-Topf: kein Fluss mehr.
  bool imNullTopf;
}

/// Was die Kasse aus ihren Daten mitgibt (siehe `receiptDueCents`).
class PlanOptionen {
  const PlanOptionen({
    this.voucherInfo,
    this.voucherSettings,
    this.voucherArticles,
    this.smallBusiness = false,
    this.zeroRateBucketFrom,
    required this.today,
  });

  final List<({String code, VoucherCheck check})>? voucherInfo;
  final PosVoucherSettings? voucherSettings;
  final List<({String id, int priceCents, int vatRateBp})>? voucherArticles;
  final bool smallBusiness;
  final String? zeroRateBucketFrom;

  /// Wiener Tag `YYYY-MM-DD`.
  final String today;
}

class Plan {
  const Plan(this.zusatz, this.gutscheine, this.auszahlungCents, this.mitPlan, this.minusJeTopf);

  /// Positionen, die der Server hinten anhaengt.
  final List<Innen> zusatz;

  /// Eintraege, die Toepfe und Fluss lesen (`gutschein-beleg.zahlbetrag`).
  final List<PlanGutschein> gutscheine;

  /// Summe der Auszahlungen in Cent.
  final int auszahlungCents;

  /// Mindestens ein Wunsch der neuen Form: der Server rechnet mit `plane`.
  final bool mitPlan;

  /// Summe der Einloese-Minuszeilen je Topf (Deckung, Vorbelegung).
  final Map<String, int> minusJeTopf;
}

class PlanFehler implements Exception {
  const PlanFehler(this.fehler, this.text);

  /// Der Code, mit dem der Server abwiese (`voucher_*`).
  final String fehler;
  final String text;
}

const topfStandard = 'amountRateStandard';
const topfReduced1 = 'amountRateReduced1';
const topfReduced2 = 'amountRateReduced2';
const topfZero = 'amountRateZero';
const topfSpecial = 'amountRateSpecial';
const topfOthers = 'amountRatOthers';
const topfReihenfolge = [topfStandard, topfReduced1, topfReduced2, topfZero, topfSpecial, topfOthers];

/// `vat-buckets.bucketFuerSatz`.
String topfFuerSatz(double vat) {
  if (vat == 20) return topfStandard;
  if (vat == 10) return topfReduced1;
  if (vat == 13) return topfReduced2;
  if (vat == 0) return topfZero;
  if (vat == 19 || vat == 4.9) return topfSpecial;
  return topfOthers;
}

bool _istGutscheinZeile(Innen p) => p.kind == 'voucher' || p.kind == 'voucher_float';

/// Position, die ein Gutschein decken darf: weder Trinkgeld noch Gutscheinzeile.
bool istDeckbar(Innen p) => p.tip == null && p.kind != 'tip' && !_istGutscheinZeile(p);

/// Wie beleg-toepfe: Euro in Positionsreihenfolge aufsummieren, erst die Summe auf Cent runden.
int centSumme(Iterable<Innen> liste) {
  var s = 0.0;
  for (final it in liste) {
    s = s + it.priceOne * it.amount;
  }
  return jsRound(s * 100).toInt();
}

/// `gutschein-core.satzBpAusVat`.
int _satzBp(double vat) => jsRound(vat * 100).toInt();

Innen _position(int satzBp, int cents, String kind) => Innen(1, cents / 100, satzBp / 100, null, kind: kind);

/// Code in Normalform (tolerant eingelesen, Pruefzeichen stimmt) oder `null`.
String? normalerCode(String? code) {
  if (code == null) return null;
  final v = VoucherCode.validate(code);
  return v is Valid ? v.normalized : null;
}

/// Ein Wunsch der neuen Form (nicht vom Server gelesen)?
bool _istWunsch(KeckVoucher v) => v.isNewForm && v.serverFields.isEmpty;

/// Ein gelesener Eintrag (Serverfelder gesetzt).
bool _istGelesen(KeckVoucher v) => v.serverFields.isNotEmpty;

const _statusFehler = {
  VoucherStatus.usedUp: 'voucher_used_up',
  VoucherStatus.paidOut: 'voucher_used_up',
  VoucherStatus.cancelled: 'voucher_cancelled',
  VoucherStatus.blocked: 'voucher_blocked',
  VoucherStatus.expired: 'voucher_expired',
};

Map<int, List<Innen>> _jeSatz(Iterable<Innen> liste) {
  final jeSatz = <int, List<Innen>>{};
  for (final it in liste) {
    (jeSatz[_satzBp(it.vat)] ??= []).add(it);
  }
  return jeSatz;
}

/// Summe, die `kuTeile` hoechstens verteilt: je Satz `centSumme` der deckbaren Positionen, nur positive.
int kuBasisCents(List<Innen> kunde) =>
    _jeSatz(kunde.where(istDeckbar)).values.map(centSumme).where((c) => c > 0).fold(0, (a, b) => a + b);

/// `gutschein-core.kuTeile`: anteilig zur Positionssumme je Satz, groesster
/// Rest, Topf-Reihenfolge bei Gleichstand. `null`, wenn der Korb den Betrag
/// nicht deckt.
List<({int satzBp, int cents})>? _kuTeile(List<Innen> kunde, int betragCents) {
  int rang(int s) => topfReihenfolge.indexOf(topfFuerSatz(s / 100));
  final saetze = [
    for (final MapEntry(key: s, value: liste) in _jeSatz(kunde.where(istDeckbar)).entries)
      (satzBp: s, basis: centSumme(liste)),
  ].where((s) => s.basis > 0).toList()
    // Jeder Satz kommt einmal vor: die Ordnung ist vollstaendig, die (nicht
    // stabile) Sortierung von Dart ergibt dieselbe Folge wie JavaScript.
    ..sort((a, b) {
      final r = rang(a.satzBp) - rang(b.satzBp);
      return r != 0 ? r : b.satzBp - a.satzBp;
    });
  final summe = saetze.fold(0, (s, x) => s + x.basis);
  if (summe <= 0 || betragCents > summe) return null;
  final cents = [for (final s in saetze) (betragCents * s.basis) ~/ summe];
  final rest = [for (final s in saetze) (betragCents * s.basis) % summe];
  var offen = betragCents - cents.fold(0, (s, c) => s + c);
  final nachRest = [for (var i = 0; i < saetze.length; i++) i]
    ..sort((a, b) {
      final r = rest[b] - rest[a];
      return r != 0 ? r : a - b;
    });
  for (var k = 0; offen > 0; k++, offen--) {
    cents[nachRest[k]] += 1;
  }
  return [
    for (var i = 0; i < saetze.length; i++)
      if (cents[i] > 0) (satzBp: saetze[i].satzBp, cents: cents[i]),
  ];
}

/// Wuensche und gelesene Eintraege in Positionen und Belegeintraege, wie
/// `plane` sie baut. [kunde] sind Ware und Trinkgeld in innerer Form. Wirft
/// [PlanFehler] mit dem Code des Servers.
Plan planeGutscheine(List<Innen> kunde, List<KeckVoucher> vouchers, {required bool storno, required bool training, required PlanOptionen o}) {
  final wuensche = vouchers.where(_istWunsch).toList();
  final zusatz = <Innen>[];
  final gutscheine = <PlanGutschein>[];

  // Wert und Rabatt der Altform bzw. gelesener Belege: Euro aus ganzen Cent.
  PlanGutschein altEintrag(KeckVoucher v, int i) {
    final c = v.valueCents;
    if (c == null) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1} hat keinen ganzen Cent-Wert.');
    return PlanGutschein(v.action, v.type, c / 100, imNullTopf: v.zeroRateBucket == true);
  }

  if (wuensche.isEmpty) {
    final nulltopf = !storno && o.today.compareTo(o.zeroRateBucketFrom ?? nullTopfAb) >= 0;
    // `gutschein-transaktion.brauchtPlan`: ab dem Stichtag laeuft plane auch fuer einen Altform-Verkauf.
    final mitPlan = nulltopf &&
        vouchers.any((v) => !_istGelesen(v) && v.action == VoucherAction.sell && v.type == VoucherType.value);
    if (mitPlan && kunde.any(_istGutscheinZeile)) throw const PlanFehler('voucher_invalid', 'Gutschein-Positionen setzt nur der Server.');
    for (final (i, v) in vouchers.indexed) {
      // Gelesene Eintraege der neuen Form ohne Wert/Rabatt: ihr Geld steht in den Positionen.
      if (_istGelesen(v) && v.type != VoucherType.value && v.type != VoucherType.promo) continue;
      final g = altEintrag(v, i);
      // Altform-Verkauf ab dem Stichtag: Betrag in den 0-%-Topf.
      if (nulltopf && !_istGelesen(v) && g.action == VoucherAction.sell && g.type == VoucherType.value) {
        zusatz.add(_position(0, v.valueCents!, 'voucher_float'));
        g.imNullTopf = true;
      }
      gutscheine.add(g);
    }
    return Plan(zusatz, gutscheine, 0, mitPlan, const {});
  }

  // Ab hier: mindestens ein Wunsch der neuen Form (createReceipt fuehrt `plane` aus).
  if (storno) throw const PlanFehler('voucher_invalid', 'Gutscheine der neuen Form gibt es am Storno nur gespiegelt vom Server.');
  if (training) throw const PlanFehler('voucher_invalid', 'Gutscheine der neuen Form gibt es nicht auf Schulungsbelegen.');
  if (kunde.any(_istGutscheinZeile)) throw const PlanFehler('voucher_invalid', 'Gutschein-Positionen setzt nur der Server.');
  for (final (i, v) in vouchers.indexed) {
    if (_istGelesen(v)) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: Serverfelder an einem Wunsch.');
    if (v.isNewForm && !v.isValid) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1} ist unvollstaendig.');
  }
  // Kein Gutschein mit Gutschein bezahlen, sobald einer der beiden die neue Form hat.
  final handel = vouchers.where((v) => v.action == VoucherAction.sell || v.action == VoucherAction.redeem).toList();
  if (handel.any((v) => v.action == VoucherAction.sell) &&
      handel.any((v) => v.action == VoucherAction.redeem) &&
      handel.any((v) => v.isNewForm)) {
    throw const PlanFehler('voucher_invalid', 'Gutscheine verkaufen und einloesen gehen nicht am selben Beleg.');
  }
  if (wuensche.any((v) => v.type == VoucherType.promotion) && vouchers.length > 1) {
    throw const PlanFehler('voucher_invalid', 'Ein Aktionsgutschein steht allein am Beleg.');
  }
  if (wuensche.any((v) => v.action == VoucherAction.payout) && vouchers.any((v) => !v.isNewForm && v.type == VoucherType.promo)) {
    throw const PlanFehler('voucher_invalid', 'Rabatt und Auszahlung gehen nicht am selben Beleg.');
  }
  final codes = [
    for (final v in wuensche)
      if (v.action != VoucherAction.sell) normalerCode(v.code),
  ];
  if (codes.any((c) => c == null)) throw const PlanFehler('voucher_invalid', 'Ein Gutscheincode ist ungueltig.');
  if (codes.toSet().length != codes.length) throw const PlanFehler('voucher_invalid', 'Derselbe Gutschein steht zweimal am Beleg.');

  final ku = o.smallBusiness;
  final nulltopf = o.today.compareTo(o.zeroRateBucketFrom ?? nullTopfAb) >= 0;
  final minusJeTopf = <String, int>{};
  void minus(int s, int c) {
    final topf = topfFuerSatz(s / 100);
    minusJeTopf[topf] = (minusJeTopf[topf] ?? 0) + c;
  }

  final belegt = <int>{};
  var auszahlungCents = 0;

  void einstellung(VoucherType gewollt) {
    final e = o.voucherSettings;
    // Der Server verkauft nur mit bestaetigter Einstellung (`voucher_settings_missing`), auch Mehrzweck.
    if (e == null || e.valueVoucherType == null) {
      throw const PlanFehler('voucher_settings_missing', 'Die Gutschein-Einstellung der Kasse fehlt (voucherSettings).');
    }
    if (e.valueVoucherType != gewollt) {
      throw const PlanFehler('voucher_invalid', 'Die Gutschein-Einstellung der Kasse verkauft eine andere Art.');
    }
  }

  VoucherCheck pruefung(KeckVoucher v, int i) {
    final code = normalerCode(v.code);
    for (final info in o.voucherInfo ?? const <({String code, VoucherCheck check})>[]) {
      if (normalerCode(info.code) != code) continue;
      if (info.check.type != v.type) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: die Art passt nicht zur Pruefung.');
      return info.check;
    }
    throw PlanFehler('voucher_not_found', 'Gutschein ${i + 1}: keine Pruefung zum Code (checkVoucher).');
  }

  void saldo(VoucherCheck check, int c, int i) {
    final b = check.balanceCents;
    if (b == null || c > b) throw PlanFehler('voucher_insufficient_balance', 'Gutschein ${i + 1}: der Betrag uebersteigt den Saldo.');
  }

  for (final (i, v) in vouchers.indexed) {
    if (!v.isNewForm) {
      final g = altEintrag(v, i);
      if (nulltopf && g.action == VoucherAction.sell && g.type == VoucherType.value) {
        zusatz.add(_position(0, v.valueCents!, 'voucher_float'));
        g.imNullTopf = true;
      }
      gutscheine.add(g);
      continue;
    }
    if (!v.type.isNewForm) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: unbekannte Art.');

    if (v.action == VoucherAction.sell) {
      if (v.type == VoucherType.multiPurpose) {
        einstellung(VoucherType.multiPurpose);
        final c = v.amountCents!;
        if (nulltopf) {
          zusatz.add(_position(0, c, 'voucher_float'));
          gutscheine.add(PlanGutschein(VoucherAction.sell, VoucherType.value, c / 100, imNullTopf: true));
        } else {
          gutscheine.add(PlanGutschein(VoucherAction.sell, VoucherType.value, c / 100));
        }
      } else if (v.type == VoucherType.singlePurpose) {
        einstellung(VoucherType.singlePurpose);
        final satz = ku ? 0 : o.voucherSettings!.vatRateBp;
        if (satz == null || satz < 0) {
          throw const PlanFehler('voucher_settings_missing', 'Der Satz des Einzweckgutscheins fehlt (Gutschein-Einstellung der Kasse).');
        }
        zusatz.add(_position(satz, v.amountCents!, 'voucher'));
      } else {
        ({String id, int priceCents, int vatRateBp})? a;
        for (final x in o.voucherArticles ?? const <({String id, int priceCents, int vatRateBp})>[]) {
          if (x.id == v.articleId) {
            a = x;
            break;
          }
        }
        if (a == null) throw PlanFehler('voucher_item_mismatch', 'Gutschein ${i + 1}: der Artikel fehlt (voucherArticles).');
        if (a.priceCents <= 0 || a.vatRateBp < 0) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: Artikel ohne Preis oder Satz.');
        final c = v.quantity! * a.priceCents;
        if (c > 1000000) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: Betrag zu hoch.');
        zusatz.add(_position(ku ? 0 : a.vatRateBp, c, 'voucher'));
      }
      continue;
    }

    final check = pruefung(v, i);

    if (v.action == VoucherAction.payout) {
      // `gutschein-core.darfAuszahlen`: aktiv, oder abgelaufen bis zum Ende der Rueckzahlbarkeit.
      if (!((check.balanceCents ?? 0) > 0)) throw PlanFehler('voucher_used_up', 'Gutschein ${i + 1}: kein Saldo.');
      if (check.status == VoucherStatus.expired) {
        final bis = check.validity?.refundableUntil;
        if (bis != null && bis.isNotEmpty && o.today.compareTo(bis) > 0) {
          throw PlanFehler('voucher_expired', 'Gutschein ${i + 1}: nicht mehr rueckzahlbar.');
        }
      } else if (check.status != VoucherStatus.active) {
        throw PlanFehler(_statusFehler[check.status] ?? 'voucher_invalid', 'Gutschein ${i + 1}: Status ${check.status.wire}.');
      }
      final c = v.amountCents!;
      saldo(check, c, i);
      if (v.type == VoucherType.multiPurpose) {
        zusatz.add(_position(0, -c, 'voucher_float'));
        gutscheine.add(PlanGutschein(VoucherAction.payout, VoucherType.value, c / 100, imNullTopf: true));
      } else {
        final satz = check.vatRateBp;
        if (satz == null) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: Satz fehlt in der Pruefung.');
        zusatz.add(_position(satz, -c, 'voucher'));
      }
      auszahlungCents += c;
      continue;
    }

    if (check.status != VoucherStatus.active) {
      throw PlanFehler(_statusFehler[check.status] ?? 'voucher_invalid', 'Gutschein ${i + 1}: Status ${check.status.wire}.');
    }

    if (v.type == VoucherType.multiPurpose || v.type == VoucherType.singlePurpose) {
      final c = v.amountCents!;
      saldo(check, c, i);
      if (v.type == VoucherType.multiPurpose) {
        gutscheine.add(PlanGutschein(VoucherAction.redeem, VoucherType.value, c / 100));
      } else if (check.exempt == true || ku) {
        // Befreit verkauft (`kuEingefroren`) oder Kleinunternehmer-Konto: der gedeckte Teil
        // verlaesst anteilig alle Toepfe des Korbs.
        final teile = _kuTeile(kunde, c);
        if (teile == null) throw PlanFehler('voucher_rate_mismatch', 'Gutschein ${i + 1}: der Korb deckt den Betrag nicht.');
        for (final t in teile) {
          zusatz.add(_position(t.satzBp, -t.cents, 'voucher'));
          minus(t.satzBp, t.cents);
        }
      } else {
        final satz = check.vatRateBp;
        if (satz == null) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: Satz fehlt in der Pruefung.');
        zusatz.add(_position(satz, -c, 'voucher'));
        minus(satz, c);
      }
    } else if (v.type == VoucherType.service) {
      final artikelId = check.article?.id;
      var stueck = 0.0;
      final jeSatz = <int, List<Innen>>{};
      for (final k in v.positions ?? const <int>[]) {
        final it = k < kunde.length ? kunde[k] : null;
        if (it == null ||
            it.kind != null ||
            it.tip != null ||
            artikelId == null ||
            artikelId.isEmpty ||
            it.articleId != artikelId ||
            it.amount != it.amount.truncateToDouble() ||
            it.amount < 1 ||
            belegt.contains(k)) {
          throw PlanFehler('voucher_item_mismatch', 'Gutschein ${i + 1}: Position ${k + 1} passt nicht zum Leistungsgutschein.');
        }
        belegt.add(k);
        stueck += it.amount;
        (jeSatz[_satzBp(it.vat)] ??= []).add(it);
      }
      final offen = check.remainingQuantity;
      if (offen == null || stueck > offen) {
        throw PlanFehler('voucher_insufficient_balance', 'Gutschein ${i + 1}: nicht genug offene Stueck.');
      }
      for (final MapEntry(key: s, value: liste) in jeSatz.entries) {
        final c = centSumme(liste);
        zusatz.add(_position(s, -c, 'voucher'));
        minus(s, c);
      }
    } else {
      // Aktion: Rabatt ueber die Altmechanik promo.
      final basis = centSumme(kunde.where(istDeckbar));
      final betrag = check.discountCents;
      final roh = betrag != null && betrag > 0 ? betrag : ((basis * (check.discountPercentBp ?? 0)) / 10000).floor();
      final rabatt = roh < basis ? roh : basis;
      if (!(rabatt > 0)) throw PlanFehler('voucher_invalid', 'Gutschein ${i + 1}: kein Rabatt auf diesen Korb.');
      gutscheine.add(PlanGutschein(VoucherAction.redeem, VoucherType.promo, rabatt / 100));
    }
  }

  // Einloese-Minuszeilen eines Topfs uebersteigen nie die deckbaren Positionen dieses Topfs.
  for (final MapEntry(key: topf, value: c) in minusJeTopf.entries) {
    final basis = centSumme(kunde.where((it) => istDeckbar(it) && topfFuerSatz(it.vat) == topf));
    if (c > basis) throw const PlanFehler('voucher_rate_mismatch', 'Ein Gutschein deckt mehr als die Positionen seines Steuersatzes.');
  }
  return Plan(zusatz, gutscheine, auszahlungCents, true, minusJeTopf);
}
