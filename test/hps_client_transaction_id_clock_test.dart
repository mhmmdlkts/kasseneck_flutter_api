import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// [HpsClient.newTransactionId] haelt den zuletzt vergebenen Zeitstempel in
/// prozessweitem statischem Zustand, damit die Kennung innerhalb eines
/// Prozesses garantiert nie zweimal vergeben wird -- auch nicht bei einer
/// rueckwaerts springenden Uhr (siehe Dartdoc dort). Die Tests hier erzwingen
/// dafuer absichtlich einen Zeitstempel weit in der Zukunft (100/200 Jahre),
/// damit die Kollisionspruefung unabhaengig von der echten Systemuhr
/// nachvollziehbar bleibt.
///
/// Das hinterlaesst den statischen Zustand DAUERHAFT in der Zukunft -- ohne
/// oeffentlichen Reset (der Zustand ist bewusst privat) waere jeder spaetere
/// Aufruf von [HpsClient.newTransactionId] ueber die echte Systemuhr in
/// DERSELBEN Test-Datei betroffen: die Kennung traegt dann einen 100/200
/// Jahre zu hohen Zeitstempel statt der echten Zeit. Deshalb liegen diese
/// beiden Tests in einer eigenen Datei -- `package:test` fuehrt jede
/// Test-Datei in einer eigenen Isolate aus, der statische Zustand bleibt
/// also auf diese Datei beschraenkt und ist keine Falle fuer
/// `test/hps_client_test.dart`.
void main() {
  group('Erzeugte Kennung -- erzwungener Zukunfts-Zeitstempel', () {
    const oneYearMs = 365 * 24 * 60 * 60 * 1000;

    test('erzwungen viele Kennungen in derselben Millisekunde bleiben eindeutig -- '
        'auch wenn der Zaehler ueberlaeuft', () {
      final fixedMs =
          DateTime.now().millisecondsSinceEpoch + 100 * oneYearMs;
      final ids = <String>{};
      // mehr als 100000, damit der Zaehler je Millisekunde nachweislich
      // ueberlaeuft und auf die naechste Millisekunde weiterschaltet
      const callCount = 250000;
      for (var i = 0; i < callCount; i++) {
        final id = HpsClient.newTransactionId(nowMillis: fixedMs);
        expect(id.length, lessThanOrEqualTo(18));
        expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
        ids.add(id);
      }
      expect(ids.length, callCount);
    });

    test('eine rueckwaerts springende Uhr wiederholt keine bereits vergebene Kennung', () {
      final highMs =
          DateTime.now().millisecondsSinceEpoch + 200 * oneYearMs;
      final ids = <String>{
        HpsClient.newTransactionId(nowMillis: highMs),
        // Uhr springt um eine Minute zurueck (z.B. NTP-Korrektur)
        HpsClient.newTransactionId(nowMillis: highMs - 60000),
        // Uhr springt um eine Stunde zurueck (z.B. Zeitumstellung)
        HpsClient.newTransactionId(nowMillis: highMs - 3600000),
        // dieselbe Millisekunde erneut
        HpsClient.newTransactionId(nowMillis: highMs),
      };
      expect(ids.length, 4);
    });
  });
}
