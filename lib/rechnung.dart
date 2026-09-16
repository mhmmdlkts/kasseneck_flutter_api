/// Rechnungen (§ 11 UStG, keine Belege) und Kunden über die Rechnungs-API —
/// Zwilling von `@kreiseck/kasseneck-api/rechnung` im JS-Paket.
///
/// Der Schlüssel ist der `api_key` des Kontos, **ohne** Kassen-Token. Live
/// braucht das Konto die Freigabe durch Kasseneck; vor dem ersten Ausstellen
/// [RechnungApi.getInvoiceSetupStatus] aufrufen.
library;

export 'src/rechnung/api.dart';
export 'src/rechnung/modelle.dart';
export 'src/rechnung/summen.dart';
export 'src/rechnung/transport.dart' show RechnungTransport, kRechnungBaseUrl;
export 'src/rechnung/vertrag.dart';
// Die Fehler, die die Aufrufe werfen — ohne sie wären sie aus diesem Barrel
// nicht zu fangen.
export 'src/register/fehler.dart' show KasseneckApiError, KasseneckHttpError, KasseneckValidationError;
