import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/partner.dart';
import 'package:kasseneck_api/src/aufrufe.dart';

/// Der Partner-Client gegen eine Attrappe: was geht raus, was kommt an, und
/// was macht er aus einem Fehler.
///
/// Der Zwilling dieser Datei ist `test/partner-client.test.ts` im JS-Paket.
void main() {
  const partnerKey = 'pk_live_GEHEIMERPARTNERSCHLUESSEL42';

  const betrieb = <String, dynamic>{
    'company_name': 'Bäckerei Jobst e.U.',
    'rechtsform': 'eu',
    'email': 'chef@jobst.at',
    'address': <String, dynamic>{'street': 'Hauptstrasse', 'number': '12a', 'zip': '5020', 'city': 'Salzburg'},
    'bundesland': 'salzburg',
    'tax_details': <String, dynamic>{'taxnr': '12-345/6789', 'is_small_business': false},
    'contacts': <dynamic>[
      <String, dynamic>{'name': 'Anna Jobst', 'email': 'anna@jobst.at'}
    ],
  };

  /// Ein Client, der die übergebenen Antworten der Reihe nach liefert.
  ({PartnerApi api, List<http.Request> log}) stelle(
    List<Map<String, dynamic>> antworten, {
    AvvModus modus = AvvModus.vollmacht,
  }) {
    final log = <http.Request>[];
    var i = 0;
    final mock = MockClient((request) async {
      log.add(request);
      final a = antworten[i < antworten.length ? i : antworten.length - 1];
      i++;
      return http.Response(jsonEncode(a), 200, headers: <String, String>{'content-type': 'application/json'});
    });
    return (
      api: PartnerApi(partnerKey: partnerKey, httpClient: mock, avvModus: modus),
      log: log,
    );
  }

  Map<String, dynamic> erfolg(Map<String, dynamic> data) =>
      <String, dynamic>{'status': 'success', 'message': 'ok', 'data': data};
  Map<String, dynamic> fehler(String message, Map<String, dynamic> data) =>
      <String, dynamic>{'status': 'error', 'message': message, 'data': data};

  Map<String, dynamic> params(http.Request r) =>
      Map<String, dynamic>.from(jsonDecode(r.body)['params'] as Map);

  // -------------------------------------------------------------------------
  // Anmeldung
  // -------------------------------------------------------------------------

  test('der Schlüssel geht als Bearer raus, ohne Kassen-Token', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'partner': <String, dynamic>{'id': 'ptn_1', 'name': 'Muster GmbH', 'status': 'aktiv'},
        'env': 'live',
      })
    ]);
    await f.api.getPartnerInfo();
    final a = f.log.single;
    expect(a.url.toString(), 'https://api.kasseneck.at/v1/getPartnerInfo');
    expect(a.method, 'POST');
    expect(a.headers['Authorization'], 'Bearer $partnerKey');
    // Ein Partner arbeitet nie an einer Kasse — die Kopfzeile hat hier nichts
    // verloren.
    expect(a.headers.containsKey('cashregister-token'), isFalse);
    expect(params(a), <String, dynamic>{});
  });

  test('ein Betriebsschlüssel wird vor dem Senden abgelehnt', () {
    // kr_live_… ist ein tadelloser Schlüssel — nur für einen anderen Weg. Ohne
    // diese Prüfung käme ein nichtssagendes „ungültiger Schlüssel" vom Server.
    expect(() => PartnerApi(partnerKey: 'kr_live_ABCDEFGHIJKLMNOPQ'), throwsA(isA<KasseneckValidationError>()));
    expect(() => PartnerApi(partnerKey: ''), throwsA(isA<KasseneckValidationError>()));
    expect(() => PartnerApi(partnerKey: 'pk_live_kurz'), throwsA(isA<KasseneckValidationError>()));
  });

  test('kein Fehler nennt den Schlüssel', () {
    try {
      PartnerApi(partnerKey: 'kr_live_GEHEIMERKUNDENSCHLUESSEL');
      fail('hätte werfen müssen');
    } on KasseneckValidationError catch (e) {
      expect(e.toString(), isNot(contains('GEHEIMERKUNDENSCHLUESSEL')));
    }
  });

  test('die Umgebung steht im Schlüssel und ist ohne Netz ablesbar', () {
    expect(partnerSchluesselEnv('pk_test_ABCDEFGHIJKLMNOPQ'), 'test');
    expect(partnerSchluesselEnv(partnerKey), 'live');
    expect(partnerSchluesselEnv('kr_live_ABCDEFGHIJKLMNOPQ'), isNull);
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    expect(f.api.env, 'live');
  });

  // -------------------------------------------------------------------------
  // Betriebe
  // -------------------------------------------------------------------------

  test('createPartnerCustomer sendet appId, betrieb und den Idempotenzschlüssel', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'customerId': 'cust_1',
        'status': 'angelegt',
        'env': 'live',
        'firma': 'Bäckerei Jobst e.U.',
        'appId': 'app_1',
        'zugang': <String, dynamic>{'eingeladen': true, 'sentTo': 'c***@jobst.at'},
        'naechsteSchritte': <dynamic>['FinanzOnline-Link senden'],
      })
    ]);
    final r = await f.api.createPartnerCustomer(
      appId: 'app_1',
      betrieb: betrieb,
      idempotencyKey: 'eigene-kundennummer-4711',
    );
    expect(params(f.log.single), <String, dynamic>{
      'appId': 'app_1',
      'betrieb': betrieb,
      'idempotencyKey': 'eigene-kundennummer-4711',
    });
    expect(r.customerId, 'cust_1');
    expect(r.eingeladen, isTrue);
    expect(r.sentTo, 'c***@jobst.at');
    expect(r.wiederholt, isFalse);
  });

  test('eine wiederholte Anlage meldet sich als solche', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'cust_1', 'wiederholt': true, 'zugang': <String, dynamic>{}})
    ]);
    final r = await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb, idempotencyKey: 'x');
    expect(r.wiederholt, isTrue);
  });

  test('einladen:false wird als zugang-Objekt gesendet, sonst gar nicht', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'cust_1'}),
      erfolg(<String, dynamic>{'customerId': 'cust_2'}),
    ]);
    await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb, einladen: false);
    expect(params(f.log[0])['zugang'], <String, dynamic>{'einladen': false});
    await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb);
    // Nicht gesetzt heisst nicht gesendet — sonst hielte das Backend die
    // Vorgabe für eine ausdrückliche Angabe.
    expect(params(f.log[1]).containsKey('zugang'), isFalse);
  });

  test('fehlende Pflichtangaben gehen gar nicht erst raus', () async {
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    await expectLater(
      f.api.createPartnerCustomer(appId: '', betrieb: betrieb),
      throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')),
    );
    await expectLater(f.api.getPartnerCustomer('  '), throwsA(isA<KasseneckValidationError>()));
    await expectLater(f.api.activateCashregister('cust_1', ''), throwsA(isA<KasseneckValidationError>()));
    expect(f.log, isEmpty, reason: 'es wurde trotzdem gesendet');
  });

  test('listPartnerCustomers seitenweise, mit Grenzen für limit', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'kunden': <dynamic>[
          <String, dynamic>{
            'customerId': 'cust_1',
            'firma': 'A',
            'status': 'live',
            'appId': 'app_1',
            'env': 'live',
            'createdAt': 5,
          }
        ],
        'cursor': 'weiter',
        'gesamt': 12,
      })
    ]);
    final r = await f.api.listPartnerCustomers(status: 'live', limit: 50, cursor: 'a');
    expect(params(f.log.single), <String, dynamic>{'status': 'live', 'limit': 50, 'cursor': 'a'});
    expect(r.cursor, 'weiter');
    expect(r.gesamt, 12);
    expect(r.kunden.single.customerId, 'cust_1');
    expect(r.kunden.single.avv, isNull, reason: 'ohne avv-Feld darf kein Stand erfunden werden');
    await expectLater(f.api.listPartnerCustomers(limit: 0), throwsA(isA<KasseneckValidationError>()));
    await expectLater(f.api.listPartnerCustomers(limit: 201), throwsA(isA<KasseneckValidationError>()));
  });

  test('getPartnerCustomer liest die Hülle "kunde" und fällt nicht über null-Felder', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'kunde': <String, dynamic>{
          'customerId': 'cust_1',
          'firma': 'A',
          'status': 'signatur_bereit',
          'env': 'test',
          'liveEnabled': false,
          'appId': null,
          'angelegtVia': 'api',
          'betrieb': <String, dynamic>{'company_name': 'A'},
          'fon': <String, dynamic>{'eingerichtet': true, 'verifiedAt': 99},
          'zugang': null,
        }
      })
    ]);
    final k = await f.api.getPartnerCustomer('cust_1');
    expect(k.status, 'signatur_bereit');
    expect(k.zeile.env, PartnerEnv.test);
    expect(k.fonEingerichtet, isTrue);
    expect(k.zugangEmail, isNull);
    expect(k.zeile.appId, isNull);
  });

  test('eine Antwort ohne die zugesagte Hülle wirft, statt später zu überraschen', () async {
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{'irgendwas': 1})]);
    await expectLater(
      f.api.getPartnerCustomer('cust_1'),
      throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
    );
  });

  test('sendPartnerCustomerFonLink gibt den Empfänger maskiert zurück', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'cust_1', 'sentTo': 'c***@jobst.at', 'expiresAt': 123})
    ]);
    final r = await f.api.sendPartnerCustomerFonLink('cust_1');
    expect(r.sentTo, 'c***@jobst.at');
    expect(r.expiresAt, 123);
  });

  // -------------------------------------------------------------------------
  // Signatur und Kassen
  // -------------------------------------------------------------------------

  test('requestCustomerSignature liefert den Antrag; ein zweiter Ruf den laufenden', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'antrag': <String, dynamic>{
          'requestId': 'req_1',
          'status': 'beantragt',
          'statusText': 'Beantragt',
          'art': 'signaturkarte',
          'historie': <dynamic>[],
        },
        'wiederholt': true,
        'hinweis': 'Es lief bereits ein Antrag.',
      })
    ]);
    final r = await f.api.requestCustomerSignature('cust_1');
    expect(params(f.log.single), <String, dynamic>{'customerId': 'cust_1'});
    expect(r.antrag.requestId, 'req_1');
    expect(r.wiederholt, isTrue);
    expect(r.hinweis, 'Es lief bereits ein Antrag.');
  });

  test('getCustomerSignatureStatus trennt "bereit" von "registriert"', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'signatur': <String, dynamic>{'bereit': false, 'signatureId': null, 'vdaId': null},
        'antraege': <dynamic>[
          <String, dynamic>{'requestId': 'req_1', 'status': 'registriert', 'statusText': 'Bei FinanzOnline registriert'}
        ],
        'fon': <String, dynamic>{'vorhanden': true, 'geprueftAt': 7},
      })
    ]);
    final s = await f.api.getCustomerSignatureStatus('cust_1');
    expect(s.bereit, isFalse);
    expect(s.antraege.single.status, 'registriert');
    expect(s.fonVorhanden, isTrue);
  });

  test('createCustomerCashregister darf vor der Signatur laufen und sagt, warum nichts geschah', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'kasse': <String, dynamic>{
          'cashregisterId': 'kasse_1',
          'name': 'Theke',
          'status': 'entwurf',
          'statusText': 'Entwurf',
          'automatisch': true,
          'schritt': 'signatur',
          'schrittText': 'Signaturkarte zuweisen',
          'erledigt': <dynamic>[],
          'schritte': <dynamic>[
            <String, dynamic>{'key': 'signatur', 'text': 'Signaturkarte zuweisen'}
          ],
          'versuche': 0,
        },
        'inbetriebnahme': <String, dynamic>{
          'gestartet': false,
          'ok': null,
          'schritt': null,
          'grund': 'signature_not_ready',
        },
      })
    ]);
    final r = await f.api.createCustomerCashregister(customerId: 'cust_1', name: 'Theke');
    expect(params(f.log.single), <String, dynamic>{'customerId': 'cust_1', 'name': 'Theke'});
    expect(r.kasse.status, 'entwurf');
    expect(r.kasse.istLive, isFalse);
    expect(r.kasse.automatisch, isTrue);
    expect(r.grund, 'signature_not_ready');
    expect(r.ok, isNull, reason: 'ok:null heisst „nicht gelaufen" und darf nicht zu false werden');
  });

  test('ein zu langer Kassenname geht nicht raus', () async {
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    await expectLater(
      f.api.createCustomerCashregister(customerId: 'cust_1', name: 'x' * 61),
      throwsA(isA<KasseneckValidationError>()),
    );
    expect(f.log, isEmpty);
  });

  test('activateCashregister meldet eine bereits laufende Kasse als unverändert', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'kasse': <String, dynamic>{
          'cashregisterId': 'kasse_1',
          'status': 'live',
          'statusText': 'In Betrieb',
          'schritt': null,
        },
        'unveraendert': true,
      })
    ]);
    final r = await f.api.activateCashregister('cust_1', 'kasse_1');
    expect(params(f.log.single), <String, dynamic>{'customerId': 'cust_1', 'cashregisterId': 'kasse_1'});
    expect(r.unveraendert, isTrue);
    expect(r.kasse.schritt, isNull);
    expect(r.kasse.istLive, isTrue);
  });

  test('listCustomerCashregisters bringt nie Token', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'customerId': 'cust_1',
        'kassen': <dynamic>[
          <String, dynamic>{'cashregisterId': 'kasse_1', 'status': 'live'}
        ],
        'signaturBereit': true,
      })
    ]);
    final r = await f.api.listCustomerCashregisters('cust_1');
    expect(r.signaturBereit, isTrue);
    // Der Typ führt gar kein Token-Feld — die Zusicherung steht im Typ, hier
    // wird sie nur an der echten Antwort nachvollzogen.
    expect(r.kassen.single.cashregisterId, 'kasse_1');
  });

  test('getCustomerCredentials hüllt die Geheimnisse', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'customerId': 'cust_1',
        'firma': 'A',
        'env': 'live',
        'apiKey': 'kr_live_GEHEIM',
        'kassen': <dynamic>[
          <String, dynamic>{'cashregisterId': 'kasse_1', 'live': true, 'cashregisterToken': 'cb_live_GEHEIM'}
        ],
        'hinweis': 'Nur verschlüsselt speichern.',
      })
    ]);
    final z = await f.api.getCustomerCredentials('cust_1');
    expect(z.apiKey.reveal(), 'kr_live_GEHEIM');
    expect(z.toString(), isNot(contains('kr_live_GEHEIM')));
    expect(z.kassen.single.cashregisterToken.reveal(), 'cb_live_GEHEIM');
  });

  // -------------------------------------------------------------------------
  // Vertrag
  // -------------------------------------------------------------------------

  test('reportCustomerVertrag übersetzt customerId auf das Feld kundeId', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'vertragId': 'v_1', 'bestaetigtAt': 5, 'art': 'avv', 'version': '2026-08'})
    ]);
    final r = await f.api.reportCustomerVertrag(
      customerId: 'cust_1',
      version: '2026-08',
      textHash: 'abc',
      name: 'Anna Jobst',
      funktion: 'Inhaberin',
      akzeptiertAt: 42,
    );
    // Der Endpunkt heisst das Feld kundeId; der Client nennt es überall
    // customerId. Zwei Namen für dieselbe Kennung wären eine Fehlerquelle.
    expect(params(f.log.single), <String, dynamic>{
      'kundeId': 'cust_1',
      'art': 'avv',
      'version': '2026-08',
      'textHash': 'abc',
      'name': 'Anna Jobst',
      'funktion': 'Inhaberin',
      'akzeptiertAt': 42,
    });
    expect(r.vertragId, 'v_1');
  });

  test('in Vollmacht lässt sich nur der AVV melden — der Client sendet nichts anderes', () async {
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    await expectLater(
      f.api.reportCustomerVertrag(
        customerId: 'cust_1',
        version: '1',
        textHash: 'a',
        name: 'A',
        funktion: 'B',
        art: 'nutzung',
      ),
      throwsA(isA<KasseneckValidationError>()),
    );
    expect(f.log, isEmpty);
  });

  // -------------------------------------------------------------------------
  // Webhook-Verwaltung
  // -------------------------------------------------------------------------

  test('createPartnerWebhook liefert das Secret — und wirft, wenn es fehlt', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'webhook': <String, dynamic>{
          'webhookId': 'wh_1',
          'url': 'https://api.firma.at/hook',
          'events': <dynamic>['signature.ready'],
          'aktiv': true,
        },
        'secret': 'whsec_1',
      })
    ]);
    final r = await f.api.createPartnerWebhook(
      url: 'https://api.firma.at/hook',
      events: <String>['signature.ready'],
    );
    expect(params(f.log.single), <String, dynamic>{
      'url': 'https://api.firma.at/hook',
      'events': <dynamic>['signature.ready'],
    });
    expect(r.secret, 'whsec_1');
    expect(r.webhook.aktiv, isTrue);

    final ohne = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'webhook': <String, dynamic>{'webhookId': 'wh_1'}
      })
    ]);
    await expectLater(
      ohne.api.createPartnerWebhook(url: 'https://api.firma.at/hook', events: <String>['webhook.test']),
      throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
    );
  });

  test('ein Webhook ohne Ereignis geht nicht raus', () async {
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    await expectLater(
      f.api.createPartnerWebhook(url: 'https://api.firma.at/hook', events: <String>[]),
      throwsA(isA<KasseneckValidationError>()),
    );
    expect(f.log, isEmpty);
  });

  test('listPartnerWebhooks bringt den Ereignis-Katalog mit', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'webhooks': <dynamic>[
          <String, dynamic>{'webhookId': 'wh_1', 'aktiv': false}
        ],
        'ereignisse': <dynamic>[
          <String, dynamic>{'key': 'webhook.test', 'text': 'Testereignis'}
        ],
      })
    ]);
    final r = await f.api.listPartnerWebhooks();
    expect(r.webhooks.single.aktiv, isFalse);
    expect(r.ereignisse.single.key, 'webhook.test');
  });

  test('updatePartnerWebhook verlangt eine Änderung, deletePartnerWebhook eine Kennung', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'webhook': <String, dynamic>{'webhookId': 'wh_1', 'aktiv': false}
      }),
      erfolg(<String, dynamic>{'webhookId': 'wh_1', 'geloescht': true}),
    ]);
    final w = await f.api.updatePartnerWebhook('wh_1', <String, dynamic>{'aktiv': false});
    expect(params(f.log.first), <String, dynamic>{
      'webhookId': 'wh_1',
      'patch': <String, dynamic>{'aktiv': false}
    });
    expect(w.aktiv, isFalse);
    expect(await f.api.deletePartnerWebhook('wh_1'), 'wh_1');
    await expectLater(
      f.api.updatePartnerWebhook('wh_1', <String, dynamic>{}),
      throwsA(isA<KasseneckValidationError>()),
    );
    await expectLater(f.api.deletePartnerWebhook(''), throwsA(isA<KasseneckValidationError>()));
  });

  test('sendPartnerWebhookTest und listPartnerWebhookDeliveries', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'eventId': 'evt_1',
        'zustellungen': <dynamic>[
          <String, dynamic>{'deliveryId': 'dlv_1'}
        ]
      }),
      erfolg(<String, dynamic>{
        'zustellungen': <dynamic>[
          <String, dynamic>{
            'deliveryId': 'dlv_1',
            'webhookId': 'wh_1',
            'event': 'webhook.test',
            'eventId': 'evt_1',
            'status': 'fehlgeschlagen',
            'versuche': 6,
            'statusCode': 500,
            'antwort': 'boom',
          }
        ]
      }),
    ]);
    final t = await f.api.sendPartnerWebhookTest('wh_1');
    expect(t.eventId, 'evt_1');
    final z = await f.api.listPartnerWebhookDeliveries(webhookId: 'wh_1', limit: 10);
    expect(params(f.log[1]), <String, dynamic>{'webhookId': 'wh_1', 'limit': 10});
    expect(z.single.status, 'fehlgeschlagen');
    expect(z.single.statusCode, 500);
    await expectLater(
      f.api.listPartnerWebhookDeliveries(limit: 999),
      throwsA(isA<KasseneckValidationError>()),
    );
  });

  // -------------------------------------------------------------------------
  // Fehlercodes
  // -------------------------------------------------------------------------

  test('jeder Fehlercode kommt maschinenlesbar an und trägt einen Handlungssatz', () async {
    for (final code in kPartnerFehlerCodes) {
      final f = stelle(<Map<String, dynamic>>[
        fehler('Etwas ging schief.', <String, dynamic>{'code': code})
      ]);
      try {
        await f.api.getPartnerInfo();
        fail('$code: hätte werfen müssen');
      } on KasseneckApiError catch (e) {
        expect(partnerFehlerCode(e), code);
        expect(istPartnerFehler(e, code), isTrue);
        final rat = partnerFehlerRat(code, AvvModus.vollmacht);
        expect(rat, isNotNull, reason: '$code: kein Handlungssatz');
        expect(rat!.length, greaterThan(20), reason: '$code: Handlungssatz zu dünn');
      }
    }
  });

  test('die Beilagen eines Fehlers kommen mit — schritt, rc, verschachteltes', () async {
    final f = stelle(<Map<String, dynamic>>[
      fehler('Die Inbetriebnahme ist hängen geblieben.', <String, dynamic>{
        'code': 'activation_failed',
        'schritt': 'uebermitteln',
        'rc': 'B13',
        'kasse': <String, dynamic>{'cashregisterId': 'kasse_1', 'status': 'fehlgeschlagen'},
      })
    ]);
    try {
      await f.api.activateCashregister('cust_1', 'kasse_1');
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(e.code, 'activation_failed');
      expect(e.details['schritt'], 'uebermitteln');
      expect(e.details['rc'], 'B13');
      // Auch die verschachtelte Beilage überlebt das Sieb — sie sagt dem
      // Aufrufer, wo genau die Kette steht.
      expect((e.details['kasse'] as Map)['status'], 'fehlgeschlagen');
      expect(e.message, 'Die Inbetriebnahme ist hängen geblieben.');
    }
  });

  test('validation liefert Feld und Grund, rate_limited die Wartezeit', () async {
    final v = stelle(<Map<String, dynamic>>[
      fehler('Bitte Eingaben prüfen.', <String, dynamic>{
        'code': 'validation',
        'errors': <dynamic>[
          <String, dynamic>{'field': 'tax_details.taxnr', 'message': 'Prüfziffer stimmt nicht.'}
        ],
      })
    ]);
    try {
      await v.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb);
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      final felder = partnerFeldFehler(e);
      expect(felder.single.field, 'tax_details.taxnr');
      expect(felder.single.message, 'Prüfziffer stimmt nicht.');
    }

    final r = stelle(<Map<String, dynamic>>[
      fehler('Zu viele Aufrufe.', <String, dynamic>{'code': 'rate_limited', 'retryAfterSec': 42})
    ]);
    try {
      await r.api.getPartnerInfo();
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(partnerWartezeitSek(e), 42);
    }
  });

  test('ein Fehler ohne Code bleibt ohne Code — kein geratener Wert', () async {
    final f = stelle(<Map<String, dynamic>>[fehler('Betrieb nicht gefunden.', <String, dynamic>{})]);
    try {
      await f.api.getPartnerCustomer('cust_fremd');
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(e.code, isNull);
      expect(partnerFehlerCode(e), isNull);
      expect(partnerFeldFehler(e), isEmpty);
      expect(partnerWartezeitSek(e), isNull);
    }
  });

  test('kein gesendetes Geheimnis kommt über die Fehler-Beilage zurück', () async {
    // Ein feindlicher oder verwirrter Proxy könnte den Bearer zurückspiegeln.
    // Das Sieb wirft jeden Wert weg, der mit dem gesendeten Schlüssel
    // überlappt.
    final f = stelle(<Map<String, dynamic>>[
      fehler('Fehler.', <String, dynamic>{
        'code': 'not_found',
        'echo': partnerKey,
        'teil': partnerKey.substring(0, 20),
      })
    ]);
    try {
      await f.api.getPartnerInfo();
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(e.details['echo'], isNull);
      expect(e.details['teil'], isNull);
      expect('${e.toString()} ${e.details}', isNot(contains(partnerKey)));
    }
  });

  // -------------------------------------------------------------------------
  // Vertragsweg und Ablauf
  // -------------------------------------------------------------------------

  test('vertrag_offen nennt den Weg, der für dieses Konto gilt', () async {
    for (final modus in AvvModus.values) {
      final rat = vertragOffenRat(modus);
      expect(rat, contains(modus.name), reason: 'der Rat für "${modus.name}" nennt den Weg nicht');
      expect(rat, contains('Auftragsverarbeitungsvertrag'));
    }
    // Die Wege unterscheiden sich wirklich — sonst wäre die Fallunterscheidung
    // Zierde.
    expect(AvvModus.values.map(vertragOffenRat).toSet().length, AvvModus.values.length);

    final f = stelle(<Map<String, dynamic>>[
      fehler('Der Betrieb hat den Vertrag noch nicht bestätigt.', <String, dynamic>{'code': 'vertrag_offen'})
    ]);
    try {
      await f.api.activateCashregister('cust_1', 'kasse_1');
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(istPartnerFehler(e, 'vertrag_offen'), isTrue);
      // Die Fassade wurde mit AvvModus.vollmacht gebaut.
      expect(f.api.vertragOffenHinweis, contains('vollmacht'));
      expect(f.api.fehlerRat('vertrag_offen'), f.api.vertragOffenHinweis);
      expect(f.api.avvModus, AvvModus.vollmacht);
    }
  });

  test('der Vertragsstand kommt je Betrieb mit und schlägt die Einstellung', () async {
    // Die Fassade ist mit AvvModus.vollmacht gebaut; der Betrieb sagt aber
    // 'unterauftrag'. Massgeblich ist der Betrieb — die Einstellung ist nur der
    // Rückfall für den Moment, in dem noch keiner geladen ist.
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'kunde': <String, dynamic>{
          'customerId': 'cust_1',
          'status': 'angelegt',
          'avv': <String, dynamic>{
            'status': 'offen',
            'version': null,
            'bestaetigtAt': null,
            'modus': 'unterauftrag',
          },
        }
      })
    ]);
    final kunde = await f.api.getPartnerCustomer('cust_1');
    expect(kunde.avv!.status, 'offen');
    expect(kunde.avv!.erfuellt, isFalse);
    expect(kunde.avv!.modus, AvvModus.unterauftrag);
    expect(f.api.vertragOffenHinweisFuer(kunde.avv), contains('unterauftrag'));
    expect(f.api.vertragOffenHinweis, contains('vollmacht'));

    // Ohne Stand (ältere Backend-Fassung) fällt es auf die Einstellung zurück.
    expect(f.api.vertragOffenHinweisFuer(null), contains('vollmacht'));
    // Ein unbekannter Weg wird nicht geraten, sondern fällt auf die Vorgabe.
    expect(AvvStand.aus(<String, dynamic>{'modus': 'erfunden'})!.modus, kAvvModusStandard);
  });

  test('der Ablauf steht als Daten da und ist in sich schlüssig', () {
    expect(kPartnerAblauf.map((s) => s.key).toList(),
        <String>['betrieb', 'fon', 'avv', 'signatur', 'kasse', 'zugangsdaten', 'belege']);
    // Jeder Aufruf der Kette ist einer, den dieses Paket wirklich kennt — ein
    // Schritt, der auf einen erfundenen Endpunkt zeigt, wäre schlimmer als
    // keiner.
    for (final schritt in kPartnerAblauf) {
      if (schritt.aufruf == null) continue;
      expect(Aufrufe.alle, contains(schritt.aufruf), reason: 'unbekannter Aufruf: ${schritt.aufruf}');
    }
    expect(naechsterSchritt('angelegt')?.key, 'fon');
    expect(naechsterSchritt('signatur_bereit')?.key, 'kasse');
    expect(naechsterSchritt('live')?.key, 'zugangsdaten');
    expect(naechsterSchritt('gesperrt'), isNull);
    expect(naechsterSchritt('etwas_neues'), isNull);
  });

  test('alle Aufrufe der Partner-API stehen in der Aufrufliste', () {
    // Der Vertrag mit dem JS-Zwilling und den Hosting-Weiterleitungen liest
    // genau diese Liste. Ein Aufruf, der hier fehlt, hat in Produktion keine
    // Adresse — und fällt als „HTML statt JSON" auf, nicht als 404.
    for (final name in <String>[
      Aufrufe.getPartnerInfo,
      Aufrufe.createPartnerCustomer,
      Aufrufe.listPartnerCustomers,
      Aufrufe.getPartnerCustomer,
      Aufrufe.sendPartnerCustomerFonLink,
      Aufrufe.requestCustomerSignature,
      Aufrufe.getCustomerSignatureStatus,
      Aufrufe.createCustomerCashregister,
      Aufrufe.activateCashregister,
      Aufrufe.listCustomerCashregisters,
      Aufrufe.getCustomerCredentials,
      Aufrufe.reportCustomerVertrag,
      Aufrufe.createPartnerWebhook,
      Aufrufe.listPartnerWebhooks,
      Aufrufe.updatePartnerWebhook,
      Aufrufe.deletePartnerWebhook,
      Aufrufe.sendPartnerWebhookTest,
      Aufrufe.listPartnerWebhookDeliveries,
    ]) {
      expect(Aufrufe.alle, contains(name));
    }
  });
}
