import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/printer_service.dart';

/// Mehrere Zahlungen an den Golden-Belegen des JS-Pakets (`split-*`,
/// `storno-split-*`): der Beleg liest sich, das gelieferte Layout gilt als
/// vollstaendig und wird gedruckt, ein Layout ohne die Kartenbloecke nicht.
///
/// Die Belege kommen mit der npm-Version, die die Zahlungsliste einfuehrt; bis
/// die Kopie unter test/fixtures/vertrag auf diesem Stand ist, wird hier
/// uebersprungen statt rot gemeldet -- der Manifest-Abgleich in
/// beleg_layout_test.dart haelt die Kopie ohnehin echt.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

KasseneckReceipt _beleg(String name, {String? layoutVon}) {
  final f = _json('${_wurzel.path}/belege/$name.json');
  final firma = f['company'] as Map<String, dynamic>;
  return KasseneckReceipt.fromJson({
    'receipt': {...(f['receipt'] as Map<String, dynamic>), 'customerDetails': '', 'legalMessage': ''},
    'company': firma['companyName'],
    'street': firma['street'],
    'zip': firma['zip'],
    'city': firma['city'],
    'phone': firma['phone'],
    'uid': firma['uid'],
    'taxnr': firma['taxnr'],
    'is_small_business': false,
    'footer1': firma['footer1'] ?? '',
    'footer2': firma['footer2'] ?? '',
    'layout': _json('${_wurzel.path}/erwartet/${layoutVon ?? name}.lines.json'),
  });
}

void main() {
  final manifest = _json('${_wurzel.path}/manifest.json');
  final namen = (manifest['belege'] as Map<String, dynamic>).keys.where((n) => n.contains('split')).toList()..sort();
  final skip = namen.isEmpty ? 'Vertragskopie noch ohne Belege mit mehreren Zahlungen' : null;

  test('jeder Beleg mit Zahlungsliste liest sich und sein Layout gilt als vollstaendig', () {
    for (final n in namen) {
      final roh = (_json('${_wurzel.path}/belege/$n.json')['receipt'] as Map)['payments'] as List;
      final b = _beleg(n);
      expect(b.payments!.length, roh.length, reason: n);
      expect(b.layoutIstVollstaendig, isTrue, reason: n);
    }
  }, skip: skip);

  test('mixed kommt als mixed an, nicht als Barzahlung', () {
    final mixed = [
      for (final n in namen)
        if ((_json('${_wurzel.path}/belege/$n.json')['receipt'] as Map)['paymentMethod'] == 'mixed') n,
    ];
    expect(mixed, isNotEmpty);
    for (final n in mixed) {
      expect(_beleg(n).paymentMethod, KeckPaymentMethod.mixed, reason: n);
    }
  }, skip: skip);

  test('ein Layout ohne die Kartenbloecke gilt nicht als vollstaendig', () {
    final mitKarte = [for (final n in namen) if (_beleg(n).kartenzahlungen.isNotEmpty) n];
    expect(mitKarte, isNotEmpty);
    for (final n in mitKarte) {
      expect(_beleg(n, layoutVon: 'verkauf-bar').layoutIstVollstaendig, isFalse, reason: n);
    }
  }, skip: skip);

  test('der Bon druckt das gelieferte Layout samt eingerueckter Zeilen', () async {
    final raster = File('${_wurzel.path}/erwartet/split-karte-karte-bar.grid48.txt');
    final b = _beleg('split-karte-karte-bar');
    final paper = await KeckPrinterService.getPaperFromReceipt(b, KeckPaperSize.mm80);
    final text = latin1.decode(paper.bytes.expand((x) => x).toList(), allowInvalid: true);
    expect(raster.readAsStringSync(), contains('  Gegeben:'));
    expect(text, contains('  Gegeben:'));
    expect(text, contains('1. Kartenzahlung'));
    expect(text, contains('Zahlungsarten:'));
  }, skip: skip);
}
