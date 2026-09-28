/// Fehler der Kassen-Aufrufe um den Verkauf herum (Einstellungen, Logo,
/// Artikel, Drucker, Trinkgeld-Empfänger) auswerten: am `code`, nie am Text.
/// Zwilling von `pos/errors.ts` im JS-Paket. Belege, Storno und Belegmail
/// haben eigene Listen (`receiptErrorCodes` …), die Anmeldung
/// [registerErrorCodes].
library;

import '../register/codes.dart';
import '../register/fehler.dart';

export '../register/codes.dart' show FieldError;

/// Gleich `pos.posErrorCodes` im Vertrag (`surface.json`): Fehlerfälle der
/// zehn Endpunkte und ihre Handler-Codes, dazu Anmelde- und Randcodes (ohne
/// den Partner-Zugang) und der Paketcode `route_missing`. `validation` trägt
/// `details.errors[]` mit dem äußeren Feldpfad ([posFieldErrors]).
const List<String> posErrorCodes = [
  'account_not_found',
  'admin_required',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'device_not_found',
  'dialect_mismatch',
  'internal_translation_error',
  'live_not_enabled',
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
  'session_expired',
  'session_other_cashregister',
  'unauthorized',
  'user_disabled',
  'user_verification_failed',
  'validation',
  // Code des Pakets: HTML statt Backend, der Aufruf kam nie an.
  'route_missing',
];

bool isPosErrorCode(Object? wert) => wert is String && posErrorCodes.contains(wert);

/// Der Code eines geworfenen Fehlers, wenn er in [posErrorCodes] steht; sonst `null`.
String? posErrorCode(Object? fehler) =>
    fehler is KasseneckApiError && isPosErrorCode(fehler.code) ? fehler.code : null;

/// Kurzform für `catch (e) { if (isPosError(e, 'logo_too_large')) … }`.
bool isPosError(Object? fehler, [String? code]) {
  final gefunden = posErrorCode(fehler);
  return gefunden != null && (code == null || gefunden == code);
}

/// Die Feldfehler einer `validation`-Antwort (`business.vatRates`,
/// `device.shortcuts.cash`); leer, wenn es keine sind.
List<FieldError> posFieldErrors(Object? fehler) => fieldErrors(fehler);
