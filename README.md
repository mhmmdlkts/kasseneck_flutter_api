<p align="center">
  <img src="doc/kreiseck_logo.png" alt="Kreiseck — Software Solutions" width="300">
</p>

<h1 align="center">Kasseneck Flutter API</h1>

<p align="center">
  <b>The Austrian RKSV-compliant cash register, right inside your Flutter app.</b><br>
  Issue signed receipts, take card payments and print — in a few lines of Dart.
</p>

<p align="center">
  <a href="https://pub.dev/packages/kasseneck_api"><img src="https://img.shields.io/pub/v/kasseneck_api?color=930C0C&label=pub" alt="pub version"></a>
  <a href="https://pub.dev/packages/kasseneck_api/score"><img src="https://img.shields.io/pub/points/kasseneck_api?color=930C0C" alt="pub points"></a>
  <img src="https://img.shields.io/badge/platform-Android-930C0C" alt="platform">
  <img src="https://img.shields.io/badge/RKSV-compliant-930C0C" alt="RKSV compliant">
  <a href="https://kreiseck.com"><img src="https://img.shields.io/badge/by-Kreiseck-111111" alt="by Kreiseck"></a>
</p>

---

`kasseneck_api` is the official Flutter client for **Kasseneck** — a fully **RKSV-compliant**
(Austrian _Registrierkassensicherheitsverordnung_) point-of-sale backend by
**[Kreiseck Software Solutions](https://kreiseck.com)**. It takes care of the signed
_Datenerfassungsprotokoll_, card-payment terminals, receipt printing and PDF reports, so you
can focus on your app.

> 🔑 **You need an API key & a cashregister token to operate a register.**
> Request yours at **[office@kreiseck.com](mailto:office@kreiseck.com)** · **[kreiseck.com](https://kreiseck.com)**

## ✨ Features

- 🧾 **RKSV receipts** — standard, cancellation, zero & training; signed JWS chain + QR code
- 💶 **All Austrian VAT rates** — incl. the new **4.9 % _Grundnahrungsmittel_** rate (from 1 Jul 2026)
- 🪙 **Exact money** — amounts are integer **cents** internally (no floating-point drift)
- 💳 **Card payments out of the box** — Hobex (Cloud & on-terminal **HPS**), myPOS, GP Tom, SumUp — **and any other method** via `CreditCardProvider.custom`
- 🎟️ **Vouchers** — value & promo, sell & redeem, with proportional VAT split
- 💛 **Tips** — per register user, cash or card; staff tips run as 0 % pass-through, owner tips as revenue split across the receipt's VAT rates
- 🖨️ **Printing** — Bluetooth & Wi-Fi (ESC/POS) plus the myPOS built-in printer
- 📱 **Drop-in receipt widget** for on-screen display
- 📊 **Reports & invoices** — daily / monthly PDF
- 🔗 **Stripe payment links** for remote & online payments

## 🧩 Requirements

- Flutter · Dart `>= 3.6`
- A Kasseneck **API key** + **cashregister token** (→ Kreiseck)
- An **Android** device/terminal for card payments & Bluetooth printing

## 📦 Installation

```yaml
dependencies:
  kasseneck_api: ^5.0.0
```

```bash
flutter pub get
```

## 🚀 Quick start

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';

final kasseneck = KasseneckApi(
  apiKey: 'YOUR_API_KEY',
  cashregisterToken: 'YOUR_CASHREGISTER_TOKEN',
);

// A cash sale with two items — prices are integer cents (320 = € 3.20)
final receipt = await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.cash,
  customerDetails: ['Max Mustermann'],
  items: [
    KasseneckItem(name: 'Coffee', quantity: 2, vat: VatRate.vat20,      priceCents: 320),
    KasseneckItem(name: 'Bread',  quantity: 1, vat: VatRate.vat4komma9, priceCents: 240),
    // or, if you have euro doubles: KasseneckItem.euro(..., singlePrice: 3.20)
  ],
);

print('Receipt ${receipt?.receiptId} — signed: ${receipt?.signatureSuccess}');
```

> 💡 Models & enums live in their own files — import the ones you use
> (`models/…`, `enums/…`). Payment, refund, zero & training receipts all run through the
> same `KasseneckApi` instance. **Cancellations go through `RegisterReceiptClient.stornieren`**
> (see below); `cancelReceipt`/`createCancelReceipt` on `KasseneckApi` are the deprecated old path.

## ↩️ Cancellations (Storno)

A cancellation is a **new signed receipt** that reverses an existing one — fully or in parts.
The register client (`package:kasseneck_api/kasse.dart`, `RegisterReceiptClient`) talks to the
backend's `cancelReceipt` endpoint; the server negates the lines, checks remaining quantities and
permissions, links both receipts and prints the reference line on the cancellation receipt.

```dart
import 'package:kasseneck_api/kasse.dart';

final ergebnis = await client.stornieren(
  originalReceiptId: 'KASSE1-ID-42',
  grund: 'fehleingabe',                       // catalogue: stornogruende
  positionen: [(index: 0, menge: 1)],         // omit = cancel everything that is left
  anmerkung: 'Kunde wollte nur eine',         // internal note, never printed
);
ergebnis.beleg;        // the signed cancellation receipt
ergebnis.restmengen;   // what is still open per line of the original
```

**Decide on the error code, never on the message.** Every business error of `cancelReceipt`
carries `KasseneckApiError.code` from `stornoFehlercodes` — e.g. `bereits_storniert`,
`menge_ueber_rest`, `nur_eigene_belege`. The German `message` is for display and may change.

```dart
try {
  await client.stornieren(originalReceiptId: id, grund: 'fehleingabe');
} on KasseneckApiError catch (e) {
  switch (e.code) {
    case 'bereits_storniert': // show the receipt as cancelled, disable the button
    case 'menge_ueber_rest':  // reload remaining quantities (someone was faster)
    case 'nur_eigene_belege': // ask the owner
      break;
    default:
      rethrow;
  }
}
```

**Vouchers.** A value voucher is mirrored only on a full cancellation (no `positionen`) — it is
indivisible. A promo (discount) voucher is already part of the original's turnover; **every**
cancellation takes it back in proportion to the cancelled quantity: 3 × € 10 with a € 6 discount
is € 8 per piece, so the cancellation receipt shows "−10,00" plus a line "Gutschein-Ausgleich
+2,00". What each cancellation granted is stored on its entry in `receipt.cancellations` as
`promoAdjustmentCents` (cents per VAT bucket) — the register can show it, it never has to compute it.

Before offering a cancellation, `restmengen(beleg)` gives the remaining quantities from the
original's `cancellations` list; the server remains the source of truth.

## 💳 Card payments

Card payments work **out of the box** with several terminals — and you're **never locked in**:

| Method | How |
|---|---|
| **Hobex Cloud** (recommended) | `HobexCloudPayments` — `pay(...)` with a resolved, three-way outcome |
| **Hobex HPS** (local terminal, recommended) | `HpsPayments` — `pay`/`refund`/`cancel`, same three-way outcome |
| **myPOS · GP Tom · SumUp** | supported & rendered on the receipt |
| **Any other terminal/method** | `CreditCardProvider.custom` — just pass your own card data |

Whatever terminal you use, hand the result to `sellReceipt(...)` as `cardPaymentData` and it is
stored and printed on the receipt.

**Why `HpsPayments`/`HobexCloudPayments` instead of calling the terminal directly:** a card
payment has three possible outcomes, not two — approved, definitely declined, or *unknown*
(the request timed out, the connection dropped, the terminal never answered). Treating "unknown"
as "declined" and retrying is how a customer gets charged twice for the same purchase. Both
classes fix the transaction id **before** the first network call and, if the first answer is
lost, resolve the same id against the terminal/cloud instead of silently starting a new attempt
— so a lost response ends in `CardPaymentOutcome.unresolved` (keep the id, resolve later) rather
than being guessed at.

<details>
<summary><b>Example — local Hobex terminal (HPS) → signed receipt</b></summary>

```dart
import 'package:kasseneck_api/hobex_hps.dart'; // HpsClient, HpsPayments, HpsResult, CardPaymentOutcome, HobexReceipt

final hps = HpsPayments(HpsClient(tid: '3600335')); // TID without leading zero

// The id is fixed BEFORE the request goes out — persist it right away so a
// lost response can still be traced back and resolved instead of retried blind.
final transactionId = HpsClient.newTransactionId();

final result = await hps.pay(amount: 12.50, transactionId: transactionId);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // proceed below
  case CardPaymentOutcome.declined:
    return; // definitely no money moved — safe to retry
  case CardPaymentOutcome.unresolved:
    // Not settled within the resolve budget (90 s by default, configurable).
    //
    // Do NOT retry here. Measured on a real terminal (2026-08-26): passing the same
    // transactionId again starts a SECOND card flow — the terminal does not recognize
    // it as the same transaction. A retry is a real second charge, not a safe repeat.
    //
    // Keep `transactionId`, resolve the outcome first — `HpsClient.transactionStatus(...)`
    // once the terminal answers again — and act only on a known outcome.
    // doc/kartenzahlung.md documents what each response code actually means.
    return;
}

