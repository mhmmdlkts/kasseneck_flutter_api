/// Kartenterminal-Zugang (zentral): der Vertrag der sieben Endpunkte
/// `registerTerminalDevice`, `getTerminalAccess`, `claimTerminal`,
/// `requestTerminalCode`, `getTerminalCode`, `reportTerminalLogin` und
/// `reportTerminalReady` (nur `/v3`, api_key wie [KasseneckApi]).
///
/// Das Terminal ist eine App am Handy. Ihr Login (Benutzer, Passwort) und die
/// Terminal-ID verwaltet Kasseneck zentral; ein Geraet meldet sich einmal an
/// (Kennung + Geheimnis), holt damit den Zugang und, wenn die Terminal-ID auf
/// ein neues Geraet zieht, den Freigabecode. Namen und Felder sind bewusst
/// neutral (kein Anbietername): der Anbieter benennt sich gerade um.
///
/// Geheimnisse: `deviceSecret`, `password` und `code` stehen in keinem
/// `toString` und in keiner Fehlermeldung dieses Pakets. Eingaben werden vor
/// dem Senden geprueft ([KasseneckValidationError], `kind: request`), ohne
/// ihren Wert zu nennen.
///
/// Aus der Antwort wird nichts erfunden: eine Kennung, die da sein muss, ist
/// sonst ein Antwortfehler (`kind: response`); ein fehlendes Nebenfeld ist
/// `null`. Zeiten kommen als ISO 8601 in UTC und werden zu [DateTime] (UTC);
/// eine unlesbare Zeit ist `null`.
library;

import '../lager/lesen.dart' show antwortfehler, ganzzahlVon, objekt;
import '../register/fehler.dart' show KasseneckValidationError;

/// Stabile Fehlercodes der sieben Endpunkte (Katalog `genius` im Backend,
/// `GENIUS_FEHLERCODES`). Sie kommen als `KasseneckApiError.code` an.
const Set<String> terminalErrorCodes = {
  // Fuer diesen Betrieb ist kein Terminal eingerichtet.
  'terminal_not_enabled',
  // Nur in der Live-Umgebung (die Terminal-Konten sind echt); ein kr_test_-Schluessel nie.
  'terminal_test_environment',
  // deviceId oder deviceSecret falsch: bewusst dieselbe Antwort fuer beides.
  'terminal_device_unknown',
  'terminal_device_blocked',
  // Angaben zum Geraet unvollstaendig (Bezeichnung, Plattform, App, Meldung).
  'invalid_terminal_device',
  // Hoechstzahl der Geraete des Betriebs oder 10 Anmeldungen je Tag erreicht.
  'too_many_terminal_devices',
  // Die Terminal-ID gehoert nicht zu diesem Betrieb (auch: gibt es nicht).
  'terminal_not_in_business',
  // Der Code kommt nicht automatisch: das Konto liest kein Postfach, die App fragt ihn von Hand ab.
  'terminal_code_manual',
  'terminal_code_rate_limited',
  // Dem Geraet ist keine Terminal-ID zugeordnet: erst getTerminalAccess.
  'terminal_not_assigned',
  // Die Terminal-ID gehoert fest einem anderen Geraet.
  'terminal_fixed',
  // Dem Geraet ist eine Terminal-ID fest zugeordnet: Wechsel nur ueber den Support.
  'terminal_device_fixed',
  'server_error',
};

/// Plattformen eines Geraets (`platform`).
const Set<String> terminalPlatforms = {'android', 'ios'};

/// Werte von [TerminalCodeState.status] und der Antwort von
/// `requestTerminalCode`. `found` liefert den Code; auf Android genau einmal
/// (danach `delivered` ohne Code), auf iOS bleibt er bis [TerminalCodeState.validUntil]
/// lesbar (`delivered` mit Code).
const Set<String> terminalCodeStatuses = {'none', 'searching', 'found', 'delivered', 'unclear', 'no_code', 'expired'};

/// Werte von [TerminalSetup.state]: zugeordnet, wartet auf den Code, wird
/// eingerichtet, fertig, fehlgeschlagen.
const Set<String> terminalSetupStates = {'assigned', 'waiting_for_code', 'setting_up', 'ready', 'failed'};

/// Herkunft eines Codes ([TerminalCodeState.source]): aus dem Postfach oder vom Support eingetragen.
const Set<String> terminalCodeSources = {'mailbox', 'support'};

/// Grund von [TerminalAccessUnavailable.reason]: alle Terminal-IDs des Betriebs sind in Gebrauch.
const String terminalNoFreeTerminal = 'no_free_terminal';

/// Bezeichnungen, nach denen [parseTerminalCode] ohne Angabe sucht (wie die
/// Vorgabe im Backend).
const List<String> terminalCodeLabelsDefault = ['Autorisierungscode', 'Authorization code'];

