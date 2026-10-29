import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/services/logo_service.dart';

/// `getReceipts(start, end)` seit 11.7: dieselbe Rueckgabe wie bis 11.6
/// (`getReportV2`), geholt ueber `listReceipts` (`view: full`, `order: asc`,
/// Seiten ueber `nextCursor`). Zeitraeume ueber 31 Tage teilt das Paket in
/// aufeinanderfolgende Fenster von hoechstens 31 Kalendertagen (Wanduhr ohne
/// Zeitzone, `to` ausschliesslich, lueckenlos).
///
/// Die Attrappe ist ein kleiner Server: sie filtert ihren Bestand nach
/// `from <= timeStamp < to`, sortiert aufsteigend, blaettert in Seiten zu
/// [_seitengroesse] und prueft jede Anfrage gegen die Regeln des Backends
/// (31 Tage, Cursor nur mit demselben Fenster). So faellt eine falsche
/// Teilung als fehlender, doppelter oder abgewiesener Beleg auf und nicht nur
/// als anderer Parameter.
///
/// Rot-Proben (belegt am 28.10.2026, nicht behauptet), jeweils in
/// `receiptListWindows` (`lib/src/receipt/liste.dart`), danach zurueck -> gruen:
///   * Fenster 32 statt 31 Tage (`receiptListDaysMax + 1`) -> 6 rot: alle
///     fuenf Faelle „ueber mehr als 31 Tage“ und „Fehler im zweiten Fenster“
///     (die Pruefung vor dem Senden wirft, sonst stuenden Grenzen falsch).
///   * naechstes Fenster eine Sekunde nach der Grenze beginnen -> dieselben 6
///     rot („drei Fenster“: der Beleg genau auf der Grenze fehlt).
///   * letztes Fenster nicht auf `end` kuerzen (immer 31 Tage) -> 7 rot,
///     auch die Ein-Fenster-Faelle (`to` falsch, Belege nach `end` kaemen
///     dazu).

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};

/// Kleiner als jede `limit`, damit auch ein Fenster mehrere Seiten hat.
const _seitengroesse = 2;

