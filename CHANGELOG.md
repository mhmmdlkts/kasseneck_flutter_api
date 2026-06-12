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