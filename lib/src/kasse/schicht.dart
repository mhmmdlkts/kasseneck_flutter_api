/// Schicht, Kassenstand und Lade-Protokoll an der Kasse: Kataloge, Modelle und
/// Helfer. Zwilling von `pos/schicht-typen.ts`, `pos/schicht-lesen.ts` und den
/// Helfern aus `pos/schicht.ts` im JS-Paket (npm 1.9.0); die sechs Aufrufe
/// stehen an [RegisterReceiptClient] (`belege.dart`).
///
/// **Fehlt ein Feld, fehlt das Recht.** Ohne `cashView` sendet der Server kein
/// Soll, kein Ist, keinen Laufstand und keinen Vorschlag (Blindzaehlung); im
/// Modell sind diese Felder dann `null`, nie `0`. Auf dem Bon
/// ([ShiftSummaryReceipt]) stehen dieselben Werte blind ebenfalls als `null`.
/// Wo `null` am Draht etwas Eigenes heisst (offene Schicht: kein Ist), steht es
/// im Feld dazu.
///
/// Alle Betraege in Cent (Ganzzahl, Vorzeichen wie gebucht), Zeiten als
/// ISO 8601 (UTC), Stueckelung als Karte „Wert in Cent“ -> Anzahl.
///
/// Leseregel wie beim Lager: ein Betrag, eine Anzahl oder eine Nummer ist eine
/// Ganzzahl, eine Kennung ein nicht leerer Text, sonst endet der Aufruf mit
/// [KasseneckValidationError] (`kind: response`). Ein Ersatzwert wie `0` waere
/// eine falsche Aussage („nichts in der Lade“ statt „Antwort kaputt“). Texte
/// sind nachsichtiger: ein fehlender oder fremder Wert wird `null`.
library;

import 'dart:math';

import '../lager/lesen.dart' show ganzzahlVon, objekt;
import '../register/fehler.dart';
import 'lager.dart' show jsTrim;
import 'texte.dart' show labelText;

// ---- Kataloge -----------------------------------------------------------------

/// Scheine und Muenzen in Euro-Cent, vom groessten Schein abwaerts (Backend
/// `EUR_STUECKELUNG`).
const List<int> eurDenominations = [50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1];

/// Alle Arten einer Kassenbewegung (Katalog `KASSEN_BEWEGUNG_ART`). Die ersten
/// acht sendet die Kasse ([manualMovementTypes]); `transfer_in` (Gegenseite
/// einer Umbuchung), `expense`, `count_difference` und `handover_difference`
/// vergibt nur der Server.
const List<String> movementTypes = [
  'change_in',
  'cash_drop',
  'owner_deposit',
  'owner_withdrawal',
  'tip_payout',
  'other_in',
  'other_out',
  'transfer_out',
  'transfer_in',
  'expense',
  'count_difference',
  'handover_difference',
];

/// Was die Kasse von Hand buchen darf. Pflichtangaben je Art (sonst lehnt der
/// Server ab): `note` bei `other_in`/`other_out`, `recipientId` bei
/// `tip_payout`, `targetDrawerId` bei `transfer_out`. `location` bei
/// `change_in`/`cash_drop` ist freiwillig.
const List<String> manualMovementTypes = [
  'change_in',
  'cash_drop',
  'owner_deposit',
  'owner_withdrawal',
  'tip_payout',
  'other_in',
  'other_out',
  'transfer_out',
];

/// Woher Wechselgeld kommt bzw. wohin abgeschoepft wird (Katalog `KASSEN_ORT`).
const List<String> cashLocations = ['bank', 'safe'];

/// Warum die Lade aufging (Katalog `LADE_OEFFNUNG_GRUND`). `sale`,
/// `cash_movement`, `shift_open` und `shift_close` meldet die Kasse selbst beim
/// jeweiligen Vorgang; von Hand waehlt der Kassier aus [manualOpeningReasons].
const List<String> openingReasons = [
  'sale',
  'cash_movement',
  'shift_open',
  'shift_close',
  'change',
  'check',
  'misoperation',
  'other',
];

/// Die Gruende des Knopfs „Lade“; `other` braucht einen Text (`note`).
const List<String> manualOpeningReasons = ['change', 'check', 'misoperation', 'other'];

/// Arten der Bon-Daten (Katalog `SCHICHT_BON_ART`): Z-Bon, X-Bon, Kassenbewegung.
const List<String> shiftReceiptKinds = ['shift_close', 'shift_interim', 'cash_movement'];

// ---- Helfer der Kasse ----------------------------------------------------------

const int _anzahlMax = 100000;
final Set<String> _werte = {for (final w in eurDenominations) '$w'};

/// Summe einer Stueckelung in Cent, oder `null`, wenn sie keine ist: [denominations]
/// ist keine Abbildung, ein Schluessel ist kein Euro-Wert ([eurDenominations],
/// genau so geschrieben, `"500"`, nicht `"0500"`), eine Anzahl ist keine ganze
/// Zahl von 0 bis 100 000. Dieselbe Regel wie am Server (`invalid_denominations`).
/// Schluessel duerfen Text oder Zahl sein. Gemeinsame Faelle mit dem JS-Zwilling:
/// `shift-cases.json` des Vertrags.
int? sumDenominations(Object? denominations) {
  if (denominations is! Map) return null;
  var summe = 0;
  for (final e in denominations.entries) {
    final k = e.key;
    if (k is! String && k is! int) return null;
    final wert = '$k';
    if (!_werte.contains(wert)) return null;
    final v = e.value;
    if (v is! num) return null;
    final n = ganzzahlVon(v);
    if (n == null || n < 0 || n > _anzahlMax) return null;
    summe += int.parse(wert) * n;
  }
  return summe;
}

final RegExp _betragMuster = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$');
final BigInt _groessteSichere = BigInt.from(9007199254740991);

/// Ein eingetippter Betrag in Cent, **ohne Gleitkomma**: `'12,5'` -> `1250`,
/// `'0'` -> `0` (anders als beim Kassieren ist 0 hier gueltig: eine leere Lade,
/// kein Startgeld). Dezimaltrenner Komma oder Punkt mit einer oder zwei
/// Nachkommastellen; `null` fuer leer, Vorzeichen, Tausendertrenner
/// (`'1.000'`, `'1 000'`), drei Nachkommastellen, Euro-Zeichen und alles ueber
/// einer sicheren Ganzzahl. Leerraum aussen faellt weg wie bei
/// `String.prototype.trim` in JS. Gemeinsame Faelle mit dem JS-Zwilling:
/// `shift-cases.json` des Vertrags.
int? parseCentsAllowZero(String text) {
  final m = _betragMuster.firstMatch(jsTrim(text));
  if (m == null) return null;
  final cents = BigInt.parse(m[1]!) * BigInt.from(100) + BigInt.parse((m[2] ?? '').padRight(2, '0'));
  return cents <= _groessteSichere ? cents.toInt() : null;
}

