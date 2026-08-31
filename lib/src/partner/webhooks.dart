/// Webhooks: Endpunkte verwalten und eingehende Zustellungen auswerten.
///
/// Die Signaturpruefung liegt daneben in `webhook_signatur.dart` -- sie braucht
/// weder Transport noch Schluessel und laeuft in jedem Empfaenger, auch in
/// einem, der sonst nichts von diesem Paket benutzt.
library;

import 'dart:convert';

import 'typen.dart';
import 'webhook_signatur.dart';

/// Alle Ereignisse, die ein Webhook abonnieren **und proben** kann. Ein
/// Endpunkt bekommt ausschliesslich die, die in seiner `events`-Liste stehen.
///
/// Kasseneck fuehrt daneben interne Ereignisse (etwa den Abschluss eines
/// Auftragsverarbeitungsvertrags). Sie stehen hier bewusst nicht: sie lassen
/// sich weder abonnieren noch mit `sendPartnerWebhookTest` ausloesen, und ein
/// Name in dieser Liste, den niemand bestellen kann, waere ein Versprechen
/// ohne Deckung.
const List<String> kPartnerWebhookEreignisse = <String>[
  'customer.created',
  'customer.updated',
  'customer.status_changed',
  'customer.fon_verified',
  'customer.live_enabled',
  'signature.requested',
  'signature.ready',
  'signature.failed',
  'cashregister.created',
  'cashregister.live',
  'cashregister.failed',
  'app.version.accepted',
  'app.version.rejected',
  'webhook.test',
];

bool istPartnerWebhookEreignis(Object? wert) =>
    wert is String && kPartnerWebhookEreignisse.contains(wert);

/// Die Felder des Umschlags, so wie er auf der Leitung liegt.
///
/// Als Liste, damit der Zwilling sie nachhaelt: `test` kam spaeter dazu, und
/// genau ein solches Feld verschwindet sonst auf einer Seite, ohne dass etwas
/// rot wird.
const List<String> kWebhookUmschlagFelder = <String>[
  'id',
  'type',
  'createdAt',
  'partnerId',
  'test',
  'data',
];

/// Die Huelle jeder Zustellung.
///
/// [type] bleibt bewusst ein `String` und keine Aufzaehlung: ein spaeter
/// ergaenztes Ereignis soll einen laufenden Empfaenger nicht anhalten, sondern
/// in seinem `default`-Zweig landen.
class PartnerWebhookEreignis {
  const PartnerWebhookEreignis({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.partnerId,
    required this.test,
    required this.data,
  });

  /// `evt_...` -- die Kennung, auf die **entdoppelt** wird.
  final String id;
  final String type;
  final int createdAt;
  final String partnerId;

  /// **Probe oder Ernstfall.** Eine mit `sendPartnerWebhookTest` ausgeloeste
  /// Zustellung traegt `test: true` im Umschlag; ein echtes Ereignis fuehrt
  /// das Feld gar nicht, hier steht dann `false`.
  ///
  /// Diese Zeile gehoert an den Anfang jedes Handlers:
  ///
  /// ```dart
  /// if (ereignis.test) return;
  /// ```
  ///
  /// Ohne sie haelt jemand eine Probe fuer echt und schreibt seinem Kunden,
  /// die Kasse sei fertig. Eine Probe traegt eine erkennbar erfundene
  /// Nutzlast -- nur sieht man das erst, wenn man hinsieht.
  final bool test;
  final Map<String, dynamic> data;

  @override
  String toString() => 'PartnerWebhookEreignis($id, $type${test ? ', Probe' : ''})';
}

/// Das Ergebnis von [leseWebhookEreignis]: entweder das Ereignis, oder genau
/// ein Ablehnungsgrund.
class WebhookEreignisErgebnis {
  const WebhookEreignisErgebnis.ok(this.ereignis, this.zeitstempelSek)
      : ok = true,
        grund = null;
  const WebhookEreignisErgebnis.nein(this.grund)
      : ok = false,
        ereignis = null,
        zeitstempelSek = 0;

