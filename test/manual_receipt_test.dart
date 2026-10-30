import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/manual_receipt.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/src/receipt/aufdruck.dart';

/// Nacherfassung eines Handbelegs (`manualReceipt`), Zwilling von
/// `models/manual-receipt.ts` und `nacherfassungBlock` im npm-Paket.
Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;
final _vokabular = _json('test/fixtures/vertrag/v3/v3-vokabular.json');

const _einzel = {'number': 'H-17', 'date': '2026-12-31', 'time': '14:30', 'reason': 'network_outage'};
const _sammel = {'number': '201', 'numberTo': '248', 'count': 48, 'date': '2026-11-03', 'reason': 'power_outage'};

/// Grundlage: der Golden-Beleg `sale-cash` des Vertrags, dazu der Handbeleg.
KasseneckReceipt _beleg(Map<String, Object>? handbeleg, {bool kleinunternehmer = false}) {
  final roh = Map<String, dynamic>.from(_json('test/fixtures/vertrag/receipts/sale-cash.json')['receipt'] as Map)
    ..remove('manualReceipt');
  if (handbeleg != null) roh['manualReceipt'] = handbeleg;
  roh['customerDetails'] = (roh['customerDetails'] as List).join('\n');
  roh['legalMessage'] = (roh['legalMessage'] as List).join('\n');
  return KasseneckReceipt.fromMetadata(roh, {'company': 'Praxis Mag. Mirela Weinzierl', 'is_small_business': kleinunternehmer});
}

List<Object?> _zeilen(List<LayoutLine> block) => [
      for (final z in block)
        switch (z) {
          LayoutBannerLine() => '<banner ${z.text}>',
          LayoutTextLine() => z.text,
          LayoutSpaceLine() => '<space>',
          _ => z.toJson(),
        }
    ];

void main() {
  group('ManualReceipt', () {
    test('liest Einzel- und Sammelbeleg und schreibt sie gleich zurueck', () {
      expect(ManualReceipt.fromJson(_einzel)!.toJson(), _einzel);
      expect(ManualReceipt.fromJson(_sammel)!.toJson(), _sammel);
      final sonstiges = {..._sammel, 'reason': 'other', 'note': 'Kasse beim Umzug abgebaut'};
      expect(ManualReceipt.fromJson(sonstiges)!.toJson(), sonstiges);
    });
    test('ohne Nummer, Datum oder Grund kein Handbeleg; falsche Zusatzfelder fallen weg', () {
      for (final fehlt in ['number', 'date', 'reason']) {
        expect(ManualReceipt.fromJson(Map.of(_einzel)..remove(fehlt)), isNull, reason: fehlt);
      }
      expect(ManualReceipt.fromJson(null), isNull);
      expect(ManualReceipt.fromJson('H-17'), isNull);
      expect(ManualReceipt.fromJson({..._einzel, 'count': '7', 'numberTo': 5, 'x': 1})!.toJson(), _einzel);
    });
    test('Gruende und Fehlercodes wie im Vertrag', () {
      expect(manualReceiptReasons, (_vokabular['catalogs']['HANDBELEG_GRUND'] as Map).values.toList());
      expect(manualReceiptErrorCodes, _vokabular['errorCodes']['manualReceipt']);
      expect(isManualReceiptErrorCode('manual_receipt_duplicate'), isTrue);
      expect(isManualReceiptErrorCode('handbeleg_doppelt'), isFalse);
    });
    test('am Beleg gelesen und in toJson geschrieben, ohne Feld kein Schluessel', () {
      final beleg = _beleg(_einzel);
      expect(beleg.manualReceipt!.toJson(), _einzel);
      expect((beleg.toJson()['receipt'] as Map)['manualReceipt'], _einzel);
      final ohne = KasseneckReceipt.fromJson(beleg.toJson()..['receipt'] = (Map.of(beleg.toJson()['receipt'] as Map)..remove('manualReceipt')));
      expect(ohne.manualReceipt, isNull);
      expect((ohne.toJson()['receipt'] as Map).containsKey('manualReceipt'), isFalse);
    });
  });

  group('nacherfassungBlock', () {
    test('Einzelbeleg nach Internet-Ausfall mit Uhrzeit', () {
      expect(_zeilen(nacherfassungBlock(_beleg(_einzel))), [
        '<banner NACHERFASSUNG>', 'nach Ausfall der Kasse', 'Grund: Internet', '<space>',
        'Handbeleg Nr. H-17', 'vom 31.12.2026, 14:30 Uhr', 'USt: Duplikat des Handbelegs',
      ]);
    });
    test('Tagessammelbeleg mit Anzahl', () {
      expect(_zeilen(nacherfassungBlock(_beleg(_sammel))).sublist(4), [
        'Tagessammelbeleg', 'Handbelege Nr. 201 bis 248', '48 Belege vom 03.11.2026', 'USt: Duplikat der Handbelege',
      ]);
    });
    test('Leistung ausser Haus ohne Grund-Zeile', () {
      expect(_zeilen(nacherfassungBlock(_beleg({'number': '5', 'date': '2026-10-29', 'reason': 'outside_premises'}))), [
        '<banner NACHERFASSUNG>', 'Leistung außer Haus', '<space>', 'Handbeleg Nr. 5', 'vom 29.10.2026', 'USt: Duplikat des Handbelegs',
      ]);
    });
    test('Kleinunternehmer: keine USt-Zeile; ohne Feld kein Block', () {
      expect(_zeilen(nacherfassungBlock(_beleg(_einzel, kleinunternehmer: true))).any((z) => '$z'.startsWith('USt:')), isFalse);
      expect(nacherfassungBlock(_beleg(null)), isEmpty);
    });
  });
}
