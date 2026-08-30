/// Die Fehlercodes der Partner-API und das, was ein Integrator daraufhin tun
/// muss.
///
/// Das Backend antwortet auf jeden fachlichen Ausgang mit HTTP 200 und legt
/// seine Entscheidung in `data.code` (siehe `docs/api/partner.md` im Backend).
/// Der Transport hebt den Code an `KasseneckApiError.code`; hier steht, was er
/// bedeutet.
///
/// **Warum die Texte hier stehen und nicht nur im Backend:** die Meldung des
/// Servers sagt, WAS ist. Sie sagt nicht, was der Aufrufer als naechstes tut,
/// und sie kann es auch nicht: `vertrag_offen` bedeutet je nach Vertragsweg des
/// Partner-Kontos drei verschiedene naechste Schritte. Diese Datei ist deshalb
/// kein zweiter Abdruck der Doku, sondern die Handlungsanweisung daneben.
library;

import '../register/fehler.dart';

/// Die drei Wege, auf denen ein Betrieb zum Auftragsverarbeitungsvertrag kommt.
enum AvvModus {
  /// Vorgabe: der Betrieb bestaetigt selbst, im Panel oder ueber den
  /// Einrichtungs-Link.
  direkt,

  /// Der Partner holt die Zustimmung in unserem Namen ein und meldet sie mit
  /// `reportCustomerVertrag`.
  vollmacht,

  /// Der Betrieb hat den Vertrag mit dem Partner; Kasseneck ist
  /// Unterauftragsverarbeiter.
  unterauftrag,
}

// Die Namen der Aufzaehlung sind genau die, unter denen Kasseneck die drei
// Wege fuehrt (`partner.avvModus`) -- `AvvModus.vollmacht.name` ist
// "vollmacht". Deshalb gibt es hier keine zweite Zuordnungstabelle.

/// Vorgabe, solange Kasseneck fuer das Partner-Konto nichts anderes gesetzt hat.
const AvvModus kAvvModusStandard = AvvModus.direkt;

/// Die Staende, die `betrieb.avv.status` annehmen kann.
///
/// `nicht_erforderlich` ist der Test-Betrieb: dort wird nichts Echtes
/// verarbeitet, es gibt keinen Vertragsgegenstand, und das Live-Gate greift gar
/// nicht. **Er darf nicht wie `offen` behandelt werden** -- ein "Vertrag fehlt"
/// an einem Test-Betrieb schickt einen Integrator auf die Suche nach einem
/// Problem, das es nicht gibt.
///
/// Bewusst eine Liste von Zeichenketten und keine Aufzaehlung: eine spaetere
/// Backend-Fassung soll einen neuen Stand durchreichen koennen, statt hier zu
/// scheitern.
const List<String> kAvvStatus = <String>[
  'offen',
  'bestaetigt',
  'veraltet',
  'ueber_partner',
  'nicht_erforderlich',
];

/// Was ein Stand bedeutet -- als Text, fuer eine Anzeige. `null` fuer einen
/// Wert, den dieses Paket nicht kennt; ein erfundener Text waere schlimmer als
/// keiner.
String? avvStatusText(String status) => const <String, String>{
      'offen': 'Der Auftragsverarbeitungsvertrag fehlt -- es geht keine neue Kasse live.',
      'bestaetigt': 'Die geltende Fassung ist bestaetigt.',
      'veraltet': 'Bestaetigt, aber inzwischen gilt eine neuere Pflichtfassung.',
      'ueber_partner': 'Im Weg "unterauftrag" durch den eigenen Partnervertrag abgedeckt.',
      'nicht_erforderlich': 'Testumgebung -- kein Vertragsgegenstand, keine Sperre.',
    }[status];

/// Steht dem Live-Betrieb aus Sicht des Auftragsverarbeitungsvertrags nichts im
/// Weg? Drei Staende sagen ja -- `bestaetigt`, `ueber_partner` und
/// `nicht_erforderlich` (Testumgebung).
///
/// [avvErfuellt] und [avvSperrt] sind **nicht** die Umkehrung voneinander: fuer
/// einen Stand, den dieses Paket nicht kennt, sind beide `false`. Das ist die
/// ehrliche Antwort -- die Auskunft, ob eine Kasse live geht, gibt der Server
/// mit `vertrag_offen`, nicht diese Funktion. Wer aus "nicht erfuellt" auf
/// "gesperrt" schliesst, warnt beim naechsten neuen Stand vor etwas, das nicht
/// ist.
bool avvErfuellt(String? status) =>
    status == 'bestaetigt' || status == 'ueber_partner' || status == 'nicht_erforderlich';