final Random _zufall = Random.secure();

/// Ein frischer Idempotenzschluessel fuer einen neuen Vorgang: `kasse-` und 32
/// Hex-Zeichen aus dem sicheren Zufall, dieselbe Form wie beim Zaehlen der
/// Inventur. Fuer „Erneut senden“ nie einen neuen ziehen, sondern den alten
/// behalten.
String newIdempotencyKey() {
  final b = StringBuffer('kasse-');
  for (var i = 0; i < 16; i++) {
    b.write(_zufall.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

// ---- Modelle -------------------------------------------------------------------

/// Wer gehandelt hat: Kassen-Benutzer (`register_user`), Inhaber (`owner`,
/// Panel) oder Admin.
class ShiftActor {
  const ShiftActor({this.registerUserId, this.name, required this.role});

  final String? registerUserId;
  final String? name;

  /// `register_user`, `owner`, `admin` oder ein kuenftiger Wert.
  final String role;

  Map<String, dynamic> toJson() => {'registerUserId': registerUserId, 'name': name, 'role': role};
}

class DrawerInfo {
  const DrawerInfo({required this.id, this.name, required this.shiftMode, this.cashregisterId});

  final String id;
  final String? name;

  /// Schichtbetrieb: verkauft wird erst nach dem Oeffnen einer Schicht.
  final bool shiftMode;
  final String? cashregisterId;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'shiftMode': shiftMode, 'cashregisterId': cashregisterId};
}

/// Die vier Rechte des angemeldeten Benutzers an der Lade.
class DrawerRights {
  const DrawerRights({required this.shift, required this.cashMove, required this.cashView, required this.drawer});

  /// Schicht oeffnen und schliessen.
  final bool shift;

  /// Ein- und Auszahlungen buchen.
  final bool cashMove;

  /// Soll, Ist und Differenz sehen; ohne dieses Recht wird blind gezaehlt.
  final bool cashView;

  /// Die Lade von Hand oeffnen (mit Grund).
  final bool drawer;

  Map<String, dynamic> toJson() => {'shift': shift, 'cashMove': cashMove, 'cashView': cashView, 'drawer': drawer};
}

class NonCashAmount {
  const NonCashAmount({required this.method, required this.cents});

  /// Zahlart, wie am Beleg (`card` ...).
  final String method;
  final int cents;

  Map<String, dynamic> toJson() => {'method': method, 'cents': cents};
}

class ShiftTipTotals {
  const ShiftTipTotals({
    required this.registerUserId,
    this.name,
    required this.receivedImmediatelyCents,
    required this.retainedCents,
    required this.paidOutCents,
    this.refundedByEmployeeCents = 0,
  });

  final String registerUserId;
  final String? name;

  /// Steht dem Mitarbeiter aus der Lade zu (bar oder Karte am Terminal des Betriebs).
  final int receivedImmediatelyCents;

  /// Behaelt der Betrieb und zahlt es ueber den Lohn („über Lohn“).
  final int retainedCents;

  /// In dieser Schicht aus der Lade ausgezahlt („schon genommen“).
  final int paidOutCents;

  /// Beim Storno selbst zurueckgegeben („selbst zurückgegeben“, Fix-Runde 1,
  /// R62). Eigene Zahl, damit „schon genommen“ nie negativ wird: offen =
  /// verdient − genommen + selbst zurueckgegeben. Fehlt es in der Antwort
  /// (Backend vor dieser Regel), gilt 0.
  final int refundedByEmployeeCents;

  Map<String, dynamic> toJson() => {
        'registerUserId': registerUserId,
        'name': name,
        'receivedImmediatelyCents': receivedImmediatelyCents,
        'retainedCents': retainedCents,
        'paidOutCents': paidOutCents,
        'refundedByEmployeeCents': refundedByEmployeeCents,
      };
}

/// Trinkgeld eines Mitarbeiters mit seinem offenen Anspruch an die Lade
/// ([openCents], „offen“): im Kassenstand ([DrawerState.tips]) und auf dem Z-
/// und X-Bon. Was davon gezeigt wird, sagt [shiftTipLines].
class ShiftTip extends ShiftTipTotals {
  const ShiftTip({
    required super.registerUserId,
    super.name,
    required super.receivedImmediatelyCents,
    required super.retainedCents,
    required super.paidOutCents,
    super.refundedByEmployeeCents,
    this.carriedOverCents = 0,
    required this.openCents,
  });

  /// Offene Forderung an die Lade beim Oeffnen der Schicht („aus früheren
  /// Schichten“, Fix-Runde 2, R64); ohne offene Schicht der ganze Anspruch.
  /// Fehlt es, 0. Fuer den Leser geht auf: offen = aus frueheren Schichten +
  /// verdient − ueber Lohn − schon genommen + selbst zurueckgegeben.
  final int carriedOverCents;

  final int openCents;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'carriedOverCents': carriedOverCents, 'openCents': openCents};
}

/// Trinkgeld auf dem Z- und X-Bon: offen = Anspruch beim Abschluss bzw. jetzt.
typedef ShiftReceiptTip = ShiftTip;

/// Eine Zeile des Trinkgelds eines Mitarbeiters (siehe [shiftTipLines]).
class ShiftTipLine {
  const ShiftTipLine({required this.key, required this.text, required this.cents});

  /// `shift_receipt.tip_earned`, `tip_retained`, `tip_paid_out` oder `tip_open`.
  final String key;

  /// Das Wort aus dem Katalog ([labelText]).
  final String text;
  final int cents;
}

/// Was vom Trinkgeld eines Mitarbeiters dasteht, auf dem Bon, im Kassenstand
/// und beim Abschluss gleich (Rulings R50/R51): „verdient“ (sofort + ueber
/// Lohn) immer, „über Lohn“, „schon genommen“, „selbst zurückgegeben“ (R62)
/// und „offen“ nur, wenn nicht 0. Davor „aus früheren Schichten“ (R64, nur
/// wenn nicht 0).
/// Ist alles 0, gibt es keine Zeile, und der Mitarbeiter entfaellt ganz. Ohne
/// `openCents` (Laufstand, [ShiftTipTotals]) zaehlt offen als 0. Gemeinsame
/// Faelle mit dem JS-Zwilling: `shift-cases.json`.
List<ShiftTipLine> shiftTipLines(ShiftTipTotals tip) {
  final verdient = tip.receivedImmediatelyCents + tip.retainedCents;
  final rest = <(String, int)>[
    ('shift_receipt.tip_retained', tip.retainedCents),
    ('shift_receipt.tip_paid_out', tip.paidOutCents),
    ('shift_receipt.tip_refunded_by_employee', tip.refundedByEmployeeCents),
    ('shift_receipt.tip_open', tip is ShiftTip ? tip.openCents : 0),
  ].where((z) => z.$2 != 0).toList();
  final vortrag = tip is ShiftTip ? tip.carriedOverCents : 0;
  if (verdient == 0 && rest.isEmpty && vortrag == 0) return const [];
  return [
    for (final (key, cents) in [
      if (vortrag != 0) ('shift_receipt.tip_carried_over', vortrag),
      ('shift_receipt.tip_earned', verdient),
      ...rest,
    ])
      ShiftTipLine(key: key, text: labelText(key), cents: cents),
  ];
}

/// Laufstand der Schicht (nur mit `cashView`).
class ShiftRunningTotals {
  const ShiftRunningTotals({
    required this.cashSalesCents,
    required this.cashCancellationsCents,
    required this.nonCashByMethod,
    required this.receiptCount,
    required this.cancellationCount,
    required this.cashInCents,
    required this.cashOutCents,
    required this.tips,
    required this.openingsWithoutSale,
  });

  final int cashSalesCents;
  final int cashCancellationsCents;

  /// Nach Zahlart sortiert.
  final List<NonCashAmount> nonCashByMethod;
  final int receiptCount;
  final int cancellationCount;
  final int cashInCents;
  final int cashOutCents;

  /// Nach Name sortiert.
  final List<ShiftTipTotals> tips;
  final int openingsWithoutSale;

  Map<String, dynamic> toJson() => {
        'cashSalesCents': cashSalesCents,
        'cashCancellationsCents': cashCancellationsCents,
        'nonCashByMethod': [for (final u in nonCashByMethod) u.toJson()],
        'receiptCount': receiptCount,
        'cancellationCount': cancellationCount,
        'cashInCents': cashInCents,
        'cashOutCents': cashOutCents,
        'tips': [for (final t in tips) t.toJson()],
        'openingsWithoutSale': openingsWithoutSale,
      };
}

/// Nachrechnung des Laufstands beim Abschluss: stimmt er, oder welche Felder
/// weichen ab.
class ShiftReconciliation {
  const ShiftReconciliation({required this.matches, this.deviations});

  final bool matches;

  /// Je abweichendem Feld (Name wie in [ShiftRunningTotals]) der gespeicherte
  /// und der nachgerechnete Wert; sonst `null`.
  final Map<String, ({Object? stored, Object? recomputed})>? deviations;

  Map<String, dynamic> toJson() => {
        'matches': matches,
        'deviations': deviations == null
            ? null
            : {for (final e in deviations!.entries) e.key: {'stored': e.value.stored, 'recomputed': e.value.recomputed}},
      };
}

/// Eine Schicht. Die Felder nach „Nur mit `cashView`“ sind `null`, wenn der
/// Server sie nicht sendet (kein Recht); `null` heisst dort „nicht gesendet“
/// oder „es gibt (noch) keinen Wert“ – nie `0`. Ohne das Recht `shift` sendet
/// der Server von einer offenen Schicht nur die Grunddaten ([id], [drawerId],
/// [cashregisterId], [number], [status], [openedAt], [openedBy]); alles
/// andere ist dann `null`, auch [openingFloatTakenOver].
class Shift {
  const Shift({
    required this.id,
    required this.drawerId,
    this.cashregisterId,
    required this.number,
    required this.status,
    this.openedAt,
    this.openedBy,
    this.openedDeviceId,
    this.closedAt,
    this.closedBy,
    this.closedDeviceId,
    this.openingFloatCents,
    this.openingDenominations,
    this.openingFloatTakenOver,
    this.comment,
    this.blind,
    this.countedCents,
    this.suggestedFloatCents,
    this.runningTotals,
    this.expectedCents,
    this.differenceCents,
    this.reconciliation,
  });

  final String id;
  final String drawerId;
  final String? cashregisterId;
  final int number;

  /// `open` oder `closed`.
  final String status;
  final String? openedAt;
  final ShiftActor? openedBy;
  final String? openedDeviceId;
  final String? closedAt;
  final ShiftActor? closedBy;
  final String? closedDeviceId;

  /// Startgeld; blind `null`, wenn es uebernommen wurde.
  final int? openingFloatCents;
  final Map<String, int>? openingDenominations;

  /// Wurde das Startgeld uebernommen; `null` in den Grunddaten ohne Recht `shift`.
  final bool? openingFloatTakenOver;
  final String? comment;

  /// Wurde blind gezaehlt (nach dem Abschluss); offen `null`.
  final bool? blind;

  // Nur mit `cashView`:
  final int? countedCents;
  final int? suggestedFloatCents;
  final ShiftRunningTotals? runningTotals;
  final int? expectedCents;
  final int? differenceCents;
  final ShiftReconciliation? reconciliation;

  /// Die Drahtform; Felder, die fehlen (kein Recht), fehlen auch hier.
  Map<String, dynamic> toJson() => {
        'id': id,
        'drawerId': drawerId,
        'cashregisterId': cashregisterId,
        'number': number,
        'status': status,
        'openedAt': openedAt,
        'openedBy': openedBy?.toJson(),
        'openedDeviceId': openedDeviceId,
        'closedAt': closedAt,
        'closedBy': closedBy?.toJson(),
        'closedDeviceId': closedDeviceId,
        'openingFloatCents': openingFloatCents,
        'openingDenominations': openingDenominations == null ? null : {...openingDenominations!},
        if (openingFloatTakenOver != null) 'openingFloatTakenOver': openingFloatTakenOver,
        'comment': comment,
        'blind': blind,
        if (countedCents != null) 'countedCents': countedCents,
        if (suggestedFloatCents != null) 'suggestedFloatCents': suggestedFloatCents,
        if (runningTotals != null) 'runningTotals': runningTotals!.toJson(),
        if (expectedCents != null) 'expectedCents': expectedCents,
        if (differenceCents != null) 'differenceCents': differenceCents,
        if (reconciliation != null) 'reconciliation': reconciliation!.toJson(),
      };
}

/// Offener Trinkgeld-Anspruch eines Mitarbeiters (auszahlbar beim Abschluss
/// oder per `tip_payout`).
class TipClaim {
  const TipClaim({required this.registerUserId, this.name, required this.cents});

  final String registerUserId;
  final String? name;
  final int cents;

  Map<String, dynamic> toJson() => {'registerUserId': registerUserId, 'name': name, 'cents': cents};
}

/// Eine gemeldete Oeffnung der Lade (nur mit `cashView`).
class DrawerOpening {
  const DrawerOpening({this.at, this.deviceTime, required this.reason, this.byName, required this.ok});

  /// Serverzeit des Eingangs.
  final String? at;

  /// Zeit am Geraet (bei nachgesendeten Oeffnungen frueher als [at]).
  final String? deviceTime;

  /// Ein Wert aus [openingReasons] oder ein kuenftiger.
  final String reason;

  /// Name des Bedieners; `null`, wenn der Server keinen nennt.
  final String? byName;

  /// Ging der Impuls an die Lade durch?
  final bool ok;

  Map<String, dynamic> toJson() => {
        'at': at,
        'deviceTime': deviceTime,
        'reason': reason,
        'by': byName == null ? null : {'name': byName},
        'ok': ok,
      };
}

/// Stand der Lade fuer die Kasse: Lade, Rechte, Schicht und was das Recht
/// `cashView` zeigt.
class DrawerState {
  const DrawerState({
    required this.drawer,
    required this.rights,
    this.shift,
    this.longOpenWarning,
    this.tipClaims = const [],
    this.tips = const [],
    this.suggestedFloatCents,
    this.expectedCents,
    this.recentOpenings,
  });

  final DrawerInfo drawer;
  final DrawerRights rights;

  /// Die offene Schicht; `null` ohne offene Schicht und ohne Recht `shift`.
  final Shift? shift;

  /// Schicht seit mindestens 16 Stunden offen; `null` ohne Recht `shift`.
  final bool? longOpenWarning;
  final List<TipClaim> tipClaims;

  /// Trinkgeld je Mitarbeiter in der laufenden Schicht und offene Ansprueche
  /// (auch aus frueheren Schichten), nach Name; fuer jede Sitzung, auch ohne
  /// `cashView` (Trinkgeld ist kein Bar-Soll). Wer ueberall 0 hat, fehlt.
  final List<ShiftTip> tips;

  /// Vorschlag fuer das Startgeld (letzter Stand); bei offener Schicht `null`.
  /// Nur mit `shift` und `cashView`.
  final int? suggestedFloatCents;

  /// Soll in der Lade; ohne Schicht `null`. Nur mit `shift` und `cashView`.
  final int? expectedCents;

  /// Die letzten Oeffnungen, neueste zuerst; nur mit `cashView`, sonst `null`.
  final List<DrawerOpening>? recentOpenings;

  Map<String, dynamic> toJson() => {
        'drawer': drawer.toJson(),
        'rights': rights.toJson(),
        if (shift != null) 'shift': shift!.toJson(),
        if (longOpenWarning != null) 'longOpenWarning': longOpenWarning,
        'tipClaims': [for (final t in tipClaims) t.toJson()],
        'tips': [for (final t in tips) t.toJson()],
        if (suggestedFloatCents != null) 'suggestedFloatCents': suggestedFloatCents,
        if (expectedCents != null) 'expectedCents': expectedCents,
        if (recentOpenings != null) 'recentOpenings': [for (final o in recentOpenings!) o.toJson()],
      };
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.number,
    this.shiftId,
    required this.type,
    required this.amountCents,
    this.location,
    this.note,
    this.by,
    this.at,
    this.recipient,
    this.counterpart,
  });

  final String id;
  final int number;
  final String? shiftId;

  /// Ein Wert aus [movementTypes] oder ein kuenftiger.
  final String type;

  /// Mit Vorzeichen: Auszahlungen negativ.
  final int amountCents;

  /// `bank` oder `safe`.
  final String? location;
  final String? note;
  final ShiftActor? by;
  final String? at;
  final ({String? registerUserId, String? name})? recipient;

  /// Gegenbuchung einer Umbuchung in der anderen Lade.
  final ({String? drawerId, String? movementId})? counterpart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'shiftId': shiftId,
        'type': type,
        'amountCents': amountCents,
        'location': location,
        'note': note,
        'by': by?.toJson(),
        'at': at,
        'recipient': recipient == null ? null : {'registerUserId': recipient!.registerUserId, 'name': recipient!.name},
        'counterpart':
            counterpart == null ? null : {'drawerId': counterpart!.drawerId, 'movementId': counterpart!.movementId},
      };
}

