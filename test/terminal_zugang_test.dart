import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/src/v3.dart' show unknownOutcomeCalls;

/// Kartenterminal-Zugang zentral (nur `/v3`): die sieben Aufrufe gegen eine
/// Server-Attrappe und der Helfer fuer den Knopf „Einfuegen“. Die
/// Antwortformen folgen genius-core.js/genius-daten.js im Backend; alle
/// Kennungen, Zugangsdaten und Codes sind erfunden.
///
/// Die Pruefliste fuer [parseTerminalCode] ist eine Kopie aus dem Backend
/// (functions-kasse/test/unit/fixtures/genius-code-faelle.json, siehe
/// test/fixtures/terminal/README.md): der Vertrag mit
/// `genius-core.codeAusEingabe`. Nie hier anpassen, sondern dort und neu kopieren.

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};
const _deviceId = 'Lm4Qx9Rt2Vb7Nc5Kp8Zs';
const _secret = 'q7Wm2Xc9Vb4Nk8Lp3Rt6Yz1Hs5Jd0Fg2Ua9Ei4Oo7P';
const _tid = '12345678';
const _passwort = 'Erfunden-Passwort-42';
const _code = 'Xk7pQ2';

KasseneckApi _api(http.Client client, {Duration readTimeout = const Duration(seconds: 30)}) => KasseneckApi(
  apiKey: 'kr_live_Beispielschluessel0123456789',
  cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
  httpClient: client,
  readTimeout: readTimeout,
);

final _antwortfehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response'));
final _eingabefehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request'));

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

/// Eine Attrappe, die jede Anfrage festhaelt und mit [antwort] antwortet.
({http.Client client, List<http.Request> anfragen}) _netz(http.Response Function(http.Request r) antwort) {
  final anfragen = <http.Request>[];
  final client = MockClient((r) async {
    anfragen.add(r);
    return antwort(r);
  });
  return (client: client, anfragen: anfragen);
}

Map<String, dynamic> _zugang({Map<String, dynamic>? mehr}) => {
  'available': true,
  'username': 'livia@melisse-nails.example',
  'password': _passwort,
  'terminalId': _tid,
  'terminalName': 'Melisse Nails e.U.',
  'accountId': 'melisse-nails',
  'autoCode': true,
  'codeFormat': {
    'length': 6,
    'labels': ['Autorisierungscode', 'Authorization code'],
  },
  'setup': {'state': 'assigned', 'since': '2026-11-07T09:00:00.000Z'},
  'updatedAt': '2026-11-06T18:30:00.000Z',
  ...?mehr,
};