/// Sperrt dieser Stand den Live-Betrieb? Nur `offen` und `veraltet` tun das.
bool avvSperrt(String? status) => status == 'offen' || status == 'veraltet';

/// Was fuer einen Test-Betrieb zu tun ist: nichts.
const String kAvvNichtErforderlichRat =
    'Nichts zu tun: dieser Betrieb liegt in der Testumgebung. Dort wird nichts Echtes verarbeitet -- '
    'es gibt keinen Vertragsgegenstand und keine Sperre. Der Auftragsverarbeitungsvertrag wird erst '
    'fuer den Live-Betrieb gebraucht.';

/// Liest den Weg aus seinem Namen; `null` bei einem unbekannten Wert.
AvvModus? avvModusAus(String? wert) => switch (wert) {
      'direkt' => AvvModus.direkt,
      'vollmacht' => AvvModus.vollmacht,
      'unterauftrag' => AvvModus.unterauftrag,
      _ => null,
    };

/// Alle Codes, die die Partner-API kennt. Als Liste und nicht nur als
/// Aufzaehlung, damit ein Aufrufer sie zur Laufzeit durchgehen kann
/// (Katalogseite, Selbsttest der eigenen Fehlerbehandlung).
const List<String> kPartnerFehlerCodes = <String>[
  // Eingabe und Konto
  'validation',
  'app_not_found',
  'app_not_accepted',
  'customer_exists',
  'customer_conflict',
  'email_taken',
  'customer_limit',
  'rate_limited',
  // Vertrag (Art. 28 DSGVO)
  'vertrag_offen',
  'modus_not_allowed',
  'vollmacht_fehlt',
  'text_changed',
  'art_not_allowed',
  'already_accepted',
  'not_found',
  // Signatur und Kasse
  'fon_missing',
  'no_card_available',
  'signature_pending',
  'signature_not_ready',
  'signature_failed',
  'module_inactive',
  'cashregister_limit',
  'cashregister_not_found',
  'activation_failed',
  // Webhooks
  'webhook_limit',
  'event_not_subscribed',
  'webhook_inactive',
];

bool istPartnerFehlerCode(Object? wert) =>
    wert is String && kPartnerFehlerCodes.contains(wert);

