/// Belege einer Kasse auflisten: der Vertrag des Endpunkts `listReceipts`
/// (nur `/v3`, api_key + `cashregister-token` wie `getReportV2`).
///
/// Ein Tag (`date`) oder ein Zeitraum (`from`, `to`, hoechstens 31
/// Kalendertage), seitenweise ueber einen undurchsichtigen Cursor. Zeiten sind
/// die Wiener Wanduhr als Text, wie `timeStamp` am Beleg; deshalb nimmt das
/// Paket hier Text und kein `DateTime` (ein `DateTime` des Geraets traegt
/// dessen Zeitzone, und um Mitternacht laege der Tag sonst daneben).
///
/// Die Pruefung der Eingaben ist ein Zwilling von `pruefeParameter` im
/// Backend (`beleg-liste-core.js`): was hier durchgeht, lehnt der Server nicht
/// am Format ab, und ein Fehler faellt vor dem Senden auf statt als
/// `invalid_date` nach einem Netzweg.
library;

import '../../enums/keck_payment_method.dart';
import '../../enums/receipt_type.dart';
import '../../models/keck_payment.dart';
import '../../models/registration_info.dart' show CancellationOf;
import '../aufrufe.dart';
import '../kasse/belege.dart' show CancellationState, ReceiptOperator;
import '../lager/lesen.dart' show antwortfehler, ganzzahlVon, naechsterCursor, objekt;
import '../register/fehler.dart';

/// Stabile Fehlercodes von `listReceipts` unter `/v3`. Sie kommen als
/// `KasseneckApiError.code` an; die Eingabefehler darunter faengt das Paket
/// schon vor dem Senden ab ([KasseneckValidationError], `kind: request`),
/// ankommen koennen sie trotzdem (ein Cursor einer anderen Abfrage:
/// `invalid_cursor`). Dahinter die Codes von Anmeldung und Rand.
const Set<String> receiptListErrorCodes = {
  'invalid_date',
  'invalid_range',
  'range_too_long',
  'invalid_limit',
  'invalid_order',
  'invalid_view',
  'invalid_cursor',
  'server_error',
};

/// Werte von `order`: `desc` (neueste zuerst, Vorgabe des Servers) und `asc`.
const Set<String> receiptListOrders = {'desc', 'asc'};

/// Groesste Seite, die der Server liefert (Vorgabe 100).
const int receiptListLimitMax = 500;

/// Laengster Zeitraum in Kalendertagen (Wanduhr, nicht 31 x 24 Stunden).
const int receiptListDaysMax = 31;

/// Hoechstens so viele Seiten holt `listAllReceipts`, dann bricht es mit
/// einem Fehler ab. Mit 500 je Seite sind das 50.000 Belege in einem Fenster;
/// mehr deutet auf eine Schleife, nicht auf eine Kasse.
const int receiptListPagesMax = 100;

/// Ein Beleg in `listReceipts` (`view: summary`): die Zeile einer Liste,
/// Betraege in ganzen Cent. Fuer Kopf, Layout und Pruefangaben gehoert der
/// Beleg einzeln ueber `getReceipt` geholt.
///
/// Nicht zu verwechseln mit `ReceiptSummary` aus `pos.dart`: das ist die
/// Zeile von `listMyReceipts` am Kassenweg (Summe in Euro, Positionen kurz)
/// und hat einen anderen Vertrag.
class ReceiptListEntry {
  const ReceiptListEntry({
    required this.receiptId,
    required this.counter,
    required this.receiptType,
    required this.zeroKind,
    required this.timeStamp,
    required this.totalCents,
    required this.grossByRateCents,
    required this.paymentMethod,
    required this.payments,
    required this.tipCents,
    required this.operator,
    required this.cancellationOf,
    required this.cancellationReason,
    required this.cancellationStatus,
    required this.signatureOk,
    required this.customProjectId,
    required this.fullReceiptId,
  });

  final String? receiptId;

  /// Fortlaufender Belegzaehler der Kasse; fehlt bei Altbelegen.
  final int? counter;

  /// `null`, wenn der Server keinen oder einen hier unbekannten Wert nennt;
  /// geraten wird keiner.
  final ReceiptType? receiptType;

  /// Nur am Nullbeleg (`monthly`, `annual`, `manual` …), sonst `null`.
  final String? zeroKind;

