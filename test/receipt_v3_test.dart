import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/pos.dart' show RegisterReceiptClient, CancellationState, ReceiptSummary, cardRefundReference;
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/register.dart' show RegisterTransport;

/// Der Beleg-, Storno- und Mailweg gegen den Vertrag `/v3`
/// (`test/fixtures/vertrag/v3/antworten/*.json`), Zwilling von
/// `test/receipts-v3.test.ts` im npm-Paket: jede Antwort wird mit den
/// englischen Namen gelesen, die Anbieterdaten erscheinen nur im Kanal `app`
/// (Kassenweg), und was hinausgeht, ist genau das, was der Vertrag zeigt.
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;
List<Map<String, dynamic>> _faelle(String pfad) => (_json(pfad)['cases'] as List).cast<Map<String, dynamic>>();

final _belege = _faelle('antworten/belege.json');
final _kasseBelege = _faelle('antworten/kasse-belege.json');
final _storno = _faelle('antworten/storno.json');
final _mail = _faelle('antworten/belegmail.json');
final _vokabular = _json('v3-vokabular.json');

Map<String, dynamic> _fall(List<Map<String, dynamic>> faelle, String name, {String? channel}) =>
    faelle.firstWhere((f) => f['name'] == name && (channel == null || f['channel'] == channel));

http.Response _antwort(Map<String, dynamic> fall) => http.Response(
      jsonEncode(fall['response']),
      fall['httpStatus'] as int,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
    );