/// Eine Kassenbewegung auf dem Z- oder X-Bon.
class ShiftReceiptMovement {
  const ShiftReceiptMovement({
    required this.number,
    required this.type,
    required this.amountCents,
    this.note,
    this.byName,
    this.at,
  });

  final int number;
  final String type;
  final int amountCents;
  final String? note;
  final String? byName;
  final String? at;

  Map<String, dynamic> toJson() =>
      {'number': number, 'type': type, 'amountCents': amountCents, 'note': note, 'byName': byName, 'at': at};
}

/// Kopf der Bon-Daten der Schicht (gemeinsam fuer Z-, X-Bon und Kassenbewegung).
class ShiftReceiptHeader {
  const ShiftReceiptHeader({
    required this.kind,
    required this.blind,
    this.businessName,
    this.cashregisterId,
    this.cashregisterName,
    this.drawerName,
  });

  /// Ein Wert aus [shiftReceiptKinds].
  final String kind;

  /// Ohne `cashView` erstellt: Soll, Ist, Differenz und Barumsatz sind `null`.
  final bool blind;
  final String? businessName;
  final String? cashregisterId;
  final String? cashregisterName;
  final String? drawerName;

  Map<String, dynamic> _kopfJson() => {
        'kind': kind,
        'blind': blind,
        'business': {'name': businessName},
        'cashregister': {'id': cashregisterId, 'name': cashregisterName},
        'drawer': {'name': drawerName},
      };
}

