import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Schicht, Kassenstand und Lade-Protokoll an der Kasse (seit 11.1), Zwilling
/// von `pos/schicht.ts` im npm-Paket 1.9.0: die sechs Aufrufe gegen
/// `v3/antworten/kasse.json` (dass jeder Fall mit seinen Parametern hinausgeht
/// und sein Code ankommt, prueft auch `kasse_v3_test.dart`), die Blindzaehlung,
/// der Ausgang nach einem Zeitlimit und die Lade am Beleg und am Geraet.

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _endpunkte = _json('test/fixtures/vertrag/v3/antworten/kasse.json')['endpoints'] as Map<String, dynamic>;

const _schicht = [
  'getMyDrawerState',
  'openMyShift',
  'recordMyCashMovement',
  'logMyDrawerOpenings',
  'getMyShiftReport',
  'closeMyShift',
];

Iterable<Map<String, dynamic>> _faelle(String endpunkt) => ((_endpunkte[endpunkt] as Map)['cases'] as List)
    .cast<Map<String, dynamic>>()
    .where((f) => f['method'] == 'POST' && f['params'] is Map && !(f['params'] as Map).containsKey(r'$body'));

Map<String, dynamic> _fall(String endpunkt, String name) => _faelle(endpunkt).firstWhere((f) => f['case'] == name);

/// Ohne `null`-Werte, rekursiv (fehlt und `null` sind im Modell gleich).
Object? _ohneNull(Object? w) => switch (w) {
  Map m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _ohneNull(e.value),
  },
  List l => [for (final x in l) _ohneNull(x)],
  _ => w,
};

({RegisterReceiptClient client, List<http.Request> anfragen}) _kasse(
  Future<http.Response> Function(http.Request r) antwort, {
  Duration? timeout,
}) {
  final anfragen = <http.Request>[];
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((r) {
      anfragen.add(r);
      return antwort(r);
    }),
    timeout: timeout,
  );
  return (client: RegisterReceiptClient(transport), anfragen: anfragen);
}

http.Response _antwort(Map<String, dynamic> fall) => http.Response.bytes(
  utf8.encode(jsonEncode(fall['response'])),
  fall['httpStatus'] as int,
  headers: {
    'content-type': 'application/json',
    for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
  },
);

String _s(Object? v) => v is String ? v : '';

Map<String, int>? _karte(Object? w) => w is Map ? w.cast<String, int>() : null;

Future<Object?> _rufe(RegisterReceiptClient c, String endpunkt, Map<String, dynamic> p) => switch (endpunkt) {
  'getMyDrawerState' => c.getMyDrawerState(drawerId: p['drawerId'] as String?, cashregisterId: p['cashregisterId'] as String?),
  'openMyShift' => c.openMyShift(
    idempotencyKey: _s(p['idempotencyKey']),
    drawerId: _s(p['drawerId']),
    openingFloatCents: p['openingFloatCents'] as int?,
    denominations: _karte(p['denominations']),
    takeOver: p['takeOver'] as bool?,
  ),
  'recordMyCashMovement' => c.recordMyCashMovement(
    idempotencyKey: _s(p['idempotencyKey']),
    drawerId: _s(p['drawerId']),
    type: _s(p['type']),
    amountCents: p['amountCents'] as int,
    location: p['location'] as String?,
    note: p['note'] as String?,
    recipientId: p['recipientId'] as String?,
    targetDrawerId: p['targetDrawerId'] as String?,
  ),
  'logMyDrawerOpenings' => c.logMyDrawerOpenings(
    drawerId: _s(p['drawerId']),
    entries: [
      for (final e in (p['entries'] as List? ?? const []).cast<Map<String, dynamic>>())
        DrawerOpeningEntry(
          idempotencyKey: _s(e['idempotencyKey']),
          reason: _s(e['reason']),
          ok: e['ok'] as bool,
          deviceTime: e['deviceTime'] as Object,
          note: e['note'] as String?,
          receiptId: e['receiptId'] as String?,
          error: e['error'] as String?,
        ),
    ],
  ),
  'getMyShiftReport' => c.getMyShiftReport(shiftId: _s(p['shiftId'])),
  'closeMyShift' => c.closeMyShift(
    idempotencyKey: _s(p['idempotencyKey']),
    shiftId: _s(p['shiftId']),
    countedCents: p['countedCents'] as int,
    denominations: _karte(p['denominations']),
    attempt: p['attempt'] as int?,
    comment: p['comment'] as String?,
    tipPayouts: p['tipPayouts'] == null
        ? null
        : [
            for (final a in (p['tipPayouts'] as List).cast<Map<String, dynamic>>())
              TipPayout(registerUserId: _s(a['registerUserId']), cents: a['cents'] as int),
          ],
  ),
  _ => throw StateError(endpunkt),
};