void main() {
  group('parseTerminalCode: Pruefaelle aus dem Backend', () {
    final datei =
        jsonDecode(File('test/fixtures/terminal/genius-code-faelle.json').readAsStringSync()) as Map<String, dynamic>;
    final standard = datei['standard'] as Map<String, dynamic>;
    final faelle = (datei['faelle'] as List).cast<Map<String, dynamic>>();

    test('die Vorgaben des Helfers sind die Vorgaben der Pruefliste', () {
      expect(terminalCodeLengthDefault, standard['laenge']);
      expect(terminalCodeLabelsDefault, (standard['bezeichnungen'] as List).cast<String>());
    });

    test('die Liste ist nicht leer und deckt Treffer wie Nicht-Treffer', () {
      expect(faelle.where((f) => f['erwartet'] != null), isNotEmpty);
      expect(faelle.where((f) => f['erwartet'] == null), isNotEmpty);
    });

    for (final fall in faelle) {
      test(fall['name'] as String, () {
        final laenge = (fall['laenge'] ?? standard['laenge']) as int;
        final bezeichnungen = ((fall['bezeichnungen'] ?? standard['bezeichnungen']) as List).cast<String>();
        expect(parseTerminalCode(fall['text'] as String, length: laenge, labels: bezeichnungen), fall['erwartet']);
        // Ohne Angaben gelten dieselben Vorgaben.
        if (fall['laenge'] == null && fall['bezeichnungen'] == null) {
          expect(parseTerminalCode(fall['text'] as String), fall['erwartet']);
        }
      });
    }
  });

  group('parseTerminalCode: Raender', () {
    test('Bezeichnung ohne Ruecksicht auf Gross-/Kleinschreibung, Code unveraendert', () {
      expect(parseTerminalCode('AUTORISIERUNGSCODE: Xk7pQ2'), _code);
      expect(parseTerminalCode('authorization CODE:\tXk7pQ2.'), _code);
    });

    test('Leerraum zwischen Bezeichnung und Doppelpunkt', () {
      expect(parseTerminalCode('Autorisierungscode :\r\n Xk7pQ2'), _code);
    });

    test('Code mitten im Wort zaehlt nicht: danach kein Buchstabe, keine Ziffer', () {
      expect(parseTerminalCode('Autorisierungscode: Xk7pQ2x'), isNull);
      expect(parseTerminalCode('Autorisierungscode: Xk7pQ2-'), _code);
    });

    test('Sonderzeichen der Bezeichnung sind woertlich', () {
      expect(parseTerminalCode('Code (neu): Xk7pQ2', labels: ['Code (neu)']), _code);
      expect(parseTerminalCode('Code neu: Xk7pQ2', labels: ['Code (neu)']), isNull);
      expect(parseTerminalCode('Codeneu: Xk7pQ2', labels: ['Code.neu']), isNull);
    });

    test('leere Bezeichnungen treffen nicht jedes „: Code“', () {
      expect(parseTerminalCode('Hinweis: Xk7pQ2', labels: ['', '  ']), isNull);
      expect(parseTerminalCode('  Xk7pQ2 ', labels: const []), _code);
    });

    test('eine unsinnige Laenge findet nichts und wirft nicht', () {
      expect(parseTerminalCode('', length: 0), isNull);
      expect(parseTerminalCode('Xk7pQ2', length: -1), isNull);
    });
  });

  group('registerTerminalDevice', () {
    test('sendet die Angaben und liest Kennung und Geheimnis', () async {
      final netz = _netz((_) => _erfolg({'deviceId': _deviceId, 'deviceSecret': _secret}));
      final r = await _api(netz.client).registerTerminalDevice(
        label: 'Handy Livia',
        platform: 'android',
        app: 'kasse/1.0.12',
        requestedBy: 'Livia Lindmayr',
      );
      expect(r.deviceId, _deviceId);
      expect(r.deviceSecret, _secret);
      final anfrage = netz.anfragen.single;
      expect(anfrage.url.toString(), 'https://api.kasseneck.at/v3/registerTerminalDevice');
      expect(anfrage.headers['Authorization'], 'Bearer kr_live_Beispielschluessel0123456789');
      expect(_params(anfrage), {
        'label': 'Handy Livia',
        'platform': 'android',
        'app': 'kasse/1.0.12',
        'requestedBy': 'Livia Lindmayr',
      });
    });

    test('ohne requestedBy geht das Feld nicht hinaus', () async {
      final netz = _netz((_) => _erfolg({'deviceId': _deviceId, 'deviceSecret': _secret}));
      await _api(netz.client).registerTerminalDevice(label: 'iPad', platform: 'ios', app: 'kasse/1.0.12');
      expect(_params(netz.anfragen.single), {'label': 'iPad', 'platform': 'ios', 'app': 'kasse/1.0.12'});
    });

    test('toString nennt das Geheimnis nie', () async {
      final r = const TerminalDeviceRegistration(deviceId: _deviceId, deviceSecret: _secret);
      expect(r.toString(), contains(_deviceId));
      expect(r.toString(), isNot(contains(_secret)));
    });

    test('prueft vor dem Senden: Bezeichnung, Plattform, App, requestedBy', () async {
      final netz = _netz((_) => _erfolg({}));
      final api = _api(netz.client);
      await expectLater(api.registerTerminalDevice(label: '  ', platform: 'android', app: 'kasse/1'), _eingabefehler);
      await expectLater(
        api.registerTerminalDevice(label: 'x' * 61, platform: 'android', app: 'kasse/1'),
        _eingabefehler,
      );
      // Steuerzeichen zaehlen wie beim Server als Leerraum.
      await expectLater(api.registerTerminalDevice(label: '\n\t', platform: 'android', app: 'kasse/1'), _eingabefehler);
      await expectLater(api.registerTerminalDevice(label: 'Handy', platform: 'web', app: 'kasse/1'), _eingabefehler);
      await expectLater(
        api.registerTerminalDevice(label: 'Handy', platform: 'Android', app: 'kasse/1'),
        _eingabefehler,
      );
      await expectLater(api.registerTerminalDevice(label: 'Handy', platform: 'ios', app: ''), _eingabefehler);
      await expectLater(api.registerTerminalDevice(label: 'Handy', platform: 'ios', app: 'a' * 41), _eingabefehler);
      await expectLater(
        api.registerTerminalDevice(label: 'Handy', platform: 'ios', app: 'kasse/1', requestedBy: 'r' * 81),
        _eingabefehler,
      );
      expect(netz.anfragen, isEmpty);
      // Die Grenzen selbst gehen hinaus.
      await expectLater(
        api.registerTerminalDevice(label: 'x' * 60, platform: 'ios', app: 'a' * 40, requestedBy: 'r' * 80),
        _antwortfehler,
      );
      expect(netz.anfragen, hasLength(1));
    });

    test('ohne Geheimnis ist die Antwort unbrauchbar', () async {
      final netz = _netz((_) => _erfolg({'deviceId': _deviceId}));
      await expectLater(
        _api(netz.client).registerTerminalDevice(label: 'Handy', platform: 'android', app: 'kasse/1'),
        _antwortfehler,
      );
    });

    test('Fachfehler kommt mit Code', () async {
      final netz = _netz((_) => _fehler('too_many_terminal_devices'));
      await expectLater(
        _api(netz.client).registerTerminalDevice(label: 'Handy', platform: 'android', app: 'kasse/1'),
        throwsA(
          isA<KasseneckApiError>()
              .having((e) => e.code, 'code', 'too_many_terminal_devices')
              .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected),
        ),
      );
    });
  });

  group('getTerminalAccess', () {
    test('Zugang: alle Felder gelesen, Zeiten als UTC', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      final z = await _api(netz.client).getTerminalAccess(
        deviceId: _deviceId,
        deviceSecret: _secret,
        platform: 'android',
        app: 'kasse/1.0.12',
        label: 'Handy Livia',
      );
      expect(z.available, isTrue);
      final g = z as TerminalAccessGranted;
      expect(g.username, 'livia@melisse-nails.example');
      expect(g.password, _passwort);
      expect(g.terminalId, _tid);
      expect(g.terminalName, 'Melisse Nails e.U.');
      expect(g.accountId, 'melisse-nails');
      expect(g.autoCode, isTrue);
      expect(g.codeFormat.length, 6);
      expect(g.codeFormat.labels, ['Autorisierungscode', 'Authorization code']);
      expect(g.setup.state, 'assigned');
      expect(g.setup.since, DateTime.utc(2026, 11, 7, 9));
      expect(g.updatedAt, DateTime.utc(2026, 11, 6, 18, 30));
      expect(g.updatedAt!.isUtc, isTrue);
      expect(_params(netz.anfragen.single), {
        'deviceId': _deviceId,
        'deviceSecret': _secret,
        'platform': 'android',
        'app': 'kasse/1.0.12',
        'label': 'Handy Livia',
      });
      expect(netz.anfragen.single.url.path, '/v3/getTerminalAccess');
    });

    test('ohne freiwillige Angaben gehen nur Kennung und Geheimnis hinaus', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      await _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret);
      expect(_params(netz.anfragen.single), {'deviceId': _deviceId, 'deviceSecret': _secret});
    });

    test('Nebenfelder fehlen: null, autoCode nur bei echtem true', () async {
      final roh = _zugang(mehr: {'terminalName': null, 'updatedAt': null, 'autoCode': 'true'});
      (roh['setup'] as Map).remove('since');
      final netz = _netz((_) => _erfolg(roh));
      final g =
          await _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret)
              as TerminalAccessGranted;
      expect(g.terminalName, isNull);
      expect(g.updatedAt, isNull);
      expect(g.setup.since, isNull);
      expect(g.autoCode, isFalse);
    });

    test('der Zugang ergibt mit parseTerminalCode den Code aus der Mail', () async {
      final netz = _netz(
        (_) => _erfolg(
          _zugang(
            mehr: {
              'codeFormat': {
                'length': 8,
                'labels': ['Freigabecode'],
              },
            },
          ),
        ),
      );
      final g =
          await _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret)
              as TerminalAccessGranted;
      expect(
        parseTerminalCode('Freigabecode:\nXk7pQ2ab', length: g.codeFormat.length, labels: g.codeFormat.labels),
        'Xk7pQ2ab',
      );
    });

    test('keine frei: Liste des Betriebs', () async {
      final netz = _netz(
        (_) => _erfolg({
          'available': false,
          'reason': 'no_free_terminal',
          'terminals': [
            {
              'terminalId': _tid,
              'name': 'Melisse Nails e.U.',
              'lastUsedBy': 'Handy Mirela',
              'lastUsedAt': '2026-11-06T15:00:00.000Z',
            },
            {'terminalId': '87654321', 'name': null, 'lastUsedBy': null, 'lastUsedAt': null},
            // Ohne Kennung nicht zuzuordnen: faellt weg.
            {'name': 'kaputt'},
            'kein Objekt',
          ],
        }),
      );
      final z = await _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret);
      expect(z.available, isFalse);
      switch (z) {
        case TerminalAccessGranted():
          fail('erwartet: keine frei');
        case TerminalAccessUnavailable(:final reason, :final terminals):
          expect(reason, terminalNoFreeTerminal);
          expect(terminals.map((t) => t.terminalId), [_tid, '87654321']);
          expect(terminals.first.name, 'Melisse Nails e.U.');
          expect(terminals.first.lastUsedBy, 'Handy Mirela');
          expect(terminals.first.lastUsedAt, DateTime.utc(2026, 11, 6, 15));
          expect(terminals.last.name, isNull);
          expect(terminals.last.lastUsedAt, isNull);
      }
    });

    test('toString nennt Passwort und Benutzer nie', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      final z = await _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret);
      expect(z.toString(), isNot(contains(_passwort)));
      expect(z.toString(), isNot(contains('livia@')));
      expect(z.toString(), contains(_tid));
    });

    test('Antwortfehler: available fehlt oder ist kein Wahrheitswert, Pflichtfeld fehlt', () async {
      for (final roh in <Map<String, dynamic>>[
        {..._zugang()}..remove('available'),
        _zugang(mehr: {'available': 'true'}),
        {..._zugang()}..remove('password'),
        {..._zugang()}..remove('username'),
        {..._zugang()}..remove('terminalId'),
        {..._zugang()}..remove('accountId'),
        {..._zugang()}..remove('codeFormat'),
        _zugang(
          mehr: {
            'codeFormat': {'length': '6', 'labels': <String>[]},
          },
        ),
        _zugang(mehr: {'setup': null}),
        _zugang(
          mehr: {
            'setup': {'since': null},
          },
        ),
        {'available': false, 'terminals': <Object>[]},
      ]) {
        final netz = _netz((_) => _erfolg(roh));
        await expectLater(
          _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret),
          _antwortfehler,
          reason: '$roh',
        );
      }
    });

    test('prueft vor dem Senden, ohne den Wert des Geheimnisses zu nennen', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      final api = _api(netz.client);
      await expectLater(api.getTerminalAccess(deviceId: ' ', deviceSecret: _secret), _eingabefehler);
      await expectLater(api.getTerminalAccess(deviceId: _deviceId, deviceSecret: ''), _eingabefehler);
      await expectLater(
        api.getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret, platform: 'web'),
        _eingabefehler,
      );
      await expectLater(api.getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret, app: ''), _eingabefehler);
      await expectLater(
        api.getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret, label: 'x' * 61),
        _eingabefehler,
      );
      try {
        await api.getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret, platform: 'web');
      } on KasseneckValidationError catch (e) {
        expect(e.toString(), isNot(contains(_secret)));
      }
      expect(netz.anfragen, isEmpty);
    });

    test('jeder Code des Katalogs kommt als KasseneckApiError mit Code, abgelehnt', () async {
      for (final code in terminalErrorCodes) {
        final netz = _netz((_) => _fehler(code));
        await expectLater(
          _api(netz.client).getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret),
          throwsA(
            isA<KasseneckApiError>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected),
          ),
          reason: code,
        );
      }
    });
  });

  test('terminalErrorCodes ist der Katalog des Backends', () {
    // GENIUS_FEHLERCODES in gemeinsam/api-vokabular-v3.js (Backend), gleiche Reihenfolge egal.
    expect(terminalErrorCodes, {
      'terminal_not_enabled',
      'terminal_test_environment',
      'terminal_device_unknown',
      'terminal_device_blocked',
      'invalid_terminal_device',
      'too_many_terminal_devices',
      'terminal_not_in_business',
      'terminal_code_manual',
      'terminal_code_rate_limited',
      'terminal_not_assigned',
      'terminal_fixed',
      'terminal_device_fixed',
      'server_error',
    });
  });

  test('terminalErrorCodes ist errorCodes.terminal des gezogenen Vertrags', () {
    final vertrag = jsonDecode(File('test/fixtures/vertrag/v3/v3-vokabular.json').readAsStringSync()) as Map<String, dynamic>;
    final liste = ((vertrag['errorCodes'] as Map)['terminal'] as List).cast<String>();
    expect(terminalErrorCodes, liste.toSet());
  });

  group('claimTerminal', () {
    test('sendet die Terminal-ID und liefert den Zugang', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      final g = await _api(
        netz.client,
      ).claimTerminal(deviceId: _deviceId, deviceSecret: _secret, terminalId: _tid, label: 'Handy Livia');
      expect(g.terminalId, _tid);
      expect(g.password, _passwort);
      expect(netz.anfragen.single.url.path, '/v3/claimTerminal');
      expect(_params(netz.anfragen.single), {
        'deviceId': _deviceId,
        'deviceSecret': _secret,
        'terminalId': _tid,
        'label': 'Handy Livia',
      });
    });

    test('eine Liste statt des Zugangs ist ein Antwortfehler', () async {
      final netz = _netz((_) => _erfolg({'available': false, 'reason': 'no_free_terminal', 'terminals': <Object>[]}));
      await expectLater(
        _api(netz.client).claimTerminal(deviceId: _deviceId, deviceSecret: _secret, terminalId: _tid),
        _antwortfehler,
      );
    });

    test('fremde Terminal-ID', () async {
      final netz = _netz((_) => _fehler('terminal_not_in_business'));
      await expectLater(
        _api(netz.client).claimTerminal(deviceId: _deviceId, deviceSecret: _secret, terminalId: '99999999'),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'terminal_not_in_business')),
      );
    });

    test('leere Terminal-ID geht nicht hinaus', () async {
      final netz = _netz((_) => _erfolg(_zugang()));
      await expectLater(
        _api(netz.client).claimTerminal(deviceId: _deviceId, deviceSecret: _secret, terminalId: ' '),
        _eingabefehler,
      );
      expect(netz.anfragen, isEmpty);
    });
  });

  group('requestTerminalCode', () {
    test('sendet die Plattform und liefert den Stand', () async {
      final netz = _netz((_) => _erfolg({'status': 'searching'}));
      final stand = await _api(
        netz.client,
      ).requestTerminalCode(deviceId: _deviceId, deviceSecret: _secret, platform: 'ios', requestedBy: 'Livia Lindmayr');
      expect(stand, 'searching');
      expect(terminalCodeStatuses, contains(stand));
      expect(_params(netz.anfragen.single), {
        'deviceId': _deviceId,
        'deviceSecret': _secret,
        'platform': 'ios',
        'requestedBy': 'Livia Lindmayr',
      });
    });

    test('ohne Stand unbrauchbar, Plattform Pflicht', () async {
      final netz = _netz((_) => _erfolg({}));
      final api = _api(netz.client);
      await expectLater(
        api.requestTerminalCode(deviceId: _deviceId, deviceSecret: _secret, platform: 'android'),
        _antwortfehler,
      );
      await expectLater(
        api.requestTerminalCode(deviceId: _deviceId, deviceSecret: _secret, platform: ''),
        _eingabefehler,
      );
      expect(netz.anfragen, hasLength(1));
    });

    test('Konto ohne Postfach: terminal_code_manual', () async {
      final netz = _netz((_) => _fehler('terminal_code_manual'));
      await expectLater(
        _api(netz.client).requestTerminalCode(deviceId: _deviceId, deviceSecret: _secret, platform: 'android'),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'terminal_code_manual')),
      );
    });
  });

  group('getTerminalCode', () {
    test('gefunden: Code, Herkunft, Gueltigkeit, Einrichtung', () async {
      final netz = _netz(
        (_) => _erfolg({
          'status': 'found',
          'code': _code,
          'source': 'mailbox',
          'validUntil': '2026-11-07T09:20:00.000Z',
          'setup': {'state': 'waiting_for_code', 'since': '2026-11-07T09:00:00.000Z'},
        }),
      );
      final s = await _api(netz.client).getTerminalCode(deviceId: _deviceId, deviceSecret: _secret);
      expect(s.status, 'found');
      expect(s.code, _code);
      expect(s.source, 'mailbox');
      expect(terminalCodeSources, contains(s.source));
      expect(s.validUntil, DateTime.utc(2026, 11, 7, 9, 20));
      expect(s.setup.state, 'waiting_for_code');
      expect(terminalSetupStates, contains(s.setup.state));
      expect(s.toString(), isNot(contains(_code)));
      expect(_params(netz.anfragen.single), {'deviceId': _deviceId, 'deviceSecret': _secret});
      expect(netz.anfragen.single.url.path, '/v3/getTerminalCode');
    });

    test('ohne Anfrage: none ohne Code', () async {
      final netz = _netz(
        (_) => _erfolg({
          'status': 'none',
          'setup': {'state': 'ready', 'since': null},
        }),
      );
      final s = await _api(netz.client).getTerminalCode(deviceId: _deviceId, deviceSecret: _secret);
      expect(s.status, 'none');
      expect(s.code, isNull);
      expect(s.source, isNull);
      expect(s.validUntil, isNull);
      expect(s.setup.state, 'ready');
    });

    test('unlesbare Gueltigkeit ist null, fehlender Stand ein Antwortfehler', () async {
      var netz = _netz(
        (_) => _erfolg({
          'status': 'delivered',
          'code': _code,
          'validUntil': 'morgen',
          'setup': {'state': 'setting_up'},
        }),
      );
      expect((await _api(netz.client).getTerminalCode(deviceId: _deviceId, deviceSecret: _secret)).validUntil, isNull);
      netz = _netz(
        (_) => _erfolg({
          'setup': {'state': 'ready'},
        }),
      );
      await expectLater(_api(netz.client).getTerminalCode(deviceId: _deviceId, deviceSecret: _secret), _antwortfehler);
      netz = _netz((_) => _erfolg({'status': 'none'}));
      await expectLater(_api(netz.client).getTerminalCode(deviceId: _deviceId, deviceSecret: _secret), _antwortfehler);
    });
  });

  group('reportTerminalLogin und reportTerminalReady', () {
    test('Login: Wahrheitswerte gehen als bool hinaus', () async {
      final netz = _netz((_) => _erfolg({}));
      await _api(netz.client).reportTerminalLogin(
        deviceId: _deviceId,
        deviceSecret: _secret,
        terminalId: _tid,
        success: true,
        newOnDevice: false,
      );
      expect(netz.anfragen.single.url.path, '/v3/reportTerminalLogin');
      expect(_params(netz.anfragen.single), {
        'deviceId': _deviceId,
        'deviceSecret': _secret,
        'terminalId': _tid,
        'success': true,
        'newOnDevice': false,
      });
    });

    test('Bereit: nur Kennung und Geheimnis', () async {
      final netz = _netz((_) => http.Response(jsonEncode({'status': 'success', 'message': ''}), 200, headers: _kopf));
      await _api(netz.client).reportTerminalReady(deviceId: _deviceId, deviceSecret: _secret);
      expect(netz.anfragen.single.url.path, '/v3/reportTerminalReady');
      expect(_params(netz.anfragen.single), {'deviceId': _deviceId, 'deviceSecret': _secret});
    });

    test('Fehler kommen mit Code', () async {
      var netz = _netz((_) => _fehler('terminal_not_assigned'));
      await expectLater(
        _api(netz.client).reportTerminalReady(deviceId: _deviceId, deviceSecret: _secret),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'terminal_not_assigned')),
      );
      netz = _netz((_) => _fehler('terminal_device_blocked'));
      await expectLater(
        _api(netz.client).reportTerminalLogin(
          deviceId: _deviceId,
          deviceSecret: _secret,
          terminalId: _tid,
          success: false,
          newOnDevice: false,
        ),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'terminal_device_blocked')),
      );
    });
  });

  // Wie npm 1.28.0: unklar nur nach Anmeldung (Geheimnis verloren) und
  // getTerminalCode (Code auf Android verbraucht); die uebrigen fuenf abgelehnt.
  const unklar = {'registerTerminalDevice', 'getTerminalCode'};

  for (final (art, client, grund) in [
    ('Zeitlimit', MockClient((_) => Completer<http.Response>().future), KasseneckHttpError.reasonTimeout),
    ('Netzfehler', MockClient((_) async => throw const SocketException('weg')), KasseneckHttpError.reasonNetwork),
  ]) {
    test('$art: Ausgang unklar genau bei registerTerminalDevice und getTerminalCode', () async {
      final api = _api(client, readTimeout: const Duration(milliseconds: 20));
      final aufrufe = <String, Future<Object?> Function()>{
        'registerTerminalDevice': () => api.registerTerminalDevice(label: 'Handy', platform: 'android', app: 'kasse/1'),
        'getTerminalAccess': () => api.getTerminalAccess(deviceId: _deviceId, deviceSecret: _secret),
        'claimTerminal': () => api.claimTerminal(deviceId: _deviceId, deviceSecret: _secret, terminalId: _tid),
        'requestTerminalCode': () =>
            api.requestTerminalCode(deviceId: _deviceId, deviceSecret: _secret, platform: 'android'),
        'getTerminalCode': () => api.getTerminalCode(deviceId: _deviceId, deviceSecret: _secret),
        'reportTerminalLogin': () => api.reportTerminalLogin(
          deviceId: _deviceId,
          deviceSecret: _secret,
          terminalId: _tid,
          success: true,
          newOnDevice: true,
        ),
        'reportTerminalReady': () => api.reportTerminalReady(deviceId: _deviceId, deviceSecret: _secret),
      };
      for (final MapEntry(key: name, value: los) in aufrufe.entries) {
        await expectLater(
          los(),
          throwsA(
            isA<KasseneckHttpError>()
                .having((e) => e.functionName, 'functionName', name)
                .having((e) => e.reason, 'reason', grund)
                .having(
                  (e) => e.outcome,
                  'outcome',
                  unklar.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected,
                ),
          ),
          reason: name,
        );
      }
      expect(aufrufe.keys, containsAll(unklar));
    });
  }

  test('unknownOutcomeCalls fuehrt von den sieben genau die zwei', () {
    expect(unknownOutcomeCalls.where((c) => c.contains('Terminal')).toSet(), {
      'registerTerminalDevice',
      'getTerminalCode',
    });
  });
}