// Adapt the terminal result, then create the signed receipt.
final card = HobexReceipt.fromHps(result.response!);
await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider, // hobexHps
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
  items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

Also available: `hps.refund(...)`, `hps.cancel(...)` — same resolved outcome. Pass an `HpsObserver`
callback to the `HpsPayments` constructor to log requests, failures and how an outcome was resolved.
</details>

<details>
<summary><b>Example — Hobex Cloud → signed receipt</b></summary>

```dart
import 'package:kasseneck_api/kasseneck_api.dart'; // HobexCloudPayments, HobexCloudResult, CardPaymentOutcome

final cloud = HobexCloudPayments(kasseneck);

// Same rule as HPS: the id is fixed by the caller before the request goes out.
final transactionId = KasseneckApi.newHobexTransactionId();

final result = await cloud.pay(transactionId: transactionId, amount: 12.50);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // proceed below
  case CardPaymentOutcome.declined:
    return; // definitely no money moved — safe to retry
  case CardPaymentOutcome.unresolved:
    // Not settled within the resolve budget. Do NOT retry blindly — keep
    // `transactionId` and resolve later, see the HPS example above.
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

`HobexCloudPayments` has no `cancel()` — a Cloud refund still goes through the raw
`kasseneck.hobexRefund(...)` (see below), unresolved just like the plain call.
</details>

<details>
<summary><b>Low-level access — raw <code>HpsClient</code> / <code>kasseneck.hobexPay(...)</code></b></summary>

Both the local `HpsClient` (`import 'package:kasseneck_api/hobex_hps.dart';`) and the Cloud calls
`kasseneck.hobexPay(...)` / `hobexRefund(...)` remain available directly, for full control over the
request. **Neither does the outcome resolution above:** a raw call that never gets an answer stays
unresolved forever — building a payment flow directly on top of it means re-solving the exact
problem `HpsPayments`/`HobexCloudPayments` already solve, with a real risk of getting the "was it
charged?" question wrong under exactly the conditions (timeout, dropped connection) where getting
it wrong is expensive. Reach for the raw client only when you need something the resolved wrapper
doesn't expose (e.g. `hps.diagnosis()`, `hps.transactionStatus(...)`).
</details>

## 🖨️ Printing

```dart
// Bluetooth (ESC/POS)
await kasseneck.initBluetoothPrinter(printerAddress: 'AA:BB:CC:DD:EE:FF');
await receipt!.printReceiptBluetooth();

