/// Partner-API: alles, was ein Partner-Softwarehaus über die
/// Kasseneck-Schnittstelle tut — Betriebe anlegen und bis zur laufenden Kasse
/// begleiten, danach in ihrem Namen Belege signieren.
///
/// Einstieg ist [PartnerApi]. Sie steht bewusst **neben** `KasseneckApi`: der
/// Partner-Schlüssel (`pk_live_…`) gehört auf einen Server, `KasseneckApi`
/// braucht dagegen den `api_key` eines einzelnen Betriebs.
///
/// **Was die Endpunkte tun, steht in der Referenz des Backends** —
/// `docs/api/partner.md` (ausführlich) und `docs/api/partner.llms.txt`
/// (kompakt, für Werkzeuge und Sprachmodelle). Dieses Paket wiederholt sie
/// nicht; hier steht die Benutzung.
///
/// Die Reihenfolge der Kette steht als Daten in [kPartnerAblauf], die
/// Fehlercodes samt Handlungssatz in [partnerFehlerRat].
///
/// Der Zwilling in JavaScript ist `@kreiseck/kasseneck-api/partner`.
library;

export 'src/partner/ablauf.dart';
export 'src/partner/api.dart';
export 'src/partner/fehler.dart';
export 'src/partner/secret.dart';
export 'src/partner/transport.dart' show PartnerTransport, kPartnerBaseUrl, partnerSchluesselEnv;
export 'src/partner/typen.dart';
export 'src/partner/webhook_signatur.dart';
export 'src/partner/webhooks.dart';
// Die Fehlerarten sind Teil der öffentlichen Signatur jedes Aufrufs — ohne
// diese Exporte könnte ein Aufrufer, der nur dieses Barrel importiert, sie
// nicht benennen und damit nicht gezielt fangen.
export 'src/register/fehler.dart'
    show KasseneckApiError, KasseneckHttpError, KasseneckValidationError, fehlerDetails;
