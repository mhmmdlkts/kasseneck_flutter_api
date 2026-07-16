## 4.5.0
- **`ViennaTime`: Geschäftszeitzone Europe/Vienna** (`package:kasseneck_api/services/vienna_time.dart`). Der Kasseneck-Server liefert Beleg-Timestamps als Wiener Wanduhrzeit ohne Offset; auf Geräten mit fremder Zeitzone (z. B. im Ausland) verrutschten dadurch Beleg- und Buchungs-Tage gegeneinander. `ViennaTime` rechnet deterministisch per EU-Sommerzeitregel (letzter Sonntag März/Oktober, 01:00 UTC — kein tz-Paket nötig): `fromWallClock`/`toWallClock`, `parseServerTimeStamp`, `dayKey`, `now`/`today`, `deviceDiffersFromVienna`.
- `KasseneckReceipt.timeStamp` ist jetzt immer ein echter Zeitpunkt (UTC): Server-Timestamps werden beim Parsen als Wiener Wanduhrzeit interpretiert (`ViennaTime.parseServerTimeStamp`); `toReceiptJson` serialisiert UTC mit `Z` (Roundtrip-kompatibel, alte naive Strings werden weiterhin korrekt gelesen). `readableTime` zeigt unverändert Wiener Zeit — jetzt auch bei fremder Geräte-Zeitzone.
- `ReportMonth.now()` bestimmt den aktuellen Monat nach Wiener Zeit.

## 4.4.0
- **Unified `KeckPrinter` with a `PrinterTransport` abstraction.** New high-level printer facade that separates ESC/POS byte building from transport, replacing reliance on global printer state for new code. Ships two transports — `WifiTransport` (raw TCP, port 9100) and `BluetoothTransport` (its own `BluetoothDevice`, no shared global device) — and is USB-ready via the public `PrinterTransport` interface. Convenience factories `KeckPrinter.wifi(...)` / `KeckPrinter.bluetooth(...)`, plus DI-friendly `KeckPrinter(transport)`. High-level ops `printReceipt`/`printText`/`printQr`/`printBarcode`/`cut`/`openDrawer`/`feed`/`printJob`/`printRawBytes` each return a `KeckPrintResult` (never throw). All exported from `package:kasseneck_api/printing.dart`. Backward compatible: the static `KeckPrinterService` API is unchanged — the Bluetooth send logic (MTU negotiation, discovery, chunking, flow control) was extracted into a shared helper (`writeToBluetoothDevice`), behaviour identical.

## 4.3.0
- **1D barcode support** in the vendored ESC/POS engine: `EscPosGenerator.barcode(type, data, {align, height, width, hri})` and the fluent `CustomPrintJob.barcode(...)`. Emits GS k form 2 (length-prefixed) with the symbologies UPC-A, UPC-E, EAN-13, EAN-8, CODE39, ITF, CODABAR, CODE93 and CODE128 (auto code-set B — `{B` is prepended unless the data already starts a code-set sequence), plus height (GS h), width (GS w) and HRI position (GS H) options. `BarcodeType` and `BarcodeHri` are exported from `package:kasseneck_api/printing.dart`. This closes the last gap vs. esc_pos_utils_plus — the print stack is now fully self-contained.

## 4.2.0
- **Crisp image QR:** the image-based QR (`addQrCodeAsImage`, used by the imageRaster/bitImage print modes) is now rasterized directly from the QR module matrix with an integer per-module scale and no anti-aliasing — pure black/white pixels, sharp by construction. This replaces the previous `QrPainter → PNG encode/decode` path, whose non-integer pixel size (280 px over a variable module count) produced fringed edges and a larger image that was slow over Bluetooth; the new bitmap is smaller and faster to send. The native QR command (`addQrCode`) and the Bluetooth send path are unchanged.

