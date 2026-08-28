import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'terminal_info.dart';

/// Standard-Port der HPS-Schnittstelle am Terminal.
const int hpsDefaultPort = 8080;

/// Zeitbudget der ganzen Suche, ueber alle Netze zusammen.
const Duration hpsScanBudget = Duration(seconds: 18);

/// Zeitlimit je Adresse beim Abklopfen des Ports.
///
/// Bewusst weit ueber den Millisekunden, die eine wache Gegenstelle braucht:
/// das Terminal haengt im WLAN-Stromsparmodus und beantwortet das ERSTE Paket
/// erst nach dem Aufwachen (gemessen: 1-2 s SYN-Wiederholung, danach
/// Millisekunden). Mit einem knappen Limit ist ein schlafendes Terminal
/// unauffindbar.
const Duration hpsProbeTimeout = Duration(seconds: 2);

/// Zeitlimit fuer die Nachfrage `GET /api/terminals` je Kandidat.
///
/// Auf Port 8080 lauscht in fremden Netzen alles Moegliche -- Router-Oberflaechen,
/// Kameras, Entwicklungsserver. Erst diese Nachfrage macht aus einem offenen
/// Port ein hobex-Terminal.
const Duration hpsVerifyTimeout = Duration(seconds: 3);

/// Gleichzeitig offene Verbindungen beim Abklopfen. Hoeher quittiert das
/// Betriebssystem mit "too many open files".
const int hpsScanConcurrency = 64;

/// Hoechstzahl abgesuchter Netze.
const int hpsMaxScanInterfaces = 4;

/// Ein gefundenes Terminal: Adresse plus die Kennungen, die es selbst nennt.
class DiscoveredHpsTerminal {
  const DiscoveredHpsTerminal({
    required this.host,
    required this.port,
    required this.terminals,
  });

  final String host;
  final int port;

  /// Was `GET /api/terminals` geliefert hat. Die TIDs stehen darin -- der
  /// Aufrufer muss sie nicht mehr erfragen.
  final List<TerminalInfo> terminals;

  /// Die TIDs, in der Reihenfolge der Antwort. Leer, wenn das Geraet keine
  /// nennt (dann ist es trotzdem ein Treffer -- es hat geantwortet).
  List<String> get tids => <String>[
        for (final t in terminals)
          if (t.tid != null && t.tid!.isNotEmpty) t.tid!,
      ];

  Uri get baseUrl => Uri.parse('http://$host:$port');

  @override
  String toString() => 'DiscoveredHpsTerminal($host:$port, tids: $tids)';
}

/// Ein abgesuchtes Netz -- fuer die Anzeige in der Kasse und die Fehlersuche.
class ScannedHpsSubnet {
  const ScannedHpsSubnet({
    required this.interface,
    required this.subnet,
    required this.hosts,
  });

  final String interface;

  /// Netz in Schreibweise `192.168.0.0/24`.
  final String subnet;

  /// Zahl der eingeplanten Adressen. Bricht das Budget den Scan ab, wurden es
  /// weniger -- die Zahl sagt, wie gross das Netz ist, nicht wie weit man kam.
  final int hosts;

  @override
  String toString() => 'ScannedHpsSubnet($interface, $subnet, $hosts)';
}

/// Ergebnis der Suche: Treffer plus die abgesuchten Netze.
class HpsDiscoveryResult {
  const HpsDiscoveryResult({required this.found, required this.scanned});

  final List<DiscoveredHpsTerminal> found;
  final List<ScannedHpsSubnet> scanned;

  /// Der erste Treffer, oder `null`. Der uebliche Fall in einer Kasse: genau
  /// ein Terminal im Netz.
  DiscoveredHpsTerminal? get first => found.isEmpty ? null : found.first;

  @override
  String toString() =>
      'HpsDiscoveryResult(${found.length} gefunden, ${scanned.length} Netze)';
}

/// Eine IPv4-Adresse dieses Geraets auf einer Schnittstelle.
class LocalIpv4 {
  const LocalIpv4({required this.name, required this.address});

  final String name;
  final String address;

  @override
  String toString() => 'LocalIpv4($name, $address)';
}

