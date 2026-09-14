/// Firmenlogo fuer den Bondruck: Adresse -> Pixel -> Rasterbild in der Groesse
/// des Blatts (Zwilling von `ladeDruckLogo` im Druck-Kit der Browser-Kasse).
/// Ein Logo, das nicht laedt, ist kein Druckfehler: der Bon kommt ohne Logo.
library;

import 'dart:typed_data';

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';

typedef PixelLader = Future<({int breite, int hoehe, Uint8List rgba})> Function(String url);

final Map<String, Future<DruckLogo?>> _speicher = {};

void druckLogoSpeicherLeeren() => _speicher.clear();

/// Der Pixel-Deckel ([logoPixelZulaessig]) prueft erst NACH diesem Decode,
/// nicht vorher am Bildkopf: `decodePng` nutzt Flutters `ui.instantiateImageCodec`
/// und liefert Breite/Hoehe erst mit dem fertigen Frame; ein billigeres
/// Vorab-Lesen der PNG-Kopfdaten (`ui.ImageDescriptor.encoded`) waere ein
/// zweiter, eigener Deckel-Weg nur fuer PNG und haette diesen mit Goldens
/// geprueften, gemeinsamen Decode-Pfad anfassen muessen -- fuer eine Grenze,
/// die den seltenen Fall (zu grosses Logo) abfaengt, nicht den Regelfall.
Future<({int breite, int hoehe, Uint8List rgba})> _ausLogoService(String url) async {
  await LogoService.loadLogo(url);
  final bytes = LogoService.getLogoBytes(url);
  if (bytes == null) throw StateError('Logo nicht ladbar');
  final bild = await decodePng(bytes);
  return (breite: bild.width, hoehe: bild.height, rgba: bild.rgba);
}

/// Laedt das Logo unter [url] und rastert es in die Groesse, die das Blatt
/// [stufe] und [papier] geben ([logoMass]/[logoRaster]) -- `null` ohne Adresse
/// oder bei jedem Fehler (Netz, Decode, Pixelmass). [pixel] ersetzt den
/// Standardweg ueber [LogoService]/[decodePng] (Tests, andere Quellen).
///
/// Ergebnisse werden je Adresse, Stufe und Papier zwischengespeichert
/// ([druckLogoSpeicherLeeren] leert den Speicher). Ein Fehlschlag (`null`)
/// wird **nicht** gemerkt: ein kurzer Netzausfall soll das Logo nicht bis zum
/// Neustart verstecken. Der Preis: solange das Logo unerreichbar bleibt,
/// versucht es jeder Druck erneut.
///
/// [frist] deckt den **ganzen** Aufruf -- Abruf (Standardweg oder [pixel]),
/// Decode und Raster -- mit einer einzigen Obergrenze, Vorgabe drei Sekunden
/// (Hausregel wie im Druck-Kit der Browser-Kasse: das Logo ist Zierde, ein
/// Druck darf nicht laenger darauf warten). [LogoService.frist] bleibt daneben
/// bestehen und deckt fuer sich nur den HTTP-Teil in `_ausLogoService` -- das
/// ist keine zweite Frist fuer denselben Zweck, sondern eine eigene: der
/// [LogoService] wird auch direkt genutzt (Bild-Anzeige in der App, ohne
/// Bondruck) und braucht dort seine eigene Grenze. Treffen beide aufeinander
/// (Standardweg, `frist` hier kleiner oder gleich [LogoService.frist]),
/// gewinnt die kleinere: [Future.timeout] hier greift, sobald sie ablaeuft,
/// egal wie weit der HTTP-Abruf innerhalb seiner eigenen Frist noch ist.
/// Ein Timeout wird -- wie jeder Fehlschlag -- **nicht** gemerkt: der
/// Speichereintrag ist damit schon weg, ein Ergebnis, das erst danach
/// eintrifft, findet keinen eigenen Eintrag mehr vor und schreibt keinen
/// neuen; der naechste Aufruf laedt einfach neu.
Future<DruckLogo?> ladeDruckLogo(
  String? url,
  LogoStufe stufe,
  KeckPaperSize papier, {
  PixelLader? pixel,
  Duration frist = const Duration(seconds: 3),
}) {
  if (url == null || url.isEmpty) return Future.value(null);
  final schluessel = '$url|${stufe.kuerzel}|${papier.name}';
  final vorhanden = _speicher[schluessel];
  if (vorhanden != null) return vorhanden;
  final abruf = _laden(url, stufe, papier, pixel).timeout(frist, onTimeout: () => null);
  _speicher[schluessel] = abruf;
  abruf.then((logo) {
    // Nur den eigenen Eintrag entfernen: wurde der Speicher inzwischen
    // geleert oder laeuft schon ein neuerer Abruf, bleibt der stehen. Das
    // greift unveraendert auch nach einem Timeout, denn der Speicher haelt
    // genau dieses (mit `timeout` umhuellte) Future -- ein spaeter fertig
    // werdender roher Ladevorgang schreibt nirgends mehr hinein.
    if (logo == null && identical(_speicher[schluessel], abruf)) {
      _speicher.remove(schluessel);
    }
  });
  return abruf;
}

Future<DruckLogo?> _laden(String url, LogoStufe stufe, KeckPaperSize papier, PixelLader? pixel) async {
  try {
    final p = await (pixel ?? _ausLogoService)(url);
    if (!logoPixelZulaessig(p.breite, p.hoehe)) {
      // Deckel VOR logoRaster, zusaetzlich zur Frist um den ganzen Aufruf:
      // logoRaster laeuft synchron ueber jedes Pixel, ein Future.timeout kann
      // laufenden synchronen Code nicht unterbrechen (siehe Kommentar bei
      // ladeDruckLogo). Wie jeder andere Ladefehler: `null` statt Wurf --
      // kein Logo statt haengendem Bondruck.
      return null;
    }
    final zeichen = papier.defaultCharCount;
    final mass = logoMass(BlattLogo(stufe: stufe, pxBreite: p.breite, pxHoehe: p.hoehe), zeichen);
    return DruckLogo(
      stufe: stufe,
      pxBreite: p.breite,
      pxHoehe: p.hoehe,
      raster: logoRaster(p.rgba, p.breite, p.hoehe, mass, zeichen),
    );
  } catch (_) {
    return null;
  }
}
