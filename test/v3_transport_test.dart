import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/rechnung.dart' show RechnungTransport, RechnungApi, kRechnungBaseUrl;
import 'package:kasseneck_api/register.dart' show RegisterClient, RegisterTransport, kRegisterBaseUrl;
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/hobex_hps/discovery.dart';
import 'package:kasseneck_api/src/hobex_hps/hps_client.dart';
import 'package:kasseneck_api/src/v3.dart';

/// Der Transport spricht nur `/v3` und schliesst am Kennzeichen: jede Antwort
/// muss `Kasseneck-Api-Version: v3` tragen, sonst wird nichts gelesen und
/// nichts weiter getan (Zwilling von `test/transport-v3.test.ts` im
/// npm-Paket). Geprueft an allen vier Wegen des Pakets: Geraete-Client mit
/// api_key, Kopplung/Anmeldung, laufende Kassen-Sitzung, Rechnungs-API.

const _kennzeichen = {'kasseneck-api-version': 'v3'};
const _json = {'content-type': 'application/json'};

/// Eine vorbereitete Antwort. Der Rumpf wird nur ausgeliefert, wenn jemand ihn
/// liest; [gelesen] haelt fest, ob das geschah.
class _Antwort {
  _Antwort(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

class _Netz {
  _Netz(this.antwort);

  _Antwort Function(http.BaseRequest request) antwort;
  final List<http.BaseRequest> anfragen = [];
  bool gelesen = false;

  late final http.Client client = MockClient.streaming((request, _) async {
    anfragen.add(request);
    final a = antwort(request);
    late final StreamController<List<int>> strom;
    strom = StreamController<List<int>>(onListen: () {
      gelesen = true;
      strom.add(a.body);
      strom.close();
    });
    return http.StreamedResponse(strom.stream, a.status, headers: a.headers);
  });
}

_Antwort _v3(Object huelle, {int status = 200}) =>
    _Antwort(status, {..._json, ..._kennzeichen}, utf8.encode(jsonEncode(huelle)));

_Antwort _ohneKennzeichen() => _Antwort(200, _json, utf8.encode(jsonEncode({'status': 'success', 'data': {}})));

_Antwort _html({bool kennzeichen = false}) => _Antwort(
    200, {'content-type': 'text/html; charset=utf-8', if (kennzeichen) ..._kennzeichen}, utf8.encode('<html></html>'));

final _posten = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 100);

/// Ein Weg des Pakets: wie er gebaut wird und welche Aufrufe er absetzt.
class _Weg {
  const _Weg(this.name, this.basis, this.aufrufe);
  final String name;
  final String basis;

  /// Aufrufname -> Ausloeser gegen das gegebene Netz.
  final Map<String, Future<Object?> Function(http.Client client)> aufrufe;
}

KasseneckApi _geraet(http.Client c) =>
    KasseneckApi(apiKey: 'k', cashregisterToken: base64Encode(utf8.encode('C:s')), httpClient: c);

RegisterTransport _sitzung(http.Client c, {String? baseUrl, String? clientHeader, bool omit = false}) =>
    RegisterTransport(
      idToken: () async => 'tok',
      sessionId: () async => 'sess',
      cashregisterId: 'K1',
      httpClient: c,
      baseUrl: baseUrl,
      clientHeader: clientHeader,
      omitKasseneckHeaders: omit,
    );

final _wege = <_Weg>[
  _Weg('KasseneckApi (api_key)', 'https://api.kasseneck.at/v3', {
    'createReceipt': (c) => _geraet(c).sellReceipt(payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 100)], items: [_posten]),
    'getReceipt': (c) => _geraet(c).getReceipt('R1'),
    'financeWebService': (c) => _geraet(c).getCashboxStatus(),
    'cancelReceipt': (c) =>
        _geraet(c).stornieren(cashregisterId: 'K1', originalReceiptId: 'R1', grund: 'input_error'),
    'sendReceiptEmail': (c) => _geraet(c).belegSenden(fullReceiptId: 'F1', an: 'a@b.at'),
    'hobexPayApi': (c) => _geraet(c).hobexPay(transactionId: '1', amount: 1),
    'hobexRefundApi': (c) => _geraet(c).hobexRefund(transactionId: '1', amount: 1),
    'stripeCaptureIntent': (c) => _geraet(c).stripeCaptureIntent(stripeSessionId: 's1'),
  }),
  _Weg('RegisterClient (Kopplung)', 'https://kasse.kasseneck.at/api/v3', {
    'pairRegisterDevice': (c) => RegisterClient(httpClient: c).pairRegisterDevice(code: 'ABC123'),
  }),
  _Weg('RegisterTransport (Sitzung)', 'https://kasse.kasseneck.at/api/v3', {
    'createReceipt': (c) => _sitzung(c).rufen('createReceipt'),
    'cancelReceipt': (c) => _sitzung(c).rufen('cancelReceipt'),
    'listMyReceipts': (c) => _sitzung(c).rufen('listMyReceipts'),
  }),
  _Weg('RechnungTransport', 'https://api.kasseneck.at/v3', {
    'getInvoice': (c) => RechnungTransport(apiKey: 'kr_test_x', httpClient: c).rufen('getInvoice', {}),
    'getInvoicePdf': (c) => RechnungTransport(apiKey: 'kr_test_x', httpClient: c).rufenBinaer('getInvoicePdf', {}),
  }),
];

