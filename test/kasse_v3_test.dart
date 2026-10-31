import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/register.dart';
import 'package:kreiseck_validator/kreiseck_validator.dart' show VoucherCode;

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
  'listMyStockLocations', 'listMyStock', 'setMyCashregisterStockLocation',
];
const _weitere = ['listMyCashregisters', 'generateFullReceiptId', 'createReceipt', 'cancelReceipt'];

/// Inventur zaehlen (seit 10.7). Die Modelle sind die der Lager-API; ihre
/// Feldmengen prueft `kasse_inventur_test.dart` (verlustfrei ueber `toJson`)
/// statt F8 hier.
const _inventur = [
  'listMyStocktakes', 'listMyStocktakeItems', 'listMyStocktakeCounts', 'recordMyStocktakeCount', 'voidMyStocktakeCount',
];

/// Schicht, Kassenstand und Lade-Protokoll (seit 11.1). Die Modelle prueft
/// `kasse_schicht_test.dart` verlustfrei ueber `toJson`.
const _schicht = [
  'getMyDrawerState', 'openMyShift', 'recordMyCashMovement', 'logMyDrawerOpenings', 'getMyShiftReport', 'closeMyShift',
];

/// Gutscheine der neuen Form (seit 11.3): pruefen und Etikett nachdrucken.
/// Ihre fachlichen Codes (`voucher_*`) stehen nicht in `posErrorCodes`; die
/// Saetze dazu fuehrt der Textkatalog (`voucher_error.*`).
const _gutschein = ['checkVoucher', 'reprintVoucherLabel'];

/// Ausgaben eines Belegs melden (seit 11.5). Modelle, Vorab-Pruefung und die
/// Faelle Feld fuer Feld prueft `beleg_ausgaben_test.dart`.
const _ausgaben = ['logReceiptOutputs'];

/// Pruefung (DEP) an der Kasse (seit 11.13, npm 1.21.0): nur der Chef
/// exportiert (`manager_only`). Die Faelle des Geraets mit api_key
/// (`*_device`) laufen hier mit, wie `checkVoucher/success_device`: die
/// Nutzlast ist dieselbe, nur die Anmeldung eine andere. Eine Datei als
/// Antwort fuehrt der Export nicht (nur JSON); den Dateiweg prueft
/// `kasse_dep_test.dart`.
const _dep = ['createDepExport', 'getDepExport', 'getDepExportFile', 'createDepHandoverLink', 'revokeDepHandoverLink'];

/// Fälle, die dieser Weg bewusst nicht senden kann, mit Grund.
const _nichtDieserWeg = {
  'openMyShift/key_conflict':
      'denominations: null am Draht; ein Dart-Parameter ohne Wert geht nie als null hinaus (der Code kommt in kasse_schicht_test.dart an)',
  'closeMyShift/payouts_invalid': 'Auszahlung ohne registerUserId; TipPayout verlangt die Kennung schon im Typ',
  'createReceipt/start_receipt': 'Startbeleg: Panel bzw. API-Schlüssel, nicht der Verkauf der Kasse',
  'createReceipt/receipt_type_unknown': 'receiptType ist hier fest standard',
  'createReceipt/tip_on_start': 'Startbeleg mit Trinkgeld: Weg des API-Schlüssels',
  'createReceipt/cashregister_missing':
      'ohne cashregisterId: der Sitzungs-Transport legt die Kasse jeder Nutzlast bei, so geht dieser Weg nie hinaus',
  'createReceipt/payments_conflict': 'paymentMethod neben payments, sendet dieser Weg nie',
  'cancelReceipt/payments_conflict': 'paymentMethod am Storno, sendet dieser Weg nie',
  'cancelReceipt/card_data_without_card': 'cardPaymentId am Storno, sendet dieser Weg nie',
  'cancelReceipt/items_no_array': 'items ist hier immer eine Liste (Stornoposition)',
  'cancelReceipt/tip_source_invalid': 'eine Quelle ausserhalb von tipRefundSources wirft vor dem Senden (storno_trinkgeld_test.dart)',
  'setMyCashregisterStockLocation/data_missing':
      'ohne stockLocationId: null geht als leerer Text hinaus (Zuruecksetzen), weglassen kann dieser Weg nicht',
};

