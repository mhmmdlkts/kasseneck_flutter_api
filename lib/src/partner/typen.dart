/// Die Formen, die die Partner-API zurueckgibt.
///
/// **Die Referenz ist das Backend**, nicht diese Datei: `docs/api/partner.md`
/// (ausfuehrlich) und `docs/api/partner.llms.txt` (kompakt) beschreiben Felder,
/// Fehlercodes und Ereignisse. Hier stehen sie als Typen, damit ein Aufrufer
/// beim Tippen sieht, was es gibt -- nicht als zweiter Text daneben.
///
/// **Lesen ist tolerant.** Jede Antwort von aussen ist fremd: keine harten
/// Casts, keine Annahme ueber Feldtypen, unbekannte Statuswerte kommen als
/// `String` durch statt zu `null` zu werden. Eine Fassung, die einen neuen
/// Status einfuehrt, soll diesen Client nicht anhalten.
library;

import 'fehler.dart';
import 'secret.dart';

// ---------------------------------------------------------------------------
// Kleine Leser -- an einer Stelle, damit nicht jede Klasse ihre eigene
// Vorstellung von "fehlt" entwickelt.
// ---------------------------------------------------------------------------

Map<String, dynamic> alsMap(Object? wert) =>
    wert is Map ? Map<String, dynamic>.from(wert) : <String, dynamic>{};

Map<String, dynamic>? alsMapOderNull(Object? wert) =>
    wert is Map ? Map<String, dynamic>.from(wert) : null;

List<dynamic> alsListe(Object? wert) => wert is List ? wert : const <dynamic>[];

List<String> alsTexte(Object? wert) =>
    alsListe(wert).whereType<String>().toList(growable: false);

String alsText(Object? wert, [String rueckfall = '']) =>
    wert is String ? wert : rueckfall;

String? alsTextOderNull(Object? wert) => wert is String ? wert : null;

int? alsZahlOderNull(Object? wert) =>
    wert is num && wert.isFinite ? wert.toInt() : null;

bool alsJaNein(Object? wert, [bool rueckfall = false]) =>
    wert is bool ? wert : rueckfall;

/// Umgebung, in der ein Partner-Schluessel arbeitet.
enum PartnerEnv { test, live }

PartnerEnv envAus(Object? wert) =>
    wert == 'test' ? PartnerEnv.test : PartnerEnv.live;

/// `credentials:read` gehoert **nicht** zum Standardsatz und wird keinem
/// bestehenden Schluessel nachtraeglich hinzugefuegt: wer ihn hat, kann im
/// Namen fremder Betriebe Belege signieren. Dafuer wird ein eigener Schluessel
/// angelegt.
const String kScopeCredentials = 'credentials:read';

// ---------------------------------------------------------------------------
// Partner
// ---------------------------------------------------------------------------

class PartnerApp {
  const PartnerApp({
    required this.id,
    required this.name,
    required this.status,
    required this.platform,
    required this.platforms,
    required this.symbolUrl,
    required this.veroeffentlichung,
    required this.listungErlaubt,
  });

  factory PartnerApp.aus(Map<String, dynamic> a) => PartnerApp(
        id: alsText(a['id']),
        name: alsText(a['name']),
        status: alsText(a['status']),
        platform: alsTextOderNull(a['platform']),
        platforms: alsTexte(a['platforms']),
        symbolUrl: alsTextOderNull(alsMap(a['symbol'])['url']),
        veroeffentlichung: alsJaNein(a['veroeffentlichung']),
        listungErlaubt: alsJaNein(a['listungErlaubt']),
      );

  /// Die `appId` fuer `createPartnerCustomer`.
  final String id;
  final String name;
  final String status;
  final String? platform;
  final List<String> platforms;
  final String? symbolUrl;
  final bool veroeffentlichung;
  final bool listungErlaubt;
}

class PartnerSchluesselInfo {
  const PartnerSchluesselInfo({
    required this.hint,
    required this.label,
    required this.createdAt,
    required this.scopes,
  });

  factory PartnerSchluesselInfo.aus(Map<String, dynamic> k) => PartnerSchluesselInfo(
        hint: alsTextOderNull(k['hint']),
        label: alsTextOderNull(k['label']),
        createdAt: alsZahlOderNull(k['createdAt']),
        scopes: alsTexte(k['scopes']),
      );

