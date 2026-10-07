<p align="center">
  <img src="https://raw.githubusercontent.com/mhmmdlkts/kasseneck_flutter_api/main/doc/kasseneck.gif" alt="Kasseneck, an RKSV fiscal cash register from Austria" width="420">
</p>

<h1 align="center">kasseneck_api</h1>

<p align="center">
  <b>Austrian fiscal cash register (RKSV) for Flutter: signed receipts, card payments, receipt printing.</b>
</p>

<p align="center">
  <a href="https://pub.dev/packages/kasseneck_api"><img src="https://img.shields.io/pub/v/kasseneck_api?color=136B6B&label=pub" alt="pub"></a>
  <a href="https://pub.dev/packages/kasseneck_api/score"><img src="https://img.shields.io/pub/points/kasseneck_api?color=136B6B" alt="pub points"></a>
  <img src="https://img.shields.io/badge/RKSV-%C2%A7%20131b%20BAO-136B6B" alt="RKSV">
  <img src="https://img.shields.io/badge/License-MIT-136B6B" alt="MIT">
  <a href="https://kasseneck.at"><img src="https://img.shields.io/badge/Kasseneck-kasseneck.at-132A2A" alt="kasseneck.at"></a>
  <a href="https://kreiseck.com"><img src="https://img.shields.io/badge/by-Kreiseck-132A2A" alt="Kreiseck Software Solutions"></a>
</p>

<p align="center">
  <a href="https://github.com/mhmmdlkts/kasseneck_flutter_api/blob/main/README.de.md">Deutsche Kurzfassung</a>
</p>

**kasseneck_api** is the Flutter client for **Kasseneck**, a fiscal cash register
(*Registrierkasse*) for Austria that follows the RKSV, the Austrian cash register
security regulation. Your Flutter app sells, cancels and prints receipts; the
Kasseneck backend does the receipt signing, chains every receipt into the data
capture log (DEP) and reports to FinanzOnline. The package also covers card
payments (hobex terminal and cloud, Stripe payment links), ESC/POS receipt
printers and invoices.