/// Bon-Daten des Z-Bons (`shift_close`) bzw. X-Bons (`shift_interim`); Druck
/// mit `shiftReceiptLayout`. Kein Registrierkassenbeleg.
class ShiftSummaryReceipt extends ShiftReceiptHeader {
  const ShiftSummaryReceipt({
    required super.kind,
    required super.blind,
    super.businessName,
    super.cashregisterId,
    super.cashregisterName,
    super.drawerName,
    required this.number,
    this.openedAt,
    this.closedAt,
    this.openedByName,
    this.closedByName,
    this.openingFloatCents,
    required this.openingFloatTakenOver,
    this.openingDenominations,
    this.cashSalesCents,
    this.cashCancellationsCents,
    required this.receiptCount,
    required this.cancellationCount,
    this.nonCashByMethod = const [],
    this.movements = const [],
    this.tips = const [],
    this.expectedCents,
    this.countedCents,
    this.countedDenominations,
    this.differenceCents,
    this.comment,
    required this.openingsWithoutSale,
  });

  /// Nummer der Schicht (Draht: `shift.number`).
  final int number;
  final String? openedAt;
  final String? closedAt;
  final String? openedByName;
  final String? closedByName;
  final int? openingFloatCents;
  final bool openingFloatTakenOver;
  final Map<String, int>? openingDenominations;

  /// Blind `null`.
  final int? cashSalesCents;
  final int? cashCancellationsCents;
  final int receiptCount;
  final int cancellationCount;
  final List<NonCashAmount> nonCashByMethod;
  final List<ShiftReceiptMovement> movements;
  final List<ShiftReceiptTip> tips;

  /// Blind `null`.
  final int? expectedCents;

  /// Beim X-Bon immer `null`.
  final int? countedCents;
  final Map<String, int>? countedDenominations;
  final int? differenceCents;
  final String? comment;
  final int openingsWithoutSale;