/// Was der Aufrufer tun muss. Ein Satz je Code, in der zweiten Person -- nicht
/// die Wiederholung der Server-Meldung, sondern der naechste Handgriff.
///
/// `vertrag_offen` fehlt hier mit Absicht: sein naechster Handgriff haengt am
/// Vertragsweg des Partner-Kontos, den nur der Aufrufer kennt. Dafuer gibt es
/// [vertragOffenRat].
const Map<String, String> _rat = <String, String>{
  'validation': 'Eingaben pruefen -- data.errors nennt Feld und Grund. Es wurde nichts angelegt.',
  'app_not_found': 'Die appId gibt es nicht. getPartnerInfo liefert die eigenen Apps samt id.',
  'app_not_accepted':
      'Diese App hat noch keine abgenommene Version. Mit einem pk_test_-Schluessel geht es sofort weiter; live erst nach der Abnahme.',
  'customer_exists': 'Diesen Betrieb gibt es schon (data.customerId). Mit derselben customerId weiterarbeiten.',
  'customer_conflict':
      'Die Steuernummer ist bei Kasseneck bereits registriert. Die Zuordnung zum Partner macht Kasseneck -- hello@kasseneck.at.',
  'email_taken':
      'Fuer diese E-Mail gibt es schon einen Kasseneck-Zugang. Eine andere Adresse waehlen oder den Betrieb zuordnen lassen.',
  'customer_limit': 'Das Tageslimit fuer neue Betriebe ist erreicht (data.max, data.resetAt). Morgen weiter.',
  'rate_limited': 'Zu viele Aufrufe. data.retryAfterSec Sekunden warten und denselben Aufruf wiederholen.',
  'modus_not_allowed':
      'Fuer dieses Partner-Konto ist der Vollmachtsweg nicht freigeschaltet. reportCustomerVertrag ist damit nicht der richtige Weg.',
  'vollmacht_fehlt':
      'Der Partnervertrag mit dem Vollmachts-Kapitel ist nicht bestaetigt. Im Partner-Portal bestaetigen, dann erneut melden.',
  'text_changed':
      'Der gemeldete textHash passt nicht zur geltenden Fassung. Den aktuellen Text holen, erneut anzeigen, mit dem neuen Hash melden -- die alte Zustimmung gilt nicht.',
  'art_not_allowed': 'In Vollmacht laesst sich nur der Auftragsverarbeitungsvertrag (art:"avv") melden.',
  'already_accepted': 'Dieser Vertrag ist in dieser Fassung bereits bestaetigt. Nichts zu tun.',
  'not_found': 'Der genannte Datensatz gehoert nicht zu diesem Partner-Konto oder gibt es nicht.',
  'fon_missing':
      'Der Betrieb hat noch keinen FinanzOnline-Zugang. sendPartnerCustomerFonLink senden und customer.fon_verified abwarten.',
  'no_card_available':
      'Zurzeit ist keine gepruefte Signaturkarte frei. Kasseneck kuemmert sich und meldet sich -- hier ist nichts zu tun.',
  'signature_pending': 'Fuer diesen Betrieb laeuft bereits ein Antrag. Auf signature.ready warten.',
  'signature_not_ready':
      'Die Signatur ist noch nicht bereit. Auf das Ereignis signature.ready warten; eine mit automatisch:true angelegte Kasse geht danach von selbst live.',
  'signature_failed':
      'FinanzOnline hat die Registrierung abgelehnt (data.rc). Kasseneck klaert das -- hello@kasseneck.at.',
  'module_inactive': 'Das Modul (data.modul) ist fuer diesen Betrieb nicht gebucht. Kasseneck schaltet es frei.',
  'cashregister_limit': 'Hoechstens 20 Registrierkassen je Betrieb. Eine bestehende nutzen.',
  'cashregister_not_found': 'Diese cashregisterId gibt es bei diesem Betrieb nicht.',
  'activation_failed':
      'Die Inbetriebnahme blieb an data.schritt haengen (ggf. data.rc). activateCashregister erneut aufrufen -- jeder Schritt ist idempotent, der Lauf setzt an der Bruchstelle an.',
  'webhook_limit': 'Hoechstens 10 Webhook-Endpunkte je Partner. Einen ungenutzten loeschen.',
  'event_not_subscribed': 'Der Endpunkt abonniert das Ereignis nicht. events erweitern und erneut versuchen.',
  'webhook_inactive': 'Der Webhook steht auf aktiv:false. Zuerst aktivieren.',
};

/// Was `vertrag_offen` fuer dieses Partner-Konto bedeutet.
///
/// Ohne bestaetigten Auftragsverarbeitungsvertrag (Art. 28 DSGVO) nimmt
/// Kasseneck **keine neue Kasse** in Betrieb; laufende Kassen bleiben
/// unberuehrt. Welcher der drei Wege gilt, setzt Kasseneck je Partner-Konto --
/// die Partner-API gibt ihn heute nicht aus, er ist deshalb Teil der
/// Client-Einstellungen (`PartnerApi.avvModus`).
String vertragOffenRat([AvvModus modus = kAvvModusStandard]) => switch (modus) {
      AvvModus.vollmacht =>
        'Der Auftragsverarbeitungsvertrag dieses Betriebs fehlt. Vertragsweg "vollmacht": '
            'den unveraenderten Kasseneck-Text in der eigenen App zeigen, die Zustimmung einholen '
            'und mit reportCustomerVertrag melden (art:"avv", passender textHash). '
            'Danach die Kasse erneut aktivieren.',
      AvvModus.unterauftrag =>
        'Der Auftragsverarbeitungsvertrag dieses Betriebs fehlt. Vertragsweg "unterauftrag": '
            'der Betrieb hat den Vertrag mit euch, Kasseneck ist Unterauftragsverarbeiter. '
            'Faellt die Deckung weg (Partnervertrag beendet oder Partner-Konto gesperrt), steht der '
            'Betrieb wieder auf offen -- dann klaert das Kasseneck, hello@kasseneck.at.',
      AvvModus.direkt =>
        'Der Auftragsverarbeitungsvertrag dieses Betriebs fehlt. Vertragsweg "direkt" (Vorgabe): '
            'der Betrieb bestaetigt selbst -- im Kasseneck-Panel oder ueber den Einrichtungs-Link. '
            'Ein Partner kann das auf diesem Weg nicht fuer ihn tun. Das Ereignis '
            'customer.avv_accepted meldet die Bestaetigung.',
    };

