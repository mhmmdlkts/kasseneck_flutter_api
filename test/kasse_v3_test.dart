import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/register.dart';

/// Der Kassenweg `kasse.kasseneck.at/api/v3` gegen den Vertrags-Export des
/// Backends (`v3/antworten/kasse.json`, erzeugt aus den echten Handlern).
///
/// Jeder Fall jedes Endpunkts läuft durch die öffentlichen Clients dieses
/// Pakets: die Anfrage geht genau so hinaus, wie der Export sie aufgezeichnet
/// hat (Adresse und Parameter), ein Erfolg wird gelesen, ein Fehler kommt mit
/// seinem Code und seinen Daten an. Was die Clients schon vor dem Senden
/// abweisen, weist auch der Server ab. Was dieser Weg gar nicht senden kann
/// (ein anderer Anmeldeweg, eine Nutzlast, die kein Client baut), steht
/// ausdrücklich in [_nichtDieserWeg]; nichts fällt still heraus.

final _export = jsonDecode(File('test/fixtures/vertrag/v3/antworten/kasse.json').readAsStringSync())
    as Map<String, dynamic>;
final _endpunkte = (_export['endpoints'] as Map<String, dynamic>);
final _vertrag = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map<String, dynamic>;

const _anmeldung = [
  'pairRegisterDevice', 'listRegisterUsersForDevice', 'listRegisterSessionsForDevice', 'registerUserLogin',
  'registerPinLogin', 'renewRegisterSession', 'endRegisterSession', 'unpairRegisterDevice',
];
const _kassenAufrufe = [
  'listMyArticleGroups', 'listMyArticles', 'getKasseSettings', 'setMyKasseSettings', 'setMyKasseLogo',
  'setMyRegisterDeviceSettings', 'listMyPrinters', 'createPrintJob', 'getPrintJob', 'listMyTipRecipients',
];
const _weitere = ['listMyCashregisters', 'generateFullReceiptId', 'createReceipt', 'cancelReceipt'];

/// Fälle, die dieser Weg bewusst nicht senden kann, mit Grund.
const _nichtDieserWeg = {
  'createReceipt/start_receipt': 'Startbeleg: Panel bzw. API-Schlüssel, nicht der Verkauf der Kasse',
  'createReceipt/receipt_type_unknown': 'receiptType ist hier fest standard',
  'createReceipt/tip_on_start': 'Startbeleg mit Trinkgeld: Weg des API-Schlüssels',
  'createReceipt/cashregister_missing':
      'ohne cashregisterId: der Sitzungs-Transport legt die Kasse jeder Nutzlast bei, so geht dieser Weg nie hinaus',
  'createReceipt/payments_conflict': 'paymentMethod neben payments, sendet dieser Weg nie',
  'cancelReceipt/payments_conflict': 'paymentMethod am Storno, sendet dieser Weg nie',
  'cancelReceipt/card_data_without_card': 'cardPaymentId am Storno, sendet dieser Weg nie',
  'cancelReceipt/items_no_array': 'items ist hier immer eine Liste (Stornoposition)',
};

/// Fälle, deren Fehler die Kasse beim Verkauf im Alltag sieht (Anmeldung
/// abgelaufen, andere Kasse, Modul aus), die der Export aber mit der alten
/// Einzelzahlart (bzw. ohne Positionen) aufgezeichnet hat. Der Handler bricht
/// vor dem Lesen der Zahlungen ab; der Verkauf schickt dieselbe Anfrage mit
/// `payments` statt `paymentMethod` (und einer Position, wo keine stand).
const _mitZahlungen = {'without_token', 'session_other_cashregister', 'module_off'};

Map<String, dynamic> _alsVerkauf(Map<String, dynamic> fall) {
  final p = Map<String, dynamic>.from(fall['params'] as Map);
  final items = (p['items'] as List?) ?? [
    {'name': 'Kaffee', 'amount': 2, 'priceOneCents': 320, 'vat': 20},
  ];
  final summe = items.fold<int>(0, (s, i) => s + ((i as Map)['amount'] as int) * (i['priceOneCents'] as int));
  final methode = p.remove('paymentMethod') ?? 'cash';
  p['items'] = items;
  p['payments'] = [
    {'method': methode, 'amountCents': summe},
  ];
  return {...fall, 'params': p};
}

Iterable<Map<String, dynamic>> _faelle(String endpunkt) =>
    ((_endpunkte[endpunkt] as Map)['cases'] as List).cast<Map<String, dynamic>>().where((f) {
      final p = f['params'];
      return f['method'] == 'POST' && p is Map && !p.containsKey(r'$body');
    }).map((f) => endpunkt == 'createReceipt' && _mitZahlungen.contains(f['case']) ? _alsVerkauf(f) : f);

Map<String, dynamic> _fall(String endpunkt, String name) =>
    ((_endpunkte[endpunkt] as Map)['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['case'] == name);

class _Lauf {
  final List<http.Request> log = [];
  Object? ergebnis;
  Object? fehler;
  bool vorab = false;

  Map<String, dynamic> get params => (jsonDecode(log.single.body) as Map)['params'] as Map<String, dynamic>;
}

http.Client _mock(Map<String, dynamic> fall, _Lauf lauf) {
  final kopf = (fall['headers'] as Map).cast<String, String>();
  return MockClient((request) async {
    lauf.log.add(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode(fall['response'])),
      fall['httpStatus'] as int,
      headers: {'content-type': 'application/json', for (final e in kopf.entries) e.key.toLowerCase(): e.value},
    );
  });
}

RegisterTransport _transport(http.Client client, String kasse) => RegisterTransport(
      idToken: () async => 'id-token',
      sessionId: () async => 'sess-1',
      cashregisterId: kasse,
      httpClient: client,
    );

String _s(Object? v) => v is String ? v : '';

RegisterClientInfo? _clientInfo(Object? roh) {
  if (roh is! Map) return null;
  final screen = roh['screen'];
  return RegisterClientInfo(
    userAgent: roh['userAgent'] as String?,
    platform: roh['platform'] as String?,
    language: roh['language'] as String?,
    tz: roh['tz'] as String?,
    app: roh['app'] as String?,
    screen: screen is Map ? (w: screen['w'] as int, h: screen['h'] as int) : null,
  );
}

RegisterGeo? _geo(Object? roh) => roh is Map
    ? RegisterGeo(lat: (roh['lat'] as num).toDouble(), lng: (roh['lng'] as num).toDouble(), acc: (roh['acc'] as num?)?.toDouble())
    : null;

KeckPaymentInput _zahlung(Map<dynamic, dynamic> z) => KeckPaymentInput(
      method: KeckPaymentMethod.values.byName(z['method'] as String),
      amountCents: z['amountCents'] as int,
      tenderedCents: z['tenderedCents'] as int?,
      provider: z['provider'] == null ? null : CreditCardProvider.values.byName(z['provider'] as String),
      providerPaymentId: z['providerPaymentId'] as String?,
      providerData: (z['providerData'] as Map?)?.cast<String, dynamic>(),
      refundOf: z['refundOf'] as String?,
      tipCents: z['tipCents'] as int?,
    );

/// Das Logo eines Druckjobs aus seinen Rasterzeilen zurückgebaut.
DruckLogo _logoAus(Map<dynamic, dynamic> l) {
  final breite = l['width'] as int;
  final hoehe = l['height'] as int;
  final bytes = base64Decode(l['rows'] as String);
  final jeZeile = (breite + 7) >> 3;
  final punkte = Uint8List(breite * hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      if (bytes[y * jeZeile + (x >> 3)] & (0x80 >> (x & 7)) != 0) punkte[y * breite + x] = 1;
    }
  }
  return DruckLogo(
    stufe: LogoStufe.values.firstWhere((s) => s.kuerzel == l['scale']),
    pxBreite: l['pxWidth'] as int,
    pxHoehe: l['pxHeight'] as int,
    raster: LogoRaster(breite: breite, hoehe: hoehe, punkte: punkte),
  );
}