  Map<String, dynamic> toJson() => {
        ..._kopfJson(),
        'shift': {
          'number': number,
          'openedAt': openedAt,
          'closedAt': closedAt,
          'openedByName': openedByName,
          'closedByName': closedByName,
        },
        'openingFloatCents': openingFloatCents,
        'openingFloatTakenOver': openingFloatTakenOver,
        'openingDenominations': openingDenominations == null ? null : {...openingDenominations!},
        'cashSalesCents': cashSalesCents,
        'cashCancellationsCents': cashCancellationsCents,
        'receiptCount': receiptCount,
        'cancellationCount': cancellationCount,
        'nonCashByMethod': [for (final u in nonCashByMethod) u.toJson()],
        'movements': [for (final m in movements) m.toJson()],
        'tips': [for (final t in tips) t.toJson()],
        'expectedCents': expectedCents,
        'countedCents': countedCents,
        'countedDenominations': countedDenominations == null ? null : {...countedDenominations!},
        'differenceCents': differenceCents,
        'comment': comment,
        'openingsWithoutSale': openingsWithoutSale,
      };
}

/// Bon-Daten des Z- oder X-Bons unter dem Namen der Aufgabe (Zwilling:
/// `ShiftSummaryReceipt`).
typedef ShiftReceiptData = ShiftSummaryReceipt;

/// Bon-Daten einer Kassenbewegung; Druck mit `cashMovementLayout`.
class CashMovementReceipt extends ShiftReceiptHeader {
  const CashMovementReceipt({
    super.kind = 'cash_movement',
    required super.blind,
    super.businessName,
    super.cashregisterId,
    super.cashregisterName,
    super.drawerName,
    this.shiftNumber,
    required this.number,
    required this.type,
    required this.amountCents,
    this.note,
    this.location,
    this.recipientName,
    this.targetDrawerName,
    this.byName,
    this.at,
  });

  /// Nummer der Schicht; `null` ausserhalb einer Schicht.
  final int? shiftNumber;

  /// Nummer der Bewegung (Draht: `movement.number`).
  final int number;
  final String type;
  final int amountCents;
  final String? note;
  final String? location;
  final String? recipientName;
  final String? targetDrawerName;
  final String? byName;
  final String? at;

  Map<String, dynamic> toJson() => {
        ..._kopfJson(),
        'shift': shiftNumber == null ? null : {'number': shiftNumber},
        'movement': {
          'number': number,
          'type': type,
          'amountCents': amountCents,
          'note': note,
          'location': location,
          'recipientName': recipientName,
          'targetDrawerName': targetDrawerName,
          'byName': byName,
          'at': at,
        },
      };
}

/// Antwort von `openMyShift`.
class OpenShiftResult {
  const OpenShiftResult({required this.shift, this.handoverDifferenceCents});

  final Shift shift;

  /// Unterschied zum uebergebenen Bestand beim Zaehlen; nur mit `cashView`.
  final int? handoverDifferenceCents;

  Map<String, dynamic> toJson() => {
        'shift': shift.toJson(),
        if (handoverDifferenceCents != null) 'handoverDifferenceCents': handoverDifferenceCents,
      };
}

/// Antwort von `recordMyCashMovement`.
class CashMovementResult {
  const CashMovementResult({required this.movement, required this.receipt});

  final CashMovement movement;
  final CashMovementReceipt receipt;

  Map<String, dynamic> toJson() => {'movement': movement.toJson(), 'receipt': receipt.toJson()};
}

/// Antwort von `logMyDrawerOpenings`.
class DrawerOpeningsResult {
  const DrawerOpeningsResult({required this.accepted, required this.duplicates, this.drawerId});

  final int accepted;

  /// Schon gemeldet (gleicher Schluessel): zaehlt nicht doppelt.
  final int duplicates;

  /// Die Lade, in die gemeldet wurde: eine stillgelegte meldet in die Hauptlade.
  final String? drawerId;

  Map<String, dynamic> toJson() => {'accepted': accepted, 'duplicates': duplicates, 'drawerId': drawerId};
}

/// Antwort von `getMyShiftReport`.
class ShiftReport {
  const ShiftReport({required this.shift, required this.movements, required this.receipt});

  final Shift shift;

  /// Blind ohne `count_difference`/`handover_difference`.
  final List<CashMovement> movements;

  /// X-Bon (offene Schicht) bzw. Z-Bon zum Nachdruck.
  final ShiftSummaryReceipt receipt;

  Map<String, dynamic> toJson() =>
      {'shift': shift.toJson(), 'movements': [for (final m in movements) m.toJson()], 'receipt': receipt.toJson()};
}

/// Ergebnis von `closeMyShift`: [recount] = bitte noch einmal zaehlen (kein
/// Fehler), sonst geschlossen mit Z-Bon in [receipt].
class ShiftCloseResult {
  const ShiftCloseResult.recount()
      : recount = true,
        shift = null,
        receipt = null,
        lastShiftOfRegister = false;

  const ShiftCloseResult.closed({required Shift this.shift, required ShiftSummaryReceipt this.receipt, required this.lastShiftOfRegister})
      : recount = false;

  /// Bitte noch einmal zaehlen und mit demselben Betrag oder neu erneut senden.
  final bool recount;

  /// Die geschlossene Schicht; `null` bei [recount].
  final Shift? shift;

  /// Z-Bon; `null` bei [recount].
  final ShiftSummaryReceipt? receipt;

  /// Es war die letzte offene Schicht der Kasse.
  final bool lastShiftOfRegister;

  Map<String, dynamic> toJson() => recount
      ? {'status': 'recount'}
      : {
          'status': 'closed',
          'shift': shift!.toJson(),
          'receipt': receipt!.toJson(),
          'lastShiftOfRegister': lastShiftOfRegister,
        };
}

// ---- Optionen ------------------------------------------------------------------

/// Wer die Lade oeffnete (gepufferte Oeffnung): der damals angemeldete
/// Mitarbeiter. Der Server nimmt ihn nur, wenn er zum Betrieb gehoert und der
/// Kasse zugewiesen ist, den Namen aus dem Konto; sonst gilt der sendende Benutzer.
class DrawerOpeningOperator {
  const DrawerOpeningOperator({required this.registerUserId, this.name});

  final String registerUserId;
  final String? name;

  Map<String, dynamic> toJson() => {'registerUserId': registerUserId, 'name': ?name};
}

/// Eine Oeffnung der Lade, wie die Kasse sie puffert und meldet.
class DrawerOpeningEntry {
  const DrawerOpeningEntry({
    required this.idempotencyKey,
    required this.reason,
    required this.ok,
    required this.deviceTime,
    this.note,
    this.receiptId,
    this.error,
    this.drawerId,
    this.operator,
  });

  /// Je Eintrag ein eigener Schluessel: ein zweites Melden zaehlt nicht doppelt.
  final String idempotencyKey;

