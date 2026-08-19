import 'dart:convert';

class RKSVService {
  static const String signatureDeviceDamagedKey = 'Sicherheitseinrichtung ausgefallen';
  static String _base64ToBase64Url(String input) {
    return input.replaceAll('+', '-').replaceAll('/', '_').replaceAll(RegExp(r'=+$'), '');
  }

  /// Trägt die Signatur den RKSV-Ausfallvermerk im dritten JWS-Segment?
  ///
  /// Eine Signatur ohne drei Segmente kommt so nie vom Backend. Kommt sie
  /// doch, ist das **kein Grund, den Belegbildschirm abstürzen zu lassen** —
  /// und „nicht prüfbar" liegt näher an „ausgefallen" als an „in Ordnung".
  static bool isSigSuccess(String sig) {
    final teile = sig.split('.');
    if (teile.length < 3 || teile[2].isEmpty) return false;
    return teile[2] != _base64ToBase64Url(base64Encode(utf8.encode(signatureDeviceDamagedKey)));
  }
}