import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/services/logo_service.dart';

void main() {
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
}
