/// Der Vertrag der Rechnungs-API als Listen — Zwilling von
/// `src/rechnung/vertrag.ts` im JS-Paket `@kreiseck/kasseneck-api`.
///
/// `test/rechnung_api_test.dart` vergleicht jede Liste in beide Richtungen mit
/// dem Abschnitt `invoice` in `test/fixtures/vertrag/surface.json` (gezogen
/// von `tool/zwillinge.sh`). Wer hier etwas ändert, ändert zuerst das JS-Paket.
///
/// Die Feldbeschreibung selbst (Grenzen, Pflichtfelder) prüft das Backend; der
/// Client schickt die Anfrage unverändert und wertet `validation` aus.
library;

/// Die Aufrufe der Rechnungs-API, in der Reihenfolge des Vertrags.
const List<String> invoiceCalls = [
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
  'recordInvoicePayment',
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
  'not_payable',
  'payment_exceeds_invoice',
  'tax_scheme_mismatch',
  'vat_rate_not_in_country',
  'reverse_charge_reason_required',
  'reverse_charge_threshold',
  'mixed_supply_not_allowed',
  'oss_not_enabled',
  'einvoice_unavailable',
  'amount_too_large',
  // Seit 10.4: UID-Pruefung beim Ausstellen ohne Steuer (ig. Lieferung, Reverse
  // Charge). `vat_id_invalid` sperrt auch mit `acceptVatIdRisk`;
  // `vat_id_check_pending` traegt `details['retryAfter']` (Sekunden bis zum
  // naechsten sinnvollen Versuch, mit demselben `idempotencyKey`).
  'vat_id_invalid',
  'vat_id_check_pending',
  // Seit 10.4: Position mit `reservationId` (nur `issueInvoice`), geprueft
  // beim Ausstellen. Unbekannt oder fremd; keine offene Position mit gleichem
  // Artikel am Lagerstandort der Rechnung; schon eingeloest oder freigegeben.
  'reservation_not_found',
  'reservation_mismatch',
  'reservation_not_active',
];

/// Fehlercodes, die nicht die Rechnung, sondern die Anfrage betreffen:
/// Anmeldung, Freischaltung, Rand (`dialect_mismatch`,
/// `internal_translation_error`, `response_translation_failed`) und eine
/// fehlende Route. Sie gehören nicht zu [invoiceErrorCodes], darum liefert
/// `invoiceErrorCode` für sie `null`.
const List<String> invoiceRequestErrorCodes = [
  'account_not_found',
  'admin_required',
  'api_not_approved',
  'app_check_invalid',
  'app_check_missing',
  'cashregister_not_assigned',
  'cashregister_not_found',
  'cashregister_token_invalid',
  'cashregister_token_missing',
  'dialect_mismatch',
  'internal_translation_error',
  'live_not_enabled',
  'method_not_allowed',
  'mfa_required',
  'not_found',
  'register_user_no_business',
  'register_user_not_allowed',
  'register_user_not_found',
  'response_translation_failed',
  'session_expired',
  'session_other_cashregister',
  'unauthorized',
  'user_disabled',
  'user_verification_failed',
  'route_missing',
];

/// Gründe einer Gutschrift; der Server druckt den deutschen Text.
const List<String> creditNoteReasons = ['cancellation', 'price_reduction', 'return', 'incorrect_invoice', 'other'];

/// Der Steuerfall einer Rechnung. Er wird vom Server **abgeleitet** (Kundenland,
/// Kundenart, UID, Ware oder Leistung); eine mitgeschickte Angabe muss dazu
/// passen, sonst `tax_scheme_mismatch`. Neue Fälle stehen hinten.
const List<String> taxSchemes = [
  'normal',
  'smallBusiness',
  'reverseCharge',
  'intraCommunitySupply',
  'exportThirdCountry',
  'domesticReverseCharge',
  'oss',
  'outsideScope',
];

/// Steuerfälle, in denen die Rechnung keine Steuer ausweist: jede Position
/// zählt zu 0 %, gleich welcher `vatRate` an ihr steht (`computeInvoiceTotals`).
/// `oss` gehört nicht dazu — dort wird Steuer ausgewiesen, nur nicht
/// österreichische.
const List<String> zeroRatedTaxSchemes = [
  'smallBusiness',
  'reverseCharge',
  'intraCommunitySupply',
  'exportThirdCountry',
  'domesticReverseCharge',
  'outsideScope',
];

/// Ware oder Leistung — ohne das lässt sich ig. Lieferung nicht von Reverse
/// Charge trennen. Ohne Angabe gilt `goods`.
const List<String> itemKinds = ['goods', 'service'];

/// Gründe für den Übergang der Steuerschuld **im Inland** (§ 19 UStG samt
/// Verordnungen). Ohne Grund gibt es kein `domesticReverseCharge`.
const List<String> reverseChargeReasons = [
  'construction',
  'scrap',
  'mobile_devices',
  'it_devices',
  'metals',
  'emission_certificates',
  'gas_electricity',
  'energy_certificates',
  'investment_gold',
  'security_transfer',
  'foreign_supplier',
];

const List<String> priceModes = ['net', 'gross'];

const List<int> vatRates = [0, 10, 13, 20];

const List<String> customerTypes = ['private', 'company'];

const List<String> invoiceListStatus = ['final', 'paid', 'cancelled', 'open', 'overdue'];

/// Rechnung oder Gutschrift (bis 9.x `RE`/`GU`).
const List<String> docTypes = ['invoice', 'credit_note'];

const List<String> einvoiceFormats = ['ubl', 'cii'];

/// Was einer Rechnung zur vollständigen E-Rechnung fehlt (`einvoice.missing`,
/// auch in `details.missing` von `invoice_requirements_missing`).
const List<String> einvoiceMissingCodes = [
  'name',
  'street',
  'zip',
  'city',
  'country',
  'vat_id',
  'order_reference',
  'order_reference_format',
];

/// Warum eine Rechnung abgeschrieben wurde (`writeOffReasonCode`).
const List<String> writeOffReasonCodes = [
  'uncollectible',
  'time_barred',
  'waived',
  'disputed',
  'settled_externally',
  'other',
];

/// Sprachen einer Rechnung. Eine Rechnung hat eine Nummer und eine Sprache,
/// beim Ausstellen eingefroren; Behörden bekommen immer `de`.
const List<String> invoiceLanguages = ['de', 'en'];

/// Wie eine Rechnung bezahlt wurde. `cash` wird gebucht, die Antwort trägt dann
/// zusätzlich den Hinweis `cash_receipt_required`: eine Barzahlung ist ein
/// Barumsatz und braucht einen Beleg (§ 132a BAO).
const List<String> invoicePaymentMethods = ['transfer', 'card', 'online', 'cash'];

/// Hinweise an einer erfolgreichen Antwort — keine Fehler.
///
/// `reservation_expired` (seit 10.4): die Reservierung einer Position war beim
/// Ausstellen schon abgelaufen. Die Rechnung entsteht trotzdem, verkauft wird
/// ohne Reservierung; der Hinweis nennt `reservationId`, je Reservierung einmal.
const List<String> invoiceNoticeCodes = [
  'cash_receipt_required',
  'recapitulative_statement_due',
  'place_of_supply_check',
  'reservation_expired',
];

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
bool isInvoiceErrorCode(String? code) => code != null && invoiceErrorCodes.contains(code);
