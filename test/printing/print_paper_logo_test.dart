import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

import '../helpers/test_receipts.dart';

/// Das Logo kommt aus einem HTTP-Abruf, der nur den Status prueft — nicht, ob
/// die Bytes ein Bild sind. Ein kaputtes Logo darf den Beleg nicht kosten:
/// es wird als Erstes verarbeitet, der gesetzlich vorgeschriebene QR-Code
/// entsteht erst weit danach.

Future<KasseneckReceipt> belegMitLogo(String url, Uint8List bytes) async {
  LogoService.httpClient = MockClient((_) async => http.Response.bytes(bytes, 200));
  final receipt = buildReceipt(items: cartA().items);
  receipt.logoUrl = url;
  await receipt.init();
  expect(receipt.logo, isNotNull, reason: 'Vorbedingung: Bytes liegen im Cache');
  return receipt;
}

Future<PrintPaper> drucke(KasseneckReceipt receipt) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
  return paper;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => LogoService.frist = LogoService.standardFrist);

  test('kaputte Logo-Bytes: der Beleg entsteht trotzdem, samt QR', () async {
    // Genau die Bytes, die der eigene LogoService-Test als "erfolgreich
    // geladenes Logo" im Cache ablegt.
    final receipt = await belegMitLogo(
        'https://example.test/kaputt.png', Uint8List.fromList([1, 2, 3]));

    final paper = await drucke(receipt);

    final arten = paper.myPosPaper.commands.map((c) => c['type']).toList();
    expect(arten, contains('qrCode'), reason: 'QR-Code fehlt');
    expect(arten, isNot(contains('image')), reason: 'kein Logo erwartet');
    final doubles = paper.myPosPaper.commands.where((c) => c['type'] == 'doubleText');
    expect(doubles.map((c) => c['leftValue']), contains('Gesamt:'));
  });

  test('leere Logo-Bytes reissen den Beleg nicht mit', () async {
    final receipt = await belegMitLogo('https://example.test/leer.png', Uint8List(0));
    final paper = await drucke(receipt);
    expect(paper.myPosPaper.commands.map((c) => c['type']), contains('qrCode'));
  });

  test('ein gueltiges Logo wird weiterhin gedruckt', () async {
    // Gegenprobe: der Fangzweig darf nicht jedes Logo verschlucken.
    final png = await encodePng(RasterImage.filled(8, 8, 0, 0, 0, 255));
    final receipt = await belegMitLogo('https://example.test/gut.png', png);

    final paper = await drucke(receipt);

    expect(paper.myPosPaper.commands.map((c) => c['type']), contains('image'));
  });
}
