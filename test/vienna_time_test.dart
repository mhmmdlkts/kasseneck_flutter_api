import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

void main() {
  group('ViennaTime.offsetAt', () {
    test('Winterzeit ist UTC+1', () {
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 1, 10, 12)),
          const Duration(hours: 1));
    });

    test('Sommerzeit ist UTC+2', () {
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 7, 17, 12)),
          const Duration(hours: 2));
    });

    test('Umstellung März 2026: letzter Sonntag (29.03.) um 01:00 UTC', () {
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 3, 29, 0, 59)),
          const Duration(hours: 1));
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 3, 29, 1, 0)),
          const Duration(hours: 2));
    });

    test('Umstellung Oktober 2026: letzter Sonntag (25.10.) um 01:00 UTC', () {
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 10, 25, 0, 59)),
          const Duration(hours: 2));
      expect(ViennaTime.offsetAt(DateTime.utc(2026, 10, 25, 1, 0)),
          const Duration(hours: 1));
    });
  });

  group('ViennaTime Wanduhr-Konvertierung', () {
    test('fromWallClock im Sommer: 23:30 Wien = 21:30 UTC', () {
      final instant = ViennaTime.fromWallClock(DateTime(2026, 7, 17, 23, 30));
      expect(instant, DateTime.utc(2026, 7, 17, 21, 30));
    });

    test('fromWallClock im Winter: 12:00 Wien = 11:00 UTC', () {
      final instant = ViennaTime.fromWallClock(DateTime(2026, 1, 10, 12));
      expect(instant, DateTime.utc(2026, 1, 10, 11));
    });

    test('toWallClock ist die Umkehrung von fromWallClock', () {
      for (final wall in [
        DateTime(2026, 7, 17, 23, 30),
        DateTime(2026, 1, 10, 0, 5),
        DateTime(2026, 3, 29, 12),
        DateTime(2026, 10, 25, 12),
      ]) {
        expect(ViennaTime.toWallClock(ViennaTime.fromWallClock(wall)), wall);
      }
    });

    test('toWallClock liefert ein naives DateTime', () {
      expect(ViennaTime.toWallClock(DateTime.utc(2026, 7, 17, 12)).isUtc, false);
    });
  });

  group('ViennaTime.dayKey', () {
    test('Zahlung 00:30 türkischer Zeit landet im Wiener Vortag', () {
      // 18.07. 00:30 UTC+3 (Türkei) = 17.07. 21:30 UTC = 17.07. 23:30 Wien.
      final paymentInstant = DateTime.utc(2026, 7, 17, 21, 30);
      expect(ViennaTime.dayKey(paymentInstant), '2026-07-17');
    });

    test('Beleg (Server-Wanduhrzeit) und Zahlung bekommen denselben Tag', () {
      final receiptInstant =
          ViennaTime.parseServerTimeStamp('2026-07-17T23:30:00');
      final paymentInstant = DateTime.utc(2026, 7, 17, 21, 30);
      expect(ViennaTime.dayKey(receiptInstant),
          ViennaTime.dayKey(paymentInstant));
    });

    test('Wiener Mitternachtsgrenze', () {
      expect(ViennaTime.dayKey(DateTime.utc(2026, 7, 17, 21, 59)), '2026-07-17');
      expect(ViennaTime.dayKey(DateTime.utc(2026, 7, 17, 22, 0)), '2026-07-18');
    });
  });

  group('ViennaTime.parseServerTimeStamp', () {
    test('ohne Offset = Wiener Wanduhrzeit', () {
      expect(ViennaTime.parseServerTimeStamp('2026-07-01T00:05:19'),
          DateTime.utc(2026, 6, 30, 22, 5, 19));
    });

    test('mit Z = bereits UTC (Roundtrip aus toReceiptJson)', () {
      expect(ViennaTime.parseServerTimeStamp('2026-06-30T22:05:19.000Z'),
          DateTime.utc(2026, 6, 30, 22, 5, 19));
    });
  });
}
