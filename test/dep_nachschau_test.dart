import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// DEP-Export fuer die Kassennachschau (nur `/v3`): die fuenf Aufrufe gegen
/// eine Server-Attrappe. Die Antwortformen folgen `exportNachAussen` und den
/// Endpunkten im Backend (dep-nachschau-endpoints.js, dep-link-endpoints.js).

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};
const _id = 'DEP-2026-10-30-0001';

KasseneckApi _api(http.Client client) => KasseneckApi(
  apiKey: 'kr_test_x',
  cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
  httpClient: client,
);

http.Response _erfolg(Map<String, dynamic> daten) =>
    http.Response(jsonEncode({'status': 'success', 'message': '', 'data': daten}), 200, headers: _kopf);

http.Response _fehler(String code) => http.Response(
  jsonEncode({
    'status': 'error',
    'message': 'Nicht moeglich.',
    'code': code,
    'data': {'code': code},
  }),
  200,
  headers: _kopf,
);

Map<String, dynamic> _params(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

Map<String, dynamic> _export(String status, {Map<String, dynamic>? mehr}) => {
  'exportId': _id,
  'status': status,
  'from': '2026-10-01',
  'to': '2026-10-31',
  'createdAt': '2026-10-30T09:00:00',
  'finishedAt': status == 'done' ? '2026-10-30T09:01:10' : null,
  'receiptCount': status == 'done' ? 3 : null,
  'counterFrom': status == 'done' ? 7 : null,
  'counterTo': status == 'done' ? 9 : null,
  'sha256': status == 'done' ? 'a' * 64 : null,
  'size': status == 'done' ? 2048 : null,
  'findings': status == 'done'
      ? {
          'receiptCount': 3,
          'counterFrom': 7,
          'counterTo': 9,
          'gaps': [
            {'from': 4, 'to': 5},
          ],
          'chainBreaks': [
            {'counter': 8, 'expected': 'abc', 'found': 'def'},
          ],
          'withoutCounter': ['r-1'],
          'withoutSignature': ['r-2', 'r-3'],
        }
      : null,
  'items': status == 'done' ? {'rowCount': 5, 'sha256': 'b' * 64, 'size': 120} : null,
  'handoverLinks': [
    {
      'linkId': 'L' * 20,
      'createdAt': '2026-10-30T09:05:00',
      'expiresAt': '2026-11-13T09:05:00',
      'revokedAt': null,
      'firstAccessAt': null,
      'accessCount': 0,
    },
  ],
  if (status == 'failed') 'error': 'export_failed',
  ...?mehr,
};

void main() {
  group('createDepExport', () {
    test('sendet nur die gesetzten Felder an /v3 und liest die Antwort', () async {
      final log = <http.Request>[];
      final api = _api(
        MockClient((r) async {
          log.add(r);
          return _erfolg({'exportId': _id, 'status': 'running', 'from': '2026-10-01', 'to': null});
        }),
      );
      final e = await api.createDepExport(from: '2026-10-01', requestId: 'anf-1');
      expect(log.single.url.toString(), 'https://api.kasseneck.at/v3/createDepExport');
      expect(log.single.headers['Authorization'], 'Bearer kr_test_x');
      expect(log.single.headers['cashregister-token'], isNotEmpty);
      expect(_params(log.single), {'from': '2026-10-01', 'requestId': 'anf-1'});
      expect(e.exportId, _id);
      expect(e.status, depExportRunning);
      expect(e.from, '2026-10-01');
      expect(e.to, isNull);
      expect(e.findings, isNull);
      expect(e.handoverLinks, isEmpty);

      await _api(
        MockClient((r) async {
          log.add(r);
          return _erfolg({'exportId': _id, 'status': 'running', 'from': null, 'to': null});
        }),
      ).createDepExport();
      expect(_params(log.last), isEmpty);
    });

    test('Fehlercodes des Servers kommen als KasseneckApiError', () async {
      for (final code in ['invalid_period', 'export_running', 'too_many_exports', 'validation']) {
        expect(depExportErrorCodes, contains(code));
        final api = _api(MockClient((_) async => _fehler(code)));
        await expectLater(api.createDepExport(), throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)));
      }
    });

    test('Antwort ohne Kennung oder Status ist ein Antwortfehler', () async {
      for (final daten in [
        {'status': 'running'},
        {'exportId': _id},
      ]) {
        final api = _api(MockClient((_) async => _erfolg(daten)));
        await expectLater(
          api.createDepExport(),
          throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
        );
      }
    });
  });

  group('getDepExport', () {
    test('liest Befund, Positionen und Links', () async {
      final log = <http.Request>[];
      final api = _api(
        MockClient((r) async {
          log.add(r);
          return _erfolg(_export('done'));
        }),
      );
      final e = await api.getDepExport(_id);
      expect(_params(log.single), {'exportId': _id});
      expect(e.isDone, isTrue);
      expect(e.receiptCount, 3);
      expect(e.counterFrom, 7);
      expect(e.counterTo, 9);
      expect(e.sha256, 'a' * 64);
      expect(e.size, 2048);
      expect(e.createdAt, '2026-10-30T09:00:00');
      final f = e.findings!;
      expect(f.gaps.single.from, 4);
      expect(f.gaps.single.to, 5);
      expect(f.chainBreaks.single.counter, 8);
      expect(f.chainBreaks.single.expected, 'abc');
      expect(f.chainBreaks.single.found, 'def');
      expect(f.withoutCounter, ['r-1']);
      expect(f.withoutSignature, ['r-2', 'r-3']);
      expect(f.isClean, isFalse);
      expect(e.items!.rowCount, 5);
      expect(e.items!.size, 120);
      expect(e.handoverLinks.single.accessCount, 0);
      expect(e.handoverLinks.single.revokedAt, isNull);
      expect(e.error, isNull);
    });

    test('fehlgeschlagen traegt den Code, fremde Zahlen werden null statt geraten', () async {
      final api = _api(MockClient((_) async => _erfolg(_export('failed', mehr: {'receiptCount': 2.5, 'size': 'x'}))));
      final e = await api.getDepExport(_id);
      expect(e.isFailed, isTrue);
      expect(e.error, 'export_failed');
      expect(e.receiptCount, isNull);
      expect(e.size, isNull);
    });

    test('export_not_found', () async {
      final api = _api(MockClient((_) async => _fehler('export_not_found')));
      await expectLater(
        api.getDepExport(_id),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'export_not_found')),
      );
    });
  });

  group('waitForDepExport', () {
    // Wartet in fake_async: die Pausen laufen auf der falschen Uhr, der Test
    // misst den Abstand der Abfragen.
    ({Future<DepExport> Function() lauf, List<int> zeiten}) wartend(
      FakeAsync zeit,
      List<String> staende, {
      Duration timeout = const Duration(minutes: 10),
    }) {
      final zeiten = <int>[];
      var n = 0;
      final api = _api(
        MockClient((r) async {
          zeiten.add(zeit.elapsed.inMilliseconds);
          final s = staende[n < staende.length ? n : staende.length - 1];
          n++;
          return _erfolg(_export(s));
        }),
      );
      return (lauf: () => api.waitForDepExport(_id, timeout: timeout), zeiten: zeiten);
    }

    test('Abstand 2 s, mal 1,5, hoechstens 15 s; fertig liefert den Export', () {
      fakeAsync((zeit) {
        final w = wartend(zeit, [...List.filled(9, 'running'), 'done']);
        DepExport? ergebnis;
        w.lauf().then((e) => ergebnis = e);
        zeit.elapse(const Duration(minutes: 2));
        expect(ergebnis?.isDone, isTrue);
        // 0, +2000, +3000, +4500, +6750, +10125, +15000 (Deckel), +15000 ...
        expect(w.zeiten, [0, 2000, 5000, 9500, 16250, 26375, 41375, 56375, 71375, 86375]);
      });
    });

    test('failed wirft DepExportFailedException mit dem Code', () {
      fakeAsync((zeit) {
        final w = wartend(zeit, ['running', 'failed']);
        Object? fehler;
        w.lauf().then(
          (_) {},
          onError: (Object e) {
            fehler = e;
          },
        );
        zeit.elapse(const Duration(seconds: 30));
        expect(fehler, isA<DepExportFailedException>().having((e) => e.error, 'error', 'export_failed'));
        expect((fehler as DepExportFailedException).exportId, _id);
      });
    });

    test('Zeitueberschreitung wirft DepExportTimeoutException, ohne weiter zu fragen', () {
      fakeAsync((zeit) {
        final w = wartend(zeit, ['running'], timeout: const Duration(seconds: 20));
        Object? fehler;
        w.lauf().then(
          (_) {},
          onError: (Object e) {
            fehler = e;
          },
        );
        zeit.elapse(const Duration(minutes: 5));
        expect(fehler, isA<DepExportTimeoutException>());
        // Letzte Abfrage genau zur Frist, danach nichts mehr.
        expect(w.zeiten.last, 20000);
        expect(zeit.pendingTimers, isEmpty);
      });
    });

    test('ein Fehler der Abfrage geht unveraendert durch', () async {
      final api = _api(MockClient((_) async => _fehler('export_not_found')));
      await expectLater(api.waitForDepExport(_id), throwsA(isA<KasseneckApiError>()));
    });
  });

  group('getDepExportFile', () {
    test('direkte Bytes mit Dateiname und Inhaltstyp aus den Kopfzeilen', () async {
      final log = <http.Request>[];
      final pdf = Uint8List.fromList([37, 80, 68, 70, 1, 2]);
      final api = _api(
        MockClient((r) async {
          log.add(r);
          return http.Response.bytes(
            pdf,
            200,
            headers: {
              'content-type': 'application/pdf',
              'content-disposition': 'attachment; filename="$_id.pdf"',
              'kasseneck-api-version': 'v3',
            },
          );
        }),
      );
      final d = await api.getDepExportFile(_id, 'protocol');
      expect(log.single.url.toString(), 'https://api.kasseneck.at/v3/getDepExportFile');
      expect(_params(log.single), {'exportId': _id, 'file': 'protocol'});
      expect(d.bytes, pdf);
      expect(d.fileName, '$_id.pdf');
      expect(d.contentType, 'application/pdf');
    });

    test('das DEP selbst ist JSON und wird nicht fuer eine Huelle gehalten', () async {
      final dep = utf8.encode(jsonEncode({'Belege-Gruppe': [], 'Signaturzertifikat': 'x'}));
      final api = _api(
        MockClient(
          (r) async => http.Response.bytes(
            dep,
            200,
            headers: {
              'content-type': 'application/json',
              'content-disposition': 'attachment; filename="$_id.json"',
              'kasseneck-api-version': 'v3',
            },
          ),
        ),
      );
      final d = await api.getDepExportFile(_id, 'dep');
      expect(d.bytes, dep);
      expect(d.fileName, '$_id.json');
    });

    test('ohne Content-Disposition ein Name aus Kennung und Art', () async {
      final api = _api(
        MockClient(
          (r) async => http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'application/zip', 'kasseneck-api-version': 'v3'},
          ),
        ),
      );
      expect((await api.getDepExportFile(_id, 'zip')).fileName, '$_id.zip');
      expect((await api.getDepExportFile(_id, 'items')).fileName, '${_id}_positionen.csv');
    });

    test('grosse Datei: folgt dem Link ohne Zugangsdaten und prueft Groesse und SHA-256', () async {
      final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
      final log = <http.Request>[];
      final api = _api(
        MockClient((r) async {
          log.add(r);
          if (r.url.host == 'speicher.example') return http.Response.bytes(bytes, 200);
          return _erfolg({
            'download': {
              'url': 'https://speicher.example/b/dep.zip?sig=abc',
              'expiresAt': '2026-10-30T09:20:00.000Z',
              'size': bytes.length,
              'sha256': sha256.convert(bytes).toString().toUpperCase(),
              'fileName': '../$_id.zip',
              'contentType': 'application/zip',
            },
          });
        }),
      );
      final d = await api.getDepExportFile(_id, 'zip');
      expect(d.bytes, bytes);
      expect(d.fileName, '$_id.zip', reason: 'nur der letzte Teil des Namens');
      expect(d.contentType, 'application/zip');
      expect(log, hasLength(2));
      expect(log[1].method, 'GET');
      expect(log[1].headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(log[1].headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')));
    });

    Future<DepExportFile> mitLink(Uint8List geliefert, {int? size, String? sha, int status = 200}) {
      final api = _api(
        MockClient((r) async {
          if (r.url.host == 'speicher.example') return http.Response.bytes(geliefert, status);
          return _erfolg({
            'download': {
              'url': 'https://speicher.example/x',
              'expiresAt': '2026-10-30T09:20:00.000Z',
              'size': size,
              'sha256': sha,
              'fileName': 'a.zip',
              'contentType': 'application/zip',
            },
          });
        }),
      );
      return api.getDepExportFile(_id, 'zip');
    }

    test('Pruefsummenabweichung wirft, statt verdorbene Bytes zu liefern', () async {
      final echt = Uint8List.fromList([1, 2, 3, 4]);
      final verdorben = Uint8List.fromList([1, 2, 3, 5]);
      await expectLater(
        mitLink(verdorben, size: 4, sha: sha256.convert(echt).toString()),
        throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('SHA-256'))),
      );
    });

    test('Groessenabweichung wirft', () async {
      final b = Uint8List.fromList([1, 2, 3, 4]);
      await expectLater(
        mitLink(b, size: 5, sha: sha256.convert(b).toString()),
        throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('Dateigroesse'))),
      );
    });

    test('ohne Angaben des Servers wird nichts geprueft, was nicht da ist', () async {
      final b = Uint8List.fromList([9, 9]);
      expect((await mitLink(b)).bytes, b);
    });

    test('Link mit HTTP-Fehler', () async {
      await expectLater(
        mitLink(Uint8List(0), status: 403),
        throwsA(isA<KasseneckHttpError>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('Link mit unbrauchbarer Adresse oder Pruefsumme ist ein Antwortfehler', () async {
      for (final dl in [
        {'url': 'ftp://x/y'},
        {'url': 'http://example.com/x'},
        {'url': 'https://speicher.example/x', 'sha256': 'zz'},
        <String, dynamic>{},
      ]) {
        final api = _api(MockClient((r) async => _erfolg({'download': dl})));
        await expectLater(api.getDepExportFile(_id, 'zip'), throwsA(isA<KasseneckValidationError>()));
      }
    });

    test('http ist nur fuer localhost und 127.0.0.1 erlaubt', () async {
      final b = Uint8List.fromList([7]);
      for (final host in ['127.0.0.1:9199', 'localhost:9199']) {
        final api = _api(
          MockClient((r) async {
            if (r.url.host != 'api.kasseneck.at') return http.Response.bytes(b, 200);
            return _erfolg({
              'download': {'url': 'http://$host/b/x?alt=media', 'fileName': 'a.zip'},
            });
          }),
        );
        expect((await api.getDepExportFile(_id, 'zip')).bytes, b);
      }
    });

    test('Fehlercodes: not_ready, file_not_available, invalid_file, export_failed', () async {
      for (final code in ['export_not_ready', 'file_not_available', 'invalid_file', 'export_failed']) {
        final api = _api(MockClient((_) async => _fehler(code)));
        await expectLater(
          api.getDepExportFile(_id, 'dep'),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)),
        );
      }
    });

    test('ein unbekannter file-Wert faellt vor dem Senden auf', () async {
      var gesendet = 0;
      final api = _api(
        MockClient((_) async {
          gesendet++;
          return _erfolg({});
        }),
      );
      await expectLater(
        api.getDepExportFile(_id, 'pdf'),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')),
      );
      expect(gesendet, 0);
    });
  });

  group('Pruefer-Links', () {
    test('createDepHandoverLink liefert Adresse, Code und Ablauf', () async {
      final log = <http.Request>[];
      final api = _api(
        MockClient((r) async {
          log.add(r);
          return _erfolg({
            'linkId': 'L' * 20,
            'url': 'https://check.kasseneck.at/dep#link=${'L' * 20}.tok',
            'code': '123456',
            'expiresAt': '2026-11-13T09:05:00.000Z',
          });
        }),
      );
      final l = await api.createDepHandoverLink(_id);
      expect(log.single.url.toString(), 'https://api.kasseneck.at/v3/createDepHandoverLink');
      expect(_params(log.single), {'exportId': _id});
      expect(l.linkId, 'L' * 20);
      expect(l.code, '123456');
      expect(l.url, startsWith('https://check.kasseneck.at/dep#link='));
      expect(l.expiresAt, '2026-11-13T09:05:00.000Z');
      expect(l.toString(), isNot(contains('123456')));
      expect(l.toString(), isNot(contains('tok')));
    });

    test('Antwort ohne Code ist ein Antwortfehler; too_many_links kommt mit Code', () async {
      await expectLater(
        _api(MockClient((_) async => _erfolg({'linkId': 'L', 'url': 'https://x/y'}))).createDepHandoverLink(_id),
        throwsA(isA<KasseneckValidationError>()),
      );
      await expectLater(
        _api(MockClient((_) async => _fehler('too_many_links'))).createDepHandoverLink(_id),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'too_many_links')),
      );
    });

    test('revokeDepHandoverLink', () async {
      final log = <http.Request>[];
      final api = _api(
        MockClient((r) async {
          log.add(r);
          return _erfolg({'linkId': 'L' * 20, 'revokedAt': '2026-10-30T10:00:00.000Z'});
        }),
      );
      final r = await api.revokeDepHandoverLink('L' * 20);
      expect(log.single.url.toString(), 'https://api.kasseneck.at/v3/revokeDepHandoverLink');
      expect(_params(log.single), {'linkId': 'L' * 20});
      expect(r.linkId, 'L' * 20);
      expect(r.revokedAt, '2026-10-30T10:00:00.000Z');
      await expectLater(
        _api(MockClient((_) async => _fehler('link_not_found'))).revokeDepHandoverLink('x'),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'link_not_found')),
      );
    });
  });

  test('Fehlercodes: alle Codes des Backend-Katalogs dep_nachschau sind bekannt', () {
    // docs/api/fehlercodes.json, Eintrag dep_nachschau.
    expect(depExportErrorCodes, {
      'validation',
      'invalid_period',
      'export_running',
      'too_many_exports',
      'export_not_found',
      'export_not_ready',
      'export_failed',
      'invalid_file',
      'file_not_available',
      'too_many_links',
      'link_not_found',
      'server_error',
    });
  });
}