  /// Wiener Wanduhr ohne Offset (`YYYY-MM-DDTHH:mm:ss`), wie gespeichert.
  final String? timeStamp;

  /// Summe von [grossByRateCents]; beim Storno negativ.
  final int totalCents;

  /// Brutto je RKSV-Satzgruppe (`amountRateStandard` … `amountRateSpecial`).
  final ReceiptGrossByRate grossByRateCents;

  /// `mixed` bei mehreren Zahlarten. `null`, wenn er fehlt oder unbekannt ist:
  /// ein Ersatzwert wie „bar“ waere eine falsche Aussage in der Kassenliste.
  final KeckPaymentMethod? paymentMethod;

  /// Nur bei Belegen mit Zahlungsliste; ohne Anbieter-Interna.
  final List<KeckPayment>? payments;

  /// Nur, wenn der Beleg Trinkgeld traegt.
  final int? tipCents;

  /// Bediener (nur der Name, `uid` ist hier immer `null`).
  final ReceiptOperator? operator;

  /// Nur am Storno-Beleg: das Original.
  final CancellationOf? cancellationOf;

  /// Grund des Stornos (englisch, Katalog `cancellationReasons`).
  final String? cancellationReason;

  /// Storno-Stand eines Standardbelegs (`none`, `partial`, `full`); jede
  /// andere Belegart ist `none`. `null`, wenn die Antwort ihn nicht nennt.
  final CancellationState? cancellationStatus;

  /// Wurde der Beleg mit funktionierender Signatureinheit ausgestellt?
  final bool signatureOk;

  /// Referenz des Aufrufers, wie beim Verkauf mitgegeben.
  final String? customProjectId;

  /// Schluessel fuer `downloadReceipt` und den Beleg-Link.
  final String? fullReceiptId;
}

/// Brutto je RKSV-Satzgruppe in ganzen Cent.
class ReceiptGrossByRate {
  const ReceiptGrossByRate({
    required this.standard,
    required this.reduced1,
    required this.reduced2,
    required this.zero,
    required this.special,
  });

  final int standard;
  final int reduced1;
  final int reduced2;
  final int zero;
  final int special;
}

/// Umsatz eines Tages aus der Tagesstatistik (`daySummary`).
///
/// **Nicht die Summe der Liste:** [receiptCount] zaehlt jeden Beleg des Tages
/// (auch Null-, Start- und Trainingsbelege), [revenueCents] nur Standard- und
/// Storno-Belege, ohne Mitarbeiter-Trinkgeld und nach Aktionsrabatt. Wer die
/// Liste summieren will, summiert die Liste.
class ReceiptDaySummary {
  const ReceiptDaySummary({
    required this.date,
    required this.receiptCount,
    required this.revenueCents,
    required this.revenueByRate,
  });

  /// Der Wiener Tag `YYYY-MM-DD`.
  final String date;
  final int receiptCount;
  final int revenueCents;

  /// Je Satz in Basispunkten (2000 = 20 %), hoechster zuerst; Saetze ohne
  /// Umsatz fehlen.
  final List<({int rateBp, int grossCents})> revenueByRate;
}

/// Eine Seite von `listReceipts`: [T] ist [ReceiptListEntry] (`view:
/// summary`) oder `KasseneckReceipt` (`view: full`).
///
/// Generisch statt zwei Seitenklassen, weil Blaettern, Cursor und
/// Tagessumme in beiden Ansichten dieselben sind; welche Ansicht kam, legt die
/// aufgerufene Methode fest, nicht ein Parameter. So kann kein Aufrufer eine
/// volle Seite als Kurzzeilen lesen.
class ReceiptListPage<T> {
  const ReceiptListPage({
    required this.receipts,
    required this.hasMore,
    required this.nextCursor,
    required this.daySummary,
  });

  final List<T> receipts;

  /// Es gibt eine weitere Seite; dann ist [nextCursor] gesetzt.
  final bool hasMore;

  /// Fuer die naechste Seite, mit **demselben** Zeitfenster und derselben
  /// `order` (nur `limit` darf sich aendern); `null` am Ende.
  final String? nextCursor;

  /// Nur mit `date` und nur auf der ersten Seite; `null`, wenn der Tag keine
  /// Statistik hat oder ein Zeitraum abgefragt wurde.
  final ReceiptDaySummary? daySummary;
}

final RegExp _tag = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _zeitpunkt = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$');

String _zwei(int n) => n.toString().padLeft(2, '0');

