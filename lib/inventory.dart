/// Die Lager-API: Artikel, Standorte, Bestand und Lagerprotokoll lesen,
/// Konto-Webhooks verwalten und eingehende Zustellungen pruefen (Backend
/// Stufe 5a); Artikel anlegen und aendern, Bestand buchen und Ware
/// reservieren (Stufe 5b, seit 10.4); Variantengruppen (Stufe 5c, seit 10.5);
/// Inventur (Lager-Kern Stufe 3, seit 10.7) – Zwilling von
/// `@kreiseck/kasseneck-api/inventory` im JS-Paket.
///
/// Der Schluessel ist der `api_key` des Kontos, **ohne** Kassen-Token. Er
/// gehoert auf einen **Server** (etwa das Backend eines Online-Shops), nie in
/// eine App, die Kunden installieren. Lesen braucht das Modul `lager`,
/// Schreiben dazu den Konto-Schalter „Lager-API schreiben“; Einkaufspreise und
/// Lagerwerte kommen nur mit dem Recht `costs`. Jede schreibende Anfrage
/// traegt einen `idempotencyKey`.
///
/// Mengen in Tausendstel der Basiseinheit, Geld in Cent, Einkaufspreise in
/// Mikro-Euro; alles Ganzzahlen.
///
/// `StockLevel` gibt es gleichnamig im Kassenweg (`pos.dart`); wer beide
/// Bibliotheken einbindet, nimmt fuer eine ein Praefix.
library;

export 'src/lager/anfragen.dart';
export 'src/lager/api.dart';
export 'src/lager/fehler.dart';
export 'src/lager/modelle.dart';
export 'src/lager/transport.dart' show InventoryTransport, PdfOrData, PdfOrDataFile, PdfOrDataPayload, kInventoryBaseUrl;
export 'src/lager/vertrag.dart';
export 'src/lager/webhook.dart';
// Der Lagerwert ist derselbe wie an der Kasse: ein Typ, kein Namenskonflikt.
export 'src/kasse/lager.dart' show StockValue;
// Die Fehler, die die Aufrufe werfen; ohne sie waeren sie aus diesem Barrel
// nicht zu fangen.
export 'src/register/fehler.dart'
    show ErrorOutcome, KasseneckApiError, KasseneckHttpError, KasseneckValidationError, isOutcomeUnknown;