/// Ruft den Endpunkt des Falls über den öffentlichen Client. Liefert `null`,
/// wenn der Fall auf diesem Weg nicht darstellbar ist ([_nichtDieserWeg]).
Future<_Lauf?> _rufe(String endpunkt, Map<String, dynamic> fall) async {
  if (_nichtDieserWeg.containsKey('$endpunkt/${fall['case']}')) return null;
  final p = (fall['params'] as Map).cast<String, dynamic>();
  final lauf = _Lauf();
  final http = _mock(fall, lauf);
  final kasse = p['cashregisterId'] is String ? p['cashregisterId'] as String : 'KASSE1';
  final register = RegisterClient(httpClient: http);
  final transport = _transport(http, kasse);
  final belege = RegisterReceiptClient(transport);
  final drucker = KasseDruckerClient(transport);
  Future<Object?> aufruf() async {
    switch (endpunkt) {
      case 'pairRegisterDevice':
        if (p['code'] != null && p['code'] is! String) throw const _NichtDarstellbar();
        return register.pairRegisterDevice(
          code: _s(p['code']),
          label: p['label'] as String?,
          takeover: p['takeover'] == true,
          client: _clientInfo(p['client']),
          geo: _geo(p['geo']),
        );
      case 'listRegisterUsersForDevice':
        return register.listRegisterUsersForDevice(
            ownerUid: _s(p['ownerUid']), deviceId: _s(p['deviceId']), deviceSecret: _s(p['deviceSecret']));
      case 'listRegisterSessionsForDevice':
        return register.listRegisterSessionsForDevice(
            ownerUid: _s(p['ownerUid']), deviceId: _s(p['deviceId']), deviceSecret: _s(p['deviceSecret']));
      case 'unpairRegisterDevice':
        await register.unpairRegisterDevice(
            ownerUid: _s(p['ownerUid']), deviceId: _s(p['deviceId']), deviceSecret: _s(p['deviceSecret']));
        return true;
      case 'registerUserLogin':
        return register.registerUserLogin(
          ownerUid: _s(p['ownerUid']),
          deviceId: _s(p['deviceId']),
          deviceSecret: _s(p['deviceSecret']),
          userId: _s(p['userId']),
          pin: _s(p['pin']),
          cashregisterId: _s(p['cashregisterId']),
          takeover: p['takeover'] == true,
          takeoverSessionId: p['takeoverSessionId'] as String?,
          client: _clientInfo(p['client']),
          geo: _geo(p['geo']),
        );
      case 'registerPinLogin':
        return register.registerPinLogin(
          ownerUid: _s(p['ownerUid']),
          deviceId: _s(p['deviceId']),
          deviceSecret: _s(p['deviceSecret']),
          pin: _s(p['pin']),
          cashregisterId: _s(p['cashregisterId']),
          takeover: p['takeover'] == true,
          client: _clientInfo(p['client']),
          geo: _geo(p['geo']),
        );
      case 'renewRegisterSession':
        return RegisterSessionClient.aus(transport).renewRegisterSession();
      case 'endRegisterSession':
        await RegisterSessionClient.aus(transport).endRegisterSession();
        return true;
      case 'listMyCashregisters':
        return belege.kassen();
      case 'generateFullReceiptId':
        return belege.volleBelegId(_s(p['receiptId']));
      case 'listMyArticleGroups':
        return belege.artikelgruppen();
      case 'listMyArticles':
        return belege.artikel();
      case 'listMyTipRecipients':
        return belege.tipEmpfaenger();
      case 'getKasseSettings':
        if (p['deviceId'] != null && p['deviceId'] is! String) throw const _NichtDarstellbar();
        return KasseEinstellungenClient(transport, deviceId: _s(p['deviceId'])).laden();
      case 'setMyKasseSettings':
        if (p['business'] is! Map) throw const _NichtDarstellbar();
        return KasseEinstellungenClient(transport, deviceId: '')
            .betriebSpeichern((p['business'] as Map).cast<String, dynamic>());
      case 'setMyRegisterDeviceSettings':
        if (p['device'] is! Map) throw const _NichtDarstellbar();
        return KasseEinstellungenClient(transport, deviceId: _s(p['deviceId']))
            .geraetSpeichern((p['device'] as Map).cast<String, dynamic>());
      case 'setMyKasseLogo':
        final c = KasseEinstellungenClient(transport, deviceId: '');
        if (p['remove'] == true) return c.logoEntfernen();
        if (p['image'] != null && p['image'] is! String) throw const _NichtDarstellbar();
        return c.logoSetzen(_s(p['image']));
      case 'listMyPrinters':
        return drucker.drucker();
      case 'createPrintJob':
        final layout = BelegLayout.fromJson(p['layout']);
        if (layout == null || (p['title'] != null && p['title'] is! String)) throw const _NichtDarstellbar();
        final logoRoh = p['logo'];
        // Ein Logo ohne Raster (scale: 'riesig') baut DruckLogo nicht.
        if (logoRoh is Map && logoRoh['rows'] is! String) throw const _NichtDarstellbar();
        return drucker.druckjobAnlegen(
          printerId: _s(p['printerId']),
          layout: layout,
          receiptId: p['receiptId'] as String?,
          titel: p['title'] as String?,
          quelle: p['source'] as String?,
          logo: p['logo'] is Map ? _logoAus(p['logo'] as Map) : null,
          markeZeigen: p['brand'] == true,
        );
      case 'getPrintJob':
        return drucker.druckjobHolen(printerId: _s(p['printerId']), jobId: _s(p['jobId']));
      case 'createReceipt':
        return belege.verkaufen(
          positionen: [for (final i in (p['items'] as List? ?? const [])) KasseneckItem.fromJson((i as Map).cast())],
          zahlungen: [for (final z in (p['payments'] as List? ?? const [])) _zahlung(z as Map)],
          trinkgeldCents: p['tip'] as int?,
        );
      case 'cancelReceipt':
        return belege.stornieren(
          originalReceiptId: _s(p['originalReceiptId']),
          grund: _s(p['reason']),
          anmerkung: p['note'] as String?,
          positionen: p['items'] == null
              ? null
              : [for (final i in p['items'] as List) (index: (i as Map)['index'] as int, menge: i['quantity'] as int)],
          zahlungen: p['payments'] == null ? null : [for (final z in p['payments'] as List) _zahlung(z as Map)],
        );
    }
    throw StateError('Endpunkt $endpunkt ohne Aufruf');
  }

  try {
    lauf.ergebnis = await aufruf();
  } on _NichtDarstellbar {
    lauf.vorab = true;
  } on KasseneckValidationError catch (e) {
    if (e.kind == 'request' && lauf.log.isEmpty) {
      lauf.vorab = true;
    } else {
      lauf.fehler = e;
    }
  } catch (e) {
    lauf.fehler = e;
  }
  return lauf;
}

