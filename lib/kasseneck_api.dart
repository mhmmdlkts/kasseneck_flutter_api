import 'dart:convert';
import 'package:http/http.dart' as http;

import 'enums/payment_method.dart';
import 'enums/receipt_type.dart';
import 'models/kasseneck_item.dart';
import 'models/kasseneck_receipt.dart';

/// Hauptklasse für Kasseneck-API-Aufrufe
class KasseneckApi {
  static final String _baseUrl = 'https://europe-west1-kasseneck.cloudfunctions.net';
  static final String downloadBaseUrl = 'https://europe-west1-kasseneck.cloudfunctions.net/downloadReceipt';
  final String apiKey;
  final String cashregisterToken;

  KasseneckApi({
    required this.apiKey,
    required this.cashregisterToken
  });

  Future<KasseneckReceipt?> createReceipt({
    required ReceiptType receiptType,
    PaymentMethod? paymentMethod,
    List<KasseneckItem>? items,
    String? customerDetails,
  }) async {

    if (receiptType.needsItems) {
      if (items == null || items.isEmpty) {
        throw ArgumentError(
          'Items sind Pflicht bei receiptType "$receiptType" und dürfen nicht leer sein.',
        );
      }

      if (items.any((item) => !item.isValid)) {
        throw ArgumentError('Ungültige Items übergeben.');
      }
    }

    final Map<String, dynamic> params = {
      'receiptType': receiptType.name,
    };

    if (items != null && items.isNotEmpty) {
      params['items'] = items.map((e) => e.toJson()).toList();
    }
    if (paymentMethod != null) {
      params['paymentMethod'] = paymentMethod.name;
    }
    if (customerDetails != null) {
      params['customerDetails'] = customerDetails;
    }

    final uri = Uri.parse('$_baseUrl/createReceipt');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'cashregister-token': cashregisterToken,
      'Content-Type': 'application/json',
    };

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'params': params,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> resJson = json.decode(response.body);

      if (resJson['status'] == 'success') {
        return KasseneckReceipt.fromJson(resJson['data'] as Map<String, dynamic>);
      } else {
        final msg = resJson['message'] ?? 'Unbekannter Fehler';
        throw Exception('createReceipt fehlgeschlagen: $msg');
      }
    } else {
      throw Exception(
        'Server-Fehler beim Anlegen des Belegs: ${response.statusCode} - ${response.body}',
      );
    }
  }
}