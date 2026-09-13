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
/// ([druckLogoSpeicherLeeren] leert den Speicher).
Future<DruckLogo?> ladeDruckLogo(String? url, LogoStufe stufe, KeckPaperSize papier, {PixelLader? pixel}) {
  if (url == null || url.isEmpty) return Future.value(null);
  final schluessel = '$url|${stufe.kuerzel}|${papier.name}';
  return _speicher.putIfAbsent(schluessel, () async {
    try {
      final p = await (pixel ?? _ausLogoService)(url);
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
  });
}
