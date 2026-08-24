// Vergleicht die angeheftete Version des JS-Pakets mit der veröffentlichten.
//
// Warum es diesen Schritt gibt: `npm_version` in zwillinge.yaml ist fest
// angeheftet, und `tool/zwillinge.sh pruefen` beweist nur, dass die Kopie unter
// test/fixtures/vertrag/ zu GENAU DIESER Version gehört. Erscheint auf npm eine
// neuere mit einem zusätzlichen Feld oder Enum-Wert, bleibt hier alles grün —
// die Kopie ist ja echt, sie ist bloß alt. Damit wäre der Ausfallmodus, gegen
// den die ganze Vertragsprüfung gebaut ist (stilles Auseinanderlaufen bei
// grünem Test), nicht beseitigt, sondern nur verschoben: vorher log die Kopie,
// jetzt ist sie echt und womöglich veraltet.
//
// WARNUNG, KEIN TOR. Dieser Schritt endet IMMER mit 0 — auch bei Rückstand,
// auch wenn die Registry nicht erreichbar ist. Zwei Gründe: die feste
// Anheftung ist eine bewusste Entscheidung (nachgezogen wird von Hand, mit
// `tool/zwillinge.sh ziehen`), und eine Veröffentlichung in einem fremden
// Repository darf den Bau hier nicht anhalten.
//
// Aufruf: `dart run tool/vertrag_stand.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _paket = '@kreiseck/kasseneck-api';

/// Registry-Wurzel. Über `NPM_REGISTRY` umstellbar — für einen Spiegel, und um
/// den Ausfall der Registry überhaupt proben zu können (siehe Kopf: der Schritt
/// muss auch dann durchgehen).
String get _wurzel =>
    Platform.environment['NPM_REGISTRY']?.trim().isNotEmpty == true
        ? Platform.environment['NPM_REGISTRY']!.trim().replaceAll(RegExp(r'/+$'), '')
        : 'https://registry.npmjs.org';

Future<void> main() async {
  final angeheftet = _angeheftet();
  if (angeheftet == null) {
    _sagen('npm_version steht nicht in zwillinge.yaml — nichts zu vergleichen.');
    return;
  }

  final veroeffentlicht = await _veroeffentlicht();
  if (veroeffentlicht == null) {
    // Ausdrücklich kein Fehler: ohne Auskunft der Registry ist über den Stand
    // nichts bekannt, und Nichtwissen ist kein Befund.
    _sagen('Angeheftet ist $_paket $angeheftet. Die Registry war nicht '
        'erreichbar — der Stand bleibt ungeprüft.');
    return;
  }

  final vergleich = _vergleiche(angeheftet, veroeffentlicht);
  if (vergleich < 0) {
    _sagen(
      'Rückstand: angeheftet ist $_paket $angeheftet, veröffentlicht ist '
      '$veroeffentlicht. Nachziehen steht an — npm_version in zwillinge.yaml '
      'hochsetzen, `tool/zwillinge.sh ziehen`, `flutter test`. Der Testlauf '
      'sagt dann, was fehlt.',
      warnung: true,
    );
    return;
  }
  if (vergleich > 0) {
    // Kommt vor, während im JS-Repo eine Version vorbereitet ist, die noch
    // nicht veröffentlicht wurde. Auch das ist kein Fehler hier.
    _sagen('Angeheftet ist $_paket $angeheftet, veröffentlicht ist erst '
        '$veroeffentlicht — die Anheftung ist voraus.');
    return;
  }
  _sagen('Angeheftet ist $_paket $angeheftet — das ist die veröffentlichte '
      'Version.');
}

