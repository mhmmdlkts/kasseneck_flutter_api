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
/// und sie kann es auch nicht -- dafuer muesste sie seinen Ablauf kennen. Diese
/// Datei ist deshalb kein zweiter Abdruck der Doku, sondern die
/// Handlungsanweisung daneben.
///
/// **Der Katalog ist vollstaendig.** Die Quelle ist `docs/api/fehlercodes.json`
/// im Backend (Abzug aus `partner-core.FEHLER_KATALOG`); ein Code, den nur eine
/// Seite kennt, ist fuer einen Aufrufer nicht von "gibt es nicht" zu
/// unterscheiden. Deshalb stehen hier BEIDE Flaechen: die der Schnittstelle
/// ([kPartnerFehlerCodes]) und die des Partner-Portals
/// ([kPartnerPortalFehlerCodes]).
///
/// Der Zwilling in JavaScript ist `@kreiseck/kasseneck-api/partner`
/// (`src/partner/fehler.ts`); `test/zwillinge_test.dart` haelt beide Listen
/// gegeneinander.
library;

import '../register/fehler.dart';

/// Alle Codes, die die **Schnittstelle** kennt. Als Liste und nicht nur als
/// Aufzaehlung, damit ein Aufrufer sie zur Laufzeit durchgehen kann
/// (Katalogseite, Selbsttest der eigenen Fehlerbehandlung).
///
/// Reihenfolge und Bestand wie im Abzug des Backends.
const List<String> kPartnerFehlerCodes = <String>[
  // Eingabe, Konto und Takt
  'validation',
  'rate_limited',
  'app_not_found',
  'app_not_accepted',
  'kein_partnerbetrieb',
  'live_not_allowed',
  // Betrieb anlegen
  'customer_exists',
  'customer_conflict',
  'customer_limit',
  'zugang_nicht_erlaubt',
  'email_taken',
  'no_email',
  // Signatur
  'fon_missing',
  'signature_pending',
  'request_not_found',
  'signature_missing',
  'signature_unknown',
  'signature_ambiguous',
  'signature_not_ready',
  'signature_limit',
  'signature_failed',
  // Kasse
  'module_inactive',
  'cashregister_limit',
  'cashregister_not_found',
  'activation_failed',
  // Webhooks
  'webhook_limit',
  'webhook_inactive',
  'event_not_subscribed',
];

/// Die Codes, die nur im **Partner-Portal** entstehen -- beim Pflegen der App,
/// der Schluessel, der Mitglieder und der Signaturkarten.
///
/// Sie stehen hier, obwohl kein Aufruf dieses Clients sie ausloest: der
/// Fehlerkatalog ist eine Liste, und eine halbe Liste ist schlimmer als keine.
/// Wer eine Katalogseite baut oder eine fremde Antwort einsortiert, findet
/// damit jeden Code des Backends wieder.
const List<String> kPartnerPortalFehlerCodes = <String>[
  'app_locked',
  'version_locked',
  'invalid_transition',
  'no_accepted_app',
  'consent',
  'key_limit',
  'last_owner',
  'auth_user_exists',
  'card_missing',
  'card_duplicate',
  'card_not_verified',
  'already_assigned',
];

bool istPartnerFehlerCode(Object? wert) =>
    wert is String && kPartnerFehlerCodes.contains(wert);

bool istPartnerPortalFehlerCode(Object? wert) =>
    wert is String && kPartnerPortalFehlerCodes.contains(wert);