It is the twin of the JavaScript package
[`@kreiseck/kasseneck-api`](https://www.npmjs.com/package/@kreiseck/kasseneck-api):
both share endpoint names, enum values, error codes and golden receipts, and the
test suite checks them against each other. The partner API of the JavaScript
package is server-to-server only and deliberately not part of this package.

**Version 10 speaks the English API `/v3` and nothing else**, and its own
surface is English too: class, field, parameter and enum names, error codes,
library paths. Upgrading from 9.x is one breaking step; see
[Upgrading from 9.x](#upgrading-from-9x).

## Contents

- [Quick start](#quick-start)
- [Upgrading from 9.x](#upgrading-from-9x)
- [Libraries](#libraries)
- [What a fiscal cash register in Austria has to do](#what-a-fiscal-cash-register-in-austria-has-to-do)
- [Features](#features)
- [Requirements and platforms](#requirements-and-platforms)
- [Three ways to authenticate](#three-ways-to-authenticate)
- [The /v3 wire: marker, fail closed, unknown outcome](#the-v3-wire-marker-fail-closed-unknown-outcome)
- [Selling: items, amounts, vouchers, tips](#selling-items-amounts-vouchers-tips)
- [Cancellations (Storno)](#cancellations-storno)
- [Stock at the register](#stock-at-the-register)
- [Sending a receipt by email](#sending-a-receipt-by-email)
- [Register settings](#register-settings)
- [Error handling](#error-handling)
- [Card payments](#card-payments)
- [Printing and displaying receipts](#printing-and-displaying-receipts)
- [Reports, receipt history, FinanzOnline status](#reports-receipt-history-finanzonline-status)
- [Invoices (invoice API)](#invoices-invoice-api)
- [Inventory API](#inventory-api)
- [RKSV details](#rksv-details)
- [Glossary](#glossary)

## Quick start

```yaml
dependencies:
  kasseneck_api: ^10.5.0
```

```bash
flutter pub get
```

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/models/keck_payment.dart';

final kasseneck = KasseneckApi(
  apiKey: 'YOUR_API_KEY',                  // kr_live_… or kr_test_…
  cashregisterToken: 'YOUR_CASHBOX_TOKEN', // cb_live_… or cb_test_…
);

// A cash sale with two items. Prices are integer cents (320 = EUR 3.20).
final items = [
  KasseneckItem(name: 'Coffee', quantity: 2, vat: VatRate.vat20, priceCents: 320),
  KasseneckItem(name: 'Bread',  quantity: 1, vat: VatRate.vat4_9, priceCents: 240),
  // If you only have euro doubles: KasseneckItem.euro(..., singlePrice: 3.20)
];

// payments is mandatory and must add up to the amount due (here 880).
final receipt = await kasseneck.sellReceipt(
  items: items,
  payments: [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 880, tenderedCents: 1000)],
  customerDetails: ['Max Mustermann'],
);

print('Receipt ${receipt?.receiptId}, signed: ${receipt?.signatureSuccess}');
```

`sellReceipt` returns a signed receipt (*Beleg*) that is already chained into the
DEP. Models and enums live in their own files; import the ones you need
(`models/…`, `enums/…`). A runnable example is in
[`example/example.dart`](example/example.dart).

You need a Kasseneck **API key** and a **cashbox token**. Ask for them via
[kasseneck.at/kontakt](https://kasseneck.at/kontakt).

## Upgrading from 9.x

10.0 is a breaking release. The [CHANGELOG](CHANGELOG.md) lists every change
under "Migrating from 9.x"; [`doc/migration-10.md`](doc/migration-10.md) has
the complete table of renamed names (old name, new name, file). The short
version:

- **Wire:** only `/v3`. Receipts, reports and card calls go to
  `https://api.kasseneck.at/v3` (`kPublicBaseUrl`), the register path to
  `https://kasse.kasseneck.at/api/v3` (`kPosBaseUrl`). A custom `baseUrl`
  must end in `/v3`, otherwise the client throws when it is created.
- **Names:** every public German name is English now (`stornieren` is
  `cancelReceipt`, `KasseSettings` is `PosSettings`, `lib/kasse.dart` is
  `lib/pos.dart`, `lib/rechnung.dart` is `lib/invoice.dart`, ...). The
  compiler finds each of them; the table maps them.
- **Payments:** `sellReceipt(payments:)` and `RegisterReceiptClient.sell(payments:)`
  are mandatory; `paymentMethod`, `creditCardProvider`, `cardPaymentId` and
  `cardPaymentData` are gone. See [Selling](#selling-items-amounts-vouchers-tips).
- **Errors:** everything the backend or the transport reports arrives as a
  typed `KasseneckApiError` or `KasseneckHttpError` with an `outcome`, never as
  a plain `Exception`, `TimeoutException` or `ClientException`. See
  [Error handling](#error-handling).
- **Stored receipts:** a `KasseneckReceipt.toJson()` you stored with 9.x
  uses German keys; `KasseneckReceipt.fromJson` reads only the `/v3` form.
  Run such a map through `migrateStoredReceiptJson` first:

  ```dart
  import 'package:kasseneck_api/models/kasseneck_receipt.dart';

  final receipt = KasseneckReceipt.fromJson(migrateStoredReceiptJson(storedMap));
  ```

  Register settings and articles cached by 9.x are read as they are
  (`PosSettings.fromJson`, `PosArticle.fromJson`); they are written back in
  the `/v3` form.

**The 8.x and 9.x lines are frozen.** They keep talking to the old routes and
get fixes only, from the branches
[`release/8.x`](https://github.com/mhmmdlkts/kasseneck_flutter_api/tree/release/8.x)
and [`release/9.x`](https://github.com/mhmmdlkts/kasseneck_flutter_api/tree/release/9.x).
Pin `^9.1.0` (or `^8.0.0`) if you are not ready to move; nothing forces an
upgrade while the old routes are served.

## Libraries

| Import | What it holds |
| --- | --- |
| `package:kasseneck_api/kasseneck_api.dart` | `KasseneckApi` (API key path), error types, `receiptDueCents`, `receiptLayoutFromResult`, `migrateStoredReceiptJson`, code catalogues, hobex Cloud, receipt widgets |
| `package:kasseneck_api/register.dart` | `RegisterClient` (pairing, sign-in, sessions), `RegisterTransport`, `registerErrorCodes`, error types |
| `package:kasseneck_api/pos.dart` | the register (`RegisterReceiptClient`, `PosSettingsClient`, `PosPrinterClient`, articles, cart, tiles, themes, `posErrorCodes`) |
| `package:kasseneck_api/invoice.dart` | `InvoiceApi`, invoice models and `computeInvoiceTotals`, error types |
| `package:kasseneck_api/inventory.dart` | `InventoryClient` (articles, locations, stock, stock ledger, account webhooks; create and update articles, book stock, reservations), `verifyInventoryWebhookSignature`, `parseInventoryWebhookEvent`, error types. **Belongs on a server.** |
| `package:kasseneck_api/printing.dart` | `KeckPrinter`, `KeckPrinterService`, ESC/POS builder |
| `package:kasseneck_api/hobex_hps.dart` | `HpsClient`, `HpsPayments`, terminal discovery |
| `package:kasseneck_api/models/…`, `enums/…`, `services/…`, `widgets/…` | single models, enums and services, one file each |

## What a fiscal cash register in Austria has to do

The obligation to use a fiscal cash register and the obligation to issue receipts
(*Belegerteilungspflicht*) are laid down in § 131b of the Austrian Federal Fiscal
Code (BAO). The technical requirements for the security device are in the cash
register security regulation (*Registrierkassensicherheitsverordnung*, RKSV).
The table shows which of the resulting tasks **this software** handles and which
stay with the business. The linked pages are in German.

| Task | Where it is handled |
| --- | --- |
| [Signature creation unit (*Signaturerstellungseinheit*)](https://kasseneck.at/wissen/signaturerstellungseinheit): every receipt is signed | Kasseneck, nothing to install |
| [Chaining and data capture log (DEP)](https://kasseneck.at/wissen/dep): every receipt carries its predecessor, the log can be exported | Kasseneck backend |
| [Start receipt, monthly receipt, annual receipt (*Startbeleg, Monatsbeleg, Jahresbeleg*)](https://kasseneck.at/wissen/startbeleg-monatsbeleg-jahresbeleg) | Kasseneck, automatically |
| [Reports to FinanzOnline](https://kasseneck.at/wissen/finanzonline): registration, failure, decommissioning (*Außerbetriebnahme*) | Kasseneck backend |
| [Obligation to issue receipts (*Belegerteilungspflicht*)](https://kasseneck.at/wissen/belegerteilungspflicht): every customer gets a receipt | **this package**: printed receipt, screen, or a link by email |
| [Signature unit failure (*Ausfall der Signatureinheit*)](https://kasseneck.at/wissen/ausfall): collective receipt, report, re-signing | Kasseneck, automatically |
| [Cash register audit (*Kassennachschau*)](https://kasseneck.at/wissen/kassennachschau): the auditor asks for the DEP | Kasseneck, DEP export |
| Registering the register, retention, tax assessment | **the business owner** |

In short: you build the register's user interface, not the security device. One
`sellReceipt(...)` call produces a signed, chained receipt stored in the DEP. The
backend tests its signature chain against the official verification tool of the
Austrian Federal Ministry of Finance (BMF).

> **Not legal or tax advice.** This section describes what the software does. It
> does not replace professional advice and does not promise that a particular
> business meets all of its obligations by using it. The binding sources are the
> BAO, the RKSV and the rulings of the BMF. Registering the cash register,
> operating it and retaining records remain the duty of the business owner. More
> detail with sources (in German): [kasseneck.at/wissen](https://kasseneck.at/wissen).
> As of September 2026.

### Prefer a ready-made register?

This package is for people building their own app. If you just want to take
payments, you do not need to write any code:

- **[Kasseneck, the ready-made fiscal cash register](https://kasseneck.at)** for
  phone, tablet and browser, including the signature creation unit and the
  FinanzOnline registration.
- **[Solutions by industry](https://kasseneck.at/branchen)**, from restaurants to taxis.
- **[Pricing](https://kasseneck.at/preise)** · **[API docs](https://kasseneck.at/api-doku)**
- **[Contact](https://kasseneck.at/kontakt)**, also for switching registers,
  partnerships and custom integrations.

## Features

- **RKSV receipts:** sale (standard), cancellation and zero receipt (*Nullbeleg*),
  each signed (ES256, JWS) and delivered with its QR code payload.
- **All Austrian VAT (USt) rates** as `VatRate`: 0, 4.9 (basic food, since
  1 July 2026), 10, 13, 19 and 20 %.
- **Integer cents** for receipt amounts, so there is no rounding drift.
- **Cancellations** in full or in part, with reason, remaining quantities and
  stable error codes.
- **Receipt by email** as a link to the public receipt page.
- **Card payments:** hobex terminal (HPS, local REST API) and hobex Cloud with a
  three-valued outcome, Stripe payment links, and card data from any other
  terminal stored and printed on the receipt.
- **Vouchers:** value and promo vouchers, sold and redeemed.
- **Tips:** per register user, cash or card. Staff tips are booked as a 0 %
  pass-through item, owner tips as revenue spread over the receipt's VAT rates.
- **Printing:** ESC/POS over Wi-Fi (raw TCP) and Bluetooth Low Energy, plus the
  built-in printer of myPOS devices. Raw ESC/POS builder for your own layouts.
- **Receipt widgets** that render the same receipt as the printer.
- **Reports:** daily and monthly report PDFs, receipt history.
- **Register login flow:** device pairing, PIN login and sessions for register
  users (`register.dart`, `pos.dart`).
- **Invoice API:** invoices under § 11 UStG (not receipts), customers,
  cancellation and credit notes, PDF and e-invoice XML (UBL or CII).
- **Inventory API:** articles, stock per location and the stock ledger for an
  online shop, plus webhooks with a signature check; create articles, book goods
  receipts, transfers and losses, and reserve stock at checkout, redeemed by
  the invoice (`inventory.dart`).

## Requirements and platforms

- Dart SDK `^3.12.1`, Flutter `>=3.44.0` (see `pubspec.yaml`).
- A Kasseneck API key and cashbox token for the receipt API. A test environment
  with its own `kr_test_…` key exists; ask via
  [kasseneck.at/kontakt](https://kasseneck.at/kontakt).
- Platforms: pub.dev lists **Android** only, because the bundled myPOS plugin is
  Android-only. The package is also used in iOS apps; there the myPOS calls do
  not work. **Web is not supported** (printing and terminal discovery use
  `dart:io` sockets).
- Bluetooth printing uses `flutter_blue_plus`, i.e. **Bluetooth Low Energy**.
  Printers that only speak classic Bluetooth (SPP) are not reachable.
- The hobex HPS client talks HTTP to the terminal in the local network (or to
  `127.0.0.1:8080` when the app runs on the terminal itself).

## Three ways to authenticate

| Client | Import | Credentials | Use it for |
| --- | --- | --- | --- |
| `KasseneckApi` | `kasseneck_api.dart` | API key as bearer + `cashregister-token` header, base URL `https://api.kasseneck.at/v3` | POS devices and apps: selling, cancelling, reports, card payments |
| `RegisterClient`, `RegisterReceiptClient` | `register.dart`, `pos.dart` | pairing code, then device secret + PIN, then a Firebase ID token and a register session, base URL `https://kasse.kasseneck.at/api/v3` | Register apps where staff log in personally (permissions per user) |
| `InvoiceApi` | `invoice.dart` | API key only, no cashbox token, base URL `https://api.kasseneck.at/v3` | Invoices and customers, typically from a server |

`RegisterClient`, `RegisterTransport`, `RegisterSessionClient`,
`InvoiceTransport` and `InvoiceApi` take an optional `baseUrl` (a local
emulator, for example); it must end in `/v3`. `KasseneckApi` always uses
`kPublicBaseUrl`.

The register login in short: `RegisterClient().pairRegisterDevice(code: …)`
exchanges a pairing code from the Kasseneck panel for a permanent device
identity; `registerUserLogin(…)` or `registerPinLogin(…)` returns a
`customToken` and a `sessionId`. Your app signs in to Firebase Auth with the
`customToken` (this package does not depend on `firebase_auth`) and builds the
session transport:

```dart
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

final transport = RegisterTransport(
  idToken: () async => firebaseUser.getIdToken(),  // asked on every call
  sessionId: () async => currentSessionId,         // renew every 30 s, lives 90 s
  cashregisterId: device.cashregisterId,
);
final client = RegisterReceiptClient(transport);
final receipt = await client.sell(
  items: [KasseneckItem(name: 'Coffee', quantity: 1, vat: VatRate.vat20, priceCents: 320)],
  payments: [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 320, tenderedCents: 500)],
);
```

`RegisterSessionClient.fromTransport(transport).renewRegisterSession()` keeps the session
alive. Nothing on this path is retried automatically: a receipt is not safely
repeatable.

## The /v3 wire: marker, fail closed, unknown outcome

**Marker.** Every request to a Kasseneck base carries
`Kasseneck-Api-Version: v3` and `Kasseneck-Client: kasseneck_api/<version>`.
An app that names itself passes `clientHeader: 'kasse-app/1.0.3+34'` (the
product is one of `kasse-app`, `kasse-web`, `kasseneck-api`, `kasseneck_api`,
the version letters, digits and `.+-`);
`omitKasseneckHeaders: true` leaves both headers out. Bases that are not
Kasseneck hosts (an emulator, a proxy) never get them.

**Fail closed.** Every response must carry `Kasseneck-Api-Version: v3`. The
package checks that before it reads the body, and never interprets an answer
that lacks it:

| What came back | Error | Outcome |
| --- | --- | --- |
| No marker | `KasseneckApiError` `dialect_mismatch` | unknown |
| HTTP 200 with an HTML page (hosting fallback, no function saw the call) | `KasseneckApiError` `route_missing` | rejected |
| HTTP 404 with marker and error envelope | `KasseneckApiError` with the envelope's code | rejected |
| Other HTTP status, empty body, no JSON, invalid UTF-8 | `KasseneckHttpError` (`server-error`, `empty-body`, `not-json`) | see below |

One exception: HTML with the marker on a call with an effect (see below) is
`KasseneckHttpError` `not-json` with an unknown outcome, because the handler may
have run. A test double or proxy in your own tests has to send the marker as
well.

**Unknown outcome.** Each `KasseneckApiError` and `KasseneckHttpError` has an
`outcome`: `ErrorOutcome.rejected` (the call was refused, nothing was
signed, charged or refunded) or `ErrorOutcome.unknown` (the operation **may
have happened**). `isOutcomeUnknown(error)` answers it for any error. Unknown
are:

- the codes `dialect_mismatch`, `receipt_outcome_unknown`,
  `cancellation_outcome_unknown`, `response_unreadable` (the call reported
  success, but the answer lacks the receipt, the reference or the payment;
  `details['receiptId']` carries the id when it was readable) and
  `response_translation_failed` (unless `details['handled'] == false`);
- on every call with an effect (the list `unknownOutcomeCalls` of the
  contract, `surface.json`): the calls that sign or move money
  (`createReceipt`, i.e. `sellReceipt`, `zeroReceipt` and
  `RegisterReceiptClient.sell`; `cancelReceipt`; `financeWebService`; the
  card calls `hobexPay`, `hobexRefund` and `stripeCaptureIntent`) and, since
  10.4.1, every other call that books, issues, creates, changes, deletes or
  sends something: inventory writes and reservations, inventory webhooks,
  invoices, credit notes, recorded payments, customers, register settings and
  logo, pairing and unpairing, the stock location of a register, print jobs
  and receipt emails. There it is a network error, a timeout or HTTP 5xx
  after the request was sent, and an unreadable success body. Reading calls
  and the dry runs (`previewGoodsReceipt`, `previewInvoice`) stay rejected,
  and so do the register sign-in sessions and `createPaymentLinkStripe`: a
  repeat books nothing. A dry run counts only when `dryRun` goes out exactly
  as `true` on `receiveGoods` or `issueInvoice`;
- on the money calls `hobexPay`, `hobexRefund` and `stripeCaptureIntent`:
  **every error envelope**, including one without a code, unless its code is
  one of the explicit rejections below. The backend answers from its catch-all
  without a code even when hobex or Stripe already accepted the charge or
  refund.

On the money calls only these codes mean rejected, because each is raised
before the backend contacts the provider: the sign-in and request checks
(`method_not_allowed`, `validation`, `cashregister_token_missing`,
`cashregister_token_invalid`, `cashregister_not_found`, `account_not_found`,
`live_not_enabled`, `unauthorized`, `mfa_required`,
`user_verification_failed`, `admin_required`, `register_user_not_allowed`,
`register_user_no_business`, `register_user_not_found`, `user_disabled`,
`session_expired`, `cashregister_not_assigned`,
`session_other_cashregister`), the `/v3` edge before the handler
(`not_found`, `internal_translation_error`), the module and permission gates
(`module_inactive`, `not_permitted`) and the package's own `route_missing`.

**Never resend a call whose outcome is unknown blindly.** Read the result back
(`getReceipt`, `getReceipts`, the receipt list, `hobexGetStatus`) and act on
what you find. A retried sale is a second signed receipt in the RKSV chain; a
retried card call can charge or refund twice. For the same reason, do not pass
a `RetryClient` (or any `http.Client` that resends by itself) as `httpClient`
to `KasseneckApi`, `RegisterClient`, `RegisterTransport`, `InvoiceTransport`
or `InventoryTransport`, and do not put a retrying proxy in between. A timeout
aborts the request; it does not mean the call failed.

**With an `idempotencyKey`** (inventory writes and reservations,
`issueInvoice`, `cancelInvoice`, `createCreditNote`, `recordInvoicePayment`,
`createCustomer` with a key) the safe step after an unknown outcome is the
same request with the **same** key: it takes effect exactly once and returns
the stored answer (invoices mark it with `replayed: true`; inventory writes
return the stored answer unchanged). Never a new key: that books a second
time. Without a key (receipts, cancellations, money calls, settings, webhooks,
`updateCustomer`, `createCustomer` without one) read the state first and only
then decide.

## Selling: items, amounts, vouchers, tips

**Amounts are integer cents.** `KasseneckItem.priceCents` is the gross unit
price in cents, `quantity` a whole number. `KasseneckItem.euro(singlePrice: …)`
converts a euro double once. Euro doubles appear only where a terminal API
requires them (hobex HPS, `HobexCloudPayments.pay`, SumUp); the raw cloud calls
`hobexPay` and `hobexRefund` take `amountCents` and `tipCents` like the npm
package.

**`payments` is mandatory.** `/v3` knows no single payment method per receipt:
each sale sends a list of `KeckPaymentInput` (cash, card, voucher, ...; a table
that pays with two cards and cash is one receipt). The payments must add up to
the amount due, which the server computes from its VAT buckets, after promo
discounts and including owner tips. `receiptDueCents` computes it exactly as
the backend does, rounding included, so the register never has to guess:

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';

final items = [KasseneckItem(name: 'Pizza', quantity: 2, vat: VatRate.vat10, priceCents: 1190)];
final due = receiptDueCents(items, const [], ReceiptType.standard); // 2380

await kasseneck.sellReceipt(items: items, payments: [
  KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 2000, provider: CreditCardProvider.custom, providerPaymentId: 'term-4711'),
  KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: due - 2000, tenderedCents: 500),
]);
```

With a tip, pass it along (`tip: ReceiptDueTip(200)` plus `tipRecipient:
ReceiptDueTipRecipient.owner` or `.staff`): an owner's tip is turnover and
part of the amount due, a staff tip is booked on its own. If the sums still do
not match, the server answers `payments_sum_mismatch`, and
`paymentsExpectedCents(error)` reads the amount it expected. An empty list is
allowed only when the amount due is 0.

When the amount cannot be computed from the input (a tip without goods, a tip
on a zero receipt, an item without a VAT rate, ...), `receiptDueCents` throws a
`ReceiptDueError` before anything is sent: `code` is always
`receipt_due_unavailable`, `reason` names the cause (`tip_without_goods`,
`invalid_item`, ... see `receiptDueErrorReasons`), `outcome` is always
`rejected`. Decide on `reason`, never on the message.

`sellReceipt` takes, besides `items` and `payments`:

- `vouchers`: `KeckVoucher(action: VoucherAction.sell or .redeem, type: VoucherType.value or .promo, valueCents: …)`.
  Promo vouchers can only be redeemed, only one per receipt and not together
  with other vouchers (`checkVoucherCombinationError` returns the reason).
- `tip`: `KeckTip.forRecipient(registerUserId, cents: 200)` or `KeckTip(cents: …, recipients: …)`.
  The backend books it as its own line; `listTipRecipients()` returns the people
  a tip can be assigned to. A receipt needs at least one item for a tip.
- `customerDetails`, `legalMessage`: extra lines on the receipt.
- card payments carry `provider`, `providerPaymentId` and `providerData` on
  their `KeckPaymentInput`: see [Card payments](#card-payments).

`zeroReceipt()` issues a zero receipt (*Nullbeleg*). Start, monthly and annual
receipts are created by the backend.

## Cancellations (Storno)

A cancellation (*Storno*) is a **new signed receipt** that reverses an existing
one, in full or in part. The backend negates the lines, checks remaining
quantities and permissions, links both receipts (`cancellationOf` on the
cancellation, `cancellations[]` on the original) and prints the reference line on
the cancellation receipt. The original stays byte-identical.

Two entry points, same endpoint (`cancelReceipt`):

```dart
// API key (package:kasseneck_api/kasseneck_api.dart)
final result = await kasseneck.cancelReceipt(
  cashregisterId: original.cashregisterId,
  originalReceiptId: original.receiptId,
  reason: 'input_error',                // key from cancellationReasons
  items: [(index: 0, quantity: 1)],     // omit = cancel everything that is left
  note: 'Customer wanted one',          // internal note, max 200 chars, never printed
);
result.receipt;    // the signed cancellation receipt
result.remaining;  // remaining quantity per line of the original

// Register session (package:kasseneck_api/pos.dart)
final result2 = await client.cancelReceipt(originalReceiptId: id, reason: 'input_error');
```

- Reasons (`cancellationReasons`): `input_error` (wrong entry), `customer_cancelled`
  (customer cancelled), `wrong_payment_method` (wrong payment method),
  `duplicate` (entered twice), `other` (other). The German label is
  printed on the receipt.
- An **empty** `items` list is an error, so that a broken partial
  cancellation never silently becomes a full one.
- `payments` describes the **refund**; a card refund at the terminal carries
  `provider`, `providerPaymentId` and `providerData` (only with card as the
  refund method). A card refund through a provider without its own
  `providerPaymentId` needs the original's payment id: pass the original
  receipt as `original:` (it must be the receipt named by
  `originalReceiptId`), otherwise the call throws before sending.
- Pass `original:` whenever you have it: the cancellation receipt then also
  carries the TESTKASSE and TESTSIGNATUR marks of the original for the local
  print fallback.
- `remainingQuantities(receipt)` (from `pos.dart`) computes remaining quantities
  locally from the original's `cancellations`; the server has the final word.

**Vouchers.** A value voucher is only mirrored on a full cancellation (without
`items`); it cannot be split. A promo voucher is already part of the
original's turnover, so **every** cancellation takes it back in proportion to the
cancelled quantity: 3 × EUR 10 with a EUR 6 discount is EUR 8 per piece, so the
cancellation shows "−10,00" plus a line "Gutschein-Ausgleich +2,00" (voucher
adjustment). What a cancellation granted is stored on its entry in
`receipt.cancellations` as `promoAdjustmentCents` (cents per VAT bucket).

The old cancellation through `createReceipt` without a reference to the
original (`KasseneckApi.cancelReceipt(receipt:)`, `createCancelReceipt`) is gone
in 10.0; `/v3` rejects it.

## Stock at the register

If the account runs the stock module, the backend books sales, cancellations
and invoices against the stock of a location. The register reads locations and
stock, picks its own location and says where returned goods go. Three calls on
the register path (`/api/v3` only), permissions checked by the server:

```dart
import 'package:kasseneck_api/pos.dart';

final client = RegisterReceiptClient(transport);
final locations = await client.stockLocations();        // List<StockLocation>
final list = await client.stock(locationId: 'van-1');   // StockList: stock, values
await client.setStockLocation(stockLocationId: 'van-1'); // null resets to the default location
```

- Quantities (`StockLevel.sellable`, `defective`, `reserved`, `available`) are
  integer thousandths of the base unit and keep their sign; the package never
  rounds or clamps them. `StockList.values` is `null` without the permission
  `stockCosts`, never an empty list.
- **Stock must never block a sale.** A response the package cannot read (a
  missing or fractional quantity) is never turned into `0`: it throws
  `KasseneckValidationError` with `kind: 'response'`. Treat that as "stock
  temporarily unavailable", hide the figures and keep selling.
- **Who may see stock:** `stockViewOf(user.perms)`. A missing `stockView`
  counts as granted, only an explicit `false` blocks it, as in the backend.
  Always use `stockViewOf` for the display: `perms['stockView']` returns the
  raw value and is `false` when the key is missing. The other stock
  permissions (`stockCosts`, `stockMove`, `stockLoss`, `stocktakeCount`,
  `stocktakeClose`, `stockLocation`) count only when present.
- Articles carry `stockLocationIds` and their codes `number`, `ean`,
  `internalCode` plus `stockTracked`; registers `stockLocationId`
  (`CashregisterEntry`, `RegisterCashregisterState`). The stock words of the
  register are `stock.*` labels (`labelText('stock.where_to')`).

**Article id in the cart.** `draftFromArticle` puts the article id on the
draft, the cart keeps it on its `Position`, and the receipt item sends it as
`articleId`; that is how the server knows which stock to book. `bookTile`
bundles only lines with the same article id: two articles that look the same
stay two lines, and so do an article and a free item. Free items (no id, or
an empty one) bundle as before and send the same bytes as before.

**Returns on cancellation.** `cancelReceipt` takes `returnDisposition` from
`returnDispositions`: `restock` (back into stock, the server's default),
`defective` (into stock as defective) or `disposed`. It is the default for the
call; a different choice per line goes into `itemReturnDispositions`, keyed by
the line index used in `items`:

```dart
await client.cancelReceipt(
  originalReceiptId: id,
  reason: 'customer_cancelled',
  items: [(index: 0, quantity: 1), (index: 2, quantity: 1)],
  returnDisposition: ReturnDisposition.restock.name,
  itemReturnDispositions: {2: ReturnDisposition.defective.name},
);
```

An unknown value, a per-line choice without `items` or for an index not in
`items` throws `KasseneckValidationError` (`request`) before anything is sent.
The choice only affects lines with an article; `returnDispositionLabels` maps
each value to its label (`labelText(returnDispositionLabels['restock']!)` is
"Zurück ins Lager"). Without a choice the request is the same as before.

## Sending a receipt by email

The guest gives an address at the counter and receives a **link to the public
receipt page**, no PDF attachment. That page offers a PDF. The receipt document
itself stays byte-identical (it is part of the DEP); the backend logs the
delivery separately.

```dart
// Register session (package:kasseneck_api/pos.dart)
final sent = await client.sendReceiptEmail(fullReceiptId: receipt.fullReceiptId, to: 'guest@example.com');
// API key (package:kasseneck_api/kasseneck_api.dart)
final sent2 = await kasseneck.sendReceiptEmail(fullReceiptId: receipt.fullReceiptId, to: 'guest@example.com');

sent.to;   // normalised address as logged by the backend
sent.at;   // ISO timestamp in Vienna time
sent.via;  // 'own' (business mailbox), 'platform' or 'platform_fallback'
```

With the API key, the cashbox token decides which register is meant. Error codes
(`receiptEmailErrorCodes`): `invalid_address` (let the user correct it),
`too_many_requests` (the backend allows five mails per receipt in 24 hours and 30 per
register per hour; try later), `send_failed` (nothing was sent, a new
attempt is fine), `receipt_not_found` (unknown receipt **or** one of another
register; the backend answers both the same way). Only the backend validates the
address.

## Register settings

The register settings are two blocks, `business` (for every register of the
business) and `device` (this device), with English keys and values
(`theme: 'night'`, `checkoutMode: 'panel'`, `printerType: 'network'`, ...).
`PosSettingsClient` loads them merged with the defaults and writes **patches**:

```dart
import 'package:kasseneck_api/pos.dart';

final settings = PosSettingsClient(transport, deviceId: device.deviceId);
final before = await settings.load();

// Values this package version does not know (a newer server) keep their raw
// value and are listed here. Show them as "set on the server", never overwrite.
final foreign = unknownPosSettingValues(before); // e.g. ['business.theme']

final after = before.business.merge({'theme': 'night', 'payCard': false});
final patch = posSettingsChanges(before.business.toJson(), after.toJson());
if (patch.isNotEmpty) await settings.saveBusiness(patch);
```

- **Send only what changed.** The server merges deeply; a whole block would
  overwrite values a newer server knows. `posSettingsChanges(before, after)`
  produces the patch. `vatRates` always goes as the whole map (at least one
  rate switched on), and `shortcuts` as the whole map of all known actions,
  so that the server sees every key binding when it checks for keys bound
  twice. `saveDevice` rejects a partial shortcut map.
- **Strict before sending.** An unknown key, a German key from 9.x
  (`stil`), a value outside a field's list, a `vatRates` map without any rate,
  an unknown shortcut action or a key bound twice throws a
  `KasseneckValidationError` (`kind: 'request'`) and nothing goes out. `merge`
  throws an `ArgumentError` for the same mistakes.
- **Defaults of 10.0:** `checkoutMode` is `panel` (9.x: page),
  `terminalPort` 8080, and the 16 shortcut actions follow the contract
  (`customAmount` Mod+D, `receipts` Mod+J, `fullscreen` Mod+F).
- `setLogo(dataUrl)` and `removeLogo()` change the register logo.

## Error handling

Decide on the **error code**, never on the message text. The messages are German
and may change.

```dart
try {
  await kasseneck.cancelReceipt(cashregisterId: crId, originalReceiptId: id, reason: 'input_error');
} on KasseneckApiError catch (e) {
  if (isOutcomeUnknown(e)) {
    // cancellation_outcome_unknown, response_unreadable, ...: the cancellation
    // may exist. Reload the original and look at its cancellations; never resend.
    return;
  }
  switch (e.code) {
    case 'already_cancelled':          // show as cancelled, disable the button
    case 'quantity_exceeds_remaining': // reload remaining quantities (someone was faster)
    case 'own_receipts_only':          // ask the manager
      break;
    default:
      rethrow;
  }
} on KasseneckHttpError catch (e) {
  if (e.outcome == ErrorOutcome.unknown) {
    // timeout or 5xx after sending: same as above, read back, never resend
  }
  rethrow;
}
```

The error types are exported from `kasseneck_api.dart`, `register.dart` and
`invoice.dart`. `pos.dart` exports only `KasseneckReceiptFormatError`,
`ErrorOutcome` and `isOutcomeUnknown`; to catch the others on the register
path, import `register.dart` as well.

| Type | Meaning |
| --- | --- |
| `KasseneckApiError` | The backend refused, or the package detected an edge problem (`code`, `message`, `details`, `outcome`). |
| `KasseneckHttpError` | Transport problem (`reason`: `KasseneckHttpError.reasonTimeout`, `reasonNetwork`, `'server-error'`, `'empty-body'`, `'not-json'`; `statusCode`, `timeout`, `outcome`). |
| `KasseneckValidationError` | A request was rejected before sending (`kind: 'request'`), or a response of a reading call lacks a required field (`'response'`). |
| `KasseneckReceiptFormatError` | A receipt fetched with `getReceipt` or `RegisterReceiptClient.get` could not be parsed (`receiptId` when readable). On the signing calls the same problem is `response_unreadable` with an unknown outcome. |

Invalid input to `sellReceipt` and `zeroReceipt` (no items, invalid vouchers,
payments missing or malformed) throws a `KasseneckValidationError`
(`kind: 'request'`) before anything is sent, the same type as
`RegisterReceiptClient.sell` and the npm package.

**What the cashier sees.** `pos.dart` carries the register's sentences, the
same ones the web register shows (`posMessages`, `posLabels`, `messageText`,
`labelText`, generated from the contract file `pos-texts.json`), and the rules
that pick one for an error. Classify the error yourself (`ErrorKind.api` for a
`KasseneckApiError`, `ErrorKind.timeout`/`ErrorKind.network` for the
`KasseneckHttpError` reasons of the same name, ...), then:

```dart
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

String sentence(Object e, String fallback) {
  final kind = switch (e) {
    KasseneckApiError() => ErrorKind.api,
    KasseneckHttpError(reason: KasseneckHttpError.reasonTimeout) => ErrorKind.timeout,
    KasseneckHttpError(reason: KasseneckHttpError.reasonNetwork) => ErrorKind.network,
    KasseneckHttpError() => ErrorKind.unexpected,
    _ => ErrorKind.other,
  };
  final rule = findErrorRule(kind, code: e is KasseneckApiError ? e.code : null, outcome: messageOutcome(e));
  if (rule.key case final key?) {
    return messageText(key, key == 'server.unexpected' ? {'status': e is KasseneckHttpError ? e.statusCode : 0} : const {});
  }
  return switch (rule.behavior!) {
    ErrorRuleBehavior.serverText => (e as KasseneckApiError).message,
    ErrorRuleBehavior.ownText || ErrorRuleBehavior.fallback => fallback,
  };
}
```

`findErrorRule` applies a code rule (`errorCodeRules`: edge codes get a human
sentence instead of the technical one), then an outcome rule
(`errorOutcomeRules`), then the one rule of the kind (`errorRules`, unchanged
since 10.0.0-rc.1). `messageOutcome` follows the transport first, which marks
every call with an effect as outcome unknown (see the /v3 wire above), and also
treats a timeout or network error on a call from `callsWithEffect` (receipt,
cancellation, FinanzOnline, card payments, print job, receipt email) as outcome
unknown: the sentence then says to check whether the last operation went
through, never to try again. Since 10.4.1 that includes the settings, pairing,
unpairing and stock location calls, as in the web register.

**Code catalogues per endpoint group**, each one the server's own codes, then
the sign-in and edge codes that can reach it, then the codes the package sets
itself (`clientErrorCodes`: `route_missing`, `response_unreadable`):
`receiptErrorCodes`, `cancellationErrorCodes`, `paymentErrorCodes` (the
`payments[]` codes of a sale or cancellation, such as `payments_sum_mismatch`),
`receiptEmailErrorCodes`, `registerErrorCodes` (`register.dart`),
`posErrorCodes` (`pos.dart`) and `invoiceErrorCodes` / `invoiceRequestErrorCodes`
(`invoice.dart`). Helpers such as `isRegisterError(e, 'cashregister_in_use')`,
`registerErrorDetails(e)` (`retryAfterSec`, `deviceLabel`, ...),
`isPosError`, `posFieldErrors` and `invoiceFieldErrors` read the details.

## Card payments

A card payment has three possible outcomes, not two: approved, definitely
declined, or **unknown** (timeout, lost connection, the terminal never
answered). Treating "unknown" as "declined" and retrying is how a customer gets
charged twice. `HpsPayments` and `HobexCloudPayments` fix the transaction ID
**before** the first network call and, if the answer is lost, resolve that same
ID instead of starting a new charge. A lost answer ends in
`CardPaymentOutcome.unresolved` (keep the ID, resolve later) rather than a guess.

| Provider | What the package does |
| --- | --- |
| **hobex HPS** (terminal in the local network) | `HpsPayments`: `pay`, `refund`, `cancel` with a resolved three-valued outcome; `discoverHpsTerminals` finds terminals in the LAN |
| **hobex Cloud** (via the Kasseneck backend) | `HobexCloudPayments.pay` with the same outcome; refunds via `kasseneck.hobexRefund(...)` |
| **Stripe** | payment links for remote and online payments: `createStripeLink`, `stripeCaptureIntent` |
| **SumUp** | thin wrapper around the `sumup` plugin: `SumupService` in `services/sumup_service.dart` |
| **any other terminal** (for example GP Tom or myPOS) | pass your terminal's result on the card payment as `KeckPaymentInput(provider: …, providerPaymentId: …, providerData: …)`; it is stored and printed on the receipt |

`HpsPayments` and `HobexCloudPayments.pay` take euros (`amount: 12.50`), as
the hobex API expects; the raw calls `kasseneck.hobexPay(...)` and
`hobexRefund(...)` take integer cents (`amountCents: 1250`), like the npm
package.

<details>
<summary><b>Example: hobex terminal (HPS) to signed receipt</b></summary>

```dart
import 'package:kasseneck_api/hobex_hps.dart'; // HpsClient, HpsPayments, CardPaymentOutcome, HobexReceipt

// Default base URL is http://127.0.0.1:8080 (app runs on the terminal).
// Terminal in the LAN: HpsClient(baseUrl: Uri.parse('http://192.168.1.50:8080'), tid: …)
final hps = HpsPayments(HpsClient(tid: '3600335')); // TID without leading zero

// The ID is fixed BEFORE the request goes out. Persist it right away, so that a
// lost answer can be resolved later instead of being retried blindly.
final transactionId = HpsClient.newTransactionId();

final result = await hps.pay(amount: 12.50, transactionId: transactionId);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // continue below
  case CardPaymentOutcome.declined:
    return; // definitely no money moved; a new attempt is safe
  case CardPaymentOutcome.unresolved:
    // Not resolved within the resolve budget (90 s, configurable).
    //
    // Do NOT retry here. Measured on a real terminal (2026-08-26): sending the
    // same transactionId again starts a SECOND card transaction; the terminal
    // does not recognise it as the same one. A retry is a real second charge.
    //
    // Keep transactionId and resolve the outcome first
    // (HpsClient.transactionStatus(...) once the terminal answers again), then
    // act on a known outcome. doc/kartenzahlung.md (German) explains the
    // individual response codes.
    return;
}

// Take over the terminal result, then create the signed receipt.
final card = HobexReceipt.fromHps(result.response!);
await kasseneck.sellReceipt(
  payments: [
    KeckPaymentInput(
      method: KeckPaymentMethod.creditCard,
      amountCents: 1250,
      provider: card.creditCardProvider, // hobexHps
      providerPaymentId: card.transactionId,
      providerData: card.toCardPaymentData(),
    ),
  ],
  items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

`hps.refund(...)` and `hps.cancel(...)` return the same resolved outcome. An
`HpsObserver` passed to `HpsPayments` (`observer:`) logs requests, failures and
how an outcome was resolved.

To find a terminal in the local network:

```dart
final scan = await discoverHpsTerminals(stopAtFirst: true);
final found = scan.first;
if (found != null) {
  final client = HpsClient(baseUrl: Uri.parse('http://${found.host}:${found.port}'), tid: found.tids.first);
}
```
</details>

<details>
<summary><b>Example: hobex Cloud to signed receipt</b></summary>

```dart
import 'package:kasseneck_api/kasseneck_api.dart'; // HobexCloudPayments, CardPaymentOutcome

final cloud = HobexCloudPayments(kasseneck);

// Same rule as with HPS: the caller fixes the ID before the request goes out.
final transactionId = KasseneckApi.newHobexTransactionId();

final result = await cloud.pay(transactionId: transactionId, amount: 12.50);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // continue below
  case CardPaymentOutcome.declined:
    return; // definitely no money moved; a new attempt is safe
  case CardPaymentOutcome.unresolved:
    // Not resolved within the budget. Do NOT retry blindly: keep transactionId
    // and resolve later, see the HPS example above.
    return;
}

final card = result.receipt!;
await kasseneck.sellReceipt(
  payments: [
    KeckPaymentInput(
      method: KeckPaymentMethod.creditCard,
      amountCents: 1250,
      provider: card.creditCardProvider,
      providerPaymentId: card.transactionId,
      providerData: card.toCardPaymentData(),
    ),
  ],
  items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

`HobexCloudPayments` has no `refund()` or `cancel()`. A cloud refund still goes
through the raw call `kasseneck.hobexRefund(...)`: it returns `true` or throws
a `KasseneckApiError`, never `false`, and it does not resolve its outcome. Only
the rejection codes listed under "Unknown outcome" mean nothing was refunded;
any other failure, including an error without a code, is an unknown outcome
(`isOutcomeUnknown`): check with `hobexGetStatus` before refunding again.
</details>

<details>
<summary><b>Raw access: <code>HpsClient</code> and <code>kasseneck.hobexPay(...)</code></b></summary>

The local `HpsClient` and the cloud calls `kasseneck.hobexPay(...)`,
`hobexRefund(...)` and `hobexGetStatus(...)` remain available for full control.
**Neither resolves the outcome:** a raw call that never gets an answer stays
unresolved forever. Building a payment flow on it means solving again the
problem that `HpsPayments` and `HobexCloudPayments` already solve, with the real
risk of answering "was the card charged?" wrongly under exactly the conditions
(timeout, dropped connection) where a wrong answer is expensive. Use the raw
client only for what the wrapper does not expose, for example
`hps.diagnosis()` or `hps.transactionStatus(...)`.
</details>

<details>
<summary><b>Example: Stripe payment link</b></summary>

```dart
import 'package:kasseneck_api/enums/stripe_link_mode.dart';

final session = await kasseneck.createStripeLink(
  items: [KasseneckItem(name: 'Gift card', quantity: 1, vat: VatRate.vat20, priceCents: 5000)],
  createReceiptAfterPayment: true,
  mode: StripeLinkMode.payment, // or .authorization, captured later with stripeCaptureIntent
  customerEmail: 'guest@example.com',
);
print(session?.url);
```
</details>

## Printing and displaying receipts

```dart
import 'package:kasseneck_api/printing.dart'; // KeckPrinter, KeckPaperSize, QrPrintMode, QrModuleSize, …

// Recommended: one printer object per device. Returns a KeckPrintResult instead
// of throwing, and reports a missing QR code (qrError).
final printer = KeckPrinter.wifi(ip: '192.168.0.50', size: KeckPaperSize.mm80);
// or: KeckPrinter.bluetooth(address: 'AA:BB:CC:DD:EE:FF', size: KeckPaperSize.mm58)
final printed = await printer.printReceipt(receipt);
if (printed.qrError != null) {
  // The receipt went out without its QR code: tell the customer.
}
await printer.openDrawer();
await printer.dispose();
```

QR code garbled or missing? Printers understand different commands:

```dart
await printer.printReceipt(receipt, qrMode: QrPrintMode.imageBitImage); // or .native
// Some cheap printers only know the older QR model 1:
await printer.printReceipt(receipt, qrMode: QrPrintMode.nativeModel1);
// The native command sizes its modules to fit the paper (quiet zone included).
// qrModuleSize is a cap, never an enlargement beyond what fits:
await printer.printReceipt(receipt, qrModuleSize: QrModuleSize.large);
```

The older static path still works: `kasseneck.initWifiPrinter(ip, size)` or
`kasseneck.initBluetoothPrinter(printerAddress: …)`, then
`receipt.printReceiptWifi()` or `receipt.printReceiptBluetooth(qrMode: …, qrModuleSize: …)`.
Note that `KasseneckApi.openCashDrawer()` and `printReceiptWifi()` only send to
the configured **Wi-Fi** printer and silently do nothing if none is set. On myPOS
devices, `receipt.printReceiptMyPos()` uses the built-in printer. For your own
layouts, `printing.dart` exports the ESC/POS builder (`EscPosGenerator`,
`PosStyles`, `CustomPrintJob`).

### The same receipt on screen and paper

```dart
import 'package:kasseneck_api/services/logo_service.dart';

// Once at app start: store logos on disk, so the first receipt after a restart
// does not wait for the network.
await LogoService.enablePersistentStorage();

// Screen (widget from kasseneck_api.dart). The server's layout wins whenever
// the response carries one; otherwise draw the local fallback (the printer
// service does that for you) in fallbackPaperSize (default mm58).
final shown = receiptLayoutFromResult(receipt, fallbackPaperSize: KeckPaperSize.mm80);
if (shown.layout != null) {
  KeckReceiptSheetWidget(
    layout: shown.layout!,
    logoUrl: receipt.logoUrl,
    logoSize: receipt.logoScale,
    brandMark: receipt.showKreiseckLogo,
  );
}

// Paper, with the same logo (printing.dart)
final logo = await loadPrintLogo(receipt.logoUrl, receipt.logoScale, KeckPaperSize.mm80);
final paper = await KeckPrinterService.getPaperFromReceipt(receipt, KeckPaperSize.mm80,
    logo: logo, brandMark: receipt.showKreiseckLogo);
```

**Server layout first.** `receiptLayoutFromResult(receipt, fallbackPaperSize:)`
returns the server's line model (80 mm) whenever the response carries one, and
`layout == null` with the fallback width otherwise. On the public channel only
the server's layout carries the card block, so screen, paper and PDF show the
same receipt. `KeckPrinterService.getPaperFromReceipt` follows the same rule:
a server layout is always printed; the local fallback prints the TESTKASSE and
TESTSIGNATUR frames and the receipt type block (STORNOBELEG, TRAININGSBELEG,
NULLBELEG, ...) itself.

## Reports, receipt history, FinanzOnline status

```dart
import 'package:kasseneck_api/models/report_month.dart';

final monthly = await kasseneck.downloadMonthlyReport(ReportMonth.now()); // PDF bytes, Vienna month
final daily   = await kasseneck.downloadDailyReport(DateTime.now());       // PDF bytes
final history = await kasseneck.getReceipts(start, end);                   // List<KasseneckReceipt>
final one     = await kasseneck.getReceipt(receiptId);
final status  = await kasseneck.getCashboxStatus();                        // register status at FinanzOnline
```

`getReceipts` skips single receipts it cannot read instead of failing the whole
range. `getSignatureStatus(certificateHex)` asks FinanzOnline for the status of a
signature certificate.

## Invoices (invoice API)

Invoices (*Rechnungen*) are **not receipts**: no cashbox token, no signature, but
a sequential invoice number under § 11 UStG. The key is the account's
`api_key`, and it belongs on a **server**. For live use, Kasseneck has to enable
the invoice API for the account, so check the setup first.

```dart
import 'package:kasseneck_api/invoice.dart';

final invoices = InvoiceApi(apiKey: 'kr_live_…');

final setup = await invoices.getInvoiceSetupStatus();
if (!setup.ready) {
  for (final gap in setup.missing) {
    print('${gap.requirement}: ${gap.message}');
  }
  return;
}

final customer = await invoices.createCustomer(
  const CustomerInput(type: 'company', name: 'Café Muster GmbH', country: 'AT', externalId: 'shop-4711'),
);

try {
  final issued = await invoices.issueInvoice(IssueInvoiceRequest(
    idempotencyKey: 'order-4711', // the same key never creates a second invoice
    customerId: customer.id,
    priceMode: 'net',
    serviceStart: '2026-09-15',
    items: const [InvoiceItemInput(description: 'Consulting', quantity: 2, unitPriceCents: 5000, vatRate: 20)],
  ));
  final pdf = await invoices.getInvoicePdf(issued.invoice.id); // Uint8List
  final xml = await invoices.getInvoiceXml(issued.invoice.id); // UBL; format: 'cii' for CII
  // xml.xml, xml.format ('ubl'), xml.filename ('invoice-<number>.xml')
} on KasseneckApiError catch (e) {
  switch (invoiceErrorCode(e)) {
    case 'validation':
      for (final f in invoiceFieldErrors(e)) {
        print('${f.field}: ${f.message}');
      }
    case 'invoice_setup_incomplete':
      print(e.details['missing']);
    default:
      rethrow;
  }
}
```

After a timeout (`KasseneckHttpError.reasonTimeout`), issue again **with the same
`idempotencyKey`**: the answer then carries `replayed: true` and the same
invoice. The same key with different data gives `idempotency_conflict`. Since
10.4.1 every invoice call with an effect (`issueInvoice`, `cancelInvoice`,
`createCreditNote`, `recordInvoicePayment`, `createCustomer`,
`updateCustomer`) reports `ErrorOutcome.unknown` after a timeout, a network
error, HTTP 5xx or an unreadable answer (before: `rejected`);
`previewInvoice` and the reading calls stay `rejected`.
Cancel with `cancelInvoice`, partial credit with `createCreditNote`; all error
codes are listed in `invoiceErrorCodes`.

**Prices.** Each item has either `unitPriceCents` (integer cents) or
`unitPriceMicros` (millionths of a euro, for prices below one cent), never both.
Micro prices are accepted only once they are enabled for the account; otherwise
the server answers with `validation`. On a request, `vatRate` is one of
`vatRates` (0, 10, 13, 20). `unit` takes a key from `invoiceUnits` (`piece`,
`hour`, …; default `piece`), not free text.

**Language and brand.** An invoice has one number and one language (`de` or
`en`): the one in the request, otherwise the customer's, otherwise German.
Public authorities always get German. `brandId` picks a brand from
`listBrands()`. The same invoice in the other language exists only as a marked
translation copy, `getInvoicePdf(id, language: 'de')`, never as a second invoice.

**The tax case is derived.** `taxScheme` is optional: the server derives it from
customer country, customer type, VAT ID and the `kind` (`goods` or `service`) of
the items. A value you send is checked; if it does not match, you get
`tax_scheme_mismatch` with the expected case instead of a wrong invoice. For
domestic reverse charge there is `reverseChargeReason` from
`reverseChargeReasons` (construction services, scrap, certain devices and more).
Other cases include `oss` and `outsideScope` (service to a business outside the
EU, not taxable in Austria).

**Already paid.** If you collect online and invoice afterwards, pass the payment
along: `IssueInvoiceRequest(payment: PaymentInput(method: 'card'))`. It is
recorded in the same transaction that finalises the invoice, and the PDF then
has no payment box and no Girocode QR. If the money arrives later, use
`recordInvoicePayment(RecordPaymentRequest(...))` with its own
`idempotencyKey`, otherwise a retry books twice. With `method: 'cash'` (and with
`onSite: true`) the payment is booked and the `notice` list carries
`cash_receipt_required`: a cash sale needs a receipt from the fiscal cash
register (§ 132a BAO); the note on the invoice does not replace it.

**Computing totals in advance.** `computeInvoiceTotals` computes the totals exactly as
the server does, offline. `previewInvoice` asks the server: a dry run that checks
like issuing (customer, tax case, required fields) but finalises nothing and does
not consume the `idempotencyKey`.

```dart
const items = [
  InvoiceItemInput(description: 'Manicure', quantity: 1, unitPriceCents: 1479, vatRate: 20),
  InvoiceItemInput(description: 'Polish', quantity: 1, unitPriceCents: 1500, vatRate: 20),
];
final totals = computeInvoiceTotals(items, 'gross');
// totals.grossCents == 2979, netCents == 2483, vatCents == 496

final request = IssueInvoiceRequest(
  idempotencyKey: 'order-$orderNumber',
  customerId: customer.id,
  priceMode: 'gross',
  serviceStart: '2026-09-16',
  items: items,
);
final preview = await invoices.previewInvoice(request);
// preview.preview.totals, preview.preview.taxScheme, preview.preview.taxSchemeReason
final issued = await invoices.issueInvoice(request); // same key, one invoice
```

In **gross mode** the gross amount per rate is the agreed price:
net = round(G × 100 / (100 + rate)), VAT = G − net. In **net mode** the VAT per
rate is rounded from the net sum. Rounding is commercial (half a cent away from
zero), per rate, then summed. If the server derives a tax-exempt case
(`zeroRatedTaxSchemes`, e.g. `intraCommunitySupply`), pass it as the third argument of
`computeInvoiceTotals`, otherwise the function computes tax the invoice does not show;
`previewInvoice` names the case. Issuing is binding: customer or account may
change between preview and invoice. Totals are positive for credit notes too;
the sign is in the document type (`docType: 'credit_note'`).

**Stock.** An item may name its article (`InvoiceItemInput.articleId`); if
the article is stock-tracked and the stock module is active, issuing the
invoice books it out, from `IssueInvoiceRequest.stockLocationId` or the
default location. The invoice never fails because of stock. `cancelInvoice`
and `createCreditNote` take `returnDisposition` (`restock`, `defective`,
`disposed`); credit-note lines use `CreditNoteItemInput` with their own
`returnDisposition`. The fields go out only when set; the server checks them
(an unknown choice, a choice on an invoice line or an id of the wrong shape
comes back as `validation` with the field path).

```dart
await invoices.createCreditNote(const CreditNoteRequest(
  idempotencyKey: 'return-4711',
  invoiceId: 'inv_…',
  reason: 'return',
  returnDisposition: 'restock',
  items: [
    CreditNoteItemInput(description: 'Rye bread', quantity: 1, unitPriceCents: 450, vatRate: 10,
        articleId: 'rye-bread', returnDisposition: 'defective'),
  ],
));
```

**Reservations.** An item of `issueInvoice` can redeem a reservation of the
inventory API: use `IssueInvoiceItemInput` with `articleId` and
`reservationId` (from `InventoryClient.createReservation`). The server checks it
when issuing: `reservation_not_found`, `reservation_mismatch` (no open quantity
of this article at the invoice's stock location) or `reservation_not_active`
(already redeemed or released). An expired reservation is no error: the invoice
is issued and sells without it, and `notice` carries `reservation_expired` with
`reservationId`. Selling less than reserved releases the rest. Credit notes do
not take the field (`validation`).

**VAT ID check.** An invoice without VAT that relies on the customer's VAT ID
(intra-Community supply, reverse charge) is only issued with a result of the
VAT ID check (FinanzOnline, otherwise VIES) on the day of issue. Decide on the
code: `vat_id_check_pending` means try again later with the same
`idempotencyKey` (`e.details['retryAfter']` seconds), or issue anyway with
`IssueInvoiceRequest(acceptVatIdRisk: true)`, in which case you bear the risk
and the invoice carries `vatIdRisk`. `vat_id_invalid` blocks even with it. An
issued invoice carries the frozen proof in `vatIdProof` (`checkedOn`, `source`
`finanzonline` or `vies`, `level` 1 or 2, `code`).

```dart
try {
  await invoices.issueInvoice(const IssueInvoiceRequest(
    idempotencyKey: 'order-1001',
    priceMode: 'gross',
    serviceStart: '2026-10-06',
    stockLocationId: 'haupt',
    items: [
      IssueInvoiceItemInput(description: 'Rye bread', quantity: 2, unitPriceCents: 450, vatRate: 10,
          articleId: 'rye-bread', reservationId: 'res_…'),
    ],
  ));
} on KasseneckApiError catch (e) {
  if (invoiceErrorCode(e) == 'vat_id_check_pending') {
    final retryAfter = e.details['retryAfter']; // seconds; then the same request, same key
  } else {
    rethrow;
  }
}
```

**Notices are always a list.** `notice` on `issueInvoice`, `previewInvoice` and
`recordInvoicePayment` is a `List<InvoiceNotice>`, empty if there is nothing to
say. An intra-EU supply carries `recapitulative_statement_due`, a cash-paid
invoice `cash_receipt_required`. Decide on the code, not the text:

```dart
if (issued.notice.any((n) => n.code == 'cash_receipt_required')) {
  // Cash sale: issue a receipt through the fiscal cash register
}
```

## Inventory API

For online shops and other systems that show or mirror the stock of a
Kasseneck account: read articles, locations, stock per location and the stock
ledger, and get every stock change pushed by webhook within seconds, also the
ones made at the register in the shop. Since 10.4 also write: create and update
articles, book goods receipts, transfers, losses and condition changes, and
reserve stock at checkout (see [Writing and reservations](#writing-and-reservations));
since 10.5 variant groups (sizes, colours, see [Variants](#variants)).
Uses the `api_key` of the account and belongs on a **server**, never in an app
customers install. Reading needs the module `lager`, writing also the account
switch „Lager-API schreiben“ (always on in the test environment, `kr_test_…`);
purchase prices and stock values appear only when the account has the
permission `costs` (otherwise the fields are absent, not `null`:
`Article.hasPurchasePriceMicros`, `StockResult.values == null`).

The package needs the Flutter SDK to resolve (it declares `flutter: sdk:
flutter`), but `lib/inventory.dart` imports no Flutter code, so a server
built on it runs without `dart:ui`; a test keeps it that way.

**Integers with a fixed scale:** quantities in thousandths of the base unit
(`1000` = 1 piece, `250` = 0.250 kg), money in cents, purchase prices in
micro-euros. `available = onHand − reserved` and may be negative: the register
never refuses a sale. A fractional or missing quantity in a response throws
`KasseneckValidationError` with `kind: 'response'`; it is never read as `0`.

```dart
import 'package:kasseneck_api/inventory.dart';

final inventory = InventoryClient(apiKey: 'kr_live_…');

// 1. Read: an article by its EAN, then its stock per location.
final article = await inventory.lookupArticleByCode(code: '9001234567896');
final stock = await inventory.getStock(article.id);
// stock.stock.first: locationId 'haupt', onHand 12000, reserved 2000, available 10000

// 2. Initial sync, page by page over nextCursor.
final mirror = <String, ({int available, int sequence})>{};
await for (final row in inventory.iterateStock(locationId: 'haupt')) {
  mirror['${row.articleId}/${row.locationId}'] = (available: row.available, sequence: row.sequence);
}

// 3. Subscribe once. The secret is shown only in this response.
final created = await inventory.createWebhook(
  url: 'https://shop.example.com/kasseneck-webhook',
  events: ['stock.changed', 'stock.below_minimum'],
  description: 'Bäckerei Kornblum online shop',
);
final secret = created.secret; // store it where the receiver reads it, never in a log

// 4. Receive: the header X-Kasseneck-Signature and the raw body bytes, before
// any JSON decoding. Answer within 10 s, work afterwards.
final reorder = <String>[];
final expiredOrders = <String>[];
final variantGroups = <String, VariantGroup>{};
int receive(String? signatureHeader, List<int> rawBody) {
  if (!verifyInventoryWebhookSignature(secret, signatureHeader, rawBody)) return 400;
  final InventoryWebhookEvent? event;
  try {
    event = parseInventoryWebhookEvent(rawBody); // throws on a malformed envelope
  } on KasseneckValidationError {
    return 400;
  }
  if (event == null || event.test) return 200; // unknown type of a later version, or a test delivery
  switch (event) {
    case InventoryStockChangedEvent(:final data):
      // State, not delta: keep it only if sequence is higher than the stored one.
      final key = '${data.articleId}/${data.locationId}';
      if (data.sequence > (mirror[key]?.sequence ?? -1)) {
        mirror[key] = (available: data.available, sequence: data.sequence);
      }
    case InventoryStockBelowMinimumEvent(:final data):
      reorder.add(data.articleId);
    case InventoryArticleEvent(:final data):
      if (!data.active) mirror.removeWhere((key, _) => key.startsWith('${data.id}/'));
    case InventoryReservationEvent(:final data):
      // reservation.expired, .released or .redeemed: the status afterwards.
      if (data.status == 'expired') expiredOrders.add(data.reference ?? data.id);
    case InventoryVariantGroupEvent(:final data):
      // variant_group.created or .updated: keep it only if updatedAt is later.
      final stored = variantGroups[data.id];
      if (stored == null || (data.updatedAt ?? '').compareTo(stored.updatedAt ?? '') > 0) variantGroups[data.id] = data;
  }
  return 200;
}
```

- **Signature.** `verifyInventoryWebhookSignature(secret, header, rawBody,
  {toleranceSec = 300, now})` returns `true` or `false` and never throws. It
  is the same procedure as for partner webhooks: `X-Kasseneck-Signature:
  t=<unix seconds>,v1=<hex>` with HMAC-SHA256 over `"<t>.<raw body>"`,
  compared in constant time, and a window of 300 seconds in both directions
  against replays. Unlike the JavaScript twin it is synchronous (pure Dart,
  `package:crypto`), so there is no `await` to forget. Pass the bytes as
  received (`List<int>`) or the body as a `String`; decoding and re-encoding
  the JSON changes the bytes and the signature no longer matches. After
  `rotateWebhookSecret` only the new secret is valid; pass both during your own
  switch-over (`secret` may be a list, one match is enough).
- **Parsing.** `parseInventoryWebhookEvent(rawBody)` returns `null` for an
  event type this version does not know (answer 2xx and skip it) and throws
  `KasseneckValidationError` on a body that is no envelope or carries a
  fractional quantity. The result is a sealed `InventoryWebhookEvent`:
  `InventoryStockChangedEvent`, `InventoryStockBelowMinimumEvent`,
  `InventoryArticleEvent` (`article.created`, `article.updated`,
  `article.deactivated`), since 10.4 `InventoryReservationEvent`
  (`reservation.expired`, `reservation.released`, `reservation.redeemed`)
  and since 10.5 `InventoryVariantGroupEvent` (`variant_group.created`,
  `variant_group.updated`), each with `id`, `createdAt`, `accountId` and
  `test`. A `switch` without `default` over all subclasses needs a case for
  each new one.
- **Events.** `stock.changed` carries the current state of one article at one
  location (`onHand`, `reserved`, `available`, `defective`, `sequence`,
  `updatedAt`) plus `cause` (`sale`, `invoice`, `goods_receipt`, `transfer`,
  `takeover` …, see `stockChangeCauses`) and `movementId`; changes within
  10 seconds are combined into one delivery. `stock.below_minimum` fires once
  when `available` (`onHand − reserved`, so a reservation alone can trigger it)
  drops below the minimum stock set for the location
  (`Article.minStockByLocation`); `minStock` in the payload is that threshold,
  the article's own `minStock` never triggers it, and
  `listStock(belowMinimum: true)` follows the same rule. `reservation.*`
  carries the reservation as `getReservation` returns it, with its status
  afterwards; `released` and `redeemed` also fire for a partial release or
  redemption (the status stays `active`). `variant_group.*` carries the
  group as `getVariantGroup` returns it (see [Variants](#variants)). In
  movements, `goods_receipt` is a goods receipt; `receipt` only ever means a
  sales receipt (`source.type`). Deduplicate on `event.id`; deliveries are
  retried after 1 min, 5 min, 30 min, 2 h and 12 h.
- **Safety net without webhooks.** `listStock(changedSince: …)` and
  `listArticles(updatedSince: …)` are sorted by `updatedAt` ascending and
  include the boundary, so remembering the last `updatedAt`
  (`DateTime.parse(article.updatedAt!)`) and asking again loses nothing. Times
  go out as ISO 8601 UTC with milliseconds. Lists take `limit` (1–200, server
  default 50) and `cursor`; `iterateArticles`, `iterateStock` and
  `iterateStockMovements` follow `nextCursor` as a `Stream` and end with a
  response error if the server names the same cursor twice.
- **Checked before sending.** An empty id, a `limit` outside 1–200, a lookup by
  `code` together with `externalSystem`/`externalId`, an empty `events` list or
  an `updateWebhook` without a change throw `KasseneckValidationError` with
  `kind: 'request'`; nothing goes out. Everything else the server checks and
  answers with `validation` (`inventoryFieldErrors(error)`).
- **Test deliveries.** `sendWebhookTest` sends an invented payload with
  `test: true` in the envelope; at most 20 per account and calendar day in
  Vienna, after that `rate_limited` with the wait until midnight in Vienna.
  Deliveries carry `deliveryId` (the header `X-Kasseneck-Delivery`), webhooks
  `consecutiveFailures`, the same names as for partner webhooks.
- **Errors.** `rate_limited` (about 20 requests per second per account, or the
  daily limit of `sendWebhookTest`) carries the wait in
  `inventoryRetryAfterSec(error)`. `inventory_api_not_enabled`,
  `module_inactive`, `article_not_found`, `invalid_cursor`,
  `webhook_not_found`, `webhook_limit` (5 per account),
  `invalid_webhook_url`, `event_not_subscribed` and `webhook_inactive` are
  decided on the code with `isInventoryError(error, code)`.
- **Errors when writing.** `idempotency_conflict` (same key, other content),
  `exceeds_stock` (transfers, losses and condition changes never overdraw),
  `insufficient_available` (reservation; the missing positions in
  `inventoryShortfalls(error)`), `code_taken` and `external_id_taken` (with
  `details['field']` and the `articleId` that owns the code),
  `stock_kind_locked`, `article_inactive`, `reservation_not_found`,
  `reservation_not_active`, since 10.5 `variant_group_not_found`,
  `variant_already_exists`, `invalid_variant_attributes`,
  `variant_group_inactive` and `variant_limit` (see [Variants](#variants)),
  and the rest of `inventoryErrorCodes`.
- **Names.** `StockLevel` here has `onHand` and `sequence`; the register's
  `StockLevel` in `pos.dart` is a different type with `sellable`. If you import
  both libraries, give one a prefix (`import '…/inventory.dart' as inv;`).
  `StockValue` is the same type in both.

### Writing and reservations

Every write takes an `idempotencyKey` (1–120 characters). The same request with
the same key takes effect once and returns the stored answer; the same key with
other content gives `idempotency_conflict`. Fix the key before the first
attempt and store it with your order: after a timeout or network error
(`KasseneckHttpError`), send the **same** request with the **same** key again.
The client never retries by itself and never trims or shortens a key; a new key
would book a second time. Since 10.4.1 every write, reservation and webhook
call reports `ErrorOutcome.unknown` in that case (also after HTTP 5xx or an
unreadable answer; before: `rejected`). For writes and reservations,
`isOutcomeUnknown(error)` is the signal to resend with the same key. The
webhook calls (`createWebhook`, `updateWebhook`, `deleteWebhook`,
`rotateWebhookSecret`, `sendWebhookTest`) take no key: read the state first
(`listWebhooks`, for a test delivery `listWebhookDeliveries`) instead of
sending again. `previewGoodsReceipt` and the reading calls stay `rejected`.

```dart
final inventory = InventoryClient(apiKey: 'kr_live_…');

// An article with the shop's own id; without ean the server assigns the next own code.
final article = await inventory.createArticle(const CreateArticleRequest(
  idempotencyKey: 'shop-article-1001',
  name: 'Kaiser roll',
  unitPriceCents: 65,
  vatRate: 10,
  stockTracked: true,
  minStockByLocation: {'haupt': 20000},
  externalIds: {'shop': '1001'},
));

// Goods receipt: preview first (books nothing, values only with `costs`), then book.
const items = [GoodsReceiptItem(articleId: 'rye-bread', quantity: 20000, totalCents: 2400, batch: 'C-41')];
final preview = await inventory.previewGoodsReceipt(const GoodsReceiptPreviewRequest(items: items));
final booked = await inventory.receiveGoods(const ReceiveGoodsRequest(idempotencyKey: 'shop-gr-118', items: items));
for (final w in booked.warnings) {
  print('${w.code}: ${w.message}'); // a warning, not an error: the booking took effect
}

// Checkout: reserve all or nothing, against available = onHand − reserved.
try {
  final reservation = await inventory.createReservation(const CreateReservationRequest(
    idempotencyKey: 'shop-res-1001',
    items: [ReservationItemInput(articleId: 'rye-bread', quantity: 2000)],
    reference: 'Order 1001',
    expiresInMinutes: 30,
  ));
  // Redeem it with the invoice: IssueInvoiceItemInput(reservationId: reservation.id, articleId: …)
  // or give it back: releaseReservation(ReleaseReservationRequest(idempotencyKey: …, reservationId: reservation.id))
} on KasseneckApiError catch (e) {
  for (final s in inventoryShortfalls(e)) {
    print('${s.articleId} at ${s.locationId}: ${s.available} of ${s.requested} available');
  }
}
```

- **Articles.** `createArticle`, `updateArticle` and `deactivateArticle`
  answer with the article as `getArticle` returns it. In an update only the
  named fields change; `UpdateArticleRequest(clear: {'description'})` clears a
  field (`null` on the wire). `externalIds` and `metadata` are replaced,
  `minStockByLocation` is merged per location (`{'haupt': null}` removes only
  that location). `purchasePriceMicros` needs the permission `costs`.
  `minStock` is a legacy field that triggers nothing.
- **Booking.** `receiveGoods`, `transferStock`, `recordStockLoss`,
  `changeStockCondition` and `reverseStockMovement` answer with a
  `StockOperation` (`operationId`, `movementIds`, `lotIds`, `warnings`).
  Warning codes are `inventoryWarningCodes` (`isInventoryWarningCode`).
  Catalogs: `stockLossReasons`, `withdrawalTypes`, `landedCostTypes`,
  `landedCostAllocations`, `stockConditions`.
- **Reservations.** `createReservation`, `extendReservation`,
  `releaseReservation` (all, or per position), `getReservation`,
  `listReservations` and `iterateReservations`. A `Reservation` carries
  `status` (`reservationStatuses`), `reference`, `items` with `quantity`,
  `redeemed` and `released` (`ReservationItem.open` is the rest) and
  `expiresAt`. `expiresInMinutes` is 5 to 43,200. Stock movements of type
  `reservation` have `quantityDelta: 0` and the amount in `reservedDelta`.
- **Checked before sending**, nothing else: an invalid key, a missing id, an
  integer beyond ±(2^53 − 1) (the server computes in JavaScript), an
  `expiresInMinutes` outside 5–43,200, an update without a field or with a
  `clear` the server cannot apply, a release with an empty list. All of these
  throw `KasseneckValidationError` with `kind: 'request'`.

### Variants

A variant is an ordinary article with `variantGroupId` and
`variantAttributes`: its own id, code, stock and tile at the register; it is
read, booked, reserved and invoiced like any other article. The variant group
holds what the variants share (name, attributes with their values, defaults
for new variants) and guarantees that each combination exists only once. The
writes take an `idempotencyKey` and the account switch „Lager-API
schreiben“, like every other write.

```dart
final inventory = InventoryClient(apiKey: 'kr_live_…');

// 1. Create the group with every combination (3 sizes × 2 colours = 6 variants).
final apron = await inventory.createVariantGroup(const CreateVariantGroupRequest(
  idempotencyKey: 'shop-group-3001',
  name: 'Schürze',
  attributes: [
    VariantAttribute(key: 'size', label: 'Größe', values: ['S', 'M', 'L']),
    VariantAttribute(key: 'colour', label: 'Farbe', values: ['rot', 'blau']),
  ],
  defaults: VariantGroupDefaultsInput(unitPriceCents: 2490, vatRate: 20, stockTracked: true),
  createMatrix: true,
));
// apron.variants: articleId and variantAttributes {'colour': 'rot', 'size': 'S'} per variant

// 2. The answer carries ids only. Read the articles of the group (names
//    "Schürze S rot" …, own codes) and map them to the shop's products.
final articleIdByCombination = <String, String>{};
await for (final article in inventory.iterateArticles(variantGroupId: apron.id)) {
  final attributes = article.variantAttributes!;
  articleIdByCombination['${attributes['size']}/${attributes['colour']}'] = article.id;
}

// 3. A new size later: add the value, then the variants you want.
await inventory.updateVariantGroup(UpdateVariantGroupRequest(
  idempotencyKey: 'shop-group-3001-xl',
  variantGroupId: apron.id,
  addAttributeValues: const {'size': ['S', 'M', 'L', 'XL']}, // known values are skipped
));
try {
  await inventory.addVariant(AddVariantRequest(
    idempotencyKey: 'shop-variant-3001-xl-rot',
    variantGroupId: apron.id,
    variantAttributes: const {'size': 'XL', 'colour': 'rot'},
    ean: '9001234567834', // optional: a foreign article with this code
  ));
} on KasseneckApiError catch (e) {
  if (!isInventoryError(e, 'variant_already_exists')) rethrow;
  // Exists already: link e.details['articleId'] instead.
}
```

- **Limits.** At most 3 attributes per group (keys `^[a-z0-9_]{1,32}$`,
  `__…__` is reserved), at most 30 values per attribute (1 to 30 characters,
  unique ignoring case), at most 100 combinations with `createMatrix` and at
  most 100 entries in `variants` per request, at most 250 active variants per
  group (`variant_limit`). The client does not check these before sending
  (the server may raise them); they are exported as `variantAttributesMax`,
  `variantValuesMax`, `variantMatrixMax` and `variantGroupActiveMax`. A
  request that would need more writes than fit into one operation (about 187
  external ids with 100 variants) is refused as a whole with
  `too_many_positions` and `details['field']` (`variants`, `createMatrix`, or
  `externalIds` for `addVariant`); nothing is written. Send fewer variants and
  add the rest with `addVariant`.
- **Order.** `attributes` keeps the order of the group: it decides the default
  name "group value1 value2" and the matrix (the first attribute runs
  outermost). `variantAttributes` on articles, in `VariantGroup.variants` and
  in webhooks comes with its keys **sorted by code point**, not in attribute
  order; compare by key, never by position. Values are stored trimmed and in
  Unicode NFC; a variant's value must match a listed value exactly (case and
  spaces are not adjusted), otherwise `invalid_variant_attributes` names the
  `field` (`inventoryFieldErrors(error)`).
- **Variants are articles.** `addVariant` answers with the `Article` as
  `createArticle` does. A `VariantInput` takes the fields of
  `CreateArticleRequest` (the name is optional); fields it does not name are
  filled from the group defaults **at creation only**: changing the group name
  or defaults later changes no existing variant (use `updateArticle`). A
  variant is never moved to another group, and an existing article never
  becomes a variant.
- **Changing a group.** `updateVariantGroup` changes only the named fields:
  `name`, `defaults` as a partial update (`VariantGroupDefaultsInput(clear:
  {'unitPriceCents'})` clears one default, `clearDefaults: true` all of them),
  `addAttributeValues`. `active: false` deactivates the group and every
  variant (codes and external ids become free), stands alone and is final; a
  deactivated group answers every other change and `addVariant` with
  `variant_group_inactive`. After `ErrorOutcome.unknown` simply repeat it,
  also with a new key; it completes an interrupted run. `deactivateArticle` on
  one variant of an active group takes it out of `variants` and frees its
  combination.
- **After `unknown`.** As with every write: resend with the **same**
  `idempotencyKey`. A new key would create the group a second time (the
  combination check is per group). `variant_already_exists` on `addVariant`
  carries `details['articleId']` of the existing variant.
- **Reading.** `getVariantGroup`, `listVariantGroups(active:, updatedSince:,
  limit:, cursor:)` and `iterateVariantGroups`. A `VariantGroup` carries
  `attributes` (`VariantAttribute`: `key`, `label`, `values`), `defaults`
  (`VariantGroupDefaults`, only the fields with a default), `active`,
  `variants` (`VariantGroupMember`: `articleId`, `variantAttributes`) and the
  times; the articles themselves come from
  `listArticles(variantGroupId: …)`.
- **Events.** `InventoryVariantGroupEvent` (`variant_group.created`,
  `variant_group.updated`) carries the group as `getVariantGroup` returns it.
  `updated` fires only on a visible change; creating a variant also sends
  `article.created`, deactivating the group one `variant_group.updated` and
  one `article.deactivated` per variant. Deliveries can overtake each other:
  keep a group state only if its `updatedAt` is later than the stored one.
  Without webhooks, `listVariantGroups(updatedSince: …)` and
  `listArticles(variantGroupId: …, updatedSince: …)` are sorted by
  `updatedAt` ascending and include the boundary.
- **Checked before sending**, nothing else: an invalid key, an empty
  `variantGroupId`, `createMatrix: true` together with `variants`, an update
  without a field, `active` other than `false` or not alone, `defaults`
  together with `clearDefaults`, a `clear` naming another field or a field
  that is also set, and integers beyond ±(2^53 − 1). Fractions and a missing
  `variantAttributes` are ruled out by the types.

## RKSV details

Every receipt is chained and signed (ES256, JWS) and comes with its
machine-readable QR payload, as the RKSV requires. A failed signature unit is
detected (`receipt.signatureSuccess`, `receipt.isSigFailed`) and marked on the
receipt; the backend handles the follow-up (see the obligations table above).

## Glossary

German RKSV terms used in the API and on the receipts:

| German | English |
| --- | --- |
| Beleg | receipt |
| Startbeleg | start receipt |
| Nullbeleg | zero receipt |
| Monatsbeleg | monthly receipt |
| Jahresbeleg | annual receipt |
| Schlussbeleg | final receipt |
| Storno | cancellation |
| Signaturerstellungseinheit | signature creation unit |
| DEP (Datenerfassungsprotokoll) | data capture log (DEP) |
| Kassennachschau | cash register audit |
| Belegerteilungspflicht | obligation to issue receipts |
| Registrierkasse | fiscal cash register |
| Umsatzzähler | turnover counter |
| Außerbetriebnahme | decommissioning |
| Ausfall der Signatureinheit | signature unit failure |
| Rechnung | invoice |
| USt | VAT |

FinanzOnline (the tax authority's online portal) and BMF (Federal Ministry of
Finance) are names and stay as they are.

## Versioning

The package follows semantic versioning. What changed and when is in the
[CHANGELOG](CHANGELOG.md); entries from 10.0.0 on are in English, older ones in
German. The frozen lines 8.x and 9.x live on the branches `release/8.x` and
`release/9.x`.

## License

MIT, see [LICENSE](LICENSE).

---

**Kasseneck** is a product of
[Kreiseck Software Solutions](https://kreiseck.com) from Salzburg, Austria: apps,
POS systems and automation. Questions about the API, custom integrations or a
partnership: [kasseneck.at/kontakt](https://kasseneck.at/kontakt).
