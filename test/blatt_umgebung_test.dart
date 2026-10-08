import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/widgets/keck_receipt_sheet_widget.dart';

// Das Blatt misst die Zeichenbreite selbst und zeichnet in genau dieser Breite.
// Erbt der Text etwas, das die Messung nicht kennt -- Zeichenabstand aus dem
// App-Thema (Material 3: 0,25), die Textgroesse des Geraets oder iOS-
// "Fettschrift" --, ist jede volle Zeile breiter als das Blatt, und das letzte
// Zeichen faellt weg (in karteck: "Kartenzahlun" statt "Kartenzahlung").

ReceiptLayout _fixture(String name) => ReceiptLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/expected/$name.lines.json').readAsStringSync()))!;

class _Umgebung {
  final String name;
  final TextStyle? stil;
  final double scale;
  final bool fett;
  const _Umgebung(this.name, {this.stil, this.scale = 1.0, this.fett = false});
}

const _umgebungen = [
  _Umgebung('neutral'),
  _Umgebung('Zeichenabstand aus dem Thema', stil: TextStyle(letterSpacing: 0.5, wordSpacing: 2)),
  _Umgebung('Textgroesse 1,3', scale: 1.3),
  _Umgebung('Textgroesse 0,85', scale: 0.85),
  _Umgebung('iOS-Fettschrift', fett: true),
  _Umgebung('alles zusammen', stil: TextStyle(letterSpacing: 0.5), scale: 1.3, fett: true),
];

void main() {
  for (final u in _umgebungen) {
    testWidgets('${u.name}: volle Zeilen passen genau ins Blatt', (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(u.scale), boldText: u.fett),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DefaultTextStyle.merge(
              style: u.stil,
              child: KeckReceiptSheetWidget(layout: _fixture('cancellation-full')),
            ),
          ),
        ),
      ));
      final blatt = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
      final zeilen = find.text('=' * 48);
      expect(zeilen, findsNWidgets(2));
      for (final e in zeilen.evaluate()) {
        final text = tester.renderObject<RenderParagraph>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(RichText)).first);
        final breite = text.getMaxIntrinsicWidth(double.infinity);
        expect(breite, closeTo(blatt, 0.5), reason: 'Zeile $breite px auf Blatt $blatt px');
      }
    });
  }
}