/// Was der Aufrufer tun muss. Ein Satz je Code, in der zweiten Person -- nicht
/// die Wiederholung der Server-Meldung, sondern der naechste Handgriff.
///
/// Jeder Code des Katalogs steht hier; `partner_client_test.dart` haelt das
/// fest. Ein Code ohne Satz waere schlimmer als ein fehlender Code: er sieht
/// aus wie behandelt und sagt nichts.
const Map<String, String> _rat = <String, String>{
  // -- Schnittstelle ---------------------------------------------------------
  'validation':
      'Eingaben pruefen -- data.errors nennt Feld und Grund, verschachtelt mit vollem Pfad (address.zip, contacts.0.email). Auch ein UNBEKANNTES Feld ist ein Formfehler: es wird abgewiesen und nicht stillschweigend verworfen. Es wurde nichts angelegt.',
  'rate_limited':
      'Zu viele Aufrufe. data.retryAfterSec Sekunden warten und denselben Aufruf wiederholen.',
  'app_not_found': 'Die appId gibt es nicht. getPartnerInfo liefert die eigenen Apps samt id.',
  'app_not_accepted':
      'Diese App hat noch keine abgenommene Version. Mit einem pk_test_-Schluessel oder mit env:"test" geht es sofort weiter; live erst nach der Abnahme.',
  'kein_partnerbetrieb':
      'Dieser Betrieb gehoert nicht zu diesem Partner-Konto. Die eigenen stehen in listPartnerCustomers.',
  'live_not_allowed':
      'Ein Test-Schluessel erzeugt nichts Echtes. Fuer einen Live-Betrieb den Live-Schluessel nehmen -- umgekehrt darf ein Live-Schluessel mit env:"test" sehr wohl einen Testbetrieb anlegen.',
  'customer_exists':
      'Diesen Betrieb gibt es schon (data.customerId). Mit derselben customerId weiterarbeiten.',
  'customer_conflict':
      'Die Steuernummer ist bei Kasseneck bereits registriert. Die Zuordnung zum Partner macht Kasseneck -- hello@kasseneck.at.',
  'customer_limit':
      'Das Tageslimit fuer neue Betriebe ist erreicht (data.max, data.resetAt). Morgen weiter.',
  'zugang_nicht_erlaubt':
      'Fuer dieses Partner-Konto sind Zugaenge zum Kundenpanel nicht freigeschaltet -- es entstand NICHTS, auch kein Betrieb. Ohne zugang{einladen:true} erneut anlegen oder die Freischaltung erfragen (Stand: getPartnerInfo.partner.darfZugangEinrichten).',
  'email_taken':
      'Fuer diese E-Mail gibt es schon einen Kasseneck-Zugang. Eine andere Adresse waehlen, auf die Einladung verzichten oder den Betrieb zuordnen lassen.',
  'no_email':
      'Im Konto des Betriebs steht keine E-Mail-Adresse. Ohne sie geht weder eine Einladung noch der FinanzOnline-Link hinaus.',
  'fon_missing':
      'Der Betrieb hat noch keinen FinanzOnline-Zugang. sendPartnerCustomerFonLink senden und customer.fon_verified abwarten. Betrifft das ANMELDEN der Signatureinheit, nicht das Beantragen.',
  'signature_pending': 'Fuer diesen Betrieb laeuft bereits ein Antrag. Auf signature.ready warten.',
  'request_not_found':
      'Diese signaturId gibt es nicht. getCustomerSignatureStatus nennt die des Betriebs.',
  'signature_missing':
      'Der Betrieb hat ueberhaupt keine Signatur, und jede Kasse bezieht sich auf eine. Zuerst requestCustomerSignature.',
  'signature_unknown':
      'Die genannte signaturId gehoert nicht zu diesem Betrieb. getCustomerSignatureStatus nennt die seinen.',
  'signature_ambiguous':
      'Der Betrieb hat mehrere Signaturen; welche die Kasse benutzt, muss dastehen. Eine aus data.auswahl als signaturId mitgeben.',
  'signature_not_ready':
      'Die Signatur DIESER Kasse ist noch nicht bereit. Auf signature.ready warten; eine mit automatisch:true angelegte Kasse geht danach von selbst live.',
  'signature_limit':
      'Hoechstens zehn Signaturen je Betrieb. Eine bestehende benutzen, statt mit weitere:true eine weitere zu beantragen.',
  'signature_failed':
      'FinanzOnline hat die Anmeldung abgelehnt (data.rc). Kasseneck klaert das -- hello@kasseneck.at.',
  'module_inactive':
      'Das Modul (data.modul) ist fuer diesen Betrieb nicht gebucht. Kasseneck schaltet es frei.',
  'cashregister_limit': 'Hoechstens 20 Registrierkassen je Betrieb. Eine bestehende nutzen.',
  'cashregister_not_found': 'Diese cashregisterId gibt es bei diesem Betrieb nicht.',
  'activation_failed':
      'Die Inbetriebnahme blieb an data.schritt haengen (ggf. data.rc). activateCashregister erneut aufrufen -- jeder Schritt ist idempotent, der Lauf setzt an der Bruchstelle an.',
  'webhook_limit': 'Hoechstens 10 Webhook-Endpunkte je Partner. Einen ungenutzten loeschen.',
  'webhook_inactive': 'Der Webhook steht auf aktiv:false. Zuerst aktivieren, dann erneut proben.',
  'event_not_subscribed':
      'Der Endpunkt abonniert dieses Ereignis nicht -- auch eine Probe bekommt nur, was in seiner events-Liste steht. events erweitern und erneut versuchen.',

  // -- Partner-Portal --------------------------------------------------------
  'app_locked':
      'Name, Verteilungen und Kontakt einer App sind fest, sobald eine Version geprueft wird. Aenderungen daran gehen ueber Kasseneck.',
  'version_locked':
      'Diese App-Version wird geprueft oder ist abgenommen. Fuer Aenderungen eine neue Version anlegen.',
  'invalid_transition':
      'Dieser Statuswechsel ist nicht vorgesehen. Den geltenden Stand laden und von dort weitergehen.',
  'no_accepted_app':
      'Einen Live-Schluessel gibt es erst nach der Abnahme einer App. Bis dahin mit dem pk_test_-Schluessel arbeiten.',
  'consent': 'Der Datenschutzhinweis wurde nicht bestaetigt. Ohne die Bestaetigung entsteht nichts.',
  'key_limit':
      'Mehr aktive Schluessel je Umgebung als erlaubt. Zuerst einen widerrufen, dann einen neuen erzeugen.',
  'last_owner':
      'Der letzte Inhaber eines Partner-Kontos laesst sich nicht entfernen. Zuerst einen zweiten ernennen.',
  'auth_user_exists': 'Diese E-Mail-Adresse ist bereits einem Konto zugeordnet. Eine andere waehlen.',
  'card_missing': 'Zu diesem Antrag sind noch keine Kartendaten eingetragen.',
  'card_duplicate':
      'Diese Seriennummer ist bei Kasseneck schon eingetragen -- die Karte ist bereits erfasst.',
  'card_not_verified': 'Die Kartendaten sind noch nicht geprueft. Die Pruefung abwarten (data.antrag).',
  'already_assigned':
      'Fuer diesen Antrag sind bereits Kartendaten eingetragen; ein zweiter Satz ueberschreibt nichts.',
};

/// Der Handlungssatz zu einem Code -- aus beiden Flaechen. `null` fuer einen
/// Code, den dieses Paket nicht kennt; ein erfundener Satz waere schlimmer als
/// keiner.
String? partnerFehlerRat(String code) => _rat[code];

/// Der Fehlercode eines gefangenen Fehlers -- `null`, wenn es keiner der
/// unseren ist.
String? partnerFehlerCode(Object? fehler) =>
    fehler is KasseneckApiError ? fehler.code : null;

/// Kurzform fuer `catch (e) { if (istPartnerFehler(e, 'signature_missing')) ... }`.
bool istPartnerFehler(Object? fehler, String code) =>
    partnerFehlerCode(fehler) == code;

/// Ein Feldfehler aus `data.errors[]` einer `validation`-Antwort.
class PartnerFeldFehler {
  const PartnerFeldFehler(this.field, this.message);

  /// Der Feldpfad, so wie er im gesendeten Betrieb steht -- verschachtelt und
  /// je Kontakt: `address.land`, `tax_details.ustid`, `contacts.1.abteilung`.
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