class _NichtDarstellbar implements Exception {
  const _NichtDarstellbar();
}

/// Die Parameter des Falls, wie der Client sie senden muss: Positionen der
/// Form v1 (`amount`, `priceOneCents`, `vat`) heißen am Client v2.
Map<String, dynamic> _soll(String endpunkt, Map<String, dynamic> fall) {
  final p = Map<String, dynamic>.from(fall['params'] as Map);
  if (endpunkt == 'createReceipt' && p['items'] is List) {
    p['items'] = [
      for (final i in p['items'] as List)
        {
          'name': i['name'],
          'quantity': i['quantity'] ?? i['amount'],
          'unitPriceCents': i['unitPriceCents'] ?? i['priceOneCents'],
          'vatRate': i['vatRate'] ?? i['vat'],
        },
    ];
  }
  // Das Zeilenmodell geht in der Form von BelegLayout.toJson hinaus: ruleset
  // immer gesetzt, Standardwerte der Zeilen ausgeschrieben. Für ein Layout des
  // Servers (success_logo_qr) ist das dieselbe Form, siehe eigener Test.
  if (endpunkt == 'createPrintJob' && BelegLayout.fromJson(p['layout']) != null) {
    p['layout'] = BelegLayout.fromJson(p['layout'])!.toJson();
  }
  return p;
}

/// Der Storno-Beleg der Codebase kasse ist im Export ein Platzhalter des
/// Selbstaufrufs (ohne Signatur); den ganzen Beleg zeigt storno.json
/// (receipt_v3_test). Hier heißt Erfolg darum: signiert gemeldet, Antwort nicht
/// lesbar, also response_unreadable mit der Kennung, nie ein gewöhnlicher Fehler.
bool _stornoPlatzhalter(String endpunkt, Map<String, dynamic> fall) =>
    endpunkt == 'cancelReceipt' && fall['response']['status'] == 'success';

