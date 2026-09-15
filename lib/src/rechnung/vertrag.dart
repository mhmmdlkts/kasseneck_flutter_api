/// Der Vertrag der Rechnungs-API als Listen — Zwilling von
/// `src/rechnung/vertrag.ts` im JS-Paket `@kreiseck/kasseneck-api`.
///
/// `test/rechnung_api_test.dart` vergleicht jede Liste in beide Richtungen mit
/// dem Abschnitt `rechnung` in `test/fixtures/vertrag/oberflaeche.json` (gezogen
/// von `tool/zwillinge.sh`). Wer hier etwas ändert, ändert zuerst das JS-Paket.
///
/// Die Feldbeschreibung selbst (Grenzen, Pflichtfelder) prüft das Backend; der
/// Client schickt die Anfrage unverändert und wertet `validation` aus.
library;

/// Die Aufrufe der Rechnungs-API, in der Reihenfolge des Vertrags.
const List<String> rechnungAufrufe = [
  'createCustomer',
  'getCustomer',
  'updateCustomer',
  'searchCustomers',
  'issueInvoice',
  'cancelInvoice',
  'createCreditNote',
  'getInvoice',
  'listInvoices',
  'getInvoicePdf',
  'getInvoiceXml',
  'getInvoiceSetupStatus',
  'listBrands',
];

/// Stabile Fehlercodes — am Code entscheiden, nie am Text.
const List<String> invoiceErrorCodes = [
  'validation',
  'idempotency_conflict',
  'module_inactive',
  'customer_not_found',
  'customer_exists',
  'short_code_taken',
  'short_code_immutable',
  'recipient_required',
  'invoice_requirements_missing',
  'invoice_not_found',
  'invoice_ambiguous',
  'not_cancellable',
  'partial_credit_exists',
  'credit_exceeds_invoice',
  'einvoice_incomplete',
  'invoice_api_not_enabled',
  'invoice_setup_incomplete',
  'language_not_allowed',
  'brand_not_found',
];

/// Gründe einer Gutschrift; der Server druckt den deutschen Text.
const List<String> creditNoteReasons = ['cancellation', 'price_reduction', 'return', 'incorrect_invoice', 'other'];

const List<String> taxSchemes = ['normal', 'smallBusiness', 'reverseCharge', 'igLieferung', 'exportThirdCountry'];

const List<String> priceModes = ['net', 'gross'];

const List<int> vatRates = [0, 10, 13, 20];

const List<String> customerTypes = ['private', 'company'];

const List<String> invoiceListStatus = ['final', 'paid', 'cancelled', 'open', 'overdue'];

const List<String> docTypes = ['RE', 'GU'];

const List<String> einvoiceFormats = ['ubl', 'cii'];

/// Sprachen einer Rechnung. Eine Rechnung hat eine Nummer und eine Sprache,
/// beim Ausstellen eingefroren; Behörden bekommen immer `de`.
const List<String> invoiceLanguages = ['de', 'en'];

/// Einheiten einer Position. Der Aufdruck folgt der Sprache der Rechnung
/// (Stk / pcs), in der E-Rechnung steht der Code aus UN/ECE Rec 20/21.
const List<String> invoiceUnits = [
  'piece', 'pair', 'set', 'dozen', 'second', 'minute', 'hour', 'day', 'night', 'week', 'month',
  'quarter', 'half_year', 'year', 'milligram', 'gram', 'kilogram', 'tonne', 'millimetre',
  'centimetre', 'metre', 'running_metre', 'kilometre', 'square_metre', 'hectare', 'millilitre',
  'litre', 'cubic_metre', 'kilowatt_hour', 'megawatt_hour', 'gigabyte', 'terabyte',
  'flat_rate', 'person', 'licence', 'user', 'device', 'session', 'trip', 'page', 'sheet',
  'package', 'box', 'carton', 'bottle', 'can', 'roll', 'bag', 'pallet',
];

/// Was vor dem Ausstellen erfüllt sein muss — in dieser Reihenfolge meldet
/// `getInvoiceSetupStatus` die Lücken.
const List<String> invoiceSetupRequirements = [
  'module_active',
  'api_enabled',
  'live_enabled',
  'business_name',
  'address',
  'vat_id',
  'bank_account',
  'number_format',
];

/// Gehört [code] zum Katalog der Rechnungs-API?
bool istRechnungFehlercode(String? code) => code != null && invoiceErrorCodes.contains(code);