/// Laenge eines Codes ohne Angabe (wie die Vorgabe im Backend).
const int terminalCodeLengthDefault = 6;

/// Antwort von `registerTerminalDevice`.
///
/// [deviceSecret] kommt **nur in dieser Antwort**: im sicheren Speicher des
/// Geraets ablegen (Keychain/Keystore), nie protokollieren, nie an einen
/// anderen Dienst senden. Ging die Antwort verloren, hilft nur eine neue
/// Anmeldung.
class TerminalDeviceRegistration {
  const TerminalDeviceRegistration({required this.deviceId, required this.deviceSecret});

  final String deviceId;
  final String deviceSecret;

  // Das Geheimnis nie in einem Protokoll: toString nennt nur die Kennung.
  @override
  String toString() => 'TerminalDeviceRegistration($deviceId)';
}

/// Stand der Einrichtung am Geraet (`setup`).
class TerminalSetup {
  const TerminalSetup({required this.state, this.since});

  /// Ein Wert aus [terminalSetupStates]; ein unbekannter bleibt, wie er kam.
  final String state;

  /// Seit wann der Stand gilt (UTC).
  final DateTime? since;

  @override
  String toString() => 'TerminalSetup($state)';
}

/// Wie ein Code aussieht (`codeFormat`), aus den Einstellungen des Backends:
/// die Eingabe fuer [parseTerminalCode].
class TerminalCodeFormat {
  const TerminalCodeFormat({required this.length, required this.labels});

  final int length;
  final List<String> labels;
}

/// Eine Terminal-ID des eigenen Betriebs, wenn keine frei ist
/// ([TerminalAccessUnavailable.terminals]); nie die eines fremden Betriebs.
class TerminalListEntry {
  const TerminalListEntry({required this.terminalId, this.name, this.lastUsedBy, this.lastUsedAt});

  final String terminalId;

  /// Name des Terminals beim Anbieter.
  final String? name;

  /// Bezeichnung des Geraets, das sie zuletzt nutzte.
  final String? lastUsedBy;
  final DateTime? lastUsedAt;
}

/// Antwort von `getTerminalAccess`: entweder der Zugang
/// ([TerminalAccessGranted]) oder die Liste der Terminal-IDs des Betriebs,
/// von denen keine frei ist ([TerminalAccessUnavailable]; eine davon mit
/// `claimTerminal` uebernehmen). Ein `switch` ohne `default` deckt beide.
sealed class TerminalAccess {
  const TerminalAccess();

  /// `available` am Draht.
  bool get available;
}

/// Der Zugang fuer dieses Geraet. [password] nie protokollieren und nur fuer
/// die Anmeldung in der Terminal-App verwenden.
final class TerminalAccessGranted extends TerminalAccess {
  const TerminalAccessGranted({
    required this.username,
    required this.password,
    required this.terminalId,
    required this.accountId,
    required this.autoCode,
    required this.codeFormat,
    required this.setup,
    this.terminalName,
    this.updatedAt,
  });

  @override
  bool get available => true;

  final String username;
  final String password;
  final String terminalId;
  final String? terminalName;

  /// Kennung des Terminal-Kontos bei Kasseneck.
  final String accountId;

  /// `true`: der Freigabecode kommt automatisch (`requestTerminalCode`, dann
  /// `getTerminalCode`). `false`: die App laesst ihn eintippen oder einfuegen
  /// ([parseTerminalCode]); `requestTerminalCode` antwortet dann
  /// `terminal_code_manual`. Nur ein echtes `true` am Draht zaehlt.
  final bool autoCode;
  final TerminalCodeFormat codeFormat;
  final TerminalSetup setup;

  /// Letzte Aenderung an Konto oder Zuordnung (UTC): spaeter als der
  /// gespeicherte Stand, dann neu anmelden.
  final DateTime? updatedAt;

  // Passwort nie in einem Protokoll.
  @override
  String toString() => 'TerminalAccessGranted($terminalId, ${setup.state})';
}

/// Keine Terminal-ID ist frei; [terminals] sind die des eigenen Betriebs.
final class TerminalAccessUnavailable extends TerminalAccess {
  const TerminalAccessUnavailable({required this.reason, required this.terminals});

  @override
  bool get available => false;

  /// Heute immer [terminalNoFreeTerminal]; ein anderer Wert bleibt, wie er kam.
  final String reason;
  final List<TerminalListEntry> terminals;

  @override
  String toString() => 'TerminalAccessUnavailable($reason, ${terminals.length})';
}

/// Antwort von `getTerminalCode`: Stand der Code-Anfrage und der Einrichtung.
class TerminalCodeState {
  const TerminalCodeState({required this.status, required this.setup, this.code, this.source, this.validUntil});