  final bool ok;
  final PartnerWebhookEreignis? ereignis;
  final int zeitstempelSek;
  final WebhookAblehnung? grund;
}

/// Prueft die Signatur **und** liest das Ereignis -- in dieser Reihenfolge. Wer
/// zuerst liest und dann prueft, hat den fremden Rumpf schon durch seinen Code
/// laufen lassen.
///
/// **Entdoppeln nicht vergessen:** dieselbe Zustellung kann mehrfach ankommen
/// (Wiederholung nach einer Antwort, die unterwegs verloren ging). Massgeblich
/// ist `ereignis.id`, nicht der Kopf `X-Kasseneck-Delivery` -- der ist bei
/// Wiederholungen derselbe, beantwortet aber "habe ich dieses Ereignis schon
/// verarbeitet?" nur fuer genau diesen Endpunkt.
///
/// Innerhalb von zehn Sekunden mit 2xx antworten und die Arbeit danach
/// erledigen; sonst wiederholt Kasseneck bis zu fuenfmal
/// ([kWebhookWiederholungSek]) und gibt dann auf.
WebhookEreignisErgebnis leseWebhookEreignis({
  required List<String> secrets,
  required String? signaturKopf,
  required List<int> rumpf,
  int? jetztSek,
  int toleranzSek = kWebhookToleranzSek,
}) {
  final geprueft = pruefeWebhookSignatur(
    secrets: secrets,
    signaturKopf: signaturKopf,
    rumpf: rumpf,
    jetztSek: jetztSek,
    toleranzSek: toleranzSek,
  );
  if (!geprueft.ok) return WebhookEreignisErgebnis.nein(geprueft.grund!);

  Object? roh;
  try {
    roh = jsonDecode(utf8.decode(rumpf));
  } on Object {
    return const WebhookEreignisErgebnis.nein(WebhookAblehnung.rumpfKeinJson);
  }
  if (roh is! Map) return const WebhookEreignisErgebnis.nein(WebhookAblehnung.rumpfKeinEreignis);
  final e = Map<String, dynamic>.from(roh);
  final id = e['id'];
  final type = e['type'];
  if (id is! String || type is! String) {
    return const WebhookEreignisErgebnis.nein(WebhookAblehnung.rumpfKeinEreignis);
  }
  return WebhookEreignisErgebnis.ok(
    PartnerWebhookEreignis(
      id: id,
      type: type,
      createdAt: alsZahlOderNull(e['createdAt']) ?? 0,
      partnerId: alsText(e['partnerId']),
      // Nur ein ausdrueckliches `true` ist eine Probe. Alles andere -- auch
      // ein fehlendes Feld -- ist der Ernstfall; im Zweifel lieber einmal zu
      // viel gearbeitet als eine echte Kasse fuer eine Probe gehalten.
      test: e['test'] == true,
      data: alsMap(e['data']),
    ),
    geprueft.zeitstempelSek,
  );
}

// ---------------------------------------------------------------------------
// Endpunkte verwalten
// ---------------------------------------------------------------------------

class PartnerWebhook {
  const PartnerWebhook({
    required this.webhookId,
    required this.url,
    required this.events,
    required this.aktiv,
    required this.beschreibung,
    required this.createdAt,
    required this.letzteZustellung,
    required this.fehlerInFolge,
  });

  factory PartnerWebhook.aus(Map<String, dynamic> w) => PartnerWebhook(
        webhookId: alsText(w['webhookId']),
        url: alsText(w['url']),
        events: alsTexte(w['events']),
        aktiv: w['active'] != false,
        beschreibung: alsTextOderNull(w['description']),
        createdAt: alsZahlOderNull(w['createdAt']),
        letzteZustellung: alsZahlOderNull(w['lastDelivery']),
        fehlerInFolge: alsZahlOderNull(w['consecutiveFailures']) ?? 0,
      );

