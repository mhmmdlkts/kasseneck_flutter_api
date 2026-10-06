/// Fehler der Lager-API auswerten: am Code, nie am Text – Zwilling von
/// `src/inventory/fehler.ts` im JS-Paket.
///
/// Es zaehlen die Codes der Lager-Endpunkte ([inventoryErrorCodes]) und die,
/// die Anmeldung und Rand auf jedem Aufruf erzeugen koennen
/// ([inventoryRequestErrorCodes]). Ein fremder Code ist fuer diese Helfer
/// kein Lager-Fehler: wer darauf verzweigt, tut es bewusst ueber
/// [KasseneckApiError.code].
library;

import '../register/fehler.dart';
import 'lesen.dart' show fehlmengen;
import 'modelle.dart';
import 'vertrag.dart';

final Set<String> _bekannt = {...inventoryErrorCodes, ...inventoryRequestErrorCodes};

/// Ein Code, den ein Lager-Aufruf liefern kann?
bool isInventoryErrorCode(String? code) => code != null && _bekannt.contains(code);

/// Der Fehlercode eines geworfenen Fehlers; `null`, wenn es keiner der Lager-API ist.
String? inventoryErrorCode(Object? error) =>
    error is KasseneckApiError && isInventoryErrorCode(error.code) ? error.code : null;

/// Kurzform fuer `on Object catch (e) { if (isInventoryError(e, 'article_not_found')) … }`;
/// ohne [code] jeder Code der Lager-API.
bool isInventoryError(Object? error, [String? code]) {
  final gefunden = inventoryErrorCode(error);
  return gefunden != null && (code == null || gefunden == code);
}

/// Die Feldfehler einer `validation`-Antwort; leer, wenn es keine sind.
List<({String field, String message})> inventoryFieldErrors(Object? error) {
  if (error is! KasseneckApiError) return const [];
  final roh = error.details['errors'];
  if (roh is! List) return const [];
  return [
    for (final e in roh)
      if (e is Map && e['field'] is String && e['message'] is String)
        (field: e['field'] as String, message: e['message'] as String),
  ];
}

/// Wie lange `rate_limited` noch gilt, in Sekunden (`data.retryAfterSec`,
/// dasselbe wie die Kopfzeile `Retry-After`). `null`, wenn der Fehler kein
/// `rate_limited` ist oder der Server keine Angabe macht. Die Grenze gilt je
/// Konto (etwa 20 Anfragen je Sekunde, kurze Spitzen bis 40).
///
/// Eine Kommazahl wird aufgerundet: wer frueher fragt, bekommt nur wieder
/// `rate_limited`.
int? inventoryRetryAfterSec(Object? error) {
  if (inventoryErrorCode(error) != 'rate_limited') return null;
  final wert = (error as KasseneckApiError).details['retryAfterSec'];
  if (wert is int) return wert >= 0 ? wert : null;
  if (wert is double && wert.isFinite && wert >= 0) return wert.ceil();
  return null;
}

/// Die Positionen, fuer die beim Reservieren der verfuegbare Bestand nicht
/// reicht (`insufficient_available`, `details['details']`): je Artikel und
/// Standort angefragt und verfuegbar, in Tausendstel. Leer, wenn der Fehler ein
/// anderer ist. Es fehlen nur diese Positionen; reserviert wurde nichts (ganz
/// oder gar nicht).
List<InventoryShortfall> inventoryShortfalls(Object? error) {
  if (inventoryErrorCode(error) != 'insufficient_available') return const [];
  return fehlmengen((error as KasseneckApiError).details['details']);
}

final Set<String> _hinweise = {...inventoryWarningCodes};

/// `true` fuer einen Hinweis-Code einer Buchung (`StockOperation.warnings[].code`).
/// Hinweise sind nie Fehler: die Buchung hat gewirkt.
bool isInventoryWarningCode(String? code) => code != null && _hinweise.contains(code);
