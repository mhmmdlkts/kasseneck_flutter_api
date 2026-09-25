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

## Contents

- [Quick start](#quick-start)
- [What a fiscal cash register in Austria has to do](#what-a-fiscal-cash-register-in-austria-has-to-do)
- [Features](#features)
- [Requirements and platforms](#requirements-and-platforms)
- [Three ways to authenticate](#three-ways-to-authenticate)
- [Selling: items, amounts, vouchers, tips](#selling-items-amounts-vouchers-tips)
- [Cancellations (Storno)](#cancellations-storno)
- [Sending a receipt by email](#sending-a-receipt-by-email)
- [Error handling](#error-handling)
- [Card payments](#card-payments)
- [Printing and displaying receipts](#printing-and-displaying-receipts)
- [Reports, receipt history, FinanzOnline status](#reports-receipt-history-finanzonline-status)
- [Invoices (invoice API)](#invoices-invoice-api)
- [RKSV details](#rksv-details)
- [Glossary](#glossary)

## Quick start

```yaml
dependencies:
  kasseneck_api: ^9.1.0
```

```bash
flutter pub get
```

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';

final kasseneck = KasseneckApi(
  apiKey: 'YOUR_API_KEY',                  // kr_live_… or kr_test_…
  cashregisterToken: 'YOUR_CASHBOX_TOKEN', // cb_live_… or cb_test_…
);

// A cash sale with two items. Prices are integer cents (320 = EUR 3.20).
final receipt = await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.cash,
  customerDetails: ['Max Mustermann'],
  items: [
    KasseneckItem(name: 'Coffee', quantity: 2, vat: VatRate.vat20,      priceCents: 320),
    KasseneckItem(name: 'Bread',  quantity: 1, vat: VatRate.vat4komma9, priceCents: 240),
    // If you only have euro doubles: KasseneckItem.euro(..., singlePrice: 3.20)
  ],
);

print('Receipt ${receipt?.receiptId}, signed: ${receipt?.signatureSuccess}');
```

`sellReceipt` returns a signed receipt (*Beleg*) that is already chained into the
DEP. Models and enums live in their own files; import the ones you need
(`models/…`, `enums/…`). A runnable example is in
[`example/example.dart`](example/example.dart).

You need a Kasseneck **API key** and a **cashbox token**. Ask for them via
[kasseneck.at/kontakt](https://kasseneck.at/kontakt).

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
  users (`register.dart`, `kasse.dart`).
- **Invoice API:** invoices under § 11 UStG (not receipts), customers,
  cancellation and credit notes, PDF and e-invoice XML (UBL or CII).

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
| `KasseneckApi` | `kasseneck_api.dart` | API key as bearer + `cashregister-token` header, base URL `https://api.kasseneck.at/v1` | POS devices and apps: selling, cancelling, reports, card payments |
| `RegisterClient`, `RegisterReceiptClient` | `register.dart`, `kasse.dart` | pairing code, then device secret + PIN, then a Firebase ID token and a register session, base URL `https://kasse.kasseneck.at/api` | Register apps where staff log in personally (permissions per user) |
| `RechnungApi` | `rechnung.dart` | API key only, no cashbox token | Invoices and customers, typically from a server |

The register login in short: `RegisterClient().pairRegisterDevice(code: …)`
exchanges a pairing code from the Kasseneck panel for a permanent device
identity; `registerUserLogin(…)` or `registerPinLogin(…)` returns a
`customToken` and a `sessionId`. Your app signs in to Firebase Auth with the
`customToken` (this package does not depend on `firebase_auth`) and builds the
session transport:

```dart
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/register.dart';

final transport = RegisterTransport(
  idToken: () async => firebaseUser.getIdToken(),  // asked on every call
  sessionId: () async => currentSessionId,         // renew every 30 s, lives 90 s
  cashregisterId: device.cashregisterId,
);
final client = RegisterReceiptClient(transport);
final receipt = await client.verkaufen(
  positionen: [KasseneckItem(name: 'Coffee', quantity: 1, vat: VatRate.vat20, priceCents: 320)],
  zahlungsart: KeckPaymentMethod.cash,
);
```

`RegisterSessionClient.aus(transport).renewRegisterSession()` keeps the session
alive. Nothing on this path is retried automatically: a receipt is not safely
repeatable.

## Selling: items, amounts, vouchers, tips

**Amounts are integer cents.** `KasseneckItem.priceCents` is the gross unit
price in cents, `quantity` a whole number. `KasseneckItem.euro(singlePrice: …)`
converts a euro double once. Euro doubles appear only where an external API
requires them (hobex, SumUp).

`sellReceipt` takes, besides `items` and `paymentMethod`:

- `vouchers`: `KeckVoucher(action: VoucherAction.sell or .redeem, type: VoucherType.value or .promo, valueCents: …)`.
  Promo vouchers can only be redeemed, only one per receipt and not together
  with other vouchers (`checkVoucherCombinationError` returns the reason).
- `tip`: `KeckTip.fuer(registerUserId, cents: 200)` or `KeckTip(cents: …, recipients: …)`.
  The backend books it as its own line; `listTipRecipients()` returns the people
  a tip can be assigned to. A receipt needs at least one item for a tip.
- `customerDetails`, `legalMessage`: extra lines on the receipt.
- `creditCardProvider`, `cardPaymentId`, `cardPaymentData`: see
  [Card payments](#card-payments).

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
final result = await kasseneck.stornieren(
  cashregisterId: original.cashregisterId,
  originalReceiptId: original.receiptId,
  grund: 'fehleingabe',                 // key from stornogruende
  positionen: [(index: 0, menge: 1)],   // omit = cancel everything that is left
  anmerkung: 'Customer wanted one',     // internal note, max 200 chars, never printed
);
result.beleg;       // the signed cancellation receipt
result.restmengen;  // remaining quantity per line of the original

// Register session (package:kasseneck_api/kasse.dart)
final result2 = await client.stornieren(originalReceiptId: id, grund: 'fehleingabe');
```

- Reasons (`stornogruende`): `fehleingabe` (wrong entry), `kunde_storniert`
  (customer cancelled), `falsche_zahlart` (wrong payment method),
  `doppelt_erfasst` (entered twice), `sonstiges` (other). The German label is
  printed on the receipt.
- An **empty** `positionen` list is an error, so that a broken partial
  cancellation never silently becomes a full one.
- `KasseneckApi.stornieren` also accepts `kartenanbieter`, `kartenzahlungId` and
  `kartenzahlungsdaten` for the **refund** at the terminal (only with card as the
  refund method). `RegisterReceiptClient.stornieren` has no card arguments.
- `restmengen(receipt)` (from `kasse.dart`) computes remaining quantities
  locally from the original's `cancellations`; the server has the final word.

**Vouchers.** A value voucher is only mirrored on a full cancellation (without
`positionen`); it cannot be split. A promo voucher is already part of the
original's turnover, so **every** cancellation takes it back in proportion to the
cancelled quantity: 3 × EUR 10 with a EUR 6 discount is EUR 8 per piece, so the
cancellation shows "−10,00" plus a line "Gutschein-Ausgleich +2,00" (voucher
adjustment). What a cancellation granted is stored on its entry in
`receipt.cancellations` as `promoAdjustmentCents` (cents per VAT bucket).

**Deprecated:** `KasseneckApi.cancelReceipt` and `createCancelReceipt` use the
old path via `createReceipt` without a reference to the original: no remaining
quantities, no protection against cancelling twice, vouchers are not taken back.
The backend still accepts them but answers with a deprecation notice.

## Sending a receipt by email

The guest gives an address at the counter and receives a **link to the public
receipt page**, no PDF attachment. That page offers a PDF. The receipt document
itself stays byte-identical (it is part of the DEP); the backend logs the
delivery separately.

```dart
// Register session (package:kasseneck_api/kasse.dart)
final sent = await client.belegSenden(fullReceiptId: receipt.fullReceiptId, an: 'guest@example.com');
// API key (package:kasseneck_api/kasseneck_api.dart)
final sent2 = await kasseneck.belegSenden(fullReceiptId: receipt.fullReceiptId, an: 'guest@example.com');

sent.to;   // normalised address as logged by the backend
sent.at;   // ISO timestamp in Vienna time
sent.via;  // 'eigen' (business mailbox), 'plattform' or 'plattform-fallback'
```

With the API key, the cashbox token decides which register is meant. Error codes
(`belegMailFehlercodes`): `adresse_ungueltig` (let the user correct it),
`zu_oft` (the backend allows five mails per receipt in 24 hours and 30 per
register per hour; try later), `versand_fehlgeschlagen` (nothing was sent, a new
attempt is fine), `beleg_nicht_gefunden` (unknown receipt **or** one of another
register; the backend answers both the same way). Only the backend validates the
address.

## Error handling

Decide on the **error code**, never on the message text. The messages are German
and may change.

```dart
try {
  await kasseneck.stornieren(cashregisterId: crId, originalReceiptId: id, grund: 'fehleingabe');
} on KasseneckApiError catch (e) {
  switch (e.code) {
    case 'bereits_storniert': // show as cancelled, disable the button
    case 'menge_ueber_rest':  // reload remaining quantities (someone was faster)
    case 'nur_eigene_belege': // ask the manager
      break;
    default:
      rethrow;
  }
}
```

The error types are exported from `kasseneck_api.dart` and `rechnung.dart`.
`kasse.dart` exports only `KasseneckReceiptFormatError`; to catch the others on
the register path, import `kasseneck_api.dart` as well.

| Type | Meaning |
| --- | --- |
| `KasseneckApiError` | The backend refused (`code`, `message`, `details`). Code catalogues: `stornoFehlercodes`, `belegMailFehlercodes`, `invoiceErrorCodes`. |
| `KasseneckValidationError` | A request was rejected before sending (`'request'`), or a response lacks a required field (`'response'`, may carry `receiptId`). |
| `KasseneckHttpError` | Transport problem: `reason` is e.g. `KasseneckHttpError.zeitablauf` (timeout), `KasseneckHttpError.netz` (network) or `'not-json'`. |
| `KasseneckReceiptFormatError` | The receipt was issued and signed, but the response could not be read. It carries the `receiptId`; fetch the receipt with `getReceipt`. **Do not sell again.** |

`KasseneckApi.sellReceipt` and `zeroReceipt` behave differently from the newer
calls: invalid input throws `ArgumentError`, a refusal by the backend or a
non-200 HTTP status throws a plain `Exception`, and a request that exceeds
`signatureTimeout` (default 90 s) throws a `TimeoutException`. A timeout does not
mean the receipt failed, because the backend may have signed it already. Check
the receipt history before selling again.

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
| **any other terminal** (for example GP Tom or myPOS) | pass your terminal's result as `creditCardProvider`, `cardPaymentId`, `cardPaymentData`; it is stored and printed on the receipt |

hobex amounts are euros (`amount: 12.50`), as the hobex API expects.

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
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider, // hobexHps
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
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
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider,
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
  items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

`HobexCloudPayments` has no `refund()` or `cancel()`. A cloud refund still goes
through the raw call `kasseneck.hobexRefund(...)`, which returns a `bool` and does
not resolve its outcome.
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
import 'package:kasseneck_api/printing.dart'; // KeckPrinter, KeckPaperSize, QrPrintMode, QrModulGroesse, …

// Recommended: one printer object per device. Returns a KeckPrintResult instead
// of throwing, and reports a missing QR code (qrFehler).
final printer = KeckPrinter.wifi(ip: '192.168.0.50', size: KeckPaperSize.mm80);
// or: KeckPrinter.bluetooth(address: 'AA:BB:CC:DD:EE:FF', size: KeckPaperSize.mm58)
final printed = await printer.printReceipt(receipt);
if (printed.qrFehler != null) {
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
// qrGroesse is a cap, never an enlargement beyond what fits:
await printer.printReceipt(receipt, qrGroesse: QrModulGroesse.gross);
```

The older static path still works: `kasseneck.initWifiPrinter(ip, size)` or
`kasseneck.initBluetoothPrinter(printerAddress: …)`, then
`receipt.printReceiptWifi()` or `receipt.printReceiptBluetooth(qrMode: …, qrGroesse: …)`.
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
await LogoService.dauerhaftAblegen();

// Screen (widget from kasseneck_api.dart)
KeckBelegBlattWidget(
  layout: receipt.layout!,
  logoUrl: receipt.logoUrl,
  logoStufe: receipt.logoStufe,
  marke: receipt.showKreiseckLogo,
);

// Paper, with the same logo (printing.dart)
final logo = await ladeDruckLogo(receipt.logoUrl, receipt.logoStufe, KeckPaperSize.mm80);
final paper = await KeckPrinterService.getPaperFromReceipt(receipt, KeckPaperSize.mm80,
    logo: logo, marke: receipt.showKreiseckLogo);
```

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
import 'package:kasseneck_api/rechnung.dart';

final invoices = RechnungApi(apiKey: 'kr_live_…');

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
} on KasseneckApiError catch (e) {
  switch (rechnungFehlerCode(e)) {
    case 'validation':
      for (final f in rechnungFeldFehler(e)) {
        print('${f.field}: ${f.message}');
      }
    case 'invoice_setup_incomplete':
      print(e.details['missing']);
    default:
      rethrow;
  }
}
```

After a timeout (`KasseneckHttpError.zeitablauf`), issue again **with the same
`idempotencyKey`**: the answer then carries `replayed: true` and the same
invoice. The same key with different data gives `idempotency_conflict`.
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

**Computing totals in advance.** `rechnungSummen` computes the totals exactly as
the server does, offline. `previewInvoice` asks the server: a dry run that checks
like issuing (customer, tax case, required fields) but finalises nothing and does
not consume the `idempotencyKey`.

```dart
const items = [
  InvoiceItemInput(description: 'Manicure', quantity: 1, unitPriceCents: 1479, vatRate: 20),
  InvoiceItemInput(description: 'Polish', quantity: 1, unitPriceCents: 1500, vatRate: 20),
];
final totals = rechnungSummen(items, 'gross');
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
(`steuerfreieFaelle`, e.g. `igLieferung`), pass it as the third argument of
`rechnungSummen`, otherwise the function computes tax the invoice does not show;
`previewInvoice` names the case. Issuing is binding: customer or account may
change between preview and invoice. Totals are positive for credit notes too;
the sign is in the document type (`docType: 'GU'`).

**Notices are always a list.** `notice` on `issueInvoice`, `previewInvoice` and
`recordInvoicePayment` is a `List<InvoiceNotice>`, empty if there is nothing to
say. An intra-EU supply carries `recapitulative_statement_due`, a cash-paid
invoice `cash_receipt_required`. Decide on the code, not the text:

```dart
if (issued.notice.any((n) => n.code == 'cash_receipt_required')) {
  // Cash sale: issue a receipt through the fiscal cash register
}
```

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
[CHANGELOG](CHANGELOG.md) (in German).

## License

MIT, see [LICENSE](LICENSE).

---

**Kasseneck** is a product of
[Kreiseck Software Solutions](https://kreiseck.com) from Salzburg, Austria: apps,
POS systems and automation. Questions about the API, custom integrations or a
partnership: [kasseneck.at/kontakt](https://kasseneck.at/kontakt).