/// Wie [vertragOffenRat], nur mit Stand und Weg aus dem Betrieb selbst -- der
/// verlaesslichen Quelle: `listPartnerCustomers` und `getPartnerCustomer`
/// fuehren beides je Betrieb mit. Fehlt der Weg (aeltere Backend-Fassung),
/// gilt [rueckfall].
///
/// **`nicht_erforderlich` bekommt einen eigenen Satz**, keinen abgeschwaechten:
/// an einem Test-Betrieb kann `vertrag_offen` gar nicht entstehen, und ein
/// "bitte bestaetigen lassen" schickte den Aufrufer auf eine Suche ohne Ziel.
///
/// Fuer jeden anderen Stand -- auch `bestaetigt` -- bleibt es beim Weg-Satz:
/// das Live-Gate prueft **alle** sperrenden Vertragsarten, nicht nur den
/// Auftragsverarbeitungsvertrag. Ein `vertrag_offen` bei `avv.status:
/// "bestaetigt"` ist damit moeglich, und "nichts zu tun" waere dann falsch.
String vertragOffenRatFuer(
  AvvModus? modus, {
  String? status,
  AvvModus rueckfall = kAvvModusStandard,
}) {
  if (status == 'nicht_erforderlich') return kAvvNichtErforderlichRat;
  return vertragOffenRat(modus ?? rueckfall);
}

/// Der Handlungssatz zu einem Code. [modus] wird nur fuer `vertrag_offen`
/// gebraucht und sonst nicht angesehen.
String? partnerFehlerRat(String code, [AvvModus modus = kAvvModusStandard]) =>
    code == 'vertrag_offen' ? vertragOffenRat(modus) : _rat[code];

/// Der Fehlercode eines gefangenen Fehlers -- `null`, wenn es keiner der
/// unseren ist.
String? partnerFehlerCode(Object? fehler) =>
    fehler is KasseneckApiError ? fehler.code : null;

/// Kurzform fuer `catch (e) { if (istPartnerFehler(e, 'vertrag_offen')) ... }`.
bool istPartnerFehler(Object? fehler, String code) =>
    partnerFehlerCode(fehler) == code;

/// Ein Feldfehler aus `data.errors[]` einer `validation`-Antwort.
class PartnerFeldFehler {
  const PartnerFeldFehler(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => 'PartnerFeldFehler($field): $message';
}

/// Die Feldfehler einer `validation`-Antwort; leer, wenn es keine sind.
List<PartnerFeldFehler> partnerFeldFehler(Object? fehler) {
  if (fehler is! KasseneckApiError) return const <PartnerFeldFehler>[];
  final roh = fehler.details['errors'];
  if (roh is! List) return const <PartnerFeldFehler>[];
  final raus = <PartnerFeldFehler>[];
  for (final eintrag in roh) {
    if (eintrag is! Map) continue;
    final field = eintrag['field'];
    final message = eintrag['message'];
    if (field is String && message is String) raus.add(PartnerFeldFehler(field, message));
  }
  return raus;
}

/// Wie lange `rate_limited` noch gilt, in Sekunden. `null`, wenn der Fehler
/// kein `rate_limited` ist oder das Backend keine Angabe macht.
int? partnerWartezeitSek(Object? fehler) {
  if (partnerFehlerCode(fehler) != 'rate_limited') return null;
  final wert = (fehler as KasseneckApiError).details['retryAfterSec'];
  if (wert is num && wert.isFinite && wert >= 0) return wert.toInt();
  return null;
}