  /// Ein Wert aus [openingReasons].
  final String reason;

  /// Ging der Impuls an die Lade durch? Fehlgeschlagene werden mit `false` gemeldet.
  final bool ok;

  /// Zeit am Geraet: Millisekunden seit 1970 ([int]), ISO 8601 ([String]) oder
  /// [DateTime] (geht als Millisekunden hinaus).
  final Object deviceTime;

  /// Text, Pflicht bei `other`.
  final String? note;

  /// Beleg bei `sale`.
  final String? receiptId;

  /// Fehlertext eines fehlgeschlagenen Impulses.
  final String? error;

  /// Lade der Oeffnung (gepuffert); muss `drawerId` der Anfrage sein, sonst `validation`.
  final String? drawerId;

  /// Wer oeffnete (gepuffert), siehe [DrawerOpeningOperator].
  final DrawerOpeningOperator? operator;

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'reason': reason,
        'ok': ok,
        'deviceTime': deviceTime is DateTime ? (deviceTime as DateTime).millisecondsSinceEpoch : deviceTime,
        'note': ?note,
        'receiptId': ?receiptId,
        'error': ?error,
        'drawerId': ?drawerId,
        if (operator != null) 'operator': operator!.toJson(),
      };
}

/// Trinkgeld-Auszahlung beim Abschluss: hoechstens der offene Anspruch
/// ([DrawerState.tipClaims]).
class TipPayout {
  const TipPayout({required this.registerUserId, required this.cents});

  final String registerUserId;
  final int cents;

  Map<String, dynamic> toJson() => {'registerUserId': registerUserId, 'cents': cents};
}

// ---- Leser ---------------------------------------------------------------------

/// Wo gelesen wird: Aufruf und Pfad unter `data`, fuer die Meldung.
class _Ort {
  const _Ort(this.name, this.pfad, [this.kind = 'response']);

  final String name;
  final String pfad;

  /// `response` fuer Antworten, `request` fuer Bon-Daten, die ein Aufrufer uebergibt.
  final String kind;

  _Ort unter(String teil) => _Ort(name, pfad.isEmpty ? teil : '$pfad.$teil', kind);
}

KasseneckValidationError _fehler(_Ort ort, String grund) =>
    KasseneckValidationError(ort.name, '${ort.kind == 'response' ? 'Antwort' : 'Bon-Daten'}: $grund', ort.kind);

Map<String, dynamic> _pflichtObjekt(_Ort ort, Object? w) =>
    objekt(w) ?? (throw _fehler(ort, '${ort.pfad.isEmpty ? 'data' : ort.pfad} ist kein Objekt'));

String? _text(Object? w) => w is String ? w : null;

String _kennung(_Ort ort, Map<String, dynamic> o, String feld) {
  final w = o[feld];
  if (w is! String || w.isEmpty) throw _fehler(ort, '${ort.pfad}.$feld fehlt');
  return w;
}

int _ganzzahl(_Ort ort, Map<String, dynamic> o, String feld) =>
    ganzzahlVon(o[feld]) ?? (throw _fehler(ort, '${ort.pfad}.$feld ist keine ganze Zahl'));

int? _ganzzahlOderNull(_Ort ort, Map<String, dynamic> o, String feld) => o[feld] == null ? null : _ganzzahl(ort, o, feld);

bool _wahr(_Ort ort, Map<String, dynamic> o, String feld) {
  final w = o[feld];
  if (w is! bool) throw _fehler(ort, '${ort.pfad}.$feld ist kein Wahrheitswert');
  return w;
}

bool? _wahrOderNull(_Ort ort, Map<String, dynamic> o, String feld) => o[feld] == null ? null : _wahr(ort, o, feld);

List<T> _liste<T>(_Ort ort, Map<String, dynamic> o, String feld, T Function(_Ort ort, Object? w) lese) {
  final w = o[feld];
  if (w is! List) throw _fehler(ort, '${ort.pfad}.$feld ist keine Liste');
  return List.unmodifiable([for (final (i, e) in w.indexed) lese(ort.unter('$feld[$i]'), e)]);
}

Map<String, int>? _stueckelung(_Ort ort, Map<String, dynamic> o, String feld) {
  final w = o[feld];
  if (w == null) return null;
  final karte = objekt(w);
  if (karte == null) throw _fehler(ort, '${ort.pfad}.$feld ist keine Stueckelung');
  final ortFeld = ort.unter(feld);
  return Map.unmodifiable({for (final k in karte.keys) k: _ganzzahl(ortFeld, karte, k)});
}

ShiftActor? _akteur(_Ort ort, Object? w) {
  if (w == null) return null;
  final o = _pflichtObjekt(ort, w);
  return ShiftActor(registerUserId: _text(o['registerUserId']), name: _text(o['name']), role: _text(o['role']) ?? '');
}

NonCashAmount _unbar(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  return NonCashAmount(method: _kennung(ort, o, 'method'), cents: _ganzzahl(ort, o, 'cents'));
}

ShiftTipTotals _trinkgeld(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  return ShiftTipTotals(
    registerUserId: _kennung(ort, o, 'registerUserId'),
    name: _text(o['name']),
    receivedImmediatelyCents: _ganzzahl(ort, o, 'receivedImmediatelyCents'),
    retainedCents: _ganzzahl(ort, o, 'retainedCents'),
    paidOutCents: _ganzzahl(ort, o, 'paidOutCents'),
    // Fehlt bei einem Backend vor der Regel R62: dann 0, statt die ganze Antwort zu verwerfen.
    refundedByEmployeeCents: o['refundedByEmployeeCents'] == null ? 0 : _ganzzahl(ort, o, 'refundedByEmployeeCents'),
  );
}

/// Trinkgeld mit offenem Anspruch (Kassenstand, Bon).
ShiftTip _trinkgeldMitOffen(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  final t = _trinkgeld(ort, o);
  return ShiftTip(
    registerUserId: t.registerUserId,
    name: t.name,
    receivedImmediatelyCents: t.receivedImmediatelyCents,
    retainedCents: t.retainedCents,
    paidOutCents: t.paidOutCents,
    refundedByEmployeeCents: t.refundedByEmployeeCents,
    // Fehlt bei einem Backend vor der Regel R64: dann 0.
    carriedOverCents: o['carriedOverCents'] == null ? 0 : _ganzzahl(ort, o, 'carriedOverCents'),
    openCents: _ganzzahl(ort, o, 'openCents'),
  );
}

