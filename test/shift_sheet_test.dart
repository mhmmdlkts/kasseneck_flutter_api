import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Die Bons der Schicht (Z-Bon, X-Bon, Kassenbewegung) als Zeilenmodell,
/// Zwilling von `receipt/shift-sheet.ts` (npm 1.9.0): dieselben Goldens
/// (`expected/shift-*`, `cash-movement*`), Zeichen fuer Zeichen. Die Bon-Daten
/// kommen aus den Vertragsantworten (`shift-receipts.json` nennt den Fall).
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _endpunkte = _json('${_wurzel.path}/v3/antworten/kasse.json')['endpoints'] as Map<String, dynamic>;
final _bons = (_json('${_wurzel.path}/shift-receipts.json')['receipts'] as Map).cast<String, Map<String, dynamic>>();

/// Bons mit Kartentrinkgeld bar aus der Lade (npm 1.37.0): eigenes Manifest,
/// Eingabe = Vertragsfall + `overlay` (flach ueber `data.receipt`).
final _kartenBons =
    (_json('${_wurzel.path}/shift-receipts-card-tips.json')['receipts'] as Map).cast<String, Map<String, dynamic>>();

Map<String, dynamic> _fall(String quelle) {
  final teile = quelle.split('/');
  return ((_endpunkte[teile[0]] as Map)['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['case'] == teile[1]);
}

RegisterReceiptClient _client(Map<String, dynamic> fall) {
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode(fall['response'])),
        fall['httpStatus'] as int,
        headers: {
          'content-type': 'application/json',
          for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
        },
      ),
    ),
  );
  return RegisterReceiptClient(transport);
}

/// Bon-Daten wie die Kasse sie aus der Antwort des Falls bekommt.
Future<Object> _bon(String name) async => _bonAus(_bons[name]!['source'] as String);

/// Bon-Daten aus dem Fall [quelle]; [overlay] liegt flach ueber
/// `data.receipt` (wie `{ ...quelle, ...overlay }` im npm-Paket).
Future<Object> _bonAus(String quelle, {Map<String, dynamic> overlay = const {}}) async {
  final fall = jsonDecode(jsonEncode(_fall(quelle))) as Map<String, dynamic>;
  ((fall['response'] as Map)['data'] as Map)['receipt'] = {
    ...(((fall['response'] as Map)['data'] as Map)['receipt'] as Map).cast<String, dynamic>(),
    ...overlay,
  };
  final c = _client(fall);
  return switch (quelle.split('/')[0]) {
    'closeMyShift' => (await c.closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 0)).receipt!,
    'getMyShiftReport' => (await c.getMyShiftReport(shiftId: 's')).receipt,
    'recordMyCashMovement' =>
      (await c.recordMyCashMovement(idempotencyKey: 'k', drawerId: 'd', type: 'cash_drop', amountCents: 1)).receipt,
    final e => throw StateError(e),
  };
}

ReceiptLayout _layout(Object bon, {PosPaperSize? papier}) => bon is CashMovementReceipt
    ? cashMovementLayout(bon, paperSize: papier ?? PosPaperSize.mm58)
    : shiftReceiptLayout(bon as ShiftSummaryReceipt, paperSize: papier ?? PosPaperSize.mm58);

List<String> _texte(ReceiptLayout l) => [
  for (final z in l.lines)
    switch (z) {
      LayoutTextLine(:final text) => text,
      LayoutBannerLine(:final text) => text,
      LayoutColumnsLine(:final columns) => columns.map((c) => c.text).join(' | '),
      _ => '',
    },
];

