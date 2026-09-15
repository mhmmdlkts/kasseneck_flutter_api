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
  static const cancelInvoice = 'cancelInvoice';
  static const cancelReceipt = 'cancelReceipt';
  static const createCreditNote = 'createCreditNote';
  static const createCustomer = 'createCustomer';
  static const createPaymentLinkStripe = 'createPaymentLinkStripe';
  static const createReceipt = 'createReceipt';
  static const downloadDailyReport = 'downloadDailyReport';
  static const downloadReport = 'downloadReport';
  static const endRegisterSession = 'endRegisterSession';
  static const financeWebService = 'financeWebService';
  static const getCustomer = 'getCustomer';
  static const getFirstReceiptDate = 'getFirstReceiptDate';
  static const getInvoice = 'getInvoice';
  static const getInvoicePdf = 'getInvoicePdf';
  static const getInvoiceSetupStatus = 'getInvoiceSetupStatus';
  static const getInvoiceXml = 'getInvoiceXml';
  static const getKasseSettings = 'getKasseSettings';
  static const getReceipt = 'getReceipt';
  static const getReportV2 = 'getReportV2';
  static const hobexGetStatus = 'hobexGetStatus';
  static const hobexPayApi = 'hobexPayApi';
  static const hobexRefundApi = 'hobexRefundApi';
  static const issueInvoice = 'issueInvoice';
  static const listInvoices = 'listInvoices';
  static const listMyArticleGroups = 'listMyArticleGroups';
  static const listMyArticles = 'listMyArticles';
  static const listMyReceipts = 'listMyReceipts';
  static const listMyTipRecipients = 'listMyTipRecipients';
  static const listRegisterSessionsForDevice = 'listRegisterSessionsForDevice';
  static const listRegisterUsersForDevice = 'listRegisterUsersForDevice';
  static const pairRegisterDevice = 'pairRegisterDevice';
  static const registerPinLogin = 'registerPinLogin';
  static const registerUserLogin = 'registerUserLogin';
  static const renewRegisterSession = 'renewRegisterSession';
  static const searchCustomers = 'searchCustomers';
  static const sendReceiptEmail = 'sendReceiptEmail';
  static const setMyKasseSettings = 'setMyKasseSettings';
  static const setMyRegisterDeviceSettings = 'setMyRegisterDeviceSettings';
  static const stripeCaptureIntent = 'stripeCaptureIntent';
  static const unpairRegisterDevice = 'unpairRegisterDevice';
  static const updateCustomer = 'updateCustomer';

  /// Alle Namen, die dieses Paket kennt.
  static const Set<String> alle = {
    cancelInvoice,
    cancelReceipt,
    createCreditNote,
    createCustomer,
    createPaymentLinkStripe,
    createReceipt,
    downloadDailyReport,
    downloadReport,
    endRegisterSession,
    financeWebService,
    getCustomer,
    getFirstReceiptDate,
    getInvoice,
    getInvoicePdf,
    getInvoiceSetupStatus,
    getInvoiceXml,
    getKasseSettings,
    getReceipt,
    getReportV2,
    hobexGetStatus,
    hobexPayApi,
    hobexRefundApi,
    issueInvoice,
    listInvoices,
    listMyArticleGroups,
    listMyArticles,
    listMyReceipts,
    listMyTipRecipients,
    listRegisterSessionsForDevice,
    listRegisterUsersForDevice,
    pairRegisterDevice,
    registerPinLogin,
    registerUserLogin,
    renewRegisterSession,
    searchCustomers,
    sendReceiptEmail,
    setMyKasseSettings,
    setMyRegisterDeviceSettings,
    stripeCaptureIntent,
    unpairRegisterDevice,
    updateCustomer,
  };
}
