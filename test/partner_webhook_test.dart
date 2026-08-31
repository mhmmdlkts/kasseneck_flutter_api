/// Die Signaturprüfung ist die eine Stelle, an der ein Fehler NICHT auffällt:
/// eine zu lasche Prüfung lässt jeden durch und meldet nie etwas. Deshalb
/// prüfen diese Tests nicht nur den guten Fall, sondern jede Hürde einzeln —
/// und zwar so, dass ihr Wegfall rot wird:
///
///   Zeitfenster weg     -> „abgelaufener Zeitstempel" und „aus der Zukunft"
///   Rumpf-Bindung weg   -> „verfälschter Rumpf"
///   Secret-Bindung weg  -> „fremdes Secret"
///   Kopf-Prüfung weg    -> „fehlender Kopf", „unbrauchbarer Kopf"
///   Längenprüfung weg   -> „abgeschnittene Signatur"
///   catch-als-Ja        -> „eine Ausnahme im Inneren ist eine Ablehnung"
///
/// Keiner hängt an der Wanduhr: `jetztSek` wird immer gesetzt.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/partner.dart';

/// Ein Rumpf, dessen Lesen scheitert -- der Fall, den Punkt 4 der Zusage
/// abdeckt. Realistisch ist er, weil `rumpf` aus einem fremden Datenstrom
/// kommt: ein abgerissener Upload liefert genau so eine Liste.
class _RumpfDerWirft extends ListBase<int> {
  @override
  int get length => throw StateError('Rumpf nicht lesbar');
  @override
  set length(int wert) => throw StateError('Rumpf nicht lesbar');
  @override
  int operator [](int i) => throw StateError('Rumpf nicht lesbar');
  @override
  void operator []=(int i, int wert) => throw StateError('Rumpf nicht lesbar');
}

