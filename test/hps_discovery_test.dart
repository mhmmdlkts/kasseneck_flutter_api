import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/src/hobex_hps/discovery.dart';

/// Antwort eines echten Terminals auf `GET /api/terminals` -- gekuerzt auf die
/// Felder, an denen die Suche haengt.
const String _terminalListe = '[{"tid":"3600335","company":"Kreiseck",'
    '"active":true}]';

/// Antwort der gemessenen Firmware auf `GET /api/terminals/0/diagnosis` --
/// das zweite Erkennungsmerkmal, das ohne bekannte TID auskommt. Dasselbe
/// Merkmal benutzt kasseneck-connect.
const String _platzhalterStatus =
    '{"responseCode":"100108","responseText":"Invalid TID","tid":"0",'
    '"transactionId":"0"}';

/// Was die gemessene Firmware auf ALLES andere antwortet.
final http.Response _nichtImplementiert =
    http.Response('Endpoint not implemented', 404);

/// Netz mit wegabhaengigen Antworten: Schluessel ist `host` oder `host+pfad`.
http.Client _netz(Map<String, http.Response> antworten) {
  return MockClient((request) async {
    final antwort = antworten['${request.url.host}${request.url.path}'] ??
        antworten[request.url.host];
    if (antwort == null) {
      throw http.ClientException('kein Anschluss unter dieser Adresse');
    }
    return antwort;
  });
}

Future<bool> Function(String, int, Duration) _offen(Set<String> hosts) {
  return (host, port, timeout) async => hosts.contains(host);
}