/// Aufrufe mit unklarem Ausgang nach dem Senden: signierend, FinanzOnline,
/// und die Geldwege (Kartenbelastung, Erstattung, Stripe-Einzug).
/// Derselbe Aufruf wie in [_wege], aber mit kurzer Frist.
Future<Object?> _mitFrist(_Weg weg, String name, http.Client c) {
  const f = Duration(milliseconds: 20);
  final geraet = KasseneckApi(
      apiKey: 'k',
      cashregisterToken: base64Encode(utf8.encode('C:s')),
      httpClient: c,
      readTimeout: f,
      cardTimeout: f,
      signatureTimeout: f);
  switch (weg.name) {
    case 'KasseneckApi (api_key)':
      return switch (name) {
        'createReceipt' => geraet.sellReceipt(payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 100)], items: [_posten]),
        'getReceipt' => geraet.getReceipt('R1'),
        'financeWebService' => geraet.getCashboxStatus(),
        'cancelReceipt' => geraet.stornieren(cashregisterId: 'K1', originalReceiptId: 'R1', grund: 'input_error'),
        'sendReceiptEmail' => geraet.belegSenden(fullReceiptId: 'F1', an: 'a@b.at'),
        'hobexPayApi' => geraet.hobexPay(transactionId: '1', amount: 1),
        'hobexRefundApi' => geraet.hobexRefund(transactionId: '1', amount: 1),
        'stripeCaptureIntent' => geraet.stripeCaptureIntent(stripeSessionId: 's1'),
        _ => throw StateError(name),
      };
    case 'RegisterClient (Kopplung)':
      return RegisterClient(httpClient: c, timeout: f).pairRegisterDevice(code: 'ABC123');
    case 'RegisterTransport (Sitzung)':
      return RegisterTransport(
              idToken: () async => 't', sessionId: () async => 's', cashregisterId: 'K', httpClient: c, timeout: f)
          .rufen(name);
    default:
      final t = RechnungTransport(apiKey: 'kr_test_x', httpClient: c, timeout: f);
      return name == 'getInvoicePdf' ? t.rufenBinaer(name, {}) : t.rufen(name, {});
  }
}

const _signierend = {
  'createReceipt',
  'cancelReceipt',
  'financeWebService',
  'hobexPayApi',
  'hobexRefundApi',
  'stripeCaptureIntent',
};

TypeMatcher<KasseneckApiError> _apiFehler(String code, ErrorOutcome ausgang) => isA<KasseneckApiError>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.outcome, 'outcome', ausgang);

TypeMatcher<KasseneckHttpError> _httpFehler(String grund, ErrorOutcome ausgang) => isA<KasseneckHttpError>()
    .having((e) => e.reason, 'reason', grund)
    .having((e) => e.outcome, 'outcome', ausgang);

/// Bindet der Quelltext `v3.dart` ein, in jeder Form (`show`, `as`,
/// doppelte Anfuehrungszeichen, `export`)?
bool _bindetV3Ein(String text) =>
    RegExp(r'''^\s*(import|export)\s+['"][^'"]*\bv3\.dart['"]''', multiLine: true).hasMatch(text);

