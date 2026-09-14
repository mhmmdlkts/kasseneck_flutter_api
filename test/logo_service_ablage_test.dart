import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/services/logo_service.dart';

/// Die Ablage soll den ersten Bon nach einem App-Start mit Logo drucken, ohne
/// auf das Netz zu warten. Jeder Test simuliert den Neustart mit
/// `speicherLeeren()` und zaehlt, ob dafuer ein Request hinausging.

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]);

void main() {
  late Directory ordner;
  var anfragen = 0;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('logo_ablage_');
    LogoService.speicherOrdner = ordner;
    LogoService.frist = LogoService.standardFrist;
    LogoService.auffrischenNach = const Duration(days: 7);
    LogoService.speicherLeeren();
    anfragen = 0;
  });

  tearDown(() {
    LogoService.speicherOrdner = null;
    LogoService.speicherLeeren();
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  void netzLiefert(Uint8List bytes, [int status = 200]) {
    LogoService.httpClient = MockClient((_) async {
      anfragen++;
      return http.Response.bytes(bytes, status);
    });
  }

  void netzWeg() {
    LogoService.httpClient = MockClient((_) async {
      anfragen++;
      throw http.ClientException('offline');
    });
  }

  List<File> logoDateien() =>
      ordner.listSync().whereType<File>().where((f) => f.path.endsWith('.logo')).toList();

  test('nach dem Neustart kommt das Logo von der Platte, ohne Request', () async {
    const url = 'https://example.test/logo_1788764947508.png?token=abc';
    netzLiefert(_png);
    await LogoService.loadLogo(url);
    expect(anfragen, 1);

    LogoService.speicherLeeren();
    netzWeg();
    await LogoService.loadLogo(url);

    expect(anfragen, 1, reason: 'die Ablage muss den Request ersparen');
    expect(LogoService.getLogoBytes(url), _png);
  });

  test('die Adresse steht nicht im Klartext auf der Platte (Token)', () async {
    const url = 'https://example.test/logo.png?token=geheim-token';
    netzLiefert(_png);
    await LogoService.loadLogo(url);
    final namen = logoDateien().map((f) => f.path).join(' ');
    expect(logoDateien(), hasLength(1));
    expect(namen, isNot(contains('geheim-token')));
  });

  test('ein altes abgelegtes Logo wird aufgefrischt', () async {
    const url = 'https://example.test/fest.jpg';
    netzLiefert(_png);
    await LogoService.loadLogo(url);
    logoDateien().single.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));

    LogoService.speicherLeeren();
    netzLiefert(_jpeg);
    await LogoService.loadLogo(url);

    expect(anfragen, 2);
    expect(LogoService.getLogoBytes(url), _jpeg, reason: 'ueberschriebenes Logo kommt nach');
    expect(logoDateien().single.readAsBytesSync(), _jpeg);
  });

  test('scheitert die Auffrischung, bleibt das alte Logo statt keines', () async {
    const url = 'https://example.test/fest-offline.jpg';
    netzLiefert(_png);
    await LogoService.loadLogo(url);
    logoDateien().single.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));

    LogoService.speicherLeeren();
    netzWeg();
    await LogoService.loadLogo(url);

    expect(LogoService.getLogoBytes(url), _png);
  });

  test('eine kaputte Datei wird verworfen und neu geholt', () async {
    const url = 'https://example.test/kaputt.png';
    netzLiefert(_png);
    await LogoService.loadLogo(url);
    final datei = logoDateien().single;
    datei.writeAsBytesSync([1, 2, 3]); // halb geschrieben / fremd

    LogoService.speicherLeeren();
    netzLiefert(_jpeg);
    await LogoService.loadLogo(url);

    expect(anfragen, 2);
    expect(LogoService.getLogoBytes(url), _jpeg);
    expect(datei.readAsBytesSync(), _jpeg);
  });

  test('ohne Netz und ohne Ablage: kein Logo, kein Wurf', () async {
    netzWeg();
    const url = 'https://example.test/nie-geladen.png';
    await LogoService.loadLogo(url);
    expect(LogoService.getLogoBytes(url), isNull);
    expect(logoDateien(), isEmpty);
  });

  test('keine Bilddatei (z. B. HTML-Fehlerseite mit 200) wird nicht abgelegt', () async {
    const url = 'https://example.test/portal.png';
    netzLiefert(Uint8List.fromList('<html>Captive Portal</html>'.codeUnits));
    await LogoService.loadLogo(url);
    expect(logoDateien(), isEmpty);
  });

  test('hoechstens maxDateien Logos, die aeltesten gehen zuerst', () async {
    netzLiefert(_png);
    for (var i = 0; i < LogoService.maxDateien; i++) {
      final url = 'https://example.test/alt_$i.png';
      await LogoService.loadLogo(url);
    }
    // Alter festlegen: alt_0 am aeltesten.
    final vorher = logoDateien()..sort((a, b) => a.path.compareTo(b.path));
    expect(vorher, hasLength(LogoService.maxDateien));
    final aeltester = File(vorher.first.path);
    for (final (i, f) in vorher.indexed) {
      f.setLastModifiedSync(DateTime.now().subtract(Duration(hours: 100 - i)));
    }

    await LogoService.loadLogo('https://example.test/neu.png');

    final nachher = logoDateien();
    expect(nachher, hasLength(LogoService.maxDateien));
    expect(aeltester.existsSync(), isFalse, reason: 'die aelteste Datei geht zuerst');
  });

  test('ein fehlender Ordner wird angelegt', () async {
    LogoService.speicherOrdner = Directory('${ordner.path}/tief/drin');
    netzLiefert(_png);
    await LogoService.loadLogo('https://example.test/ordner.png');
    expect(Directory('${ordner.path}/tief/drin').listSync().whereType<File>(), hasLength(1));
  });

  group('istBilddatei', () {
    test('PNG, JPEG, WebP ja', () {
      expect(LogoService.istBilddatei(_png), isTrue);
      expect(LogoService.istBilddatei(_jpeg), isTrue);
      final webp = Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]);
      expect(LogoService.istBilddatei(webp), isTrue);
    });

    test('Text, leer und abgeschnittene Koepfe nein', () {
      expect(LogoService.istBilddatei(Uint8List(0)), isFalse);
      expect(LogoService.istBilddatei(Uint8List.fromList([0x89, 0x50])), isFalse);
      expect(LogoService.istBilddatei(Uint8List.fromList('RIFF1234WAVE'.codeUnits)), isFalse);
    });
  });
}