/// Erfolgsfälle, die das Paket bewusst schon vor dem Senden abweist: genau
/// die, die die gemeinsame Vertragsdatei `receipt-outputs-cases.json` als
/// `contract_<fall>` mit Abweisung führt (Schlüssel außerhalb der Regel des
/// Servers). Ohne den beanstandeten Eintrag laufen sie in
/// `beleg_ausgaben_test.dart` Feld für Feld.
final Set<String> _vorabStattErfolg = {
  for (final a in ((jsonDecode(File('test/fixtures/vertrag/receipt-outputs-cases.json').readAsStringSync()) as Map)['requests']
          as List)
      .cast<Map<String, dynamic>>())
    if ((a['name'] as String).startsWith('contract_') && (a['expected'] as Map).containsKey('error'))
      'logReceiptOutputs/${(a['name'] as String).substring('contract_'.length)}',
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

/// Tasten-Aktionen, die der Server nicht in seiner Vorgabekarte fuehrt: fehlen
/// sie in einer Antwort, liest das Paket sie als leere Liste (keine Taste).
const _tastenOhneServervorgabe = ['shiftStatus', 'openDrawer', 'voucherPayout'];

/// Das Geraet, so wie das Paket die Serverantwort liest.
Object? _geraetGelesen(Object? device) {
  if (device is! Map) return device;
  final tasten = (device['shortcuts'] as Map?) ?? const {};
  return {
    ...device,
    'shortcuts': {for (final a in _tastenOhneServervorgabe) a: <String>[], ...tasten},
  };
}

/// Der Gutschein-Block, so wie das Paket ihn liest: ohne das alte Feld `label`
/// (Kassen vor 11.8, Ruling R3), sonst unveraendert.
Object? _gutscheinGelesen(Object? vouchers) {
  if (vouchers is! Map) return vouchers;
  return {...vouchers}..remove('label');
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
PrintLogo _logoAus(Map<dynamic, dynamic> l) {
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
  return PrintLogo(
    size: SheetLogoSize.values.firstWhere((s) => s.code == l['scale']),
    pixelWidth: l['pxWidth'] as int,
    pixelHeight: l['pxHeight'] as int,
    raster: LogoRaster(width: breite, height: hoehe, dots: punkte),
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
  final drucker = PosPrinterClient(transport);
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
        return RegisterSessionClient.fromTransport(transport).renewRegisterSession();
      case 'endRegisterSession':
        await RegisterSessionClient.fromTransport(transport).endRegisterSession();
        return true;
      case 'listMyCashregisters':
        return belege.cashregisters();
      case 'generateFullReceiptId':
        return belege.fullReceiptId(_s(p['receiptId']));
      case 'listMyArticleGroups':
        return belege.articleGroups();
      case 'listMyArticles':
        return belege.articles();
      case 'listMyTipRecipients':
        return belege.tipRecipients();
      case 'listMyStockLocations':
        return belege.stockLocations();
      case 'listMyStock':
        return belege.stock(
          locationId: p['locationId'] as String?,
          articleId: p['articleId'] as String?,
          belowMinimum: p['belowMinimum'] as bool?,
        );
      case 'setMyCashregisterStockLocation':
        final ziel = p['stockLocationId'] as String;
        return belege.setStockLocation(
          stockLocationId: ziel.isEmpty ? null : ziel,
          cashregisterId: p['cashregisterId'] as String?,
        );
      case 'listMyStocktakes':
        return belege.listMyStocktakes(locationId: p['locationId'] as String?, status: p['status'] as String?);
      case 'listMyStocktakeItems':
        return belege.listMyStocktakeItems(
          stocktakeId: _s(p['stocktakeId']),
          openOnly: p['openOnly'] as bool?,
          limit: p['limit'] as int?,
          cursor: p['cursor'] as String?,
        );
      case 'listMyStocktakeCounts':
        return belege.listMyStocktakeCounts(
          stocktakeId: _s(p['stocktakeId']),
          articleId: p['articleId'] as String?,
          ownOnly: p['ownOnly'] as bool?,
          limit: p['limit'] as int?,
          cursor: p['cursor'] as String?,
        );
      case 'recordMyStocktakeCount':
        return belege.recordMyStocktakeCount(
          idempotencyKey: _s(p['idempotencyKey']),
          stocktakeId: _s(p['stocktakeId']),
          articleId: _s(p['articleId']),
          quantity: p['quantity'] as int,
          condition: p['condition'] as String?,
          serialNumbers: (p['serialNumbers'] as List?)?.cast<String>(),
          note: p['note'] as String?,
          cashregisterId: p['cashregisterId'] as String?,
        );
      case 'voidMyStocktakeCount':
        return belege.voidMyStocktakeCount(
          idempotencyKey: _s(p['idempotencyKey']),
          stocktakeId: _s(p['stocktakeId']),
          countId: _s(p['countId']),
          reason: _s(p['reason']),
        );
      case 'getMyDrawerState':
        return belege.getMyDrawerState(
            drawerId: p['drawerId'] as String?, cashregisterId: p['cashregisterId'] as String?);
      case 'openMyShift':
        return belege.openMyShift(
          idempotencyKey: _s(p['idempotencyKey']),
          drawerId: _s(p['drawerId']),
          openingFloatCents: p['openingFloatCents'] as int?,
          denominations: (p['denominations'] as Map?)?.cast<String, int>(),
          takeOver: p['takeOver'] as bool?,
        );
      case 'recordMyCashMovement':
        return belege.recordMyCashMovement(
          idempotencyKey: _s(p['idempotencyKey']),
          drawerId: _s(p['drawerId']),
          type: _s(p['type']),
          amountCents: p['amountCents'] as int,
          location: p['location'] as String?,
          note: p['note'] as String?,
          recipientId: p['recipientId'] as String?,
          targetDrawerId: p['targetDrawerId'] as String?,
        );
      case 'logMyDrawerOpenings':
        return belege.logMyDrawerOpenings(
          drawerId: _s(p['drawerId']),
          entries: [
            for (final e in (p['entries'] as List? ?? const []).cast<Map<String, dynamic>>())
              DrawerOpeningEntry(
                idempotencyKey: _s(e['idempotencyKey']),
                reason: _s(e['reason']),
                ok: e['ok'] == true,
                deviceTime: e['deviceTime'] as Object,
                note: e['note'] as String?,
                receiptId: e['receiptId'] as String?,
                error: e['error'] as String?,
                drawerId: e['drawerId'] as String?,
                operator: e['operator'] == null
                    ? null
                    : DrawerOpeningOperator(
                        registerUserId: _s((e['operator'] as Map)['registerUserId']),
                        name: (e['operator'] as Map)['name'] as String?,
                      ),
              ),
          ],
        );
      case 'getMyShiftReport':
        return belege.getMyShiftReport(shiftId: _s(p['shiftId']));
      case 'closeMyShift':
        return belege.closeMyShift(
          idempotencyKey: _s(p['idempotencyKey']),
          shiftId: _s(p['shiftId']),
          countedCents: p['countedCents'] as int,
          denominations: (p['denominations'] as Map?)?.cast<String, int>(),
          attempt: p['attempt'] as int?,
          comment: p['comment'] as String?,
          tipPayouts: (p['tipPayouts'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map((a) => TipPayout(registerUserId: _s(a['registerUserId']), cents: a['cents'] as int))
              .toList(),
          afterCount: p['afterCount'] == null
              ? null
              : AfterCount(type: _s((p['afterCount'] as Map)['type']), amountCents: (p['afterCount'] as Map)['amountCents'] as int),
          checkOnly: p['checkOnly'] as bool? ?? false,
        );
      case 'checkVoucher':
        return belege.checkVoucher(_s(p['code']));
      case 'reprintVoucherLabel':
        return belege.reprintVoucherLabel(_s(p['id']));
      case 'createDepExport':
        return belege.createDepExport(
            from: p['from'] as String?, to: p['to'] as String?, requestId: p['requestId'] as String?);
      case 'getDepExport':
        return belege.getDepExport(_s(p['exportId']));
      case 'getDepExportFile':
        return belege.getDepExportFile(_s(p['exportId']), _s(p['file']));
      case 'createDepHandoverLink':
        return belege.createDepHandoverLink(_s(p['exportId']));
      case 'revokeDepHandoverLink':
        return belege.revokeDepHandoverLink(_s(p['linkId']));
      case 'logReceiptOutputs':
        return belege.logReceiptOutputs(entries: [
          for (final e in (p['entries'] as List? ?? const [])) ReceiptOutputEntry.fromJson((e as Map).cast()),
        ]);
      case 'getKasseSettings':
        if (p['deviceId'] != null && p['deviceId'] is! String) throw const _NichtDarstellbar();
        return PosSettingsClient(transport, deviceId: _s(p['deviceId'])).load();
      case 'setMyKasseSettings':
        if (p['business'] is! Map) throw const _NichtDarstellbar();
        return PosSettingsClient(transport, deviceId: '')
            .saveBusiness((p['business'] as Map).cast<String, dynamic>());
      case 'setMyRegisterDeviceSettings':
        if (p['device'] is! Map) throw const _NichtDarstellbar();
        return PosSettingsClient(transport, deviceId: _s(p['deviceId']))
            .saveDevice((p['device'] as Map).cast<String, dynamic>());
      case 'setMyKasseLogo':
        final c = PosSettingsClient(transport, deviceId: '');
        if (p['remove'] == true) return c.removeLogo();
        if (p['image'] != null && p['image'] is! String) throw const _NichtDarstellbar();
        return c.setLogo(_s(p['image']));
      case 'listMyPrinters':
        return drucker.printers();
      case 'createPrintJob':
        final layout = ReceiptLayout.fromJson(p['layout']);
        if (layout == null || (p['title'] != null && p['title'] is! String)) throw const _NichtDarstellbar();
        final logoRoh = p['logo'];
        // Ein Logo ohne Raster (scale: 'riesig') baut DruckLogo nicht.
        if (logoRoh is Map && logoRoh['rows'] is! String) throw const _NichtDarstellbar();
        return drucker.createPrintJob(
          printerId: _s(p['printerId']),
          layout: layout,
          receiptId: p['receiptId'] as String?,
          title: p['title'] as String?,
          source: p['source'] as String?,
          logo: p['logo'] is Map ? _logoAus(p['logo'] as Map) : null,
          brandMark: p['brand'] == true,
        );
      case 'getPrintJob':
        return drucker.getPrintJob(printerId: _s(p['printerId']), jobId: _s(p['jobId']));
      case 'createReceipt':
        return belege.sell(
          items: [for (final i in (p['items'] as List? ?? const [])) KasseneckItem.fromJson((i as Map).cast())],
          payments: [for (final z in (p['payments'] as List? ?? const [])) _zahlung(z as Map)],
          tipCents: p['tip'] is Map ? (p['tip'] as Map)['cents'] as int : p['tip'] as int?,
          tipKeptByEmployee: p['tip'] is Map && (p['tip'] as Map)['keptByEmployee'] == true,
        );
      case 'cancelReceipt':
        return belege.cancelReceipt(
          originalReceiptId: _s(p['originalReceiptId']),
          reason: _s(p['reason']),
          note: p['note'] as String?,
          items: p['items'] == null
              ? null
              : [for (final i in p['items'] as List) (index: (i as Map)['index'] as int, quantity: i['quantity'] as int)],
          payments: p['payments'] == null ? null : [for (final z in p['payments'] as List) _zahlung(z as Map)],
          refundTip: p['refundTip'] as bool?,
          tipRefundSource: p['tipRefundSource'] as String?,
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
  // Der Gutscheincode geht in Normalform hinaus (der Server nimmt beide
  // Schreibweisen; aufgezeichnet ist die getippte).
  if (endpunkt == 'checkVoucher' && p['code'] is String) {
    p['code'] = VoucherCode.normalize(p['code'] as String);
  }
  // Das Zeilenmodell geht in der Form von BelegLayout.toJson hinaus: ruleset
  // immer gesetzt, Standardwerte der Zeilen ausgeschrieben. Für ein Layout des
  // Servers (success_logo_qr) ist das dieselbe Form, siehe eigener Test.
  if (endpunkt == 'createPrintJob' && ReceiptLayout.fromJson(p['layout']) != null) {
    p['layout'] = ReceiptLayout.fromJson(p['layout'])!.toJson();
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
    if (_vorabStattErfolg.contains(name)) return;
    expect(antwort['status'], 'error', reason: '$name: der Client weist ab, was der Server annimmt');
    return;
  }
  expect(_vorabStattErfolg.contains(name), isFalse, reason: '$name: steht in _vorabStattErfolg, ging aber hinaus');
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
  if (_kassenAufrufe.contains(endpunkt) || _inventur.contains(endpunkt) || _schicht.contains(endpunkt)) {
    expect(isPosError(lauf.fehler, code as String), isTrue, reason: '$name: $code in posErrorCodes');
  }
  if (_ausgaben.contains(endpunkt)) {
    expect(isReceiptOutputError(lauf.fehler, code as String), isTrue, reason: '$name: $code in receiptOutputErrorCodes');
  }
  if (_dep.contains(endpunkt)) {
    expect(depExportErrorCodes.contains(code) || isPosError(lauf.fehler, code as String), isTrue,
        reason: '$name: $code in depExportErrorCodes oder posErrorCodes');
  }
}

void main() {
  group('jeder Fall des Kassenwegs', () {
    for (final endpunkt in [..._anmeldung, ..._kassenAufrufe, ..._weitere, ..._inventur, ..._schicht, ..._gutschein, ..._ausgaben, ..._dep]) {
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

    test('alle 47 Endpunkte des Vertrags sind abgedeckt (Belegwelt in receipt_v3_test)', () {
      final hier = {..._anmeldung, ..._kassenAufrufe, ..._weitere, ..._inventur, ..._schicht, ..._gutschein, ..._ausgaben, ..._dep};
      expect((_vertrag['calls']['pos'] as List), hasLength(47));
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
      expect(stockLocationTypes, _vertrag['pos']['stockLocationTypes']);
      expect(StockLocationType.values.map((t) => t.name), stockLocationTypes);
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
      expect(u.settings.business.theme, PosTheme.night);
      expect(u.settings.business.color, '#222222');
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
      expect((geraet!.ergebnis as PosSettings).toJson()['device'], _geraetGelesen(soll['device']));
    });

    test('Benutzerliste: Einstellungen ohne erfundenen vouchers-Block (der Server fuehrt ihn dort nicht)', () async {
      // Der Block `vouchers` kommt allein aus getKasseSettings. Hier bleibt er der
      // Standard (Verkaufen aus) und geht nie in die Drahtform: kein Block, der
      // wie eine Serverantwort aussaehe.
      for (final f in _faelle('listRegisterUsersForDevice').where((f) => f['response']['status'] == 'success')) {
        final lauf = await _rufe('listRegisterUsersForDevice', f);
        final stand = (lauf!.ergebnis as RegisterDeviceUsers).settings;
        final gesendet = (f['response']['data']['settings'] as Map?)?.keys.toSet() ?? <String>{};
        expect(stand.vouchers, PosVoucherSettings.off, reason: '${f['case']}');
        expect(stand.toJson().containsKey('vouchers'), isFalse, reason: '${f['case']}');
        expect(gesendet.contains('vouchers'), isFalse, reason: '${f['case']}');
      }
    });

    test('Anmeldung: Gutschein-Rechte des Vertrags = Schluessel von voucherPermsOf, kein Antwortschluessel geht verloren', () async {
      final voucherSchluessel = <String>{};
      for (final ep in ['registerUserLogin', 'registerPinLogin']) {
        for (final f in _faelle(ep).where((f) => f['response']['status'] == 'success')) {
          final d = f['response']['data'] as Map<String, dynamic>;
          final lauf = await _rufe(ep, f);
          expect(lauf!.ergebnis, isA<RegisterUserSession>(), reason: '$ep/${f['case']}');
          expect(d.keys.toSet(), RegisterUserSession.fields, reason: '$ep/${f['case']}');
          expect((d['user'] as Map).keys.toSet(), RegisterUser.fields, reason: '$ep/${f['case']} user');
          final perms = (d['user'] as Map)['perms'] as Map<String, dynamic>;
          voucherSchluessel.addAll(perms.keys.where((k) => k.startsWith('voucher')));
          // Jeder Schluessel des Vertrags kommt in den gelesenen Rechten an (nicht im Auffangbecken).
          final gelesen = RegisterUserPerms.fromJson(perms);
          for (final k in perms.keys) {
            expect(gelesen.other.containsKey(k), isFalse, reason: '$ep/${f['case']} perms.$k');
          }
        }
      }
      // voucherPermsOf loest genau diese Rechte auf: kippt eines, faellt es hier auf.
      expect(voucherSchluessel, {'voucherSell', 'voucherRedeem', 'voucherManage'});
      final alle = RegisterUserPerms.fromJson({for (final k in voucherSchluessel) k: false});
      expect(voucherPermsOf(alle), const VoucherPerms(voucherSell: false, voucherRedeem: false, voucherManage: false));
      final rein = RegisterUserPerms.fromJson({for (final k in voucherSchluessel) k: true});
      expect(voucherPermsOf(rein), const VoucherPerms(voucherSell: true, voucherRedeem: true, voucherManage: true));
    });

    test('Sitzungen: own, deviceLabel', () async {
      final lauf = await _rufe('listRegisterSessionsForDevice', _fall('listRegisterSessionsForDevice', 'success_select'));
      final s = lauf!.ergebnis as RegisterSessionOverview;
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
      final a = PosArticle.fromJson({
        'id': 'a1', 'name': 'Wurst', 'unitPriceCents': 1290, 'vatRate': 10, 'unit': 'kg', 'groupId': 'g1',
        'kasse': {'sichtbar': false, 'sort': 3}, 'active': true,
        'mengenregel': 'dezimal', 'mengeFragen': true, 'maxMenge': 2.5,
      });
      expect([a.visible, a.sort, a.quantityRule, a.askQuantity, a.maxQuantity], [false, 3, QuantityRule.decimal, true, 2.5]);
      // Neu geschrieben wird die Drahtform.
      final neu = a.toJson();
      expect(neu['tile'], {'visible': false, 'sort': 3});
      expect(neu['quantityRule'], 'decimal');
      expect(PosArticle.fromJson(neu).toJson(), neu);
    });
  });

  group('Lager: gelesene Modelle (Vertragsfälle)', () {
    test('Standorte: Hauptstandort virtuell, Fahrzeug ohne Adresse, aufgelöster Standort mit Adresse', () async {
      for (final name in ['success_cashier', 'success_owner']) {
        final lauf = await _rufe('listMyStockLocations', _fall('listMyStockLocations', name));
        final orte = lauf!.ergebnis as List<StockLocation>;
        expect(orte.map((o) => o.id), ['haupt', 'auto1', 'alt'], reason: name);
        final [haupt, auto, alt] = orte;
        expect([haupt.type, haupt.virtual, haupt.active, haupt.address], [StockLocationType.store, true, true, null]);
        expect([auto.type, auto.licensePlate, auto.address, auto.virtual], [StockLocationType.vehicle, 'W-12345', null, false]);
        expect([alt.type, alt.active, alt.licensePlate], [StockLocationType.warehouse, false, null]);
        expect([alt.address?.street, alt.address?.zip, alt.address?.city, alt.address?.country],
            ['Hauptplatz 1', '1010', 'Wien', 'AT']);
      }
    });

    test('Bestand: Tausendstel unverändert, Werte nur mit Recht (sonst null, nie leer)', () async {
      final kassier = (await _rufe('listMyStock', _fall('listMyStock', 'success_cashier')))!.ergebnis as StockList;
      expect(kassier.values, isNull);
      expect([for (final b in kassier.stock) [b.articleId, b.locationId, b.sellable, b.defective, b.reserved, b.available]], [
        ['art_kaffee', 'haupt', 12000, 0, 2000, 10000],
        ['art_kaffee', 'auto1', 3000, 1000, 0, 3000],
      ]);
      final inhaber = (await _rufe('listMyStock', _fall('listMyStock', 'success_owner')))!.ergebnis as StockList;
      expect([for (final w in inhaber.values!) [w.articleId, w.stockValueCents, w.averageCostMicros]], [
        ['art_kaffee', 4800, 3000000],
      ]);
      final ort = await _rufe('listMyStock', _fall('listMyStock', 'success_location'));
      expect(ort!.params['locationId'], 'auto1');
      expect((ort.ergebnis as StockList).stock.single.locationId, 'auto1');
    });

    test('Standort der Kasse: gesetzt und zurückgesetzt (null geht als leerer Text hinaus)', () async {
      final gesetzt = await _rufe('setMyCashregisterStockLocation', _fall('setMyCashregisterStockLocation', 'success_manager'));
      final g = gesetzt!.ergebnis as CashregisterStockLocation;
      expect([g.cashregisterId, g.stockLocationId], ['KASSE1', 'auto1']);
      final zurueck = await _rufe('setMyCashregisterStockLocation', _fall('setMyCashregisterStockLocation', 'success_reset'));
      expect(zurueck!.params['stockLocationId'], '');
      final z = zurueck.ergebnis as CashregisterStockLocation;
      expect([z.cashregisterId, z.stockLocationId], ['KASSE1', null]);
    });
  });

  group('Pruefung (DEP) am Kassenweg (Vertragsfaelle)', () {
    test('ein Kassierer ohne Chef-Recht bekommt bei jedem der fuenf Aufrufe manager_only und den Satz der Kasse', () async {
      for (final ep in _dep) {
        final lauf = (await _rufe(ep, _fall(ep, 'cashier_no_manager')))!;
        expect(lauf.log, hasLength(1), reason: ep);
        expect(lauf.log.single.headers['Authorization'], 'Bearer id-token', reason: ep);
        expect(lauf.log.single.headers['register-session'], 'sess-1', reason: ep);
        expect(lauf.params['cashregisterId'], 'KASSE1', reason: ep);
        final fehler = lauf.fehler;
        expect(fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', 'manager_only'), reason: ep);
        expect(isOutcomeUnknown(fehler), isFalse, reason: '$ep: abgewiesen, nichts entstanden');
        final regel = findErrorRule(ErrorKind.api,
            code: (fehler as KasseneckApiError).code, outcome: messageOutcome(fehler));
        expect(regel.key, 'dep.manager_only', reason: ep);
      }
    });

    test('getDepExport liest den Export samt Befund und Pruefer-Links', () async {
      final roh = _fall('getDepExport', 'success_manager')['response']['data'] as Map<String, dynamic>;
      final e = (await _rufe('getDepExport', _fall('getDepExport', 'success_manager')))!.ergebnis as DepExport;
      expect(e.exportId, roh['exportId']);
      expect(e.isDone, isTrue);
      expect((e.from, e.to), (roh['from'], roh['to']));
      expect((e.receiptCount, e.counterFrom, e.counterTo), (3, 1, 3));
      expect(e.sha256, roh['sha256']);
      expect(e.findings!.isClean, isTrue);
      expect(e.items!.rowCount, 4);
      expect(e.handoverLinks.single.linkId, 'kwLink0000000000000A');
      expect(e.handoverLinks.single.expiresAt, '2026-10-10T08:00:00.000Z');

      final laeuft = (await _rufe('getDepExport', _fall('getDepExport', 'success_running')))!.ergebnis as DepExport;
      expect(laeuft.status, depExportRunning);
      expect(laeuft.sha256, isNull);
      expect(laeuft.handoverLinks, isEmpty);
    });

    test('export_running nennt den laufenden Export, invalid_period vor dem Senden oder vom Server', () async {
      final lauf = (await _rufe('createDepExport', _fall('createDepExport', 'running_already')))!;
      expect((lauf.fehler as KasseneckApiError).details['exportId'], 'DEP-2026-09-26-0002');
      expect(findErrorRule(ErrorKind.api, code: 'export_running').key, 'dep.running');

      // bis vor von: das Paket weist ab, bevor etwas hinausgeht.
      final vorab = (await _rufe('createDepExport', _fall('createDepExport', 'period_wrong')))!;
      expect(vorab.vorab, isTrue);
      expect(vorab.log, isEmpty);
      // von in der Zukunft kennt nur der Server.
      final zukunft = (await _rufe('createDepExport', _fall('createDepExport', 'period_future')))!;
      expect(zukunft.fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_period'));
    });

    test('revokeDepHandoverLink liest den Widerruf', () async {
      final r = (await _rufe('revokeDepHandoverLink', _fall('revokeDepHandoverLink', 'success_manager')))!.ergebnis
          as DepHandoverRevocation;
      expect(r.linkId, 'kwLink0000000000000A');
      expect(r.revokedAt, '2026-09-26T08:00:00.000Z');
    });
  });

  group('Kassen-Aufrufe: gelesene Modelle', () {
    test('Artikel: tile, quantityRule, revenueGroupId', () async {
      for (final name in ['success_cashregister', 'success_owner', 'module_inventory']) {
        final fall = _fall('listMyArticles', name);
        final lauf = await _rufe('listMyArticles', fall);
        final artikel = lauf!.ergebnis as List<PosArticle>;
        final roh = (fall['response']['data']['articles'] as List).cast<Map<String, dynamic>>();
        expect(artikel.length, roh.length);
        for (final (i, a) in artikel.indexed) {
          final r = roh[i];
          expect(a.id, r['id']);
          expect(a.visible, (r['tile'] as Map?)?['visible'] != false, reason: a.id);
          expect(a.sort, (r['tile'] as Map?)?['sort'] ?? 0);
          expect(a.quantityRule?.name, r['quantityRule']);
          expect(a.askQuantity, r['askQuantity']);
          expect(a.revenueGroupId, r['revenueGroupId']);
        }
      }
    });

    test('Einstellungen des Kontos: nacht wird night, Gerät mit eigenen Tasten', () async {
      final lauf = await _rufe('getKasseSettings', _fall('getKasseSettings', 'manager_with_device'));
      final e = lauf!.ergebnis as PosSettings;
      final roh = _fall('getKasseSettings', 'manager_with_device')['response']['data'];
      expect(e.toJson(), {'business': roh['business'], 'device': _geraetGelesen(roh['device']), 'vouchers': _gutscheinGelesen(roh['vouchers'])},
          reason: 'die Antwort ist schon gemischt; gelesen und zurückgeschrieben ergibt sie sich selbst');
    });

    test('jede Einstellungs-Antwort liest sich verlustfrei', () async {
      for (final ep in ['getKasseSettings', 'setMyKasseSettings', 'setMyRegisterDeviceSettings']) {
        for (final fall in _faelle(ep).where((f) => f['response']['status'] == 'success')) {
          final lauf = await _rufe(ep, fall);
          final daten = fall['response']['data'] as Map<String, dynamic>;
          final json = switch (lauf!.ergebnis) {
            final PosSettings s => s.toJson(),
            final PosBusinessSettings b => {'business': b.toJson()},
            final PosDeviceSettings g => {'device': g.toJson()},
            _ => throw StateError('${fall['case']}'),
          };
          for (final teil in json.keys) {
            final soll = switch (teil) {
              'device' => _geraetGelesen(daten[teil]),
              'vouchers' => _gutscheinGelesen(daten[teil]),
              _ => daten[teil],
            };
            expect(json[teil], soll, reason: '$ep/${fall['case']} $teil');
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
      final fremd = await PosPrinterClient(_transport(
              _mock({
                'headers': {'Kasseneck-Api-Version': 'v3'},
                'httpStatus': 200,
                'response': {'status': 'success', 'data': {'jobId': 'j', 'status': 'cancelled'}},
              }, lauf),
              'KASSE1'))
          .getPrintJob(printerId: 'dr_theke', jobId: 'j');
      expect(fremd.status, printJobStatusUnknown);
      expect(isPrintJobFinished(fremd.status), isTrue, reason: 'nie bis zum Zeitlimit abfragen');
    });

    test('Kasse: autoLogout wird gelesen, fehlt es, ist es null', () {
      final mit = CashregisterEntry.fromJson({
        'id': 'THEKE-1',
        'label': 'THEKE-1',
        'autoLogout': {'autoLogoutMinutes': 5, 'logoutAfterSale': true},
      });
      expect(mit.autoLogout, isNotNull);
      expect(mit.autoLogout!.autoLogoutMinutes, 5);
      expect(mit.autoLogout!.logoutAfterSale, isTrue);
      final teil = CashregisterEntry.fromJson({'id': 'THEKE-1', 'autoLogout': {'autoLogoutMinutes': 0}});
      expect(teil.autoLogout!.autoLogoutMinutes, 0);
      expect(teil.autoLogout!.logoutAfterSale, isNull);
      expect(CashregisterEntry.fromJson({'id': 'THEKE-1'}).autoLogout, isNull);
      expect(CashregisterEntry.fromJson({'id': 'THEKE-1', 'autoLogout': null}).autoLogout, isNull);
    });

    test('Kassenliste und Volltext-Belegnummer', () async {
      final kassen = (await _rufe('listMyCashregisters', _fall('listMyCashregisters', 'manager')))!.ergebnis
          as List<CashregisterEntry>;
      expect(kassen.first.id, 'KASSE1');
      expect(kassen.first.onboarding.startReceiptCreated, isTrue);
      expect(kassen.first.token, isNull, reason: 'Kassen-Benutzer bekommen keinen Kassen-Token');
      final owner = (await _rufe('listMyCashregisters', _fall('listMyCashregisters', 'owner')))!.ergebnis
          as List<CashregisterEntry>;
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
      final ergebnis = await client.cancelReceipt(originalReceiptId: original, reason: 'input_error');
      expect(ergebnis.receipt.testCashregister, isTrue);

      // Ohne Test-Umgebung gelten die Kennzeichen des Originals.
      final ohne = RegisterReceiptClient(_transport(_mock(fall, _Lauf()), 'KASSE1'));
      final normal = await ohne.cancelReceipt(originalReceiptId: original, reason: 'input_error');
      expect(normal.receipt.testCashregister, isFalse);
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
      final c = PosSettingsClient(
          _transport(_mock(_fallErfolg(teil == 'business' ? 'setMyKasseSettings' : 'setMyRegisterDeviceSettings'), lauf), 'KASSE1'),
          deviceId: 'dev_pin');
      try {
        await (teil == 'business' ? c.saveBusiness(block) : c.saveDevice(block));
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
      final karte = {...posShortcutDefaults, 'card': ['Mod+B']};
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
        final e = await client.cancelReceipt(originalReceiptId: original.receiptId, reason: 'input_error', original: original);
        return e.receipt;
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
      final c = PosSettingsClient(_transport(_mock(_fallErfolg('setMyRegisterDeviceSettings'), lauf), 'KASSE1'),
          deviceId: 'dev_pin');
      await expectLater(
          c.saveDevice({'shortcuts': {'cash': ['Mod+K']}}),
          throwsA(isA<KasseneckValidationError>()
              .having((e) => e.kind, 'kind', 'request')
              .having((e) => e.reason, 'reason', contains('ganze Karte'))));
      expect(lauf.log, isEmpty);
      // Über posSettingsChanges geht bei einer Tastenänderung die ganze Karte,
      // und eine Doppelbelegung mit einer gespeicherten Taste fällt auf.
      const vorher = PosDeviceSettings();
      final doppelt = posSettingsChanges(vorher.toJson(), vorher.merge({'shortcuts': {'cash': ['Mod+K']}}).toJson());
      await expectLater(c.saveDevice(doppelt),
          throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('Mod+K schon belegt'))));
      expect(lauf.log, isEmpty);
    });

    test('F7: fehlende Druckerliste oder fehlende Job-Kennung ist ein Antwortfehler', () async {
      Future<Object?> mit(String ep, Map<String, dynamic> daten, Future<Object?> Function(PosPrinterClient) rufen) async {
        final c = PosPrinterClient(_transport(
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

      final layout = ReceiptLayout.fromJson(_fall('createPrintJob', 'success_cashregister')['params']['layout'])!;
      final antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
      expect(await mit('listMyPrinters', {}, (c) => c.printers()), antwortfehler);
      expect(await mit('listMyPrinters', {'printers': []}, (c) => c.printers()), isEmpty);
      expect(await mit('createPrintJob', {'status': 'pending'}, (c) => c.createPrintJob(printerId: 'dr', layout: layout)),
          antwortfehler);
      expect(await mit('createPrintJob', {'jobId': '', 'status': 'pending'},
          (c) => c.createPrintJob(printerId: 'dr', layout: layout)), antwortfehler);
      expect(await mit('getPrintJob', {'status': 'printed'}, (c) => c.getPrintJob(printerId: 'dr', jobId: 'j')),
          antwortfehler);
    });

    group('F8: Feldmengen der Erfolgsantworten', () {
      // Pfad in der Antwort -> Felder, die das Modell liest, und Felder, die
      // der Vertrag heute nicht in jedem Fall zeigt (optional).
      final modelle = <String, (Set<String>, Set<String>)>{
        'pairRegisterDevice': (PairedRegisterDevice.fields, const {}),
        'listRegisterUsersForDevice': (RegisterDeviceUsers.fields, const {}),
        'listRegisterUsersForDevice.users[]': (RegisterUserSummary.fields, const {}),
        'listRegisterUsersForDevice.policy': (RegisterPinPolicy.fields, const {}),
        'listRegisterUsersForDevice.cashregister': (RegisterCashregisterState.fields, const {'stockLocationId'}),
        'listRegisterSessionsForDevice': (RegisterSessionOverview.fields, const {}),
        'listRegisterSessionsForDevice.sessions[]': (RegisterSession.fields, const {}),
        'registerUserLogin': (RegisterUserSession.fields, const {}),
        'registerUserLogin.user': (RegisterUser.fields, const {}),
        'registerPinLogin': (RegisterUserSession.fields, const {}),
        'registerPinLogin.user': (RegisterUser.fields, const {}),
        'renewRegisterSession': (const {'expiresAt'}, const {}),
        'listMyCashregisters': (const {'cashregisters'}, const {}),
        'listMyCashregisters.cashregisters[]': (CashregisterEntry.fields, const {'stockLocationId', 'autoLogout'}),
        'listMyCashregisters.cashregisters[].onboarding': (CashregisterOnboarding.fields, const {}),
        'generateFullReceiptId': (const {'fullReceiptId'}, const {}),
        'listMyArticleGroups': (const {'groups'}, const {}),
        'listMyArticleGroups.groups[]': (ArticleGroup.fields, const {'symbol', 'vatRate'}),
        'listMyArticles': (const {'articles'}, const {}),
        'listMyArticles.articles[]':
            (PosArticle.fields, const {
              'unitPriceCents', 'quantityRule', 'askQuantity', 'maxQuantity', 'stockLocationIds',
              'number', 'ean', 'internalCode', 'stockTracked',
              // Leistungsgutschein-Freigabe (11.8.0): der Vertrag zeigt sie in keinem Artikelfall.
              'serviceVoucher',
            }),
        'listMyArticles.articles[].tile': (PosArticle.tileFields, const {}),
        'setMyKasseLogo': (const {'logoImage'}, const {}),
        'listMyPrinters': (const {'printers'}, const {}),
        'listMyPrinters.printers[]': (NetworkPrinter.fields, const {}),
        'listMyPrinters.printers[].lastResult': (PrintResult.fields, const {'status'}),
        'createPrintJob': (PrintJob.fields, const {'createdAt', 'sentAt', 'result'}),
        'getPrintJob': (PrintJob.fields, const {}),
        'getPrintJob.result': (PrintResult.fields, const {}),
        'listMyTipRecipients': (const {'recipients'}, const {}),
        'listMyTipRecipients.recipients[]': (KeckTipPerson.fields, const {}),
        'listMyStockLocations': (const {'locations'}, const {}),
        'listMyStockLocations.locations[]': (StockLocation.fields, const {}),
        'listMyStockLocations.locations[].address': (StockLocationAddress.fields, const {}),
        'listMyStock': (StockList.fields, const {}),
        'listMyStock.stock[]': (StockLevel.fields, const {}),
        'listMyStock.values[]': (StockValue.fields, const {}),
        'setMyCashregisterStockLocation': (CashregisterStockLocation.fields, const {}),
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
            {...PosArticle.fields, for (final k in PosArticle.tileFields) 'tile.$k'},
            {for (final f in PosArticle.fields) f: null, 'tile': {'visible': true, 'sort': 1}},
            PosArticle.fromJson,
          ),
          (ArticleGroup.fields, {for (final f in ArticleGroup.fields) f: null}, ArticleGroup.fromJson),
          (
            {...NetworkPrinter.fields, for (final k in PrintResult.fields) 'lastResult.$k'},
            {for (final f in NetworkPrinter.fields) f: null, 'lastResult': {for (final k in PrintResult.fields) k: null}},
            NetworkPrinter.fromJson,
          ),
          (
            {...CashregisterEntry.fields, for (final k in CashregisterOnboarding.fields) 'onboarding.$k'},
            {for (final f in CashregisterEntry.fields) f: null, 'onboarding': {for (final k in CashregisterOnboarding.fields) k: null}},
            CashregisterEntry.fromJson,
          ),
          (KeckTipPerson.fields, {for (final f in KeckTipPerson.fields) f: null}, KeckTipPerson.fromJson),
        ];
        for (final (soll, roh, lesen) in beispiele) {
          expect(gelesen(roh, lesen), soll);
        }
      });
    });

    group('F1: mit() weist unbekannte und deutsche Schlüssel laut ab', () {
      test('das Beispiel des Reviews: qrModus statt qrMode', () {
        const g = PosDeviceSettings();
        expect(() => g.merge({'qrModus': 'raster'}),
            throwsA(isA<ArgumentError>().having((e) => e.message, 'message', allOf(contains('device.qrModus'), contains('qrMode')))));
        expect(g.merge({'qrMode': 'raster'}).qrMode, PosQrMode.raster);
      });

      test('unbekannter Schlüssel, deutscher Wert, deutsche Tasten-Aktion', () {
        const b = PosBusinessSettings();
        expect(() => b.merge({'stil': 'night'}), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('business.stil'))));
        expect(() => b.merge({'gibtsnicht': 1}), throwsA(isA<ArgumentError>()));
        expect(() => b.merge({'theme': 'nacht'}), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('night'))));
        expect(() => const PosDeviceSettings().merge({'shortcuts': {'bar': ['F2']}}),
            throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('cash'))));
      });

      test('ein unbekannter englischer Wert bleibt erlaubt (künftiger Wert des Servers)', () {
        expect(const PosBusinessSettings().merge({'theme': 'sepia'}).unknownValues, {'theme': 'sepia'});
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
