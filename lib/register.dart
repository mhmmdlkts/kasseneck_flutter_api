/// Kopplung und Anmeldung eines Kassengeräts (RKSV-Kasse).
///
/// Der Einstieg ist [RegisterClient]. Diese Aufrufe laufen ohne Anmeldung —
/// der Kopplungs-Code aus dem Panel bzw. das Gerätegeheimnis ist der Nachweis.
/// Sie stehen bewusst neben `KasseneckApi`, die einen `api_key` braucht.
library;

export 'src/register/pairing.dart';
