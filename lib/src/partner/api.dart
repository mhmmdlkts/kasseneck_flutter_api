/// Der Partner-Client: alles, was ein Partner-Softwarehaus ueber die
/// Kasseneck-Schnittstelle tut.
///
/// **Was die Endpunkte tun, steht in der Referenz des Backends**
/// (`docs/api/partner.md`, kompakt `docs/api/partner.llms.txt`). Hier steht die
/// Benutzung: Reihenfolge, Fehlerbehandlung, Umgang mit den Geheimnissen.
///
/// Die Kette hat eine harte Reihenfolge -- Betrieb anlegen, FinanzOnline
/// einrichten, Signatur beantragen, auf `signature.ready` warten, Kasse
/// anlegen, Zugangsdaten holen, Belege signieren. Sie steht als Daten in
/// [kPartnerAblauf].
///
/// **Was hier geprueft wird und was nicht.** Vor dem Senden prueft dieser
/// Client nur, was er ohne den Server wissen kann: dass eine Kennung ueberhaupt
/// da ist, dass eine Liste nicht leer ist, dass eine Zahl im erlaubten Bereich
/// liegt. Die fachliche Pruefung der Betriebsdaten (Steuernummer samt
/// Pruefziffer, UID, PLZ, Gericht) macht das Backend mit `kreiseck_validator`
/// -- sie hier zu wiederholen hiesse, zwei Wahrheiten zu haben, von denen eine
/// veraltet. Ein Formfehler kommt als `KasseneckApiError` mit
/// `code == 'validation'` zurueck; [partnerFeldFehler] macht `data.errors[]`
/// daraus. **Es entsteht dabei nichts** -- der Aufruf ist folgenlos
/// wiederholbar.
library;

import 'package:http/http.dart' as http;

import '../aufrufe.dart';
import '../register/fehler.dart';
import 'betrieb.dart';
import 'fehler.dart';
import 'transport.dart';
import 'typen.dart';
import 'webhooks.dart';

class PartnerApi {
  /// [partnerKey] ist der Partner-Schluessel `pk_test_...` / `pk_live_...`.
  PartnerApi({
    required String partnerKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? frist,
  }) : _t = PartnerTransport(
          partnerKey: partnerKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
          frist: frist,
        );

  /// Fuer Tests und fuer Aufrufer, die den Transport selbst bauen.
  PartnerApi.mitTransport(this._t);

  final PartnerTransport _t;

  /// `test` oder `live`, aus dem Schluessel abgelesen -- ohne Netzaufruf.
  String get env => _t.env;

  /// Der Handlungssatz zu einem beliebigen Fehlercode der Partner-API. Gehoert
  /// in die eigene Fehlermeldung, damit ein Anwender nicht in der Doku
  /// nachschlagen muss.
  String? fehlerRat(String code) => partnerFehlerRat(code);

  // -------------------------------------------------------------------------
  // Kleine Pruefungen vor dem Senden
  // -------------------------------------------------------------------------

  String _pflicht(Object? wert, String vorgang, String feld) {
    final s = wert is String ? wert.trim() : '';
    if (s.isEmpty) throw KasseneckValidationError(vorgang, '$feld fehlt', 'request');
    return s;
  }

  Map<String, dynamic> _verlangt(Object? wert, String vorgang, String feld) {
    if (wert is! Map) {
      throw KasseneckValidationError(vorgang, 'Antwort enthaelt kein $feld', 'response');
    }
    return Map<String, dynamic>.from(wert);
  }

  // -------------------------------------------------------------------------
  // Partner
  // -------------------------------------------------------------------------

