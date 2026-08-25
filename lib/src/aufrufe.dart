/// Die Namen der Backend-Functions, die dieses Paket aufruft — an einer Stelle
/// statt als Zeichenketten über die Aufrufstellen verstreut.
///
/// Der Zwilling `@kreiseck/kasseneck-api` führt dieselbe Liste und gibt sie im
/// Vertrag (`fixtures/oberflaeche.json`) aus; `test/zwillinge_test.dart`
/// vergleicht beide. So fällt auf, wenn das JS-Paket einen Aufruf kennt, den
/// dieses hier nicht hat — ein reiner Wertevergleich würde das nie finden.
///
/// Deshalb steht hier **nur**, was dieses Paket wirklich absetzt. Ein Name
/// ohne Aufrufstelle täuschte dem Vergleich eine Deckung vor, die es nicht
/// gibt — und verdeckte genau die Lücke, die er finden soll.
library;

abstract final class Aufrufe {
  static const cancelReceipt = 'cancelReceipt';
  static const createPaymentLinkStripe = 'createPaymentLinkStripe';
  static const createReceipt = 'createReceipt';
  static const downloadDailyReport = 'downloadDailyReport';
  static const downloadReport = 'downloadReport';
  static const endRegisterSession = 'endRegisterSession';
  static const financeWebService = 'financeWebService';
  static const getFirstReceiptDate = 'getFirstReceiptDate';
  static const getKasseSettings = 'getKasseSettings';
  static const getReceipt = 'getReceipt';
  static const getReportV2 = 'getReportV2';
  static const hobexPayApi = 'hobexPayApi';
  static const hobexRefundApi = 'hobexRefundApi';
  static const listMyArticleGroups = 'listMyArticleGroups';
  static const listMyArticles = 'listMyArticles';
  static const listMyReceipts = 'listMyReceipts';
  static const listMyTipRecipients = 'listMyTipRecipients';
  static const listRegisterUsersForDevice = 'listRegisterUsersForDevice';
  static const pairRegisterDevice = 'pairRegisterDevice';
  static const registerPinLogin = 'registerPinLogin';
  static const registerUserLogin = 'registerUserLogin';
  static const renewRegisterSession = 'renewRegisterSession';
  static const setMyKasseSettings = 'setMyKasseSettings';
  static const setMyRegisterDeviceSettings = 'setMyRegisterDeviceSettings';
  static const stripeCaptureIntent = 'stripeCaptureIntent';
  static const unpairRegisterDevice = 'unpairRegisterDevice';

  /// Alle Namen, die dieses Paket kennt.
  static const Set<String> alle = {
    cancelReceipt,
    createPaymentLinkStripe,
    createReceipt,
    downloadDailyReport,
    downloadReport,
    endRegisterSession,
    financeWebService,
    getFirstReceiptDate,
    getKasseSettings,
    getReceipt,
    getReportV2,
    hobexPayApi,
    hobexRefundApi,
    listMyArticleGroups,
    listMyArticles,
    listMyReceipts,
    listMyTipRecipients,
    listRegisterUsersForDevice,
    pairRegisterDevice,
    registerPinLogin,
    registerUserLogin,
    renewRegisterSession,
    setMyKasseSettings,
    setMyRegisterDeviceSettings,
    stripeCaptureIntent,
    unpairRegisterDevice,
  };
}
