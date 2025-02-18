import 'dart:convert';

class RKSVService {
  static const String signatureDeviceDamagedKey = 'Sicherheitseinrichtung ausgefallen';
  static String _base64ToBase64Url(String input) {
    return input.replaceAll('+', '-').replaceAll('/', '_').replaceAll(RegExp(r'=+$'), '');
  }

  static bool isSigSuccess(String sig) {
    return sig.split('.')[2] != _base64ToBase64Url(base64Encode(utf8.encode(signatureDeviceDamagedKey)));
  }
}