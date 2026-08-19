/// Die Belegliste: Zeitraum, Filter, Tagesgruppen — Zwilling von `belege.ts`
/// der Browser-Kasse.
///
/// Reine Funktionen; das Laden macht [RegisterReceiptClient].
///
/// **Gerechnet wird in Wiener Kalendertagen**, nicht in denen des Geräts. Ein
/// Tablet mit falsch gestellter Zeitzone darf den Kassenschluss nicht
/// verschieben — und um halb eins nachts sind „die Belege von heute" die des
/// laufenden Wiener Tages, nicht die des UTC-Vortags.
library;

import '../../enums/keck_payment_method.dart';
import '../../services/vienna_time.dart';
import 'belege.dart';

enum Zeitraum { heute, gestern, siebenTage, dreissigTage }

enum BelegartFilter { alle, verkauf, storno, sonstige }

enum ZahlungFilter { alle, bar, karte }

class Belegfilter {
  const Belegfilter({
    this.zeitraum = Zeitraum.heute,
    this.belegart = BelegartFilter.alle,
    this.zahlung = ZahlungFilter.alle,
    this.wer,
  });

  final Zeitraum zeitraum;
  final BelegartFilter belegart;
  final ZahlungFilter zahlung;

  /// Bediener-Name; `null` heißt alle.
  final String? wer;

  Belegfilter kopie({
    Zeitraum? zeitraum,
    BelegartFilter? belegart,
    ZahlungFilter? zahlung,
    String? wer,
    bool werLoeschen = false,
  }) =>
      Belegfilter(
        zeitraum: zeitraum ?? this.zeitraum,
        belegart: belegart ?? this.belegart,
        zahlung: zahlung ?? this.zahlung,
        wer: werLoeschen ? null : (wer ?? this.wer),
      );
}

String _zwei(int n) => n.toString().padLeft(2, '0');

/// Der Wiener Kalendertag eines Zeitpunkts als `YYYY-MM-DD`.
String wienDatum(DateTime zeitpunkt) {
  final w = ViennaTime.toWallClock(zeitpunkt);
  return '${w.year}-${_zwei(w.month)}-${_zwei(w.day)}';
}

/// `von`/`bis` (Wiener Wanduhr, `YYYY-MM-DD`) für den Zeitraum.
({String von, String bis}) zeitfenster(Zeitraum zeitraum, [DateTime? jetzt]) {
  final zeit = jetzt ?? DateTime.now();
  final heute = wienDatum(zeit);
  DateTime zurueck(int tage) => zeit.subtract(Duration(days: tage));
  return switch (zeitraum) {
    Zeitraum.heute => (von: heute, bis: heute),
    Zeitraum.gestern => (von: wienDatum(zurueck(1)), bis: wienDatum(zurueck(1))),
    // Sieben Tage schließen heute mit ein — also sechs zurück.
    Zeitraum.siebenTage => (von: wienDatum(zurueck(6)), bis: heute),
    Zeitraum.dreissigTage => (von: wienDatum(zurueck(29)), bis: heute),
  };
}

/// Lesbarer Name der Belegart — nie ein Rohwert.
String belegartText(Belegzusammenfassung beleg) {
  if (beleg.istStorno) return 'Storno';
  switch (beleg.belegart) {
    case 'standard':
      return 'Verkauf';
    case 'start':
      return 'Startbeleg';
    case 'training':
      return 'Trainingsbeleg';
    case 'zero':
      return switch (beleg.nullbelegAnlass) {
        'monthly' => 'Monatsbeleg',
        'annual' => 'Jahresbeleg',
        'annual_replacement' => 'Jahresbeleg (Ersatz)',
        'outage_end' => 'Nullbeleg nach Ausfall',
        'final' => 'Schlussbeleg',
        // Auch ein künftiger, hier unbekannter Anlass bleibt ein Nullbeleg.
        _ => 'Nullbeleg (Prüfbeleg)',
      };
    default:
      return 'Beleg';
  }
}

List<Belegzusammenfassung> gefiltert(List<Belegzusammenfassung> belege, Belegfilter f) {
  return [
    for (final b in belege)
      if (_passt(b, f)) b,
  ];
}

bool _passt(Belegzusammenfassung b, Belegfilter f) {
  switch (f.belegart) {
    case BelegartFilter.verkauf:
      if (!b.istVerkauf) return false;
    case BelegartFilter.storno:
      if (!b.istStorno) return false;
    case BelegartFilter.sonstige:
      if (b.istVerkauf || b.istStorno) return false;
    case BelegartFilter.alle:
      break;
  }
  final bar = b.zahlungsart == KeckPaymentMethod.cash;
  if (f.zahlung == ZahlungFilter.bar && !bar) return false;
  if (f.zahlung == ZahlungFilter.karte && bar) return false;
  if (f.wer != null && (b.bediener?.name ?? '') != f.wer) return false;
  return true;
}

/// Bediener-Namen in der Liste, für den Filter — sortiert, ohne Doppelte.
List<String> bediener(List<Belegzusammenfassung> belege) {
  final namen = <String>{
    for (final b in belege)
      if ((b.bediener?.name ?? '').isNotEmpty) b.bediener!.name,
  }.toList();
  namen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return namen;
}

class Tagesgruppe {
  const Tagesgruppe({required this.datum, required this.belege});

  /// Wiener Kalendertag `YYYY-MM-DD`.
  final String datum;
  final List<Belegzusammenfassung> belege;
}

/// Nach Wiener Kalendertag gruppiert, neueste zuerst.
List<Tagesgruppe> tagesgruppen(List<Belegzusammenfassung> belege) {
  final sortiert = [...belege]..sort((a, b) => b.zeitstempel.compareTo(a.zeitstempel));
  final aus = <Tagesgruppe>[];
  for (final b in sortiert) {
    final datum = wienDatum(ViennaTime.parseServerTimeStamp(b.zeitstempel));
    if (aus.isNotEmpty && aus.last.datum == datum) {
      aus.last.belege.add(b);
    } else {
      aus.add(Tagesgruppe(datum: datum, belege: [b]));
    }
  }
  return aus;
}

/// Uhrzeit eines Belegs in Wiener Wanduhrzeit (`HH:MM`).
String uhrzeit(String zeitstempel) {
  final w = ViennaTime.toWallClock(ViennaTime.parseServerTimeStamp(zeitstempel));
  return '${_zwei(w.hour)}:${_zwei(w.minute)}';
}
