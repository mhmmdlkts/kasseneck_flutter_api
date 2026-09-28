/// Firmenlogo fuer den Bondruck: Adresse -> Pixel -> Rasterbild in der Groesse
/// des Blatts (Zwilling von `loadPrintLogo` im Druck-Kit der Browser-Kasse).
/// Ein Logo, das nicht laedt, ist kein Druckfehler: der Bon kommt ohne Logo.
library;

import 'dart:typed_data';

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';

typedef PixelLoader = Future<({int width, int height, Uint8List rgba})> Function(String url);

final Map<String, Future<PrintLogo?>> _speicher = {};

/// Zeitpunkt des letzten Fehlschlags je Schluessel -- siehe [loadPrintLogo]s
/// `negativeCacheTtl`.
final Map<String, DateTime> _negativCache = {};

/// Vorgabe fuer `negativeCacheTtl` in [loadPrintLogo].
///
/// Eine Minute haelt den Regelbetrieb am Tresen frei von wiederholten,
/// wirkungslosen Wartezeiten, ohne eine reparierte Adresse lange zu
/// verstecken -- sie zaehlt ab dem Fehlschlag, nicht ab dem Beleg.
const Duration defaultNegativeCacheTtl = Duration(seconds: 60);

void clearPrintLogoCache() {
  _speicher.clear();
  _negativCache.clear();
}

/// Der Pixel-Deckel ([isLogoPixelSizeAllowed]) prueft erst NACH diesem Decode,
/// nicht vorher am Bildkopf: `decodePng` nutzt Flutters `ui.instantiateImageCodec`
/// und liefert Breite/Hoehe erst mit dem fertigen Frame; ein billigeres
/// Vorab-Lesen der PNG-Kopfdaten (`ui.ImageDescriptor.encoded`) waere ein
/// zweiter, eigener Deckel-Weg nur fuer PNG und haette diesen mit Goldens
/// geprueften, gemeinsamen Decode-Pfad anfassen muessen -- fuer eine Grenze,
/// die den seltenen Fall (zu grosses Logo) abfaengt, nicht den Regelfall.
Future<({int width, int height, Uint8List rgba})> _ausLogoService(String url) async {
  await LogoService.loadLogo(url);
  final bytes = LogoService.getLogoBytes(url);
  if (bytes == null) throw StateError('Logo nicht ladbar');
  final bild = await decodePng(bytes);
  return (width: bild.width, height: bild.height, rgba: bild.rgba);
}

