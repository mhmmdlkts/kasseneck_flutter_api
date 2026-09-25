/// Mehrere Zahlungen je Beleg -- Fehlercode-Katalog, Zwilling von
/// `functions/gemeinsam/zahlungen-core.js` ZAHLUNGS_FEHLERCODES und
/// `@kreiseck/kasseneck-api` PAYMENT_ERROR_CODES (gleiche Codes, gleiche
/// Reihenfolge).
///
/// `createReceipt` und `cancelReceipt` legen sie bei jedem Fehler rund um
/// `payments` als `code` neben die Meldung; sie kommen als
/// `KasseneckApiError.code` an. **Entscheide am Code, nie am Text.**
///
/// Schreibweise: auf `/v1`, `/v2` und intern gross (`PAYMENTS_SUM_MISMATCH`),
/// unter `/v3` klein (`payments_sum_mismatch`, jeder Code 1:1). Anders als die
/// Storno-Codes, die `/v3` umbenennt -- darum prueft [istZahlungFehlercode]
/// beide Schreibweisen, `istStornoFehlercode` dagegen exakt.
library;

const List<String> zahlungFehlercodes = [
  'PAYMENTS_INVALID', // payments ist keine Liste oder hat mehr als 20 Eintraege
  'PAYMENT_METHOD_INVALID', // Zahlart unbekannt oder mixed
  'PAYMENT_AMOUNT_INVALID', // amountCents keine Ganzzahl, 0 oder falsches Vorzeichen
  'PAYMENT_TENDERED_INVALID', // tenderedCents an Nicht-Bar-Zahlung, zu klein oder doppelt
  'PAYMENT_PROVIDER_INVALID', // Karte ohne/mit unbekanntem provider, providerPaymentId fehlt
  'PAYMENT_PROVIDER_NOT_ALLOWED', // Anbieterfelder an einer Zahlung, die weder Karte noch online ist
  'PAYMENTS_SUM_MISMATCH', // Summe != Zahlbetrag (Antwort nennt data.expectedCents)
  'PAYMENTS_DUE_NEGATIVE', // Zahlbetrag < 0 (Wertgutschein groesser als der Beleg)
  'PAYMENTS_NOT_ALLOWED', // Null-/Startbeleg mit Zahlungen, alter Storno-Weg
  'PAYMENTS_CONFLICT', // payments zusammen mit paymentMethod oder Kartenfeldern
  'PAYMENTS_REQUIRED', // /v3 ohne payments
  'PAYMENT_METHOD_NOT_SUPPORTED', // paymentMethod/Kartenfelder unter /v3
  'TIP_PAYMENT_METHOD_INVALID', // Trinkgeld-Zahlart kommt in payments nicht vor
  'TIP_PAYMENT_METHOD_REQUIRED', // mehrere Zahlarten, tip.paymentMethod fehlt
  'TIP_EXCEEDS_PAYMENT', // Trinkgeld uebersteigt die Zahlungen seiner Zahlart
  'PAYMENT_REFUND_NOT_ALLOWED', // refundOf ausserhalb eines Stornos oder kein String
  'PAYMENT_TIP_INVALID', // tipCents keine Ganzzahl, <= 0, > amountCents oder nicht am Verkauf
  'TIP_CONFLICT', // tip und payments[].tipCents zugleich
];

/// Ist [wert] ein Code aus [zahlungFehlercodes] -- gross (`/v1`) wie klein
/// (`/v3`)? Ein Anzeigetext ist keiner.
bool istZahlungFehlercode(Object? wert) => wert is String && zahlungFehlercodes.contains(wert.toUpperCase());
