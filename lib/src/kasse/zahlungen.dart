/// Mehrere Zahlungen je Beleg -- Fehlercode-Katalog unter `/v3`, Zwilling von
/// `@kreiseck/kasseneck-api` PAYMENT_ERROR_CODES (gleiche Codes, gleiche
/// Reihenfolge, siehe `receipt/codes.dart`).
///
/// `createReceipt` und `cancelReceipt` legen sie bei jedem Fehler rund um
/// `payments` als `code` neben die Meldung; sie kommen als
/// `KasseneckApiError.code` an. **Entscheide am Code, nie am Text.**
library;

import '../receipt/codes.dart' show paymentErrorCodes;
import '../register/fehler.dart' show KasseneckApiError;

/// Die Codes, gleiche Reihenfolge wie `PAYMENT_ERROR_CODES`.

/// Ist [value] ein Code aus [paymentErrorCodes]? Exakt, wie unter `/v3`
/// (klein); ein grosser Code aus `/v1` ist keiner. Ein Anzeigetext auch nicht.
bool isPaymentErrorCode(Object? value) => value is String && paymentErrorCodes.contains(value);

/// Der Zahlbetrag des Servers aus einem `payments_sum_mismatch`
/// (`details.expectedCents`), sonst `null`. Das Paket wiederholt nie selbst mit
/// diesem Betrag: eine Kartenzahlung ist schon belastet. Die Kasse entscheidet
/// (Differenz nachkassieren oder erstatten) und schickt dann einen neuen
/// Verkauf. Zwilling von `paymentsExpectedCents` im npm-Paket.
int? paymentsExpectedCents(Object? error) {
  if (error is! KasseneckApiError || error.code != 'payments_sum_mismatch') return null;
  final wert = error.details['expectedCents'];
  return wert is int ? wert : null;
}
