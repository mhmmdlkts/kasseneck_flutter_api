/// Pruefung der Signatur eingehender Kasseneck-Webhooks.
///
/// **Das ist der Teil, den Integratoren am haeufigsten falsch bauen** -- und
/// der einzige, bei dem ein Fehler nicht auffaellt: eine zu lasche Pruefung
/// laesst jeden durch, der die Adresse kennt, und meldet dabei nie etwas.
/// Deshalb liegt sie fertig im Paket und nicht als Beispielschnipsel in der
/// Doku.
///
/// Vier Dinge muessen stimmen, und jedes einzelne fehlt in der Praxis
/// regelmaessig:
///
/// 1. **Der ROHE Rumpf.** Signiert werden die Bytes, die ankommen -- nicht das
///    Ergebnis von `jsonDecode` und erneutem `jsonEncode`. Schluesselreihen-
///    folge, Zahlenschreibweise und Leerraum aendern sich dabei, und die
///    Signatur passt nicht mehr. In `dart:io` heisst das: den Datenstrom der
///    Anfrage sammeln, bevor irgendetwas ihn deutet.
/// 2. **Das Zeitfenster.** Ohne Pruefung von `t` ist eine einmal
///    mitgeschnittene, gueltig signierte Zustellung fuer immer
///    wiederverwendbar. 300 Sekunden in beide Richtungen -- auch in die
///    Zukunft, sonst hilft eine falsch gestellte Uhr auf der Gegenseite dem
///    Angreifer.
/// 3. **Der zeitkonstante Vergleich.** Ein `==` auf Hex-Zeichenketten bricht
///    beim ersten abweichenden Zeichen ab. Wer messen kann, wie lange die
///    Ablehnung dauert, raet die Signatur Zeichen fuer Zeichen.
/// 4. **Jede Ausnahme ist eine Ablehnung.** Ein `catch`, das weiterlaufen
///    laesst, macht aus einem Formfehler ein Ja.
///
/// Der Kopf lautet `X-Kasseneck-Signature: t=<unix-sekunden>,v1=<hex>` mit
/// `v1 = HMAC-SHA256(secret, "<t>.<roher Rumpf>")`. **Mehrere `v1=`-Anteile
/// sind erlaubt** -- so laeuft ein Schluesselwechsel ohne Zustellungsluecke; es
/// reicht, wenn einer passt.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Der Kopf, in dem die Signatur steht.
const String kWebhookSignaturKopf = 'X-Kasseneck-Signature';

/// Der Kopf mit dem Ereignisnamen (dasselbe wie `body.type`).
const String kWebhookEreignisKopf = 'X-Kasseneck-Event';

/// Der Kopf mit der Zustell-Kennung -- bei Wiederholungen **dieselbe**.
const String kWebhookZustellungKopf = 'X-Kasseneck-Delivery';

/// Erlaubte Abweichung des Zeitstempels, in Sekunden (in beide Richtungen).
const int kWebhookToleranzSek = 300;

/// Wartezeiten zwischen den Zustellversuchen, in Sekunden.
const List<int> kWebhookWiederholungSek = <int>[60, 300, 1800, 7200, 43200];

/// Erstversuch plus je eine Wiederholung pro Planeintrag.
const int kWebhookMaxVersuche = 6;

/// So lange wartet Kasseneck auf eine 2xx-Antwort.
const Duration kWebhookFrist = Duration(seconds: 10);

/// Hoechstzahl der Webhook-Endpunkte je Partner.
const int kWebhookLimit = 10;

/// Warum eine Zustellung abgelehnt wurde. Jeder Grund ist ein Nein.
enum WebhookAblehnung {
  secretFehlt,
  kopfFehlt,
  kopfUnbrauchbar,
  rumpfFehlt,
  zeitfenster,
  signatur,
  rumpfKeinJson,
  rumpfKeinEreignis,
}

/// Das Ergebnis der Pruefung. Entweder ist sie durch -- dann steht der
/// Zeitstempel fest --, oder sie nennt genau einen Grund.
class WebhookPruefung {
  const WebhookPruefung.ok(this.zeitstempelSek)
      : ok = true,
        grund = null;
  const WebhookPruefung.nein(this.grund)
      : ok = false,
        zeitstempelSek = 0;

  final bool ok;
  final int zeitstempelSek;
  final WebhookAblehnung? grund;

  @override
  String toString() => ok ? 'WebhookPruefung.ok($zeitstempelSek)' : 'WebhookPruefung.nein(${grund!.name})';
}