void _pruefeFall(String endpunkt, Map<String, dynamic> fall, _Lauf lauf) {
  final name = '$endpunkt/${fall['case']}';
  final antwort = fall['response'] as Map<String, dynamic>;
  if (lauf.vorab) {
    expect(lauf.log, isEmpty, reason: '$name: vorab abgewiesen, nichts geht hinaus');
    expect(antwort['status'], 'error', reason: '$name: der Client weist ab, was der Server annimmt');
    return;
  }
  expect(lauf.log, hasLength(1), reason: '$name: genau ein Aufruf');
  expect(lauf.log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/$endpunkt', reason: name);
  final gesendet = Map<String, dynamic>.from(lauf.params);
  final soll = _soll(endpunkt, fall);
  // Der Sitzungs-Transport legt die Kasse zu jeder Nutzlast (wie
  // registerUserAuth im JS-Paket); nennt der Fall sie nicht, zählt sie nicht.
  if (!soll.containsKey('cashregisterId')) gesendet.remove('cashregisterId');
  expect(gesendet, soll, reason: '$name: Parameter wie aufgezeichnet');

  if (_stornoPlatzhalter(endpunkt, fall)) {
    expect(
        lauf.fehler,
        isA<KasseneckApiError>()
            .having((e) => e.code, 'code', 'response_unreadable')
            .having((e) => e.details['receiptId'], 'receiptId', antwort['data']['receipt']['receiptId']),
        reason: name);
    return;
  }
  if (antwort['status'] == 'success') {
    expect(lauf.fehler, isNull, reason: '$name: ${lauf.fehler}');
    expect(lauf.ergebnis, isNotNull, reason: name);
    return;
  }
  final code = antwort['code'] ?? (antwort['data'] as Map?)?['code'];
  expect(lauf.fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', code), reason: name);
  final daten = Map<String, dynamic>.from(antwort['data'] as Map? ?? const {});
  final details = (lauf.fehler as KasseneckApiError).details;
  for (final e in daten.entries) {
    expect(details[e.key], e.value, reason: '$name: details.${e.key}');
  }
  if (_anmeldung.contains(endpunkt)) {
    expect(isRegisterError(lauf.fehler, code as String), isTrue, reason: '$name: $code in registerErrorCodes');
  }
  if (_kassenAufrufe.contains(endpunkt)) {
    expect(isPosError(lauf.fehler, code as String), isTrue, reason: '$name: $code in posErrorCodes');
  }
}

void main() {
  group('jeder Fall des Kassenwegs', () {
    for (final endpunkt in [..._anmeldung, ..._kassenAufrufe, ..._weitere]) {
      test(endpunkt, () async {
        var gelaufen = 0;
        for (final fall in _faelle(endpunkt)) {
          final lauf = await _rufe(endpunkt, fall);
          if (lauf == null) continue;
          _pruefeFall(endpunkt, fall, lauf);
          gelaufen++;
        }
        expect(gelaufen, greaterThan(0));
      });
    }

    test('die Liste der nicht darstellbaren Fälle nennt nur vorhandene Fälle, keinen Erfolg des Kassenwegs', () {
      for (final eintrag in _nichtDieserWeg.keys) {
        final [endpunkt, name] = eintrag.split('/');
        final fall = _fall(endpunkt, name);
        if (fall['response']['status'] == 'success') {
          // Ein Erfolg, den dieser Weg nicht senden kann, gehört einem anderen
          // Anmeldeweg (API-Schlüssel, Panel).
          expect(fall['caller'], isNot(startsWith('register_user')), reason: eintrag);
        }
      }
    });

    test('alle 25 Endpunkte des Vertrags sind abgedeckt (Belegwelt in receipt_v3_test)', () {
      final hier = {..._anmeldung, ..._kassenAufrufe, ..._weitere};
      final belegwelt = {'listMyReceipts', 'getReceipt', 'sendReceiptEmail'};
      expect({...hier, ...belegwelt}, (_vertrag['calls']['pos'] as List).toSet());
    });
  });

  group('Codes am Vertrag', () {
    test('registerErrorCodes und posErrorCodes sind die Listen aus surface.json', () {
      expect(registerErrorCodes, _vertrag['registerErrorCodes']);
      expect(posErrorCodes, _vertrag['pos']['posErrorCodes']);
      expect(printJobStatuses, _vertrag['pos']['printJobStatuses']);
      expect(printJobSources, _vertrag['pos']['printJobSources']);
      expect(quantityRules, _vertrag['pos']['quantityRules']);
    });

    test('am Code, nie am Text: derselbe Text mit anderem Code ist ein anderer Fehler', () {
      const belegt = KasseneckApiError('registerPinLogin', 'Kasse wird gerade auf „Tablet" verwendet.',
          code: 'cashregister_in_use', details: {'deviceLabel': 'Tablet', 'takeoverAllowed': true});
      const anders = KasseneckApiError('registerPinLogin', 'Kasse wird gerade auf „Tablet" verwendet.',
          code: 'login_failed');
      expect(isRegisterError(belegt, 'cashregister_in_use'), isTrue);
      expect(isRegisterError(anders, 'cashregister_in_use'), isFalse);
      expect(isRegisterError(const KasseneckApiError('x', 'y', code: 'etwas_neues')), isFalse);
      expect(isRegisterError(Exception('cashregister_in_use')), isFalse);
      expect(registerErrorDetails(belegt).deviceLabel, 'Tablet');
      expect(registerErrorDetails(belegt).takeoverAllowed, isTrue);
      expect(isPosError(const KasseneckApiError('x', 'y', code: 'logo_too_large'), 'logo_too_large'), isTrue);
    });

    test('Angaben einer Abweisung als Daten: Sperre, Standort, Lizenzen; fehlend = null', () async {
      final sperre = await _rufe('registerPinLogin', _fallMitCode('registerPinLogin', 'too_many_attempts'));
      expect(registerErrorDetails(sperre!.fehler).retryAfterSec, isA<num>());
      final lizenzen = await _rufe('pairRegisterDevice', _fall('pairRegisterDevice', 'license_full'));
      final d = registerErrorDetails(lizenzen!.fehler);
      expect([d.pairedDevices, d.licenses], [4, 2]);
      expect(d.deviceLabel, isNull);
      expect(d.retryAfterSec, isNull);
    });

    test('Feldfehler einer validation-Antwort', () async {
      final lauf = await _rufe('createPrintJob', _fall('createPrintJob', 'layout_paper'));
      expect(posFieldErrors(lauf!.fehler), [const FieldError('layout', 'Ungültiger Wert.')]);
      expect(posFieldErrors(Exception('x')), isEmpty);
    });
  });

  group('Anmeldung: gelesene Modelle', () {
    test('Kopplung: companyName, cashregisterLabel, testEnvironment; client.app geht mit', () async {
      final lauf = await _rufe('pairRegisterDevice', _fall('pairRegisterDevice', 'success'));
      final g = lauf!.ergebnis as PairedRegisterDevice;
      expect([g.companyName, g.cashregisterLabel, g.testEnvironment], ['Café Welt', 'Theke 1', false]);
      expect(lauf.params['client']['app'], 'kasse-app/1.0.3+34');
      final test = await _rufe('pairRegisterDevice', _fall('pairRegisterDevice', 'success_test_environment'));
      expect((test!.ergebnis as PairedRegisterDevice).testEnvironment, isTrue);
    });

    test('Benutzerliste: Modus, Regel, Belegkopf, Kasse, Einstellungen englisch', () async {
      final lauf = await _rufe('listRegisterUsersForDevice', _fall('listRegisterUsersForDevice', 'success_select'));
      final u = lauf!.ergebnis as RegisterDeviceUsers;
      expect(u.loginMode, RegisterLoginMode.selectUser);
      expect([u.policy?.length, u.policy?.charset], [4, 'digits']);
      expect(u.users.where((b) => b.pinPolicyOutdated).length, 6);
      expect(u.receiptHeader?['company'], 'Café Welt');
      expect(u.cashregister?.ready, isTrue);
      expect(u.settings.betrieb.theme, KasseStil.night);
      expect(u.settings.betrieb.color, '#222222');
      expect(unknownPosSettingValues(u.settings), isEmpty);

      final stillgelegt =
          await _rufe('listRegisterUsersForDevice', _fall('listRegisterUsersForDevice', 'cashregister_decommissioned'));
      final k = (stillgelegt!.ergebnis as RegisterDeviceUsers).cashregister!;
      expect(k.ready, isFalse);
      expect(k.reason, contains('außer Betrieb'));

      final nurPin = await _rufe('listRegisterUsersForDevice', _fall('listRegisterUsersForDevice', 'success_only_pin'));
      expect((nurPin!.ergebnis as RegisterDeviceUsers).loginMode, RegisterLoginMode.pin);
      final sperre =
          await _rufe('listRegisterUsersForDevice', _fall('listRegisterUsersForDevice', 'legacy_without_cashregister_with_lock'));
      expect((sperre!.ergebnis as RegisterDeviceUsers).locationLock, isTrue);
    });

    test('ohne gespeicherte Einstellungen: der Stand ist der Standard des Vertrags', () async {
      // Wie npm fixtures/kasse-settings-standard.json: business aus dem Konto
      // ohne Einstellungen, device aus einem unbekannten Gerät.
      final soll = jsonDecode(File('test/fixtures/vertrag/pos-settings-defaults.json').readAsStringSync());
      final konto =
          await _rufe('listRegisterUsersForDevice', _fall('listRegisterUsersForDevice', 'account_without_settings'));
      expect((konto!.ergebnis as RegisterDeviceUsers).settings.toJson()['business'], soll['business']);
      final geraet = await _rufe('getKasseSettings', _fall('getKasseSettings', 'cashier_unknown_device'));
      expect((geraet!.ergebnis as KasseSettings).toJson()['device'], soll['device']);
    });

    test('Sitzungen: own, deviceLabel', () async {
      final lauf = await _rufe('listRegisterSessionsForDevice', _fall('listRegisterSessionsForDevice', 'success_select'));
      final s = lauf!.ergebnis as RegisterSessionsStand;
      expect(s.licenses, 5);
      expect(s.sessions.map((x) => x.own), [false, true]);
      expect(s.sessions.first.deviceLabel, 'Tablet vorne');
    });
  });

  group('B2: ein mit 9.x gekoppeltes Gerät', () {
    // So legt die Flutter-Kasse (9.x) ihren Gerätesatz ab (lib/geraet.dart,
    // GeraeteAblage): deutsche Anzeigefelder, testUmgebung. Das Paket liest
    // davon nur ownerUid, deviceId, deviceSecret und cashregisterId.
    final gespeichert = jsonDecode(jsonEncode({
      'ownerUid': 'kw_betrieb1',
      'deviceId': 'dev_pin',
      'deviceSecret': 'EXAMPLEB59E65C4AAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'testUmgebung': false,
      'cashregisterId': 'KASSE1',
      'betrieb': 'Café Welt',
      'kasse': 'Theke 1',
    })) as Map<String, dynamic>;

    test('Benutzerliste und PIN-Anmeldung ohne neue Kopplung, gesendet nur die Geräteangaben', () async {
      final fall = _fallErfolg('registerPinLogin');
      final lauf = _Lauf();
      final register = RegisterClient(httpClient: _mock(fall, lauf));
      final sitzung = await register.registerPinLogin(
        ownerUid: gespeichert['ownerUid'] as String,
        deviceId: gespeichert['deviceId'] as String,
        deviceSecret: gespeichert['deviceSecret'] as String,
        pin: '1234',
        cashregisterId: gespeichert['cashregisterId'] as String,
      );
      expect(sitzung.sessionId, isNotEmpty);
      expect(lauf.params.keys.toSet(), {'ownerUid', 'deviceId', 'deviceSecret', 'pin', 'cashregisterId'});

      final liste = _Lauf();
      final users = await RegisterClient(httpClient: _mock(_fall('listRegisterUsersForDevice', 'success_only_pin'), liste))
          .listRegisterUsersForDevice(
        ownerUid: gespeichert['ownerUid'] as String,
        deviceId: gespeichert['deviceId'] as String,
        deviceSecret: gespeichert['deviceSecret'] as String,
      );
      expect(users.loginMode, RegisterLoginMode.pin);
      expect(liste.params, {
        'ownerUid': gespeichert['ownerUid'],
        'deviceId': gespeichert['deviceId'],
        'deviceSecret': gespeichert['deviceSecret'],
      });
    });

    test('zwischengespeicherte Kacheln der Version 9.x lesen sich weiter', () {
      final a = KasseArtikel.aus({
        'id': 'a1', 'name': 'Wurst', 'unitPriceCents': 1290, 'vatRate': 10, 'unit': 'kg', 'groupId': 'g1',
        'kasse': {'sichtbar': false, 'sort': 3}, 'active': true,
        'mengenregel': 'dezimal', 'mengeFragen': true, 'maxMenge': 2.5,
      });
      expect([a.sichtbar, a.sort, a.mengenregel, a.mengeFragen, a.maxMenge], [false, 3, Mengenregel.decimal, true, 2.5]);
      // Neu geschrieben wird die Drahtform.
      final neu = a.toJson();
      expect(neu['tile'], {'visible': false, 'sort': 3});
      expect(neu['quantityRule'], 'decimal');
      expect(KasseArtikel.aus(neu).toJson(), neu);
    });
  });

  group('Kassen-Aufrufe: gelesene Modelle', () {
    test('Artikel: tile, quantityRule, revenueGroupId', () async {
      for (final name in ['success_cashregister', 'success_owner', 'module_inventory']) {
        final fall = _fall('listMyArticles', name);
        final lauf = await _rufe('listMyArticles', fall);
        final artikel = lauf!.ergebnis as List<KasseArtikel>;
        final roh = (fall['response']['data']['articles'] as List).cast<Map<String, dynamic>>();
        expect(artikel.length, roh.length);
        for (final (i, a) in artikel.indexed) {
          final r = roh[i];
          expect(a.id, r['id']);
          expect(a.sichtbar, (r['tile'] as Map?)?['visible'] != false, reason: a.id);
          expect(a.sort, (r['tile'] as Map?)?['sort'] ?? 0);
          expect(a.mengenregel?.name, r['quantityRule']);
          expect(a.mengeFragen, r['askQuantity']);
          expect(a.erloesgruppeId, r['revenueGroupId']);
        }
      }
    });

    test('Einstellungen des Kontos: nacht wird night, Gerät mit eigenen Tasten', () async {
      final lauf = await _rufe('getKasseSettings', _fall('getKasseSettings', 'manager_with_device'));
      final e = lauf!.ergebnis as KasseSettings;
      final roh = _fall('getKasseSettings', 'manager_with_device')['response']['data'];
      expect(e.toJson(), {'business': roh['business'], 'device': roh['device']},
          reason: 'die Antwort ist schon gemischt; gelesen und zurückgeschrieben ergibt sie sich selbst');
    });

    test('jede Einstellungs-Antwort liest sich verlustfrei', () async {
      for (final ep in ['getKasseSettings', 'setMyKasseSettings', 'setMyRegisterDeviceSettings']) {
        for (final fall in _faelle(ep).where((f) => f['response']['status'] == 'success')) {
          final lauf = await _rufe(ep, fall);
          final daten = fall['response']['data'] as Map<String, dynamic>;
          final json = switch (lauf!.ergebnis) {
            final KasseSettings s => s.toJson(),
            final KasseSettingsBetrieb b => {'business': b.toJson()},
            final KasseSettingsGeraet g => {'device': g.toJson()},
            _ => throw StateError('${fall['case']}'),
          };
          for (final teil in json.keys) {
            expect(json[teil], daten[teil], reason: '$ep/${fall['case']} $teil');
          }
        }
      }
    });

    test('Logo: Adresse bzw. leer nach dem Entfernen', () async {
      expect((await _rufe('setMyKasseLogo', _fall('setMyKasseLogo', 'success_png')))!.ergebnis, startsWith('https://'));
      expect((await _rufe('setMyKasseLogo', _fall('setMyKasseLogo', 'remove')))!.ergebnis, '');
    });

    test('Drucker: Felder englisch, Abhol-Adresse nur für den Chef', () async {
      final kassier = (await _rufe('listMyPrinters', _fall('listMyPrinters', 'cashier_without_url')))!.ergebnis
          as List<NetworkPrinter>;
      final d = kassier.single;
      expect([d.id, d.name, d.kind, d.paperSize, d.active, d.printerSerial], ['dr_theke', 'Theke', 'epson-sdp', 'mm80', true, 'TM-T20']);
      expect(d.lastResult?.success, isTrue);
      expect(d.lastSeenAt, 1790409595000);
      expect(d.sdpUrl, isNull);
      final chef = (await _rufe('listMyPrinters', _fall('listMyPrinters', 'manager_with_url')))!.ergebnis
          as List<NetworkPrinter>;
      expect(chef.single.sdpUrl, startsWith('https://'));
    });

    test('Druckjob mit Logo und QR: Layout des Servers und Logo-Raster gehen unverändert hinaus', () async {
      final fall = _fall('createPrintJob', 'success_logo_qr');
      final lauf = await _rufe('createPrintJob', fall);
      // Ohne Umweg über _soll: das Layout wie aufgezeichnet, die Rasterzeilen
      // aus dem zurückgebauten Logo neu gepackt.
      expect(lauf!.params..remove('cashregisterId'), fall['params']);
      final job = lauf.ergebnis as PrintJob;
      expect([job.jobId, job.status], ['auto1', 'pending']);
    });

    test('Druckjob-Stand: gedruckt, offen, unbekannt beendet die Abfrage', () async {
      final gedruckt = (await _rufe('getPrintJob', _fall('getPrintJob', 'success_printed')))!.ergebnis as PrintJob;
      expect(gedruckt.status, 'printed');
      expect(gedruckt.result?.success, isTrue);
      expect(isPrintJobFinished(gedruckt.status), isTrue);
      final offen = (await _rufe('getPrintJob', _fall('getPrintJob', 'success_open')))!.ergebnis as PrintJob;
      expect([offen.status, offen.result, isPrintJobFinished(offen.status)], ['pending', null, false]);

      final lauf = _Lauf();
      final fremd = await KasseDruckerClient(_transport(
              _mock({
                'headers': {'Kasseneck-Api-Version': 'v3'},
                'httpStatus': 200,
                'response': {'status': 'success', 'data': {'jobId': 'j', 'status': 'cancelled'}},
              }, lauf),
              'KASSE1'))
          .druckjobHolen(printerId: 'dr_theke', jobId: 'j');
      expect(fremd.status, printJobStatusUnknown);
      expect(isPrintJobFinished(fremd.status), isTrue, reason: 'nie bis zum Zeitlimit abfragen');
    });

    test('Kassenliste und Volltext-Belegnummer', () async {
      final kassen = (await _rufe('listMyCashregisters', _fall('listMyCashregisters', 'manager')))!.ergebnis
          as List<KassenEintrag>;
      expect(kassen.first.id, 'KASSE1');
      expect(kassen.first.onboarding.startReceiptCreated, isTrue);
      expect(kassen.first.token, isNull, reason: 'Kassen-Benutzer bekommen keinen Kassen-Token');
      final owner = (await _rufe('listMyCashregisters', _fall('listMyCashregisters', 'owner')))!.ergebnis
          as List<KassenEintrag>;
      expect(owner.map((k) => k.id), ['KASSE1', 'KASSE2', 'KASSE3', 'KASSE4']);
      expect(owner.map((k) => k.decommissioned), [false, true, false, false]);
      expect(owner.first.token, isNotNull, reason: 'der Inhaber bekommt ihn');
      expect((await _rufe('generateFullReceiptId', _fall('generateFullReceiptId', 'success_cashregister')))!.ergebnis,
          isA<String>());
    });
  });

  group('Verkauf und Storno am Kassenweg', () {
    test('Verkauf: payments wie im Fall, Beleg mit Testkennzeichen der Antwort', () async {
      final lauf = await _rufe('createReceipt', _fall('createReceipt', 'sale_payments'));
      final beleg = lauf!.ergebnis as KasseneckReceipt;
      expect(lauf.params.containsKey('paymentMethod'), isFalse);
      expect(beleg.receiptId, isNotEmpty);
    });

    test('Storno der Testkasse trägt TESTKASSE, auch ohne Kennzeichen in der Antwort', () async {
      // Der ganze Storno-Beleg des Kanals app aus storno.json (der Export des
      // Kassenwegs trägt nur einen Platzhalter).
      final storno = jsonDecode(File('test/fixtures/vertrag/v3/antworten/storno.json').readAsStringSync()) as Map;
      final ganz = (storno['cases'] as List).cast<Map<String, dynamic>>().firstWhere(
          (f) => f['channel'] == 'app' && f['response']['status'] == 'success');
      final fall = {..._fall('cancelReceipt', 'success_full'), 'response': ganz['response'], 'headers': ganz['headers'] ?? const {'Kasseneck-Api-Version': 'v3'}, 'httpStatus': 200};
      final original = (ganz['params'] as Map)['originalReceiptId'] as String;
      final lauf = _Lauf();
      final client = RegisterReceiptClient(_transport(_mock(fall, lauf), 'KASSE1'), testEnvironment: true);
      final ergebnis = await client.stornieren(originalReceiptId: original, grund: 'input_error');
      expect(ergebnis.beleg.testCashregister, isTrue);

      // Ohne Test-Umgebung gelten die Kennzeichen des Originals.
      final ohne = RegisterReceiptClient(_transport(_mock(fall, _Lauf()), 'KASSE1'));
      final normal = await ohne.stornieren(originalReceiptId: original, grund: 'input_error');
      expect(normal.beleg.testCashregister, isFalse);
    });

    test('Storno-Ausgang unklar bleibt unklar (cancellation_outcome_unknown)', () async {
      final lauf = await _rufe('cancelReceipt', _fall('cancelReceipt', 'self_call_without_response'));
      expect(lauf!.fehler, isA<KasseneckApiError>().having((e) => e.outcome, 'outcome', ErrorOutcome.unknown));
      expect(isOutcomeUnknown(lauf.fehler), isTrue);
    });

    test('Erfolg mit unlesbarer Antwort: response_unreadable, genau ein Aufruf', () async {
      for (final ep in ['createReceipt', 'cancelReceipt']) {
        final fall = Map<String, dynamic>.from(_fall(ep, ep == 'createReceipt' ? 'sale_payments' : 'success_full'));
        fall['response'] = {'status': 'success', 'data': {'receipt': {'receiptId': 'KASSE1-ID-9'}}};
        final lauf = await _rufe(ep, fall);
        expect(lauf!.log, hasLength(1));
        expect(lauf.fehler, isA<KasseneckApiError>()
            .having((e) => e.code, 'code', 'response_unreadable')
            .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)
            .having((e) => e.details['receiptId'], 'receiptId', 'KASSE1-ID-9'), reason: ep);
      }
    });
  });

  group('Einstellungen: Prüfung vor dem Senden', () {
    Future<(Object?, _Lauf)> schreiben(String teil, Map<String, dynamic> block) async {
      final lauf = _Lauf();
      final c = KasseEinstellungenClient(
          _transport(_mock(_fallErfolg(teil == 'business' ? 'setMyKasseSettings' : 'setMyRegisterDeviceSettings'), lauf), 'KASSE1'),
          deviceId: 'dev_pin');
      try {
        await (teil == 'business' ? c.betriebSpeichern(block) : c.geraetSpeichern(block));
        return (null, lauf);
      } catch (e) {
        return (e, lauf);
      }
    }

    Matcher abgewiesen(String text) =>
        isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request').having((e) => e.reason, 'reason', contains(text));

    test('unbekannter Schlüssel, auch ein deutscher aus 0.x', () async {
      final (f, lauf) = await schreiben('business', {'stil': 'night'});
      expect(f, abgewiesen('business.stil: unbekanntes Feld'));
      expect(lauf.log, isEmpty);
    });

    test('Wert der inneren Form 0.x und unbekannter Wert mit Hinweis', () async {
      expect((await schreiben('business', {'theme': 'nacht'})).$1, abgewiesen('innere Form 0.x'));
      expect((await schreiben('business', {'theme': 'sepia'})).$1, abgewiesen('posSettingsChanges'));
      expect((await schreiben('device', {'layout': 'rechts'})).$1, abgewiesen('device.layout'));
    });

    test('vatRates ohne einen Satz an geht nicht hinaus', () async {
      expect((await schreiben('business', {'vatRates': {'20': false}})).$1, abgewiesen('business.vatRates'));
    });

    test('Tasten: unbekannte Aktion und Doppelbelegung', () async {
      expect((await schreiben('device', {'shortcuts': {'kassieren': ['F9']}})).$1,
          abgewiesen('device.shortcuts.kassieren: unbekannte Aktion'));
      final karte = {...kasseTastenStandard, 'card': ['Mod+B']};
      expect((await schreiben('device', {'shortcuts': karte})).$1, abgewiesen('schon belegt'));
      // Wird cash zugleich frei, geht die ganze Karte hinaus.
      final (f, lauf) = await schreiben('device', {'shortcuts': {...karte, 'cash': ['F2']}});
      expect(f, isNull);
      expect(lauf.params['device']['shortcuts'], {...karte, 'cash': ['F2']});
    });

    test('null zählt als nicht gesendet', () async {
      final (f, lauf) = await schreiben('business', {'stil': null, 'theme': 'night'});
      expect(f, isNull);
      expect(lauf.params['business'], {'theme': 'night'});
    });
  });

  group('Nachbesserung Runde 1', () {
    test('F2: Anmeldung abgelaufen, andere Kasse, Modul aus kommen am Verkauf mit Code und Daten an', () async {
      for (final (name, code) in [
        ('without_token', 'unauthorized'),
        ('session_other_cashregister', 'session_other_cashregister'),
        ('module_off', 'module_inactive'),
      ]) {
        final fall = _faelle('createReceipt').firstWhere((f) => f['case'] == name);
        final lauf = await _rufe('createReceipt', fall);
        expect(lauf!.log, hasLength(1), reason: name);
        expect(lauf.params['payments'], isNotEmpty, reason: name);
        expect(lauf.params.containsKey('paymentMethod'), isFalse, reason: name);
        expect(lauf.fehler, isA<KasseneckApiError>()
            .having((e) => e.code, 'code', code)
            .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)
            .having((e) => e.details['code'], 'details.code', code), reason: name);
      }
    });

    test('F4: Verkauf trägt TESTSIGNATUR der Antwort, Storno übernimmt sie vom Original', () async {
      final verkauf = await _rufe('createReceipt', _fall('createReceipt', 'sale_payments'));
      final original = verkauf!.ergebnis as KasseneckReceipt;
      expect(original.testSignature, isTrue, reason: 'sale_payments trägt testSignature');

      final storno = jsonDecode(File('test/fixtures/vertrag/v3/antworten/storno.json').readAsStringSync()) as Map;
      final ganz = (storno['cases'] as List).cast<Map<String, dynamic>>().firstWhere(
          (f) => f['channel'] == 'app' && f['response']['status'] == 'success');
      final fall = {
        'headers': const {'Kasseneck-Api-Version': 'v3'},
        'httpStatus': 200,
        'response': ganz['response'],
      };
      Future<KasseneckReceipt> stornieren({required bool testKasse}) async {
        original.testCashregister = testKasse;
        final client = RegisterReceiptClient(_transport(_mock(fall, _Lauf()), 'KASSE1'));
        final e = await client.stornieren(originalReceiptId: original.receiptId, grund: 'input_error', original: original);
        return e.beleg;
      }

      final mitSignatur = await stornieren(testKasse: false);
      expect(mitSignatur.testSignature, isTrue, reason: 'TESTSIGNATUR des Originals');
      expect(mitSignatur.testCashregister, isFalse);
      final testKasse = await stornieren(testKasse: true);
      expect(testKasse.testCashregister, isTrue, reason: 'TESTKASSE des Originals');
      expect(testKasse.testSignature, isFalse, reason: 'TESTKASSE verdrängt TESTSIGNATUR');
    });

    test('F6: shortcuts nur als ganze Karte, sonst geht nichts hinaus', () async {
      final lauf = _Lauf();
      final c = KasseEinstellungenClient(_transport(_mock(_fallErfolg('setMyRegisterDeviceSettings'), lauf), 'KASSE1'),
          deviceId: 'dev_pin');
      await expectLater(
          c.geraetSpeichern({'shortcuts': {'cash': ['Mod+K']}}),
          throwsA(isA<KasseneckValidationError>()
              .having((e) => e.kind, 'kind', 'request')
              .having((e) => e.reason, 'reason', contains('ganze Karte'))));
      expect(lauf.log, isEmpty);
      // Über posSettingsChanges geht bei einer Tastenänderung die ganze Karte,
      // und eine Doppelbelegung mit einer gespeicherten Taste fällt auf.
      const vorher = KasseSettingsGeraet();
      final doppelt = posSettingsChanges(vorher.toJson(), vorher.mit({'shortcuts': {'cash': ['Mod+K']}}).toJson());
      await expectLater(c.geraetSpeichern(doppelt),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('Mod+K schon belegt'))));
      expect(lauf.log, isEmpty);
    });

    test('F7: fehlende Druckerliste oder fehlende Job-Kennung ist ein Antwortfehler', () async {
      Future<Object?> mit(String ep, Map<String, dynamic> daten, Future<Object?> Function(KasseDruckerClient) rufen) async {
        final c = KasseDruckerClient(_transport(
            _mock({
              'headers': const {'Kasseneck-Api-Version': 'v3'},
              'httpStatus': 200,
              'response': {'status': 'success', 'data': daten},
            }, _Lauf()),
            'KASSE1'));
        try {
          return await rufen(c);
        } catch (e) {
          return e;
        }
      }

      final layout = BelegLayout.fromJson(_fall('createPrintJob', 'success_cashregister')['params']['layout'])!;
      final antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
      expect(await mit('listMyPrinters', {}, (c) => c.drucker()), antwortfehler);
      expect(await mit('listMyPrinters', {'printers': []}, (c) => c.drucker()), isEmpty);
      expect(await mit('createPrintJob', {'status': 'pending'}, (c) => c.druckjobAnlegen(printerId: 'dr', layout: layout)),
          antwortfehler);
      expect(await mit('createPrintJob', {'jobId': '', 'status': 'pending'},
          (c) => c.druckjobAnlegen(printerId: 'dr', layout: layout)), antwortfehler);
      expect(await mit('getPrintJob', {'status': 'printed'}, (c) => c.druckjobHolen(printerId: 'dr', jobId: 'j')),
          antwortfehler);
    });

    group('F8: Feldmengen der Erfolgsantworten', () {
      // Pfad in der Antwort -> Felder, die das Modell liest, und Felder, die
      // der Vertrag heute nicht in jedem Fall zeigt (optional).
      final modelle = <String, (Set<String>, Set<String>)>{
        'pairRegisterDevice': (PairedRegisterDevice.felder, const {}),
        'listRegisterUsersForDevice': (RegisterDeviceUsers.felder, const {}),
        'listRegisterUsersForDevice.users[]': (RegisterUserSummary.felder, const {}),
        'listRegisterUsersForDevice.policy': (RegisterPinPolicy.felder, const {}),
        'listRegisterUsersForDevice.cashregister': (RegisterCashregisterState.felder, const {}),
        'listRegisterSessionsForDevice': (RegisterSessionsStand.felder, const {}),
        'listRegisterSessionsForDevice.sessions[]': (RegisterSession.felder, const {}),
        'registerUserLogin': (RegisterUserSession.felder, const {}),
        'registerUserLogin.user': (RegisterUser.felder, const {}),
        'registerPinLogin': (RegisterUserSession.felder, const {}),
        'registerPinLogin.user': (RegisterUser.felder, const {}),
        'renewRegisterSession': (const {'expiresAt'}, const {}),
        'listMyCashregisters': (const {'cashregisters'}, const {}),
        'listMyCashregisters.cashregisters[]': (KassenEintrag.felder, const {}),
        'listMyCashregisters.cashregisters[].onboarding': (KassenInbetriebnahme.felder, const {}),
        'generateFullReceiptId': (const {'fullReceiptId'}, const {}),
        'listMyArticleGroups': (const {'groups'}, const {}),
        'listMyArticleGroups.groups[]': (Artikelgruppe.felder, const {'symbol', 'vatRate'}),
        'listMyArticles': (const {'articles'}, const {}),
        'listMyArticles.articles[]': (KasseArtikel.felder, const {'unitPriceCents', 'quantityRule', 'askQuantity', 'maxQuantity'}),
        'listMyArticles.articles[].tile': (KasseArtikel.kachelFelder, const {}),
        'setMyKasseLogo': (const {'logoImage'}, const {}),
        'listMyPrinters': (const {'printers'}, const {}),
        'listMyPrinters.printers[]': (NetworkPrinter.felder, const {}),
        'listMyPrinters.printers[].lastResult': (PrintResult.felder, const {'status'}),
        'createPrintJob': (PrintJob.felder, const {'createdAt', 'sentAt', 'result'}),
        'getPrintJob': (PrintJob.felder, const {}),
        'getPrintJob.result': (PrintResult.felder, const {}),
        'listMyTipRecipients': (const {'recipients'}, const {}),
        'listMyTipRecipients.recipients[]': (KeckTipPerson.felder, const {}),
      };
      // Ohne Nutzlast, die ein Modell liest: Bestätigungen (ok, id).
      const ohneModell = {'endRegisterSession', 'unpairRegisterDevice'};
      // Rohdaten bzw. eigene Prüfung: Einstellungen (verlustfrei getestet),
      // Belegkopf (Rohdaten), Rechte (RegisterUserPerms kennt jeden Schlüssel).
      const roh = {'settings', 'receiptHeader', 'perms', 'business', 'device'};
      // Einstellungen: der Test „jede Einstellungs-Antwort liest sich verlustfrei“.
      const einstellungen = {'getKasseSettings', 'setMyKasseSettings', 'setMyRegisterDeviceSettings'};

      Map<String, Set<String>> gesendet() {
        final pfade = <String, Set<String>>{};
        void lauf(String pfad, Object? v) {
          if (v is Map) {
            (pfade[pfad] ??= {}).addAll(v.keys.cast<String>());
            for (final e in v.entries) {
              if (!roh.contains(e.key)) lauf('$pfad.${e.key}', e.value);
            }
          } else if (v is List) {
            for (final x in v) {
              lauf('$pfad[]', x);
            }
          }
        }

        for (final ep in [..._anmeldung, ..._kassenAufrufe, 'listMyCashregisters', 'generateFullReceiptId']) {
          if (ohneModell.contains(ep) || einstellungen.contains(ep)) continue;
          for (final f in _faelle(ep).where((f) => f['response']['status'] == 'success')) {
            lauf(ep, f['response']['data']);
          }
        }
        return pfade;
      }

      test('jedes gesendete Feld liest ein Modell, jedes gelesene Feld sendet der Vertrag', () {
        final pfade = gesendet();
        expect(pfade.keys.toSet(), modelle.keys.toSet(), reason: 'jede Sicht hat ein Modell');
        for (final e in modelle.entries) {
          final (felder, optional) = e.value;
          final da = pfade[e.key]!;
          expect(da.difference(felder), isEmpty, reason: '${e.key}: gesendet, aber nicht gelesen');
          expect(felder.difference(da).difference(optional), isEmpty, reason: '${e.key}: gelesen, aber nie gesendet');
        }
      });

      test('die Modelle mit öffentlichem Leser lesen genau ihre Felder', () {
        Set<String> gelesen(Map<String, dynamic> roh, void Function(Map<String, dynamic>) lesen) {
          final spur = <String>{};
          lesen(_Mitschreiber(roh, '', spur));
          return spur;
        }

        final beispiele = <(Set<String>, Map<String, dynamic>, void Function(Map<String, dynamic>))>[
          (
            {...KasseArtikel.felder, for (final k in KasseArtikel.kachelFelder) 'tile.$k'},
            {for (final f in KasseArtikel.felder) f: null, 'tile': {'visible': true, 'sort': 1}},
            KasseArtikel.aus,
          ),
          (Artikelgruppe.felder, {for (final f in Artikelgruppe.felder) f: null}, Artikelgruppe.aus),
          (
            {...NetworkPrinter.felder, for (final k in PrintResult.felder) 'lastResult.$k'},
            {for (final f in NetworkPrinter.felder) f: null, 'lastResult': {for (final k in PrintResult.felder) k: null}},
            NetworkPrinter.aus,
          ),
          (
            {...KassenEintrag.felder, for (final k in KassenInbetriebnahme.felder) 'onboarding.$k'},
            {for (final f in KassenEintrag.felder) f: null, 'onboarding': {for (final k in KassenInbetriebnahme.felder) k: null}},
            KassenEintrag.aus,
          ),
          (KeckTipPerson.felder, {for (final f in KeckTipPerson.felder) f: null}, KeckTipPerson.aus),
        ];
        for (final (soll, roh, lesen) in beispiele) {
          expect(gelesen(roh, lesen), soll);
        }
      });
    });

    group('F1: mit() weist unbekannte und deutsche Schlüssel laut ab', () {
      test('das Beispiel des Reviews: qrModus statt qrMode', () {
        const g = KasseSettingsGeraet();
        expect(() => g.mit({'qrModus': 'raster'}),
            throwsA(isA<ArgumentError>().having((e) => e.message, 'message', allOf(contains('device.qrModus'), contains('qrMode')))));
        expect(g.mit({'qrMode': 'raster'}).qrMode, KasseQrModus.raster);
      });

      test('unbekannter Schlüssel, deutscher Wert, deutsche Tasten-Aktion', () {
        const b = KasseSettingsBetrieb();
        expect(() => b.mit({'stil': 'night'}), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('business.stil'))));
        expect(() => b.mit({'gibtsnicht': 1}), throwsA(isA<ArgumentError>()));
        expect(() => b.mit({'theme': 'nacht'}), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('night'))));
        expect(() => const KasseSettingsGeraet().mit({'shortcuts': {'bar': ['F2']}}),
            throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('cash'))));
      });

      test('ein unbekannter englischer Wert bleibt erlaubt (künftiger Wert des Servers)', () {
        expect(const KasseSettingsBetrieb().mit({'theme': 'sepia'}).fremdeWerte, {'theme': 'sepia'});
      });
    });
  });
}

