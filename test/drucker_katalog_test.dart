import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/src/kasse/drucker_katalog.dart'
    show
        PrinterCatalogProblemReason,
        findPrinterCatalogEntry,
        normalizePrinterModel,
        printerCatalog,
        printerCatalogCharsPerLine,
        printerCatalogCuts,
        printerCatalogProblems,
        printerCatalogQrModes;

/// Druckerkatalog, Zwilling von `drucker-katalog.test.ts` (npm 1.35.0):
/// `printer-catalog.json` ist der Vertrag, beide Seiten rechnen dieselben
/// Faelle. Die Datei fuehrt die ausgelieferten Eintraege, die Wertemengen und
/// die Prueffaelle; dieser Test haelt Code und Datei deckungsgleich.
final Map<String, dynamic> _vertrag =
    jsonDecode(File('test/fixtures/vertrag/printer-catalog.json').readAsStringSync()) as Map<String, dynamic>;
final Map<String, dynamic> _faelle = (_vertrag['cases'] as Map).cast<String, dynamic>();
final PrinterDeviceTest _geraetetest = PrinterDeviceTest.fromJson(
  (_faelle['deviceTest'] as Map).cast<String, dynamic>(),
);

List<Map<String, dynamic>> _liste(String abschnitt) => (_faelle[abschnitt] as List).cast<Map<String, dynamic>>();

/// Der ausgelieferte Katalog, die Eintraege mit [ids] freigegeben (mit dem
/// Geraetetest der Datei).
List<PrinterCatalogEntry> _freigegeben(Iterable<String> ids) => [
  for (final e in printerCatalog)
    ids.contains(e.id)
        ? PrinterCatalogEntry(
            id: e.id,
            manufacturer: e.manufacturer,
            model: e.model,
            matchNames: e.matchNames,
            values: e.values,
            approval: PrinterCatalogApproval(approved: true, deviceTest: _geraetetest),
          )
        : e,
];

final List<PrinterCatalogEntry> _alleFrei = _freigegeben([for (final e in printerCatalog) e.id]);

List<Map<String, String>> _funde(List<PrinterCatalogEntry> katalog) => [
  for (final p in printerCatalogProblems(katalog)) p.toJson(),
];

void main() {
  group('Vertrag', () {
    test('Abschnitte der Datei', () {
      expect(_vertrag.keys, ['_note', 'rules', 'printers', 'cases']);
      expect(_faelle.keys, [
        'normalize',
        'lookupShipped',
        'lookup',
        'lookupPartial',
        'deviceTest',
        'settings',
        'problems',
      ]);
    });

    test('die Wertemengen sind die der Geraete-Einstellungen', () {
      final regeln = (_vertrag['rules'] as Map).cast<String, dynamic>();
      expect(regeln['paperSize'], [for (final p in PosPaperSize.values) p.value]);
      expect(regeln['charsPerLine'], {for (final e in printerCatalogCharsPerLine.entries) e.key.value: e.value});
      expect(regeln['cut'], [for (final c in printerCatalogCuts) c.value]);
      expect(regeln['qrMode'], [for (final q in printerCatalogQrModes) q.value]);
      expect(regeln['codePage'], [for (final c in PosCodePage.values) c.value]);
      expect(regeln['problemReasons'], [for (final r in PrinterCatalogProblemReason.values) r.value]);
    });
  });

  group('Katalog', () {
    test('im Code stehen genau die Eintraege der Datei', () {
      expect([for (final e in printerCatalog) e.toJson()], _vertrag['printers']);
    });

    test('der ausgelieferte Katalog hat keinen Fund, auch ganz freigegeben nicht', () {
      expect(_funde(printerCatalog), isEmpty);
      expect(_funde(_alleFrei), isEmpty);
    });

    test('jeder Name fuehrt genau zu seinem Eintrag', () {
      for (final e in _alleFrei) {
        for (final name in e.matchNames) {
          expect(
            [
              for (final x in _alleFrei)
                if (x.matchNames.contains(name)) x.id,
            ],
            [e.id],
            reason: name,
          );
          expect(findPrinterCatalogEntry(_alleFrei, name)?.id, e.id, reason: name);
        }
      }
    });

    test('Eintraege sind unveraenderlich', () {
      expect(() => printerCatalog.first.matchNames.add('X'), throwsUnsupportedError);
    });
  });

  group('normalizePrinterModel', () {
    for (final f in _liste('normalize')) {
      test(jsonEncode(f['input']), () => expect(normalizePrinterModel(f['input'] as String?), f['output']));
    }
  });

  group('printerCatalogEntry (ausgeliefert)', () {
    for (final f in _liste('lookupShipped')) {
      test(jsonEncode(f['model']), () => expect(printerCatalogEntry(f['model'] as String?)?.id, f['expected']));
    }
  });

  group('printerCatalogEntry (alle freigegeben)', () {
    for (final f in _liste('lookup')) {
      test(
        jsonEncode(f['model']),
        () => expect(findPrinterCatalogEntry(_alleFrei, f['model'] as String?)?.id, f['expected']),
      );
    }
  });

  group('printerCatalogEntry (teilweise freigegeben)', () {
    for (final f in _liste('lookupPartial')) {
      test('${jsonEncode(f['approve'])}: ${jsonEncode(f['model'])}', () {
        final katalog = _freigegeben((f['approve'] as List).cast<String>());
        expect(_funde(katalog), isEmpty);
        expect(findPrinterCatalogEntry(katalog, f['model'] as String?)?.id, f['expected']);
      });
    }
  });

  test('printerCatalogSettings: je Eintrag die Einstellungen der Datei, alles gueltige Geraete-Werte', () {
    expect([for (final f in _liste('settings')) f['id']], [for (final e in printerCatalog) e.id]);
    for (final f in _liste('settings')) {
      final eintrag = printerCatalog.firstWhere((e) => e.id == f['id']);
      // Der Vorschlag geht unveraendert als Teil der Geraete-Einstellungen hinaus (saveDevice).
      final teil = printerCatalogSettings(eintrag).toJson();
      expect(teil, f['settings'], reason: f['id'] as String);
      for (final MapEntry(key: feld, value: wert) in teil.entries) {
        final erlaubt = posDeviceValues[feld];
        if (erlaubt != null) {
          expect(erlaubt, contains(wert), reason: '${f['id']}: $feld');
        } else {
          expect(wert, isA<bool>(), reason: '${f['id']}: $feld');
        }
      }
    }
  });

  group('printerCatalogProblems', () {
    for (final f in _liste('problems')) {
      test(f['name'] as String, () {
        final katalog = [
          for (final p in (f['printers'] as List).cast<Map<String, dynamic>>()) PrinterCatalogEntry.fromJson(p),
        ];
        expect(_funde(katalog), f['expected']);
      });
    }

    test('ein Wert ausserhalb der Einstellungen scheitert schon beim Lesen', () {
      final json = jsonDecode(jsonEncode(_vertrag['printers'][0])) as Map<String, dynamic>;
      (json['values'] as Map)['paperSize'] = 'mm100';
      expect(() => PrinterCatalogEntry.fromJson(json), throwsFormatException);
    });
  });
}
