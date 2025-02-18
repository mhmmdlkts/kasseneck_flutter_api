import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LogoService {
  static final Map<String, Uint8List> _logoBytes = {};

  /// Lädt das Bild nur einmal und speichert es
  static Future<void> loadLogo(String? imageUrl) async {
    if (imageUrl == null) {
      return;
    }
    if (_logoBytes.containsKey(imageUrl)) {
      return;
    }

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        _logoBytes[imageUrl] = response.bodyBytes;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Fehler beim Laden des Bildes: $e');
      }
    }
  }

  /// Gibt das Bild als `Uint8List` für den Belegdruck zurück
  static Uint8List? getLogoBytes(String? imageUrl) => imageUrl==null?null:_logoBytes[imageUrl];
}