  /// Wer bin ich, in welcher Umgebung, mit welchen Rechten -- und welche Apps
  /// gehoeren mir. `apps[].id` ist die `appId` fuer [createPartnerCustomer].
  ///
  /// Der guenstigste Selbsttest beim Hochfahren: er beweist Schluessel,
  /// Umgebung und Rechte in einem Aufruf.
  Future<PartnerInfo> getPartnerInfo() async {
    final d = await _t.rufen(Aufrufe.getPartnerInfo);
    _verlangt(d['partner'], 'getPartnerInfo', 'partner');
    return PartnerInfo.aus(d);
  }

  // -------------------------------------------------------------------------
  // Betriebe
  // -------------------------------------------------------------------------

  /// Legt einen Betrieb an.
  ///
  /// **Ohne Panel-Zugang**, solange nicht [einladen] `= true` dabeisteht: viele
  /// Betriebe arbeiten ausschliesslich in der App des Partners, und ein
  /// stillschweigend erzeugter Login samt Einladungsmail waere dort etwas, das
  /// niemand erwartet. Fuer die Einladung braucht das Partner-Konto ausserdem
  /// [PartnerInfo.darfZugangEinrichten] -- sonst `zugang_nicht_erlaubt`, und
  /// es entsteht nichts, auch kein Betrieb.
  ///
  /// **[env] waehlt die Umgebung.** Ohne Angabe entscheidet der Schluessel; ein
  /// LIVE-Schluessel darf [PartnerEnv.test] verlangen -- das ist der
  /// vorgesehene Weg, die ganze Kette zu proben, ohne sich einen zweiten
  /// Schluessel zu holen. Umgekehrt nie: ein Test-Schluessel mit
  /// [PartnerEnv.live] bekommt `live_not_allowed`, und es entsteht nichts. Ein
  /// so angelegter Live-Betrieb ist sofort freigeschaltet und traegt das Modul
  /// `registrierkasse`.
  ///
  /// **[idempotencyKey] benutzen.** Ein verlorener Antwortweg ist kein
  /// Sonderfall, und ohne Schluessel legt der zweite Versuch einen zweiten
  /// Betrieb an. Mit Schluessel kommt die gespeicherte Antwort zurueck
  /// ([NeuerBetrieb.wiederholt]) -- auch dann, wenn der Rumpf inzwischen
  /// abweicht. Die eigene Kundennummer ist der natuerliche Wert dafuer.
  ///
  /// [betrieb] sind die Stammdaten, so wie die Referenz sie beschreibt -- eine
  /// Karte, weil Dart keine Form dafuer erzwingen kann, die der Server nicht
  /// ohnehin prueft. **Das Backend weist ein unbekanntes Feld ab**, statt es
  /// stillschweigend zu verwerfen; [unbekannteBetriebsfelder] beantwortet
  /// dieselbe Frage vor dem Senden, mit denselben Pfaden.
  Future<NeuerBetrieb> createPartnerCustomer({
    required String appId,
    required Map<String, dynamic> betrieb,
    String? idempotencyKey,
    bool? einladen,
    PartnerEnv? env,
  }) async {
    final app = _pflicht(appId, 'createPartnerCustomer', 'appId');
    if (betrieb.isEmpty) {
      throw const KasseneckValidationError('createPartnerCustomer', 'betrieb ist leer', 'request');
    }
    if (idempotencyKey != null && idempotencyKey.length > 120) {
      throw const KasseneckValidationError(
          'createPartnerCustomer', 'idempotencyKey ist laenger als 120 Zeichen', 'request');
    }
    final d = await _t.rufen(Aufrufe.createPartnerCustomer, params: <String, dynamic>{
      'appId': app,
      'business': betrieb,
      'idempotencyKey': idempotencyKey,
      'access': einladen == null ? null : <String, dynamic>{'invite': einladen},
      'env': env == null ? null : envName(env),
    });
    final ergebnis = NeuerBetrieb.aus(d, app);
    if (ergebnis.customerId.isEmpty) {
      throw const KasseneckValidationError(
          'createPartnerCustomer', 'Antwort enthaelt keine customerId', 'response');
    }
    return ergebnis;
  }

