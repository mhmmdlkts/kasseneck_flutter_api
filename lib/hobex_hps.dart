/// **hobex Payment Service (HPS)** — typed client for the terminal's local REST
/// API (`http://127.0.0.1:8080` when the app runs on the terminal).
///
/// Bewusst getrennt vom alten, cloud-basierten Hobex (`KasseneckApi.hobexPay` /
/// `hobexRefund`, die ueber Kasseneck-Cloud-Endpunkte gehen). Eigener Import,
/// damit alt und neu sauber nebeneinander leben:
///
/// ```dart
/// import 'package:kasseneck_api/hobex_hps.dart';
///
/// final hps = HpsClient(tid: '3600335');
/// final res = await hps.payment(amount: 1.00);
/// ```
library;

export 'src/hobex_hps/hps_client.dart' show HpsClient;
export 'src/hobex_hps/transaction_response.dart' show TransactionResponse;
export 'src/hobex_hps/diagnosis.dart' show Diagnosis;
export 'src/hobex_hps/terminal_info.dart' show TerminalInfo;
export 'src/hobex_hps/enums.dart' show HpsTransactionType, Cvm;
export 'src/hobex_hps/exceptions.dart'
    show HpsException, HpsHttpException, HpsConnectionException;
export 'src/hobex_hps/observer.dart' show HpsEvent, HpsEventKind, HpsObserver;
export 'src/hobex_hps/hps_result.dart' show HpsResult;
export 'src/hobex_hps/hps_payments.dart' show HpsPayments;
// CardPaymentOutcome ist zwischen HPS und der Hobex-Cloud geteilt und liegt
// deshalb nicht im HPS-Baum -- siehe src/payments/card_payment_outcome.dart.
export 'src/payments/card_payment_outcome.dart' show CardPaymentOutcome;
export 'models/hobex_receipt.dart' show HobexReceipt;
