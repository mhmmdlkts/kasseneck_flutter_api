/// Fehler der Kassen-Anmeldung (Kopplung, Benutzerliste, PIN-Anmeldung,
/// Sitzung, Entkoppeln) auswerten: **am `code`, nie am Meldungstext.**
/// Zwilling von `register/errors.ts` im JS-Paket.
///
/// Bis 9.x verglich die Kasse deutsche Meldungen („Kasse wird gerade auf …
/// verwendet“) und zog Zahlen aus dem Text. Unter `/api/v3` trägt jede
/// Abweisung einen Code (Nachtrag §11.7.4) und ihre Angaben als Daten
/// ([registerErrorDetails]). Die `message` bleibt ein deutscher Menschentext
/// zum Anzeigen, sie ist kein Vertrag.
library;

import 'fehler.dart';

/// Die Codes der Anmeldung, gleich `registerErrorCodes` im Vertrag
/// (`surface.json`): Fehlerfälle der acht Anmelde-Endpunkte und ihre
/// Handler-Codes, dazu Anmelde- und Randcodes (ohne den Partner-Zugang) und
/// der Paketcode `route_missing`. Ein Code, der hier nicht steht, bleibt über
/// [KasseneckApiError.code] lesbar; die Kasse braucht dafür einen
/// Rückfallzweig.
const List<String> registerErrorCodes = [
  'account_not_found',
  'admin_required',
  'cashregister_in_use',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'device_bound_elsewhere',
  'device_not_found',
  'device_not_paired',
  'device_takeover_required',
  'dialect_mismatch',
  'internal_translation_error',
  'licenses_exhausted',
  'live_not_enabled',
  'location_outside',
  'location_required',
  'login_failed',
  'login_mode_select_user',
  'login_unavailable',
  'method_not_allowed',
  'mfa_required',
  'not_found',
  'pairing_code_expired',
  'pairing_code_unknown',
  'pairing_code_used',
  'pairing_failed',
  'register_user_no_business',
  'register_user_not_allowed',
  'register_user_not_found',
  'register_user_only',
  'response_translation_failed',
  'session_ended',
  'session_expired',
  'session_not_running',
  'session_other_cashregister',
  'too_many_attempts',
  'unauthorized',
  'user_disabled',
  'user_verification_failed',
  'validation',
  // Code des Pakets: HTML statt Backend, der Aufruf kam nie an.
  'route_missing',
];

bool isRegisterErrorCode(Object? wert) => wert is String && registerErrorCodes.contains(wert);

/// Der Code eines geworfenen Fehlers, wenn er einer der Anmeldung ist; sonst `null`.
String? registerErrorCode(Object? fehler) =>
    fehler is KasseneckApiError && isRegisterErrorCode(fehler.code) ? fehler.code : null;

/// Kurzform für `catch (e) { if (isRegisterError(e, 'cashregister_in_use')) … }`.
/// Ohne [code]: ist es überhaupt ein Fehler der Kassen-Anmeldung?
bool isRegisterError(Object? fehler, [String? code]) {
  final gefunden = registerErrorCode(fehler);
  return gefunden != null && (code == null || gefunden == code);
}

/// Die Angaben einer Abweisung, soweit sie welche trägt. Was fehlt, ist
/// `null`; [deviceLabel] ist auch dann `null`, wenn das belegende Gerät
/// keinen Namen hat (die Oberfläche sagt dann „ein anderes Gerät“).
class RegisterErrorDetails {
  const RegisterErrorDetails({
    this.deviceLabel,
    this.takeoverAllowed = false,
    this.retryAfterSec,
    this.distanceM,
    this.pairedDevices,
    this.licenses,
  });

  /// `cashregister_in_use`, `device_takeover_required`: Name des Geräts, das
  /// die Kasse hält.
  final String? deviceLabel;

  /// `cashregister_in_use`: darf dieser Benutzer die Kasse übernehmen?
  final bool takeoverAllowed;

  /// `too_many_attempts`: Sekunden bis zum nächsten Versuch.
  final num? retryAfterSec;

  /// `location_outside`: Abstand zum Betrieb in Metern.
  final num? distanceM;

  /// `licenses_exhausted`: gekoppelte Geräte und Lizenzen.
  final num? pairedDevices;
  final num? licenses;
}

RegisterErrorDetails registerErrorDetails(Object? fehler) {
  final d = fehler is KasseneckApiError ? fehler.details : const <String, dynamic>{};
  num? zahl(Object? v) => v is num && v.isFinite ? v : null;
  final label = d['deviceLabel'];
  return RegisterErrorDetails(
    deviceLabel: label is String && label.isNotEmpty ? label : null,
    takeoverAllowed: d['takeoverAllowed'] == true,
    retryAfterSec: zahl(d['retryAfterSec']),
    distanceM: zahl(d['distanceM']),
    pairedDevices: zahl(d['pairedDevices']),
    licenses: zahl(d['licenses']),
  );
}

/// Ein Feldfehler aus `details.errors[]` einer `validation`-Antwort.
class FieldError {
  const FieldError(this.field, this.message);

  /// Feldpfad in der gesendeten Anfrage (`deviceId`, `business.vatRates`).
  final String field;
  final String message;

  @override
  bool operator ==(Object other) => other is FieldError && other.field == field && other.message == message;

  @override
  int get hashCode => Object.hash(field, message);

  @override
  String toString() => 'FieldError($field: $message)';
}

/// Die Feldfehler einer `validation`-Antwort; leer, wenn es keine sind.
List<FieldError> fieldErrors(Object? fehler) {
  if (fehler is! KasseneckApiError) return const [];
  final roh = fehler.details['errors'];
  if (roh is! List) return const [];
  return [
    for (final e in roh)
      if (e is Map && e['field'] is String && e['message'] is String)
        FieldError(e['field'] as String, e['message'] as String),
  ];
}

/// Feldfehler der Anmeldung (Zwilling von `registerFieldErrors`).
List<FieldError> registerFieldErrors(Object? fehler) => fieldErrors(fehler);