  /// Ein Hinweis auf den Schluessel (Anfang/Ende), nie der Schluessel selbst.
  final String? hint;
  final String? label;
  final int? createdAt;
  final List<String> scopes;
}

class PartnerInfo {
  const PartnerInfo({
    required this.partnerId,
    required this.name,
    required this.status,
    required this.env,
    required this.scopes,
    required this.key,
    required this.apps,
  });

  factory PartnerInfo.aus(Map<String, dynamic> d) {
    final p = alsMap(d['partner']);
    return PartnerInfo(
      partnerId: alsText(p['id']),
      name: alsText(p['name']),
      status: alsText(p['status'], 'aktiv'),
      env: envAus(d['env']),
      scopes: alsTexte(d['scopes']),
      key: PartnerSchluesselInfo.aus(alsMap(d['key'])),
      apps: alsListe(d['apps'])
          .map((e) => PartnerApp.aus(alsMap(e)))
          .toList(growable: false),
    );
  }

  final String partnerId;
  final String name;
  final String status;
  final PartnerEnv env;
  final List<String> scopes;
  final PartnerSchluesselInfo key;
  final List<PartnerApp> apps;
}

// ---------------------------------------------------------------------------
// Betriebe
// ---------------------------------------------------------------------------

/// Das Ergebnis von `createPartnerCustomer`.
class NeuerBetrieb {
  const NeuerBetrieb({
    required this.customerId,
    required this.status,
    required this.env,
    required this.firma,
    required this.appId,
    required this.eingeladen,
    required this.sentTo,
    required this.naechsteSchritte,
    required this.wiederholt,
  });

  factory NeuerBetrieb.aus(Map<String, dynamic> d, String appIdRueckfall) {
    final zugang = alsMap(d['zugang']);
    return NeuerBetrieb(
      customerId: alsText(d['customerId']),
      status: alsText(d['status'], 'angelegt'),
      env: envAus(d['env']),
      firma: alsText(d['firma']),
      appId: alsText(d['appId'], appIdRueckfall),
      eingeladen: alsJaNein(zugang['eingeladen']),
      sentTo: alsTextOderNull(zugang['sentTo']),
      naechsteSchritte: alsTexte(d['naechsteSchritte']),
      wiederholt: alsJaNein(d['wiederholt']),
    );
  }

  final String customerId;
  final String status;
  final PartnerEnv env;
  final String firma;
  final String appId;
  final bool eingeladen;

  /// Empfaenger der Einladung, **maskiert** -- die Adresse gibt das Backend nie
  /// im Klartext aus.
  final String? sentTo;
  final List<String> naechsteSchritte;

  /// `true`, wenn derselbe `idempotencyKey` schon einmal ankam. Dann ist dies
  /// die gespeicherte Antwort und es wurde nichts zweites angelegt.
  final bool wiederholt;
}

/// Stand des Auftragsverarbeitungsvertrags eines Betriebs, aus Partnersicht.
///
/// `offen` heisst: es geht **keine neue Kasse** live (`vertrag_offen`).
/// `veraltet` heisst: bestaetigt ist eine Fassung, die inzwischen nicht mehr
/// die geltende ist -- auch das zaehlt nicht als bestaetigt. `ueber_partner`
/// gibt es nur im Weg `unterauftrag`: dort hat der Betrieb gar keinen Vertrag
/// mit Kasseneck, es zaehlt allein der Partnervertrag.
class AvvStand {
  const AvvStand({
    required this.status,
    required this.version,
    required this.bestaetigtAt,
    required this.modus,
  });

  /// `null`, wenn die Antwort den Stand gar nicht fuehrt (aeltere
  /// Backend-Fassung). Bewusst nicht "offen": "nicht mitgeliefert" und "nicht
  /// bestaetigt" duerfen fuer den Aufrufer nicht dasselbe sein -- das eine ist
  /// eine alte Fassung, das andere eine Kasse, die nicht live geht.
  static AvvStand? aus(Object? wert) {
    if (wert is! Map) return null;
    final a = Map<String, dynamic>.from(wert);
    return AvvStand(
      status: alsText(a['status'], 'offen'),
      version: alsTextOderNull(a['version']),
      bestaetigtAt: alsZahlOderNull(a['bestaetigtAt']),
      modus: avvModusAus(alsTextOderNull(a['modus'])) ?? kAvvModusStandard,
    );
  }