/// Die Anheftung aus der Datei lesen, die sie führt. Nirgends zweitschriftlich.
String? _angeheftet() {
  try {
    final doc = loadYaml(File('zwillinge.yaml').readAsStringSync());
    final wert = (doc as YamlMap)['npm_version'];
    final text = wert?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

/// Frist für den GESAMTEN Abruf — Verbindung, Antwortkopf und Rumpf zusammen.
const _frist = Duration(seconds: 20);

/// Die Version hinter dem dist-tag `latest`; `null`, wenn die Registry
/// schweigt, langsam ist oder etwas Unerwartetes antwortet.
///
/// Die Frist liegt über dem GANZEN Abruf, nicht über einzelnen Schritten. Ein
/// Deckel allein auf `close()` deckte nur den Antwortkopf ab: eine Gegenstelle,
/// die die Verbindung annimmt, HTTP 200 samt Kopf schickt und den Rumpf dann
/// stehen lässt, hinge unbegrenzt. Dafür braucht es keinen Ausfall der
/// Registry — ein Captive Portal oder eine halbtote CDN-Kante genügt.
///
/// Das wäre schlimmer als gar keine Prüfung: `continue-on-error` in der CI
/// fängt einen Fehlschlag ab, aber kein Hängen. Der Lauf stünde bis zum
/// Sechs-Stunden-Limit und würde dann abgebrochen — ein Cancel ist kein
/// „continue". Ein Hinweisschritt, der den Bau anhalten kann, ist schlechter
/// als keiner.
///
/// Aus demselben Grund NICHT je Teilschritt gedeckelt: mit tröpfelnden Bytes
/// ließe sich eine Kette von Einzelfristen beliebig verlängern. Eine Frist über
/// das gesamte Future greift auch dann, wenn der Rumpf zur Hälfte ankommt und
/// dann stockt.
Future<String?> _veroeffentlicht() async {
  final klient = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final ziel = Uri.parse('$_wurzel/${Uri.encodeComponent(_paket)}/latest');
    return await _abrufen(klient, ziel).timeout(_frist);
  } catch (_) {
    return null;
  } finally {
    // Auch nach abgelaufener Frist: schneidet die noch offene Verbindung ab,
    // statt das Programm auf sie warten zu lassen.
    klient.close(force: true);
  }
}

/// Der Abruf selbst — bewusst ohne eigene Frist, die liegt in
/// [_veroeffentlicht] über dem Ganzen.
Future<String?> _abrufen(HttpClient klient, Uri ziel) async {
  final anfrage = await klient.getUrl(ziel);
  final antwort = await anfrage.close();
  if (antwort.statusCode != 200) {
    // Den Rumpf trotzdem abnehmen: eine nicht ausgelesene Antwort hielte die
    // Verbindung offen. Innerhalb der Frist, also ohne Hängerisiko.
    await antwort.drain<void>();
    return null;
  }
  final rumpf = await antwort.transform(utf8.decoder).join();
  final version = (jsonDecode(rumpf) as Map<String, dynamic>)['version'];
  final text = version?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// Negativ, wenn [a] älter ist als [b]. Vorabversionen ("0.7.0-rc.1") werden
/// auf ihren Zahlenteil gekürzt: für die Frage "steht Nachziehen an?" reicht
/// das, und eine halbe SemVer-Umsetzung wäre hier mehr Angriffsfläche als Nutzen.
int _vergleiche(String a, String b) {
  final links = _zahlen(a);
  final rechts = _zahlen(b);
  for (var i = 0; i < 3; i++) {
    final d = links[i].compareTo(rechts[i]);
    if (d != 0) return d;
  }
  // Gleiche Zahlen, aber verschiedener Text (Vorabversion): als gleich werten
  // statt zu raten, welche Seite vorn liegt.
  return 0;
}

List<int> _zahlen(String version) {
  final teile = version.split('-').first.split('.');
  return List<int>.generate(
    3,
    (i) => i < teile.length ? (int.tryParse(teile[i]) ?? 0) : 0,
  );
}

/// Ausgabe. In der CI zusätzlich als Annotation, damit ein Rückstand in der
/// Zusammenfassung des Laufs steht und nicht nur im Protokoll.
void _sagen(String text, {bool warnung = false}) {
  final einzeilig = text.replaceAll('\n', ' ');
  if (warnung && Platform.environment['GITHUB_ACTIONS'] == 'true') {
    stdout.writeln('::warning title=Vertrag nachziehen::$einzeilig');
  }
  stdout.writeln(einzeilig);
}
