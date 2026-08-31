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
    'companyName': 'Bäckerei Jobst e.U.',
    'legalForm': 'eu',
    'email': 'chef@jobst.at',
    'address': <String, dynamic>{'street': 'Hauptstrasse', 'number': '12a', 'zip': '5020', 'city': 'Salzburg'},
    'state': 'salzburg',
    'taxDetails': <String, dynamic>{'taxNumber': '12-345/6789', 'smallBusiness': false},
    'contacts': <dynamic>[
      <String, dynamic>{'name': 'Anna Jobst', 'email': 'anna@jobst.at'}
    ],
  };

  /// Ein Client, der die übergebenen Antworten der Reihe nach liefert.
  ({PartnerApi api, List<http.Request> log}) stelle(List<Map<String, dynamic>> antworten) {
    final log = <http.Request>[];
    var i = 0;
    final mock = MockClient((request) async {
      log.add(request);
      final a = antworten[i < antworten.length ? i : antworten.length - 1];
      i++;
      return http.Response(jsonEncode(a), 200, headers: <String, String>{'content-type': 'application/json'});
    });
    return (api: PartnerApi(partnerKey: partnerKey, httpClient: mock), log: log);
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
        'partner': <String, dynamic>{'id': 'ptn_1', 'name': 'Muster GmbH', 'status': 'active'},
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
        'status': 'created',
        'env': 'live',
        'companyName': 'Bäckerei Jobst e.U.',
        'appId': 'app_1',
        'access': <String, dynamic>{'invited': true, 'sentTo': 'c***@jobst.at'},
        'nextSteps': <dynamic>['FinanzOnline-Link senden'],
      })
    ]);
    final r = await f.api.createPartnerCustomer(
      appId: 'app_1',
      betrieb: betrieb,
      idempotencyKey: 'eigene-kundennummer-4711',
    );
    expect(params(f.log.single), <String, dynamic>{
      'appId': 'app_1',
      'business': betrieb,
      'idempotencyKey': 'eigene-kundennummer-4711',
    });
    expect(r.customerId, 'cust_1');
    expect(r.eingeladen, isTrue);
    expect(r.sentTo, 'c***@jobst.at');
    expect(r.wiederholt, isFalse);
  });

  test('eine wiederholte Anlage meldet sich als solche', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'cust_1', 'replayed': true, 'access': <String, dynamic>{}})
    ]);
    final r = await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb, idempotencyKey: 'x');
    expect(r.wiederholt, isTrue);
  });

  /// Rot-Probe: in `api.dart` die Zeile `'env': env == null ? null :
  /// envName(env)` streichen — dann steht `env` nicht mehr im gesendeten
  /// Rumpf und dieser Test fällt. Geprüft wird die NUTZLAST auf der Leitung,
  /// nicht das Argument: ein Test, der nur die Methode beobachtet, bliebe
  /// grün, während der Server nie ein `env` sähe.
  test('env geht mit auf die Leitung — ein Live-Schlüssel darf einen Testbetrieb anlegen', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'ptest_1', 'env': 'test', 'access': <String, dynamic>{}}),
      erfolg(<String, dynamic>{'customerId': 'cust_2', 'env': 'live', 'access': <String, dynamic>{}}),
    ]);
    final r = await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb, env: PartnerEnv.test);
    expect(params(f.log[0]),
        <String, dynamic>{'appId': 'app_1', 'business': betrieb, 'env': 'test'});
    expect(r.env, PartnerEnv.test);

    // Ohne Angabe entscheidet der Schlüssel — dann darf auch nichts gesendet
    // werden: ein erfundenes `env: "live"` nähme dem Schlüssel die
    // Entscheidung ab.
    await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb);
    expect(params(f.log[1]).containsKey('env'), isFalse);
  });

  test('die Umgebungen sind genau die beiden des Backends', () {
    expect(kPartnerEnvs, <String>['live', 'test']);
    expect(envName(PartnerEnv.live), 'live');
    expect(envName(PartnerEnv.test), 'test');
  });

  test('darfZugangEinrichten fehlt = NEIN, nicht „vielleicht"', () async {
    // Eine Berechtigung, die nicht ausdrücklich dasteht, hat man nicht. Ein
    // `true` aus Kulanz erzeugte einen Aufruf, der zugang_nicht_erlaubt
    // bekommt — und dabei entsteht NICHTS, auch kein Betrieb.
    final ohne = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'partner': <String, dynamic>{'id': 'p1', 'name': 'A', 'status': 'active'},
        'env': 'live',
      })
    ]);
    expect((await ohne.api.getPartnerInfo()).darfZugangEinrichten, isFalse);

    final mit = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'partner': <String, dynamic>{
          'id': 'p1',
          'name': 'A',
          'status': 'active',
          'canCreateAccess': true,
        },
        'env': 'live',
      })
    ]);
    expect((await mit.api.getPartnerInfo()).darfZugangEinrichten, isTrue);
  });

  test('einladen:false wird als zugang-Objekt gesendet, sonst gar nicht', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'customerId': 'cust_1'}),
      erfolg(<String, dynamic>{'customerId': 'cust_2'}),
    ]);
    await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb, einladen: false);
    expect(params(f.log[0])['access'], <String, dynamic>{'invite': false});
    await f.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb);
    // Nicht gesetzt heisst nicht gesendet — sonst hielte das Backend die
    // Vorgabe für eine ausdrückliche Angabe.
    expect(params(f.log[1]).containsKey('access'), isFalse);
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
        'customers': <dynamic>[
          <String, dynamic>{
            'customerId': 'cust_1',
            'companyName': 'A',
            'status': 'live',
            'appId': 'app_1',
            'env': 'live',
            'createdAt': 5,
          }
        ],
        'cursor': 'weiter',
        'total': 12,
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
        'customer': <String, dynamic>{
          'customerId': 'cust_1',
          'companyName': 'A',
          'status': 'signature_ready',
          'env': 'test',
          'liveEnabled': false,
          'appId': null,
          'createdVia': 'api',
          'business': <String, dynamic>{'companyName': 'A'},
          'fon': <String, dynamic>{'configured': true, 'verifiedAt': 99},
          'access': null,
        }
      })
    ]);
    final k = await f.api.getPartnerCustomer('cust_1');
    expect(k.status, 'signature_ready');
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

  test('checkPartnerCustomerEmail sagt nur ja oder nein', () async {
    // Der Sinn ist der Zeitpunkt: ohne diese Frage fällt email_taken erst nach
    // einem ganzen ausgefüllten Formular auf.
    final f = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{'available': true})]);
    expect(await f.api.checkPartnerCustomerEmail('  Neu@Jobst.at '), isTrue);
    expect(params(f.log.single), <String, dynamic>{'email': 'Neu@Jobst.at'});

    // Alles außer einem ausdrücklichen `true` heißt NICHT frei — im Zweifel
    // keine Zusage, sonst fährt der Aufrufer in ein email_taken.
    final g = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{})]);
    expect(await g.api.checkPartnerCustomerEmail('x@y.at'), isFalse);

    final h = stelle(<Map<String, dynamic>>[erfolg(<String, dynamic>{'available': true})]);
    expect(() => h.api.checkPartnerCustomerEmail('   '), throwsA(isA<KasseneckValidationError>()));
  });

  test('rotatePartnerWebhookSecret behält den Endpunkt und bringt ein neues Secret', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'webhook': <String, dynamic>{'webhookId': 'wh1', 'url': 'https://p.test/hook', 'events': <String>['webhook.test'], 'active': true},
        'secret': 'whsec_neu',
      })
    ]);
    final r = await f.api.rotatePartnerWebhookSecret('wh1');
    expect(r.secret, 'whsec_neu');
    expect(r.webhook.webhookId, 'wh1');
    expect(params(f.log.single), <String, dynamic>{'webhookId': 'wh1'});

    // Ohne Secret wäre der Wechsel nicht nachvollziehbar: dann lieber ein
    // Fehler als ein Aufrufer, der weiter mit dem alten signiert.
    final g = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{'webhook': <String, dynamic>{'webhookId': 'wh1'}})
    ]);
    expect(() => g.api.rotatePartnerWebhookSecret('wh1'), throwsA(isA<KasseneckValidationError>()));
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
        'request': <String, dynamic>{
          'requestId': 'req_1',
          'status': 'requested',
          'statusText': 'Beantragt',
          'art': 'signature_card',
          'history': <dynamic>[],
        },
        'replayed': true,
        'note': 'Es lief bereits ein Antrag.',
      })
    ]);
    final r = await f.api.requestCustomerSignature('cust_1');
    expect(params(f.log.single), <String, dynamic>{'customerId': 'cust_1'});
    expect(r.antrag.requestId, 'req_1');
    expect(r.wiederholt, isTrue);
    expect(r.hinweis, 'Es lief bereits ein Antrag.');

    // Eine WEITERE Signatur entsteht nur ausdrücklich — sonst bliebe der
    // Aufruf nicht folgenlos wiederholbar.
    final weiter = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'request': <String, dynamic>{'requestId': 'req_2', 'history': <dynamic>[]},
        'replayed': false,
      })
    ]);
    await weiter.api.requestCustomerSignature('cust_1', weitere: true);
    expect(params(weiter.log.single), <String, dynamic>{'customerId': 'cust_1', 'additional': true});
  });

  test('getCustomerSignatureStatus trennt "bereit" von "registriert"', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'signature': <String, dynamic>{'ready': false, 'signatureId': null, 'vdaId': null},
        'requests': <dynamic>[
          <String, dynamic>{'requestId': 'req_1', 'status': 'registered', 'statusText': 'Bei FinanzOnline registriert'}
        ],
        'fon': <String, dynamic>{'present': true, 'verifiedAt': 7},
      })
    ]);
    final s = await f.api.getCustomerSignatureStatus('cust_1');
    expect(s.bereit, isFalse);
    expect(s.antraege.single.status, 'registered');
    expect(s.fonVorhanden, isTrue);
  });

  test('createCustomerCashregister darf vor der Signatur laufen und sagt, warum nichts geschah', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'cashregister': <String, dynamic>{
          'cashregisterId': 'kasse_1',
          'name': 'Theke',
          'status': 'draft',
          'statusText': 'Entwurf',
          'automatic': true,
          'step': 'signature',
          'stepText': 'Signaturkarte zuweisen',
          'completedSteps': <dynamic>[],
          'steps': <dynamic>[
            <String, dynamic>{'key': 'signature', 'text': 'Signaturkarte zuweisen'}
          ],
          'attempts': 0,
        },
        'activation': <String, dynamic>{
          'started': false,
          'ok': null,
          'step': null,
          'reason': 'signature_not_ready',
        },
      })
    ]);
    final r = await f.api.createCustomerCashregister(customerId: 'cust_1', signaturId: 'sig_1');
    // KEIN `name`: Kassennamen vergibt Kasseneck, ein gesendetes name wäre ein
    // validation-Fehler.
    expect(params(f.log.single), <String, dynamic>{'customerId': 'cust_1', 'signatureRequestId': 'sig_1'});
    expect(r.kasse.status, 'draft');
    expect(r.kasse.istLive, isFalse);
    expect(r.kasse.automatisch, isTrue);
    expect(r.grund, 'signature_not_ready');
    expect(r.ok, isNull, reason: 'ok:null heisst „nicht gelaufen" und darf nicht zu false werden');
  });

  test('activateCashregister meldet eine bereits laufende Kasse als unverändert', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'cashregister': <String, dynamic>{
          'cashregisterId': 'kasse_1',
          'status': 'live',
          'statusText': 'In Betrieb',
          'step': null,
        },
        'unchanged': true,
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
        'cashregisters': <dynamic>[
          <String, dynamic>{'cashregisterId': 'kasse_1', 'status': 'live'}
        ],
        'signatureReady': true,
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
        'companyName': 'A',
        'env': 'live',
        'apiKey': 'kr_live_GEHEIM',
        'cashregisters': <dynamic>[
          <String, dynamic>{'cashregisterId': 'kasse_1', 'live': true, 'cashregisterToken': 'cb_live_GEHEIM'}
        ],
        'note': 'Nur verschlüsselt speichern.',
      })
    ]);
    final z = await f.api.getCustomerCredentials('cust_1');
    expect(z.apiKey.reveal(), 'kr_live_GEHEIM');
    expect(z.toString(), isNot(contains('kr_live_GEHEIM')));
    expect(z.kassen.single.cashregisterToken.reveal(), 'cb_live_GEHEIM');
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
          'active': true,
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
          <String, dynamic>{'webhookId': 'wh_1', 'active': false}
        ],
        'events': <dynamic>[
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
        'webhook': <String, dynamic>{'webhookId': 'wh_1', 'active': false}
      }),
      erfolg(<String, dynamic>{'webhookId': 'wh_1', 'geloescht': true}),
    ]);
    final w = await f.api.updatePartnerWebhook('wh_1', <String, dynamic>{'active': false});
    expect(params(f.log.first), <String, dynamic>{
      'webhookId': 'wh_1',
      'patch': <String, dynamic>{'active': false}
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
        'deliveries': <dynamic>[
          <String, dynamic>{'deliveryId': 'dlv_1'}
        ]
      }),
      erfolg(<String, dynamic>{
        'deliveries': <dynamic>[
          <String, dynamic>{
            'deliveryId': 'dlv_1',
            'webhookId': 'wh_1',
            'event': 'webhook.test',
            'eventId': 'evt_1',
            'status': 'failed',
            'attempts': 6,
            'statusCode': 500,
            'response': 'boom',
          }
        ]
      }),
    ]);
    final t = await f.api.sendPartnerWebhookTest('wh_1');
    expect(t.eventId, 'evt_1');
    expect(t.ereignis, 'webhook.test', reason: 'ohne Angabe ist die Probe die Leitungsprobe');
    final z = await f.api.listPartnerWebhookDeliveries(webhookId: 'wh_1', limit: 10);
    expect(params(f.log[1]), <String, dynamic>{'webhookId': 'wh_1', 'limit': 10});
    expect(z.single.status, 'failed');
    expect(z.single.statusCode, 500);
    await expectLater(
      f.api.listPartnerWebhookDeliveries(limit: 999),
      throwsA(isA<KasseneckValidationError>()),
    );
  });

  /// Rot-Probe: in `api.dart` den Schlüssel `'event'` aus dem Rumpf von
  /// `sendPartnerWebhookTest` streichen — dann fällt dieser Test. Er sieht die
  /// gesendete NUTZLAST an, nicht das Argument: nur so fällt auf, wenn der
  /// Client das Ereignis zwar entgegennimmt, aber nie weitergibt und der
  /// Partner statt seines Falls immer nur „webhook.test" bekommt.
  test('eine Probe kann jedes abonnierte Ereignis auslösen, nicht nur webhook.test', () async {
    final f = stelle(<Map<String, dynamic>>[
      erfolg(<String, dynamic>{
        'eventId': 'evt_2',
        'ereignis': 'signature.ready',
        'deliveries': <dynamic>[]
      }),
      erfolg(<String, dynamic>{'eventId': 'evt_3', 'deliveries': <dynamic>[]}),
    ]);
    final t = await f.api.sendPartnerWebhookTest('wh_1', event: 'signature.ready');
    expect(params(f.log[0]), <String, dynamic>{'webhookId': 'wh_1', 'event': 'signature.ready'});
    expect(t.ereignis, 'signature.ready');
    expect(t.eventId, 'evt_2');

    // Ohne Ereignis darf auch keines mitgehen: ein leeres `event` wäre für den
    // Server ein unbekanntes Ereignis (validation) statt der Leitungsprobe.
    await f.api.sendPartnerWebhookTest('wh_1', event: '   ');
    expect(params(f.log[1]), <String, dynamic>{'webhookId': 'wh_1'});
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
        final rat = partnerFehlerRat(code);
        expect(rat, isNotNull, reason: '$code: kein Handlungssatz');
        expect(rat!.length, greaterThan(20), reason: '$code: Handlungssatz zu dünn');
        expect(f.api.fehlerRat(code), rat);
      }
    }
  });

  /// Der Katalog, Code für Code, gegen `docs/api/fehlercodes.json` im Backend.
  ///
  /// Rot-Probe: einen Code aus [kPartnerFehlerCodes] streichen — dieser Test
  /// fällt sofort mit dem fehlenden Namen. Ein Code, den nur eine Seite kennt,
  /// ist für einen Aufrufer nicht von „gibt es nicht" zu unterscheiden.
  test('der Fehlerkatalog ist vollständig — 28 Codes der Schnittstelle, 12 des Portals', () {
    expect(kPartnerFehlerCodes, <String>[
      'validation',
      'rate_limited',
      'app_not_found',
      'app_not_accepted',
      'kein_partnerbetrieb',
      'live_not_allowed',
      'customer_exists',
      'customer_conflict',
      'customer_limit',
      'zugang_nicht_erlaubt',
      'email_taken',
      'no_email',
      'fon_missing',
      'signature_pending',
      'request_not_found',
      'signature_missing',
      'signature_unknown',
      'signature_ambiguous',
      'signature_not_ready',
      'signature_limit',
      'signature_failed',
      'module_inactive',
      'cashregister_limit',
      'cashregister_not_found',
      'activation_failed',
      'webhook_limit',
      'webhook_inactive',
      'event_not_subscribed',
    ]);
    expect(kPartnerFehlerCodes.length, 28);

    expect(kPartnerPortalFehlerCodes, <String>[
      'app_locked',
      'version_locked',
      'invalid_transition',
      'no_accepted_app',
      'consent',
      'key_limit',
      'last_owner',
      'auth_user_exists',
      'card_missing',
      'card_duplicate',
      'card_not_verified',
      'already_assigned',
    ]);
    expect(kPartnerPortalFehlerCodes.length, 12);

    // Auch die Portal-Codes tragen einen Satz: der Katalog ist eine Liste, und
    // eine halbe Liste ist schlimmer als keine.
    for (final code in kPartnerPortalFehlerCodes) {
      expect(partnerFehlerRat(code)?.length ?? 0, greaterThan(20), reason: '$code: kein Handlungssatz');
    }

    // Die beiden Flächen überschneiden sich nicht, und die Erkenner trennen
    // sie sauber.
    for (final code in kPartnerFehlerCodes) {
      expect(istPartnerFehlerCode(code), isTrue, reason: code);
      expect(istPartnerPortalFehlerCode(code), isFalse, reason: code);
    }
    for (final code in kPartnerPortalFehlerCodes) {
      expect(istPartnerPortalFehlerCode(code), isTrue, reason: code);
      expect(istPartnerFehlerCode(code), isFalse, reason: code);
    }

    // Ein abgeschaffter Code darf keinen Handlungssatz behalten — sonst rät
    // dieses Paket zu einem Weg, den es nicht mehr gibt.
    for (final weg in <String>[
      'vertrag_offen',
      'modus_not_allowed',
      'vollmacht_fehlt',
      'text_changed',
      'no_card_available',
    ]) {
      expect(partnerFehlerRat(weg), isNull, reason: '$weg steht nicht mehr im Katalog');
      expect(istPartnerFehlerCode(weg), isFalse, reason: weg);
    }
  });

  test('die Beilagen eines Fehlers kommen mit — schritt, rc, verschachteltes', () async {
    final f = stelle(<Map<String, dynamic>>[
      fehler('Die Inbetriebnahme ist hängen geblieben.', <String, dynamic>{
        'code': 'activation_failed',
        'step': 'transmit_start_receipt',
        'rc': 'B13',
        'cashregister': <String, dynamic>{'cashregisterId': 'kasse_1', 'status': 'failed'},
      })
    ]);
    try {
      await f.api.activateCashregister('cust_1', 'kasse_1');
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      expect(e.code, 'activation_failed');
      expect(e.details['step'], 'transmit_start_receipt');
      expect(e.details['rc'], 'B13');
      // Auch die verschachtelte Beilage überlebt das Sieb — sie sagt dem
      // Aufrufer, wo genau die Kette steht.
      expect((e.details['cashregister'] as Map)['status'], 'failed');
      expect(e.message, 'Die Inbetriebnahme ist hängen geblieben.');
    }
  });

  test('validation liefert Feld und Grund, rate_limited die Wartezeit', () async {
    final v = stelle(<Map<String, dynamic>>[
      fehler('Bitte Eingaben prüfen.', <String, dynamic>{
        'code': 'validation',
        'errors': <dynamic>[
          <String, dynamic>{'field': 'taxDetails.taxNumber', 'message': 'Prüfziffer stimmt nicht.'}
        ],
      })
    ]);
    try {
      await v.api.createPartnerCustomer(appId: 'app_1', betrieb: betrieb);
      fail('hätte werfen müssen');
    } on KasseneckApiError catch (e) {
      final felder = partnerFeldFehler(e);
      expect(felder.single.field, 'taxDetails.taxNumber');
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
  // Betriebsfelder und Ablauf
  // -------------------------------------------------------------------------

  /// Rot-Probe: in `betrieb.dart` im `_sammle` das `raus.add(voll)` durch
  /// `continue` ersetzen — dann findet die Funktion nichts mehr, und dieser
  /// Test fällt an jeder der vier Zeilen. Genau das war der Zustand VORHER:
  /// ein `iban` verschwand spurlos, und der Partner glaubte, er habe es
  /// geschickt.
  test('ein unbekanntes Betriebsfeld fällt hier auf, mit demselben Pfad wie beim Server', () {
    expect(unbekannteBetriebsfelder(betrieb), isEmpty, reason: 'ein gültiger Betrieb ist sauber');

    final schmutzig = <String, dynamic>{
      ...betrieb,
      'iban': 'AT61 1904 3002 3457 3201',
      'address': <String, dynamic>{...betrieb['address'] as Map<String, dynamic>, 'land': 'AT'},
      'taxDetails': <String, dynamic>{
        ...betrieb['taxDetails'] as Map<String, dynamic>,
        'ustid': 'ATU12345675',
      },
      'contacts': <dynamic>[
        <String, dynamic>{'name': 'Anna Jobst', 'email': 'anna@jobst.at', 'rolle': 'chef'},
        <String, dynamic>{'name': 'B', 'email': 'b@c.at'},
      ],
    };
    expect(
      unbekannteBetriebsfelder(schmutzig)..sort(),
      <String>['address.land', 'contacts.0.rolle', 'iban', 'taxDetails.ustid'],
    );

    // Der Pfad trägt den INDEX des Kontakts, nicht nur „contacts" — sonst
    // suchte jemand in zehn Kontakten nach dem einen falschen Feld.
    expect(
      unbekannteBetriebsfelder(<String, dynamic>{
        'contacts': <dynamic>[
          <String, dynamic>{'name': 'A'},
          <String, dynamic>{'name': 'B'},
          <String, dynamic>{'name': 'C', 'abteilung': 'Kasse'},
        ]
      }),
      <String>['contacts.2.abteilung'],
    );

    // Ein falscher Typ ist KEIN unbekanntes Feld — den meldet der Server als
    // eigenen Formfehler auf demselben Pfad. Hier darf er nicht als
    // „unbekannt" durchgehen und schon gar nicht werfen.
    expect(unbekannteBetriebsfelder(<String, dynamic>{'contacts': 'Anna', 'address': null}), isEmpty);
    expect(unbekannteBetriebsfelder(null), isEmpty);
    expect(unbekannteBetriebsfelder('kein Betrieb'), isEmpty);
  });

  test('die Feldliste deckt sich mit BETRIEB_FELDER des Backends', () {
    // partner-core.BETRIEB_FELDER, flach ausgeschrieben. Ein Feld, das hier
    // fehlt, meldet die Vorschau als unbekannt, obwohl der Server es nimmt;
    // eines zu viel gaukelt ein Feld vor, das der Server abweist.
    expect(kBetriebFelder, <String>[
      'companyName',
      'legalForm',
      'state',
      'industry',
      'companyRegister',
      'court',
      'web',
      'phone',
      'email',
      'billingEmail',
      'address.street',
      'address.number',
      'address.zip',
      'address.city',
      'taxDetails.taxNumber',
      'taxDetails.vatId',
      'taxDetails.gln',
      'taxDetails.smallBusiness',
      'contacts[].name',
      'contacts[].email',
      'contacts[].phone',
      'contacts[].roles',
      'taxAdvisor.name',
      'taxAdvisor.email',
      'taxAdvisor.phone',
      'taxAdvisor.mayContact',
    ]);
  });

  test('der Ablauf steht als Daten da und ist in sich schlüssig', () {
    // OHNE Vertragsschritt: Verträge wirken im Partner-Weg nicht mehr.
    expect(kPartnerAblauf.map((s) => s.key).toList(),
        <String>['business', 'fon', 'signature', 'cashregister', 'zugangsdaten', 'belege']);
    // Jeder Aufruf der Kette ist einer, den dieses Paket wirklich kennt — ein
    // Schritt, der auf einen erfundenen Endpunkt zeigt, wäre schlimmer als
    // keiner.
    for (final schritt in kPartnerAblauf) {
      if (schritt.aufruf == null) continue;
      expect(Aufrufe.alle, contains(schritt.aufruf), reason: 'unbekannter Aufruf: ${schritt.aufruf}');
    }
    expect(naechsterSchritt('created')?.key, 'fon');
    expect(naechsterSchritt('signature_ready')?.key, 'cashregister');
    expect(naechsterSchritt('live')?.key, 'zugangsdaten');
    expect(naechsterSchritt('blocked'), isNull);
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
      Aufrufe.createPartnerWebhook,
      Aufrufe.listPartnerWebhooks,
      Aufrufe.updatePartnerWebhook,
      Aufrufe.deletePartnerWebhook,
      Aufrufe.sendPartnerWebhookTest,
      Aufrufe.listPartnerWebhookDeliveries,
      Aufrufe.checkPartnerCustomerEmail,
      Aufrufe.rotatePartnerWebhookSecret,
    ]) {
      expect(Aufrufe.alle, contains(name));
    }
    // Und umgekehrt: ein Aufruf, den es nicht mehr gibt, darf keine Adresse
    // behalten — sonst zeigt die Doku auf einen Endpunkt, der nichts tut.
    expect(Aufrufe.alle, isNot(contains('reportCustomerVertrag')),
        reason: 'Verträge wirken im Partner-Weg nicht mehr');
  });
}