  final String status;
  final String? version;
  final int? bestaetigtAt;

  /// Der Weg, den Kasseneck fuer DIESES Partner-Konto gesetzt hat.
  final AvvModus modus;

  bool get erfuellt => status == 'bestaetigt' || status == 'ueber_partner';
}

/// Eine Zeile der Betriebsliste.
class BetriebZeile {
  const BetriebZeile({
    required this.customerId,
    required this.firma,
    required this.status,
    required this.appId,
    required this.env,
    required this.createdAt,
    required this.avv,
  });

  factory BetriebZeile.aus(Map<String, dynamic> k) => BetriebZeile(
        customerId: alsText(k['customerId']),
        firma: alsText(k['firma']),
        status: alsText(k['status']),
        appId: alsTextOderNull(k['appId']),
        env: envAus(k['env']),
        createdAt: alsZahlOderNull(k['createdAt']),
        avv: AvvStand.aus(k['avv']),
      );

  final String customerId;
  final String firma;

  /// Der **weiteste erreichte** Meilenstein, nicht die einzige laufende
  /// Arbeit: Signaturantrag und Kassenanlage laufen absichtlich nebeneinander.
  final String status;
  final String? appId;
  final PartnerEnv env;
  final int? createdAt;

  /// Vertragsstand -- `null`, wenn die Antwort ihn nicht fuehrt. Das ist die
  /// verlaessliche Quelle fuer den Vertragsweg; `getPartnerInfo` gibt ihn
  /// nicht aus.
  final AvvStand? avv;
}

class BetriebListe {
  const BetriebListe({required this.kunden, required this.cursor, required this.gesamt});

  factory BetriebListe.aus(Map<String, dynamic> d) => BetriebListe(
        kunden: alsListe(d['kunden'])
            .map((e) => BetriebZeile.aus(alsMap(e)))
            .toList(growable: false),
        cursor: alsTextOderNull(d['cursor']),
        gesamt: alsZahlOderNull(d['gesamt']) ?? 0,
      );

  final List<BetriebZeile> kunden;

  /// Weiter mit diesem Wert als `cursor`; `null` heisst: das war alles.
  final String? cursor;
  final int gesamt;
}

class Betrieb {
  const Betrieb({
    required this.zeile,
    required this.statusAt,
    required this.liveEnabled,
    required this.angelegtAt,
    required this.angelegtVia,
    required this.stammdaten,
    required this.fonEingerichtet,
    required this.fonVerifiedAt,
    required this.zugangEmail,
    required this.zugangEingeladenAt,
    required this.zugangAngenommenAt,
  });

  factory Betrieb.aus(Map<String, dynamic> k) {
    final fon = alsMap(k['fon']);
    final zugang = alsMapOderNull(k['zugang']);
    return Betrieb(
      zeile: BetriebZeile.aus(k),
      statusAt: alsZahlOderNull(k['statusAt']),
      liveEnabled: alsJaNein(k['liveEnabled']),
      angelegtAt: alsZahlOderNull(k['angelegtAt']),
      angelegtVia: alsTextOderNull(k['angelegtVia']),
      stammdaten: alsMap(k['betrieb']),
      fonEingerichtet: alsJaNein(fon['eingerichtet']),
      fonVerifiedAt: alsZahlOderNull(fon['verifiedAt']),
      zugangEmail: zugang == null ? null : alsTextOderNull(zugang['email']),
      zugangEingeladenAt: zugang == null ? null : alsZahlOderNull(zugang['eingeladenAt']),
      zugangAngenommenAt: zugang == null ? null : alsZahlOderNull(zugang['angenommenAt']),
    );
  }

  final BetriebZeile zeile;
  final int? statusAt;
  final bool liveEnabled;
  final int? angelegtAt;
  final String? angelegtVia;