  /// Betriebe dieses Partners, seitenweise. [cursor] aus der Antwort setzt
  /// fort; `null` heisst, es kommt nichts mehr.
  Future<BetriebListe> listPartnerCustomers({String? status, int? limit, String? cursor}) async {
    if (limit != null && (limit < 1 || limit > 200)) {
      throw const KasseneckValidationError(
          'listPartnerCustomers', 'limit muss zwischen 1 und 200 liegen', 'request');
    }
    final d = await _t.rufen(Aufrufe.listPartnerCustomers,
        params: <String, dynamic>{'status': status, 'limit': limit, 'cursor': cursor});
    return BetriebListe.aus(d);
  }

  /// Ein Betrieb mit allem, was der Partner ueber ihn sehen darf -- nie
  /// Geheimnisse.
  Future<Betrieb> getPartnerCustomer(String customerId) async {
    final id = _pflicht(customerId, 'getPartnerCustomer', 'customerId');
    final d = await _t.rufen(Aufrufe.getPartnerCustomer, params: <String, dynamic>{'customerId': id});
    return Betrieb.aus(_verlangt(d['customer'], 'getPartnerCustomer', 'customer'));
  }

  /// Schickt dem Betrieb den Einrichtungs-Link fuer seinen
  /// FinanzOnline-Zugang. Ohne diesen Zugang gibt es live keine
  /// Signatureinheit (`fon_missing`).
  ///
  /// Die Antwort nennt den Empfaenger **maskiert** -- die Adresse gibt das
  /// Backend nie im Klartext aus.
  Future<FonLinkErgebnis> sendPartnerCustomerFonLink(String customerId) async {
    final id = _pflicht(customerId, 'sendPartnerCustomerFonLink', 'customerId');
    final d = await _t.rufen(Aufrufe.sendPartnerCustomerFonLink, params: <String, dynamic>{'customerId': id});
    return FonLinkErgebnis.aus(d, id);
  }

  // -------------------------------------------------------------------------
  // Signatur
  // -------------------------------------------------------------------------

  /// Beantragt die Signatureinheit. Kasseneck laesst die Karte beim
  /// Vertrauensdiensteanbieter **auf diesen Betrieb** ausstellen und meldet sie
  /// bei FinanzOnline an; einen Vorrat fertiger Karten gibt es nicht.
  ///
  /// Der Antrag erzeugt sofort ein Signatur-OBJEKT: [SignaturAntrag.requestId]
  /// ist zugleich die `signaturId`, auf die sich eine Kasse beruft -- auch
  /// solange noch keine Karte zugewiesen ist.
  ///
  /// **Je Betrieb laeuft nur ein Antrag.** Ein zweiter Aufruf liefert den
  /// laufenden zurueck ([SignaturAntragErgebnis.wiederholt]) und ist damit
  /// folgenlos wiederholbar. Eine WEITERE Signatur (Ersatzkarte, zweiter
  /// Standort) entsteht nur mit [weitere] `= true` -- hoechstens zehn je
  /// Betrieb (`signature_limit`). Der Abschluss kommt als Ereignis
  /// `signature.ready`, nicht als Antwort auf diesen Aufruf.
  Future<SignaturAntragErgebnis> requestCustomerSignature(
    String customerId, {
    String? art,
    bool? weitere,
  }) async {
    final id = _pflicht(customerId, 'requestCustomerSignature', 'customerId');
    final d = await _t.rufen(Aufrufe.requestCustomerSignature,
        params: <String, dynamic>{'customerId': id, 'art': art, 'additional': weitere});
    return SignaturAntragErgebnis(
      antrag: SignaturAntrag.aus(_verlangt(d['request'], 'requestCustomerSignature', 'request')),
      wiederholt: alsJaNein(d['replayed']),
      hinweis: alsTextOderNull(d['note']),
    );
  }