/// Prueft, ob sich an [host]:[port] eine TCP-Verbindung aufbauen laesst.
typedef HpsTcpProbe = Future<bool> Function(
    String host, int port, Duration timeout);

/// Sucht hobex-HPS-Terminals im lokalen Netz.
///
/// Zwei Stufen, und die zweite ist die wesentliche: erst zaehlt ein
/// TCP-Scan die Adressen mit offenem [port] auf, dann fragt jede davon
/// `GET /api/terminals`. Nur wer darauf mit einer Terminal-Liste antwortet,
/// ist ein Treffer -- ein offener Port allein sagt nichts, auf 8080 lauscht in
/// fremden Netzen zu viel anderes.
///
/// Das Ergebnis traegt die TIDs gleich mit: mit [DiscoveredHpsTerminal.baseUrl]
/// und einer TID daraus laesst sich unmittelbar ein [HpsClient] bauen, ohne
/// eine zweite Runde ans Geraet.
///
/// **iOS ab 14 verlangt dafuer die Freigabe fuer das lokale Netz.** Ohne den
/// Eintrag `NSLocalNetworkUsageDescription` in der `Info.plist` laufen die
/// Verbindungen ins Leere, und die Suche meldet schlicht nichts gefunden --
/// ohne Fehler, der darauf hinweist. Wer diese Funktion einbaut, muss den
/// Eintrag setzen.
///
/// [budget] deckelt den ganzen Durchlauf. Laeuft es ab, hoeren die Arbeiter
/// auf; was bis dahin gefunden wurde, bleibt im Ergebnis -- ein Terminal, das
/// nach zwoelf Sekunden auftaucht, ist mehr wert als ein Abbruch mit leerer
/// Liste.
///
/// [stopAtFirst] bricht ab, sobald ein Terminal gefunden ist. In einer Kasse
/// mit genau einem Terminal ist das der Normalfall und spart die Haelfte bis
/// zwei Drittel der Wartezeit: gemessen 18,7 s ueber drei Netze gegenueber
/// rund 8 s, wenn nach dem Treffer im ersten Netz Schluss ist. Der Bericht
/// [HpsDiscoveryResult.scanned] fuehrt dann nur die tatsaechlich abgesuchten
/// Netze -- was er auch soll.
///
/// [interfaces], [probe] und [httpClient] sind Naehte fuer Tests; die echte
/// Suche braucht sie nicht.
Future<HpsDiscoveryResult> discoverHpsTerminals({
  int port = hpsDefaultPort,
  Duration budget = hpsScanBudget,
  Duration probeTimeout = hpsProbeTimeout,
  Duration verifyTimeout = hpsVerifyTimeout,
  int concurrency = hpsScanConcurrency,
  bool stopAtFirst = false,
  Future<List<LocalIpv4>> Function()? interfaces,
  HpsTcpProbe probe = hpsTcpReachable,
  http.Client? httpClient,
}) async {
  final clock = Stopwatch()..start();
  final netze = selectScanInterfaces(
    await (interfaces ?? listLocalIpv4)(),
  );
  final scanned = <ScannedHpsSubnet>[];
  final found = <DiscoveredHpsTerminal>[];

  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    for (final netz in netze) {
      if (stopAtFirst && found.isNotEmpty) break;
      final hosts = subnetHosts(netz.address);
      scanned.add(ScannedHpsSubnet(
        interface: netz.name,
        subnet: subnetOf(netz.address),
        hosts: hosts.length,
      ));
      if (clock.elapsed >= budget) continue;

      final offen = await _scanSubnet(
        hosts: hosts,
        port: port,
        timeout: probeTimeout,
        concurrency: concurrency,
        budget: budget - clock.elapsed,
        probe: probe,
      );

      for (final host in offen) {
        // Kein Budget-Abbruch hier: die Kandidatenliste ist kurz (ein offener
        // Port 8080 ist selten), und einen gefundenen Kandidaten ungeprueft
        // liegen zu lassen waere die teuerste Sparsamkeit -- er faellt dann
        // ganz aus dem Ergebnis.
        final infos = await _verify(
          client: client,
          host: host,
          port: port,
          timeout: verifyTimeout,
        );
        if (infos == null) continue;
        found.add(DiscoveredHpsTerminal(
          host: host,
          port: port,
          terminals: List<TerminalInfo>.unmodifiable(infos),
        ));
        if (stopAtFirst) break;
      }
    }
  } finally {
    if (ownsClient) client.close();
  }

  return HpsDiscoveryResult(
    found: List<DiscoveredHpsTerminal>.unmodifiable(found),
    scanned: List<ScannedHpsSubnet>.unmodifiable(scanned),
  );
}