Map<String, dynamic> _fallMitCode(String endpunkt, String code) => _faelle(endpunkt)
    .firstWhere((f) => f['response']['code'] == code || (f['response']['data'] as Map?)?['code'] == code);

Map<String, dynamic> _fallErfolg(String endpunkt) =>
    _faelle(endpunkt).firstWhere((f) => f['response']['status'] == 'success');

/// Eine Map, die mitschreibt, welche Schlüssel gelesen werden (auch in
/// verschachtelten Maps, als `aussen.innen`).
class _Mitschreiber extends MapBase<String, dynamic> {
  _Mitschreiber(this._innen, this._vorsilbe, this._spur);

  final Map<String, dynamic> _innen;
  final String _vorsilbe;
  final Set<String> _spur;

  @override
  dynamic operator [](Object? key) {
    _spur.add('$_vorsilbe$key');
    final wert = _innen[key];
    return wert is Map ? _Mitschreiber(Map<String, dynamic>.from(wert), '$_vorsilbe$key.', _spur) : wert;
  }

  @override
  void operator []=(String key, dynamic value) => _innen[key] = value;

  @override
  void clear() => _innen.clear();

  @override
  Iterable<String> get keys => _innen.keys;

  @override
  dynamic remove(Object? key) => _innen.remove(key);
}