## 4.1.1
- Cleans up the WiFi raw-print API from 4.1.0: dropped the unused `size` parameter (raw bytes are already rendered), renamed the result type `PrintResult` → **`KeckPrintResult`** (avoids clashing with app-level `PrintResult` types), documented that `success` means *sent* (bytes written to the socket) — not guaranteed *printed* (raw TCP to a thermal printer has no application ACK), and de-duplicated the socket send behind a shared internal helper. Final shape: `KeckPrinterService.printRawBytesWifi(bytes, {required ip, port = 9100, timeout = 5s}) → Future<KeckPrintResult>`.

## 4.1.0
- **Direct WiFi raw printing:** `KeckPrinterService.printRawBytesWifi(...)` sends finished ESC/POS bytes straight to a network printer over a short-lived socket, **without touching the globally initialized printer** (`ipAddress`/`port`/the active device stay untouched). It never throws — the outcome is reported as a result object, so callers can retry or show a hint. Exported from `package:kasseneck_api/printing.dart`. (Superseded by 4.1.1, which finalizes the signature and result type.)

## 4.0.0
- **Decoupled print stack.** The ESC/POS generator and the (correct) rasterizer from esc_pos_utils 1.1.0 are now vendored internally under `lib/src/printing/`; PNG de/encoding runs via `dart:ui`. The runtime no longer depends on `esc_pos_utils_plus`, and `image` is a dev-only dependency — apps that use this package are no longer version-locked to `image` and pull in no print dependencies at runtime.
- Fixes the Bluetooth/thermal print failure for image widths that are not a multiple of 8 (a crash in the old `esc_pos_utils_plus` rasterizer). QR and logo printing are unchanged in behaviour (native QR is byte-identical, image-QR keeps its white background and quiet zone).
- **New custom-print API** on `KeckPrinterService`, additive and sending to whichever printer is currently initialized (Bluetooth or WiFi, same send path as the receipt printers): `printRawBytes(List<int>)`, plus the high-level helpers `printText`, `printQr`, `cut`, `openDrawer` and `feed`. A `CustomPrintJob` batch builder (`text`/`qr`/`cut`/`drawer`/`feed`/`raw`, fluent) accumulates several commands into a single byte stream printed in one send via `printJob` (preferred for Bluetooth). The vendored `EscPosGenerator` and the required types (`PosStyles`, `PosAlign`, `PosCutMode`, `PosDrawer`, `QRSize`, `CapabilityProfile`, …) are exported from the new `package:kasseneck_api/printing.dart` barrel so integrators can build bytes themselves and send them with `printRawBytes`.
- **Branded API base URL:** the client now talks to `https://api.kasseneck.at/v1` instead of `europe-west1-kasseneck.cloudfunctions.net`. The receipt-download base URL is unchanged.
- **v2 item shape:** `KasseneckItem.toJson()` now sends `{ name, quantity, unitPriceCents, vatRate }` with the unit price as integer cents (no floating-point amounts). `fromJson()` reads both the new v2 form and the legacy v1 form (`priceOneCents`/`priceOne`, `amount`, `vat`), preferring cents for exactness — old stored receipts keep parsing.
- Breaking: `KeckPaperSize.paperSize` is now typed `EscPaperSize` (internal) instead of `PaperSize` from esc_pos_utils.

## 3.3.0
- Receipt download links now use the branded path-based URL `https://beleg.kasseneck.at/<token>` instead of `https://receipt.kreiseck.com/downloadReceipt?fullReceiptId=<token>`. The backend serves both the new path form and the old query form, so links on already printed or shared receipts keep working.

## 3.2.1
- GP Tom card details render correctly with `gptom_aidl_plugin` ≥ 0.1.0: `cardPaymentData` amounts arrive as integer cents and are now formatted as such (older stored receipts with euro doubles keep working); applies to thermal print and `KeckReceiptWidget`
- GP Tom transaction type is recognized via both `transactionType` and the plugin's `transacitonType` key; `Refund` (type 3) is now labelled

## 3.2.0
- Kreiseck branding on receipts: when the backend metadata flag `kreiseck_logo` is set (Firestore `users/{uid}.branding.kreiseck_logo`), the receipt ends with "powered by" and the Kreiseck logo — on thermal prints (85 % paper width), in `KeckReceiptWidget` and survives JSON round-trips for reprints
- The logo ships as a package asset (printing works offline; the backend only sends the flag); branding can never break receipt printing
- Fixed an ESC/POS rasterizer crash for images whose width is not a multiple of 8

