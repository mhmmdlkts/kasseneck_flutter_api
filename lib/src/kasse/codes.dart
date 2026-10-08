/// Fehler der Kassen-Aufrufe um den Verkauf herum (Einstellungen, Logo,
/// Artikel, Drucker, Trinkgeld-Empfänger, Lager, Inventur zaehlen) auswerten:
/// am `code`, nie am Text.
/// Zwilling von `pos/errors.ts` im JS-Paket. Belege, Storno und Belegmail
/// haben eigene Listen (`receiptErrorCodes` …), die Anmeldung
/// [registerErrorCodes].
library;

import '../register/codes.dart';
import '../register/fehler.dart';

export '../register/codes.dart' show FieldError;

/// Gleich `pos.posErrorCodes` im Vertrag (`surface.json`): Fehlerfälle der
/// Endpunkte (seit 10.7 auch die fuenf der Inventur) und ihre Handler-Codes,
/// dazu Anmelde- und Randcodes (ohne den Partner-Zugang) und der Paketcode
/// `route_missing`. `validation` trägt
/// `details.errors[]` mit dem äußeren Feldpfad ([posFieldErrors]).
const List<String> posErrorCodes = [
  'account_not_found',
  'admin_required',
  'api_not_approved',
  'app_check_invalid',
  'app_check_missing',
  'article_not_found',
  'article_not_in_scope',
  'article_not_tracked',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'count_already_voided',
  'count_not_found',
  'device_not_found',
  'dialect_mismatch',
  'idempotency_conflict',
  'idempotency_key_required',
  'internal_translation_error',
  'invalid_cursor',
  'invalid_quantity',
  'invalid_serial',
  'live_not_enabled',
  'location_inactive',
  'location_not_found',
  'logo_invalid',
  'logo_invalid_type',
  'logo_too_large',
  'method_not_allowed',
  'mfa_required',
  'module_inactive',
  'not_found',
  'not_permitted',
  'print_job_not_found',
  'print_layout_failed',
  'printer_not_found',
  'register_user_no_business',
  'register_user_not_allowed',
  'register_user_not_found',
  'response_translation_failed',
  'serial_already_counted',
  'serial_not_allowed',
  'serial_required',
  'server_error',
  'session_expired',
  'session_other_cashregister',
  'stocktake_closed',
  'stocktake_closing',
  'stocktake_not_found',
  'stocktake_not_open',
  'too_many_counts',
  'unauthorized',
  'user_disabled',
  'user_verification_failed',
  'validation',
  // Code des Pakets: HTML statt Backend, der Aufruf kam nie an.
  'route_missing',
];

bool isPosErrorCode(Object? value) => value is String && posErrorCodes.contains(value);

/// Der Code eines geworfenen Fehlers, wenn er in [posErrorCodes] steht; sonst `null`.
String? posErrorCode(Object? error) =>
    error is KasseneckApiError && isPosErrorCode(error.code) ? error.code : null;

/// Kurzform für `catch (e) { if (isPosError(e, 'logo_too_large')) … }`.
bool isPosError(Object? error, [String? code]) {
  final gefunden = posErrorCode(error);
  return gefunden != null && (code == null || gefunden == code);
}

/// Die Feldfehler einer `validation`-Antwort (`business.vatRates`,
/// `device.shortcuts.cash`); leer, wenn es keine sind.
List<FieldError> posFieldErrors(Object? error) => fieldErrors(error);