  final String webhookId;
  final String url;
  final List<String> events;
  final bool aktiv;
  final String? beschreibung;
  final int? createdAt;
  final int? letzteZustellung;

  /// Fehlversuche in Folge -- steigt der Wert, stimmt beim Empfaenger etwas
  /// nicht.
  final int fehlerInFolge;
}

class NeuerWebhook {
  const NeuerWebhook({required this.webhook, required this.secret});

  final PartnerWebhook webhook;

  /// Das Secret fuer die Signaturpruefung. **Es kommt genau einmal** -- beim
  /// Anlegen. Danach gibt das Backend es nie wieder aus; wer es verliert, legt
  /// einen neuen Endpunkt an.
  ///
  /// Bewusst ein `String` und kein [KasseneckSecret]: es gehoert dem Partner
  /// selbst und nicht einem fremden Betrieb, und es muss unveraendert in die
  /// eigene Konfiguration wandern. Verschluesselt speichern gilt trotzdem.
  final String secret;
}

class WebhookEreignisKatalog {
  const WebhookEreignisKatalog(this.key, this.text);

  final String key;
  final String text;
}

class WebhookListe {
  const WebhookListe({required this.webhooks, required this.ereignisse});

  factory WebhookListe.aus(Map<String, dynamic> d) => WebhookListe(
        webhooks: alsListe(d['webhooks'])
            .map((e) => PartnerWebhook.aus(alsMap(e)))
            .toList(growable: false),
        ereignisse: alsListe(d['events']).map((e) {
          final k = alsMap(e);
          return WebhookEreignisKatalog(alsText(k['key']), alsText(k['text']));
        }).toList(growable: false),
      );

  final List<PartnerWebhook> webhooks;

  /// Der Katalog: Ereignisname und deutscher Text, so wie das Panel ihn zeigt.
  final List<WebhookEreignisKatalog> ereignisse;
}

class WebhookZustellung {
  const WebhookZustellung({
    required this.deliveryId,
    required this.webhookId,
    required this.event,
    required this.eventId,
    required this.status,
    required this.versuche,
    required this.letzterVersuchAt,
    required this.naechsterVersuchAt,
    required this.statusCode,
    required this.antwort,
    required this.createdAt,
  });

  factory WebhookZustellung.aus(Map<String, dynamic> z) => WebhookZustellung(
        deliveryId: alsText(z['deliveryId']),
        webhookId: alsText(z['webhookId']),
        event: alsText(z['event']),
        eventId: alsText(z['eventId']),
        status: alsText(z['status']),
        versuche: alsZahlOderNull(z['attempts']) ?? 0,
        letzterVersuchAt: alsZahlOderNull(z['letzterVersuchAt']),
        naechsterVersuchAt: alsZahlOderNull(z['naechsterVersuchAt']),
        statusCode: alsZahlOderNull(z['statusCode']),
        antwort: alsTextOderNull(z['response']),
        createdAt: alsZahlOderNull(z['createdAt']),
      );

  final String deliveryId;
  final String webhookId;
  final String event;
  final String eventId;

  /// `offen`, `zugestellt` oder `fehlgeschlagen`.
  final String status;
  final int versuche;
  final int? letzterVersuchAt;
  final int? naechsterVersuchAt;
  final int? statusCode;

  /// Auszug der Antwort des Empfaengers, hoechstens 500 Zeichen.
  final String? antwort;
  final int? createdAt;
}

class WebhookTestErgebnis {
  const WebhookTestErgebnis({
    required this.eventId,
    required this.ereignis,
    required this.zustellungen,
  });

  final String eventId;

  /// Welches Ereignis geprobt wurde -- ohne Angabe `webhook.test`.
  final String ereignis;
  final List<dynamic> zustellungen;
}