Object? _modell(Object? e) => switch (e) {
  DrawerState s => s.toJson(),
  OpenShiftResult s => s.toJson(),
  CashMovementResult s => s.toJson(),
  DrawerOpeningsResult s => s.toJson(),
  ShiftReport s => s.toJson(),
  ShiftCloseResult s => s.toJson(),
  _ => throw StateError('unbekanntes Ergebnis $e'),
};

final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map)['params'] as Map<String, dynamic>;

void main() {
  group('Vertrag kasse.json', () {
    test('jede Erfolgsantwort der sechs Aufrufe liest sich verlustfrei und geht mit den Parametern des Falls hinaus', () async {
      var gelesen = 0;
      for (final endpunkt in _schicht) {
        for (final fall in _faelle(endpunkt).where((f) => (f['response'] as Map)['status'] == 'success')) {
          final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
          final ergebnis = await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          final reason = '$endpunkt/${fall['case']}';
          expect(_ohneNull(_modell(ergebnis)), _ohneNull((fall['response'] as Map)['data']), reason: reason);
          // Die Kasse der Anmeldung legt der Transport bei; sonst ist es der Fall.
          final gesendet = {..._params(anfragen.single)};
          if (!(fall['params'] as Map).containsKey('cashregisterId')) gesendet.remove('cashregisterId');
          expect(_ohneNull(gesendet), _ohneNull(fall['params']), reason: reason);
          expect(anfragen.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/$endpunkt', reason: reason);
          gelesen++;
        }
      }
      expect(gelesen, greaterThanOrEqualTo(18));
    });

    test('vor dem Senden abgewiesen werden genau diese Faelle (wie im npm-Paket)', () async {
      final abgewiesen = <String>{};
      for (final endpunkt in _schicht) {
        for (final fall in _faelle(endpunkt)) {
          final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
          try {
            await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          } on KasseneckValidationError catch (e) {
            if (e.kind == 'request' && anfragen.isEmpty) abgewiesen.add('$endpunkt/${fall['case']}');
          } on Object {
            // Fehler des Servers: hier nicht Thema.
          }
        }
      }
      expect(abgewiesen, {
        'openMyShift/data_missing',
        'openMyShift/key_missing',
        'recordMyCashMovement/data_missing',
        'recordMyCashMovement/key_missing',
        'logMyDrawerOpenings/data_missing',
        'logMyDrawerOpenings/entries_empty',
        'logMyDrawerOpenings/key_missing',
        'getMyShiftReport/data_missing',
        'closeMyShift/data_missing',
        'closeMyShift/key_missing',
      });
    });

    test('Fehler kommen mit ihrem Code an und stehen in posErrorCodes', () async {
      for (final endpunkt in _schicht) {
        for (final fall in _faelle(endpunkt).where((f) => (f['response'] as Map)['status'] == 'error')) {
          final code = (fall['response'] as Map)['code'] ?? ((fall['response'] as Map)['data'] as Map?)?['code'];
          final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
          Object? fehler;
          try {
            await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          } catch (e) {
            fehler = e;
          }
          if (anfragen.isEmpty) continue; // vorab abgewiesen, siehe oben
          expect(isPosError(fehler, code as String), isTrue, reason: '$endpunkt/${fall['case']}: $code');
        }
      }
      final schichtCodes = _json('test/fixtures/vertrag/v3/v3-vokabular.json')['errorCodes'] as Map<String, dynamic>;
      expect(schichtCodes['shift'], isNotEmpty);
      for (final c in (schichtCodes['shift'] as List).cast<String>()) {
        expect(posErrorCodes, contains(c));
      }
    });
  });

  group('Blind und Rechte', () {
    test('ohne cashView fehlen Soll, Ist, Vorschlag und Laufstand, sie stehen nie als 0 da', () async {
      final (:client, anfragen: _) = _kasse((_) async => _antwort(_fall('getMyDrawerState', 'success_cashier')));
      final kassier = await client.getMyDrawerState(drawerId: 'haupt_KASSE1');
      expect(kassier.rights.cashView, isFalse);
      expect(kassier.expectedCents, isNull);
      expect(kassier.suggestedFloatCents, isNull);
      expect(kassier.recentOpenings, isNull);
      expect(kassier.shift!.expectedCents, isNull);
      expect(kassier.shift!.countedCents, isNull);
      expect(kassier.shift!.runningTotals, isNull);
      expect(kassier.shift!.differenceCents, isNull);
      final json = kassier.toJson();
      for (final k in ['expectedCents', 'suggestedFloatCents', 'recentOpenings']) {
        expect(json.containsKey(k), isFalse, reason: k);
      }
      for (final k in ['expectedCents', 'countedCents', 'runningTotals', 'differenceCents', 'suggestedFloatCents']) {
        expect((json['shift'] as Map).containsKey(k), isFalse, reason: 'shift.$k');
      }
    });

    test('der Chef sieht Soll, Laufstand und Ansprueche', () async {
      final (:client, anfragen: _) = _kasse((_) async => _antwort(_fall('getMyDrawerState', 'success_manager')));
      final chef = await client.getMyDrawerState(drawerId: 'haupt_KASSE1');
      expect(chef.expectedCents, 29400);
      expect(chef.shift!.runningTotals!.nonCashByMethod.single.method, 'card');
      expect(chef.shift!.runningTotals!.nonCashByMethod.single.cents, 3200);
      expect(chef.tipClaims.single.cents, 400);
    });

    test('Z-Bon blind: Soll, Ist, Differenz und Barumsatz sind null', () async {
      final (:client, anfragen: _) = _kasse((_) async => _antwort(_fall('closeMyShift', 'success_cashier_blind')));
      final r = await client.closeMyShift(idempotencyKey: 'z-2', shiftId: 'haupt_KASSE1_s2', countedCents: 20000, attempt: 2);
      expect(r.recount, isFalse);
      expect(r.receipt!.blind, isTrue);
      expect(r.receipt!.expectedCents, isNull);
      expect(r.receipt!.countedCents, isNull);
      expect(r.receipt!.differenceCents, isNull);
      expect(r.receipt!.cashSalesCents, isNull);
    });

    test('recount ist kein Fehler', () async {
      final (:client, anfragen: _) = _kasse((_) async => _antwort(_fall('closeMyShift', 'success_cashier_recount')));
      final r = await client.closeMyShift(idempotencyKey: 'z-1', shiftId: 'haupt_KASSE1_s2', countedCents: 20000);
      expect(r.recount, isTrue);
      expect(r.shift, isNull);
      expect(r.receipt, isNull);
    });
  });

  group('Senden', () {
    test('getMyDrawerState: ohne Lade gilt die Hauptlade der Kasse, mit Lade nur die Lade, leer wie keine', () async {
      final (:client, :anfragen) = _kasse((_) async => _antwort(_fall('getMyDrawerState', 'success_owner_new_main_drawer')));
      final ohne = await client.getMyDrawerState();
      expect(ohne.shift, isNull);
      expect(ohne.recentOpenings, isEmpty);
      await client.getMyDrawerState(drawerId: 'lade_bar');
      await client.getMyDrawerState(drawerId: '');
      expect(anfragen.map(_params).toList(), [
        {'cashregisterId': 'KASSE1'},
        {'drawerId': 'lade_bar', 'cashregisterId': 'KASSE1'},
        {'cashregisterId': 'KASSE1'},
      ]);
    });

    test('vor dem Senden: leere Kennungen, Schluessel, leere Liste, Zahl ausserhalb des sicheren Bereichs', () async {
      final (:client, :anfragen) = _kasse((_) async => _antwort(_fall('openMyShift', 'success_manager_counted')));
      await expectLater(
        client.openMyShift(idempotencyKey: 'k', drawerId: ' ', openingFloatCents: 0),
        throwsA(_anfragefehler),
      );
      await expectLater(
        client.openMyShift(idempotencyKey: 'x' * 121, drawerId: 'lade', openingFloatCents: 0),
        throwsA(_anfragefehler),
      );
      await expectLater(
        client.openMyShift(idempotencyKey: 'k', drawerId: 'lade', openingFloatCents: 9007199254740993),
        throwsA(_anfragefehler),
      );
      await expectLater(client.getMyShiftReport(shiftId: ''), throwsA(_anfragefehler));
      await expectLater(client.logMyDrawerOpenings(drawerId: 'lade', entries: const []), throwsA(_anfragefehler));
      await expectLater(
        client.closeMyShift(
          idempotencyKey: 'k',
          shiftId: 's',
          countedCents: 0,
          tipPayouts: const [TipPayout(registerUserId: 'ru', cents: 9007199254740993)],
        ),
        throwsA(_anfragefehler),
      );
      expect(anfragen, isEmpty);
    });

    test('0 als Startgeld geht hinaus (leere Lade), takeOver nur wenn gesetzt', () async {
      final (:client, :anfragen) = _kasse((_) async => _antwort(_fall('openMyShift', 'success_manager_counted')));
      await client.openMyShift(idempotencyKey: 'o-1', drawerId: 'lade_bar', openingFloatCents: 0);
      await client.openMyShift(idempotencyKey: 'o-2', drawerId: 'lade_bar', takeOver: true);
      final erste = _params(anfragen.first);
      expect(erste['openingFloatCents'], 0);
      expect(erste.containsKey('takeOver'), isFalse);
      expect(erste.containsKey('denominations'), isFalse);
      final zweite = _params(anfragen.last);
      expect(zweite['takeOver'], isTrue);
      expect(zweite.containsKey('openingFloatCents'), isFalse);
    });

    test('Oeffnungen: Zeit als Millisekunden, Text oder DateTime, optionale Felder nur wenn gesetzt', () async {
      final (:client, :anfragen) = _kasse((_) async => _antwort(_fall('logMyDrawerOpenings', 'success_cashier')));
      await client.logMyDrawerOpenings(
        drawerId: 'haupt_KASSE1',
        entries: [
          const DrawerOpeningEntry(idempotencyKey: 'l-1', reason: 'sale', ok: true, deviceTime: 1790409480000, receiptId: 'R1'),
          const DrawerOpeningEntry(idempotencyKey: 'l-2', reason: 'check', ok: true, deviceTime: '2026-09-26T07:59:00.000Z'),
          DrawerOpeningEntry(
            idempotencyKey: 'l-3',
            reason: 'other',
            ok: false,
            deviceTime: DateTime.utc(2026, 9, 26, 8),
            note: 'Bonrolle',
            error: 'Kein Impuls',
          ),
        ],
      );
      final e = (_params(anfragen.single)['entries'] as List).cast<Map<String, dynamic>>();
      expect(e[0], {'idempotencyKey': 'l-1', 'reason': 'sale', 'ok': true, 'deviceTime': 1790409480000, 'receiptId': 'R1'});
      expect(e[1].keys, unorderedEquals(['idempotencyKey', 'reason', 'ok', 'deviceTime']));
      expect(e[2]['deviceTime'], DateTime.utc(2026, 9, 26, 8).millisecondsSinceEpoch);
      expect(e[2]['error'], 'Kein Impuls');
    });

    test('nach einem Zeitlimit: die vier schreibenden Aufrufe unklar, Lesen abgelehnt', () async {
      Future<Object?> fehler(Future<Object?> Function(RegisterReceiptClient c) aufruf) async {
        final (:client, anfragen: _) = _kasse((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 20));
        try {
          await aufruf(client);
        } catch (e) {
          return e;
        }
        return null;
      }

      final schreiben = <Future<Object?> Function(RegisterReceiptClient)>[
        (c) => c.openMyShift(idempotencyKey: 'k', drawerId: 'lade', openingFloatCents: 100),
        (c) => c.recordMyCashMovement(idempotencyKey: 'k', drawerId: 'lade', type: 'owner_deposit', amountCents: 100),
        (c) => c.logMyDrawerOpenings(
          drawerId: 'lade',
          entries: [const DrawerOpeningEntry(idempotencyKey: 'l', reason: 'check', ok: true, deviceTime: 1)],
        ),
        (c) => c.closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 100),
      ];
      for (final aufruf in schreiben) {
        expect(isOutcomeUnknown(await fehler(aufruf)), isTrue);
      }
      for (final lesen in <Future<Object?> Function(RegisterReceiptClient)>[
        (c) => c.getMyDrawerState(),
        (c) => c.getMyShiftReport(shiftId: 's'),
      ]) {
        expect(await fehler(lesen), isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.rejected));
      }
    });

    test('kaputte Antworten: kein Ersatzwert, sondern ein Antwortfehler', () async {
      final fall = Map<String, dynamic>.from(_fall('getMyShiftReport', 'success_manager'));
      final antwort = Map<String, dynamic>.from(fall['response'] as Map);
      final daten = jsonDecode(jsonEncode(antwort['data'])) as Map<String, dynamic>;
      (daten['shift'] as Map)['number'] = 'zwei';
      antwort['data'] = daten;
      fall['response'] = antwort;
      final (:client, anfragen: _) = _kasse((_) async => _antwort(fall));
      await expectLater(
        client.getMyShiftReport(shiftId: 's'),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
      );
    });
  });

  group('Lade am Beleg und am Geraet', () {
    test('sell und cancelReceipt nennen die Lade nur, wenn sie gesetzt ist; leer wirft vor dem Senden', () async {
      final (:client, :anfragen) = _kasse((_) async => http.Response('{}', 500));
      const bar = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 250)];
      final kaffee = [KasseneckItem(name: 'Kaffee', quantity: 1, priceCents: 250, vat: VatRate.vat20)];
      try {
        await client.sell(items: kaffee, payments: bar, drawerId: 'lade_bar');
      } catch (_) {}
      try {
        await client.sell(items: kaffee, payments: bar);
      } catch (_) {}
      try {
        await client.cancelReceipt(originalReceiptId: 'kasse-1-ID-12', reason: 'other', drawerId: 'lade_bar');
      } catch (_) {}
      expect(_params(anfragen[0])['drawerId'], 'lade_bar');
      expect(_params(anfragen[1]).containsKey('drawerId'), isFalse);
      expect(_params(anfragen[2])['drawerId'], 'lade_bar');
      final bisher = anfragen.length;
      for (final leer in ['', '  ']) {
        await expectLater(client.sell(items: kaffee, payments: bar, drawerId: leer), throwsA(_anfragefehler));
        await expectLater(
          client.cancelReceipt(originalReceiptId: 'kasse-1-ID-12', reason: 'other', drawerId: leer),
          throwsA(_anfragefehler),
        );
      }
      expect(anfragen.length, bisher);
    });

    test('Geraete-Einstellung drawerId: optional, ohne Standardwert; nur eine gueltige Kennung wird gelesen', () {
      expect(posDeviceOptionalFields, ['drawerId']);
      expect(const PosDeviceSettings().toJson().containsKey('drawerId'), isFalse);
      expect(PosDeviceSettings.fromJson(const {}).drawerId, isNull);
      expect(PosDeviceSettings.fromJson({'drawerId': 'lade_bar'}).drawerId, 'lade_bar');
      expect(PosDeviceSettings.fromJson({'drawerId': 'lade_bar'}).toJson()['drawerId'], 'lade_bar');
      for (final fremd in [null, '', 'lade bar', 7, 'x' * 65]) {
        expect(PosDeviceSettings.fromJson({'drawerId': fremd}).drawerId, isNull, reason: '$fremd');
      }
      // merge: setzen, behalten, entfernen.
      final mit = const PosDeviceSettings().merge({'drawerId': 'lade_bar'});
      expect(mit.drawerId, 'lade_bar');
      expect(mit.merge({'touch': true}).drawerId, 'lade_bar');
      expect(mit.merge({'drawerId': null}).drawerId, isNull);
      expect(() => mit.merge({'drawerId': 'lade bar'}), throwsArgumentError);
    });

    test('Geraete-Einstellung drawerId schreiben: Kennung oder null, anderes wirft vor dem Senden', () async {
      final gesendet = <Map<String, dynamic>>[];
      final transport = RegisterTransport(
        idToken: () async => 'id-token',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KASSE1',
        httpClient: MockClient((r) async {
          gesendet.add(_params(r));
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': '',
              'data': {'device': {'drawerId': 'lade_bar'}},
            }),
            200,
            headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
          );
        }),
      );
      final client = PosSettingsClient(transport, deviceId: 'dev_pin');
      expect((await client.saveDevice({'drawerId': 'lade_bar'})).drawerId, 'lade_bar');
      await client.saveDevice({'drawerId': null});
      expect(gesendet.map((p) => p['device']).toList(), [
        {'drawerId': 'lade_bar'},
        {'drawerId': null},
      ]);
      for (final falsch in ['', 'lade bar', 12]) {
        await expectLater(client.saveDevice({'drawerId': falsch}), throwsA(_anfragefehler));
      }
      expect(gesendet, hasLength(2));
    });
  });

  test('Texte der Schicht aus dem Katalog', () {
    expect(messageText('shift.required'), 'Bitte zuerst die Schicht öffnen.');
    expect(messageText('shift.required_other'), 'Die Schicht muss ein berechtigter Mitarbeiter öffnen.');
    expect(messageText('shift.closed', {'number': 7}), 'Schicht 7 geschlossen.');
    expect(labelText('shift.not_a_receipt'), 'Kein Registrierkassenbeleg');
  });
}