String _wanduhrText(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_zwei(t.month)}-${_zwei(t.day)}T${_zwei(t.hour)}:${_zwei(t.minute)}:${_zwei(t.second)}';

/// Ein Tag oder Zeitpunkt der Wanduhr als UTC-`DateTime` (nur zum Rechnen:
/// UTC kennt keine Zeitumstellung, also ist ein Tag hier immer ein
/// Kalendertag). `null` bei falschem Format oder unmoeglichem Datum
/// (`2026-02-30`, `25:00:00`); `DateTime` selbst liefe still in den Maerz.
DateTime? _wanduhr(String wert, {required bool nurTag}) {
  final m = (nurTag ? _tag : _zeitpunkt).firstMatch(wert) ?? (nurTag ? null : _tag.firstMatch(wert));
  if (m == null) return null;
  final teile = [for (var i = 1; i <= m.groupCount; i++) int.parse(m.group(i)!)];
  final [j, mo, t, ...rest] = teile;
  final [h, mi, s] = rest.isEmpty ? const [0, 0, 0] : rest;
  if (mo < 1 || mo > 12 || t < 1 || h > 23 || mi > 59 || s > 59) return null;
  final d = DateTime.utc(j, mo, t, h, mi, s);
  return d.month == mo && d.day == t ? d : null;
}

/// Die Parameter einer Seite, geprueft wie im Backend. Wirft
/// [KasseneckValidationError] (`kind: request`), bevor etwas hinausgeht.
Map<String, dynamic> receiptListParams({
  required String view,
  String? date,
  String? from,
  String? to,
  int? limit,
  String? order,
  String? cursor,
}) {
  const name = Aufrufe.listReceipts;
  KasseneckValidationError fehler(String grund) => KasseneckValidationError(name, grund, 'request');

  final Map<String, dynamic> fenster;
  if (date != null) {
    if (from != null || to != null) throw fehler('entweder date oder from und to angeben, nicht beides');
    if (_wanduhr(date, nurTag: true) == null) throw fehler('date muss ein Datum JJJJ-MM-TT sein');
    fenster = {'date': date};
  } else {
    if (from == null || to == null) throw fehler('Zeitraum fehlt: date oder from und to angeben');
    final von = _wanduhr(from, nurTag: false);
    if (von == null) throw fehler('from muss JJJJ-MM-TT oder JJJJ-MM-TTThh:mm:ss sein');
    final bis = _wanduhr(to, nurTag: false);
    if (bis == null) throw fehler('to muss JJJJ-MM-TT oder JJJJ-MM-TTThh:mm:ss sein');
    if (!bis.isAfter(von)) throw fehler('to muss nach from liegen (to zaehlt nicht mehr dazu)');
    // Verglichen wird wie im Backend der Text der Wanduhr: from + 31 Tage.
    if (_wanduhrText(bis).compareTo(_wanduhrText(von.add(const Duration(days: receiptListDaysMax)))) > 0) {
      throw fehler('der Zeitraum ist laenger als $receiptListDaysMax Tage');
    }
    fenster = {'from': from, 'to': to};
  }
  if (limit != null && (limit < 1 || limit > receiptListLimitMax)) {
    throw fehler('limit muss eine ganze Zahl von 1 bis $receiptListLimitMax sein');
  }
  if (order != null && !receiptListOrders.contains(order)) throw fehler('order muss desc oder asc sein');
  if (cursor != null && cursor.isEmpty) throw fehler('cursor ist leer');
  return {...fenster, 'limit': ?limit, 'order': ?order, 'view': view, 'cursor': ?cursor};
}

/// Eine Seite aus `data`; die Eintraege liest [eintraege].
ReceiptListPage<T> receiptListPage<T>(Map<String, dynamic> daten, List<T> Function(List<Object?> roh) eintraege) {
  const name = Aufrufe.listReceipts;
  final roh = daten['receipts'];
  if (roh is! List) {
    // Keine Liste ist etwas anderes als eine leere Liste: „an dem Tag nichts
    // verkauft" darf nicht aussehen wie „Antwort kaputt".
    throw antwortfehler(name, 'Antwort enthaelt keine Belegliste (data.receipts fehlt)');
  }
  final mehr = daten['hasMore'];
  if (mehr is! bool) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.hasMore)');
  final cursor = naechsterCursor(name, daten);
  // Beide Angaben muessen zusammenpassen: hasMore ohne Cursor liesse das
  // Blaettern still enden und Belege fehlten, ein Cursor ohne hasMore waere
  // eine Seite, die niemand holt.
  if (mehr != (cursor != null)) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.hasMore passt nicht zu data.nextCursor)');
  return ReceiptListPage<T>(
    receipts: List.unmodifiable(eintraege(roh)),
    hasMore: mehr,
    nextCursor: cursor,
    daySummary: _tagesSumme(daten['daySummary']),
  );
}