/// Laedt das Logo unter [url] und rastert es in die Groesse, die das Blatt
/// [size] und [paper] geben ([logoDimensions]/[logoRaster]) -- `null` ohne Adresse
/// oder bei jedem Fehler (Netz, Decode, Pixelmass). [pixel] ersetzt den
/// Standardweg ueber [LogoService]/[decodePng] (Tests, andere Quellen).
///
/// Ergebnisse werden je Adresse, Stufe und Papier zwischengespeichert
/// ([clearPrintLogoCache] leert den Speicher). Ein Fehlschlag (`null`)
/// wird nicht dauerhaft gemerkt, aber kurz: [negativeCacheTtl] (Vorgabe eine
/// Minute) sperrt einen erneuten Versuch fuer denselben Schluessel. Ohne
/// diese Sperre kostete eine kaputte Adresse **jeden** Bon erneut bis zu
/// [timeout] am Tresen, ohne je zum Ziel zu kommen -- der Zustand hielt zwar
/// nichts fest, aber der Preis war derselbe wie ohne jeden Speicher. Nach
/// Ablauf der Sperre versucht der naechste Aufruf es wieder, damit eine
/// inzwischen reparierte Adresse nicht laenger als noetig verborgen bleibt.
///
/// [timeout] deckt den **ganzen** Aufruf -- Abruf (Standardweg oder [pixel]),
/// Decode und Raster -- mit einer einzigen Obergrenze, Vorgabe drei Sekunden
/// (Hausregel wie im Druck-Kit der Browser-Kasse: das Logo ist Zierde, ein
/// Druck darf nicht laenger darauf warten). [LogoService.timeout] bleibt daneben
/// bestehen und deckt fuer sich nur den HTTP-Teil in `_ausLogoService` -- das
/// ist keine zweite Frist fuer denselben Zweck, sondern eine eigene: der
/// [LogoService] wird auch direkt genutzt (Bild-Anzeige in der App, ohne
/// Bondruck) und braucht dort seine eigene Grenze. Treffen beide aufeinander
/// (Standardweg, `timeout` hier kleiner oder gleich [LogoService.timeout]),
/// gewinnt die kleinere: [Future.timeout] hier greift, sobald sie ablaeuft,
/// egal wie weit der HTTP-Abruf innerhalb seiner eigenen Frist noch ist.
/// Ein Timeout zaehlt wie jeder andere Fehlschlag fuer [negativeCacheTtl]: der
/// Speichereintrag ist damit schon weg, ein Ergebnis, das erst danach
/// eintrifft, findet keinen eigenen Eintrag mehr vor und schreibt keinen
/// neuen; der naechste Aufruf innerhalb der Negativ-Frist bekommt sofort
/// `null`, ohne selbst zu versuchen.
Future<PrintLogo?> loadPrintLogo(
  String? url,
  SheetLogoSize size,
  KeckPaperSize paper, {
  PixelLoader? pixel,
  Duration timeout = const Duration(seconds: 3),
  Duration negativeCacheTtl = defaultNegativeCacheTtl,
}) {
  if (url == null || url.isEmpty) return Future.value(null);
  final schluessel = '$url|${size.code}|${paper.name}';
  final vorhanden = _speicher[schluessel];
  if (vorhanden != null) return vorhanden;

  final letzterFehlschlag = _negativCache[schluessel];
  if (letzterFehlschlag != null && DateTime.now().difference(letzterFehlschlag) < negativeCacheTtl) {
    return Future.value(null);
  }

  final abruf = _laden(url, size, paper, pixel).timeout(timeout, onTimeout: () => null);
  _speicher[schluessel] = abruf;
  abruf.then((logo) {
    // Nur den eigenen Eintrag entfernen: wurde der Speicher inzwischen
    // geleert oder laeuft schon ein neuerer Abruf, bleibt der stehen. Das
    // greift unveraendert auch nach einem Timeout, denn der Speicher haelt
    // genau dieses (mit `timeout` umhuellte) Future -- ein spaeter fertig
    // werdender roher Ladevorgang schreibt nirgends mehr hinein. Aus
    // demselben Grund merkt sich auch das Negativ-Gedaechtnis nur einen
    // Fehlschlag, der noch der aktuelle Stand ist -- ein laengst durch einen
    // neueren, erfolgreichen Abruf ersetzter Fehlschlag darf keine Sperre
    // fuer diesen setzen.
    if (logo == null && identical(_speicher[schluessel], abruf)) {
      _speicher.remove(schluessel);
      _negativCache[schluessel] = DateTime.now();
    }
  });
  return abruf;
}

Future<PrintLogo?> _laden(String url, SheetLogoSize stufe, KeckPaperSize papier, PixelLoader? pixel) async {
  try {
    final p = await (pixel ?? _ausLogoService)(url);
    if (!isLogoPixelSizeAllowed(p.width, p.height)) {
      // Deckel VOR logoRaster, zusaetzlich zur Frist um den ganzen Aufruf:
      // logoRaster laeuft synchron ueber jedes Pixel, ein Future.timeout kann
      // laufenden synchronen Code nicht unterbrechen (siehe Kommentar bei
      // ladeDruckLogo). Wie jeder andere Ladefehler: `null` statt Wurf --
      // kein Logo statt haengendem Bondruck.
      return null;
    }
    final zeichen = papier.defaultCharCount;
    final mass = logoDimensions(SheetLogo(size: stufe, pixelWidth: p.width, pixelHeight: p.height), zeichen);
    return PrintLogo(
      size: stufe,
      pixelWidth: p.width,
      pixelHeight: p.height,
      raster: logoRaster(p.rgba, p.width, p.height, mass, zeichen),
    );
  } catch (_) {
    return null;
  }
}