  /// Die Stammdaten, so wie das Backend sie fuehrt. Bewusst als Karte und nicht
  /// als getippte Klasse: es ist eine reine Anzeige, und ein neues Feld soll
  /// hier ankommen, ohne dass das Paket nachzieht.
  final Map<String, dynamic> stammdaten;
  final bool fonEingerichtet;
  final int? fonVerifiedAt;
  final String? zugangEmail;
  final int? zugangEingeladenAt;
  final int? zugangAngenommenAt;

  String get customerId => zeile.customerId;
  String get status => zeile.status;
  AvvStand? get avv => zeile.avv;
}

class FonLinkErgebnis {
  const FonLinkErgebnis({required this.customerId, required this.sentTo, required this.expiresAt});

  factory FonLinkErgebnis.aus(Map<String, dynamic> d, String rueckfall) => FonLinkErgebnis(
        customerId: alsText(d['customerId'], rueckfall),
        sentTo: alsText(d['sentTo']),
        expiresAt: alsZahlOderNull(d['expiresAt']) ?? 0,
      );

  final String customerId;

  /// Empfaenger, **maskiert**.
  final String sentTo;
  final int expiresAt;
}

// ---------------------------------------------------------------------------
// Signatur
// ---------------------------------------------------------------------------

class SignaturFehler {
  const SignaturFehler({required this.code, required this.meldung, required this.rc});

  final String? code;
  final String? meldung;

  /// Der FinanzOnline-Returncode, sofern die Ablehnung von dort kam.
  final String? rc;
}

class SignaturHistorieEintrag {
  const SignaturHistorieEintrag({required this.von, required this.nach, required this.at, required this.grund});

  final String? von;
  final String nach;
  final int at;
  final String? grund;
}

/// Ein Signaturantrag.
///
/// `beantragt -> zugeteilt -> registriert -> bereit`. `registriert` heisst: die
/// Einheit ist FinanzOnline bekannt; `bereit` heisst: sie darf signieren. In
/// der Testumgebung wird ohne `registriert` direkt `bereit` erreicht.
class SignaturAntrag {
  const SignaturAntrag({
    required this.requestId,
    required this.status,
    required this.statusText,
    required this.art,
    required this.vdaId,
    required this.signatureId,
    required this.fehler,
    required this.angefordertVia,
    required this.createdAt,
    required this.updatedAt,
    required this.historie,
  });

  factory SignaturAntrag.aus(Map<String, dynamic> a) {
    final f = alsMapOderNull(a['fehler']);
    return SignaturAntrag(
      requestId: alsText(a['requestId']),
      status: alsText(a['status']),
      statusText: alsText(a['statusText']),
      art: alsText(a['art'], 'signaturkarte'),
      vdaId: alsTextOderNull(a['vdaId']),
      signatureId: alsTextOderNull(a['signatureId']),
      fehler: f == null
          ? null
          : SignaturFehler(
              code: alsTextOderNull(f['code']),
              meldung: alsTextOderNull(f['meldung']),
              rc: alsTextOderNull(f['rc']),
            ),
      angefordertVia: alsTextOderNull(a['angefordertVia']),
      createdAt: alsZahlOderNull(a['createdAt']),
      updatedAt: alsZahlOderNull(a['updatedAt']),
      historie: alsListe(a['historie']).map((h) {
        final e = alsMap(h);
        return SignaturHistorieEintrag(
          von: alsTextOderNull(e['von']),
          nach: alsText(e['nach']),
          at: alsZahlOderNull(e['at']) ?? 0,
          grund: alsTextOderNull(e['grund']),
        );
      }).toList(growable: false),
    );
  }

  final String requestId;
  final String status;
  final String statusText;
  final String art;
  final String? vdaId;
  final String? signatureId;
  final SignaturFehler? fehler;
  final String? angefordertVia;
  final int? createdAt;
  final int? updatedAt;
  final List<SignaturHistorieEintrag> historie;
}

class SignaturAntragErgebnis {
  const SignaturAntragErgebnis({required this.antrag, required this.wiederholt, required this.hinweis});

  final SignaturAntrag antrag;

  /// `true`, wenn schon ein Antrag lief -- dann ist es der laufende.
  final bool wiederholt;
  final String? hinweis;
}

