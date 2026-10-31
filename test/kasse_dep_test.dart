import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Pruefung (DEP) an der Kasse (seit 11.13, Zwilling von npm 1.21.0): die
/// fuenf Aufrufe ueber den Kassenweg an `RegisterReceiptClient` und der
/// Ordnername fuer den USB-Stick. Die Vertragsfaelle des Backends laufen in
/// `kasse_v3_test.dart`; hier, was der Export nicht zeigt: Pruefung vor dem
/// Senden, Warten, die Datei direkt und ueber den Lese-Link.

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};
const _id = 'DEP-2026-10-31-0001';

http.Response _erfolg(Map<String, dynamic> daten) =>
    http.Response(jsonEncode({'status': 'success', 'message': '', 'data': daten}), 200, headers: _kopf);

http.Response _fehler(String code) => http.Response(
      jsonEncode({'status': 'error', 'message': 'Nicht moeglich.', 'code': code, 'data': {'code': code}}),
      200,
      headers: _kopf,
    );

Map<String, dynamic> _export(String status) => {
      'exportId': _id,
      'status': status,
      'from': '2026-07-01',
      'to': '2026-09-30',
      'sha256': status == 'done' ? 'a' * 64 : null,
      'handoverLinks': const [],
      if (status == 'failed') 'error': 'export_stalled',
    };

RegisterReceiptClient _kasse(http.Client client) => RegisterReceiptClient(RegisterTransport(
      idToken: () async => 'id-token-chef',
      sessionId: () async => 'sitzung-1',
      cashregisterId: 'KECK-1',
      httpClient: client,
    ));

