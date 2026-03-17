import 'package:sumup/sumup.dart';

import '../models/sumup_checkout_response.dart';

class SumupService {
  static String? _affiliateKey;
  static Future<bool> init(String affiliateKey) async {
    _affiliateKey = affiliateKey;
    SumupPluginResponse initRes = await Sumup.init(affiliateKey);
    if (!initRes.status) {
      return false;
    }
    if (!((await Sumup.isLoggedIn)??false)) {
      SumupPluginResponse loginRes = await Sumup.login();
      return loginRes.status;
    }
    return true;
  }

  static Future<SumupCheckoutResponse> checkout({
    required String title,
    required double total,
    int saleItemsCount = 1,
    double tip = 0.0,
    bool skipSuccessScreen = true,
    bool skipFailureScreen = false,
    bool tipOnCardReader = false,
    String? customerEmail,
    String? customerPhone,
    String? foreignTransactionId,
}) async {

    await Sumup.prepareForCheckout();
    var payment = SumupPayment(
      saleItemsCount: saleItemsCount,
      title: title,
      total: total,
      currency: 'EUR',
      foreignTransactionId: foreignTransactionId,
      tipOnCardReader: tipOnCardReader,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      skipFailureScreen: skipFailureScreen,
      skipSuccessScreen: skipSuccessScreen,
      tip: tip,
    );
    var request = SumupPaymentRequest(payment);
    
    SumupPluginCheckoutResponse response = await Sumup.checkout(request);

    return SumupCheckoutResponse.fromSumup(response);
  }
}