  /// Stand der Signatur eines Betriebs samt aller Antraege und des FON-Zugangs.
  Future<SignaturStand> getCustomerSignatureStatus(String customerId) async {
    final id = _pflicht(customerId, 'getCustomerSignatureStatus', 'customerId');
    final d = await _t.rufen(Aufrufe.getCustomerSignatureStatus, params: <String, dynamic>{'customerId': id});
    return SignaturStand.aus(d);
  }

  // -------------------------------------------------------------------------
  // Kassen
  // -------------------------------------------------------------------------

  /// Legt eine Kasse an.
  ///
  /// **Jede Kasse bezieht sich auf eine Signatur.** Ohne eine einzige -- auch
  /// eine noch laufende zaehlt -- entsteht keine (`signature_missing`); bei
  /// mehreren muss [signaturId] dastehen (`signature_ambiguous`, die Auswahl
  /// steht in `data.auswahl`), eine fremde Kennung ist `signature_unknown`.
  ///
  /// **Darf vor der fertigen Signatur aufgerufen werden:** die Kasse bleibt
  /// dann auf `entwurf` und geht von selbst live, sobald IHRE Signatur bereit
  /// ist ([automatisch] `= true`, Vorgabe). [NeueKasse.grund] sagt, warum
  /// gerade nichts lief: `signature_not_ready` oder `automatik_aus`.
  ///
  /// **Einen Namen gibt es nicht:** Kassennamen vergibt Kasseneck, sie sind
  /// gleich der `cashregisterId`.
  ///
  /// Hoechstens 20 Kassen je Betrieb (`cashregister_limit`); ohne gebuchtes
  /// Modul `module_inactive`.
  Future<NeueKasse> createCustomerCashregister({
    required String customerId,
    bool? automatisch,
    String? signaturId,
  }) async {
    final id = _pflicht(customerId, 'createCustomerCashregister', 'customerId');
    final d = await _t.rufen(Aufrufe.createCustomerCashregister, params: <String, dynamic>{
      'customerId': id,
      'automatic': automatisch,
      'signatureRequestId': signaturId,
    });
    final ib = alsMap(d['activation']);
    final ok = ib['ok'];
    return NeueKasse(
      kasse: Kasse.aus(_verlangt(d['cashregister'], 'createCustomerCashregister', 'cashregister')),
      gestartet: alsJaNein(ib['started']),
      // `null` heisst "nicht gelaufen" und ist etwas anderes als `false`.
      ok: ok is bool ? ok : null,
      schritt: alsTextOderNull(ib['step']),
      grund: alsTextOderNull(ib['reason']),
    );
  }

  /// Nimmt eine Kasse in Betrieb -- von Hand, wenn `automatisch:false` gilt
  /// oder ein Lauf abgebrochen ist.
  ///
  /// **Jeder Schritt der Kette ist idempotent**, der Startbeleg entsteht nach
  /// RKSV genau einmal und ein vorhandener wird erkannt. Ein
  /// Wiederholungsaufruf setzt deshalb an der Bruchstelle an und macht nichts
  /// doppelt; eine bereits laufende Kasse antwortet mit
  /// [KassenInbetriebnahme.unveraendert]. Das ist der eine veraendernde Aufruf
  /// dieses Clients, der ohne Idempotenzschluessel gefahrlos wiederholbar ist
  /// -- weil der Server ihn so gebaut hat.
  Future<KassenInbetriebnahme> activateCashregister(String customerId, String cashregisterId) async {
    final kunde = _pflicht(customerId, 'activateCashregister', 'customerId');
    final kasse = _pflicht(cashregisterId, 'activateCashregister', 'cashregisterId');
    final d = await _t.rufen(Aufrufe.activateCashregister,
        params: <String, dynamic>{'customerId': kunde, 'cashregisterId': kasse});
    return KassenInbetriebnahme(
      kasse: Kasse.aus(_verlangt(d['cashregister'], 'activateCashregister', 'cashregister')),
      unveraendert: alsJaNein(d['unchanged']),
    );
  }

