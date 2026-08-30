/// Der Partner-Client: alles, was ein Partner-Softwarehaus ueber die
/// Kasseneck-Schnittstelle tut.
///
/// **Was die Endpunkte tun, steht in der Referenz des Backends**
/// (`docs/api/partner.md`, kompakt `docs/api/partner.llms.txt`). Hier steht die
/// Benutzung: Reihenfolge, Fehlerbehandlung, Umgang mit den Geheimnissen.
///
/// Die Kette hat eine harte Reihenfolge -- Betrieb anlegen, FinanzOnline
/// einrichten, Auftragsverarbeitungsvertrag, Signatur beantragen, auf
/// `signature.ready` warten, Kasse anlegen, Zugangsdaten holen, Belege
/// signieren. Sie steht als Daten in [kPartnerAblauf].
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
import 'fehler.dart';
import 'transport.dart';
import 'typen.dart';
import 'webhooks.dart';

class PartnerApi {
  /// [partnerKey] ist der Partner-Schluessel `pk_test_...` / `pk_live_...`.
  ///
  /// [avvModus] ist keine Anmeldeangabe, sondern der Vertragsweg dieses
  /// Partner-Kontos. `getPartnerInfo` gibt ihn nicht aus; die
  /// Betriebsansichten tun es (`betrieb.avv.modus`), und
  /// [vertragOffenHinweisFuer] nimmt ihn von dort. Dieser Wert ist der
  /// Rueckfall, solange kein Betrieb geladen ist. Er steuert nur die
  /// Formulierung der Hinweise -- nicht das Verhalten des Servers.
  PartnerApi({
    required String partnerKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? frist,
    this.avvModus = kAvvModusStandard,
  }) : _t = PartnerTransport(
          partnerKey: partnerKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
          frist: frist,
        );

  /// Fuer Tests und fuer Aufrufer, die den Transport selbst bauen.
  PartnerApi.mitTransport(this._t, {this.avvModus = kAvvModusStandard});

  final PartnerTransport _t;

  /// Der Vertragsweg dieses Partner-Kontos.
  final AvvModus avvModus;

  /// `test` oder `live`, aus dem Schluessel abgelesen -- ohne Netzaufruf.
  String get env => _t.env;

  /// Was bei `vertrag_offen` zu tun ist, formuliert fuer den Vertragsweg dieses
  /// Kontos. Gehoert in die eigene Fehlermeldung, damit ein Anwender nicht in
  /// der Doku nachschlagen muss.
  String get vertragOffenHinweis => vertragOffenRat(avvModus);

  /// Wie [vertragOffenHinweis], aber mit Stand und Weg aus dem Betrieb selbst
  /// -- der verlaesslichen Quelle. Ohne den Stand gilt der eingestellte
  /// [avvModus]. Ein Test-Betrieb (`nicht_erforderlich`) bekommt einen eigenen
  /// Satz: dort ist nichts zu tun.
  String vertragOffenHinweisFuer(AvvStand? avv) =>
      vertragOffenRatFuer(avv?.modus, status: avv?.status, rueckfall: avvModus);

  /// Der Handlungssatz zu einem beliebigen Fehlercode der Partner-API.
  String? fehlerRat(String code) => partnerFehlerRat(code, avvModus);

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

