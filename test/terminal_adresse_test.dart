import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// `reportMyTerminalAddress` (Zwilling von npm 1.39.0) und der Geräte-Schalter
/// `printerHint`: die Fälle des Vertrags-Exports durch den Client, dazu die
/// Prüfung vor dem Senden und die Form der Einstellung.

final _faelle =
    ((jsonDecode(
                  File(
                    'test/fixtures/vertrag/v3/antworten/kasse.json',
                  ).readAsStringSync(),
                )
                as Map<
                  String,
                  dynamic
                >)['endpoints']['reportMyTerminalAddress']['cases']
            as List)
        .cast<Map<String, dynamic>>();

Map<String, dynamic> _fall(String name) =>
    _faelle.firstWhere((f) => f['case'] == name);

const _geheimnis = 'EXAMPLE-GEHEIM-0123456789abcdef';

RegisterClient _client(Map<String, dynamic> fall, List<http.Request> log) =>
    RegisterClient(
      httpClient: MockClient((request) async {
        log.add(request);
        return http.Response.bytes(
          utf8.encode(jsonEncode(fall['response'])),
          fall['httpStatus'] as int,
          headers: {
            'content-type': 'application/json',
            for (final e
                in (fall['headers'] as Map).cast<String, String>().entries)
              e.key.toLowerCase(): e.value,
          },
        );
      }),
    );

Future<ReportedTerminalAddress> _melden(
  RegisterClient c, {
  String secret = _geheimnis,
  String tid = '0012345',
  String host = '192.168.1.60',
  int port = 8080,
}) => c.reportMyTerminalAddress(
  ownerUid: 'kw_betrieb1',
  deviceId: 'dev_pin',
  deviceSecret: secret,
  tid: tid,
  host: host,
  port: port,
);