ShiftRunningTotals _laufstand(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  return ShiftRunningTotals(
    cashSalesCents: _ganzzahl(ort, o, 'cashSalesCents'),
    cashCancellationsCents: _ganzzahl(ort, o, 'cashCancellationsCents'),
    nonCashByMethod: _liste(ort, o, 'nonCashByMethod', _unbar),
    receiptCount: _ganzzahl(ort, o, 'receiptCount'),
    cancellationCount: _ganzzahl(ort, o, 'cancellationCount'),
    cashInCents: _ganzzahl(ort, o, 'cashInCents'),
    cashOutCents: _ganzzahl(ort, o, 'cashOutCents'),
    tips: _liste(ort, o, 'tips', _trinkgeld),
    openingsWithoutSale: _ganzzahl(ort, o, 'openingsWithoutSale'),
  );
}

ShiftReconciliation? _abgleich(_Ort ort, Object? w) {
  if (w == null) return null;
  final o = _pflichtObjekt(ort, w);
  Map<String, ({Object? stored, Object? recomputed})>? abweichungen;
  final abw = o['deviations'];
  if (abw != null) {
    final karte = _pflichtObjekt(ort.unter('deviations'), abw);
    abweichungen = {
      for (final e in karte.entries)
        e.key: (() {
          final eintrag = _pflichtObjekt(ort.unter('deviations.${e.key}'), e.value);
          return (stored: eintrag['stored'], recomputed: eintrag['recomputed']);
        })(),
    };
  }
  return ShiftReconciliation(matches: _wahr(ort, o, 'matches'), deviations: abweichungen);
}

Shift _schicht(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  final status = o['status'];
  if (status != 'open' && status != 'closed') throw _fehler(ort, '${ort.pfad}.status ist unbekannt');
  return Shift(
    id: _kennung(ort, o, 'id'),
    drawerId: _kennung(ort, o, 'drawerId'),
    cashregisterId: _text(o['cashregisterId']),
    number: _ganzzahl(ort, o, 'number'),
    status: status as String,
    openedAt: _text(o['openedAt']),
    openedBy: _akteur(ort.unter('openedBy'), o['openedBy']),
    openedDeviceId: _text(o['openedDeviceId']),
    closedAt: _text(o['closedAt']),
    closedBy: _akteur(ort.unter('closedBy'), o['closedBy']),
    closedDeviceId: _text(o['closedDeviceId']),
    openingFloatCents: _ganzzahlOderNull(ort, o, 'openingFloatCents'),
    openingDenominations: _stueckelung(ort, o, 'openingDenominations'),
    openingFloatTakenOver: _wahrOderNull(ort, o, 'openingFloatTakenOver'),
    comment: _text(o['comment']),
    blind: _wahrOderNull(ort, o, 'blind'),
    countedCents: _ganzzahlOderNull(ort, o, 'countedCents'),
    suggestedFloatCents: _ganzzahlOderNull(ort, o, 'suggestedFloatCents'),
    runningTotals: o['runningTotals'] == null ? null : _laufstand(ort.unter('runningTotals'), o['runningTotals']),
    expectedCents: _ganzzahlOderNull(ort, o, 'expectedCents'),
    differenceCents: _ganzzahlOderNull(ort, o, 'differenceCents'),
    reconciliation: _abgleich(ort.unter('reconciliation'), o['reconciliation']),
  );
}

TipClaim _anspruch(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  return TipClaim(registerUserId: _kennung(ort, o, 'registerUserId'), name: _text(o['name']), cents: _ganzzahl(ort, o, 'cents'));
}

DrawerOpening _oeffnung(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  final von = objekt(o['by']);
  return DrawerOpening(
    at: _text(o['at']),
    deviceTime: _text(o['deviceTime']),
    reason: _kennung(ort, o, 'reason'),
    byName: von == null ? null : _text(von['name']),
    ok: _wahr(ort, o, 'ok'),
  );
}

/// `getMyDrawerState` -> [DrawerState].
DrawerState ladeStand(String name, Map<String, dynamic> daten) {
  const ort0 = '';
  final ort = _Ort(name, ort0);
  final lade = _pflichtObjekt(ort.unter('drawer'), daten['drawer']);
  final ladeOrt = ort.unter('drawer');
  final rechte = _pflichtObjekt(ort.unter('rights'), daten['rights']);
  final rechteOrt = ort.unter('rights');
  return DrawerState(
    drawer: DrawerInfo(
      id: _kennung(ladeOrt, lade, 'id'),
      name: _text(lade['name']),
      shiftMode: _wahr(ladeOrt, lade, 'shiftMode'),
      cashregisterId: _text(lade['cashregisterId']),
    ),
    rights: DrawerRights(
      shift: _wahr(rechteOrt, rechte, 'shift'),
      cashMove: _wahr(rechteOrt, rechte, 'cashMove'),
      cashView: _wahr(rechteOrt, rechte, 'cashView'),
      drawer: _wahr(rechteOrt, rechte, 'drawer'),
    ),
    tipClaims: _liste(ort, daten, 'tipClaims', _anspruch),
    tips: _liste(ort, daten, 'tips', _trinkgeldMitOffen),
    shift: daten['shift'] == null ? null : _schicht(ort.unter('shift'), daten['shift']),
    longOpenWarning: _wahrOderNull(ort, daten, 'longOpenWarning'),
    suggestedFloatCents: _ganzzahlOderNull(ort, daten, 'suggestedFloatCents'),
    expectedCents: _ganzzahlOderNull(ort, daten, 'expectedCents'),
    recentOpenings: daten['recentOpenings'] == null ? null : _liste(ort, daten, 'recentOpenings', _oeffnung),
  );
}

CashMovement _bewegung(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  final empfaenger = objekt(o['recipient']);
  final paar = objekt(o['counterpart']);
  return CashMovement(
    id: _kennung(ort, o, 'id'),
    number: _ganzzahl(ort, o, 'number'),
    shiftId: _text(o['shiftId']),
    type: _kennung(ort, o, 'type'),
    amountCents: _ganzzahl(ort, o, 'amountCents'),
    location: _text(o['location']),
    note: _text(o['note']),
    by: _akteur(ort.unter('by'), o['by']),
    at: _text(o['at']),
    recipient: empfaenger == null
        ? null
        : (registerUserId: _text(empfaenger['registerUserId']), name: _text(empfaenger['name'])),
    counterpart: paar == null ? null : (drawerId: _text(paar['drawerId']), movementId: _text(paar['movementId'])),
  );
}

void _kopfPruefen(_Ort ort, Map<String, dynamic> o, Set<String> erlaubt, String erwartet) {
  final art = o['kind'];
  if (art is! String || !shiftReceiptKinds.contains(art)) throw _fehler(ort, '${ort.pfad}.kind ist unbekannt');
  if (!erlaubt.contains(art)) throw _fehler(ort, '${ort.pfad}.kind ist $art, erwartet $erwartet');
}

