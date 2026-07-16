/// Geschäftszeitzone Europe/Vienna für RKSV-Belege und Tagesabschlüsse.
///
/// Der Kasseneck-Server liefert und erwartet Zeitstempel in österreichischer
/// Wanduhrzeit ohne Offset. Damit App-Anzeige, Tagesgruppierung und Abfragen
/// unabhängig von der Geräte-Zeitzone (z. B. im Ausland) mit dem
/// Kasseneck-Bericht übereinstimmen, rechnet alles über diese Klasse.
///
/// Konventionen:
/// - "Instant" = echter Zeitpunkt (beliebige DateTime, wird über UTC gerechnet).
/// - "Wanduhrzeit" = naives DateTime, dessen Felder Wiener Ortszeit bedeuten.
///   Nur Felder verwenden (Anzeige, Tages-Schlüssel) — kein toUtc()/toLocal().
class ViennaTime {
  ViennaTime._();

  /// UTC-Offset Wiens zum gegebenen Zeitpunkt (CET +1 / CEST +2).
  static Duration offsetAt(DateTime instant) => _isSummerTime(instant.toUtc())
      ? const Duration(hours: 2)
      : const Duration(hours: 1);

  /// Zeitpunkt → Wiener Wanduhrzeit (naives DateTime).
  static DateTime toWallClock(DateTime instant) {
    final utc = instant.toUtc();
    final shifted = utc.add(offsetAt(utc));
    return DateTime(shifted.year, shifted.month, shifted.day, shifted.hour,
        shifted.minute, shifted.second, shifted.millisecond, shifted.microsecond);
  }

  /// Wiener Wanduhrzeit (naives DateTime) → echter Zeitpunkt (UTC).
  static DateTime fromWallClock(DateTime wall) {
    final base = DateTime.utc(wall.year, wall.month, wall.day, wall.hour,
        wall.minute, wall.second, wall.millisecond, wall.microsecond);
    // Erst Sommerzeit annehmen; stimmt die Annahme für den resultierenden
    // Zeitpunkt, war sie richtig — sonst gilt Winterzeit.
    final summer = base.subtract(const Duration(hours: 2));
    if (_isSummerTime(summer)) return summer;
    return base.subtract(const Duration(hours: 1));
  }

  /// Server-Zeitstempel parsen: ohne Offset = Wiener Wanduhrzeit, mit
  /// Offset/'Z' = echter Zeitpunkt. Ergebnis ist immer ein Instant (UTC).
  static DateTime parseServerTimeStamp(String raw) {
    final parsed = DateTime.parse(raw);
    return parsed.isUtc ? parsed : fromWallClock(parsed);
  }

  /// Aktuelle Wiener Wanduhrzeit.
  static DateTime now() => toWallClock(DateTime.now());

  /// Heutiges Wiener Kalenderdatum (Mitternacht, naiv).
  static DateTime today() {
    final wall = now();
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Tages-Schlüssel (yyyy-MM-dd) eines Zeitpunkts nach Wiener Zeit.
  static String dayKey(DateTime instant) =>
      toWallClock(instant).toIso8601String().split('T').first;

  /// true, wenn die Geräte-Zeitzone gerade von der Wiener Zeit abweicht.
  static bool get deviceDiffersFromVienna =>
      DateTime.now().timeZoneOffset != offsetAt(DateTime.now());

  /// EU-Sommerzeit: letzter Sonntag im März 01:00 UTC bis letzter Sonntag
  /// im Oktober 01:00 UTC.
  static bool _isSummerTime(DateTime utc) {
    final start = _lastSundayUtc(utc.year, DateTime.march);
    final end = _lastSundayUtc(utc.year, DateTime.october);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  /// Letzter Sonntag des Monats, 01:00 UTC (EU-Umstellungszeitpunkt).
  static DateTime _lastSundayUtc(int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0);
    return DateTime.utc(year, month, lastDay.day - (lastDay.weekday % 7), 1);
  }
}