// QR garbled or missing? Printers differ in which command they support:
await receipt.printReceiptBluetooth(qrMode: QrPrintMode.imageBitImage); // or .native

// Wi-Fi
await kasseneck.initWifiPrinter('192.168.0.50', KeckPaperSize.mm80);
await receipt.printReceiptWifi();

// Open the cash drawer
await KasseneckApi.openCashDrawer();
```

## 📱 On-screen receipt

A ready-made widget renders the full receipt (logo, items, VAT table, QR, card details):

```dart
KeckReceiptWidget(receipt: receipt);
```

## 📊 Reports & invoices

```dart
final monthly = await kasseneck.downloadMonthlyReport(ReportMonth.now()); // Uint8List (PDF)
final daily   = await kasseneck.downloadDailyReport(DateTime.now());
final history = await kasseneck.getReceipts(start, end);
```

## 🇦🇹 RKSV compliance

Every receipt is chained and signed (ES256 / JWS) and exposed as the machine-readable QR
payload, exactly as required by the Austrian RKSV. Signature-device outages are detected
(`receipt.signatureSuccess` / `receipt.isSigFailed`) and printed on the receipt.

## 🗂️ Versioning

This package follows semantic versioning — see the [CHANGELOG](CHANGELOG.md).
Latest: **5.0.0** — resolved card-payment outcomes (`approved` / `declined` / `unresolved`), transaction id fixed before the first request, and hardened receipt parsing. **Breaking** — see the [CHANGELOG](CHANGELOG.md).

## 💬 Support

**Kreiseck Software Solutions** — [office@kreiseck.com](mailto:office@kreiseck.com) · [kreiseck.com](https://kreiseck.com)

## 📄 License

See [LICENSE](LICENSE).