/// Prueft die Signatur einer eingehenden Zustellung.
///
/// [secrets] ist das Secret aus `createPartnerWebhook` -- es verlaesst den
/// Server genau einmal. Mehrere erlauben den Schluesselwechsel: es reicht, wenn
/// einer passt.
///
/// [rumpf] ist der **rohe** Rumpf: die Bytes, wie sie ankamen. Nicht das
/// Ergebnis von `jsonDecode`, und nichts, was danach wieder zusammengesetzt
/// wurde.
///
/// [jetztSek] ist injizierbar -- kein Test dieses Pakets haengt an der Wanduhr.
///
/// Wirft **nie**: jede Ausnahme im Inneren wird zur Ablehnung.
WebhookPruefung pruefeWebhookSignatur({
  required List<String> secrets,
  required String? signaturKopf,
  required List<int> rumpf,
  int? jetztSek,
  int toleranzSek = kWebhookToleranzSek,
}) {
  try {
    final gueltige = secrets.where((s) => s.isNotEmpty).toList(growable: false);
    if (gueltige.isEmpty) return const WebhookPruefung.nein(WebhookAblehnung.secretFehlt);

    if (signaturKopf == null || signaturKopf.trim().isEmpty) {
      return const WebhookPruefung.nein(WebhookAblehnung.kopfFehlt);
    }
    final kopf = leseSignaturKopf(signaturKopf);
    if (kopf == null) return const WebhookPruefung.nein(WebhookAblehnung.kopfUnbrauchbar);

    final jetzt = jetztSek ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    // In BEIDE Richtungen: eine vorgehende Uhr auf der Gegenseite darf ein
    // altes Ereignis nicht wieder gueltig machen.
    if ((jetzt - kopf.t).abs() > toleranzSek) {
      return const WebhookPruefung.nein(WebhookAblehnung.zeitfenster);
    }

    final nachricht = <int>[...utf8.encode('${kopf.t}.'), ...rumpf];
    for (final secret in gueltige) {
      final soll = Hmac(sha256, utf8.encode(secret)).convert(nachricht).bytes;
      for (final v1 in kopf.v1) {
        final ist = hexZuBytes(v1);
        if (ist != null && gleichZeitkonstant(ist, soll)) {
          return WebhookPruefung.ok(kopf.t);
        }
      }
    }
    return const WebhookPruefung.nein(WebhookAblehnung.signatur);
  } on Object {
    // Punkt 4 im Bibliothekskommentar: eine Ausnahme ist eine Ablehnung, nie
    // ein Ja.
    return const WebhookPruefung.nein(WebhookAblehnung.signatur);
  }
}

/// Bequemlichkeit fuer Empfaenger, die den Rumpf schon als Zeichenkette haben.
///
/// **Nur nehmen, wenn die Zeichenkette wirklich der rohe Rumpf ist** -- also
/// `utf8.decode(bytes)` und nicht ein neu zusammengesetztes JSON.
WebhookPruefung pruefeWebhookSignaturText({
  required List<String> secrets,
  required String? signaturKopf,
  required String rumpf,
  int? jetztSek,
  int toleranzSek = kWebhookToleranzSek,
}) =>
    pruefeWebhookSignatur(
      secrets: secrets,
      signaturKopf: signaturKopf,
      rumpf: utf8.encode(rumpf),
      jetztSek: jetztSek,
      toleranzSek: toleranzSek,
    );

/// Zeitstempel und Signaturanteile aus dem Kopf.
class SignaturKopf {
  const SignaturKopf(this.t, this.v1);

  final int t;
  final List<String> v1;
}

/// Zerlegt den Signaturkopf. `null`, wenn kein brauchbarer Zeitstempel oder gar
/// kein `v1=`-Anteil darin steht.
SignaturKopf? leseSignaturKopf(String kopf) {
  final teile = kopf.split(',').map((x) => x.trim()).toList(growable: false);
  final tTeile = teile.where((x) => x.startsWith('t=')).toList(growable: false);
  final v1 = teile.where((x) => x.startsWith('v1=')).map((x) => x.substring(3)).toList(growable: false);
  if (tTeile.isEmpty || v1.isEmpty) return null;
  final tTeil = tTeile.first;
  final roh = tTeil.substring(2);
  // Nur ganze Zahlen: `int.tryParse` liesse ' 12 ' und '+12' durch, und ein
  // Zeitstempel ist keins von beidem.
  if (!RegExp(r'^\d{1,15}$').hasMatch(roh)) return null;
  final t = int.tryParse(roh);
  return t == null ? null : SignaturKopf(t, v1);
}

/// Hex zu Bytes; `null` bei ungerader Laenge oder Nicht-Hex.
List<int>? hexZuBytes(String hex) {
  if (hex.isEmpty || hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
  final bytes = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Vergleich ohne frueh Abbrechen. Die Laengenpruefung davor verraet nur die
/// Laenge des Hashs, und die ist bekannt (SHA-256, 32 Bytes); der Inhalt wird
/// immer vollstaendig durchlaufen.
bool gleichZeitkonstant(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var unterschied = 0;
  for (var i = 0; i < a.length; i++) {
    unterschied |= a[i] ^ b[i];
  }
  return unterschied == 0;
}