Map<String, dynamic> _params(http.BaseRequest r) =>
    (jsonDecode((r as http.Request).body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final _eingabefehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request'));

void main() {
  group('depFolderName', () {
    final vertrag =
        jsonDecode(File('test/fixtures/vertrag/dep-folder-cases.json').readAsStringSync()) as Map<String, dynamic>;
    final faelle = (vertrag['cases'] as List).cast<Map<String, dynamic>>();

    test('jeder Fall des Vertrags (dep-folder-cases.json)', () {
      expect(faelle, hasLength(greaterThanOrEqualTo(8)));
      for (final f in faelle) {
        expect(
          depFolderName(f['cashregisterId'] as String, from: f['from'] as String?, to: f['to'] as String?),
          f['expected'],
          reason: f['name'] as String,
        );
      }
    });

    test('jedes Zeichen, das FAT32 oder exFAT nicht nimmt, wird _ (auch Steuerzeichen und Leerraum)', () {
      for (final z in ['\\', '/', ':', '*', '?', '"', '<', '>', '|', '\t', '\n', '\u0000', '\u007f', ' ', ' ']) {
        expect(depFolderName('A${z}B'), 'DEP_A_B_alles', reason: 'U+${z.codeUnitAt(0).toRadixString(16)}');
      }
      // Leerraum am Rand faellt weg statt zu _ zu werden, wie trim() in npm.
      expect(depFolderName('  KECK-1 ', from: ' 2026-07-01', to: '2026-07-31 '), 'DEP_KECK-1_2026-07-01_2026-07-31');
      expect(depFolderName('   '), 'DEP_Kasse_alles');
    });
  });

  group('Aufrufe am Kassenweg', () {
    test('createDepExport: Kassenbasis, Kassen-Anmeldung, Kasse der Sitzung, nur gesetzte Felder', () async {
      final log = <http.BaseRequest>[];
      final kasse = _kasse(MockClient((r) async {
        log.add(r);
        return _erfolg(_export('running'));
      }));
      final e = await kasse.createDepExport(from: '2026-07-01', to: '2026-09-30', requestId: 'nachschau-1');
      expect(e.status, depExportRunning);
      expect(log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/createDepExport');
      expect(log.single.headers['Authorization'], 'Bearer id-token-chef');
      expect(log.single.headers['register-session'], 'sitzung-1');
      expect(log.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')));
      expect(_params(log.single),
          {'cashregisterId': 'KECK-1', 'from': '2026-07-01', 'to': '2026-09-30', 'requestId': 'nachschau-1'});

      await kasse.createDepExport();
      expect(_params(log.last), {'cashregisterId': 'KECK-1'}, reason: 'ohne Zeitraum: alles seit Inbetriebnahme');
    });

    test('Eingaben werden vor dem Senden geprueft; es geht nichts hinaus', () async {
      var gesendet = 0;
      final kasse = _kasse(MockClient((_) async {
        gesendet++;
        return _erfolg(_export('running'));
      }));
      await expectLater(kasse.createDepExport(from: '2026-02-30'), _eingabefehler);
      await expectLater(kasse.createDepExport(from: '2026-09-30', to: '2026-07-01'), _eingabefehler);
      await expectLater(kasse.createDepExport(requestId: 'mit leerzeichen'), _eingabefehler);
      await expectLater(kasse.createDepExport(requestId: 'x' * 65), _eingabefehler);
      await expectLater(kasse.getDepExport(' '), _eingabefehler);
      await expectLater(kasse.waitForDepExport(''), _eingabefehler);
      await expectLater(kasse.waitForDepExport(_id, timeout: Duration.zero), _eingabefehler);
      await expectLater(kasse.getDepExportFile(_id, 'xml'), _eingabefehler);
      await expectLater(kasse.getDepExportFile(_id, 'dep', sha256: 'zz'), _eingabefehler);
      await expectLater(kasse.getDepExportFile(_id, 'dep', downloadTimeout: Duration.zero), _eingabefehler);
      await expectLater(kasse.createDepHandoverLink(''), _eingabefehler);
      await expectLater(kasse.revokeDepHandoverLink(''), _eingabefehler);
      expect(gesendet, 0);
    });

    test('Pruefer-Link anlegen und widerrufen; Adresse und Code nie in toString', () async {
      final log = <http.BaseRequest>[];
      final kasse = _kasse(MockClient((r) async {
        log.add(r);
        if (r.url.path.endsWith('createDepHandoverLink')) {
          return _erfolg({
            'linkId': 'kwLink0000000000000A',
            'url': 'https://check.kasseneck.at/d#geheim',
            'code': '012345',
            'expiresAt': '2026-11-14T08:00:00.000Z',
          });
        }
        return _erfolg({'linkId': 'kwLink0000000000000A', 'revokedAt': '2026-10-31T09:00:00.000Z'});
      }));
      final link = await kasse.createDepHandoverLink(_id);
      expect(link.code, '012345', reason: 'fuehrende Null bleibt');
      expect(link.toString(), isNot(anyOf(contains('geheim'), contains('012345'))));
      expect(_params(log.single), {'cashregisterId': 'KECK-1', 'exportId': _id});
      final w = await kasse.revokeDepHandoverLink(link.linkId);
      expect(w.revokedAt, '2026-10-31T09:00:00.000Z');
      expect(_params(log.last), {'cashregisterId': 'KECK-1', 'linkId': 'kwLink0000000000000A'});
    });

    test('manager_only kommt als KasseneckApiError, abgelehnt, mit dem Satz der Kasse', () async {
      final kasse = _kasse(MockClient((_) async => _fehler('manager_only')));
      for (final aufruf in <Future<Object?> Function()>[
        () => kasse.createDepExport(),
        () => kasse.getDepExport(_id),
        () => kasse.waitForDepExport(_id),
        () => kasse.getDepExportFile(_id, 'zip'),
        () => kasse.createDepHandoverLink(_id),
        () => kasse.revokeDepHandoverLink('kwLink0000000000000A'),
      ]) {
        await expectLater(
          aufruf(),
          throwsA(isA<KasseneckApiError>()
              .having((e) => e.code, 'code', 'manager_only')
              .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)),
        );
      }
      expect(messageText(findErrorRule(ErrorKind.api, code: 'manager_only').key!), startsWith('Den Export'));
    });
  });

  group('waitForDepExport am Kassenweg', () {
    test('Abstand 2 s, mal 1,5, hoechstens 15 s; fertig liefert den Export', () {
      fakeAsync((zeit) {
        final zeiten = <int>[];
        var n = 0;
        final staende = [...List.filled(7, 'running'), 'done'];
        final kasse = _kasse(MockClient((r) async {
          zeiten.add(zeit.elapsed.inMilliseconds);
          expect(r.url.path, endsWith('/getDepExport'));
          return _erfolg(_export(staende[n++]));
        }));
        DepExport? ergebnis;
        kasse.waitForDepExport(_id).then((e) => ergebnis = e);
        zeit.elapse(const Duration(minutes: 2));
        expect(ergebnis?.isDone, isTrue);
        expect(zeiten, [0, 2000, 5000, 9500, 16250, 26375, 41375, 56375]);
      });
    });

    test('failed wirft DepExportFailedException, die Frist DepExportTimeoutException', () {
      fakeAsync((zeit) {
        final kasse = _kasse(MockClient((_) async => _erfolg(_export('failed'))));
        Object? fehler;
        kasse.waitForDepExport(_id).then((_) {}, onError: (Object e) {
          fehler = e;
        });
        zeit.flushMicrotasks();
        expect(fehler, isA<DepExportFailedException>().having((e) => e.error, 'error', 'export_stalled'));

        final laeuft = _kasse(MockClient((_) async => _erfolg(_export('running'))));
        Object? frist;
        laeuft.waitForDepExport(_id, timeout: const Duration(seconds: 20)).then((_) {}, onError: (Object e) {
          frist = e;
        });
        zeit.elapse(const Duration(minutes: 1));
        expect(frist, isA<DepExportTimeoutException>().having((e) => e.exportId, 'exportId', _id));
        expect(zeit.pendingTimers, isEmpty);
      });
    });
  });

  group('getDepExportFile am Kassenweg', () {
    test('direkte Datei: Bytes, Name und Typ aus den Kopfzeilen; Pruefsumme auf Wunsch', () async {
      final dep = Uint8List.fromList(utf8.encode('{"Belege-Gruppe":[]}'));
      final kasse = _kasse(MockClient((r) async => http.Response.bytes(dep, 200, headers: {
            'content-type': 'application/json',
            'content-disposition': 'attachment; filename="$_id.json"',
            'kasseneck-api-version': 'v3',
          })));
      final d = await kasse.getDepExportFile(_id, 'dep', sha256: sha256.convert(dep).toString().toUpperCase());
      expect(d.bytes, dep);
      expect(d.fileName, '$_id.json');
      expect(d.contentType, 'application/json');
      await expectLater(
        kasse.getDepExportFile(_id, 'dep', sha256: 'c' * 64),
        throwsA(isA<KasseneckValidationError>()
            .having((e) => e.kind, 'kind', 'response')
            .having((e) => e.reason, 'reason', contains('SHA-256'))),
      );
    });

    test('grosse Datei: folgt dem Link ohne Anmeldung, prueft Groesse und SHA-256', () async {
      final bytes = Uint8List.fromList(List.generate(700, (i) => i % 251));
      final log = <http.BaseRequest>[];
      Future<DepExportFile> laden({required int size, required String sha}) => _kasse(MockClient((r) async {
            log.add(r);
            if (r.url.host == 'speicher.example') return http.Response.bytes(bytes, 200);
            return _erfolg({
              'download': {
                'url': 'https://speicher.example/b/dep.zip?sig=abc',
                'expiresAt': '2026-10-31T09:15:00.000Z',
                'size': size,
                'sha256': sha,
                'fileName': 'ordner/$_id.zip',
                'contentType': 'application/zip',
              },
            });
          })).getDepExportFile(_id, 'zip');

      final d = await laden(size: bytes.length, sha: sha256.convert(bytes).toString());
      expect(d.bytes, bytes);
      expect(d.fileName, '$_id.zip', reason: 'nur der letzte Teil des Namens');
      expect(log, hasLength(2));
      final link = log[1];
      expect(link.method, 'GET');
      final kopf = link.headers.keys.map((k) => k.toLowerCase()).toSet();
      for (final verboten in ['authorization', 'register-session', 'cashregister-token', 'kasseneck-api-version', 'kasseneck-client']) {
        expect(kopf, isNot(contains(verboten)), reason: 'der Speicherdienst bekommt kein $verboten');
      }

      await expectLater(laden(size: bytes.length, sha: 'b' * 64),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('SHA-256'))));
      await expectLater(laden(size: bytes.length + 1, sha: sha256.convert(bytes).toString()),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('Dateigroesse'))));
    });

    test('ein Link ausserhalb von https wird nicht geladen', () async {
      final log = <http.BaseRequest>[];
      final kasse = _kasse(MockClient((r) async {
        log.add(r);
        return _erfolg({
          'download': {'url': 'http://speicher.example/x', 'expiresAt': '2026-10-31T09:15:00.000Z'},
        });
      }));
      await expectLater(kasse.getDepExportFile(_id, 'zip'),
          throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')));
      expect(log, hasLength(1), reason: 'kein GET an die unsichere Adresse');
    });

    test('Fehlerhuelle mit Code: export_not_ready, file_not_available', () async {
      for (final code in ['export_not_ready', 'file_not_available']) {
        await expectLater(_kasse(MockClient((_) async => _fehler(code))).getDepExportFile(_id, 'items'),
            throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)));
      }
    });
  });
}
