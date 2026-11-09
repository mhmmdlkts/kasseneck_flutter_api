import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

/// Pfand auf dem Ersatz-Bon (`setKeckReceipt`) und im Beleg-Widget: dieselben
/// Zeilen wie das Server-Layout. Vertrag sind die Goldens `deposit` und
/// `deposit-return` des npm-Pakets (1.32.0): Eingabe `receipts/*.json`,
/// Erwartung `expected/*.lines.json`.
final _wurzel = 'test/fixtures/vertrag';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

KasseneckReceipt _beleg(String name) {
  final ein = _json('$_wurzel/receipts/$name.json');
  final firma = ein['company'] as Map;
  return KasseneckReceipt.fromMetadata(ein['receipt'], {'company': firma['companyName'], 'is_small_business': firma['isSmallBusiness'] == true});
}

/// Die Zeilen des Server-Layouts als (links, rechts) bzw. Text; `EUR` statt
/// des Euro-Zeichens, wie der Ersatz-Bon es druckt.
({List<String> paare, List<String> texte}) _erwartet(String name) {
  final zeilen = (_json('$_wurzel/expected/$name.lines.json')['lines'] as List).cast<Map<String, dynamic>>();
  final paare = <String>[];
  final texte = <String>[];
  for (final z in zeilen) {
    if (z['kind'] == 'columns') {
      final spalten = (z['columns'] as List).cast<Map<String, dynamic>>();
      // Das Server-Layout haelt "je" und Preis mit geschuetztem Leerzeichen zusammen; der Ersatz-Bon schreibt ein gewoehnliches.
      if (spalten.length == 2) paare.add('${(spalten[0]['text'] as String).replaceAll('\u00a0', ' ')} | ${(spalten[1]['text'] as String).replaceAll('€', 'EUR')}');
    } else if (z['kind'] == 'text') {
      texte.add(z['text'] as String);
    }
  }
  return (paare: paare, texte: texte);
}

const _kopf = {'Datum:', 'Kassen-ID:', 'Beleg-ID:', 'Kunde:', ''};

Future<({List<String> paare, List<String> texte})> _gedruckt(KasseneckReceipt beleg) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(beleg, qrMode: QrPrintMode.native);
  final paare = <String>[];
  final texte = <String>[];
  for (final c in paper.myPosPaper.commands) {
    if (c['type'] == 'doubleText') {
      final l = c['leftValue'] as String;
      if (!_kopf.contains(l)) paare.add('$l | ${c['rightValue']}');
    } else if (c['type'] == 'text') {
      texte.add(c['value'] as String);
    }
  }
  return (paare: paare, texte: texte);
}

void main() {
  for (final name in ['deposit', 'deposit-return']) {
    test('Ersatz-Bon $name: Positionen, Pfand-Steuerzeile, Gesamt und Zahlung wie das Server-Layout', () async {
      final soll = _erwartet(name);
      final ist = await _gedruckt(_beleg(name));
      final sollOhneKopf = [for (final p in soll.paare) if (!_kopf.contains(p.split(' | ').first)) p];
      expect(ist.paare, sollOhneKopf);
      // Ueberschrift bzw. Ruecknahmestelle stehen als zentrierte Textzeilen.
      for (final t in soll.texte.where((t) => t.startsWith('Leergut-R'))) {
        expect(ist.texte, contains(t));
      }
    });
  }

  test('Pfand steht als eingerueckte Unterzeile nach den Zusaetzen der Position', () async {
    final ist = await _gedruckt(_beleg('deposit'));
    final links = [for (final p in ist.paare) p.split(' | ').first];
    expect(links.indexOf('6  x Cola Dose je 2,00') < links.indexOf('  + 1  x Eiswürfel'), isTrue);
    expect(links.indexOf('  + 1  x Eiswürfel') < links.indexOf('  + 6  x Pfand Einweg je 0,25'), isTrue);
    expect(links.indexOf('  + 6  x Pfand Einweg je 0,25') < links.indexOf('2  x Bier Flasche 0,5 l je 1,80'), isTrue);
  });

  test('Zeile "Pfand, nicht steuerbar" nur bei Einweg, im Leergutbeleg mit Minus', () async {
    final deposit = await _gedruckt(_beleg('deposit'));
    expect(deposit.paare, contains('Pfand, nicht steuerbar | 1,50'));
    final leergut = await _gedruckt(_beleg('deposit-return'));
    expect(leergut.paare, contains('Pfand, nicht steuerbar | -2,50'));
    expect(leergut.paare, contains('Bar ausgezahlt | -3,30 EUR'));
    expect([for (final p in leergut.paare) p.split(' | ').first], isNot(contains('Zahlungsart:')));
    expect(leergut.texte, contains('Leergut-Rückgabe'));
    expect(deposit.texte, isNot(contains('Leergut-Rückgabe')));
  });

  test('Fusszeile mit der Ruecknahmestelle nur, wenn der Beleg sie traegt', () async {
    final mit = await _gedruckt(_beleg('deposit'));
    expect(mit.texte, contains('Leergut-Rückgabe: Max Hollerer GmbH, Mühlweg 9, 4600 Wels'));
    final ohne = await _gedruckt(_beleg('add-ons'));
    expect(ohne.texte.where((t) => t.startsWith('Leergut-R')), isEmpty);
  });

  testWidgets('Widget zeigt Unterzeile, Steuerzeile, Auszahlung und Ruecknahmestelle', (tester) async {
    Future<List<String>> texte(String name) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: _beleg(name))))));
      return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
    }

    final deposit = await texte('deposit');
    expect(deposit, contains('  + 6 x Pfand Einweg je 0,25'));
    expect(deposit.indexOf('  + 1 x Eiswürfel') < deposit.indexOf('  + 6 x Pfand Einweg je 0,25'), isTrue);
    expect(deposit, contains('Pfand, nicht steuerbar'));
    expect(deposit, contains('Leergut-Rückgabe: Max Hollerer GmbH, Mühlweg 9, 4600 Wels'));
    final leergut = await texte('deposit-return');
    expect(leergut, contains('Leergut-Rückgabe'));
    expect(leergut, contains('Bar ausgezahlt'));
    expect(leergut, isNot(contains('Zahlungsart:')));
  });
}