## 3.1.1
- Zero analyzer issues: debug-only logging, migrated deprecated APIs (`License.nonprofit`, QR `eyeStyle`/`dataModuleStyle`), removed redundant imports; FinanzOnline status enum names are intentionally kept verbatim (they must match the `rkdbMessage` values)
- CI runs `flutter analyze` in strict mode again

## 3.1.0
- Comprehensive test suite (~100 new tests): money & receipt math, JSON round-trips and fallback parsing, voucher rules, mocked API client, and a print↔widget consistency check that guards the two independent VAT-table renderers against drift
- `KasseneckApi` and `LogoService` accept an injectable `http.Client` (useful for testing/mocking; default behaviour unchanged)
- `financeWebService` requests now also time out after 30 s
- Continuous integration: analyze + tests run on every push

## 3.0.1
- `getReceipts` no longer fails wholesale when a single receipt can't be parsed — broken receipts are skipped (and logged in debug builds)
- Zero receipts (no items) parse correctly; item quantities also accept `1.0`
- All HTTP requests time out after 30 s instead of hanging silently forever
- Odd voucher amounts are displayed exactly (e.g. € 1,50 instead of ~2)

## 3.0.0
**Breaking: money is now integer cents** — exact arithmetic, no floating-point drift. No backend update is required: requests carry BOTH representations (`priceOne`/`value` in euro for the current backend and `priceOneCents`/`valueCents`/`singlePriceCents`, preferred by newer backends). When reading, the cents fields are preferred; euro-only data (old receipts) still parses — the euro↔cents round-trip is lossless (verified by property tests).

Migration:
- `KasseneckItem(singlePrice: 19.99)` → `KasseneckItem(priceCents: 1999)` or `KasseneckItem.euro(singlePrice: 19.99)`
- `KeckVoucher(value: 5.0)` → `KeckVoucher(valueCents: 500)` or `KeckVoucher.euro(value: 5.0)`
- `KeckInvoiceItem(singlePrice: …)` → `priceCents` / `KeckInvoiceItem.euro(…)`
- Reading: `item.singlePrice`, `voucher.value`, `receipt.sum` / `subSum` still exist as euro views; for arithmetic use `priceCents` / `valueCents` / `sumCents` / `subSumCents` / `totalCents`
- Terminal APIs (`hobexPay`, `HpsClient`, SumUp) keep euro amounts — they mirror the external providers' formats

## 2.1.3
- Reliable Bluetooth thermal printing: flow control via write-with-response (backpressure), negotiated MTU with matching chunk size, and pacing for write-without-response printers
- Fixed garbled QR output: the QR image is now composited onto a white background with a quiet zone (QrPainter renders on transparent, which ESC/POS rasterization printed as solid black)
- New `QrPrintMode` (`imageRaster` / `imageBitImage` / `native`) on `printReceiptBluetooth` / `getPrintBytes` to pick the command your printer supports (replaces `qrAsImage`)
## 2.1.2
- Cleaner static analysis (0 warnings): `KeckVoucher.value` is now nullable; removed dead null-aware code and unused SumUp leftovers
- Loosened the `my_pos` version constraint to `^0.3.0`
## 2.1.1
- New README, a runnable `example/` and inline API documentation (dartdoc)
- Added repository & issue tracker metadata
## 2.1.0
- hobex Payment Service (HPS): lokaler Terminal-Client (HpsClient) mit Zahlung, Pre-Auth, Capture, Refund, Storno, Status, Abbruch, AVT und Diagnose
- HobexReceipt.fromHps + Karten-Beleg-Rendering (Provider hobexHps); HobexReceipt aus dem hobex_hps-Barrel exportiert
## 2.0.0
- image plugin update
- voucher logic implemented
## 1.1.0
- Added new endpoints
## 1.0.0
- Initial release of kasseneck_api