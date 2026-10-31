/// Der Idempotenz-Schluessel am Verkauf (`idempotencyKey` an `createReceipt`),
/// gemeinsam fuer `KasseneckApi.sellReceipt` und
/// `RegisterReceiptClient.sell`. Zwilling von `belegSchluessel` in
/// `client/receipts.ts` des npm-Pakets.
library;

/// Hoechstlaenge wie am Server (`beleg-idempotenz-core`, `SCHLUESSEL_MAX`);
/// gemessen wie dort in UTF-16-Einheiten (`String.length`).
const int _belegSchluesselMax = 120;

/// Grund, warum [schluessel] nicht als `idempotencyKey` hinausgeht; `null`,
/// wenn er passt. Dieselbe Regel wie am Server: nicht nur Leerraum,
/// hoechstens 120 Zeichen. Gesendet wird er unveraendert: der Server erkennt
/// die Wiederholung am Schluessel, wie er ankommt, ein gekuerzter oder
/// getrimmter waere ein anderer.
String? belegSchluesselFehler(String schluessel) {
  if (schluessel.trim().isEmpty || schluessel.length > _belegSchluesselMax) {
    return 'idempotencyKey muss ein Text mit 1 bis $_belegSchluesselMax Zeichen sein (oder weglassen); er wird nie gekuerzt.';
  }
  return null;
}