class SignaturStand {
  const SignaturStand({
    required this.bereit,
    required this.signatureId,
    required this.vdaId,
    required this.antraege,
    required this.fonVorhanden,
    required this.fonGeprueftAt,
  });

  factory SignaturStand.aus(Map<String, dynamic> d) {
    final s = alsMap(d['signatur']);
    final fon = alsMap(d['fon']);
    return SignaturStand(
      bereit: alsJaNein(s['bereit']),
      signatureId: alsTextOderNull(s['signatureId']),
      vdaId: alsTextOderNull(s['vdaId']),
      antraege: alsListe(d['antraege'])
          .map((e) => SignaturAntrag.aus(alsMap(e)))
          .toList(growable: false),
      fonVorhanden: alsJaNein(fon['vorhanden']),
      fonGeprueftAt: alsZahlOderNull(fon['geprueftAt']),
    );
  }

  final bool bereit;
  final String? signatureId;
  final String? vdaId;
  final List<SignaturAntrag> antraege;
  final bool fonVorhanden;
  final int? fonGeprueftAt;
}

// ---------------------------------------------------------------------------
// Kassen
// ---------------------------------------------------------------------------

class KassenSchritt {
  const KassenSchritt(this.key, this.text);

  final String key;
  final String text;
}

class KassenFehler {
  const KassenFehler({
    required this.code,
    required this.meldung,
    required this.rc,
    required this.schritt,
    required this.at,
  });

  final String? code;
  final String? meldung;
  final String? rc;
  final String? schritt;
  final int? at;
}

class Kasse {
  const Kasse({
    required this.cashregisterId,
    required this.name,
    required this.status,
    required this.statusText,
    required this.automatisch,
    required this.schritt,
    required this.schrittText,
    required this.erledigt,
    required this.schritte,
    required this.signatureId,
    required this.versuche,
    required this.letzterFehler,
    required this.createdAt,
  });

  factory Kasse.aus(Map<String, dynamic> k) {
    final f = alsMapOderNull(k['letzterFehler']);
    return Kasse(
      cashregisterId: alsText(k['cashregisterId']),
      name: alsTextOderNull(k['name']),
      status: alsText(k['status']),
      statusText: alsText(k['statusText']),
      automatisch: alsJaNein(k['automatisch'], true),
      schritt: alsTextOderNull(k['schritt']),
      schrittText: alsTextOderNull(k['schrittText']),
      erledigt: alsTexte(k['erledigt']),
      schritte: alsListe(k['schritte']).map((s) {
        final e = alsMap(s);
        return KassenSchritt(alsText(e['key']), alsText(e['text']));
      }).toList(growable: false),
      signatureId: alsTextOderNull(k['signatureId']),
      versuche: alsZahlOderNull(k['versuche']) ?? 0,
      letzterFehler: f == null
          ? null
          : KassenFehler(
              code: alsTextOderNull(f['code']),
              meldung: alsTextOderNull(f['meldung']),
              rc: alsTextOderNull(f['rc']),
              schritt: alsTextOderNull(f['schritt']),
              at: alsZahlOderNull(f['at']),
            ),
      createdAt: alsZahlOderNull(k['createdAt']),
    );
  }

  final String cashregisterId;
  final String? name;

  /// `entwurf`, `laeuft`, `live` oder `fehlgeschlagen`.
  final String status;
  final String statusText;

  /// `true`: die Kasse geht von selbst live, sobald die Signatur bereit ist.
  final bool automatisch;

  /// Der naechste offene Schritt; `null`, wenn die Kasse live ist.
  final String? schritt;
  final String? schrittText;
  final List<String> erledigt;

  /// Die Schritte, die fuer genau diese Kasse gelten (Testumgebung: weniger).
  final List<KassenSchritt> schritte;
  final String? signatureId;
  final int versuche;
  final KassenFehler? letzterFehler;
  final int? createdAt;

  bool get istLive => status == 'live';
}

class NeueKasse {
  const NeueKasse({
    required this.kasse,
    required this.gestartet,
    required this.ok,
    required this.schritt,
    required this.grund,
  });

  final Kasse kasse;
  final bool gestartet;

  /// `null` heisst "nicht gelaufen" und ist etwas anderes als `false`.
  final bool? ok;
  final String? schritt;