void main() {
  group('reportMyTerminalAddress', () {
    test(
      'jeder Erfolgsfall sendet genau Ausweis, TID und Adresse und liest changed',
      () async {
        var gelaufen = 0;
        for (final fall in _faelle.where(
          (f) => f['response']['status'] == 'success',
        )) {
          final log = <http.Request>[];
          final p = (fall['params'] as Map).cast<String, dynamic>();
          final r = await _melden(
            _client(fall, log),
            secret: p['deviceSecret'],
            tid: p['tid'],
            host: p['host'],
            port: p['port'],
          );
          expect(
            r,
            ReportedTerminalAddress(
              changed: fall['response']['data']['changed'] as bool,
            ),
            reason: fall['case'],
          );
          expect(log, hasLength(1));
          expect(log.single.url.path, '/api/v3/reportMyTerminalAddress');
          expect(
            (jsonDecode(log.single.body) as Map)['params'],
            p,
            reason: fall['case'],
          );
          gelaufen++;
        }
        expect(gelaufen, greaterThanOrEqualTo(3));
      },
    );

    test('die drei Fachfehler kommen am Code an', () async {
      for (final (name, code) in [
        ('terminal_id_matches_not', 'terminal_id_mismatch'),
        ('address_invalid', 'invalid_terminal_address'),
        ('too_many_changes', 'too_many_changes'),
      ]) {
        await expectLater(
          _melden(_client(_fall(name), [])),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)),
          reason: name,
        );
        expect(
          isRegisterError(
            KasseneckApiError('reportMyTerminalAddress', 'x', code: code),
            code,
          ),
          isTrue,
          reason: code,
        );
      }
    });

    test(
      'Unbrauchbares wird vor dem Senden abgewiesen, ohne Wert in der Meldung',
      () async {
        final log = <http.Request>[];
        final c = _client(_fall('success_changed'), log);
        final falsche = <Future<Object?> Function()>[
          () => c.reportMyTerminalAddress(
            ownerUid: '',
            deviceId: 'dev_pin',
            deviceSecret: _geheimnis,
            tid: '0012345',
            host: '192.168.1.60',
            port: 8080,
          ),
          () => c.reportMyTerminalAddress(
            ownerUid: 'kw_betrieb1',
            deviceId: ' ',
            deviceSecret: _geheimnis,
            tid: '0012345',
            host: '192.168.1.60',
            port: 8080,
          ),
          () => c.reportMyTerminalAddress(
            ownerUid: 'kw_betrieb1',
            deviceId: 'dev_pin',
            deviceSecret: '',
            tid: '0012345',
            host: '192.168.1.60',
            port: 8080,
          ),
          () => _melden(c, tid: ''),
          () => _melden(c, host: ''),
          () => _melden(c, port: 0),
          () => _melden(c, port: 65536),
        ];
        for (final f in falsche) {
          await expectLater(
            f(),
            throwsA(
              isA<KasseneckValidationError>()
                  .having((e) => e.kind, 'kind', 'request')
                  .having(
                    (e) => e.toString(),
                    'text',
                    isNot(contains(_geheimnis)),
                  ),
            ),
          );
        }
        expect(log, isEmpty);
      },
    );

    test('eine Antwort ohne changed ist ein Antwortfehler', () async {
      final leer = {
        ..._fall('success_changed'),
        'response': {
          'status': 'success',
          'message': '',
          'data': <String, dynamic>{},
        },
      };
      await expectLater(
        _melden(_client(leer, [])),
        throwsA(
          isA<KasseneckValidationError>().having(
            (e) => e.kind,
            'kind',
            'response',
          ),
        ),
      );
    });
  });

  group('Geräte-Schalter printerHint', () {
    test(
      'optional ohne Standardwert: fehlt er, gilt an; nur ein Wahrheitswert wird gelesen',
      () {
        expect(posDeviceOptionalSwitches, ['printerHint']);
        expect(
          const PosDeviceSettings().toJson().containsKey('printerHint'),
          isFalse,
        );
        expect(PosDeviceSettings.fromJson(const {}).printerHint, isNull);
        expect(posPrinterHint(PosDeviceSettings.fromJson(const {})), isTrue);
        expect(posPrinterHint(null), isTrue);
        final aus = PosDeviceSettings.fromJson(const {'printerHint': false});
        expect(aus.printerHint, isFalse);
        expect(posPrinterHint(aus), isFalse);
        expect(aus.toJson()['printerHint'], isFalse);
        for (final fremd in [null, 'nein', 0, 'false']) {
          expect(
            PosDeviceSettings.fromJson({'printerHint': fremd}).printerHint,
            isNull,
            reason: '$fremd',
          );
        }
      },
    );

    test(
      'merge: bleibt beim Mischen, wird ersetzt oder mit null entfernt; Unsinn wirft',
      () {
        final d = PosDeviceSettings.fromJson(const {'printerHint': false});
        expect(d.merge(const {'touch': true}).printerHint, isFalse);
        expect(d.merge(const {'printerHint': true}).printerHint, isTrue);
        expect(d.merge(const {'printerHint': null}).printerHint, isNull);
        expect(
          () => d.merge(const {'printerHint': 'nein'}),
          throwsArgumentError,
        );
      },
    );

    test('schreiben: nur true/false gehen hinaus, nichts sonst', () async {
      final log = <http.Request>[];
      final antwort = {
        'httpStatus': 200,
        'headers': {'Kasseneck-Api-Version': 'v3'},
        'response': {
          'status': 'success',
          'message': '',
          'data': {
            'device': {'printerHint': false},
          },
        },
      };
      final c = PosSettingsClient(
        RegisterTransport(
          idToken: () async => 'id-token',
          sessionId: () async => 'sess-1',
          cashregisterId: 'KASSE1',
          httpClient: MockClient((request) async {
            log.add(request);
            return http.Response.bytes(
              utf8.encode(jsonEncode(antwort['response'])),
              200,
              headers: {
                'content-type': 'application/json',
                'kasseneck-api-version': 'v3',
              },
            );
          }),
        ),
        deviceId: 'dev_pin',
      );
      expect((await c.saveDevice({'printerHint': false})).printerHint, isFalse);
      expect((jsonDecode(log.single.body) as Map)['params']['device'], {
        'printerHint': false,
      });
      for (final falsch in [null, 'nein', 0]) {
        await expectLater(
          c.saveDevice({'printerHint': falsch}),
          throwsA(
            isA<KasseneckValidationError>().having(
              (e) => e.reason,
              'reason',
              contains('device.printerHint'),
            ),
          ),
        );
      }
      expect(log, hasLength(1));
    });
  });
}