  /// Die Kassen eines Betriebs samt Stand der Inbetriebnahme -- **nie** Token.
  Future<KassenListe> listCustomerCashregisters(String customerId) async {
    final id = _pflicht(customerId, 'listCustomerCashregisters', 'customerId');
    final d = await _t.rufen(Aufrufe.listCustomerCashregisters, params: <String, dynamic>{'customerId': id});
    return KassenListe.aus(d, id);
  }

  /// Holt die **Geheimnisse des Betriebs**: seinen `api_key` und die Token
  /// seiner Kassen. Damit signiert eine App in seinem Namen Belege -- und ein
  /// Beleg ist nach RKSV nicht zuruecknehmbar.
  ///
  /// Braucht den Scope `credentials:read`, der **nicht** zum Standardsatz
  /// gehoert und keinem bestehenden Schluessel nachtraeglich hinzugefuegt wird;
  /// dafuer wird ein eigener Schluessel angelegt. Jeder Abruf wird
  /// mitgeschrieben (Partner, Schluessel, Zeitpunkt) und ist fuer den Betrieb
  /// sichtbar.
  ///
  /// **Nur verschluesselt speichern. Nie protokollieren, nie in eine Mail, nie
  /// in einen Fehlerbericht.** Die Werte kommen darum als `KasseneckSecret` und
  /// nicht als `String`: `print`, `toString` und `jsonEncode` zeigen eine
  /// Maske, heraus kommt man nur ueber `.reveal()`.
  Future<BetriebZugangsdaten> getCustomerCredentials(String customerId) async {
    final id = _pflicht(customerId, 'getCustomerCredentials', 'customerId');
    final d = await _t.rufen(Aufrufe.getCustomerCredentials, params: <String, dynamic>{'customerId': id});
    return BetriebZugangsdaten.aus(d, id);
  }

  // -------------------------------------------------------------------------
  // Webhooks
  // -------------------------------------------------------------------------

  /// Legt einen Webhook-Endpunkt an. Hoechstens `kWebhookLimit` je Partner
  /// (`webhook_limit`).
  ///
  /// **Das Secret in der Antwort ist der einzige Weg dazu.** Es sofort dorthin
  /// schreiben, wo der Empfaenger es liest -- nicht in ein Protokoll.
  Future<NeuerWebhook> createPartnerWebhook({
    required String url,
    required List<String> events,
    String? beschreibung,
    bool? aktiv,
  }) async {
    final adresse = _pflicht(url, 'createPartnerWebhook', 'url');
    if (events.isEmpty) {
      throw const KasseneckValidationError(
        'createPartnerWebhook',
        'events ist leer -- ein Endpunkt ohne Ereignis bekaeme nie etwas',
        'request',
      );
    }
    final d = await _t.rufen(Aufrufe.createPartnerWebhook, params: <String, dynamic>{
      'url': adresse,
      'events': events,
      'description': beschreibung,
      'active': aktiv,
    });
    final secret = alsTextOderNull(d['secret']);
    if (secret == null || secret.isEmpty) {
      throw const KasseneckValidationError(
        'createPartnerWebhook',
        'Antwort enthaelt kein secret -- ohne es laesst sich keine Zustellung pruefen',
        'response',
      );
    }
    return NeuerWebhook(webhook: PartnerWebhook.aus(alsMap(d['webhook'])), secret: secret);
  }

  /// Die Webhook-Endpunkte dieses Partners samt Ereignis-Katalog.
  Future<WebhookListe> listPartnerWebhooks() async =>
      WebhookListe.aus(await _t.rufen(Aufrufe.listPartnerWebhooks));