void main() {
  group('Netzauswahl', () {
    test('rechnet das /24 zu einer Adresse aus', () {
      expect(subnetOf('192.168.0.187'), '192.168.0.0/24');
      // Unbrauchbares kommt unveraendert zurueck und kippt nichts.
      expect(subnetOf('kaputt'), 'kaputt');
    });

    test('zaehlt alle Adressen ausser der eigenen', () {
      final hosts = subnetHosts('192.168.0.187');
      expect(hosts.length, 253);
      expect(hosts.contains('192.168.0.187'), isFalse);
      expect(hosts.first, '192.168.0.1');
      expect(hosts.last, '192.168.0.254');
      expect(subnetHosts('kaputt'), isEmpty);
    });

    test('laesst Selbstvergabe-Adressen und Doppelnetze aus', () {
      final gewaehlt = selectScanInterfaces(const <LocalIpv4>[
        LocalIpv4(name: 'en0', address: '192.168.0.10'),
        // dasselbe /24 ueber eine zweite Schnittstelle -> nur einmal scannen
        LocalIpv4(name: 'en1', address: '192.168.0.11'),
        // Selbstvergabe: dort steht nie ein eingerichtetes Terminal
        LocalIpv4(name: 'en2', address: '169.254.3.4'),
        LocalIpv4(name: 'en3', address: '10.0.0.5'),
      ]);
      expect(gewaehlt.map((i) => i.address), <String>['192.168.0.10', '10.0.0.5']);
    });

    test('sucht hoechstens die erlaubte Zahl an Netzen ab', () {
      final viele = <LocalIpv4>[
        for (var i = 1; i <= 9; i++)
          LocalIpv4(name: 'en$i', address: '10.0.$i.2'),
      ];
      expect(selectScanInterfaces(viele).length, hpsMaxScanInterfaces);
      expect(selectScanInterfaces(viele, max: 2).length, 2);
    });
  });

  group('Suche', () {
    test('findet das Terminal und traegt seine TID gleich mit', () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.187'}),
        httpClient: _netz({'192.168.0.187': http.Response(_terminalListe, 200)}),
      );

      expect(ergebnis.found, hasLength(1));
      expect(ergebnis.first!.host, '192.168.0.187');
      expect(ergebnis.first!.port, hpsDefaultPort);
      expect(ergebnis.first!.tids, <String>['3600335']);
      expect(ergebnis.first!.baseUrl.toString(), 'http://192.168.0.187:8080');
      expect(ergebnis.scanned.single.subnet, '192.168.0.0/24');
      expect(ergebnis.scanned.single.hosts, 253);
    });

    test('ein offener Port allein ist KEIN Treffer', () async {
      // Genau der Grund fuer die zweite Stufe: auf 8080 lauscht in fremden
      // Netzen alles Moegliche. Hier antwortet eine Router-Oberflaeche.
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.1', '192.168.0.55'}),
        httpClient: _netz({
          '192.168.0.1': http.Response('<html>Router</html>', 200),
          '192.168.0.55': http.Response('{"nicht":"eine Liste"}', 200),
        }),
      );

      expect(ergebnis.found, isEmpty);
      // abgesucht wurde trotzdem -- der Bericht bleibt vollstaendig
      expect(ergebnis.scanned, hasLength(1));
    });

    test('ein Kandidat, der gar nicht antwortet, reisst die Suche nicht mit',
        () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        // .9 wirft beim Nachfragen, .187 ist das Terminal
        probe: _offen({'192.168.0.9', '192.168.0.187'}),
        httpClient: _netz({'192.168.0.187': http.Response(_terminalListe, 200)}),
      );

      expect(ergebnis.found.map((t) => t.host), <String>['192.168.0.187']);
    });

    test('sucht in mehreren Netzen und meldet jedes im Bericht', () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async => const <LocalIpv4>[
          LocalIpv4(name: 'en0', address: '192.168.0.10'),
          LocalIpv4(name: 'en1', address: '10.0.0.10'),
        ],
        probe: _offen({'10.0.0.7'}),
        httpClient: _netz({'10.0.0.7': http.Response(_terminalListe, 200)}),
      );

      expect(ergebnis.found.single.host, '10.0.0.7');
      expect(
        ergebnis.scanned.map((s) => s.subnet),
        <String>['192.168.0.0/24', '10.0.0.0/24'],
      );
    });

    test('ein Terminal ohne TID bleibt trotzdem ein Treffer', () async {
      // Es hat auf /api/terminals geantwortet -- das ist das Kriterium.
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.187'}),
        httpClient: _netz({'192.168.0.187': http.Response('[]', 200)}),
      );

      expect(ergebnis.found, hasLength(1));
      expect(ergebnis.first!.tids, isEmpty);
    });

    test('ohne brauchbares Netz wird gar nicht gescannt', () async {
      var geklopft = 0;
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '169.254.1.2')],
        probe: (host, port, timeout) async {
          geklopft++;
          return false;
        },
        httpClient: _netz(const {}),
      );

      expect(ergebnis.found, isEmpty);
      expect(ergebnis.scanned, isEmpty);
      expect(geklopft, 0);
    });

    test('ein abgelaufenes Budget beendet den Scan, der Bericht bleibt',
        () async {
      final ergebnis = await discoverHpsTerminals(
        budget: Duration.zero,
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: (host, port, timeout) async =>
            fail('bei abgelaufenem Budget darf nicht geklopft werden'),
        httpClient: _netz(const {}),
      );

      expect(ergebnis.found, isEmpty);
      // Das Netz steht im Bericht, obwohl es nicht abgesucht wurde -- sonst
      // sieht die Fehlersuche beim Kunden gar nichts.
      expect(ergebnis.scanned.single.subnet, '192.168.0.0/24');
    });

    test('findet ein Terminal, dessen Firmware /api/terminals gar nicht kennt',
        () async {
      // Der am 28.08.2026 gemessene Fall: /api/terminals antwortet 404
      // "Endpoint not implemented", der Zahlweg funktioniert trotzdem. Eine
      // Suche, die nur auf /api/terminals baut, findet dieses Geraet NICHT.
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.187'}),
        httpClient: _netz({
          '192.168.0.187/api/terminals': _nichtImplementiert,
          '192.168.0.187/api/terminals/0/diagnosis':
              http.Response(_platzhalterStatus, 200),
        }),
      );

      expect(ergebnis.found, hasLength(1));
      expect(ergebnis.first!.host, '192.168.0.187');
      // Ohne /api/terminals gibt es keine TIDs -- der Treffer bleibt trotzdem
      // ein Treffer, die Adresse ist das Gesuchte.
      expect(ergebnis.first!.tids, isEmpty);
    });

    test('eine 404-Wueste ohne HPS-Antwort ist kein Treffer', () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.42'}),
        httpClient: _netz({'192.168.0.42': _nichtImplementiert}),
      );

      expect(ergebnis.found, isEmpty);
    });

    test('ein fremdes JSON auf dem Diagnoseweg ist kein Treffer', () async {
      // Geprueft wird die Antwortform, nicht bloss "es kam JSON".
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.43', '192.168.0.44'}),
        httpClient: _netz({
          // kein responseCode
          '192.168.0.43': http.Response('{"tid":"0"}', 200),
          // responseCode da, aber die tid wird nicht zurueckgespiegelt
          '192.168.0.44':
              http.Response('{"responseCode":"0","tid":"9999"}', 200),
        }),
      );

      expect(ergebnis.found, isEmpty);
    });

    test('stopAtFirst hoert nach dem ersten Treffer auf zu suchen', () async {
      final ergebnis = await discoverHpsTerminals(
        stopAtFirst: true,
        interfaces: () async => const <LocalIpv4>[
          LocalIpv4(name: 'en0', address: '192.168.0.10'),
          LocalIpv4(name: 'en1', address: '10.0.0.10'),
        ],
        probe: _offen({'192.168.0.187', '10.0.0.7'}),
        httpClient: _netz({
          '192.168.0.187': http.Response(_terminalListe, 200),
          '10.0.0.7': http.Response(_terminalListe, 200),
        }),
      );

      expect(ergebnis.found, hasLength(1));
      expect(ergebnis.first!.host, '192.168.0.187');
      // Das zweite Netz wurde gar nicht erst angefasst -- und der Bericht
      // behauptet auch nicht, es waere abgesucht worden.
      expect(ergebnis.scanned.map((s) => s.subnet), <String>['192.168.0.0/24']);
    });

    test('ohne stopAtFirst werden alle Terminals gefunden', () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.187', '192.168.0.188'}),
        httpClient: _netz({
          '192.168.0.187': http.Response(_terminalListe, 200),
          '192.168.0.188': http.Response(_terminalListe, 200),
        }),
      );

      expect(ergebnis.found.map((t) => t.host),
          <String>['192.168.0.187', '192.168.0.188']);
    });

    test('nimmt die vollstaendigen Terminal-Angaben mit, nicht nur die TID',
        () async {
      final ergebnis = await discoverHpsTerminals(
        interfaces: () async =>
            const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: _offen({'192.168.0.187'}),
        httpClient: _netz({
          '192.168.0.187': http.Response(
            jsonEncode([
              {'tid': '3600335', 'company': 'Kreiseck', 'active': true},
              {'tid': '3600336', 'company': 'Kreiseck', 'active': false},
            ]),
            200,
          ),
        }),
      );

      final treffer = ergebnis.first!;
      expect(treffer.tids, <String>['3600335', '3600336']);
      expect(treffer.terminals.first.company, 'Kreiseck');
      expect(treffer.terminals.first.active, isTrue);
      expect(treffer.terminals.last.active, isFalse);
    });
  });
}
