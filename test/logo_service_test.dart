import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/services/logo_service.dart';

/// Das Logo haengt im Verkaufsweg HINTER dem bereits signierten Beleg. Alles
/// hier ist deshalb an einer Frage gemessen: kann dieser Abruf einen Verkauf
/// aufhalten?

void main() {
  setUp(() {
    // Prozessweiter Zustand — sonst faerbt eine gesetzte Frist auf die
    // Nachbartests ab.
    LogoService.frist = LogoService.standardFrist;
  });

  test('null-URL: kein Request, kein Ergebnis', () async {
    LogoService.httpClient = MockClient((_) async => fail('kein Request erwartet'));
    await LogoService.loadLogo(null);
    expect(LogoService.getLogoBytes(null), isNull);
  });

  test('laedt einmal und cached danach (kein zweiter Request)', () async {
    int calls = 0;
    LogoService.httpClient = MockClient((_) async {
      calls++;
      return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
    });
    const url = 'https://example.test/logo-cache.png';
    await LogoService.loadLogo(url);
    await LogoService.loadLogo(url);
    expect(calls, 1);
    expect(LogoService.getLogoBytes(url), [1, 2, 3]);
  });

  test('non-200 wird nicht gecached', () async {
    LogoService.httpClient = MockClient((_) async => http.Response('nope', 404));
    const url = 'https://example.test/logo-404.png';
    await LogoService.loadLogo(url);
    expect(LogoService.getLogoBytes(url), isNull);
  });

  test('Netzwerkfehler wird geschluckt (kein Throw)', () async {
    LogoService.httpClient = MockClient((_) async => throw http.ClientException('offline'));
    const url = 'https://example.test/logo-err.png';
    await LogoService.loadLogo(url); // darf nicht werfen
    expect(LogoService.getLogoBytes(url), isNull);
  });

  test('haengender Host: der Abruf endet mit der Frist statt nie', () async {
    // Der Fall, der weh tut: der Host nimmt die Verbindung an und antwortet
    // nie. Kein Fehler, kein Ergebnis. Ohne Frist kehrte loadLogo — und mit
    // ihm sellReceipt hinter dem bereits signierten Beleg — nie zurueck.
    LogoService.frist = const Duration(milliseconds: 20);
    LogoService.httpClient = MockClient((_) => Completer<http.Response>().future);
    const url = 'https://example.test/logo-haengt.png';

    await LogoService.loadLogo(url).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('loadLogo haengt trotz Frist'),
    );

    expect(LogoService.getLogoBytes(url), isNull, reason: 'Fehlschlag heisst kein Logo');
  });

  test('Frist deckt auch den Rumpf, nicht nur den Antwortkopf', () async {
    // Ein Host, der Kopf und 200 schickt und den Rumpf stehen laesst, ist
    // dieselbe Falle eine Ebene tiefer. `Client.get` liest den Rumpf, bevor
    // das Future abschliesst — die Frist muss also auch das decken.
    LogoService.frist = const Duration(milliseconds: 20);
    LogoService.httpClient = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        StreamController<List<int>>().stream, // Rumpf kommt nie
        200,
      );
    });
    const url = 'https://example.test/logo-rumpf.png';

    await LogoService.loadLogo(url).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('loadLogo haengt am offenen Rumpf'),
    );

    expect(LogoService.getLogoBytes(url), isNull);
  });

  test('gleichzeitige Abrufe derselben Adresse teilen sich einen Request', () async {
    // getReceipts ruft init() fuer jeden Beleg des Zeitraums; die tragen fast
    // alle dieselbe Adresse. Die Cache-Pruefung liegt vor dem await.
    int calls = 0;
    final tor = Completer<void>();
    LogoService.httpClient = MockClient((_) async {
      calls++;
      await tor.future;
      return http.Response.bytes(Uint8List.fromList([9]), 200);
    });
    const url = 'https://example.test/logo-parallel.png';

    final erster = LogoService.loadLogo(url);
    final zweiter = LogoService.loadLogo(url);
    final dritter = LogoService.loadLogo(url);
    tor.complete();

    // Wer sich anhaengt, wartet mit: nach dem zweiten Abruf muss das Logo da
    // sein. Ein blosses „schon jemand unterwegs, ich bin fertig" gaebe dem
    // Aufrufer einen leeren Cache zurueck.
    await zweiter;
    expect(LogoService.getLogoBytes(url), [9], reason: 'wer sich anhaengt, wartet mit');

    await Future.wait([erster, dritter]);
    expect(calls, 1);
  });
}