void main() {
  group('Basen', () {
    final vertrag = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map<String, dynamic>;

    test('die beiden Basen stehen wie im Vertrag', () {
      expect(kPublicBaseUrl, vertrag['baseUrls']['public']);
      expect(kPosBaseUrl, vertrag['baseUrls']['pos']);
      expect(kRechnungBaseUrl, kPublicBaseUrl);
      expect(kRegisterBaseUrl, kPosBaseUrl);
    });

    test('jeder Weg ruft seine Basis, und jeder Aufruf steht dort im Vertrag', () async {
      final routen = vertrag['routes'] as Map<String, dynamic>;
      for (final weg in _wege) {
        final liste = weg.basis == kPosBaseUrl ? routen['pos'] : routen['public'];
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          expect(liste, contains(name), reason: '${weg.name}: $name');
          final netz = _Netz((_) => _v3({'status': 'error', 'message': 'nein'}));
          await expectLater(los(netz.client), throwsA(anything));
          expect(netz.anfragen.single.url.toString(), '${weg.basis}/$name', reason: weg.name);
        }
      }
    });

    test('eine eigene Basis muss auf /v3 enden, sonst wirft schon das Anlegen', () {
      Matcher abgewiesen = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request'));
      for (final falsch in ['https://kasse.kasseneck.at/api', 'https://api.kasseneck.at/v1', '/api', '/v3x', '']) {
        expect(() => RegisterClient(baseUrl: falsch), abgewiesen, reason: falsch);
        expect(() => _sitzung(http.Client(), baseUrl: falsch), abgewiesen, reason: falsch);
        expect(() => RechnungTransport(apiKey: 'kr_test_x', baseUrl: falsch), abgewiesen, reason: falsch);
        expect(() => RechnungApi(apiKey: 'kr_test_x', baseUrl: falsch), abgewiesen, reason: falsch);
      }
      for (final gut in ['/api/v3', '/api/v3/', 'https://proxy.example/kasse/v3']) {
        expect(RegisterClient(baseUrl: gut), isNotNull);
        expect(_sitzung(http.Client(), baseUrl: gut).baseUrl, gut.replaceAll(RegExp(r'/+$'), ''));
        expect(RechnungTransport(apiKey: 'kr_test_x', baseUrl: gut).baseUrl, gut.replaceAll(RegExp(r'/+$'), ''));
      }
    });
  });

  group('Kasseneck-Kopfzeilen', () {
    test('jeder Weg sendet Version und Client-Kennung an die Kasseneck-Basis', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _v3({'status': 'error', 'message': 'nein'}));
          await expectLater(los(netz.client), throwsA(anything));
          final kopf = netz.anfragen.single.headers;
          expect(kopf['Kasseneck-Api-Version'], 'v3', reason: '${weg.name} $name');
          expect(kopf['Kasseneck-Client'], 'kasseneck_api/$kPackageVersion', reason: '${weg.name} $name');
        }
      }
    });

    test('die Paketversion ist die aus pubspec.yaml', () {
      final zeile = File('pubspec.yaml').readAsLinesSync().firstWhere((z) => z.startsWith('version:'));
      expect(kPackageVersion, zeile.substring('version:'.length).trim());
    });

    test('fremde Basen bekommen keine Kasseneck-Kopfzeile', () async {
      for (final basis in [
        'http://127.0.0.1:5001/kasseneck/europe-west1/v3',
        'http://api.kasseneck.at/v3',
        'https://api.kasseneck.at:8443/v3',
        'https://nutzer@api.kasseneck.at/v3',
        'https://proxy.example/api/v3',
        '//proxy.example/api/v3',
      ]) {
        final netz = _Netz((_) => _v3({'status': 'success', 'data': {}}));
        await _sitzung(netz.client, baseUrl: basis).rufen('listMyReceipts');
        await RechnungTransport(apiKey: 'kr_test_x', baseUrl: basis, httpClient: netz.client).rufen('getInvoice', {});
        for (final a in netz.anfragen) {
          expect(a.headers.keys.map((k) => k.toLowerCase()),
              isNot(anyOf(contains('kasseneck-api-version'), contains('kasseneck-client'))),
              reason: basis);
        }
      }
    });

    test('eine relative Basis (gleicher Ursprung) ist eine Kasseneck-Basis', () async {
      final netz = _Netz((_) => _v3({'status': 'success', 'data': {}}));
      await _sitzung(netz.client, baseUrl: '/api/v3').rufen('listMyReceipts');
      expect(netz.anfragen.single.headers['Kasseneck-Api-Version'], 'v3');
    });

    test('eigene Client-Kennung nur aus der Positivliste', () async {
      final netz = _Netz((_) => _v3({'status': 'success', 'data': {}}));
      await _sitzung(netz.client, clientHeader: 'kasse-app/1.0.3+34').rufen('listMyReceipts');
      expect(netz.anfragen.single.headers['Kasseneck-Client'], 'kasse-app/1.0.3+34');
      for (final falsch in ['kasse/1.0', 'kasse-app/', 'kasse-app', 'kasse-app/1 0', 'kasse-web/${'1' * 41}', '']) {
        expect(() => _sitzung(http.Client(), clientHeader: falsch),
            throwsA(isA<KasseneckValidationError>()), reason: falsch);
        expect(() => RegisterClient(clientHeader: falsch), throwsA(isA<KasseneckValidationError>()), reason: falsch);
        expect(() => RechnungTransport(apiKey: 'kr_test_x', clientHeader: falsch),
            throwsA(isA<KasseneckValidationError>()), reason: falsch);
        expect(() => KasseneckApi(apiKey: 'k', cashregisterToken: 't', clientHeader: falsch),
            throwsA(isA<KasseneckValidationError>()), reason: falsch);
      }
    });

    test('omitKasseneckHeaders laesst beide weg, die Antwortpruefung bleibt', () async {
      final netz = _Netz((_) => _v3({'status': 'success', 'data': {}}));
      await _sitzung(netz.client, omit: true).rufen('listMyReceipts');
      expect(netz.anfragen.single.headers.keys.map((k) => k.toLowerCase()),
          isNot(anyOf(contains('kasseneck-api-version'), contains('kasseneck-client'))));
      netz.antwort = (_) => _ohneKennzeichen();
      await expectLater(_sitzung(netz.client, omit: true).rufen('listMyReceipts'),
          throwsA(_apiFehler('dialect_mismatch', ErrorOutcome.unknown)));
    });
  });

  group('Antwortpruefung vor dem Lesen', () {
    test('ohne Kennzeichen: dialect_mismatch, Ausgang unklar, Rumpf ungelesen, kein zweiter Aufruf', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _ohneKennzeichen());
          await expectLater(los(netz.client), throwsA(_apiFehler('dialect_mismatch', ErrorOutcome.unknown)),
              reason: '${weg.name} $name');
          expect(netz.gelesen, isFalse, reason: '${weg.name} $name');
          expect(netz.anfragen, hasLength(1), reason: '${weg.name} $name');
        }
      }
    });

    test('Kennzeichen in anderer Schreibweise und mit Leerraum zaehlt', () async {
      final netz = _Netz((_) => _Antwort(200, {..._json, 'kasseneck-api-version': ' V3 '},
          utf8.encode(jsonEncode({'status': 'success', 'data': {'a': 1}}))));
      expect(await _sitzung(netz.client).rufen('listMyReceipts'), {'a': 1});
    });

    test('falscher Wert des Kennzeichens ist kein v3', () async {
      final netz = _Netz((_) => _Antwort(200, {..._json, 'kasseneck-api-version': 'v2'}, utf8.encode('{}')));
      await expectLater(_sitzung(netz.client).rufen('listMyReceipts'),
          throwsA(_apiFehler('dialect_mismatch', ErrorOutcome.unknown)));
      expect(netz.gelesen, isFalse);
    });

    test('HTML bei 200 ohne Kennzeichen: route_missing, abgelehnt, Rumpf ungelesen', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _html());
          await expectLater(los(netz.client), throwsA(_apiFehler('route_missing', ErrorOutcome.rejected)),
              reason: '${weg.name} $name');
          expect(netz.gelesen, isFalse, reason: '${weg.name} $name');
        }
      }
    });

    test('HTML mit Kennzeichen: signierend Ausgang unklar, sonst route_missing', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _html(kennzeichen: true));
          final erwartet = _signierend.contains(name)
              ? _httpFehler('not-json', ErrorOutcome.unknown)
              : _apiFehler('route_missing', ErrorOutcome.rejected);
          await expectLater(los(netz.client), throwsA(erwartet), reason: '${weg.name} $name');
        }
      }
    });

    test('HTTP != 200 vor allem anderen; 5xx auf signierenden Aufrufen ist Ausgang unklar', () async {
      for (final status in [500, 502, 503, 401, 404]) {
        for (final kennzeichen in [true, false]) {
          for (final weg in _wege) {
            for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
              final netz = _Netz((_) => _Antwort(
                  status, {'content-type': 'text/html', if (kennzeichen) ..._kennzeichen}, utf8.encode('<html/>')));
              final ausgang =
                  status >= 500 && _signierend.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected;
              await expectLater(
                  los(netz.client),
                  throwsA(_httpFehler('server-error', ausgang).having((e) => e.statusCode, 'statusCode', status)),
                  reason: '${weg.name} $name $status $kennzeichen');
            }
          }
        }
      }
    });

    test('HTTP 404 des Rands mit Kennzeichen und Code: fachlicher Fehler not_found', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _v3({'status': 'error', 'code': 'not_found', 'message': 'unbekannt'}, status: 404));
          await expectLater(los(netz.client), throwsA(_apiFehler('not_found', ErrorOutcome.rejected)),
              reason: '${weg.name} $name');
        }
      }
    });

    test('HTTP 404 ohne Kennzeichen bleibt ungelesen ein HTTP-Fehler', () async {
      final netz = _Netz((_) => _Antwort(404, _json, utf8.encode(jsonEncode({'status': 'error', 'code': 'not_found'}))));
      await expectLater(
          _sitzung(netz.client).rufen('listMyReceipts'), throwsA(_httpFehler('server-error', ErrorOutcome.rejected)));
      expect(netz.gelesen, isFalse);
    });
  });

  group('Ausgang', () {
    test('Codes mit unklarem Ausgang', () {
      for (final code in ['dialect_mismatch', 'receipt_outcome_unknown', 'cancellation_outcome_unknown',
        'response_unreadable', 'response_translation_failed']) {
        expect(KasseneckApiError('x', 'm', code: code).outcome, ErrorOutcome.unknown, reason: code);
      }
      expect(KasseneckApiError('x', 'm', code: 'response_translation_failed', details: const {'handled': true}).outcome,
          ErrorOutcome.unknown);
      expect(KasseneckApiError('x', 'm', code: 'response_translation_failed', details: const {'handled': null}).outcome,
          ErrorOutcome.unknown);
      expect(KasseneckApiError('x', 'm', code: 'response_translation_failed', details: const {'handled': false}).outcome,
          ErrorOutcome.rejected);
      for (final code in [null, 'validation', 'not_found', 'route_missing', 'login_failed']) {
        expect(KasseneckApiError('x', 'm', code: code).outcome, ErrorOutcome.rejected, reason: '$code');
      }
    });

    test('der Code des Servers kommt mit seinen Details an (handled: false)', () async {
      final netz = _Netz((_) => _v3({
            'status': 'error',
            'code': 'response_translation_failed',
            'message': 'x',
            'data': {'handled': false},
          }));
      await expectLater(_sitzung(netz.client).rufen('createReceipt'),
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.rejected)));
      await expectLater(RegisterClient(httpClient: netz.client).pairRegisterDevice(code: 'ABC123'),
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.rejected)));
    });

    test('receipt_outcome_unknown am Geraete-Client ist ein KasseneckApiError mit unklarem Ausgang', () async {
      final netz = _Netz((_) => _v3({'status': 'error', 'code': 'receipt_outcome_unknown', 'message': 'x'}));
      await expectLater(_geraet(netz.client).sellReceipt(payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 100)], items: [_posten]),
          throwsA(_apiFehler('receipt_outcome_unknown', ErrorOutcome.unknown)));
    });

    test('Netzfehler nach dem Senden: signierend unklar, sonst abgelehnt', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final c = MockClient((_) async => throw const SocketException('weg'));
          final ausgang = _signierend.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected;
          await expectLater(los(c), throwsA(_httpFehler(KasseneckHttpError.netz, ausgang)),
              reason: '${weg.name} $name');
        }
      }
    });

    test('Zeitlimit: signierend unklar, sonst abgelehnt; die Frist steht am Fehler', () async {
      const frist = Duration(milliseconds: 20);
      final haengt = MockClient((_) => Completer<http.Response>().future);
      final t = RegisterTransport(
          idToken: () async => 't', sessionId: () async => 's', cashregisterId: 'K', httpClient: haengt, timeout: frist);
      await expectLater(t.rufen('createReceipt'),
          throwsA(_httpFehler(KasseneckHttpError.zeitablauf, ErrorOutcome.unknown).having((e) => e.timeout, 'timeout', frist)));
      await expectLater(t.rufen('listMyReceipts'),
          throwsA(_httpFehler(KasseneckHttpError.zeitablauf, ErrorOutcome.rejected)));
    });

    test('Zeitlimit greift auch, wenn der Rumpf haengt', () async {
      final c = MockClient.streaming((_, _) async => http.StreamedResponse(
          StreamController<List<int>>().stream, 200, headers: {..._json, ..._kennzeichen}));
      final t = RegisterTransport(idToken: () async => 't', sessionId: () async => 's', cashregisterId: 'K',
          httpClient: c, timeout: const Duration(milliseconds: 20));
      await expectLater(t.rufen('createReceipt'),
          throwsA(_httpFehler(KasseneckHttpError.zeitablauf, ErrorOutcome.unknown)));
    });

    test('unlesbare Erfolgsantwort: signierend unklar, sonst abgelehnt', () async {
      final faelle = {
        'empty-body': '',
        'not-json': 'kein json',
        'missing-status': '{"data":{}}',
      };
      for (final MapEntry(key: grund, value: rumpf) in faelle.entries) {
        for (final weg in _wege) {
          for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
            final netz = _Netz((_) => _Antwort(200, {..._json, ..._kennzeichen}, utf8.encode(rumpf)));
            final ausgang = _signierend.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected;
            await expectLater(los(netz.client), throwsA(_httpFehler(grund, ausgang)),
                reason: '${weg.name} $name $grund');
          }
        }
      }
    });

    test('isOutcomeUnknown fasst alle Fehlerarten zusammen', () {
      expect(isOutcomeUnknown(const KasseneckApiError('x', 'm', code: 'dialect_mismatch')), isTrue);
      expect(isOutcomeUnknown(const KasseneckApiError('x', 'm', code: 'validation')), isFalse);
      expect(isOutcomeUnknown(const KasseneckHttpError('x', 0, 'network', outcome: ErrorOutcome.unknown)), isTrue);
      expect(isOutcomeUnknown(const KasseneckHttpError('x', 0, 'network')), isFalse);
      expect(isOutcomeUnknown(const KasseneckValidationError('x', 'r', 'request')), isFalse);
      expect(isOutcomeUnknown(Exception('x')), isFalse);
      expect(isOutcomeUnknown(null), isFalse);
    });
  });

  group('Zeichensatz', () {
    // Der Server sendet UTF-8; gelesen wird immer strikt UTF-8 aus den Bytes,
    // gleich was der Inhaltstyp behauptet (Proxy, CDN).
    for (final typ in ['application/json; charset', 'application/json;;', 'application/json; charset=iso-8859-1',
      'text/plain']) {
      test('Inhaltstyp "$typ" verstuemmelt nichts und wirft nichts Rohes', () async {
        final rumpf = utf8.encode(jsonEncode({'status': 'error', 'code': 'x_y', 'message': 'Grüße', 'data': {'n': 'Bäckerei'}}));
        final erfolg = utf8.encode(jsonEncode({'status': 'success', 'data': {'n': 'Bäckerei'}}));
        _Antwort a(List<int> b) => _Antwort(200, {'content-type': typ, ..._kennzeichen}, b);
        final netz = _Netz((_) => a(erfolg));
        expect(await _sitzung(netz.client).rufen('listMyReceipts'), {'n': 'Bäckerei'});
        expect(await RechnungTransport(apiKey: 'kr_test_x', httpClient: netz.client).rufen('getInvoice', {}),
            {'n': 'Bäckerei'});
        netz.antwort = (_) => a(rumpf);
        final fehler = isA<KasseneckApiError>().having((e) => e.message, 'message', 'Grüße');
        await expectLater(_sitzung(netz.client).rufen('createReceipt'), throwsA(fehler));
        await expectLater(RegisterClient(httpClient: netz.client).pairRegisterDevice(code: 'ABC123'), throwsA(fehler));
        await expectLater(
            _geraet(netz.client).stornieren(cashregisterId: 'K1', originalReceiptId: 'R1', grund: 'input_error'),
            throwsA(fehler));
        await expectLater(_geraet(netz.client).sellReceipt(payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 100)], items: [_posten]),
            throwsA(fehler));
      });
    }

    test('kein UTF-8: not-json, wirkend unklar, sonst abgelehnt', () async {
      for (final weg in _wege) {
        for (final MapEntry(key: name, value: los) in weg.aufrufe.entries) {
          final netz = _Netz((_) => _Antwort(200, {..._json, ..._kennzeichen},
              [...utf8.encode('{"status":"success","data":{"n":"'), 0xff, ...utf8.encode('"}}')]));
          final ausgang = _signierend.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected;
          await expectLater(los(netz.client), throwsA(_httpFehler('not-json', ausgang)), reason: '${weg.name} $name');
        }
      }
    });
  });

  group('Abbruch', () {
    test('das Zeitlimit bricht die laufende Anfrage ab, auf jedem Weg', () async {
      for (final weg in _wege) {
        for (final name in weg.aufrufe.keys) {
          var abgebrochen = false;
          final c = MockClient.streaming((request, _) {
            final antwort = Completer<http.StreamedResponse>();
            expect(request, isA<http.Abortable>(), reason: '${weg.name} $name');
            (request as http.Abortable).abortTrigger?.then((_) {
              abgebrochen = true;
              antwort.completeError(http.RequestAbortedException(request.url));
            });
            return antwort.future;
          });
          final ausgang = _signierend.contains(name) ? ErrorOutcome.unknown : ErrorOutcome.rejected;
          await expectLater(_mitFrist(weg, name, c), throwsA(_httpFehler(KasseneckHttpError.zeitablauf, ausgang)),
              reason: '${weg.name} $name');
          await pumpEventQueue();
          expect(abgebrochen, isTrue, reason: '${weg.name} $name');
        }
      }
    });

    test('auch ein haengender Rumpf wird abgebrochen', () async {
      var abgebrochen = false;
      final c = MockClient.streaming((request, _) async {
        (request as http.Abortable).abortTrigger?.then((_) => abgebrochen = true);
        return http.StreamedResponse(StreamController<List<int>>().stream, 200, headers: {..._json, ..._kennzeichen});
      });
      final t = RegisterTransport(idToken: () async => 't', sessionId: () async => 's', cashregisterId: 'K',
          httpClient: c, timeout: const Duration(milliseconds: 20));
      await expectLater(t.rufen('createReceipt'), throwsA(_httpFehler(KasseneckHttpError.zeitablauf, ErrorOutcome.unknown)));
      await pumpEventQueue();
      expect(abgebrochen, isTrue);
    });

    test('404 des Rands mit haengendem Rumpf bleibt ein abgelehnter HTTP-Fehler wie in npm', () async {
      final c = MockClient.streaming((_, _) async =>
          http.StreamedResponse(StreamController<List<int>>().stream, 404, headers: {..._json, ..._kennzeichen}));
      final t = RegisterTransport(idToken: () async => 't', sessionId: () async => 's', cashregisterId: 'K',
          httpClient: c, timeout: const Duration(milliseconds: 20));
      await expectLater(t.rufen('createReceipt'),
          throwsA(_httpFehler('server-error', ErrorOutcome.rejected).having((e) => e.statusCode, 'statusCode', 404)));
    });
  });

  group('Fachfehler behalten Code, Details und Ausgang', () {
    test('stornieren und belegSenden: handled false abgelehnt, data.code als Rueckfall', () async {
      final netz = _Netz((_) => _v3({
            'status': 'error',
            'code': 'response_translation_failed',
            'message': 'x',
            'data': {'handled': false, 'remainingCents': 5},
          }));
      final storno = _geraet(netz.client).stornieren(cashregisterId: 'K1', originalReceiptId: 'R1', grund: 'input_error');
      await expectLater(
          storno,
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.rejected)
              .having((e) => e.details['remainingCents'], 'details', 5)));
      await expectLater(_geraet(netz.client).belegSenden(fullReceiptId: 'F1', an: 'a@b.at'),
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.rejected)));
      netz.antwort = (_) => _v3({'status': 'error', 'message': 'x', 'data': {'code': 'cancellation_outcome_unknown'}});
      await expectLater(
          _geraet(netz.client).stornieren(cashregisterId: 'K1', originalReceiptId: 'R1', grund: 'input_error'),
          throwsA(_apiFehler('cancellation_outcome_unknown', ErrorOutcome.unknown)));
    });

    test('FinanzOnline-Abfragen reichen den Fachfehler mit Code und Ausgang weiter', () async {
      final netz = _Netz((_) => _v3({'status': 'error', 'code': 'response_translation_failed', 'message': 'x'}));
      await expectLater(_geraet(netz.client).getCashboxStatus(),
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.unknown)));
      await expectLater(_geraet(netz.client).getSignatureStatus('AB'),
          throwsA(_apiFehler('response_translation_failed', ErrorOutcome.unknown)));
    });

    test('Geldwege: Fachfehler mit Code statt stillem false oder Lesefehler', () async {
      final netz = _Netz((_) => _v3({'status': 'error', 'code': 'receipt_outcome_unknown', 'message': 'x'}));
      for (final los in [
        () => _geraet(netz.client).hobexPay(transactionId: '1', amount: 1),
        () => _geraet(netz.client).hobexRefund(transactionId: '1', amount: 1),
        () => _geraet(netz.client).stripeCaptureIntent(stripeSessionId: 's1'),
      ]) {
        await expectLater(los(), throwsA(_apiFehler('receipt_outcome_unknown', ErrorOutcome.unknown)));
      }
    });
  });

  group('Terminal-, Drucker- und Bildwege tragen keine Kasseneck-Kopfzeile', () {
    Matcher ohneKasseneck = isNot(anyOf(contains('kasseneck-api-version'), contains('kasseneck-client')));

    test('hobex HPS am Terminal', () async {
      final anfragen = <http.BaseRequest>[];
      final c = MockClient((r) async {
        anfragen.add(r);
        return http.Response('{}', 200, headers: _json);
      });
      final hps = HpsClient(tid: '1', httpClient: c, timeout: const Duration(seconds: 1));
      await hps.transactionStatus(transactionId: '1').then((_) {}, onError: (_) {});
      await hps.diagnosis().then((_) {}, onError: (_) {});
      expect(anfragen, isNotEmpty);
      for (final a in anfragen) {
        expect(a.headers.keys.map((k) => k.toLowerCase()), ohneKasseneck);
      }
    });

    test('hobex HPS Suche im Netz', () async {
      final anfragen = <http.BaseRequest>[];
      final c = MockClient((r) async {
        anfragen.add(r);
        return http.Response('[]', 200, headers: _json);
      });
      await discoverHpsTerminals(
        interfaces: () async => const <LocalIpv4>[LocalIpv4(name: 'en0', address: '192.168.0.10')],
        probe: (host, _, _) async => host == '192.168.0.187',
        httpClient: c,
      );
      expect(anfragen, isNotEmpty);
      for (final a in anfragen) {
        expect(a.headers.keys.map((k) => k.toLowerCase()), ohneKasseneck);
      }
    });

    test('Logo-Abruf, auch von einem Kasseneck-Host', () async {
      final anfragen = <http.BaseRequest>[];
      final vorher = LogoService.httpClient;
      addTearDown(() => LogoService.httpClient = vorher);
      LogoService.httpClient = MockClient((r) async {
        anfragen.add(r);
        return http.Response('nope', 404);
      });
      await LogoService.loadLogo('https://api.kasseneck.at/v3/logo-kopf.png');
      expect(anfragen, hasLength(1));
      expect(anfragen.single.headers.keys.map((k) => k.toLowerCase()), ohneKasseneck);
    });

    test('der Einbinde-Waechter erkennt jede Form', () {
      for (final zeile in [
        "import '../v3.dart';",
        "import '../v3.dart' show v3Post;",
        "import '../v3.dart' as v3;",
        'import "../v3.dart";',
        "  import 'package:kasseneck_api/src/v3.dart' hide x;",
        "export 'src/v3.dart' show kPosBaseUrl;",
      ]) {
        expect(_bindetV3Ein('library;\n$zeile\n'), isTrue, reason: zeile);
      }
      expect(_bindetV3Ein("import '../nicht_v3.dart';"), isFalse);
      expect(_bindetV3Ein("// import '../v3.dart';"), isFalse);
    });

    test('nur die Kasseneck-Wege kennen die Kopfzeilen; Terminal- und Druckerwege kommen nicht heran', () {
      // Quelltext-Waechter: die beiden Kopfzeilen setzt allein lib/src/v3.dart,
      // und nur die vier Kasseneck-Wege binden es ein. Drucker (Socket, BLE),
      // SumUp (SDK), hobex HPS und der Logo-Abruf nicht.
      final dateien = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      final mitKopf = <String>{};
      final mitV3 = <String>{};
      for (final f in dateien) {
        final text = f.readAsStringSync();
        final pfad = f.path.replaceAll(r'\', '/');
        if (RegExp('Kasseneck-(Api-Version|Client)', caseSensitive: false).hasMatch(text)) mitKopf.add(pfad);
        if (_bindetV3Ein(text)) mitV3.add(pfad);
      }
      expect(mitKopf, {'lib/src/v3.dart'});
      expect(mitV3, {
        'lib/kasseneck_api.dart',
        'lib/rechnung.dart',
        'lib/register.dart',
        'lib/src/register/pairing.dart',
        'lib/src/register/transport.dart',
        'lib/src/rechnung/transport.dart',
      });
    });
  });
}
