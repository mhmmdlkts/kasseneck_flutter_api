import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Kartenleser SumUp Solo ueber die Cloud (Backend-Spec 2026-11-18-sumup-solo-cloud-design, keck#1010):
/// Zwilling von `test/kartenleser-kasse.test.ts`, `kartenleser-ausgang.test.ts` und
/// `kartenleser-wahl.test.ts` im npm-Paket 1.43.0. Die dreizehn Aufrufe gehen nur ueber den
/// Kassenweg; jede Antwort ist fremd, eine Zahlung ein Vorgang mit Kennung, und was ihr
/// Ausgang nicht entscheidet, ist `unknown`.
Map<String, dynamic> _json(String pfad) =>
    jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;

final _surface = (_json('surface.json')['pos'] as Map).cast<String, dynamic>();
final _endpunkte = (_json('v3/antworten/kasse.json')['endpoints'] as Map).cast<String, dynamic>();

Map<String, dynamic> _fall(String endpunkt, String name) =>
    ((_endpunkte[endpunkt] as Map)['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['case'] == name);

Iterable<Map<String, dynamic>> _erfolge(String endpunkt) =>
    ((_endpunkte[endpunkt] as Map)['cases'] as List).cast<Map<String, dynamic>>().where((f) =>
        f['method'] == 'POST' && (f['response'] as Map)['status'] == 'success');

const _d = 'dev_pin';
const _ref = 'payment-0001';
const _refund = 'refund-0001';

const Map<String, dynamic> _zahlung = {
  'reference': _ref,
  'status': 'pending',
  'amountCents': 1090,
  'readerId': 'rdr_01',
  'readerName': 'Theke',
};

const Map<String, dynamic> _anbieterdaten = {
  'channel': 'cloud',
  'transactionCode': 'TC1',
  'transactionId': 'txn_1',
  'amount': 10.9,
  'currency': 'EUR',
  'cardType': 'VISA',
  'cardLastDigits': '4242',
  'entryMode': 'contactless',
  'authCode': '123456',
  'merchantCode': 'MZK4711X',
  'foreignTransactionId': _ref,
  'readerId': 'rdr_01',
};

final Map<String, dynamic> _erfolg = {
  ..._zahlung,
  'status': 'successful',
  'transaction': {
    'id': 'txn_1',
    'code': 'TC1',
    'cardType': 'VISA',
    'cardLastDigits': '4242',
    'entryMode': 'contactless',
    'authCode': '123456',
    'amountCents': 1090,
    'timeMs': 1790409575000,
  },
  'receiptPayment': {'provider': 'sumup', 'providerPaymentId': 'TC1', 'providerData': _anbieterdaten},
};

const Map<String, dynamic> _erstattung = {
  'reference': _refund,
  'paymentReference': _ref,
  'status': 'pending',
  'amountCents': 590,
};

/// Ein Kassen-Client, dessen Netz mit [huelle] antwortet (oder nach [antwort] scheitert) und
/// jede Anfrage festhaelt.
({RegisterReceiptClient client, List<http.Request> anfragen}) _kasse(Object? huelle,
    {Future<http.Response>? Function()? antwort, Duration? frist}) {
  final anfragen = <http.Request>[];
  final client = RegisterReceiptClient(RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    timeout: frist,
    httpClient: MockClient((r) {
      anfragen.add(r);
      final eigen = antwort;
      if (eigen != null) return eigen() ?? Completer<http.Response>().future;
      return Future.value(http.Response.bytes(utf8.encode(jsonEncode(huelle)), 200,
          headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'}));
    }),
  ));
  return (client: client, anfragen: anfragen);
}

/// Erfolgshuelle mit [daten].
({RegisterReceiptClient client, List<http.Request> anfragen}) _mit(Object? daten) =>
    _kasse({'status': 'success', 'data': daten});

/// Ein Transport wie die Huellen der Kassen-App (`_AusgabeTransport`, `_KopfTransport`, `_WarteTransport`):
/// er kennt an `call` und `callRaw` nur `params` und `timeout` und reicht beides an den inneren weiter.
class _Huelle implements RegisterTransport {
  _Huelle(this._innen);

  final RegisterTransport _innen;

  @override
  Future<String?> Function() get idToken => _innen.idToken;

  @override
  Future<String?> Function() get sessionId => _innen.sessionId;

  @override
  String get cashregisterId => _innen.cashregisterId;

  @override
  String get baseUrl => _innen.baseUrl;

  @override
  Future<Map<String, dynamic>> call(String name, {Map<String, dynamic> params = const {}, Duration? timeout}) =>
      _innen.call(name, params: params, timeout: timeout);

  @override
  Future<http.Response> callRaw(String name, {Map<String, dynamic> params = const {}, Duration? timeout}) =>
      _innen.callRaw(name, params: params, timeout: timeout);
}

/// Die gesendeten Parameter ohne die Kasse, die der Transport jeder Nutzlast beilegt.
Map<String, dynamic> _gesendet(http.Request r) =>
    (((jsonDecode(r.body) as Map)['params'] as Map).cast<String, dynamic>())..remove('cashregisterId');

final _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');
final _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
final _unlesbar = isA<KasseneckApiError>()
    .having((e) => e.code, 'code', 'response_unreadable')
    .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown);

Future<Object?> _fehler(Future<Object?> aufruf) async {
  try {
    await aufruf;
  } catch (e) {
    return e;
  }
  return null;
}

void main() {
  group('Kataloge', () {
    test('Stand, Gruende, Entscheidung und Konto sind die Listen aus surface.json', () {
      expect(cardAccountStates, _surface['cardAccountStates']);
      expect(cardAccountMethods, _surface['cardAccountMethods']);
      expect(cardReaderStatuses, _surface['cardReaderStatuses']);
      expect(cardReaderPaymentStatuses, _surface['cardReaderPaymentStatuses']);
      expect(cardReaderReasons, _surface['cardReaderReasons']);
      expect(cardReaderDecisions, _surface['cardReaderDecisions']);
      expect(cardReaderPaymentStatuses, ['pending', 'successful', 'failed', 'cancelled', 'declined', 'unclear']);
      expect(cardReaderDecisions, ['receipt', 'discard']);
      expect(cardReaderBluetooth, 'bluetooth');
      expect(cardReaderMinCents, 100);
      expect(cardReaderMaxCents, 1000000);
    });

    test('die Werte der Vertragsfaelle stehen in den Katalogen', () {
      final stati = <String>{};
      for (final e in [
        'getCardReaderPayment', 'startCardReaderPayment', 'cancelCardReaderPayment', 'resolveCardReaderPayment',
        'refundCardReaderPayment', 'getCardReaderRefund',
      ]) {
        for (final f in _erfolge(e)) {
          stati.add(((f['response'] as Map)['data'] as Map)['status'] as String);
        }
      }
      expect(cardReaderPaymentStatuses, containsAll(stati));
      for (final f in _erfolge('getCardReaderSetup')) {
        final d = (f['response'] as Map)['data'] as Map;
        final c = d['connection'] as Map;
        expect(cardAccountStates, contains(c['state']));
        if (c['method'] != null) expect(cardAccountMethods, contains(c['method']));
        for (final r in d['readers'] as List) {
          expect(cardReaderStatuses, contains((r as Map)['status']));
        }
      }
      for (final f in _erfolge('cancelCardReaderPayment')) {
        expect(cardReaderReasons, contains(((f['response'] as Map)['data'] as Map)['reason']));
      }
    });
  });

  group('Vertrag: jeder Erfolgsfall sendet wie aufgezeichnet und liest sich wie im npm-Paket', () {
    const leserVorgabe = {
      'serial': null, 'model': null, 'status': null, 'online': null, 'battery': null, 'busy': false, 'busyDevice': null,
    };
    Map<String, dynamic> leser(Map r) => {...leserVorgabe, ...r.cast<String, dynamic>()};
    const zahlungVorgabe = {'reason': null, 'readerId': null, 'readerName': null, 'transaction': null, 'receiptPayment': null};
    const buchungVorgabe = {
      'id': null, 'code': null, 'cardType': null, 'cardLastDigits': null, 'entryMode': null, 'authCode': null,
      'amountCents': null, 'timeMs': null,
    };

    final rufe = <String, Future<Object?> Function(RegisterReceiptClient c, Map<String, dynamic> p)>{
      'getCardReaderSetup': (c, p) async =>
          (await c.getCardReaderSetup(deviceId: p['deviceId'] as String, withStatus: p['withStatus'] == true)).toJson(),
      'startCardAccountConnection': (c, p) => c.startCardAccountConnection(deviceId: p['deviceId'] as String),
      'disconnectCardAccount': (c, p) async {
        await c.disconnectCardAccount(deviceId: p['deviceId'] as String);
        return null;
      },
      'pairCardReader': (c, p) async => (await c.pairCardReader(
              deviceId: p['deviceId'] as String, pairingCode: p['pairingCode'] as String, name: p['name'] as String))
          .toJson(),
      'renameCardReader': (c, p) async => (await c.renameCardReader(
              deviceId: p['deviceId'] as String, readerId: p['readerId'] as String, name: p['name'] as String))
          .toJson(),
      'removeCardReader': (c, p) async {
        await c.removeCardReader(deviceId: p['deviceId'] as String, readerId: p['readerId'] as String);
        return null;
      },
      'setDeviceCardReader': (c, p) =>
          c.setDeviceCardReader(deviceId: p['deviceId'] as String, readerId: p['readerId'] as String?),
      'startCardReaderPayment': (c, p) async => (await c.startCardReaderPayment(
            deviceId: p['deviceId'] as String,
            reference: p['reference'] as String,
            amountCents: p['amountCents'] as int,
            readerId: p['readerId'] as String?,
          ))
              .toJson(),
      'getCardReaderPayment': (c, p) async =>
          (await c.getCardReaderPayment(deviceId: p['deviceId'] as String, reference: p['reference'] as String)).toJson(),
      'cancelCardReaderPayment': (c, p) async =>
          (await c.cancelCardReaderPayment(deviceId: p['deviceId'] as String, reference: p['reference'] as String))
              .toJson(),
      'resolveCardReaderPayment': (c, p) async => (await c.resolveCardReaderPayment(
              deviceId: p['deviceId'] as String, reference: p['reference'] as String, decision: p['decision'] as String))
          .toJson(),
      'refundCardReaderPayment': (c, p) async => (await c.refundCardReaderPayment(
            deviceId: p['deviceId'] as String,
            reference: p['reference'] as String,
            paymentReference: p['paymentReference'] as String,
            amountCents: p['amountCents'] as int,
          ))
              .toJson(),
      'getCardReaderRefund': (c, p) async =>
          (await c.getCardReaderRefund(deviceId: p['deviceId'] as String, reference: p['reference'] as String)).toJson(),
    };

    test('die dreizehn Aufrufe in der Reihenfolge des Vertrags', () {
      final pos = (_json('surface.json')['calls'] as Map)['pos'] as List;
      expect(rufe.keys.toList(), pos.skip(pos.indexOf('getCardReaderSetup')).take(13).toList());
    });

    for (final endpunkt in rufe.keys) {
      test(endpunkt, () async {
        var gelaufen = 0;
        for (final f in _erfolge(endpunkt)) {
          final wo = '$endpunkt/${f['case']}';
          final antwort = f['response'] as Map<String, dynamic>;
          final k = _kasse(antwort);
          final p = (f['params'] as Map).cast<String, dynamic>();
          final ist = await rufe[endpunkt]!(k.client, p);
          expect(k.anfragen.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/$endpunkt', reason: wo);
          expect(_gesendet(k.anfragen.single), p, reason: wo);
          final d = (antwort['data'] as Map).cast<String, dynamic>();
          final Object? soll = switch (endpunkt) {
            'getCardReaderSetup' => {
                'connection': {'method': null, 'merchantCode': null, ...(d['connection'] as Map).cast<String, dynamic>()},
                'readers': [for (final r in d['readers'] as List) leser(r as Map)],
                'deviceReader': d['deviceReader'],
                'canManage': d['canManage'],
              },
            'startCardAccountConnection' => d['authorizeUrl'],
            'disconnectCardAccount' || 'removeCardReader' => null,
            'pairCardReader' || 'renameCardReader' => leser(d),
            'setDeviceCardReader' => d['deviceReader'],
            'refundCardReaderPayment' || 'getCardReaderRefund' => {'reason': null, ...d},
            _ => {
                ...zahlungVorgabe,
                ...d,
                if (d['transaction'] != null)
                  'transaction': {...buchungVorgabe, ...(d['transaction'] as Map).cast<String, dynamic>()},
                // Das Paket ergaenzt Zahlart und Betrag, damit die Zahlung ohne Umbau in den Verkauf passt.
                if (d['receiptPayment'] != null)
                  'receiptPayment': {
                    'method': 'creditCard',
                    'amountCents': d['amountCents'],
                    ...(d['receiptPayment'] as Map).cast<String, dynamic>(),
                  },
              },
          };
          expect(ist, soll, reason: wo);
          gelaufen++;
        }
        expect(gelaufen, greaterThan(0));
      });
    }

    test('die bezahlte Zahlung traegt die Belegzahlung 1:1 und ist ein Endstand', () async {
      final bezahlt = _fall('getCardReaderPayment', 'success_cashier');
      final z = await _kasse(bezahlt['response']).client.getCardReaderPayment(deviceId: _d, reference: _ref);
      final d = (bezahlt['response'] as Map)['data'] as Map;
      expect(z.receiptPayment!.toJson(), {
        'method': 'creditCard',
        'amountCents': d['amountCents'],
        ...(d['receiptPayment'] as Map).cast<String, dynamic>(),
      });
      expect(isCardReaderFinal(z.status), isTrue);
    });

    test('automatisch: readerId geht als ausdrueckliches null auf den Draht', () async {
      final auto = _fall('setDeviceCardReader', 'success_automatic');
      final k = _kasse(auto['response']);
      expect(await k.client.setDeviceCardReader(deviceId: _d, readerId: null), isNull);
      final params = (jsonDecode(k.anfragen.single.body) as Map)['params'] as Map;
      expect(params.containsKey('readerId'), isTrue);
      expect(params['readerId'], isNull);
      expect(k.anfragen.single.body, contains('"readerId":null'));
    });

    test('Auswahl und belegter Leser kommen aus den Fehlerdetails des Vertrags', () async {
      final wahl = _fall('startCardReaderPayment', 'select_required');
      final e1 = await _fehler(_kasse(wahl['response']).client.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090));
      expect([for (final r in cardReaderChoices(e1)) [r.readerId, r.name]],
          [for (final r in ((wahl['response'] as Map)['data'] as Map)['readers'] as List) [(r as Map)['readerId'], r['name']]]);
      expect(cardReaderBusyDevice(e1), isNull);
      // Nichts wurde gestartet: die Auswahl ist eine Ablehnung, kein unklarer Ausgang.
      expect(isOutcomeUnknown(e1), isFalse);
      final belegt = _fall('startCardReaderPayment', 'in_use');
      final e2 = await _fehler(_kasse(belegt['response']).client.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090));
      expect(cardReaderBusyDevice(e2), ((belegt['response'] as Map)['data'] as Map)['busyDevice']);
      expect(cardReaderChoices(e2), isEmpty);
      final entfernen = _fall('removeCardReader', 'in_use');
      final e3 = await _fehler(
          _kasse(entfernen['response']).client.removeCardReader(deviceId: _d, readerId: 'rdr_01KORNBLUMTHEKE00000000000'));
      expect(cardReaderBusyDevice(e3), ((entfernen['response'] as Map)['data'] as Map)['busyDevice']);
    });
  });

  group('Aufrufe senden genau die Felder', () {
    test('Einrichtung: withStatus nur, wenn wahr; Leser ohne Kennung fallen weg, Unbekanntes mit Vorgabe', () async {
      var k = _mit({
        'connection': {'state': 'connected', 'method': 'api_key', 'merchantCode': 'MZK4711X', 'refundsEnabled': true, 'connectAvailable': true},
        'readers': [
          {'readerId': 'rdr_01', 'name': 'Theke', 'serial': '1', 'model': 'solo', 'status': 'paired', 'busy': true, 'busyDevice': 'Tablet hinten'},
          {'name': 'ohne Kennung'},
          'kaputt',
        ],
        'deviceReader': 'bluetooth',
        'canManage': true,
      });
      final s = await k.client.getCardReaderSetup(deviceId: _d, withStatus: true);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'withStatus': true});
      expect(s.readers, hasLength(1));
      expect(s.readers.single.toJson(), {
        'readerId': 'rdr_01', 'name': 'Theke', 'serial': '1', 'model': 'solo', 'status': 'paired', 'online': null,
        'battery': null, 'busy': true, 'busyDevice': 'Tablet hinten',
      });
      expect(s.deviceReader, cardReaderBluetooth);
      k = _mit({'connection': {'state': 'wild', 'method': 'x'}, 'readers': 'kaputt'});
      final leer = await k.client.getCardReaderSetup(deviceId: _d);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d});
      // Ein unbekannter Stand gilt als nicht verbunden: die Kasse bietet das Verbinden an, nie eine Zahlung.
      expect(leer.toJson(), {
        'connection': {'state': 'none', 'method': null, 'merchantCode': null, 'refundsEnabled': false, 'connectAvailable': false},
        'readers': <Object?>[],
        'deviceReader': null,
        'canManage': false,
      });
    });

    test('Verwaltung: Code und Name gehen unveraendert hinaus, der Server prueft', () async {
      var k = _mit({'authorizeUrl': 'https://api.sumup.com/authorize?x=1'});
      expect(await k.client.startCardAccountConnection(deviceId: _d), 'https://api.sumup.com/authorize?x=1');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d});
      // Eine Bestaetigung ohne die dokumentierten Felder ist trotzdem Erfolg.
      k = _mit({});
      await k.client.disconnectCardAccount(deviceId: _d);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d});
      k = _mit(null);
      await k.client.removeCardReader(deviceId: _d, readerId: 'rdr_01');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'readerId': 'rdr_01'});
      const leser = {'readerId': 'rdr_01', 'name': 'Theke', 'status': 'pairing', 'busy': false};
      k = _mit(leser);
      final l = await k.client.pairCardReader(deviceId: _d, pairingCode: ' k7p4 ', name: ' Theke ');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'pairingCode': ' k7p4 ', 'name': ' Theke '});
      expect(l.status, 'pairing');
      k = _mit(leser);
      await k.client.renameCardReader(deviceId: _d, readerId: 'rdr_01', name: 'Neu');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'readerId': 'rdr_01', 'name': 'Neu'});
      expect(await _fehler(_mit({}).client.pairCardReader(deviceId: _d, pairingCode: 'A', name: 'B')), _antwortfehler);
      expect(await _fehler(_mit({}).client.startCardAccountConnection(deviceId: _d)), _antwortfehler);
    });

    test('Zuweisung: Kennung, bluetooth oder null; null geht als null hinaus', () async {
      var k = _mit({'deviceReader': null});
      expect(await k.client.setDeviceCardReader(deviceId: _d, readerId: null), isNull);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'readerId': null});
      k = _mit({'deviceReader': 'bluetooth'});
      expect(await k.client.setDeviceCardReader(deviceId: _d, readerId: 'bluetooth'), 'bluetooth');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'readerId': 'bluetooth'});
    });

    test('ein null der uebrigen Aufrufe faellt weiter weg (readerId beim Start)', () async {
      final k = _mit(_zahlung);
      await k.client.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090);
      final roh = (jsonDecode(k.anfragen.single.body) as Map)['params'] as Map;
      expect(roh.containsKey('readerId'), isFalse);
    });

    test('der Transport laesst null weiter weg; die Schnittstelle von call und callRaw bleibt params und timeout', () async {
      final anfragen = <http.Request>[];
      final t = RegisterTransport(
        idToken: () async => 'id-token',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KASSE1',
        httpClient: MockClient((r) async {
          anfragen.add(r);
          return http.Response('{"status":"success","data":{}}', 200,
              headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
        }),
      );
      await t.call('getMyTipBalance', params: {'drawerId': null, 'cashregisterId': 'KASSE1'});
      await _Huelle(t).callRaw('getMyTipBalance', params: {'drawerId': null});
      for (final a in anfragen) {
        expect((jsonDecode(a.body) as Map)['params'], {'cashregisterId': 'KASSE1'});
      }
    });

    // Die Kassen-App legt eigene Huellen um den Transport (Gutschein-Codes, Kopf, Warten). Ein ausdrueckliches
    // null muss durch sie hindurch, ohne dass sie etwas davon wissen: es reist in `params`, nicht in einem
    // eigenen Parameter, den eine Huelle nicht kennt und still fallen liesse.
    test('automatisch: readerId null geht auch durch eine Huelle wie die der Kassen-App als null hinaus', () async {
      final anfragen = <http.Request>[];
      final innen = RegisterTransport(
        idToken: () async => 'id-token',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KASSE1',
        httpClient: MockClient((r) async {
          anfragen.add(r);
          return http.Response('{"status":"success","data":{"deviceReader":null}}', 200,
              headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
        }),
      );
      final client = RegisterReceiptClient(_Huelle(innen));
      expect(await client.setDeviceCardReader(deviceId: _d, readerId: null), isNull);
      expect(anfragen.single.body, contains('"readerId":null'));
      expect(_gesendet(anfragen.single), {'deviceId': _d, 'readerId': null});
      await client.getCardReaderSetup(deviceId: _d);
      expect(_gesendet(anfragen.last), {'deviceId': _d});
    });

    test('Erfolg ohne data ist bei Einrichtung und Zuweisung ein Antwortfehler (wie npm „Antwort ist leer“)', () async {
      for (final huelle in [
        {'status': 'success'},
        {'status': 'success', 'data': null},
      ]) {
        final wo = jsonEncode(huelle);
        expect(await _fehler(_kasse(huelle).client.getCardReaderSetup(deviceId: _d)), _antwortfehler, reason: wo);
        expect(await _fehler(_kasse(huelle).client.setDeviceCardReader(deviceId: _d, readerId: null)), _antwortfehler,
            reason: wo);
        expect(await _fehler(_kasse(huelle).client.setDeviceCardReader(deviceId: _d, readerId: 'rdr_01')), _antwortfehler,
            reason: wo);
      }
      // Ein leeres Objekt ist eine Antwort: Vorgaben wie im npm-Paket.
      expect((await _mit({}).client.getCardReaderSetup(deviceId: _d)).connection.state, 'none');
      expect(await _mit({}).client.setDeviceCardReader(deviceId: _d, readerId: null), isNull);
    });

    test('Zahlung und Rueckbuchung', () async {
      var k = _mit(_zahlung);
      await k.client.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090, readerId: 'rdr_01');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _ref, 'amountCents': 1090, 'readerId': 'rdr_01'});
      k = _mit(_zahlung);
      await k.client.getCardReaderPayment(deviceId: _d, reference: _ref);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _ref});
      k = _mit(_zahlung);
      await k.client.cancelCardReaderPayment(deviceId: _d, reference: _ref);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _ref});
      k = _mit(_zahlung);
      await k.client.resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'discard');
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _ref, 'decision': 'discard'});
      final r = {..._erstattung, 'status': 'successful'};
      k = _mit(r);
      final e = await k.client.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _refund, 'paymentReference': _ref, 'amountCents': 590});
      expect(e.toJson(), {...r, 'reason': null});
      k = _mit(r);
      await k.client.getCardReaderRefund(deviceId: _d, reference: _refund);
      expect(_gesendet(k.anfragen.single), {'deviceId': _d, 'reference': _refund});
    });
  });

  test('Pruefung vor dem Senden: kein Aufruf', () async {
    final k = _mit(_zahlung);
    final c = k.client;
    final faelle = <Future<Object?>>[
      c.getCardReaderSetup(deviceId: ''),
      c.getCardReaderSetup(deviceId: '   '),
      c.startCardAccountConnection(deviceId: ''),
      c.disconnectCardAccount(deviceId: ''),
      c.pairCardReader(deviceId: '', pairingCode: 'K7P4M2Q9', name: 'Theke'),
      c.startCardReaderPayment(deviceId: _d, reference: 'kurz', amountCents: 1090),
      c.startCardReaderPayment(deviceId: _d, reference: 'mit leerzeichen!', amountCents: 1090),
      c.startCardReaderPayment(deviceId: _d, reference: 'x' * 65, amountCents: 1090),
      c.startCardReaderPayment(deviceId: _d, reference: 'kz/1abcdefg', amountCents: 1090),
      for (final cents in [99, 1000001, 0, -1090]) c.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: cents),
      c.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090, readerId: ''),
      c.startCardReaderPayment(deviceId: '', reference: _ref, amountCents: 1090),
      c.resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'vielleicht'),
      c.resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'later'),
      for (final cents in [0, -1, 1000001])
        c.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: cents),
      c.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: 'zu', amountCents: 500),
      c.refundCardReaderPayment(deviceId: _d, reference: 'zu', paymentReference: _ref, amountCents: 500),
      c.getCardReaderPayment(deviceId: _d, reference: 'a b'),
      c.cancelCardReaderPayment(deviceId: _d, reference: 'kurz'),
      c.getCardReaderRefund(deviceId: _d, reference: 'kurz'),
      c.renameCardReader(deviceId: _d, readerId: '', name: 'x'),
      c.removeCardReader(deviceId: _d, readerId: '  '),
      c.setDeviceCardReader(deviceId: _d, readerId: ''),
      c.setDeviceCardReader(deviceId: '', readerId: null),
    ];
    for (final (i, f) in faelle.indexed) {
      expect(await _fehler(f), _anfragefehler, reason: 'Fall $i');
    }
    expect(k.anfragen, isEmpty);
    // Die Grenzen sind erlaubt.
    await c.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 100);
    await c.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1000000);
    await c.startCardReaderPayment(deviceId: _d, reference: 'a' * 64, amountCents: 1000).then((_) {}, onError: (_) {});
    expect(k.anfragen, hasLength(3));
    // Eine Rueckbuchung geht ab 1 Cent hinaus; die Obergrenze (Rest der Zahlung) prueft der Server.
    final r = _mit({..._erstattung, 'amountCents': 50});
    for (final cents in [50, 1]) {
      await r.client.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: cents);
    }
    expect([for (final a in r.anfragen) _gesendet(a)['amountCents']], [50, 1]);
  });

  group('Antwort lesen', () {
    test('Lesen: fehlende Kennung, fremde Kennung und krumme Betraege sind Antwortfehler', () async {
      RegisterReceiptClient c(Object? d) => _mit(d).client;
      expect(await _fehler(c({..._zahlung}..remove('reference')).getCardReaderPayment(deviceId: _d, reference: _ref)), _antwortfehler);
      expect(await _fehler(c(null).getCardReaderPayment(deviceId: _d, reference: _ref)), _antwortfehler);
      expect(await _fehler(c({..._zahlung, 'amountCents': 10.9}).getCardReaderPayment(deviceId: _d, reference: _ref)), _antwortfehler);
      expect(await _fehler(c({..._zahlung, 'amountCents': '1090'}).getCardReaderPayment(deviceId: _d, reference: _ref)), _antwortfehler);
      expect(await _fehler(c({..._zahlung, 'reference': 'payment-9999'}).getCardReaderPayment(deviceId: _d, reference: _ref)),
          _antwortfehler);
      expect(await _fehler(c({'reference': _refund, 'paymentReference': _ref}).getCardReaderRefund(deviceId: _d, reference: _refund)),
          _antwortfehler);
      expect(await _fehler(c({..._erstattung, 'reference': 'refund-9999'}).getCardReaderRefund(deviceId: _d, reference: _refund)),
          _antwortfehler);
      expect(await _fehler(c({..._erstattung, 'paymentReference': ''}).getCardReaderRefund(deviceId: _d, reference: _refund)),
          _antwortfehler);
    });

    test('Geldwege: unlesbarer Erfolg ist response_unreadable mit unklarem Ausgang', () async {
      RegisterReceiptClient c(Object? d) => _mit(d).client;
      Future<Object?> start(Object? d) => _fehler(c(d).startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090));
      Future<Object?> erstatten(Object? d) =>
          _fehler(c(d).refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590));
      expect(await start({..._zahlung}..remove('reference')), _unlesbar);
      expect(await start(null), _unlesbar);
      expect(await start([1, 2]), _unlesbar, reason: 'data kein Objekt');
      expect(await start({..._zahlung, 'amountCents': 10.9}), _unlesbar);
      expect(await _fehler(c({..._zahlung}..remove('reference')).cancelCardReaderPayment(deviceId: _d, reference: _ref)), _unlesbar);
      expect(await _fehler(c([1]).cancelCardReaderPayment(deviceId: _d, reference: _ref)), _unlesbar);
      expect(await _fehler(c({..._zahlung}..remove('reference')).resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'discard')),
          _unlesbar);
      expect(await erstatten({..._erstattung}..remove('reference')), _unlesbar);
      expect(await erstatten(null), _unlesbar);
      expect(await erstatten('kaputt'), _unlesbar);
    });

    test('Geldwege: fremde Kennung in der Antwort ist unlesbar (Echo-Pruefung)', () async {
      RegisterReceiptClient c(Object? d) => _mit(d).client;
      final fremd = {..._zahlung, 'reference': 'payment-9999'};
      expect(await _fehler(c(fremd).startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090)), _unlesbar);
      expect(await _fehler(c(fremd).cancelCardReaderPayment(deviceId: _d, reference: _ref)), _unlesbar);
      expect(await _fehler(c(fremd).resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'receipt')), _unlesbar);
      expect(
          await _fehler(c({..._erstattung, 'reference': 'refund-9999'})
              .refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590)),
          _unlesbar);
      expect(
          await _fehler(c({..._erstattung, 'paymentReference': 'payment-9999'})
              .refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590)),
          _unlesbar);
      // Zahlungsblock mit fremder foreignTransactionId: eine fremde Zahlung landete sonst auf dem Beleg.
      final fremderBlock = {
        ..._erfolg,
        'receiptPayment': {
          ...(_erfolg['receiptPayment'] as Map).cast<String, dynamic>(),
          'providerData': {..._anbieterdaten, 'foreignTransactionId': 'payment-9999'},
        },
      };
      expect(await _fehler(c(fremderBlock).startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090)), _unlesbar);
      expect(await _fehler(c(fremderBlock).resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'receipt')), _unlesbar);
      expect(await _fehler(c(fremderBlock).getCardReaderPayment(deviceId: _d, reference: _ref)), _antwortfehler);
    });

    test('unbekannter Stand wird unclear, unbekannter Grund null, optionale Felder null', () async {
      final z = await _mit({'reference': _ref, 'status': 'wartet_neu', 'reason': 'neu', 'amountCents': 500})
          .client
          .getCardReaderPayment(deviceId: _d, reference: _ref);
      expect(z.toJson(), {
        'reference': _ref, 'status': 'unclear', 'reason': null, 'amountCents': 500, 'readerId': null, 'readerName': null,
        'transaction': null, 'receiptPayment': null,
      });
      final ohne = await _mit({'reference': _ref, 'amountCents': 500}).client.getCardReaderPayment(deviceId: _d, reference: _ref);
      expect(ohne.status, 'unclear');
      final g = await _mit({..._zahlung, 'status': 'failed', 'reason': 'declined'}).client.getCardReaderPayment(deviceId: _d, reference: _ref);
      expect(g.reason, 'declined');
      final r = await _mit({..._erstattung, 'status': 'neu'}).client.getCardReaderRefund(deviceId: _d, reference: _refund);
      expect(r.status, 'unclear');
    });

    test('receiptPayment nur bei successful, mit Zahlungskennung und channel cloud', () async {
      Future<CardReaderPayment> lesen(Map<String, dynamic> d) => _mit(d).client.getCardReaderPayment(deviceId: _d, reference: _ref);
      final rp = (_erfolg['receiptPayment'] as Map).cast<String, dynamic>();
      final ok = await lesen(_erfolg);
      expect(ok.receiptPayment!.toJson(), {'method': 'creditCard', 'amountCents': 1090, ...rp});
      expect(ok.transaction!.cardLastDigits, '4242');
      expect(ok.transaction!.timeMs, 1790409575000);
      expect((await lesen({..._erfolg, 'status': 'failed'})).receiptPayment, isNull);
      expect((await lesen({..._erfolg, 'status': 'unclear'})).receiptPayment, isNull);
      expect((await lesen({..._erfolg, 'receiptPayment': {...rp, 'providerPaymentId': ''}})).receiptPayment, isNull);
      expect(
          (await lesen({
            ..._erfolg,
            'receiptPayment': {...rp, 'providerData': {..._anbieterdaten, 'channel': 'app'}},
          }))
              .receiptPayment,
          isNull);
      expect((await lesen({..._erfolg}..remove('receiptPayment'))).receiptPayment, isNull);
      expect((await lesen({..._erfolg, 'receiptPayment': 'kaputt'})).receiptPayment, isNull);
    });

    test('receiptPayment besteht die Zahlungspruefung des Verkaufs und geht unveraendert hinaus', () async {
      final z = (await _mit(_erfolg).client.getCardReaderPayment(deviceId: _d, reference: _ref)).receiptPayment!;
      expect(z.method, KeckPaymentMethod.creditCard);
      expect(z.amountCents, 1090);
      expect(z.provider, CreditCardProvider.sumup);
      expect(z.providerPaymentId, 'TC1');
      expect(paymentsError([z], cancellation: false), isNull);
      final verkauf = _kasse(null, antwort: () => Future.error(const SocketException('Netz aus')));
      final fehler = await _fehler(verkauf.client.sell(
        items: [KasseneckItem(name: 'Kaffee', quantity: 1, priceCents: 1090, vat: VatRate.vat20)],
        payments: [z],
      ));
      expect(fehler, isNot(isA<KasseneckValidationError>()), reason: 'die Pruefung der Zahlung hat nichts abgewiesen');
      expect(verkauf.anfragen, hasLength(1));
      final gesendet = (_gesendet(verkauf.anfragen.single)['payments'] as List).single;
      expect(gesendet, {
        'method': 'creditCard',
        'amountCents': 1090,
        'provider': 'sumup',
        'providerPaymentId': 'TC1',
        'providerData': _anbieterdaten,
      });
    });
  });

  test('isCardReaderFinal: nur successful, failed, cancelled, declined', () {
    expect(cardReaderPaymentStatuses.where(isCardReaderFinal).toList(), ['successful', 'failed', 'cancelled', 'declined']);
    expect(isCardReaderFinal('neu'), isFalse);
  });

  test('cardReaderChoices und cardReaderBusyDevice lesen details nach Code', () {
    const auswahl = KasseneckApiError('startCardReaderPayment', 'Mehrere Leser.', code: 'card_reader_choice_needed', details: {
      'code': 'card_reader_choice_needed',
      'readers': [
        {'readerId': 'rdr_01', 'name': 'Theke', 'status': 'paired'},
        {'readerId': 'rdr_02', 'name': 'Terrasse'},
      ],
    });
    // Der Server schickt nur Kennung und Name: das Paket erfindet keine weiteren Leserfelder.
    expect([for (final r in cardReaderChoices(auswahl)) r.toJson()], [
      {'readerId': 'rdr_01', 'name': 'Theke'},
      {'readerId': 'rdr_02', 'name': 'Terrasse'},
    ]);
    KasseneckApiError wahl(Object? readers) =>
        KasseneckApiError('x', 'm', code: 'card_reader_choice_needed', details: {'readers': readers});
    expect([for (final r in cardReaderChoices(wahl([{'readerId': 'a'}, {'name': 'ohne'}, 7, {'readerId': ''}]))) r.toJson()], [
      {'readerId': 'a', 'name': ''},
    ]);
    expect(cardReaderChoices(wahl('kaputt')), isEmpty);
    expect(cardReaderChoices(const KasseneckApiError('x', 'm', code: 'card_reader_choice_needed')), isEmpty);
    expect(cardReaderChoices(const KasseneckApiError('x', 'm', code: 'validation', details: {'readers': [{'readerId': 'a', 'name': 'b'}]})),
        isEmpty);
    expect(cardReaderChoices(Exception('x')), isEmpty);
    expect(cardReaderChoices(null), isEmpty);
    const belegt = KasseneckApiError('startCardReaderPayment', 'belegt', code: 'card_reader_busy', details: {'busyDevice': 'Tablet hinten'});
    expect(cardReaderBusyDevice(belegt), 'Tablet hinten');
    expect(cardReaderBusyDevice(const KasseneckApiError('x', 'm', code: 'validation', details: {'busyDevice': 'Tablet'})), isNull);
    expect(cardReaderBusyDevice(const KasseneckApiError('x', 'm', code: 'card_reader_busy')), isNull);
    expect(cardReaderBusyDevice(const KasseneckApiError('x', 'm', code: 'card_reader_busy', details: {'busyDevice': ''})), isNull);
    expect(cardReaderBusyDevice(null), isNull);
  });

  group('Ausgang', () {
    // Start und Rueckbuchung antworten bei jeder unerwarteten Ausnahme mit server_error, auch NACH dem
    // Anbieteraufruf: dort ist der Ausgang unklar. Die Kasse fragt mit DERSELBEN Kennung nach.
    for (final name in ['startCardReaderPayment', 'refundCardReaderPayment']) {
      test('$name: server_error und Huelle ohne Code gelten als unklar', () {
        expect(KasseneckApiError(name, 'Fehler', code: 'server_error').outcome, ErrorOutcome.unknown);
        expect(KasseneckApiError(name, 'Fehler').outcome, ErrorOutcome.unknown);
      });
      test('$name: andere Codes bleiben abgelehnt', () {
        for (final code in [
          'card_reader_busy', 'card_payment_amount_invalid', 'card_account_not_connected', 'card_reader_choice_needed', 'validation',
        ]) {
          expect(KasseneckApiError(name, 'Nein', code: code).outcome, ErrorOutcome.rejected, reason: code);
        }
      });
    }

    test('andere Kartenleser-Aufrufe: server_error bleibt abgelehnt (Lesen und Verwalten)', () {
      for (final name in ['getCardReaderPayment', 'pairCardReader', 'getCardReaderSetup', 'cancelCardReaderPayment']) {
        expect(KasseneckApiError(name, 'Fehler', code: 'server_error').outcome, ErrorOutcome.rejected, reason: name);
      }
    });

    test('ueber den Draht: server_error beim Start ist unklar, beim Nachfragen nicht', () async {
      final huelle = {'status': 'error', 'code': 'server_error', 'message': 'Interner Fehler.'};
      final start = await _fehler(_kasse(huelle).client.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090));
      expect(isOutcomeUnknown(start), isTrue);
      final erstatten = await _fehler(
          _kasse(huelle).client.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590));
      expect(isOutcomeUnknown(erstatten), isTrue);
      final nachfragen = await _fehler(_kasse(huelle).client.getCardReaderPayment(deviceId: _d, reference: _ref));
      expect(nachfragen, isA<KasseneckApiError>().having((e) => e.code, 'code', 'server_error'));
      expect(isOutcomeUnknown(nachfragen), isFalse);
    });

    test('Zeitlimit: mit Wirkung unklar, Lesen und Zuweisen abgelehnt', () async {
      const frist = Duration(milliseconds: 20);
      Future<Object?> nie(Future<Object?> Function(RegisterReceiptClient c) los) =>
          _fehler(los(_kasse(null, antwort: () => null, frist: frist).client));
      final unklar = isA<KasseneckHttpError>()
          .having((e) => e.reason, 'reason', KasseneckHttpError.reasonTimeout)
          .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown);
      final abgelehnt = isA<KasseneckHttpError>()
          .having((e) => e.reason, 'reason', KasseneckHttpError.reasonTimeout)
          .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected);
      expect(await nie((c) => c.startCardReaderPayment(deviceId: _d, reference: _ref, amountCents: 1090)), unklar);
      expect(await nie((c) => c.cancelCardReaderPayment(deviceId: _d, reference: _ref)), unklar);
      expect(await nie((c) => c.resolveCardReaderPayment(deviceId: _d, reference: _ref, decision: 'receipt')), unklar);
      expect(await nie((c) => c.refundCardReaderPayment(deviceId: _d, reference: _refund, paymentReference: _ref, amountCents: 590)),
          unklar);
      expect(await nie((c) => c.pairCardReader(deviceId: _d, pairingCode: 'K7P4M2Q9', name: 'Theke')), unklar);
      expect(await nie((c) => c.disconnectCardAccount(deviceId: _d)), unklar);
      expect(await nie((c) => c.getCardReaderPayment(deviceId: _d, reference: _ref)), abgelehnt);
      expect(await nie((c) => c.getCardReaderRefund(deviceId: _d, reference: _refund)), abgelehnt);
      expect(await nie((c) => c.getCardReaderSetup(deviceId: _d)), abgelehnt);
      expect(await nie((c) => c.setDeviceCardReader(deviceId: _d, readerId: null)), abgelehnt);
      expect(await nie((c) => c.startCardAccountConnection(deviceId: _d)), abgelehnt);
    });
  });

  group('Pruefaelle', () {
    test('Wahl des Solos (card-reader-choice-cases.json)', () {
      final faelle = _json('card-reader-choice-cases.json');
      expect(faelle['version'], 1);
      final liste = (faelle['cases'] as List).cast<Map<String, dynamic>>();
      expect(liste.length, greaterThanOrEqualTo(20));
      for (final f in liste) {
        final w = cardReaderFor(CardReaderSetup.fromJson((f['setup'] as Map).cast<String, dynamic>()));
        final ist = <String, Object?>{
          'kind': w.kind,
          ...switch (w) {
            ChosenCardReader(:final reader) => {'readerId': reader.readerId},
            CardReadersToChoose(:final readers) => {'readerIds': [for (final l in readers) l.readerId]},
            BluetoothCardReader() => const <String, Object?>{},
            NoCardReader(:final why) => {'why': why},
          },
        };
        expect(ist, f['expected'], reason: f['name'] as String);
      }
    });

    test('Kassentext je Stand der Zahlung und Rueckbuchung (card-reader-message-cases.json)', () {
      final faelle = _json('card-reader-message-cases.json');
      expect(faelle['version'], 1);
      final liste = (faelle['cases'] as List).cast<Map<String, dynamic>>();
      for (final f in liste) {
        final key = cardReaderMessageKey(f['kind'] as String, status: f['status'] as String, reason: f['reason'] as String?);
        expect(key, f['key'], reason: jsonEncode(f));
        if (key != null) expect(posMessages.containsKey(key), isTrue, reason: '$key fehlt im Textkatalog');
      }
      for (final kind in ['payment', 'refund']) {
        for (final status in cardReaderPaymentStatuses) {
          expect(liste.any((f) => f['kind'] == kind && f['status'] == status), isTrue, reason: '$kind/$status');
        }
      }
      // Ein Stand, den das Paket nicht kennt, gilt wie unclear: nie wie bezahlt.
      expect(cardReaderMessageKey('payment', status: 'neu'), 'solo.checking');
      expect(cardReaderMessageKey('refund', status: 'neu'), 'solo.refund_checking');
      expect(() => cardReaderMessageKey('storno', status: 'pending'), throwsArgumentError);
    });
  });

  group('Kennung der Zahlung', () {
    test('Form kk-<kasse>-<epochMs>-<zufall>', () {
      expect(newCardReaderReference('CASHBOX-DEMO-1', nowMs: 1763800000000, random: 'a1b2c3'), 'kk-CASHBOX-DEMO-1-1763800000000-a1b2c3');
    });

    test('fremde Zeichen fallen weg, Laenge hoechstens 64, leer wird x', () {
      final k = newCardReaderReference('ä ö/ü' * 30, nowMs: 1763800000000, random: 'a1b2c3');
      expect(k, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      final lang = newCardReaderReference('K' * 200, nowMs: 1763800000000, random: 'a1b2c3');
      expect(lang, hasLength(64));
      expect(lang, endsWith('-1763800000000-a1b2c3'));
      expect(newCardReaderReference('ä ö/ü', nowMs: 1, random: 'a1b2c3'), 'kk-x-1-a1b2c3');
      expect(newCardReaderReference('K1', nowMs: 0, random: 'a1b2c3'), 'kk-K1-0-a1b2c3');
    });

    test('zwei Aufrufe sind verschieden, Zufall aus 6 Zeichen a-z0-9', () {
      final a = newCardReaderReference('K1');
      final b = newCardReaderReference('K1');
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^kk-K1-\d+-[a-z0-9]{6}$')));
    });

    test('ungueltige Optionen sind ein Eingabefehler', () {
      for (final random in ['', 'ABCDEF', 'abc12', 'abc1234', 'ab-123']) {
        expect(() => newCardReaderReference('K1', nowMs: 1, random: random), throwsA(_anfragefehler), reason: random);
      }
      expect(() => newCardReaderReference('K1', nowMs: -1, random: 'a1b2c3'), throwsA(_anfragefehler));
    });
  });

  test('Kassentexte: die unklare Karte nennt Solo und Uhrzeit, nie das Terminal', () {
    expect(messageText('solo.unclear_short', {'amount': '1,00 €', 'name': 'Theke', 'time': '14:05'}),
        'Kartenzahlung 1,00 € unklar – bitte klären. Solo „Theke“ · 14:05.');
    expect(labelText('solo.payment_label', {'name': 'Theke', 'time': '14:05'}), 'Solo „Theke“ · 14:05');
    expect(labelText('solo.amount_on_reader'), 'Betrag steht am Solo');
    expect(messageText('solo.busy', {'name': 'Theke', 'device': 'Tablet hinten'}), 'Solo „Theke“ ist gerade bei Tablet hinten besetzt.');
  });
}
