# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`kasseneck_api` is a **published Flutter package** (a library, not an app) — the official client
for the Austrian RKSV-compliant Kasseneck point-of-sale backend by Kreiseck. It issues signed
receipts, drives card terminals, renders/prints receipts and pulls PDF reports. Card payments and
Bluetooth printing only work on real Android hardware; everything else (money math, JSON, rendering)
is unit-testable on the host.

## Commands

```bash
flutter pub get                       # install deps
flutter analyze                       # MUST report zero issues — CI runs this in strict mode and the
                                      # project has deliberately kept it at 0 (see CHANGELOG 3.1.1)
flutter test                          # full suite
flutter test test/money_cents_test.dart            # a single file
flutter test --plain-name "Komplexer Warenkorb"    # a single test by name
dart run tool/make_print_logo.dart    # regenerate the print logo asset from doc/kreiseck_logo_src.png
```

CI (`.github/workflows/ci.yml`) runs `flutter analyze` then `flutter test` on every push/PR.

## Architecture

### `KasseneckApi` (lib/kasseneck_api.dart) — the entry point
Single client class holding `apiKey` + `cashregisterToken`. All backend calls go through two private
helpers — `_kasseneckPostRequest` (named cloud-function endpoints) and `_financeWebServicePostRequest`
(FinanzOnline status) — both POST JSON to `europe-west1-kasseneck.cloudfunctions.net` with a 30s
timeout. Every receipt-creating method (`sellReceipt`, `cancelReceipt`, `zeroReceipt`, …) funnels into
the private `_createReceipt`, which validates items/vouchers, builds params, and parses the response.
The constructor takes an **injectable `http.Client`** so tests can mock the network without touching
behaviour (same pattern in `LogoService.httpClient`).

### Money is integer **cents**, end to end
This is the core invariant (CHANGELOG 3.0.0). Internally every amount is an `int` of cents
(`priceCents`, `valueCents`, `sumCents`, `subSumCents`, `totalCents`) — exact arithmetic, no float
drift. Euro getters (`singlePrice`, `sum`, `subSum`) exist for **display only**; never use them for
math. `.euro(...)` constructors round to cents exactly once at the API boundary.

JSON carries **both** representations: requests send `priceOne`/`value` (euro, for the old backend)
**and** `priceOneCents`/`valueCents` (preferred by the new backend). When parsing, the cents field is
preferred and euro is the lossless fallback — so the client works regardless of backend version, and
old euro-only stored receipts still load. Property tests verify the euro↔cents round-trip; do not break
the dual-field contract when editing `toJson`/`fromJson`.

### Two independent receipt renderers — keep them in sync
The receipt is rendered **twice by separate code paths** that each compute the VAT table independently:
- `lib/models/print_paper.dart` — thermal/ESC-POS output (`PrintPaper.setKeckReceipt`), also emits a
  parallel `MyPosPaper` command list for the myPOS built-in printer.
- `lib/widgets/keck_receipt_widget.dart` — on-screen Flutter widget.

`test/print_widget_consistency_test.dart` asserts both produce identical VAT/total values for the same
receipt — **any change to one renderer's math must be mirrored in the other**, or this test (which
reads the print side via `myPosPaper.commands`, no printer needed) will catch the drift.

### Printing (lib/services/printer_service.dart)
`KeckPrinterService` is static state holding the active printer + `CapabilityProfile`. Three transports:
Bluetooth (ESC/POS over BLE), Wi-Fi (raw socket to port 9100), and myPOS (native). Bluetooth print does
careful flow control — negotiates MTU, prefers write-**with**-response for backpressure, falls back to
write-without-response with 20ms pacing (the fix for garbled QR/logo rasters). `QrPrintMode`
(`imageRaster`/`imageBitImage`/`native`) lets callers pick the QR command their printer supports;
`print_paper` maps each mode to a rasteriser or the native QR call. Text sent to the ESC/POS generator
is run through `_printable` (latin1-safe, maps typographic chars to ASCII) so one stray Unicode glyph
can't abort the whole print.

### RKSV signature status (lib/services/rksv_service.dart)
`RKSVService.isSigSuccess` detects a signature-device outage by checking whether the JWS signature
segment equals the base64url of `"Sicherheitseinrichtung ausgefallen"`. Surfaced as
`receipt.signatureSuccess` / `receipt.isSigFailed` and printed on the receipt.

### Hobex HPS (lib/src/hobex_hps/, barrel: lib/hobex_hps.dart)
Self-contained local-terminal client (`HpsClient`) for the on-device Hobex terminal — payment,
pre-auth/capture, refund, cancel, status, diagnosis. Kept under `lib/src/` and exposed via its own
barrel so consumers `import 'package:kasseneck_api/hobex_hps.dart'`. A **declined** payment is
`res.isApproved == false`, not an exception.

### Models / enums layout
`lib/models/` and `lib/enums/` hold one type per file and are **not** all re-exported from the main
barrel — consumers import the specific files they need (`models/…`, `enums/…`). `KasseneckReceipt`
splits its JSON into receipt-data (`toReceiptJson`) vs. company metadata (`toMetadataJson`); the
combined `toJson` is for local persistence (Isar), and `fromMetadata` rebuilds a receipt from the
list-endpoint shape. `getReceipts` parses receipts **one at a time inside try/catch** so a single bad
receipt can't empty the whole result set.

## Conventions

- Comments and identifiers are German (domain is Austrian tax/POS); match the surrounding language.
- `print` is debug-gated behind `kDebugMode` / `debugPrint` — keep it that way to preserve the 0-analyzer-issue baseline.
- FinanzOnline status enum names (e.g. in `cashbox_status`, `signature_status`) are intentionally verbatim
  to match the backend `rkdbMessage` values — do not rename them even if they violate Dart casing lints.
- Bump `version:` in `pubspec.yaml` and add a `CHANGELOG.md` entry for any user-visible change.