ShiftSummaryReceipt _schichtBon(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  _kopfPruefen(ort, o, {'shift_close', 'shift_interim'}, 'Z- oder X-Bon');
  final betrieb = objekt(o['business']) ?? const {};
  final kasse = objekt(o['cashregister']) ?? const {};
  final lade = objekt(o['drawer']) ?? const {};
  final sOrt = ort.unter('shift');
  final s = _pflichtObjekt(sOrt, o['shift']);
  return ShiftSummaryReceipt(
    kind: o['kind'] as String,
    blind: _wahr(ort, o, 'blind'),
    businessName: _text(betrieb['name']),
    cashregisterId: _text(kasse['id']),
    cashregisterName: _text(kasse['name']),
    drawerName: _text(lade['name']),
    number: _ganzzahl(sOrt, s, 'number'),
    openedAt: _text(s['openedAt']),
    closedAt: _text(s['closedAt']),
    openedByName: _text(s['openedByName']),
    closedByName: _text(s['closedByName']),
    openingFloatCents: _ganzzahlOderNull(ort, o, 'openingFloatCents'),
    openingFloatTakenOver: _wahr(ort, o, 'openingFloatTakenOver'),
    openingDenominations: _stueckelung(ort, o, 'openingDenominations'),
    cashSalesCents: _ganzzahlOderNull(ort, o, 'cashSalesCents'),
    cashCancellationsCents: _ganzzahlOderNull(ort, o, 'cashCancellationsCents'),
    receiptCount: _ganzzahl(ort, o, 'receiptCount'),
    cancellationCount: _ganzzahl(ort, o, 'cancellationCount'),
    nonCashByMethod: _liste(ort, o, 'nonCashByMethod', _unbar),
    movements: _liste(ort, o, 'movements', (mOrt, mw) {
      final m = _pflichtObjekt(mOrt, mw);
      return ShiftReceiptMovement(
        number: _ganzzahl(mOrt, m, 'number'),
        type: _kennung(mOrt, m, 'type'),
        amountCents: _ganzzahl(mOrt, m, 'amountCents'),
        note: _text(m['note']),
        byName: _text(m['byName']),
        at: _text(m['at']),
      );
    }),
    tips: _liste(ort, o, 'tips', _trinkgeldMitOffen),
    expectedCents: _ganzzahlOderNull(ort, o, 'expectedCents'),
    countedCents: _ganzzahlOderNull(ort, o, 'countedCents'),
    countedDenominations: _stueckelung(ort, o, 'countedDenominations'),
    differenceCents: _ganzzahlOderNull(ort, o, 'differenceCents'),
    comment: _text(o['comment']),
    openingsWithoutSale: _ganzzahl(ort, o, 'openingsWithoutSale'),
  );
}

CashMovementReceipt _bewegungsBon(_Ort ort, Object? w) {
  final o = _pflichtObjekt(ort, w);
  _kopfPruefen(ort, o, {'cash_movement'}, 'cash_movement');
  final betrieb = objekt(o['business']) ?? const {};
  final kasse = objekt(o['cashregister']) ?? const {};
  final lade = objekt(o['drawer']) ?? const {};
  final s = objekt(o['shift']);
  final mOrt = ort.unter('movement');
  final m = _pflichtObjekt(mOrt, o['movement']);
  return CashMovementReceipt(
    blind: _wahr(ort, o, 'blind'),
    businessName: _text(betrieb['name']),
    cashregisterId: _text(kasse['id']),
    cashregisterName: _text(kasse['name']),
    drawerName: _text(lade['name']),
    shiftNumber: s == null ? null : _ganzzahl(ort.unter('shift'), s, 'number'),
    number: _ganzzahl(mOrt, m, 'number'),
    type: _kennung(mOrt, m, 'type'),
    amountCents: _ganzzahl(mOrt, m, 'amountCents'),
    note: _text(m['note']),
    location: _text(m['location']),
    recipientName: _text(m['recipientName']),
    targetDrawerName: _text(m['targetDrawerName']),
    byName: _text(m['byName']),
    at: _text(m['at']),
  );
}

/// `closeMyShift` -> [ShiftCloseResult].
ShiftCloseResult abschlussLesen(String name, Map<String, dynamic> daten) {
  final ort = _Ort(name, '');
  if (daten['status'] == 'recount') return const ShiftCloseResult.recount();
  if (daten['status'] != 'closed') throw _fehler(ort, 'data.status ist unbekannt');
  return ShiftCloseResult.closed(
    shift: _schicht(ort.unter('shift'), daten['shift']),
    receipt: _schichtBon(ort.unter('receipt'), daten['receipt']),
    lastShiftOfRegister: _wahr(ort, daten, 'lastShiftOfRegister'),
  );
}

/// `openMyShift` -> [OpenShiftResult].
OpenShiftResult geoeffnetLesen(String name, Map<String, dynamic> daten) {
  final ort = _Ort(name, '');
  return OpenShiftResult(
    shift: _schicht(ort.unter('shift'), daten['shift']),
    handoverDifferenceCents: _ganzzahlOderNull(ort, daten, 'handoverDifferenceCents'),
  );
}

/// `recordMyCashMovement` -> [CashMovementResult].
CashMovementResult gebuchtLesen(String name, Map<String, dynamic> daten) {
  final ort = _Ort(name, '');
  return CashMovementResult(
    movement: _bewegung(ort.unter('movement'), daten['movement']),
    receipt: _bewegungsBon(ort.unter('receipt'), daten['receipt']),
  );
}

/// `logMyDrawerOpenings` -> [DrawerOpeningsResult].
DrawerOpeningsResult gemeldetLesen(String name, Map<String, dynamic> daten) {
  final ort = _Ort(name, '');
  return DrawerOpeningsResult(
    accepted: _ganzzahl(ort, daten, 'accepted'),
    duplicates: _ganzzahl(ort, daten, 'duplicates'),
    drawerId: _text(daten['drawerId']),
  );
}

/// `getMyShiftReport` -> [ShiftReport].
ShiftReport berichtLesen(String name, Map<String, dynamic> daten) {
  final ort = _Ort(name, '');
  return ShiftReport(
    shift: _schicht(ort.unter('shift'), daten['shift']),
    movements: _liste(ort, daten, 'movements', _bewegung),
    receipt: _schichtBon(ort.unter('receipt'), daten['receipt']),
  );
}

/// Prueft Bon-Daten, die ein Aufrufer an die Layouts uebergibt (`kind` muss
/// zum Bon passen); Wurf mit `kind: request`.
void zBonPruefen(String name, ShiftSummaryReceipt bon) {
  final art = bon.kind;
  if (art != 'shift_close' && art != 'shift_interim') {
    throw KasseneckValidationError(name, 'Bon-Daten: receipt.kind ist $art, erwartet Z- oder X-Bon', 'request');
  }
}

/// Wie [zBonPruefen] fuer eine Kassenbewegung.
void bewegungsBonPruefen(String name, CashMovementReceipt bon) {
  if (bon.kind != 'cash_movement') {
    throw KasseneckValidationError(name, 'Bon-Daten: receipt.kind ist ${bon.kind}, erwartet cash_movement', 'request');
  }
}
