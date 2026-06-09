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
export 'src/hobex_hps/enums.dart' show HpsTransactionType, Cvm;
export 'src/hobex_hps/exceptions.dart'
    show HpsException, HpsHttpException, HpsConnectionException;