  /// Ein Wert aus [terminalCodeStatuses]; ein unbekannter bleibt, wie er kam.
  final String status;

  /// Der Freigabecode; nur bei `found` (und auf iOS bei `delivered`). Nie protokollieren.
  final String? code;

  /// `mailbox` oder `support` ([terminalCodeSources]).
  final String? source;

  /// Bis wann der Code gilt (UTC).
  final DateTime? validUntil;
  final TerminalSetup setup;

  // Code nie in einem Protokoll.
  @override
  String toString() => 'TerminalCodeState($status, ${setup.state})';
}

// ---- Code aus der Zwischenablage ---------------------------------------------

/// Der Code aus einem eingefuegten Text (Knopf „Einfuegen“) oder `null`.
///
/// Zwei Formen: nur der Code (Leerraum am Rand faellt weg), genau [length]
/// Zeichen aus `A-Z a-z 0-9`; oder ein kopierter Mail-Text, in dem der Code
/// direkt hinter einer der [labels] mit Doppelpunkt steht (beliebiger
/// Leerraum davor und danach, auch Zeilenumbrueche), genau [length] Zeichen,
/// danach kein Buchstabe und keine Ziffer. Der Doppelpunkt ist Pflicht: das
/// Wort steht auch im Fliesstext der Mail. Bezeichnungen ohne Ruecksicht auf
/// Gross-/Kleinschreibung, der Code bleibt, wie er dasteht. Nennt der Text
/// zwei verschiedene Codes, ist keiner sicher: `null`.
///
/// [length] und [labels] kommen aus [TerminalAccessGranted.codeFormat].
/// Zwilling von `codeAusEingabe` im Backend; dieselben Pruefaelle gelten
/// beiden (test/fixtures/terminal/genius-code-faelle.json).
String? parseTerminalCode(
  String text, {
  int length = terminalCodeLengthDefault,
  List<String> labels = terminalCodeLabelsDefault,
}) {
  // Ein Einfuegen-Knopf soll nie werfen; eine unsinnige Laenge findet nichts.
  if (length < 1) return null;
  final roh = text.trim();
  if (RegExp('^[A-Za-z0-9]{$length}\$').hasMatch(roh)) return roh;
  // Eine leere Bezeichnung trifft jedes „: Code“; das Backend laesst sie in
  // seinen Einstellungen ebenso weg.
  final bezeichnungen = [
    for (final l in labels)
      if (l.trim().isNotEmpty) RegExp.escape(l.trim()),
  ];
  if (bezeichnungen.isEmpty) return null;
  final muster = RegExp(
    '(?:${bezeichnungen.join('|')})\\s*:\\s*([A-Za-z0-9]{$length})(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  final codes = {for (final m in muster.allMatches(text)) m.group(1)!};
  return codes.length == 1 ? codes.single : null;
}

// ---- Eingaben (vor dem Senden) -----------------------------------------------

KasseneckValidationError _eingabefehler(String name, String grund) => KasseneckValidationError(name, grund, 'request');

final RegExp _steuerzeichen = RegExp('[\\x00-\\x1F\\x7F]');

/// Laenge einer Zeile, wie das Backend sie misst: Steuerzeichen als
/// Leerzeichen, Rand ohne Leerraum.
int _zeilenlaenge(String wert) => wert.replaceAll(_steuerzeichen, ' ').trim().length;

void _zeile(String name, String feld, String? wert, int max, {bool pflicht = false}) {
  if (wert == null) {
    if (pflicht) throw _eingabefehler(name, '$feld fehlt');
    return;
  }
  final n = _zeilenlaenge(wert);
  if (n < 1 || n > max) throw _eingabefehler(name, '$feld muss 1 bis $max Zeichen haben');
}

void _plattform(String name, String? wert, {bool pflicht = false}) {
  if (wert == null && !pflicht) return;
  if (!terminalPlatforms.contains(wert)) throw _eingabefehler(name, 'platform muss android oder ios sein');
}

/// Prueft die Eingaben von `registerTerminalDevice`.
void pruefeGeraetAnmeldung(
  String name, {
  required String label,
  required String platform,
  required String app,
  String? requestedBy,
}) {
  _zeile(name, 'label', label, 60, pflicht: true);
  _plattform(name, platform, pflicht: true);
  _zeile(name, 'app', app, 40, pflicht: true);
  _zeile(name, 'requestedBy', requestedBy, 80);
}

/// Prueft Kennung und Geheimnis eines Geraets (nur, dass sie da sind; ihr Wert
/// kommt in keiner Meldung vor).
void pruefeGeraet(String name, String deviceId, String deviceSecret) {
  if (deviceId.trim().isEmpty) throw _eingabefehler(name, 'deviceId fehlt oder ist leer');
  if (deviceSecret.trim().isEmpty) throw _eingabefehler(name, 'deviceSecret fehlt oder ist leer');
}

/// Prueft die freiwilligen Angaben von `getTerminalAccess` und `claimTerminal`.
void pruefeZugangAngaben(String name, {String? platform, String? app, String? label}) {
  _plattform(name, platform);
  _zeile(name, 'app', app, 40);
  _zeile(name, 'label', label, 60);
}

/// Prueft eine Terminal-ID (nicht leer).
void pruefeTerminalId(String name, String terminalId) {
  if (terminalId.trim().isEmpty) throw _eingabefehler(name, 'terminalId fehlt oder ist leer');
}

/// Prueft die Eingaben von `requestTerminalCode`.
void pruefeCodeAnfrage(String name, {required String platform, String? requestedBy}) {
  _plattform(name, platform, pflicht: true);
  _zeile(name, 'requestedBy', requestedBy, 80);
}

// ---- Lesen -------------------------------------------------------------------

String? _text(Object? w) => w is String && w.isNotEmpty ? w : null;

String _pflicht(String name, String feld, Object? w) =>
    _text(w) ?? (throw antwortfehler(name, 'Antwort ist unbrauchbar (data.$feld fehlt)'));

DateTime? _zeit(Object? w) {
  final t = _text(w);
  return t == null ? null : DateTime.tryParse(t)?.toUtc();
}

TerminalSetup _setup(String name, String pfad, Object? w) {
  final o = objekt(w) ?? (throw antwortfehler(name, 'Antwort ist unbrauchbar (data.$pfad ist kein Objekt)'));
  return TerminalSetup(state: _pflicht(name, '$pfad.state', o['state']), since: _zeit(o['since']));
}

/// Die Anmeldung aus `data` von `registerTerminalDevice`.
TerminalDeviceRegistration geraetAnmeldungAus(String name, Map<String, dynamic> d) => TerminalDeviceRegistration(
  deviceId: _pflicht(name, 'deviceId', d['deviceId']),
  deviceSecret: _pflicht(name, 'deviceSecret', d['deviceSecret']),
);

/// Der Zugang aus `data` von `getTerminalAccess` oder `claimTerminal`.
/// `available` muss ein Wahrheitswert sein: geraten waere hier entweder ein
/// Zugang ohne Passwort oder eine Liste, die es nicht gibt.
TerminalAccess terminalZugangAus(String name, Map<String, dynamic> d) {
  final verfuegbar = d['available'];
  if (verfuegbar is! bool) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.available fehlt)');
  if (!verfuegbar) {
    final liste = d['terminals'];
    return TerminalAccessUnavailable(
      reason: _pflicht(name, 'reason', d['reason']),
      terminals: List.unmodifiable([
        for (final e in (liste is List ? liste : const []))
          if (objekt(e) case final o?)
            if (_text(o['terminalId']) case final tid?)
              TerminalListEntry(
                terminalId: tid,
                name: _text(o['name']),
                lastUsedBy: _text(o['lastUsedBy']),
                lastUsedAt: _zeit(o['lastUsedAt']),
              ),
      ]),
    );
  }
  final format = objekt(d['codeFormat']) ?? (throw antwortfehler(name, 'Antwort ist unbrauchbar (data.codeFormat ist kein Objekt)'));
  final laenge = ganzzahlVon(format['length']);
  if (laenge == null || laenge < 1) throw antwortfehler(name, 'Antwort enthaelt keine ganze Zahl (data.codeFormat.length)');
  final bezeichnungen = format['labels'];
  return TerminalAccessGranted(
    username: _pflicht(name, 'username', d['username']),
    password: _pflicht(name, 'password', d['password']),
    terminalId: _pflicht(name, 'terminalId', d['terminalId']),
    terminalName: _text(d['terminalName']),
    accountId: _pflicht(name, 'accountId', d['accountId']),
    autoCode: d['autoCode'] == true,
    codeFormat: TerminalCodeFormat(
      length: laenge,
      labels: List.unmodifiable([
        for (final b in (bezeichnungen is List ? bezeichnungen : const []))
          ?_text(b),
      ]),
    ),
    setup: _setup(name, 'setup', d['setup']),
    updatedAt: _zeit(d['updatedAt']),
  );
}

/// Der Stand aus `data` von `requestTerminalCode`.
String codeAnfrageStatusAus(String name, Map<String, dynamic> d) => _pflicht(name, 'status', d['status']);

/// Der Stand aus `data` von `getTerminalCode`.
TerminalCodeState codeStandAus(String name, Map<String, dynamic> d) => TerminalCodeState(
  status: _pflicht(name, 'status', d['status']),
  code: _text(d['code']),
  source: _text(d['source']),
  validUntil: _zeit(d['validUntil']),
  setup: _setup(name, 'setup', d['setup']),
);
