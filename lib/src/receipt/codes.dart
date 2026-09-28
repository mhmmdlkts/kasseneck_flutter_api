/// Fehlercodes der Belegwelt unter `/v3`, Zwilling der Kataloge in
/// `@kreiseck/kasseneck-api` 1.0 (`RECEIPT_ERROR_CODES`,
/// `CANCELLATION_ERROR_CODES`, `PAYMENT_ERROR_CODES`,
/// `RECEIPT_EMAIL_ERROR_CODES`), gleiche Codes, gleiche Reihenfolge.
///
/// Jede Liste nennt zuerst die Codes des Endpunkts, dahinter (sortiert, ohne
/// Doppel) die, die Anmeldung und Rand auf jedem Endpunkt des Kassenwegs
/// erzeugen koennen (`errorCodes.auth` ohne den Partner-Zugang und
/// `errorCodes.edge` des Vokabulars), zuletzt die Codes des Pakets
/// (`route_missing` ueberall, `response_unreadable` nur an den signierenden
/// Aufrufen). Die Codes sind klein und englisch; ein grosser Code aus `/v1`
/// ist keiner. **Entscheide am Code, nie am Text.**
library;

/// Anmeldung und Rand, sortiert: auf jedem Endpunkt des Kassenwegs moeglich.
const List<String> anmeldungUndRandCodes = [
  'account_not_found',
  'admin_required',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'dialect_mismatch',
  'internal_translation_error',
  'live_not_enabled',
  'method_not_allowed',
  'mfa_required',
  'not_found',
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
];

List<String> _mitRand(List<String> eigen, List<String> paket) => List.unmodifiable([
      ...eigen,
      for (final c in anmeldungUndRandCodes)
        if (!eigen.contains(c)) c,
      ...paket,
    ]);

const _signierend = ['route_missing', 'response_unreadable'];

/// Codes von `createReceipt` und `getReceipt` (ohne die Zahlungscodes, die
/// stehen in `zahlungFehlercodes`). `receipt_outcome_unknown` heisst: der
/// Beleg ist moeglicherweise signiert, nachlesen statt wiederholen.
final List<String> receiptErrorCodes = _mitRand(const [
  'cancellation_reference_unavailable',
  'cashregister_closed',
  'cashregister_decommissioned',
  'final_receipt_expired',
  'final_receipt_not_allowed',
  'module_inactive',
  'not_permitted',
  'receipt_limit_exceeded',
  'receipt_not_found',
  'receipt_outcome_unknown',
  'receipt_type_invalid',
  'signature_incomplete',
  'signature_missing',
  'signing_failed',
  'small_business_vat_not_allowed',
  'tip_invalid',
  'tip_not_allowed',
  'tip_recipient_unknown',
  'validation',
], _signierend);

/// Ist [wert] ein Code aus [receiptErrorCodes]?
bool isReceiptErrorCode(Object? wert) => wert is String && receiptErrorCodes.contains(wert);

/// Codes von `cancelReceipt` (Formfehler an `payments` stehen in
/// `zahlungFehlercodes`).
final List<String> cancellationErrorCodes = _mitRand(const [
  'receipt_not_found', // Original fehlt oder gehoert nicht zu dieser Kasse
  'receipt_type_not_cancellable', // Original ist selbst Storno-, Null- oder Startbeleg
  'training_receipt', // Trainingsbelege werden nicht storniert
  'already_cancelled', // keine Restmenge mehr
  'invalid_line', // Index unbekannt oder doppelt
  'quantity_exceeds_remaining', // Menge nicht ganzzahlig >= 1 oder groesser als der Rest
  'unknown_reason', // reason fehlt oder nicht im Katalog
  'note_too_long', // note laenger als 200 Zeichen
  'invalid_items', // items ist keine Liste
  'cashregister_not_assigned', // Kassen-Benutzer darf diese Kasse nicht
  'not_permitted', // Kassen-Benutzer ohne Storno-Recht
  'own_receipts_only', // Recht „eigene", fremder Beleg
  'cashregister_incomplete', // api_key/token fehlen am Konto bzw. an der Kasse
  'cancellation_failed', // der Storno-Beleg selbst wurde abgelehnt (z. B. Signatur)
  'cancellation_payments_required', // Teilstorno eines Belegs mit mehreren Zahlungen ohne payments
  'cancellation_refund_exceeds_payment', // Rueckzahlungen auf eine Zahlung uebersteigen deren Rest
  'cancellation_refund_reference_required', // Karten-Rueckzahlung ohne refundOf einer Kartenzahlung
  'cancellation_refund_reference_unknown', // refundOf nennt keine Zahlung des Originals
  'cancellation_outcome_unknown', // Ausgang unklar: nachlesen, nie wiederholen
], _signierend);

/// Codes rund um `payments` an `createReceipt` und `cancelReceipt`.
final List<String> paymentErrorCodes = _mitRand(const [
  'payments_invalid', // payments ist keine Liste oder hat mehr als 20 Eintraege
  'payment_method_invalid', // Zahlart unbekannt oder mixed
  'payment_amount_invalid', // amountCents keine Ganzzahl, 0 oder falsches Vorzeichen
  'payment_tendered_invalid', // tenderedCents an Nicht-Bar-Zahlung, zu klein oder am Storno
  'payment_provider_invalid', // Karte ohne/mit unbekanntem provider, providerPaymentId fehlt
  'payment_provider_not_allowed', // Anbieterfelder an einer Zahlung, die weder Karte noch online ist
  'payments_sum_mismatch', // Summe != Zahlbetrag (details.expectedCents)
  'payments_due_negative', // Zahlbetrag < 0 (Wertgutschein groesser als der Beleg)
  'payments_not_allowed', // Null-/Startbeleg mit Zahlungen
  'payments_conflict', // payments zusammen mit paymentMethod oder Kartenfeldern
  'payments_required', // ohne payments
  'payment_method_not_supported', // paymentMethod/Kartenfelder am Beleg
  'tip_payment_method_invalid', // Trinkgeld-Zahlart kommt in payments nicht vor
  'tip_payment_method_required', // mehrere Zahlarten, tip.paymentMethod fehlt
  'tip_exceeds_payment', // Trinkgeld uebersteigt die Zahlungen seiner Zahlart
  'payment_refund_not_allowed', // refundOf ausserhalb eines Stornos oder kein String
  'payment_tip_invalid', // tipCents keine Ganzzahl, <= 0, > amountCents oder nicht am Verkauf
  'tip_conflict', // tip und payments[].tipCents zugleich
], const ['route_missing']);

/// Die fachlichen Codes von `sendReceiptEmail` (ohne Anmeldung und Rand).
const List<String> receiptEmailSendErrorCodes = [
  'invalid_address', // Empfaengeradresse unbrauchbar (Pruefung im Backend)
  'receipt_not_found', // Beleg gibt es nicht ODER er gehoert einer anderen Kasse
  'too_many_requests', // Schleuse: 5 Mails je Beleg (24 h), 30 je Kasse und Stunde
  'send_failed', // die Mail selbst ging nicht hinaus
];

/// Codes von `sendReceiptEmail`.
final List<String> receiptEmailErrorCodes = _mitRand(receiptEmailSendErrorCodes, const ['route_missing']);

/// Versandwege einer Belegmail (Katalog `MAILWEG`): Postfach des Betriebs,
/// Plattform, Plattform nach gescheitertem eigenen Postfach.
const List<String> receiptEmailVias = ['own', 'platform', 'platform_fallback'];

/// Stornostand eines Belegs in der Belegliste (Katalog `STORNO_STAND`).
const List<String> cancellationStatuses = ['none', 'partial', 'full'];
