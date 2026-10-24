import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/pos.dart' as kasse;
import 'package:kasseneck_api/pos.dart' show KasseneckReceipt, RegisterReceiptClient, labelText, posLabels, receiptOutputLabel;
import 'package:kasseneck_api/register.dart' show FieldError, RegisterTransport;
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/kasse/beleg_ausgaben.dart' show ausgabenLesen;
import 'package:kasseneck_api/src/receipt/codes.dart' show anmeldungUndRandCodes;
import 'package:kasseneck_api/src/v3.dart' show isUnknownOutcomeCall, unknownOutcomeCalls;

/// Ausgaben eines Belegs (Spec 2026-10-24-beleg-ausgaben-design.md, Abschnitt 3):
/// `logReceiptOutputs` am Kassenweg gegen den Vertrag
/// (`v3/antworten/kasse.json`), `outputs` aus `getReceipt` (`belege.json`,
/// `kasse-belege.json`, Fall `get_receipt_with_outputs`), Kataloge, Codes,
/// Texte. Zwilling von `test/receipt-outputs.test.ts` im npm-Paket. Die
/// nachsichtige Leseregel fuer `outputs` (samt `receiptOutputLabel`) und die
/// Pruefung der Eintraege vor dem Senden kommen aus der gemeinsamen
/// Vertragsdatei `receipt-outputs-cases.json` (npm `fixtures:ausgaben`, gezogen
/// mit `tool/zwillinge.sh`): beide Pakete rechnen dieselben Faelle. Von Hand
/// stehen hier nur, was es nur in Dart gibt (DateTime, Typfehler im Puffer).
///
/// Rot-Proben (belegt): Text in `pos-texts.json` abweichend -> „Golden“ des
/// Katalogs und „Texte“ rot; `logReceiptOutputs` aus `unknownOutcomeCalls`
/// genommen -> Einordnung und „Kassenaufruf mit Wirkung“ rot; ein unbekanntes
/// Feld in `ReceiptOutputEntry.fromJson` angenommen -> Zwillingsanfragen rot;
/// ein erwarteter Wert nur in der npm-Vertragsdatei geaendert -> `pruefen` und
/// die Zwillingsfaelle rot; Beschriftungsregel in Dart gebrochen -> Lesefaelle rot.
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _tief(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

final _faelle = (((_json('antworten/kasse.json')['endpoints'] as Map)['logReceiptOutputs'] as Map)['cases'] as List)
    .cast<Map<String, dynamic>>();
final _vokabular = _json('v3-vokabular.json');
final _belege = (_json('antworten/belege.json')['cases'] as List).cast<Map<String, dynamic>>();
final _kasseBelege = (_json('antworten/kasse-belege.json')['cases'] as List).cast<Map<String, dynamic>>();

/// Gemeinsame Prueffaelle mit dem npm-Paket (`fixtures/receipt-outputs-cases.json`).
final _zwilling =
    jsonDecode(File('test/fixtures/vertrag/receipt-outputs-cases.json').readAsStringSync()) as Map<String, dynamic>;
final _lesefaelle = (_zwilling['outputs'] as List).cast<Map<String, dynamic>>();
final _anfragen = (_zwilling['requests'] as List).cast<Map<String, dynamic>>();
Map<String, dynamic> _anfrage(String name) => _anfragen.firstWhere((a) => a['name'] == name);
Map<String, dynamic>? _anfrageOderNull(String name) => _anfragen.where((a) => a['name'] == name).firstOrNull;

Map<String, dynamic> _fall(String name) => _faelle.firstWhere((c) => c['case'] == name);

http.Response _antwort(Map<String, dynamic> f) {
  final kopf = ((f['headers'] as Map?) ?? const {'Kasseneck-Api-Version': 'v3'}).cast<String, String>();
  return http.Response.bytes(
    utf8.encode(jsonEncode(f['response'])),
    (f['httpStatus'] as int?) ?? 200,
    headers: {'content-type': 'application/json', for (final e in kopf.entries) e.key.toLowerCase(): e.value},
  );
}

RegisterReceiptClient _kasse(http.Client client, {Duration? timeout}) => RegisterReceiptClient(RegisterTransport(
      idToken: () async => 'eyJ-ID',
      sessionId: () async => 'sess-1',
      cashregisterId: 'KASSE1',
      httpClient: client,
      timeout: timeout,
    ));

List<ReceiptOutputEntry> _eintraege(Object? roh) => [
      for (final e in (roh as List? ?? const [])) ReceiptOutputEntry.fromJson((e as Map).cast<String, dynamic>()),
    ];

/// Ruft den Fall ueber `logReceiptOutputs`; die Kassenbindung des Transports
/// zaehlt nur, wenn der Fall sie nennt.
Future<({Object? ergebnis, Object? fehler, List<Map<String, dynamic>> gesendet})> _rufe(Map<String, dynamic> f) async {
  final gesendet = <Map<String, dynamic>>[];
  final params = f['params'] as Map<String, dynamic>;
  final client = MockClient((r) async {
    expect(r.url.toString(), '$kPosBaseUrl/logReceiptOutputs', reason: f['case'] as String?);
    final p = (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
    if (!params.containsKey('cashregisterId')) p.remove('cashregisterId');
    gesendet.add(p);
    return _antwort(f);
  });
  try {
    final ergebnis = await _kasse(client).logReceiptOutputs(entries: _eintraege(params['entries']));
    return (ergebnis: ergebnis, fehler: null, gesendet: gesendet);
  } catch (e) {
    return (ergebnis: null, fehler: e, gesendet: gesendet);
  }
}

/// Faelle, die das Paket schon vor dem Senden abweist (sicher falsch ohne Netz): genau diese. Fall -> Grund.
const _vorDemSenden = {'data_missing': 'entries fehlt', 'entries_empty': 'leere Liste'};

Matcher _anfragefehler([Pattern? muster]) => isA<KasseneckValidationError>()
    .having((e) => e.kind, 'kind', 'request')
    .having((e) => muster == null || e.reason.contains(muster), 'reason passt zu $muster', isTrue);

const _gut = ReceiptOutputEntry(
    key: 'druck-0001', receiptId: 'KASSE1-ID-7', kind: 'print', at: '2026-09-26T09:58:00+02:00', result: 'ok');

ReceiptOutputEntry _mit({String? key, String? receiptId, String? kind, Object? at, String? result}) => ReceiptOutputEntry(
      key: key ?? _gut.key,
      receiptId: receiptId ?? _gut.receiptId,
      kind: kind ?? _gut.kind,
      at: at ?? _gut.at,
      result: result ?? _gut.result,
    );

/// Liest einen Beleg-Fall ueber den Weg seines Pfads (Kassenweg oder `KasseneckApi`).
Future<KasseneckReceipt> _belegLesen(Map<String, dynamic> f) async {
  final client = MockClient((_) async => _antwort(f));
  final id = (f['params'] as Map)['receiptId'] as String;
  if ((f['path'] as String).startsWith('/api/v3/')) {
    return RegisterReceiptClient(RegisterTransport(
      idToken: () async => 'eyJ-ID',
      sessionId: () async => 'sess-1',
      cashregisterId: 'KECK-1',
      httpClient: client,
    )).get(id);
  }
  final api = KasseneckApi(apiKey: 'kr_live_Ab12', cashregisterToken: 'cb_live_Xy34', httpClient: client);
  return (await api.getReceipt(id))!;
}

List<Map<String, dynamic>>? _alsJson(List<ReceiptOutput>? o) => o?.map((e) => e.toJson()).toList();

ReceiptOutput _o(String kind, {String result = 'ok', int? count, ReceiptOutputActor? by}) =>
    ReceiptOutput(kind: kind, at: '2026-09-26T10:00:05+02:00', result: result, by: by, count: count);

void main() {
  group('logReceiptOutputs am Kassenweg', () {
    test('jeder Erfolgsfall sendet genau die Eintraege des Falls und liest accepted/rejected wie gesendet', () async {
      final faelle = _faelle.where((c) => (c['response'] as Map)['status'] == 'success').toList();
      expect(faelle.length, greaterThanOrEqualTo(4));
      for (final f in faelle) {
        final name = f['case'] as String;
        var gesendetWird = f;
        // Ein Fall, den das Paket vor dem Senden abweist, steht so in der
        // Zwillingsdatei (contract_<fall>), dazu der Fall ohne den beanstandeten
        // Eintrag (contract_<fall>_without_short_key), der hinausgeht.
        final zwilling = _anfrageOderNull('contract_$name');
        if (zwilling != null) {
          expect(zwilling['entries'], (f['params'] as Map)['entries'], reason: '$name: Zwillingsdatei aus einem anderen Vertragsstand');
          final grund = ((zwilling['expected'] as Map)['error'] as Map)['reason'] as String;
          final ganz = await _rufe(f);
          expect(ganz.gesendet, isEmpty, reason: name);
          expect(ganz.fehler, isA<KasseneckValidationError>().having((e) => e.reason, 'reason', grund), reason: name);
          gesendetWird = _tief(f);
          (gesendetWird['params'] as Map)['entries'] = _anfrage('contract_${name}_without_short_key')['entries'];
        }
        final lauf = await _rufe(gesendetWird);
        expect(lauf.fehler, isNull, reason: '$name: ${lauf.fehler}');
        expect(lauf.gesendet, [gesendetWird['params']], reason: name);
        expect((lauf.ergebnis as LogReceiptOutputsResult).toJson(), (f['response'] as Map)['data'], reason: name);
      }
    });

    test('abgelehnte Eintraege kommen je Schluessel mit Code zurueck, die anderen sind angenommen (Review Focus 5)', () async {
      final f = _tief(_fall('mixed'));
      (f['params'] as Map)['entries'] = _anfrage('contract_mixed_without_short_key')['entries'];
      final lauf = await _rufe(f);
      // Mail und Abruf meldet die Kasse nie selbst; das Paket sendet sie trotzdem,
      // damit der Server genau diesen Eintrag ablehnt und der Puffer ihn verwirft.
      expect([for (final e in lauf.gesendet.single['entries'] as List) (e as Map)['kind']],
          ['email', 'opened', 'print', 'print', 'reprint', 'reprint']);
      final r = lauf.ergebnis as LogReceiptOutputsResult;
      expect(r.accepted, 1);
      expect(r.rejected.firstWhere((x) => x.key == 'fremd-0001'),
          const RejectedReceiptOutput(key: 'fremd-0001', code: 'receipt_not_found'));
      for (final x in r.rejected) {
        expect(receiptOutputEntryErrorCodes, contains(x.code));
      }
      // Jeder Code je Eintrag aus dem Vertrag steht in der Liste, und umgekehrt.
      expect(r.rejected.map((x) => x.code).toSet(), receiptOutputEntryErrorCodes.toSet());
    });

    test('jeder Fehlerfall wird am Code erkannt; vor dem Senden abgewiesen nur die benannten', () async {
      final abgewiesen = <String>[];
      for (final f in _faelle) {
        final antwort = f['response'] as Map;
        if (antwort['status'] != 'error' || (f['params'] as Map).containsKey(r'$body')) continue;
        final lauf = await _rufe(f);
        if (lauf.gesendet.isEmpty) {
          expect(lauf.fehler, _anfragefehler(), reason: f['case'] as String);
          abgewiesen.add(f['case'] as String);
          continue;
        }
        expect(isReceiptOutputError(lauf.fehler, antwort['code'] as String), isTrue, reason: '${f['case']}: ${lauf.fehler}');
      }
      expect(abgewiesen..sort(), _vorDemSenden.keys.toList()..sort());
    });

    test('Zwilling: jede Anfrage der Vertragsdatei sendet genau die erwartete Nutzlast oder wird mit genau diesem Grund abgewiesen',
        () async {
      expect(_zwilling['version'], 1);
      expect(_anfragen.length, greaterThanOrEqualTo(40));
      for (final a in _anfragen) {
        final name = a['name'] as String;
        final erwartet = a['expected'] as Map;
        final gesendet = <Map<String, dynamic>>[];
        final kasse = _kasse(MockClient((r) async {
          final p = (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
          p.remove('cashregisterId');
          gesendet.add(p);
          return _antwort({
            'response': {
              'status': 'success',
              'message': '',
              'data': {'accepted': (a['entries'] as List).length, 'rejected': []},
            },
          });
        }));
        // Wie die Kasse ihren Puffer liest: je Eintrag fromJson. fromJson meldet
        // ohne den Vorsatz des npm-Pakets: `entries[i]: ` vor einem unbekannten
        // Feld, `entries[i].` vor einem Feldgrund (`result muss ...`).
        Object? fehler;
        final eintraege = <ReceiptOutputEntry>[];
        for (final (i, e) in (a['entries'] as List).indexed) {
          try {
            eintraege.add(ReceiptOutputEntry.fromJson((e as Map).cast<String, dynamic>()));
          } on KasseneckValidationError catch (f) {
            final trenner = f.reason.startsWith('unbekanntes Feld') ? ': ' : '.';
            fehler = KasseneckValidationError(f.functionName, 'entries[$i]$trenner${f.reason}', f.kind);
            break;
          }
        }
        if (fehler == null) {
          try {
            await kasse.logReceiptOutputs(entries: eintraege);
          } catch (e) {
            fehler = e;
          }
        }
        if (erwartet.containsKey('sent')) {
          expect(fehler, isNull, reason: '$name: $fehler');
          expect(gesendet, [erwartet['sent']], reason: name);
        } else {
          final soll = erwartet['error'] as Map;
          expect(gesendet, isEmpty, reason: name);
          expect(fehler, isA<KasseneckValidationError>(), reason: '$name: $fehler');
          expect((fehler as KasseneckValidationError).kind, soll['scope'], reason: name);
          expect(fehler.reason, soll['reason'], reason: name);
        }
      }
    });

    test('Zwilling: KasseneckApi prueft vor dem Senden gleich (jede abgewiesene Anfrage, die fromJson durchlaesst)', () async {
      final api = KasseneckApi(
          apiKey: 'kr_live_Ab12',
          cashregisterToken: 'cb_live_Xy34',
          httpClient: MockClient((_) async => throw StateError('darf nicht senden')));
      var n = 0;
      for (final a in _anfragen) {
        final soll = (a['expected'] as Map)['error'] as Map?;
        if (soll == null) continue;
        // Was schon fromJson abweist (unbekanntes Feld, ausdrueckliches null im
        // Ergebnis), prueft der Test davor mit dem Grund des npm-Pakets.
        final List<ReceiptOutputEntry> eintraege;
        try {
          eintraege = _eintraege(a['entries']);
        } on KasseneckValidationError {
          continue;
        }
        await expectLater(() => api.logReceiptOutputs(entries: eintraege),
            throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', soll['reason'])),
            reason: a['name'] as String);
        n++;
      }
      expect(n, greaterThanOrEqualTo(25));
    });

    test('vor dem Senden, nur in Dart: Typfehler im Puffer, DateTime vor 1970', () async {
      final kasse = _kasse(MockClient((_) async => throw StateError('darf nicht senden')));
      await expectLater(
          () => _eintraege([
                {..._gut.toJson(), 'key': 42},
              ]),
          throwsA(_anfragefehler('key muss ein Text sein')));
      await expectLater(
          () => _eintraege([
                {..._gut.toJson(), 'result': true},
              ]),
          throwsA(_anfragefehler('result muss ein Text sein')));
      await expectLater(() => kasse.logReceiptOutputs(entries: [_mit(at: DateTime.utc(1969, 12, 31))]),
          throwsA(_anfragefehler('entries[0].at muss')));
    });

    test('DateTime geht als Millisekunden hinaus (wie die Ladeoeffnungen)', () async {
      final gesendet = <Map<String, dynamic>>[];
      final kasse = _kasse(MockClient((r) async {
        gesendet.add((jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>);
        return _antwort({
          'response': {
            'status': 'success',
            'message': '',
            'data': {'accepted': 2, 'rejected': []},
          },
        });
      }));
      await kasse.logReceiptOutputs(entries: [
        ReceiptOutputEntry(key: 'share-0003', receiptId: 'KASSE1-ID-7', kind: 'pdf_shared', at: DateTime.utc(2026, 9, 26, 8)),
        ReceiptOutputEntry(
            key: 'share-0004', receiptId: 'KASSE1-ID-7', kind: 'link_shared', at: DateTime.utc(2026, 9, 26, 7, 59).toIso8601String()),
      ]);
      expect(gesendet.single['entries'], [
        {'key': 'share-0003', 'receiptId': 'KASSE1-ID-7', 'at': 1790409600000, 'kind': 'pdf_shared'},
        {'key': 'share-0004', 'receiptId': 'KASSE1-ID-7', 'at': '2026-09-26T07:59:00.000Z', 'kind': 'link_shared'},
      ]);
    });

    test('50 Eintraege gehen in einem Aufruf hinaus, ein fehlendes Ergebnis nicht', () async {
      final gesendet = <Map<String, dynamic>>[];
      final kasse = _kasse(MockClient((r) async {
        gesendet.add((jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>);
        return _antwort({
          'response': {
            'status': 'success',
            'message': '',
            'data': {'accepted': 50, 'rejected': []},
          },
        });
      }));
      final eintraege = [
        for (var i = 0; i < receiptOutputEntriesMax; i++)
          ReceiptOutputEntry(key: 'teilen-${1000 + i}', receiptId: 'KASSE1-ID-7', kind: 'link_shared', at: 1790409570000),
      ];
      final ergebnis = await kasse.logReceiptOutputs(entries: eintraege);
      expect(ergebnis.toJson(), {'accepted': 50, 'rejected': []});
      expect((gesendet.single['entries'] as List).length, 50);
      expect((gesendet.single['entries'] as List).first,
          {'key': 'teilen-1000', 'receiptId': 'KASSE1-ID-7', 'at': 1790409570000, 'kind': 'link_shared'});
      expect(gesendet.single['cashregisterId'], 'KASSE1');
    });

    test('der Puffer: toJson und fromJson ergeben denselben Eintrag', () {
      for (final f in _faelle.where((c) => (c['response'] as Map)['status'] == 'success')) {
        for (final roh in ((f['params'] as Map)['entries'] as List).cast<Map<String, dynamic>>()) {
          expect(ReceiptOutputEntry.fromJson(roh).toJson(), roh, reason: '${f['case']} ${roh['key']}');
        }
      }
    });

    test('unklarer Ausgang nach Zeitlimit (mit demselben Schluessel gefahrlos wiederholbar)', () async {
      final kasse = _kasse(MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 20));
      final fehler = await kasse
          .logReceiptOutputs(entries: const [
            ReceiptOutputEntry(key: 'druck-0001', receiptId: 'KASSE1-ID-7', kind: 'print', at: 1790409480000, result: 'ok'),
          ])
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(fehler, isA<KasseneckHttpError>());
      expect(isOutcomeUnknown(fehler), isTrue);
    });

    test('kaputte Erfolgsantwort ist ein Antwortfehler, nie 0 angenommen', () async {
      for (final data in <Object?>[
        {'accepted': '3', 'rejected': []},
        {'accepted': 3},
        {'accepted': -1, 'rejected': []},
        {
          'accepted': 1,
          'rejected': [
            {'key': 'druck-0001'},
          ],
        },
        {'accepted': 1, 'rejected': {}},
        null,
      ]) {
        final f = _tief(_fall('success_cashier'));
        (f['response'] as Map)['data'] = data;
        final lauf = await _rufe(f);
        expect(lauf.fehler, isA<Exception>(), reason: '$data');
        expect(lauf.fehler, isNot(isA<KasseneckApiError>()), reason: '$data');
        if (lauf.fehler is KasseneckValidationError) {
          expect((lauf.fehler as KasseneckValidationError).kind, 'response', reason: '$data');
        } else {
          // `data: null`: die Huelle selbst ist keine (Transport des Kassenwegs).
          expect(lauf.fehler, isA<KasseneckHttpError>(), reason: '$data');
        }
      }
      // Ein Code je Eintrag, den das Paket noch nicht kennt (neuerer Server), bleibt lesbar.
      final f = _tief(_fall('success_cashier'));
      (f['response'] as Map)['data'] = {
        'accepted': 2,
        'rejected': [
          {'key': 'druck-0002', 'code': 'receipt_archived'},
        ],
        'hint': 'neu',
      };
      final lauf = await _rufe(f);
      expect((lauf.ergebnis as LogReceiptOutputsResult).toJson(), {
        'accepted': 2,
        'rejected': [
          {'key': 'druck-0002', 'code': 'receipt_archived'},
        ],
      });
    });

    test('ein Kassenaufruf mit Wirkung: Kassenweg, unklarer Ausgang, KasseneckApi auch mit api_key', () async {
      expect(Aufrufe.alle, contains('logReceiptOutputs'));
      expect(unknownOutcomeCalls, contains('logReceiptOutputs'));
      expect(isUnknownOutcomeCall('logReceiptOutputs'), isTrue);
      final f = _fall('success_api_key');
      final urls = <String>[];
      final gesendet = <Map<String, dynamic>>[];
      final api = KasseneckApi(
        apiKey: 'kr_live_Ab12',
        cashregisterToken: 'cb_live_Xy34',
        httpClient: MockClient((r) async {
          urls.add(r.url.toString());
          expect(r.headers['Authorization'], 'Bearer kr_live_Ab12');
          expect(r.headers['cashregister-token'], 'cb_live_Xy34');
          gesendet.add((jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>);
          return _antwort(f);
        }),
      );
      final ergebnis = await api.logReceiptOutputs(entries: _eintraege((f['params'] as Map)['entries']));
      expect(ergebnis.toJson(), (f['response'] as Map)['data']);
      expect(gesendet, [f['params']]);
      expect(urls, ['$kPosBaseUrl/logReceiptOutputs']);
      // Ein Fehler der ganzen Anfrage kommt auch hier am Code an.
      final fremd = _fall('foreign_cashregister');
      final apiFehler = KasseneckApi(
          apiKey: 'kr_live_Ab12',
          cashregisterToken: 'cb_live_Xy34',
          httpClient: MockClient((_) async => _antwort(fremd)));
      final e = await apiFehler
          .logReceiptOutputs(entries: _eintraege((fremd['params'] as Map)['entries']))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(isReceiptOutputError(e, 'cashregister_not_assigned'), isTrue, reason: '$e');
      // Vor dem Senden prueft KasseneckApi gleich.
      await expectLater(() => api.logReceiptOutputs(entries: [_mit(key: 'kurz')]), throwsA(_anfragefehler('key')));
    });
  });

  group('outputs aus getReceipt', () {
    test('aus dem Vertragsfall get_receipt_with_outputs, beide Kanaele, Feld fuer Feld', () async {
      for (final liste in [_belege, _kasseBelege]) {
        final f = liste.firstWhere((c) => c['name'] == 'get_receipt_with_outputs');
        final beleg = await _belegLesen(f);
        final outputs = beleg.outputs!;
        expect(_alsJson(outputs), ((f['response'] as Map)['data'] as Map)['outputs'], reason: f['path'] as String);
        expect(outputs.map((o) => o.kind).toList()..sort(), ['email', 'opened', 'print', 'reprint']);
        final abruf = outputs.firstWhere((o) => o.kind == 'opened');
        expect(abruf.by, isNull);
        expect(abruf.count, 3);
        // Nur der Abruf traegt eine Anzahl.
        for (final o in outputs) {
          expect(o.count != null, o.kind == 'opened', reason: o.kind);
        }
        expect(outputs.first.by, const ReceiptOutputActor(id: 'ru_livia', name: 'Livia Lindmayr'));
      }
    });

    test('jeder Erfolgsfall unter /v3 liest outputs als Liste; ohne Feld fehlt es', () async {
      var n = 0;
      for (final f in [..._belege, ..._kasseBelege]) {
        if (f['endpoint'] != 'getReceipt' || (f['response'] as Map)['status'] != 'success') continue;
        final daten = (f['response'] as Map)['data'] as Map;
        expect(daten['outputs'], isA<List>(), reason: '${f['name']}: der Vertrag nennt outputs');
        expect(_alsJson((await _belegLesen(f)).outputs), daten['outputs'], reason: f['name'] as String);
        n++;
      }
      expect(n, greaterThanOrEqualTo(6));
      // Antwort ohne Protokoll (Verkauf): kein Feld, keine leere Liste erfunden.
      final ohne = _tief(_belege.firstWhere((c) => c['name'] == 'get_receipt_with_outputs'));
      ((ohne['response'] as Map)['data'] as Map).remove('outputs');
      expect((await _belegLesen(ohne)).outputs, isNull);
    });

    test('Zwilling: jeder Lesefall der Vertragsdatei ergibt genau die erwartete Liste und Beschriftungen', () {
      expect(_lesefaelle.length, greaterThanOrEqualTo(8));
      for (final f in _lesefaelle) {
        final gelesen = ausgabenLesen(f['input']);
        expect(_alsJson(gelesen), f['expected'], reason: f['name'] as String);
        expect(gelesen?.map(receiptOutputLabel).toList(), f['labels'], reason: f['name'] as String);
      }
      // Der Vertragsfall steht unveraendert darin.
      final vertrag = _belege.firstWhere((c) => c['name'] == 'get_receipt_with_outputs');
      expect(_lesefaelle.firstWhere((f) => f['name'] == 'contract_get_receipt_with_outputs')['input'],
          ((vertrag['response'] as Map)['data'] as Map)['outputs']);
    });

    test('ein kaputtes Protokoll laesst den Beleg nie scheitern (Lesefaelle der Vertragsdatei am ganzen Beleg, beide Wege)', () async {
      for (final liste in [_belege, _kasseBelege]) {
        for (final z in _lesefaelle) {
          final f = _tief(liste.firstWhere((c) => c['name'] == 'get_receipt_with_outputs'));
          final daten = (f['response'] as Map)['data'] as Map;
          daten['outputs'] = z['input'];
          final beleg = await _belegLesen(f);
          expect(beleg.receiptId, (daten['receipt'] as Map)['receiptId'], reason: z['name'] as String);
          expect(_alsJson(beleg.outputs), z['expected'], reason: '${f['path']} ${z['name']}');
        }
      }
    });
  });

  group('Kataloge und Codes', () {
    test('Arten und Ergebnisse sind die des /v3-Vokabulars, die Kasse meldet nur vier Arten', () {
      final kataloge = _vokabular['catalogs'] as Map;
      expect(receiptOutputKinds, (kataloge['AUSGABE_ART'] as Map).values.toList());
      expect(receiptOutputResults, (kataloge['AUSGABE_ERGEBNIS'] as Map).values.toList());
      expect(receiptOutputLogKinds, ['print', 'reprint', 'link_shared', 'pdf_shared']);
      expect(receiptOutputKinds, containsAll(receiptOutputLogKinds));
      // pos.dart fuehrt dieselben Listen wie die Wurzel, und beide die des Vertrags.
      expect(kasse.receiptOutputKinds, same(receiptOutputKinds));
      expect(kasse.receiptOutputResults, same(receiptOutputResults));
      final surface = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map;
      expect(receiptOutputKinds, (surface['pos'] as Map)['receiptOutputKinds']);
      expect(receiptOutputResults, (surface['pos'] as Map)['receiptOutputResults']);
      expect(receiptOutputEntriesMax, 50);
    });

    test('Fehlercodes: die des Endpunkts laut Vokabular, dahinter Rand und Anmeldung, zuletzt route_missing', () {
      final codes = _vokabular['errorCodes'] as Map;
      final eigen = ((codes['registerHandlersByEndpoint'] as Map)['logReceiptOutputs'] as List).cast<String>();
      expect(receiptOutputErrorCodes, [...eigen, ...anmeldungUndRandCodes.where((c) => !eigen.contains(c)), 'route_missing']);
      for (final c in receiptOutputErrorCodes) {
        expect((codes['all'] as List).contains(c) || clientErrorCodes.contains(c), isTrue, reason: c);
      }
      // Codes je Eintrag: die des Endpunkts ohne server_error (ein Eintrag scheitert nie am Server selbst).
      expect(receiptOutputEntryErrorCodes.toSet(), eigen.where((c) => c != 'server_error').toSet());
      expect(isReceiptOutputErrorCode('receipt_not_found'), isTrue);
      expect(isReceiptOutputErrorCode('RECEIPT_NOT_FOUND'), isFalse);
      expect(receiptOutputErrorCode(Exception('x')), isNull);
    });

    test('Feldfehler einer validation-Antwort sind lesbar', () async {
      final f = _fall('entries_empty');
      final log = <http.Request>[];
      final kasse = _kasse(MockClient((r) async {
        log.add(r);
        return _antwort(f);
      }));
      // Die Liste ist nicht leer, damit die Anfrage hinausgeht; die Antwort ist die des Falls.
      final e = await kasse
          .logReceiptOutputs(entries: const [
            ReceiptOutputEntry(key: 'druck-0001', receiptId: 'KASSE1-ID-7', kind: 'print', at: 1790409480000, result: 'ok'),
          ])
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(log, hasLength(1));
      expect(isReceiptOutputError(e, 'validation'), isTrue);
      expect(receiptOutputFieldErrors(e), [const FieldError('entries', 'Ein bis 50 Einträge angeben.')]);
    });
  });

  group('Texte', () {
    test('Ausgaben am Belegdetail, Web und App gleich, mit genau diesem Wortlaut', () {
      const erwartet = <String, (String, List<String>?)>{
        'receipt.outputs_title': ('Ausgaben', null),
        'receipt.outputs_count': ('{count} Ausgaben', ['count']),
        'receipt.output_print': ('Erstdruck', null),
        'receipt.output_reprint': ('Duplikat', null),
        'receipt.output_email': ('E-Mail', null),
        'receipt.output_link_shared': ('Link geteilt', null),
        'receipt.output_pdf_shared': ('PDF geteilt', null),
        'receipt.output_opened': ('Link geöffnet ({count}×)', ['count']),
        'receipt.output_failed': ('fehlgeschlagen', null),
      };
      for (final MapEntry(key: schluessel, value: (text, platzhalter)) in erwartet.entries) {
        final eintrag = posLabels[schluessel];
        expect(eintrag, isNotNull, reason: schluessel);
        expect(eintrag!.text, text, reason: schluessel);
        expect(eintrag.placeholders, platzhalter, reason: schluessel);
        expect(eintrag.only, isNull, reason: '$schluessel: gilt auf beiden Seiten');
      }
      // Jede Art hat ihre Beschriftung unter receipt.output_<art>, und genau diese gibt es.
      for (final art in receiptOutputKinds) {
        expect(posLabels.containsKey('receipt.output_$art'), isTrue, reason: art);
      }
      expect(posLabels.keys.where((k) => k.startsWith('receipt.output')).toList()..sort(), erwartet.keys.toList()..sort());
      expect(labelText('receipt.output_opened', {'count': 3}), 'Link geöffnet (3×)');
      expect(labelText('receipt.outputs_count', {'count': 4}), '4 Ausgaben');
    });

    test('receiptOutputLabel: jede Art des Katalogs hat eine Beschriftung, die Vertragsdatei zeigt jede', () {
      for (final art in receiptOutputKinds) {
        expect(receiptOutputLabel(_o(art)), isA<String>(), reason: art);
      }
      final gezeigt = {
        for (final f in _lesefaelle)
          for (final o in (f['expected'] as List?) ?? const []) (o as Map)['kind'],
      };
      expect(gezeigt, containsAll(receiptOutputKinds));
      expect(labelText('receipt.output_failed'), 'fehlgeschlagen');
    });
  });
}