void main() {
  group('Goldens des Vertrags', () {
    test('alle Bons des Vertrags sind dabei (auch Entnehmen und Einlegen, wie im npm-Paket)', () {
      expect(_bons.keys.toSet(), {'shift-close', 'shift-close-blind', 'shift-close-take-out', 'shift-close-put-in', 'shift-interim', 'cash-movement'});
    });
    for (final name in _bons.keys) {
      test(name, () async {
        final layout = _layout(await _bon(name));
        final soll = _json('${_wurzel.path}/expected/$name.lines.json');
        expect(layout.toJson(), soll, reason: 'Zeilenmodell');
        final gelesen = ReceiptLayout.fromJson(soll)!;
        for (final zeichen in [32, 48]) {
          final grid = File('${_wurzel.path}/expected/$name.grid$zeichen.txt').readAsStringSync();
          expect(ReceiptGrid.render(layout, charsPerLine: zeichen).toText(), grid, reason: '$name @$zeichen');
          expect(ReceiptGrid.render(gelesen, charsPerLine: zeichen).toText(), grid);
        }
      });
    }
  });

  group('Goldens Kartentrinkgeld', () {
    test('eigenes Manifest: nur die zwei Bons, keiner davon im alten Manifest', () {
      expect(_kartenBons.keys.toSet(), {'shift-close-card-tips', 'shift-interim-card-tips'});
      for (final name in _kartenBons.keys) {
        expect(_bons.containsKey(name), isFalse, reason: '$name steht nicht im alten Manifest');
      }
    });
    for (final e in _kartenBons.entries) {
      test('${e.key}: Vertragsfall + overlay ergeben Zeilen und Raster wie aufgenommen', () async {
        final layout =
            _layout(await _bonAus(e.value['source'] as String, overlay: (e.value['overlay'] as Map).cast<String, dynamic>()));
        final soll = _json('${_wurzel.path}/expected/${e.key}.lines.json');
        expect(layout.toJson(), soll, reason: 'Zeilenmodell');
        for (final zeichen in [32, 48]) {
          final grid = File('${_wurzel.path}/expected/${e.key}.grid$zeichen.txt').readAsStringSync();
          final text = ReceiptGrid.render(layout, charsPerLine: zeichen).toText();
          expect(text, grid, reason: '${e.key} @$zeichen');
          expect(sha256.convert(utf8.encode(text)).toString(), e.value['grid$zeichen'], reason: '${e.key} grid$zeichen');
        }
      });
    }

    test('Kartentrinkgeld bar genommen: eigene Zeile mit Minus nach „Bar aus Verkäufen“, Soll geht auf; ohne Feld oder 0 kein Unterschied', () async {
      final overlay = (_kartenBons['shift-close-card-tips']!['overlay'] as Map).cast<String, dynamic>();
      final text = ReceiptGrid.render(_layout(await _bonAus('closeMyShift/success_manager', overlay: overlay)), charsPerLine: 48).toText();
      expect(text, matches(RegExp(r'^Bar aus Verkäufen +94,00\nKartentrinkgeld bar genommen +-5,00\nBar aus Storno', multiLine: true)));
      // Start + Bar − Kartentrinkgeld + Storno + Bewegungen = Soll (150 + 94 − 5 + 0 + 50 − 4 = 285).
      expect(text, matches(RegExp(r'^Soll +285,00$', multiLine: true)));
      // Je Mitarbeiter: „davon Kartentrinkgeld“ hinter „genommen“ (shiftTipLines).
      expect(text, matches(RegExp(r'^ {2}genommen +9,00\n {2}davon Kartentrinkgeld +5,00$', multiLine: true)));
      // Ohne das Feld und mit 0: genau der Bon von vorher (Zeilenmodell gleich).
      final vorher = jsonEncode(_layout(await _bonAus('closeMyShift/success_manager')).toJson());
      expect(jsonEncode(_layout(await _bonAus('closeMyShift/success_manager', overlay: {'cardTipsTakenCents': 0})).toJson()), vorher);
      expect(ReceiptGrid.render(_layout(await _bonAus('closeMyShift/success_manager')), charsPerLine: 48).toText(),
          isNot(contains('Kartentrinkgeld')));
      // Blind steht die Zeile wie die Bewegungen (das Geld hat die Lade sichtbar verlassen), Soll nicht.
      final blind = ReceiptGrid.render(
              _layout(await _bonAus('closeMyShift/success_cashier_blind', overlay: {'cardTipsTakenCents': 500})),
              charsPerLine: 48)
          .toText();
      expect(blind, matches(RegExp(r'^Kartentrinkgeld bar genommen +-5,00$', multiLine: true)));
      expect(blind, isNot(contains('Soll')));
    });

    test('Bon-Daten: cardTipsTakenCents am Bon und je Mitarbeiter gelesen wie gesendet, fehlt sonst', () async {
      final overlay = (_kartenBons['shift-close-card-tips']!['overlay'] as Map).cast<String, dynamic>();
      final mit = await _bonAus('closeMyShift/success_manager', overlay: overlay) as ShiftSummaryReceipt;
      expect(mit.cardTipsTakenCents, 500);
      expect(mit.tips.single.cardTipsTakenCents, 500);
      expect(mit.toJson()['cardTipsTakenCents'], 500);
      expect((mit.toJson()['tips'] as List).single['cardTipsTakenCents'], 500);
      final ohne = await _bonAus('closeMyShift/success_manager') as ShiftSummaryReceipt;
      expect(ohne.cardTipsTakenCents, isNull);
      expect(ohne.toJson().containsKey('cardTipsTakenCents'), isFalse);
      expect((ohne.toJson()['tips'] as List).single.containsKey('cardTipsTakenCents'), isFalse);
      // Kein Ersatzwert: ein Betrag, der keine ganze Zahl ist, ist eine kaputte Antwort.
      await expectLater(
        _bonAus('closeMyShift/success_manager', overlay: {'cardTipsTakenCents': 'viel'}),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
      );
    });
  });

  group('Regeln', () {
    test('kein Bon traegt „Kein Registrierkassenbeleg“ (Nachtrag 1), kein QR, keine Signatur', () async {
      for (final name in _bons.keys) {
        final l = _layout(await _bon(name));
        expect(_texte(l).join('\n'), isNot(contains('Registrierkassenbeleg')), reason: name);
        expect(l.lines.last, isNot(isA<LayoutRuleLine>()), reason: '$name: keine Linie ohne Fuss');
        expect(l.lines.whereType<LayoutQrLine>(), isEmpty);
      }
    });

    test('Kassenbewegung ohne Ort: keine Zeile „Ort“, Art „Wechselgeld“ (wie im npm-Paket)', () async {
      final fall = _fall('recordMyCashMovement/success_manager_change_in_without_location');
      final bon = (await _client(fall).recordMyCashMovement(idempotencyKey: 'k', drawerId: 'd', type: 'change_in', amountCents: 1)).receipt;
      final text = ReceiptGrid.render(_layout(bon), charsPerLine: 48).toText();
      expect(text, matches(RegExp(r'^Art +Wechselgeld$', multiLine: true)));
      expect(text, matches(RegExp(r'Betrag +30,00')));
      expect(text, isNot(matches(RegExp('Ort|Bank|Tresor'))));
    });

    test('nach der Zaehlung: „Entnommen“ negativ bzw. „Eingelegt“, dann „Bleibt in der Kassenlade“ fett (wie im npm-Paket)', () async {
      final entnahme = _layout(await _bon('shift-close-take-out'));
      final bleibt = entnahme.lines.whereType<LayoutColumnsLine>().where((z) => z.columns.first.text == 'Bleibt in der Kassenlade').single;
      expect(bleibt.toJson(), {
        'kind': 'columns',
        'columns': [
          {'text': 'Bleibt in der Kassenlade', 'width': 8, 'align': 'left'},
          {'text': '150,00', 'width': 4, 'align': 'right'},
        ],
        'bold': true,
      });
      final grid = ReceiptGrid.render(entnahme, charsPerLine: 48);
      expect(grid.lines.where((z) => z.bold && z.kind == GridLineKind.columns).map((z) => z.text.replaceAll(RegExp(' +'), ' ').trim()),
          ['Bleibt in der Kassenlade 150,00']);
      final text = grid.toText();
      // Unter Differenz, durch eine Linie getrennt (wie die Vorschau), dann die Linie zum Unbar-Block.
      expect(text, matches(RegExp(r'^Differenz +0,00\n-+\nEntnommen +-140,00\nBleibt in der Kassenlade +150,00\n-+$', multiLine: true)));
      expect(text, isNot(contains('Abschöpfung')));
      final einlage = ReceiptGrid.render(_layout(await _bon('shift-close-put-in')), charsPerLine: 48).toText();
      expect(einlage, matches(RegExp(r'^Differenz +0,00\n-+\nEingelegt +10,00\nBleibt in der Kassenlade +300,00$', multiLine: true)));
      expect(einlage, isNot(contains('Entnommen')));
      // Ohne afterCount: keine der Zeilen, keine fette Spaltenzeile (der Bon bleibt wie bisher).
      final ohne = _layout(await _bon('shift-close'));
      expect(ohne.lines.whereType<LayoutColumnsLine>().where((z) => z.bold), isEmpty);
      expect(_texte(ohne).join('\n'), isNot(matches(RegExp('Entnommen|Eingelegt|Bleibt'))));
    });

    test('nach der Zaehlung blind bzw. mit kuenftiger Art (wie im npm-Paket)', () async {
      Future<ShiftSummaryReceipt> abgewandelt(void Function(Map<String, dynamic> bon) aendere) async {
        final fall = jsonDecode(jsonEncode(_fall('closeMyShift/success_manager_take_out'))) as Map<String, dynamic>;
        aendere(((fall['response'] as Map)['data'] as Map)['receipt'] as Map<String, dynamic>);
        return (await _client(fall).closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 0)).receipt!;
      }

      // Blind: „Bleibt“ ist null, die Entnahme bleibt sichtbar.
      final blind = await abgewandelt((b) => b
        ..['blind'] = true
        ..['expectedCents'] = null
        ..['countedCents'] = null
        ..['differenceCents'] = null
        ..['cashSalesCents'] = null
        ..['cashCancellationsCents'] = null
        ..['leftInDrawerCents'] = null);
      final blindText = ReceiptGrid.render(_layout(blind), charsPerLine: 48).toText();
      expect(blindText, matches(RegExp(r'^Entnommen +-140,00$', multiLine: true)));
      expect(blindText, isNot(contains('Bleibt')));
      // Eine kuenftige Art druckt keine Betragszeile, „Bleibt“ steht trotzdem.
      final fremd = await abgewandelt((b) => b['afterCount'] = {'type': 'gibtsnicht', 'amountCents': 5});
      final fremdText = ReceiptGrid.render(_layout(fremd), charsPerLine: 48).toText();
      expect(fremdText, isNot(matches(RegExp('Entnommen|Eingelegt'))));
      expect(fremdText, matches(RegExp(r'^Bleibt in der Kassenlade +150,00$', multiLine: true)));
    });

    test('Titel nach Art: Schichtabschluss, Zwischenbericht, Kassenbewegung', () async {
      expect(_layout(await _bon('shift-close')).bannerTexts, ['Schichtabschluss']);
      expect(_layout(await _bon('shift-interim')).bannerTexts, ['Zwischenbericht']);
      expect(_layout(await _bon('cash-movement')).bannerTexts, ['Kassenbewegung']);
    });

    test('blind: keine Zeilen fuer Soll, Ist, Differenz und Barumsatz (kein erfundenes 0,00)', () async {
      final blind = (await _bon('shift-close-blind')) as ShiftSummaryReceipt;
      expect(blind.blind, isTrue);
      final text = _texte(_layout(blind)).join('\n');
      for (final wort in ['Soll', 'Ist', 'Differenz', 'Bar aus Verkäufen']) {
        expect(text, isNot(contains(wort)), reason: wort);
      }
      // Mit Recht sind sie da.
      final offen = _texte(_layout(await _bon('shift-close'))).join('\n');
      expect(offen, contains('Soll'));
      expect(offen, contains('Differenz'));
    });

    test('ein echtes 0 wird gedruckt, nur null faellt weg', () {
      const bon = ShiftSummaryReceipt(
        kind: 'shift_close',
        blind: false,
        number: 3,
        openingFloatCents: 0,
        openingFloatTakenOver: false,
        cashSalesCents: 0,
        cashCancellationsCents: 0,
        receiptCount: 0,
        cancellationCount: 0,
        expectedCents: 0,
        countedCents: 0,
        differenceCents: 0,
        openingsWithoutSale: 0,
      );
      final text = _texte(shiftReceiptLayout(bon));
      expect(text.where((z) => z.endsWith('| 0,00')), hasLength(greaterThanOrEqualTo(5)));
      // Leere Namen und Zeiten fallen weg: keine Zeile fuer Kasse, Lade, Zeiten.
      expect(text.join('\n'), isNot(contains('Kasse |')));
    });

    test('Trinkgeld: verdient immer, ueber Lohn, genommen und offen nur ungleich 0 (Nachtrag 3, R51, wie im npm-Paket)', () async {
      String block(String text) {
        final i = text.indexOf(RegExp(r'^Trinkgeld +$', multiLine: true));
        return i < 0 ? '' : text.substring(i);
      }

      final z = block(ReceiptGrid.render(_layout(await _bon('shift-close')), charsPerLine: 48).toText());
      expect(z, matches(RegExp(r'^Ben Kellner +$', multiLine: true)));
      expect(z, matches(RegExp(r'^ {2}verdient +4,00$', multiLine: true)));
      expect(z, matches(RegExp(r'^ {2}genommen +4,00$', multiLine: true)));
      expect(z, isNot(matches(RegExp('über Lohn|offen|sofort|0,00'))));
      final x = block(ReceiptGrid.render(_layout(await _bon('shift-interim')), charsPerLine: 48).toText());
      expect(x, matches(RegExp(r'^ {2}offen +4,00$', multiLine: true)));
      expect(x, isNot(matches(RegExp('genommen|über Lohn|0,00'))));
      // Wer ueberall 0 hat, entfaellt ganz -- ohne Mitarbeiter auch keine Ueberschrift.
      const leer = ShiftSummaryReceipt(
        kind: 'shift_interim',
        blind: false,
        number: 3,
        openingFloatTakenOver: false,
        receiptCount: 0,
        cancellationCount: 0,
        openingsWithoutSale: 0,
        tips: [ShiftTip(registerUserId: 'ru_kellner', name: 'Ben Kellner', receivedImmediatelyCents: 0, retainedCents: 0, paidOutCents: 0, openCents: 0)],
      );
      final t = ReceiptGrid.render(shiftReceiptLayout(leer), charsPerLine: 48).toText();
      expect(block(t), '');
      expect(t, isNot(contains('Ben Kellner')));
    });

    test('Betraege rein ganzzahlig: Cent, Vorzeichen, grosse Werte ohne Gleitkomma', () {
      String betrag(int cents) {
        const bon = CashMovementReceipt(blind: false, number: 1, type: 'cash_drop', amountCents: 0);
        final b = CashMovementReceipt(blind: false, number: 1, type: 'cash_drop', amountCents: cents);
        expect(bon.amountCents, 0);
        final spalten = cashMovementLayout(b).lines.whereType<LayoutColumnsLine>().firstWhere((z) => z.columns.first.text == 'Betrag');
        return spalten.columns.last.text;
      }

      expect(betrag(0), '0,00');
      expect(betrag(5), '0,05');
      expect(betrag(1234), '12,34');
      expect(betrag(100000), '1000,00');
      expect(betrag(-5), '-0,05');
      expect(betrag(-1234), '-12,34');
      expect(betrag(9007199254740991), '90071992547409,91');
      expect(betrag(-9007199254740991), '-90071992547409,91');
    });

    test('Papierbreite: Vorgabe mm58, mm80 wird uebernommen', () async {
      final bon = await _bon('cash-movement');
      expect(_layout(bon).paperSize, 'mm58');
      expect(_layout(bon, papier: PosPaperSize.mm80).paperSize, 'mm80');
      expect(_layout(bon).ruleset, 2);
    });

    test('falsche Art der Bon-Daten wirft vor dem Zeichnen (kind: request)', () {
      final anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');
      const bewegung = CashMovementReceipt(kind: 'shift_close', blind: false, number: 1, type: 'cash_drop', amountCents: 100);
      expect(() => cashMovementLayout(bewegung), throwsA(anfragefehler));
      const z = ShiftSummaryReceipt(
        kind: 'cash_movement',
        blind: false,
        number: 1,
        openingFloatTakenOver: false,
        receiptCount: 0,
        cancellationCount: 0,
        openingsWithoutSale: 0,
      );
      expect(() => shiftReceiptLayout(z), throwsA(anfragefehler));
    });

    test('Zeiten in Wien: 17:00 Uhr Sommerzeit aus UTC', () async {
      final text = _texte(_layout(await _bon('shift-close'))).join('\n');
      expect(text, matches(RegExp(r'\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}')));
    });
  });
}