  /// `signature_not_ready` oder `automatik_aus`, wenn nicht gestartet wurde.
  final String? grund;
}

class KassenInbetriebnahme {
  const KassenInbetriebnahme({required this.kasse, required this.unveraendert});

  final Kasse kasse;

  /// `true`: die Kasse war schon live, es wurde nichts getan.
  final bool unveraendert;
}

class KassenListe {
  const KassenListe({required this.customerId, required this.kassen, required this.signaturBereit});

  factory KassenListe.aus(Map<String, dynamic> d, String rueckfall) => KassenListe(
        customerId: alsText(d['customerId'], rueckfall),
        kassen: alsListe(d['kassen']).map((e) => Kasse.aus(alsMap(e))).toList(growable: false),
        signaturBereit: alsJaNein(d['signaturBereit']),
      );

  final String customerId;
  final List<Kasse> kassen;
  final bool signaturBereit;
}

// ---------------------------------------------------------------------------
// Zugangsdaten
// ---------------------------------------------------------------------------

/// Eine Kasse samt ihrem Token. **Der Token ist ein Geheimnis des Betriebs** --
/// deshalb steht er als [KasseneckSecret] und nicht als `String` darin.
class KassenZugang {
  const KassenZugang({
    required this.cashregisterId,
    required this.name,
    required this.live,
    required this.cashregisterToken,
  });

  final String cashregisterId;
  final String? name;
  final bool live;

  /// Kopfzeile `cashregister-token` fuer `createReceipt`. Verschluesselt
  /// speichern.
  final KasseneckSecret cashregisterToken;

  @override
  String toString() => 'KassenZugang($cashregisterId, $cashregisterToken)';
}

/// Die beiden Geheimnisse, die eine App braucht, um im Namen des Betriebs
/// Belege zu signieren.
///
/// **Nur verschluesselt speichern. Nie protokollieren, nie in eine Mail, nie in
/// einen Fehlerbericht.** Jeder Abruf wird mitgeschrieben (Partner, Schluessel,
/// Zeitpunkt) und ist fuer den Betrieb und fuer Kasseneck sichtbar.
///
/// Die Werte stecken in [KasseneckSecret]: `print`, `toString` und `jsonEncode`
/// zeigen eine Maske. Heraus kommt man nur ueber `.reveal()` -- und genau diese
/// Stellen findet eine Suche.
class BetriebZugangsdaten {
  const BetriebZugangsdaten({
    required this.customerId,
    required this.firma,
    required this.env,
    required this.apiKey,
    required this.kassen,
    required this.hinweis,
  });

  factory BetriebZugangsdaten.aus(Map<String, dynamic> d, String rueckfall) => BetriebZugangsdaten(
        customerId: alsText(d['customerId'], rueckfall),
        firma: alsText(d['firma']),
        env: envAus(d['env']),
        apiKey: alsSecret('apiKey', d['apiKey']),
        kassen: alsListe(d['kassen']).map((e) {
          final k = alsMap(e);
          return KassenZugang(
            cashregisterId: alsText(k['cashregisterId']),
            name: alsTextOderNull(k['name']),
            live: alsJaNein(k['live']),
            cashregisterToken: alsSecret('cashregisterToken', k['cashregisterToken']),
          );
        }).toList(growable: false),
        hinweis: alsText(d['hinweis']),
      );

  final String customerId;
  final String firma;
  final PartnerEnv env;

  /// Bearer-Schluessel des Betriebs (`kr_...`). Verschluesselt speichern.
  final KasseneckSecret apiKey;
  final List<KassenZugang> kassen;
  final String hinweis;

  /// Bewusst ohne die Werte: `print(zugangsdaten)` ist der haeufigste Weg, auf
  /// dem ein Geheimnis in ein Protokoll rutscht.
  @override
  String toString() => 'BetriebZugangsdaten($customerId, $apiKey, ${kassen.length} Kassen)';
}

// ---------------------------------------------------------------------------
// Vertrag
// ---------------------------------------------------------------------------

class VertragsMeldung {
  const VertragsMeldung({
    required this.vertragId,
    required this.bestaetigtAt,
    required this.art,
    required this.version,
  });

  final String vertragId;
  final int bestaetigtAt;
  final String art;
  final String version;
}