void main() {
  const secret = 'whsec_TESTGEHEIMNIS_0123456789';
  final rumpf = jsonEncode(<String, dynamic>{
    'id': 'evt_1',
    'type': 'signature.ready',
    'createdAt': 1756000000000,
    'partnerId': 'ptn_1',
    'data': <String, dynamic>{'customerId': 'cust_1', 'firma': 'Bäckerei Jobst'},
  });
  const jetzt = 1756000000;

  /// Wie das Backend signiert (webhook-core.js): HMAC-SHA256 über `${t}.${body}`.
  String kopf(int t, {String? body, String mit = secret}) {
    final nachricht = '$t.${body ?? rumpf}';
    final hex = Hmac(sha256, utf8.encode(mit)).convert(utf8.encode(nachricht)).toString();
    return 't=$t,v1=$hex';
  }

  WebhookPruefung pruefe(String? k, {String? body, List<String>? secrets, int? nun, int? toleranz}) =>
      pruefeWebhookSignaturText(
        secrets: secrets ?? <String>[secret],
        signaturKopf: k,
        rumpf: body ?? rumpf,
        jetztSek: nun ?? jetzt,
        toleranzSek: toleranz ?? kWebhookToleranzSek,
      );

  test('gültige Signatur wird angenommen — als Text und als Bytes', () {
    final alsText = pruefe(kopf(jetzt));
    expect(alsText.ok, isTrue);
    expect(alsText.zeitstempelSek, jetzt);

    // Der Empfänger bekommt in aller Regel Bytes — beides muss zum selben
    // Ergebnis führen, sonst hängt die Prüfung an der Kodierung.
    final alsBytes = pruefeWebhookSignatur(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt),
      rumpf: utf8.encode(rumpf),
      jetztSek: jetzt,
    );
    expect(alsBytes.ok, isTrue);
  });

  test('verfälschter Rumpf wird abgelehnt', () {
    final r = pruefe(kopf(jetzt), body: rumpf.replaceAll('cust_1', 'cust_2'));
    expect(r.ok, isFalse);
    expect(r.grund, WebhookAblehnung.signatur);
  });

  test('ein neu zusammengesetzter Rumpf fällt durch — signiert sind die rohen Bytes', () {
    // Der häufigste Integrationsfehler: jsonDecode, dann jsonEncode mit
    // Einrückung. Die Daten sind dieselben, die Bytes nicht.
    final neuGebaut = const JsonEncoder.withIndent('  ').convert(jsonDecode(rumpf));
    expect(pruefe(kopf(jetzt), body: neuGebaut).ok, isFalse);
  });

  test('verfälschte Signatur wird abgelehnt', () {
    final echt = kopf(jetzt);
    // Ein einziges Hex-Zeichen kippen — Länge und Form bleiben gültig.
    final letzte = echt.substring(echt.length - 1);
    final gekippt = '${echt.substring(0, echt.length - 1)}${letzte == '0' ? '1' : '0'}';
    final r = pruefe(gekippt);
    expect(r.ok, isFalse);
    expect(r.grund, WebhookAblehnung.signatur);
  });

  test('abgelaufener Zeitstempel wird abgelehnt, der Rand gilt noch', () {
    final alt = pruefe(kopf(jetzt - kWebhookToleranzSek - 1));
    expect(alt.grund, WebhookAblehnung.zeitfenster);
    // Genau am Rand gilt sie noch — sonst wäre die Grenze eine andere als die
    // zugesagte.
    expect(pruefe(kopf(jetzt - kWebhookToleranzSek)).ok, isTrue);
  });

  test('Zeitstempel aus der Zukunft wird ebenso abgelehnt', () {
    // Sonst hilft eine vorgehende Uhr auf der Gegenseite dem Angreifer.
    expect(pruefe(kopf(jetzt + kWebhookToleranzSek + 1)).grund, WebhookAblehnung.zeitfenster);
  });

  test('fehlender oder leerer Kopf wird abgelehnt', () {
    for (final kein in <String?>[null, '', '   ']) {
      expect(pruefe(kein).grund, WebhookAblehnung.kopfFehlt, reason: 'Kopf ${kein ?? "null"}');
    }
  });

  test('unbrauchbarer Kopf wird abgelehnt, nicht geraten', () {
    const kaputt = <String>[
      'v1=abcdef', // ohne t
      't=1756000000', // ohne v1
      't=heute,v1=abcdef', // t ist keine Zahl
      't=+1756000000,v1=abcdef', // int.tryParse liesse das Vorzeichen durch
      't= 1756000000 ,v1=abcdef', // Leerraum innerhalb des Wertes
      'irgendwas',
    ];
    for (final k in kaputt) {
      expect(pruefe(k).grund, WebhookAblehnung.kopfUnbrauchbar, reason: 'Kopf "$k"');
    }
  });

  test('fremdes Secret wird abgelehnt', () {
    expect(pruefe(kopf(jetzt), secrets: <String>['whsec_EINANDERES']).grund, WebhookAblehnung.signatur);
  });

  test('fehlendes Secret wird abgelehnt — nicht stillschweigend übergangen', () {
    for (final kein in <List<String>>[<String>[], <String>['']]) {
      expect(pruefe(kopf(jetzt), secrets: kein).grund, WebhookAblehnung.secretFehlt);
    }
  });

  test('mehrere Secrets erlauben den Schlüsselwechsel ohne Zustellungslücke', () {
    expect(pruefe(kopf(jetzt), secrets: <String>['whsec_NEU', secret]).ok, isTrue);
  });

  test('mehrere v1-Anteile — einer muss passen', () {
    final echt = kopf(jetzt).split('v1=')[1];
    expect(pruefe('t=$jetzt,v1=${'0' * 64},v1=$echt').ok, isTrue);
  });

  test('abgeschnittene und nicht-hexadezimale Signatur werden abgelehnt, nicht geworfen', () {
    final echt = kopf(jetzt).split('v1=')[1];
    for (final v1 in <String>[echt.substring(0, 10), '${echt}ff', 'zzzz', '']) {
      expect(pruefe('t=$jetzt,v1=$v1').ok, isFalse, reason: 'v1="$v1" wurde angenommen');
    }
  });

  test('eine Ausnahme im Inneren ist eine Ablehnung, nie ein Ja', () {
    // Punkt 4 der Zusage. Ein Rumpf, dessen Einträge keine Bytes sind, lässt
    // das Zusammensetzen der signierten Nachricht werfen — das Ergebnis muss
    // ein sauberes Nein sein und darf nicht am catch vorbei zum Ja werden.
    final r = pruefeWebhookSignatur(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt),
      rumpf: _RumpfDerWirft(),
      jetztSek: jetzt,
    );
    expect(r.ok, isFalse);
    expect(r.grund, WebhookAblehnung.signatur);
  });

  test('leseSignaturKopf liest t und alle v1-Anteile', () {
    final gelesen = leseSignaturKopf('t=17,v1=aa,v1=bb');
    expect(gelesen!.t, 17);
    expect(gelesen.v1, <String>['aa', 'bb']);
    expect(leseSignaturKopf('t=17'), isNull);
    expect(leseSignaturKopf('v1=aa'), isNull);
  });

  test('leseWebhookEreignis prüft ERST die Signatur und liest dann', () {
    final gut = leseWebhookEreignis(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt),
      rumpf: utf8.encode(rumpf),
      jetztSek: jetzt,
    );
    expect(gut.ok, isTrue);
    expect(gut.ereignis!.id, 'evt_1');
    expect(gut.ereignis!.type, 'signature.ready');
    expect(gut.ereignis!.partnerId, 'ptn_1');
    expect(gut.ereignis!.data['customerId'], 'cust_1');
    // Ein echtes Ereignis führt das Feld `test` nicht — hier steht `false`.
    expect(gut.ereignis!.test, isFalse);

    // Ein Rumpf, der gar kein JSON ist, kommt gar nicht erst zum Lesen: die
    // Signatur passt schon nicht.
    final schlecht = leseWebhookEreignis(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt),
      rumpf: utf8.encode('kein json'),
      jetztSek: jetzt,
    );
    expect(schlecht.grund, WebhookAblehnung.signatur);
  });

  test('richtig signiertes, aber unbrauchbares JSON wird als solches gemeldet', () {
    const nurText = '"hallo"';
    expect(
      leseWebhookEreignis(
        secrets: <String>[secret],
        signaturKopf: kopf(jetzt, body: nurText),
        rumpf: utf8.encode(nurText),
        jetztSek: jetzt,
      ).grund,
      WebhookAblehnung.rumpfKeinEreignis,
    );

    const kaputt = '{';
    expect(
      leseWebhookEreignis(
        secrets: <String>[secret],
        signaturKopf: kopf(jetzt, body: kaputt),
        rumpf: utf8.encode(kaputt),
        jetztSek: jetzt,
      ).grund,
      WebhookAblehnung.rumpfKeinJson,
    );
  });

  test('unbekannter Ereignistyp kommt durch statt zu scheitern', () {
    // Eine später ergänzte Ereignisart darf einen laufenden Empfänger nicht
    // anhalten — sie landet in seinem default-Zweig.
    final neu = jsonEncode(<String, dynamic>{
      'id': 'evt_9',
      'type': 'kasse.neu_erfunden',
      'createdAt': 1,
      'partnerId': 'p',
      'data': <String, dynamic>{},
    });
    final r = leseWebhookEreignis(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt, body: neu),
      rumpf: utf8.encode(neu),
      jetztSek: jetzt,
    );
    expect(r.ok, isTrue);
    expect(r.ereignis!.type, 'kasse.neu_erfunden');
    expect(istPartnerWebhookEreignis(r.ereignis!.type), isFalse);
  });

  /// Die Marke, an der eine Probe von einem echten Ereignis zu unterscheiden
  /// ist.
  ///
  /// Rot-Probe: `test: e['test'] == true` in `webhooks.dart` durch
  /// `test: false` ersetzen — dann fällt genau dieser Test, und der Handler
  /// eines Partners hätte `if (ereignis.test) return;` geschrieben, ohne dass
  /// es je greift.
  test('eine Probe trägt test:true, ein echtes Ereignis das Feld gar nicht', () {
    final probe = jsonEncode(<String, dynamic>{
      'id': 'evt_probe',
      'type': 'cashregister.live',
      'createdAt': 1,
      'partnerId': 'ptn_1',
      'test': true,
      'data': <String, dynamic>{'customerId': 'ptest_beispiel00000000'},
    });
    final p = leseWebhookEreignis(
      secrets: <String>[secret],
      signaturKopf: kopf(jetzt, body: probe),
      rumpf: utf8.encode(probe),
      jetztSek: jetzt,
    );
    expect(p.ok, isTrue);
    expect(p.ereignis!.test, isTrue, reason: 'ohne diese Marke hält jemand eine Probe für echt');
    expect(p.ereignis.toString(), contains('Probe'));

    // Nur ein ausdrückliches `true` zählt. Alles andere ist der Ernstfall —
    // sonst verschluckte ein `test: "false"` aus einer fremden Quelle eine
    // echte Kasse.
    for (final wert in <Object?>['true', 1, <String, dynamic>{}, null]) {
      final rumpf2 = jsonEncode(<String, dynamic>{
        'id': 'e',
        'type': 'cashregister.live',
        'createdAt': 1,
        'partnerId': 'p',
        'test': wert,
        'data': <String, dynamic>{},
      });
      final r = leseWebhookEreignis(
        secrets: <String>[secret],
        signaturKopf: kopf(jetzt, body: rumpf2),
        rumpf: utf8.encode(rumpf2),
        jetztSek: jetzt,
      );
      expect(r.ok, isTrue);
      expect(r.ereignis!.test, isFalse, reason: 'test:$wert ist keine Probe');
    }
  });

  test('Ereignis-Katalog, Umschlag, Wiederholungsplan und Toleranz stimmen mit dem Backend überein', () {
    // WEBHOOK_EVENTS_OFFEN im Backend — OHNE die internen Ereignisse: was ein
    // Partner nicht abonnieren kann, darf hier nicht als abonnierbar
    // erscheinen.
    expect(kPartnerWebhookEreignisse, <String>[
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
    ]);
    expect(kPartnerWebhookEreignisse, isNot(contains('customer.avv_accepted')),
        reason: 'customer.avv_accepted ist intern — weder abonnierbar noch probbar');
    // webhook-core.payload() baut den Umschlag in dieser Reihenfolge; `test`
    // steht nur auf Proben darin.
    expect(kWebhookUmschlagFelder, <String>['id', 'type', 'createdAt', 'partnerId', 'test', 'data']);
    expect(kWebhookWiederholungSek, <int>[60, 300, 1800, 7200, 43200]);
    expect(kWebhookMaxVersuche, 6);
    expect(kWebhookToleranzSek, 300);
  });
}