final Map<String, dynamic> _bericht = () {
  final belege = jsonDecode(File('test/fixtures/vertrag/v3/antworten/belege.json').readAsStringSync()) as Map;
  final fall = (belege['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['name'] == 'report');
  return (fall['response'] as Map)['data'] as Map<String, dynamic>;
}();

/// Ein Standardbeleg des Vertragsfalls `report` als Vorlage.
final Map<String, dynamic> _vorlage =
    (_bericht['receipts'] as List).cast<Map<String, dynamic>>().firstWhere((b) => b['receiptType'] == 'standard');

/// `metadata` des Vertragsfalls (Bäckerei Kornblum, Felder unter `/v3`).
final Map<String, dynamic> _metadata = _bericht['metadata'] as Map<String, dynamic>;

Map<String, dynamic> _beleg(String id, String timeStamp) =>
    {...jsonDecode(jsonEncode(_vorlage)) as Map<String, dynamic>, 'receiptId': id, 'timeStamp': timeStamp};

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

http.Response _antwort(Map<String, dynamic> huelle) => http.Response(jsonEncode(huelle), 200, headers: _kopf);

http.Response _fehler(String code) =>
    _antwort({'status': 'error', 'message': 'Fehler', 'code': code, 'data': {'code': code}});

/// Der Server im Kleinen. [stoerung] darf fuer die n-te Anfrage (ab 1) eine
/// eigene Antwort liefern.
class _Server {
  _Server(this.bestand, {this.metadata = const {}, this.mitMetadata = true, this.stoerung});

  final List<Map<String, dynamic>> bestand;
  final Map<String, dynamic> metadata;
  final bool mitMetadata;
  final http.Response? Function(int n, Map<String, dynamic> params)? stoerung;
  final List<Map<String, dynamic>> anfragen = [];

  late final MockClient client = MockClient((r) async {
    expect(r.url.toString(), 'https://api.kasseneck.at/v3/listReceipts');
    final p = _params(r);
    anfragen.add(p);
    final gestoert = stoerung?.call(anfragen.length, p);
    if (gestoert != null) return gestoert;

    expect(p['view'], 'full');
    expect(p['order'], 'asc');
    final from = p['from'] as String;
    final to = p['to'] as String;
    // Wie das Backend: hoechstens 31 Kalendertage (Wanduhr ohne Zone).
    final vonTag = DateTime.parse('${from}Z');
    if (DateTime.parse('${to}Z').isAfter(vonTag.add(const Duration(days: 31)))) return _fehler('range_too_long');

    final treffer = [
      for (final b in bestand)
        if ((b['timeStamp'] as String).compareTo(from) >= 0 && (b['timeStamp'] as String).compareTo(to) < 0) b,
    ]..sort((a, b) => (a['timeStamp'] as String).compareTo(b['timeStamp'] as String));
    var ab = 0;
    final cursor = p['cursor'] as String?;
    if (cursor != null) {
      final [cFrom, cTo, cAb] = cursor.split('|');
      if (cFrom != from || cTo != to) return _fehler('invalid_cursor');
      ab = int.parse(cAb);
    }
    final seite = treffer.skip(ab).take(_seitengroesse).toList();
    final weiter = ab + seite.length < treffer.length;
    return _antwort({
      'status': 'success',
      'message': '',
      'data': {
        'receipts': seite,
        'hasMore': weiter,
        'nextCursor': weiter ? '$from|$to|${ab + seite.length}' : null,
        if (mitMetadata) 'metadata': metadata,
      },
    });
  });

  KasseneckApi get api => KasseneckApi(
        apiKey: 'kr_test_x',
        cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
        httpClient: client,
      );

  /// Die Fenster der Anfragen ohne Folgeseiten, in Reihenfolge.
  List<(String, String)> get fenster => [
        for (final p in anfragen)
          if (p['cursor'] == null) (p['from'] as String, p['to'] as String),
      ];
}

void main() {
  late http.Client vorherLogo;
  final logoAnfragen = <Uri>[];

  setUp(() {
    vorherLogo = LogoService.httpClient;
    logoAnfragen.clear();
    LogoService.clearCache();
    LogoService.httpClient = MockClient((r) async {
      logoAnfragen.add(r.url);
      return http.Response.bytes(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], 200);
    });
  });
  tearDown(() {
    LogoService.httpClient = vorherLogo;
    LogoService.clearCache();
  });

  group('getReceipts ueber listReceipts', () {
    test('ein Fenster, mehrere Seiten: Cursor weitergegeben, alle Belege aufsteigend, Parameter wie bisher formatiert',
        () async {
      final server = _Server([
        _beleg('KECK-1-ID-5', '2026-10-27T18:00:00'),
        _beleg('KECK-1-ID-2', '2026-10-27T08:00:00'),
        _beleg('KECK-1-ID-4', '2026-10-27T12:30:00'),
        _beleg('KECK-1-ID-3', '2026-10-27T09:15:00'),
        _beleg('KECK-1-ID-6', '2026-10-27T23:59:59'),
      ], metadata: _metadata);
      // Millisekunden fallen weg wie bei getReportV2 (`split('.').first`).
      final belege = await server.api.getReceipts(DateTime(2026, 10, 27, 0, 0, 0, 250), DateTime(2026, 10, 28));

      expect(belege.map((b) => b.receiptId), ['KECK-1-ID-2', 'KECK-1-ID-3', 'KECK-1-ID-4', 'KECK-1-ID-5', 'KECK-1-ID-6']);
      const fenster = {'from': '2026-10-27T00:00:00', 'to': '2026-10-28T00:00:00', 'limit': 500, 'order': 'asc', 'view': 'full'};
      expect(server.anfragen, [
        fenster,
        {...fenster, 'cursor': '2026-10-27T00:00:00|2026-10-28T00:00:00|2'},
        {...fenster, 'cursor': '2026-10-27T00:00:00|2026-10-28T00:00:00|4'},
      ]);
    });

    test('Kopfdaten am KasseneckReceipt aus metadata, Logo wird geladen', () async {
      final kopf = {
        ..._metadata,
        'logo_url': 'https://cdn.kasseneck.at/logo/kornblum.png',
        'footer3': 'Montag Ruhetag',
      };
      final server = _Server([
        _beleg('KECK-1-ID-2', '2026-10-27T08:00:00'),
        _beleg('KECK-1-ID-3', '2026-10-27T09:00:00'),
        _beleg('KECK-1-ID-4', '2026-10-27T10:00:00'),
      ], metadata: kopf);
      final belege = await server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 28));

      expect(belege, hasLength(3));
      for (final b in belege) {
        expect(b.companyName, 'Bäckerei Kornblum', reason: b.receiptId);
        expect(b.street, 'Hauptplatz 1');
        expect(b.zip, '1010');
        expect(b.city, 'Wien');
        expect(b.phone, '+43 1 234');
        expect(b.taxNumber, '91-123/4565');
        expect(b.vatId, 'ATU12345675');
        expect(b.footer1, 'Danke');
        expect(b.footer3, 'Montag Ruhetag');
        expect(b.thanksMessage, ['Bis bald']);
        expect(b.logoUrl, 'https://cdn.kasseneck.at/logo/kornblum.png');
        expect(b.hasMandatoryFields, isTrue);
      }
      // init() wie bisher: das Logo liegt nach getReceipts bereit, einmal geholt.
      expect(logoAnfragen, [Uri.parse('https://cdn.kasseneck.at/logo/kornblum.png')]);
      expect(LogoService.getLogoBytes('https://cdn.kasseneck.at/logo/kornblum.png'), isNotNull);
    });

    test('aelteres Backend ohne metadata: Belege ohne Kopf, kein Fehler', () async {
      final server = _Server([_beleg('KECK-1-ID-2', '2026-10-27T08:00:00')], mitMetadata: false);
      final belege = await server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 28));
      expect(belege.single.receiptId, 'KECK-1-ID-2');
      expect(belege.single.companyName, '');
      expect(belege.single.logoUrl, isNull);
      expect(logoAnfragen, isEmpty);
    });

    test('ein unlesbarer Beleg wird uebersprungen, wie bisher', () async {
      final server = _Server([], metadata: _metadata, stoerung: (n, p) => _antwort({
            'status': 'success',
            'message': '',
            'data': {
              'receipts': [_beleg('KECK-1-ID-2', '2026-10-27T08:00:00'), 'kein Beleg', _beleg('KECK-1-ID-3', '2026-10-27T09:00:00')],
              'hasMore': false,
              'nextCursor': null,
              'metadata': _metadata,
            },
          }));
      final belege = await server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 28));
      expect(belege.map((b) => b.receiptId), ['KECK-1-ID-2', 'KECK-1-ID-3']);
    });

    test('start gleich end: leer, ohne Netzweg', () async {
      final server = _Server([_beleg('KECK-1-ID-2', '2026-10-27T08:00:00')]);
      expect(await server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 27)), isEmpty);
      expect(server.anfragen, isEmpty);
    });

    test('UTC-DateTime: die Felder als Wanduhr, ohne Z und ohne Umrechnung (wie bisher)', () async {
      final server = _Server([]);
      await server.api.getReceipts(DateTime.utc(2026, 10, 27, 22), DateTime.utc(2026, 10, 28, 22));
      expect(server.fenster, [('2026-10-27T22:00:00', '2026-10-28T22:00:00')]);
    });
  });

  group('getReceipts ueber mehr als 31 Tage', () {
    test('drei Fenster: Grenzen lueckenlos, to ausschliesslich, jeder Beleg genau einmal und in Reihenfolge', () async {
      final server = _Server([
        _beleg('vorher', '2026-07-31T23:59:59'),
        _beleg('A1', '2026-08-01T00:00:00'),
        _beleg('A2', '2026-08-15T12:00:00'),
        _beleg('A3', '2026-08-31T23:59:59'),
        _beleg('B1', '2026-09-01T00:00:00'),
        _beleg('B2', '2026-09-20T10:00:00'),
        _beleg('B3', '2026-10-01T23:59:59'),
        _beleg('C1', '2026-10-02T00:00:00'),
        _beleg('C2', '2026-10-19T23:59:59'),
        _beleg('end', '2026-10-20T00:00:00'),
      ], metadata: _metadata);
      final belege = await server.api.getReceipts(DateTime(2026, 8, 1), DateTime(2026, 10, 20));

      expect(server.fenster, [
        ('2026-08-01T00:00:00', '2026-09-01T00:00:00'),
        ('2026-09-01T00:00:00', '2026-10-02T00:00:00'),
        ('2026-10-02T00:00:00', '2026-10-20T00:00:00'),
      ]);
      expect(belege.map((b) => b.receiptId), ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2']);
      expect(belege.map((b) => b.companyName).toSet(), {'Bäckerei Kornblum'});
      // Fenster 1 und 2 haben je drei Belege: zwei Seiten, also fuenf Anfragen.
      expect(server.anfragen, hasLength(5));
    });

    test('zwei Fenster mit Uhrzeit: die Grenze behaelt die Uhrzeit von start', () async {
      final server = _Server([
        _beleg('A', '2026-10-31T08:29:59'),
        _beleg('B', '2026-11-01T08:30:00'),
        _beleg('C', '2026-11-15T08:29:59'),
      ]);
      final belege = await server.api.getReceipts(DateTime(2026, 10, 1, 8, 30), DateTime(2026, 11, 15, 8, 30));
      expect(server.fenster, [
        ('2026-10-01T08:30:00', '2026-11-01T08:30:00'),
        ('2026-11-01T08:30:00', '2026-11-15T08:30:00'),
      ]);
      expect(belege.map((b) => b.receiptId), ['A', 'B', 'C']);
    });

    test('ueber die Zeitumstellung: Kalendertage, nicht 31 x 24 Stunden', () async {
      // 25.10.2026 hat in Wien 25 Stunden; die Wanduhr der Grenze bleibt 00:00.
      final server = _Server([]);
      await server.api.getReceipts(DateTime(2026, 10, 10), DateTime(2026, 12, 1));
      expect(server.fenster, [
        ('2026-10-10T00:00:00', '2026-11-10T00:00:00'),
        ('2026-11-10T00:00:00', '2026-12-01T00:00:00'),
      ]);
    });

    test('genau 31 Tage ist ein Fenster, 31 Tage und eine Sekunde sind zwei', () async {
      final genau = _Server([]);
      await genau.api.getReceipts(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      expect(genau.fenster, [('2026-10-01T00:00:00', '2026-11-01T00:00:00')]);

      final drueber = _Server([]);
      await drueber.api.getReceipts(DateTime(2026, 10, 1), DateTime(2026, 11, 1, 0, 0, 1));
      expect(drueber.fenster, [
        ('2026-10-01T00:00:00', '2026-11-01T00:00:00'),
        ('2026-11-01T00:00:00', '2026-11-01T00:00:01'),
      ]);
    });

    test('ein Jahr: 12 Fenster, jedes hoechstens 31 Tage, aneinander anschliessend', () async {
      final server = _Server([]);
      await server.api.getReceipts(DateTime(2026, 1, 1), DateTime(2027, 1, 1));
      final f = server.fenster;
      expect(f.first.$1, '2026-01-01T00:00:00');
      expect(f.last.$2, '2027-01-01T00:00:00');
      for (var i = 1; i < f.length; i++) {
        expect(f[i].$1, f[i - 1].$2, reason: 'Fenster $i schliesst an');
      }
      expect(f, hasLength(12));
    });
  });

  group('getReceipts: Fehler mitten drin', () {
    test('Fehler im zweiten Fenster: geworfen, kein halbes Ergebnis, kein drittes Fenster', () async {
      final server = _Server([
        _beleg('A1', '2026-08-02T10:00:00'),
        _beleg('B1', '2026-09-02T10:00:00'),
        _beleg('C1', '2026-10-03T10:00:00'),
      ], stoerung: (n, p) => p['from'] == '2026-09-01T00:00:00' ? _fehler('server_error') : null);
      await expectLater(
        server.api.getReceipts(DateTime(2026, 8, 1), DateTime(2026, 10, 20)),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'server_error')),
      );
      expect(server.fenster, [
        ('2026-08-01T00:00:00', '2026-09-01T00:00:00'),
        ('2026-09-01T00:00:00', '2026-10-02T00:00:00'),
      ]);
    });

    test('Fehler auf der zweiten Seite eines Fensters: geworfen, keine weitere Anfrage', () async {
      final server = _Server([
        _beleg('A1', '2026-10-27T08:00:00'),
        _beleg('A2', '2026-10-27T09:00:00'),
        _beleg('A3', '2026-10-27T10:00:00'),
      ], stoerung: (n, p) => n == 2 ? _fehler('invalid_cursor') : null);
      await expectLater(
        server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 28)),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_cursor')),
      );
      expect(server.anfragen, hasLength(2));
    });

    test('kaputte Folgeseite (hasMore ohne Cursor): Antwortfehler statt still fehlender Belege', () async {
      final server = _Server([], stoerung: (n, p) => _antwort({
            'status': 'success',
            'message': '',
            'data': {'receipts': [_beleg('A1', '2026-10-27T08:00:00')], 'hasMore': true, 'nextCursor': null},
          }));
      await expectLater(
        server.api.getReceipts(DateTime(2026, 10, 27), DateTime(2026, 10, 28)),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
      );
    });
  });
}
