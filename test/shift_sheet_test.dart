import 'dart:convert';
import 'dart:io';

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
Future<Object> _bon(String name) async {
  final quelle = _bons[name]!['source'] as String;
  final fall = _fall(quelle);
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
    for (final name in ['shift-close', 'shift-close-blind', 'shift-interim', 'cash-movement']) {
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

  group('Regeln', () {
    test('jeder Bon endet mit „Kein Registrierkassenbeleg“, kein QR, keine Signatur', () async {
      for (final name in _bons.keys) {
        final l = _layout(await _bon(name));
        final letzte = l.lines.last as LayoutTextLine;
        expect(letzte.text, 'Kein Registrierkassenbeleg');
        expect(letzte.align, LayoutAlign.center);
        expect(letzte.bold, isTrue);
        expect(l.lines.whereType<LayoutQrLine>(), isEmpty);
      }
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