  /// Aendert einen Endpunkt. Nur die genannten Felder -- ein leeres [patch]
  /// lehnt das Backend ab (`validation`, Feld `patch`), statt stillschweigend
  /// nichts zu tun.
  Future<PartnerWebhook> updatePartnerWebhook(String webhookId, Map<String, dynamic> patch) async {
    final id = _pflicht(webhookId, 'updatePartnerWebhook', 'webhookId');
    if (patch.isEmpty) {
      throw const KasseneckValidationError(
          'updatePartnerWebhook', 'patch nennt keine Aenderung', 'request');
    }
    final d = await _t.rufen(Aufrufe.updatePartnerWebhook,
        params: <String, dynamic>{'webhookId': id, 'patch': patch});
    return PartnerWebhook.aus(alsMap(d['webhook']));
  }

  /// Loescht einen Endpunkt. Danach kommt dort nichts mehr an.
  Future<String> deletePartnerWebhook(String webhookId) async {
    final id = _pflicht(webhookId, 'deletePartnerWebhook', 'webhookId');
    final d = await _t.rufen(Aufrufe.deletePartnerWebhook, params: <String, dynamic>{'webhookId': id});
    return alsText(d['webhookId'], id);
  }

  /// Schickt eine Probe an genau diesen Endpunkt.
  ///
  /// Ohne [event] kommt `webhook.test` -- der Nachweis, dass die Leitung steht
  /// und die eigene Signaturpruefung gegen echte Bytes laeuft. **Mit [event]
  /// kommt genau das Ereignis, das der Empfaenger behandeln soll**, mit einer
  /// glaubwuerdigen Nutzlast: wer auf `signature.ready` hin seinen Kunden
  /// benachrichtigt, probt das einmal, statt auf eine echte Karte zu warten.
  /// Eine Leitungsprobe beweist nichts ueber die Behandlung des Ernstfalls.
  ///
  /// Der Endpunkt muss das Ereignis abonnieren (`event_not_subscribed`) und
  /// aktiv sein (`webhook_inactive`); ein unbekannter Name ist ein
  /// `validation`-Fehler auf dem Feld `event`.
  ///
  /// **Jede Probe traegt `test: true` im Umschlag**
  /// ([PartnerWebhookEreignis.test]).
  ///
  /// Der Backend-Endpunkt heisst `sendPartnerWebhookTest`; dieser Client
  /// behaelt den Namen bei, damit ein Leser der Doku und ein Leser des Codes
  /// dasselbe suchen.
  Future<WebhookTestErgebnis> sendPartnerWebhookTest(String webhookId, {String? event}) async {
    final id = _pflicht(webhookId, 'sendPartnerWebhookTest', 'webhookId');
    final ereignis = (event ?? '').trim();
    final d = await _t.rufen(Aufrufe.sendPartnerWebhookTest, params: <String, dynamic>{
      'webhookId': id,
      'event': ereignis.isEmpty ? null : ereignis,
    });
    return WebhookTestErgebnis(
      eventId: alsText(d['eventId']),
      ereignis: alsText(d['ereignis'], ereignis.isEmpty ? 'webhook.test' : ereignis),
      zustellungen: alsListe(d['deliveries']),
    );
  }

  /// Die letzten Zustellversuche -- mit [webhookId] fuer einen Endpunkt, ohne
  /// ihn fuer alle. Die Stelle, an der sich "mein Server bekommt nichts"
  /// klaeren laesst, ohne bei Kasseneck nachzufragen.
  Future<List<WebhookZustellung>> listPartnerWebhookDeliveries({String? webhookId, int? limit}) async {
    if (limit != null && (limit < 1 || limit > 200)) {
      throw const KasseneckValidationError(
          'listPartnerWebhookDeliveries', 'limit muss zwischen 1 und 200 liegen', 'request');
    }
    final d = await _t.rufen(Aufrufe.listPartnerWebhookDeliveries,
        params: <String, dynamic>{'webhookId': webhookId, 'limit': limit});
    return alsListe(d['deliveries'])
        .map((e) => WebhookZustellung.aus(alsMap(e)))
        .toList(growable: false);
  }
}