int _cent(String pfad, Object? w) =>
    ganzzahlVon(w) ?? (throw antwortfehler(Aufrufe.listReceipts, 'Antwort enthaelt keine ganze Zahl (data.$pfad)'));

String? _text(Object? w) => w is String && w.isNotEmpty ? w : null;

Map<String, dynamic> _objekt(String pfad, Object? w) =>
    objekt(w) ?? (throw antwortfehler(Aufrufe.listReceipts, 'Antwort ist unbrauchbar (data.$pfad ist kein Objekt)'));

ReceiptDaySummary? _tagesSumme(Object? w) {
  if (w == null) return null;
  final o = _objekt('daySummary', w);
  final datum = o['date'];
  if (datum is! String || _wanduhr(datum, nurTag: true) == null) {
    throw antwortfehler(Aufrufe.listReceipts, 'Antwort ist unbrauchbar (data.daySummary.date)');
  }
  final saetze = o['revenueByRate'];
  if (saetze is! List) throw antwortfehler(Aufrufe.listReceipts, 'Antwort ist unbrauchbar (data.daySummary.revenueByRate)');
  return ReceiptDaySummary(
    date: datum,
    receiptCount: _cent('daySummary.receiptCount', o['receiptCount']),
    revenueCents: _cent('daySummary.revenueCents', o['revenueCents']),
    revenueByRate: List.unmodifiable([
      for (final (i, s) in saetze.indexed) _satz('daySummary.revenueByRate[$i]', s),
    ]),
  );
}

({int rateBp, int grossCents}) _satz(String pfad, Object? w) {
  final o = _objekt(pfad, w);
  return (rateBp: _cent('$pfad.rateBp', o['rateBp']), grossCents: _cent('$pfad.grossCents', o['grossCents']));
}

/// Eine Zeile der Kurzansicht. Betraege muessen ganze Cent sein, sonst endet
/// der Aufruf mit einem Antwortfehler: eine geratene 0 waere „kein Umsatz“.
ReceiptListEntry receiptListEntry(int index, Object? w) {
  final pfad = 'receipts[$index]';
  final o = _objekt(pfad, w);
  final toepfe = _objekt('$pfad.grossByRateCents', o['grossByRateCents']);
  int topf(String feld) => _cent('$pfad.grossByRateCents.$feld', toepfe[feld]);
  final bediener = objekt(o['operator']);
  return ReceiptListEntry(
    receiptId: _text(o['receiptId']),
    counter: ganzzahlVon(o['counter']),
    receiptType: ReceiptType.values.asNameMap()[o['receiptType']],
    zeroKind: _text(o['zeroKind']),
    timeStamp: _text(o['timeStamp']),
    totalCents: _cent('$pfad.totalCents', o['totalCents']),
    grossByRateCents: ReceiptGrossByRate(
      standard: topf('standard'),
      reduced1: topf('reduced1'),
      reduced2: topf('reduced2'),
      zero: topf('zero'),
      special: topf('special'),
    ),
    paymentMethod: KeckPaymentMethod.values.asNameMap()[o['paymentMethod']],
    payments: KeckPayment.listFromJson(o['payments']),
    tipCents: o['tipCents'] == null ? null : _cent('$pfad.tipCents', o['tipCents']),
    operator: bediener == null ? null : ReceiptOperator(uid: null, name: bediener['name'] is String ? bediener['name'] as String : ''),
    cancellationOf: CancellationOf.fromJson(o['cancellationOf']),
    cancellationReason: _text(o['cancellationReason']),
    cancellationStatus: switch (o['cancellationStatus']) {
      null => null,
      'none' => CancellationState.none,
      'partial' => CancellationState.partial,
      'full' => CancellationState.full,
      _ => CancellationState.unknown,
    },
    signatureOk: o['signatureOk'] != false,
    customProjectId: _text(o['customProjectId']),
    fullReceiptId: _text(o['fullReceiptId']),
  );
}
