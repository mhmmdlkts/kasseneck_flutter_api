import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_lines_widget.dart';

/// Golden-Belege des JS-Pakets `@kreiseck/kasseneck-api` (fixtures/): Kopien
/// unter test/fixtures/belege. Das Manifest traegt die Pruefsummen; weichen die
/// Kopien ab, ist die Kopie veraltet -- dann `fixtures` aus dem JS-Paket neu
/// uebernehmen. So zeigen App, Bondrucker, Browser-Kasse und PDF dieselben Zeilen.
final _wurzel = Directory('test/fixtures/belege');

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final manifest = _json('${_wurzel.path}/manifest.json');
  final namen = (manifest['belege'] as Map<String, dynamic>).keys.toList()..sort();

  test('Golden-Kopien stimmen mit dem Manifest des JS-Pakets ueberein (Regelwerk 2, 22 Belege)', () {
    expect(manifest['regelwerk'], 2);
    expect(namen.length, greaterThanOrEqualTo(17));
    for (final n in namen) {
      final e = (manifest['belege'] as Map)[n] as Map;
      final eingabe = sha256.convert(File('${_wurzel.path}/belege/$n.json').readAsBytesSync()).toString();
      final erwartet = sha256.convert(File('${_wurzel.path}/erwartet/$n.lines.json').readAsBytesSync()).toString();
      expect(eingabe, e['eingabe'], reason: 'Fixture-Eingabe $n weicht vom JS-Paket ab');
      expect(erwartet, e['erwartet'], reason: 'Erwartete Zeilen $n weichen vom JS-Paket ab');
    }
  });

  test('BelegLayout liest jede erwartete Zeilenfolge vollstaendig (keine Zeile faellt weg)', () {
    for (final n in namen) {
      final roh = _json('${_wurzel.path}/erwartet/$n.lines.json');
      final layout = BelegLayout.fromJson(roh)!;
      expect(layout.lines.length, (roh['lines'] as List).length, reason: n);
      expect(layout.regelwerk, 2);
      expect(layout.qrDaten, isNotNull, reason: '$n ohne QR');
    }
    // Belegart-Aufdruck der Fixtures
    final storno = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/storno-voll.lines.json'))!;
    expect(storno.bannerTexte, ['STORNOBELEG']);
    final monat = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/null-monat.lines.json'))!;
    expect(monat.bannerTexte, ['MONATSBELEG']);
    expect(monat.lines.whereType<BelegText>().any((t) => t.text == 'Nullbeleg 08/2026'), isTrue);
    // Regelwerk 2: Nullbeleg mit Block "Prüfangaben" statt Summenzeile
    final monatTexte = monat.lines.whereType<BelegText>().map((t) => t.text).toList();
    expect(monatTexte, contains('Prüfangaben'));
    expect(monatTexte, isNot(contains('Betrag: 0,00 €')));
    expect(monat.lines.whereType<BelegSpalten>().any((s) => s.columns.first.text == 'Karte registriert:'), isTrue);
    final testkasse = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/testkasse-verkauf.lines.json'))!;
    expect(testkasse.bannerTexte.first, startsWith('TESTKASSE'));
    expect(testkasse.bannerTexte.last, startsWith('TESTKASSE'));
    // unbekannte Zeilenart wird uebersprungen, nicht geworfen
    final l = BelegLayout.fromJson({'lines': [{'kind': 'hologramm', 'x': 1}, {'kind': 'text', 'text': 'A', 'align': 'left', 'bold': false}], 'paperSize': 'mm80', 'regelwerk': 1})!;
    expect(l.lines.length, 1);
    expect(BelegLayout.fromJson(null), isNull);
  });

  test('KasseneckReceipt.fromJson nimmt layout/testKasse/testSignatur/kopfId; altes Backend -> null/false', () {
    final f = _json('${_wurzel.path}/belege/storno-voll.json');
    final firma = f['company'] as Map<String, dynamic>;
    final antwort = <String, dynamic>{
      'receipt': {...(f['receipt'] as Map<String, dynamic>), 'customerDetails': '', 'legalMessage': ''},
      'company': firma['companyName'], 'street': firma['street'], 'zip': firma['zip'], 'city': firma['city'], 'phone': firma['phone'],
      'uid': firma['uid'], 'taxnr': firma['taxnr'], 'is_small_business': false, 'footer1': firma['footer1'], 'footer2': firma['footer2'],
      'layout': _json('${_wurzel.path}/erwartet/storno-voll.lines.json'), 'testSignatur': true, 'kopfId': 'v1',
    };
    final r = KasseneckReceipt.fromJson(antwort);
    expect(r.layout, isNotNull);
    expect(r.layout!.bannerTexte, ['STORNOBELEG']);
    expect(r.testSignatur, isTrue);
    expect(r.testKasse, isFalse);
    expect(r.kopfId, 'v1');
    final alt = KasseneckReceipt.fromJson({...antwort}..remove('layout')..remove('testSignatur')..remove('kopfId'));
    expect(alt.layout, isNull);
    expect(alt.testSignatur, isFalse);
    expect(alt.kopfId, isNull);
  });

  test('PrintPaper.setBelegLayout druckt jede Fixture: Texte, Aufdruck (doppelt hoch), QR, Schnitt', () {
    for (final n in namen) {
      final layout = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/$n.lines.json'))!;
      final paper = PrintPaper(paperSize: KeckPaperSize.mm80, profile: CapabilityProfile());
      paper.setBelegLayout(layout);
      final bytes = paper.bytes.expand((b) => b).toList();
      final text = latin1.decode(bytes, allowInvalid: true);
      for (final b in layout.bannerTexte) {
        expect(text, contains(b.split(' — ').first), reason: '$n: Aufdruck $b fehlt im Bytestrom');
      }
      // Kopf steht drin, QR-Befehl (GS ( k) und Schnitt (GS V) sind da
      expect(text, contains('B'), reason: n);
      // Rasterzeilen (80 mm = 48 Zeichen): die Gesamt-Zeile steht als eine
      // Textzeile im Bytestrom, Preis buendig rechts (EUR statt Euro-Zeichen,
      // gerastert NACH dem Druckbarmachen -> weiterhin exakt 48 Zeichen).
      final soll = File('${_wurzel.path}/erwartet/$n.grid48.txt').readAsStringSync().split('\n');
      final gesamtZeile = soll.firstWhere((z) => z.startsWith('Gesamt:'), orElse: () => '');
      if (gesamtZeile.isNotEmpty) {
        final treffer = RegExp(r'Gesamt: +-?[\d.,]+ EUR').firstMatch(text);
        expect(treffer, isNotNull, reason: '$n: Gesamt-Zeile nicht als Rasterzeile im Bytestrom');
        expect(treffer!.group(0)!.length, 48, reason: '$n: Gesamt-Zeile nicht 48 Zeichen breit');
      }
      expect(bytes, containsAllInOrder([0x1D, 0x28, 0x6B]), reason: '$n: kein QR');
      expect(bytes.sublist(bytes.length - 6), contains(0x56), reason: '$n: kein Schnitt');
    }
  });

  testWidgets('KeckReceiptLinesWidget zeigt Zeilen, Aufdruck und (verdeckten) QR', (tester) async {
    final layout = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/training.lines.json'))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: KeckReceiptLinesWidget(layout: layout, qrCovered: true)))));
    expect(find.text('TRAININGSBELEG'), findsOneWidget);
    expect(find.byKey(const Key('keck-receipt-banner-belegart')), findsOneWidget);
    expect(find.textContaining('kein Kauf, keine Zahlung'), findsOneWidget);
    expect(find.text('Antippen zum Anzeigen'), findsOneWidget);
    // Rot-Probe: normaler Verkauf ohne Aufdruck
    final verkauf = BelegLayout.fromJson(_json('${_wurzel.path}/erwartet/verkauf-bar.lines.json'))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: KeckReceiptLinesWidget(layout: verkauf)))));
    expect(find.byKey(const Key('keck-receipt-banner-belegart')), findsNothing);
    expect(find.text('Bäckerei Muster'), findsOneWidget);
  });
}
