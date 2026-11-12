/// Technik von hobex: Nummer und Erreichbarkeit fuer das Fenster „Technik von
/// hobex“ der Kasse. Zwilling von `support.ts` im npm-Paket (1.37.0).
library;

/// Technik von hobex fuer Haendler mit hobex-Terminal, rund um die Uhr
/// erreichbar. Quelle: Angabe des Inhabers am 11.11.2026 („hobex Technik
/// 0662 225588“); es ist die Durchwahl 88 der Zentrale +43 662 2255-0 (hobex,
/// „Zahlen & Fakten“).
///
/// `phone` international (fuer einen `tel:`-Link nur Ziffern und `+` daraus
/// nehmen), `display` so, wie man sie in Oesterreich liest und waehlt,
/// `availability` die Erreichbarkeit („24/7“). Gedacht fuer die Stellen, an
/// denen hobex helfen kann: Stoerung beim hobex-Host, Terminal nicht
/// betriebsbereit, TID passt nicht, das Terminal hat geantwortet und kennt den
/// Ausgang nicht -- nie fuer Fehler im eigenen Netz oder an Kasseneck Connect.
/// Die Kasse zeigt sie in einem eigenen Fenster mit den Angaben, die hobex
/// fragt (Beschriftungen `hobex_help.*` im Textkatalog der Kasse).
///
/// Zwilling von `HOBEX_SUPPORT` (`./payments`). Ein Record ist unveraenderlich
/// wie das eingefrorene Objekt dort.
const ({String phone, String display, String availability}) hobexSupport = (
  phone: '+43 662 2255-88',
  display: '0662 2255-88',
  availability: '24/7',
);
