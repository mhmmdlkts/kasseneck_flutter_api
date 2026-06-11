## 2.1.3
- Reliable Bluetooth thermal printing: flow control via write-with-response (backpressure), negotiated MTU with matching chunk size, and pacing for write-without-response printers
- QR codes are now printed as `GS v 0` raster (`imageRaster`) instead of legacy `ESC *` — fixes garbled output and aborts on printers without `ESC *` support
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