KasseneckApi _api(http.Client client) =>
    KasseneckApi(apiKey: 'kr_test_x', cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')), httpClient: client);

RegisterReceiptClient _kasse(http.Client client) => RegisterReceiptClient(RegisterTransport(
      idToken: () async => 'id-token',
      sessionId: () async => 'sess',
      cashregisterId: 'KECK-1',
      httpClient: client,
    ));

/// Ein Mock, der genau eine Antwort gibt und die Anfragen mitschreibt.
({MockClient client, List<http.Request> log}) _einmal(Map<String, dynamic> fall) {
  final log = <http.Request>[];
  return (
    client: MockClient((r) async {
      log.add(r);
      return _antwort(fall);
    }),
    log: log,
  );
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

/// Die deutschen Namen, die `/v3` fuer [endpunkt] ersetzt (Werte der Schema-Zuordnung englisch -> deutsch).
Set<String> _deutscheNamen(String endpunkt) {
  final namen = <String>{};
  void lauf(Object? knoten) {
    if (knoten is Map) {
      for (final MapEntry(:key, :value) in knoten.entries) {
        if (key == '__' || key.startsWith(r'$')) continue;
        if (value is String && value != key) namen.add(value);
        if (value is Map && value['__'] is String && value['__'] != key) namen.add(value['__'] as String);
        lauf(value);
      }
    } else if (knoten is List) {
      for (final e in knoten) {
        lauf(e);
      }
    }
  }

  final schema = (_vokabular['schemas'] as Map)[endpunkt] as Map;
  lauf(schema['params']);
  lauf(schema['data']);
  return namen;
}

Set<String> _alleSchluessel(Object? knoten) => switch (knoten) {
      Map() => {for (final MapEntry(:key, :value) in knoten.entries) ...{key as String, ..._alleSchluessel(value)}},
      List() => {for (final e in knoten) ..._alleSchluessel(e)},
      _ => const <String>{},
    };

void _pruefeBeleg(KasseneckReceipt r, Map<String, dynamic> daten, String wo, {required bool kassenweg}) {
  final roh = daten['receipt'] as Map<String, dynamic>;
  expect(r.receiptId, roh['receiptId'], reason: wo);
  expect(r.vatId, daten['vatId'], reason: wo);
  expect(r.taxNumber, daten['taxNumber'], reason: wo);
  expect(r.testCashregister, daten['testCashregister'], reason: wo);
  expect(r.testSignature, daten['testSignature'], reason: wo);
  expect(r.headerVersionId, daten['headerVersionId'], reason: wo);
  expect(r.logoScale.code, daten['logo_scale'], reason: wo);
  expect(r.registrationInfo, RegistrationInfo.fromJson(daten['registrationInfo']), reason: wo);
  expect(r.layoutRuleset, roh['layoutRuleset'], reason: wo);
  expect(r.layout, isNotNull, reason: wo);
  expect(r.layout!.toJson(), daten['layout'], reason: '$wo: Server-Layout Zeile fuer Zeile');
  expect(r.layout!.ruleset, 2, reason: wo);
  final zahlungen = (roh['payments'] as List?) ?? const [];
  expect(r.payments?.length ?? 0, zahlungen.length, reason: wo);
  for (final (i, z) in zahlungen.cast<Map<String, dynamic>>().indexed) {
    final ist = r.payments![i];
    expect(ist.providerPaymentId, z['providerPaymentId'], reason: '$wo Zahlung $i');
    expect(ist.providerData, z['providerData'], reason: '$wo Zahlung $i');
    if (!kassenweg) expect(ist.providerPaymentId, isNull, reason: '$wo: der oeffentliche Weg traegt keine Anbieterdaten');
  }
  for (final (i, p) in ((roh['items'] as List?) ?? const []).cast<Map<String, dynamic>>().indexed) {
    if (p['kind'] == 'tip') expect(r.items[i].receivedImmediately, p['receivedImmediately'], reason: '$wo Position $i');
  }
  final bezug = roh['cancellationOf'] as Map<String, dynamic>?;
  expect(r.cancellationOf?.toJson(), bezug, reason: wo);
  if (roh['cancellationReason'] != null) {
    expect(cancellationReasons.containsKey(r.cancellationReason), isTrue, reason: '$wo: ${r.cancellationReason}');
  }
}

void main() {
  group('Beleg lesen (createReceipt, getReceipt) je Kanal', () {
    for (final (datei, faelle, kassenweg) in [('belege', _belege, false), ('kasse-belege', _kasseBelege, true)]) {
      for (final fall in faelle) {
        final resp = fall['response'] as Map<String, dynamic>;
        if (resp['status'] != 'success' || !['createReceipt', 'getReceipt'].contains(fall['endpoint'])) continue;
        test('$datei/${fall['name']}: englische Namen, Anbieterdaten je Kanal, Rundreise ueber toJson', () {
          final daten = resp['data'] as Map<String, dynamic>;
          final r = KasseneckReceipt.fromJson(daten);
          _pruefeBeleg(r, daten, fall['name'] as String, kassenweg: kassenweg);
          final gespeichert = r.toJson();
          _pruefeBeleg(KasseneckReceipt.fromJson(gespeichert), daten, '${fall['name']} (gespeichert)', kassenweg: kassenweg);
          final deutsch = _deutscheNamen(fall['endpoint'] as String).intersection(_alleSchluessel(gespeichert));
          expect(deutsch, isEmpty, reason: 'deutsche 0.x-Namen in toJson');
        });
      }
    }
  });

  test('der Kassenweg (holen) liest den Kartenbeleg mit Kennung, der oeffentliche (getReceipt) ohne', () async {
    final app = _fall(_kasseBelege, 'get_card_receipt_with_cancellation');
    final k = _einmal(app);
    final ueberKasse = await _kasse(k.client).get('KECK-1-ID-2');
    expect(_params(k.log.single), {...app['params'] as Map, 'cashregisterId': 'KECK-1'});
    expect(k.log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/getReceipt');
    expect(cardRefundReference(ueberKasse, 'p1'), 'tx-4711');
    expect(ueberKasse.cancellations.single['refundedByPayment'], {'p1': 700});

    final api = _fall(_belege, 'get_card_receipt_with_cancellation');
    final a = _einmal(api);
    final oeffentlich = (await _api(a.client).getReceipt('KECK-1-ID-2'))!;
    expect(_params(a.log.single), api['params']);
    expect(
      () => cardRefundReference(oeffentlich, 'p1'),
      throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('Kassenweg'))),
    );
    expect(() => cardRefundReference(oeffentlich, 'p9'), throwsA(isA<KasseneckValidationError>()));
  });

  test('Bericht (getReportV2): Metadaten mit taxNumber und vatId', () {
    final daten = (_fall(_belege, 'report')['response'] as Map)['data'] as Map<String, dynamic>;
    final meta = daten['metadata'] as Map<String, dynamic>;
    final r = KasseneckReceipt.fromMetadata((daten['receipts'] as List).first, meta);
    expect(r.taxNumber, meta['taxNumber']);
    expect(r.vatId, meta['vatId']);
    expect(r.taxInfo, meta['vatId']);
  });

  test('payments_sum_mismatch: expectedCents aus den Details, genau ein Aufruf, abgelehnt', () async {
    final fall = _fall(_belege, 'error_payments_sum_mismatch');
    final m = _einmal(fall);
    Object? fehler;
    try {
      await _api(m.client).sellReceipt(
        payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 500)],
        items: [KasseneckItem.fromJson(((fall['params'] as Map)['items'] as List).first as Map<String, dynamic>)],
      );
    } catch (e) {
      fehler = e;
    }
    expect(fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', 'payments_sum_mismatch'));
    expect(paymentsExpectedCents(fehler), 600);
    expect(isOutcomeUnknown(fehler), isFalse);
    expect(m.log, hasLength(1));
    expect(paymentsExpectedCents(const KasseneckApiError('createReceipt', 'x', code: 'validation', details: {'expectedCents': 1})), isNull);
  });

  group('Storno je Kanal (storno.json)', () {
    List<KeckPaymentInput>? zahlungen(Map params) => (params['payments'] as List?)
        ?.cast<Map<String, dynamic>>()
        .map((z) => KeckPaymentInput(
              method: KeckPaymentMethod.values.byName(z['method'] as String),
              amountCents: z['amountCents'] as int,
              refundOf: z['refundOf'] as String?,
              provider: z['provider'] == null ? null : CreditCardProvider.values.byName(z['provider'] as String),
              providerPaymentId: z['providerPaymentId'] as String?,
              providerData: (z['providerData'] as Map?)?.cast<String, dynamic>(),
            ))
        .toList();

    Future<CancelReceiptResult> stornieren(Map<String, dynamic> fall, http.Client client) {
      final p = fall['params'] as Map<String, dynamic>;
      final positionen = (p['items'] as List?)?.cast<Map>().map((e) => (index: e['index'] as int, quantity: e['quantity'] as int)).toList();
      return fall['channel'] == 'app'
          ? _kasse(client).cancelReceipt(
              originalReceiptId: p['originalReceiptId'] as String,
              reason: p['reason'] as String,
              items: positionen,
              payments: zahlungen(p),
            )
          : _api(client).cancelReceipt(
              cashregisterId: p['cashregisterId'] as String,
              originalReceiptId: p['originalReceiptId'] as String,
              reason: p['reason'] as String,
              items: positionen,
              payments: zahlungen(p),
            );
    }

    for (final fall in _storno) {
      test('${fall['channel']}/${fall['name']}', () async {
        final m = _einmal(fall);
        final resp = fall['response'] as Map<String, dynamic>;
        final reason = (fall['params'] as Map)['reason'];
        if (!cancellationReasons.containsKey(reason)) {
          // Unbekannter und alter deutscher Grund: faellt vor dem Senden.
          await expectLater(stornieren(fall, m.client), throwsA(isA<KasseneckValidationError>()));
          expect(m.log, isEmpty);
          return;
        }
        if (resp['status'] == 'success') {
          final erg = await stornieren(fall, m.client);
          final daten = resp['data'] as Map<String, dynamic>;
          expect(erg.originalReceiptId, (daten['cancellationOf'] as Map)['receiptId']);
          expect(erg.originalFullReceiptId, (daten['cancellationOf'] as Map)['fullReceiptId']);
          expect(erg.originalTimeStamp, (daten['cancellationOf'] as Map)['timeStamp']);
          expect(erg.remaining, daten['remaining']);
          expect(erg.receipt.cancellationReason, (daten['receipt'] as Map)['cancellationReason']);
          expect(erg.receipt.cancellationOf?.timeStamp, isNotNull);
        } else {
          await expectLater(
            stornieren(fall, m.client),
            throwsA(isA<KasseneckApiError>()
                .having((e) => e.code, 'code', resp['code'])
                .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)),
          );
          expect(isCancellationErrorCode(resp['code']), isTrue);
        }
        expect(m.log, hasLength(1));
        expect(_params(m.log.single), fall['params'], reason: 'genau die Parameter des Vertrags');
      });
    }

    test('Karten-Storno im Kanal api ohne Kennung der Erstattung, aber mit Original vom oeffentlichen Weg: wirft, nichts geht hinaus',
        () async {
      final original = KasseneckReceipt.fromJson(
          (_fall(_belege, 'get_card_receipt_with_cancellation')['response'] as Map)['data'] as Map<String, dynamic>);
      final m = _einmal(_fall(_storno, 'cancel_full_card_refund', channel: 'api'));
      await expectLater(
        _api(m.client).cancelReceipt(
          cashregisterId: 'KECK-1',
          originalReceiptId: 'KECK-1-ID-2',
          reason: 'input_error',
          original: original,
          payments: const [
            KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1', provider: CreditCardProvider.sumup),
          ],
        ),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(m.log, isEmpty);
    });

    test('Karten-Storno im Kanal app: das Original vom Kassenweg liefert den Bezug, genau ein Aufruf', () async {
      final original = KasseneckReceipt.fromJson(
          (_fall(_kasseBelege, 'get_card_receipt_with_cancellation')['response'] as Map)['data'] as Map<String, dynamic>);
      final m = _einmal(_fall(_storno, 'cancel_full_card_refund', channel: 'app'));
      await _kasse(m.client).cancelReceipt(
        originalReceiptId: 'KECK-1-ID-2',
        reason: 'input_error',
        original: original,
        payments: const [
          KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1', provider: CreditCardProvider.sumup),
        ],
      );
      expect(m.log, hasLength(1));
    });
  });

  group('Belegmail (belegmail.json)', () {
    for (final fall in _mail) {
      final params = fall['params'] as Map<String, dynamic>;
      if (params.containsKey('sprache')) {
        test('${fall['name']}: der alte Parameter sprache geht nie hinaus', () async {
          final m = _einmal(_fall(_mail, 'via_own_mailbox'));
          await _api(m.client).sendReceiptEmail(fullReceiptId: 'voll', to: 'max@example.at', language: 'de');
          expect(_params(m.log.single).containsKey('sprache'), isFalse);
          expect(_params(m.log.single)['language'], 'de');
        });
        continue;
      }
      test('${fall['name']}: Parameter wie im Vertrag, via und Codes englisch', () async {
        final m = _einmal(fall);
        final resp = fall['response'] as Map<String, dynamic>;
        final aufruf = _api(m.client).sendReceiptEmail(
          fullReceiptId: params['fullReceiptId'] as String,
          to: params['to'] as String,
          language: params['language'] as String?,
        );
        if (resp['status'] == 'success') {
          final erg = await aufruf;
          expect(erg.via, (resp['data'] as Map)['via']);
          expect(erg.at, (resp['data'] as Map)['at']);
        } else {
          await expectLater(aufruf, throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', resp['code'])));
          expect(isReceiptEmailErrorCode(resp['code']), isTrue);
        }
        expect(_params(m.log.single), params);
      });
    }
  });

  test('Belegliste: cancellationStatus englisch, unbekannt bleibt unknown, fehlend bleibt null', () {
    for (final (roh, soll) in [
      ('none', CancellationState.none),
      ('partial', CancellationState.partial),
      ('full', CancellationState.full),
      ('voll', CancellationState.unknown),
      ('refunded', CancellationState.unknown),
    ]) {
      expect(ReceiptSummary.fromJson({'receiptId': 'X', 'cancellationStatus': roh}).cancellationState, soll, reason: roh);
    }
    expect(ReceiptSummary.fromJson({'receiptId': 'X'}).cancellationState, isNull);
    expect(ReceiptSummary.fromJson({'receiptId': 'X', 'stornoStand': 'voll'}).cancellationState, isNull, reason: 'alter Schluessel');
  });

  test('migrateStoredReceiptJson: ein in 9.x gespeicherter Beleg liest sich nach dem Update unveraendert', () {
    final daten = (_fall(_kasseBelege, 'get_zero_receipt')['response'] as Map)['data'] as Map<String, dynamic>;
    final neu = KasseneckReceipt.fromJson(daten);
    // Die Form, die 9.x mit toJson abgelegt hat (0.x-Namen).
    final gespeichert = neu.toJson();
    final layout = gespeichert.remove('layout') as Map<String, dynamic>;
    final alt = <String, dynamic>{
      for (final MapEntry(:key, :value) in gespeichert.entries)
        switch (key) {
          'vatId' => 'uid',
          'taxNumber' => 'taxnr',
          'logo_scale' => 'logo_skala',
          'testCashregister' => 'testKasse',
          'testSignature' => 'testSignatur',
          'headerVersionId' => 'kopfId',
          _ => key,
        }: value,
      'layout': {
        'paperSize': layout['paperSize'],
        'regelwerk': layout['ruleset'],
        'lines': [
          for (final z in (layout['lines'] as List).cast<Map<String, dynamic>>())
            if (z['kind'] == 'banner') {'kind': 'banner', 'text': z['text'], 'ton': z['tone'] == 'warning' ? 'warnung' : 'belegart'} else z,
        ],
      },
    }..remove('registrationInfo');
    alt['pruefangaben'] = {
      'karteRegistriertAm': neu.registrationInfo?.cardRegisteredAt,
      'kasseRegistriertAm': neu.registrationInfo?.cashregisterRegisteredAt,
    };
    final kopie = jsonDecode(jsonEncode(alt)) as Map<String, dynamic>;
    final gelesen = KasseneckReceipt.fromJson(migrateStoredReceiptJson(kopie));
    expect(jsonEncode(kopie), jsonEncode(alt), reason: 'die Eingabe bleibt unberuehrt');
    expect(gelesen.toJson(), neu.toJson());
    // Ohne Migration gingen UID, Test-Kennzeichen und Warnung still verloren.
    final ohne = KasseneckReceipt.fromJson(kopie);
    expect(ohne.vatId, isNull);
    expect(ohne.testCashregister, isFalse);
  });
}