/// Prueft, ob hinter einem offenen Port wirklich ein hobex-Terminal steckt.
/// `null`, wenn nicht -- aus welchem Grund auch immer.
///
/// **Zwei Merkmale, eines genuegt.** Das ist keine Vorsicht auf Verdacht,
/// sondern am 28.08.2026 erzwungen: die naheliegende Pruefung
/// `GET /api/terminals` antwortet auf der gemessenen Firmware mit
/// **404 "Endpoint not implemented"** -- ebenso wie `/api`, `/api/status`,
/// `/api/version` und sogar `/api/terminals/{tid}/status`. Eine Suche, die nur
/// darauf baut, findet ein voll funktionsfaehiges Terminal NICHT.
///
/// 1. `GET /api/terminals` -- liefert eine Liste, wenn die Firmware sie kennt.
///    Dann stehen die TIDs gleich mit im Ergebnis.
/// 2. `GET /api/v2/transactions/0/0` -- eine Statusabfrage mit
///    Platzhalter-Kennungen. Gemessen antwortet das Terminal mit HTTP 200 und
///    `{"responseCode":"100108","responseText":"Invalid TID","tid":"0", ...}`.
///    Der Aufruf braucht KEINE bekannte TID, veraendert nichts, und die
///    Antwortform ist eindeutig hobex.
///
/// Das zweite Merkmal ist das wichtigere, und zwar nicht nur als Rueckfall:
/// es prueft genau den Weg, ueber den spaeter das Geld laeuft. Ein Geraet, das
/// `/api/terminals` beantwortet, aber keine Transaktionen annimmt, waere ein
/// Treffer ohne Wert.
///
/// JEDE Ausnahme heisst hier "nein, kein Terminal", nie "Fehler": die
/// abgeklopften Adressen sind fremde Geraete, und was sie antworten, ist
/// unvorhersehbar. Eine Suche darf daran nicht scheitern.
Future<List<TerminalInfo>?> _verify({
  required http.Client client,
  required String host,
  required int port,
  required Duration timeout,
}) async {
  final liste = await _terminalListe(
    client: client,
    host: host,
    port: port,
    timeout: timeout,
  );
  if (liste != null) return liste;

  final erkannt = await _antwortetWieHps(
    client: client,
    host: host,
    port: port,
    timeout: timeout,
  );
  // Treffer ohne TIDs: die Adresse steht fest, die Kennung muss der Aufrufer
  // anders erfahren (Einrichtung, Belegkopf, Ruecksprache). Das ist ehrlicher,
  // als das Geraet zu verschweigen, nur weil es seine TIDs nicht herausgibt.
  return erkannt ? const <TerminalInfo>[] : null;
}

/// Merkmal 1: `GET /api/terminals`. `null`, wenn die Firmware es nicht kennt.
Future<List<TerminalInfo>?> _terminalListe({
  required http.Client client,
  required String host,
  required int port,
  required Duration timeout,
}) async {
  try {
    final response = await client
        .get(Uri.parse('http://$host:$port/api/terminals'))
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return null;
    final infos = <TerminalInfo>[];
    for (final entry in decoded) {
      if (entry is! Map) return null;
      infos.add(TerminalInfo.fromJson(Map<String, dynamic>.from(entry)));
    }
    // Eine leere Liste ist eine gueltige Antwort -- das Geraet hat geredet.
    return infos;
  } catch (_) {
    return null;
  }
}

