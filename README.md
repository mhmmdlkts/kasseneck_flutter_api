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
  kasseneck_api: ^3.0.0
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
> (`models/…`, `enums/…`). Payment, refund, cancellation, zero & training receipts all run
> through the same `KasseneckApi` instance.

## 💳 Card payments

Card payments work **out of the box** with several terminals — and you're **never locked in**:

| Method | How |
|---|---|
| **Hobex Cloud** | `kasseneck.hobexPay(...)` / `hobexRefund(...)` |
| **Hobex HPS** (local terminal) | `import 'package:kasseneck_api/hobex_hps.dart';` → `HpsClient` |
| **myPOS · GP Tom · SumUp** | supported & rendered on the receipt |
| **Any other terminal/method** | `CreditCardProvider.custom` — just pass your own card data |

Whatever terminal you use, hand the result to `sellReceipt(...)` as `cardPaymentData` and it is
stored and printed on the receipt.

<details>
<summary><b>Example — local Hobex terminal (HPS) → signed receipt</b></summary>

```dart
import 'package:kasseneck_api/hobex_hps.dart'; // HpsClient, TransactionResponse, HobexReceipt

final hps = HpsClient(tid: '3600335'); // TID without leading zero

// 1) Charge the card on the terminal
final res = await hps.payment(amount: 12.50);
if (!res.isApproved) return; // declined -> res.responseCode / res.responseText

// 2) Adapt the terminal result, 3) create the signed receipt
final card = HobexReceipt.fromHps(res);
await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider, // hobexHps
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
  items: [KasseneckItem(name: 'Lunch', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

Also available: `hps.refund(...)`, `hps.cancel(...)`, `hps.transactionStatus(...)`,
`hps.diagnosis()`. A **declined** payment is not an exception — it's `res.isApproved == false`.
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
Latest: **3.0.1** — integer-cent money (exact arithmetic), QR print modes, resilient report parsing.

## 💬 Support

**Kreiseck Software Solutions** — [office@kreiseck.com](mailto:office@kreiseck.com) · [kreiseck.com](https://kreiseck.com)

## 📄 License

See [LICENSE](LICENSE).