  /// Legt einen Betrieb an. Kasseneck erzeugt dabei auch seinen Panel-Zugang
  /// und schickt die Einladung an `betrieb['email']` (abschaltbar ueber
  /// [einladen] `= false`).
  ///
  /// **[idempotencyKey] benutzen.** Ein verlorener Antwortweg ist kein
  /// Sonderfall, und ohne Schluessel legt der zweite Versuch einen zweiten
  /// Betrieb an. Mit Schluessel kommt die gespeicherte Antwort zurueck
  /// ([NeuerBetrieb.wiederholt]) -- auch dann, wenn der Rumpf inzwischen
  /// abweicht. Die eigene Kundennummer ist der natuerliche Wert dafuer.
  ///
  /// [betrieb] sind die Stammdaten, so wie die Referenz sie beschreibt. Bewusst
  /// eine Karte und keine getippte Klasse: die Felder pruefen Backend und
  /// `kreiseck_validator`, und ein neu hinzukommendes Feld soll sich ohne
  /// Paket-Neubau senden lassen.
  Future<NeuerBetrieb> createPartnerCustomer({
    required String appId,
    required Map<String, dynamic> betrieb,
    String? idempotencyKey,
    bool? einladen,
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
      'betrieb': betrieb,
      'idempotencyKey': idempotencyKey,
      'zugang': einladen == null ? null : <String, dynamic>{'einladen': einladen},
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
    return Betrieb.aus(_verlangt(d['kunde'], 'getPartnerCustomer', 'kunde'));
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

  /// Beantragt die Signatureinheit. Kasseneck weist eine Karte aus dem eigenen
  /// Bestand zu und meldet sie bei FinanzOnline an.
  ///
  /// **Je Betrieb laeuft nur ein Antrag.** Ein zweiter Aufruf liefert den
  /// laufenden zurueck ([SignaturAntragErgebnis.wiederholt]) und ist damit
  /// folgenlos wiederholbar. Der Abschluss kommt als Ereignis
  /// `signature.ready` -- nicht als Antwort auf diesen Aufruf.
  Future<SignaturAntragErgebnis> requestCustomerSignature(String customerId, {String? art}) async {
    final id = _pflicht(customerId, 'requestCustomerSignature', 'customerId');
    final d = await _t.rufen(Aufrufe.requestCustomerSignature,
        params: <String, dynamic>{'customerId': id, 'art': art});
    return SignaturAntragErgebnis(
      antrag: SignaturAntrag.aus(_verlangt(d['antrag'], 'requestCustomerSignature', 'antrag')),
      wiederholt: alsJaNein(d['wiederholt']),
      hinweis: alsTextOderNull(d['hinweis']),
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

  /// Legt eine Kasse an. **Darf vor der Signatur aufgerufen werden:** ohne sie
  /// bleibt die Kasse auf `entwurf` und geht von selbst live, sobald die
  /// Signatur bereit ist ([automatisch] `= true`, Vorgabe).
  /// [NeueKasse.grund] sagt, warum gerade nichts lief: `signature_not_ready`
  /// oder `automatik_aus`.
  ///
  /// Hoechstens 20 Kassen je Betrieb (`cashregister_limit`); ohne gebuchtes
  /// Modul `module_inactive`. Und ohne bestaetigten
  /// Auftragsverarbeitungsvertrag geht **keine neue Kasse** live --
  /// `vertrag_offen`, siehe [vertragOffenHinweis].
  Future<NeueKasse> createCustomerCashregister({
    required String customerId,
    String? name,
    bool? automatisch,
  }) async {
    final id = _pflicht(customerId, 'createCustomerCashregister', 'customerId');
    if (name != null && name.length > 60) {
      throw const KasseneckValidationError(
          'createCustomerCashregister', 'name ist laenger als 60 Zeichen', 'request');
    }
    final d = await _t.rufen(Aufrufe.createCustomerCashregister,
        params: <String, dynamic>{'customerId': id, 'name': name, 'automatisch': automatisch});
    final ib = alsMap(d['inbetriebnahme']);
    final ok = ib['ok'];
    return NeueKasse(
      kasse: Kasse.aus(_verlangt(d['kasse'], 'createCustomerCashregister', 'kasse')),
      gestartet: alsJaNein(ib['gestartet']),
      // `null` heisst "nicht gelaufen" und ist etwas anderes als `false`.
      ok: ok is bool ? ok : null,
      schritt: alsTextOderNull(ib['schritt']),
      grund: alsTextOderNull(ib['grund']),
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
      kasse: Kasse.aus(_verlangt(d['kasse'], 'activateCashregister', 'kasse')),
      unveraendert: alsJaNein(d['unveraendert']),
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
  // Vertrag
  // -------------------------------------------------------------------------

  /// Meldet eine **in Vollmacht** eingeholte Zustimmung zum
  /// Auftragsverarbeitungsvertrag.
  ///
  /// Vier Voraussetzungen, alle noetig: das Partner-Konto steht auf
  /// `vollmacht` (`modus_not_allowed`), der Partnervertrag mit dem
  /// Vollmachts-Kapitel ist bestaetigt (`vollmacht_fehlt`), der Betrieb gehoert
  /// dem Partner (`not_found`), und [textHash] passt zur geltenden
  /// Kasseneck-Fassung (`text_changed` -- dann wurde ein anderer Text gezeigt,
  /// und die eingeholte Zustimmung gilt nicht).
  ///
  /// Auf den beiden anderen Wegen (`direkt`, `unterauftrag`) ist dieser Aufruf
  /// **nicht** der richtige: dort bestaetigt der Betrieb selbst bzw. der
  /// Vertrag liegt beim Partner.
  ///
  /// Der Endpunkt nennt den Betrieb `kundeId`; dieser Client nennt ihn ueberall
  /// `customerId` und uebersetzt hier -- zwei Namen fuer dieselbe Kennung sind
  /// eine Fehlerquelle und keine Genauigkeit.
  Future<VertragsMeldung> reportCustomerVertrag({
    required String customerId,
    required String version,
    required String textHash,
    required String name,
    required String funktion,
    String art = 'avv',
    int? akzeptiertAt,
  }) async {
    final kundeId = _pflicht(customerId, 'reportCustomerVertrag', 'customerId');
    final v = _pflicht(version, 'reportCustomerVertrag', 'version');
    final hash = _pflicht(textHash, 'reportCustomerVertrag', 'textHash');
    final wer = _pflicht(name, 'reportCustomerVertrag', 'name');
    final rolle = _pflicht(funktion, 'reportCustomerVertrag', 'funktion');
    if (art != 'avv') {
      throw const KasseneckValidationError(
        'reportCustomerVertrag',
        'In Vollmacht laesst sich nur der Auftragsverarbeitungsvertrag melden (art:"avv")',
        'request',
      );
    }
    final d = await _t.rufen(Aufrufe.reportCustomerVertrag, params: <String, dynamic>{
      'kundeId': kundeId,
      'art': 'avv',
      'version': v,
      'textHash': hash,
      'name': wer,
      'funktion': rolle,
      'akzeptiertAt': akzeptiertAt,
    });
    final vertragId = alsTextOderNull(d['vertragId']);
    if (vertragId == null || vertragId.isEmpty) {
      throw const KasseneckValidationError(
          'reportCustomerVertrag', 'Antwort enthaelt keine vertragId', 'response');
    }
    return VertragsMeldung(
      vertragId: vertragId,
      bestaetigtAt: alsZahlOderNull(d['bestaetigtAt']) ?? 0,
      art: alsText(d['art'], 'avv'),
      version: alsText(d['version'], v),
    );
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
      'beschreibung': beschreibung,
      'aktiv': aktiv,
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

  /// Schickt ein `webhook.test`-Ereignis an genau diesen Endpunkt -- der
  /// schnellste Weg, die eigene Signaturpruefung gegen echte Bytes laufen zu
  /// lassen.
  ///
  /// Der Endpunkt muss `webhook.test` abonnieren (`event_not_subscribed`) und
  /// aktiv sein (`webhook_inactive`).
  ///
  /// Der Backend-Endpunkt heisst `sendPartnerWebhookTest`; dieser Client
  /// behaelt den Namen bei, damit ein Leser der Doku und ein Leser des Codes
  /// dasselbe suchen.
  Future<WebhookTestErgebnis> sendPartnerWebhookTest(String webhookId) async {
    final id = _pflicht(webhookId, 'sendPartnerWebhookTest', 'webhookId');
    final d = await _t.rufen(Aufrufe.sendPartnerWebhookTest, params: <String, dynamic>{'webhookId': id});
    return WebhookTestErgebnis(
      eventId: alsText(d['eventId']),
      zustellungen: alsListe(d['zustellungen']),
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
    return alsListe(d['zustellungen'])
        .map((e) => WebhookZustellung.aus(alsMap(e)))
        .toList(growable: false);
  }
}