/// Merkmal 2: eine Statusabfrage mit Platzhaltern, die jedes HPS-Terminal
/// beantwortet, ohne dass man seine TID kennt.
///
/// Verlangt wird die ANTWORTFORM, nicht ein bestimmter Code: ein JSON-Objekt
/// mit `responseCode`, das die uebergebene `tid` zurueckspiegelt. Auf einen
/// festen Code (gemessen `100108`) zu pruefen wuerde eine Firmware
/// aussperren, die Platzhalter anders quittiert.
Future<bool> _antwortetWieHps({
  required http.Client client,
  required String host,
  required int port,
  required Duration timeout,
}) async {
  try {
    final response = await client
        .get(Uri.parse('http://$host:$port/api/v2/transactions/0/0'))
        .timeout(timeout);
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return false;
    return decoded['responseCode'] is String && decoded['tid'] == '0';
  } catch (_) {
    return false;
  }
}

/// Klopft [hosts] auf einen offenen [port] ab und liefert die erreichbaren,
/// in der Reihenfolge von [hosts].
Future<List<String>> _scanSubnet({
  required List<String> hosts,
  required int port,
  required Duration timeout,
  required int concurrency,
  required Duration budget,
  required HpsTcpProbe probe,
}) async {
  final erreichbar = <String>{};
  final clock = Stopwatch()..start();
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (next >= hosts.length) return;
      if (clock.elapsed >= budget) return;
      final host = hosts[next++];
      if (await probe(host, port, timeout)) erreichbar.add(host);
    }
  }

  final arbeiter = concurrency < hosts.length ? concurrency : hosts.length;
  if (arbeiter <= 0) return const <String>[];
  await Future.wait(List<Future<void>>.generate(arbeiter, (_) => worker()));

  return hosts.where(erreichbar.contains).toList();
}

/// Prueft, ob sich an [host]:[port] eine TCP-Verbindung aufbauen laesst.
Future<bool> hpsTcpReachable(String host, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

/// Die IPv4-Adressen dieses Geraets, ohne Loopback.
Future<List<LocalIpv4>> listLocalIpv4() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  return <LocalIpv4>[
    for (final interface in interfaces)
      for (final address in interface.addresses)
        LocalIpv4(name: interface.name, address: address.address),
  ];
}

/// Waehlt aus, welche Netze abgeklopft werden.
///
/// Draussen bleiben die Selbstvergabe-Adressen (`169.254.x` -- dort steht nie
/// ein eingerichtetes Terminal) und unbrauchbare Adressen. Zwei
/// Schnittstellen im selben /24 ergeben einen Scan, und mehr als [max] Netze
/// werden nicht abgesucht.
///
/// Loopback wird hier bewusst NICHT aussortiert: [listLocalIpv4] liefert es
/// gar nicht erst, und so kann ein Test das Loopback-Netz einschieben und
/// gegen einen wirklich lauschenden Port scannen.
List<LocalIpv4> selectScanInterfaces(
  List<LocalIpv4> all, {
  int max = hpsMaxScanInterfaces,
}) {
  final chosen = <LocalIpv4>[];
  final seen = <String>{};
  for (final interface in all) {
    final address = interface.address;
    if (subnetHosts(address).isEmpty) continue;
    if (address.startsWith('169.254.')) continue;
    if (!seen.add(subnetOf(address))) continue;
    chosen.add(interface);
    if (chosen.length >= max) break;
  }
  return chosen;
}

/// Das /24 zu einer Adresse in Schreibweise `192.168.0.0/24`.
///
/// Eine unbrauchbare Adresse kommt unveraendert zurueck -- der Wert steht nur
/// im Bericht, er darf die Suche nicht kippen.
String subnetOf(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return address;
  return '${parts.take(3).join('.')}.0/24';
}

/// Alle Adressen des /24 zu [address], ohne die eigene.
List<String> subnetHosts(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return const <String>[];
  final prefix = parts.take(3).join('.');
  final own = int.tryParse(parts[3]);
  if (own == null) return const <String>[];

  final hosts = <String>[];
  for (var i = 1; i <= 254; i++) {
    if (i == own) continue;
    hosts.add('$prefix.$i');
  }
  return hosts;
}
