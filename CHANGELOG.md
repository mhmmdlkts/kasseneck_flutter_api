## 11.8.2 (2026-10-29)

Twin of `@kreiseck/kasseneck-api` `1.17.1` (contract files pulled from that
version). No behaviour change.

- **The contract now carries the report as a binary path:**
  `antworten/berichte.json` (backend keck#798), generated from the real
  `getCashregisterReport` handler: one closed day as PDF (HTTP 200,
  `application/pdf`, bytes from `%PDF-`) and the rejections with HTTP 200 as an
  envelope with a code (`period_not_closed` for the current month and today,
  `period_in_future`, `invalid_period`). `test/bericht_vertrag_test.dart`
  replays it through `readPdfBody` and through `getCashregisterReport` over the
  whole transport: the PDF arrives byte for byte, each rejection is a
  `KasseneckApiError` with the contract's code and outcome `rejected`; the mixed
  form of `invalid_period` is refused before sending (`ArgumentError`). Reason:
  up to 11.8.0 this package returned such an envelope as PDF bytes; with the
  case in the contract, backend, npm and Dart are pinned to the same answer.
- The other contract files change only `_quelle` (new inputs on the backend side).

## 11.8.1 (2026-10-29)

- **`getCashregisterReport`, `downloadMonthlyReport` and `downloadDailyReport`
  throw the server's rejection instead of returning it as PDF bytes.** The
  backend rejects a report with HTTP 200 and its JSON envelope (current month
  or today: `period_not_closed`, future: `period_in_future`). Up to 11.8.0 the
  device client only checked for an empty body and returned the envelope's
  192 bytes as the "PDF", so a PDF viewer opened the error message as the
  report. Now a `KasseneckApiError` with the server's code, message and
  outcome `rejected` arrives, as on every JSON call. A success envelope without
  a file is a `KasseneckValidationError` (`kind: response`); an empty, non-JSON
  or status-less body is the same `KasseneckHttpError` (`empty-body`,
  `not-json`, `missing-status`) as on the JSON path. The first bytes decide
  (`%PDF`), not the content type, which a proxy can drop or get wrong. Found
  live on 29.10.2026 against the demo register. Apps that catch this
  themselves (checking for `%PDF-`) can switch to the package error.
- The three report calls, `InvoiceTransport.callBinary` (`getInvoicePdf`) and
  the file branch of `InventoryTransport.callPdfOrData` now share one check,
  so a binary path can no longer drift from the others. `getInvoicePdf` and
  `getStocktakePdf` already behaved correctly and are unchanged. Reason: the
  report path was the only one written by hand, and the transport test matrix
  did not list it.
- No public symbol changed. The npm twin `@kreiseck/kasseneck-api` checked the
  first bytes from the start (`createBinaryTransport`) and is unaffected.

## 11.8.0 (2026-10-29)

Twin of `@kreiseck/kasseneck-api` `1.17.0` (contract files pulled from that
version): vouchers at the register, stage 4b, voucher types
(Gutschein-Sorten). A business names any number of voucher types; the
register shows one tile per type in the tab "Gutscheine" and sells a value
voucher only through a type. Additive for reading, with behaviour changes
for selling (named below). Notes for callers:

- **Voucher types in the register settings: `PosVoucherSettings.typeSale`,
  `types`, `serviceArticles`, `labelDefault`.** New optional constructor
  parameters (off, empty, `null`), so existing calls still compile.
  `typeSale` shows the tab (server switch and at least one sellable type or
  service article), `types` are the sellable types in tile order
  (`PosVoucherType`), `serviceArticles` adds the fixed tile
  "Leistungsgutschein", `labelDefault` is the business's standard label
  template. Fail-closed as before: a malformed `typeSale`, `serviceArticles`
  or `types` closes the whole block (`PosVoucherSettings.off`), a malformed
  type is dropped on its own (unknown kind, rate not matching the kind, fixed
  amount outside 1.00-10,000.00 €, years outside 1-30, payout `never` with a
  limited validity, inactive, reserved id; the first of two equal ids
  counts), and `typeSale` is off when no type and no service article is
  left. An unusable label template becomes `null` and never closes anything.
  The old field `label` (registers before 11.8) is not read. `toJson` now
  always writes the four fields and `==` compares them (types and templates
  deeply), so a stored block reads back equal. Reason: from stage 4b the
  server sells value vouchers only through a type and keeps `sale` always
  `false`.
- **New public types (`package:kasseneck_api/pos.dart`):** `PosVoucherType`
  (`id`, `name`, `kind`, `vatRateBp`, `amount`, `validity`, `payout`,
  `label`, `order`, `active`, `soldCount`, `fromJson`, `toJson`),
  `VoucherTypeAmount` (`.free()`, `.fixed(cents)`), `VoucherAmountMode`,
  `VoucherTypeValidity` (`.unlimited()`, `.years(n)`),
  `VoucherTypeValidityPattern`, `VoucherPayout`, `VoucherLabelTemplate` (a
  copy of the template with `size`, `layout`, `rotation`, `fields`,
  `freeText` and `toJson`; the package draws no labels), and the lists
  `voucherTypeKinds`, `voucherAmountModes`, `voucherTypeValidityPatterns`,
  `voucherPayouts` (equal to `surface.json` and the `/v3` catalogues). From
  `package:kasseneck_api/kasseneck_api.dart`: `VoucherDueType` (`id`,
  `kind`, `vatRateBp`, `amount`); every `PosVoucherType` is one, so
  `settings.vouchers.types` goes straight into `voucherTypes`. Reason: web
  register and app read the same model.
- **A value voucher is sold only with `typeId`.** `KeckVoucher.typeId`
  (constructor, `fromJson`, `toJson`, `toPayload`); for a `PosVoucherType t`
  the recommended wish is `KeckVoucher(action: VoucherAction.sell, type:
  t.kind, typeId: t.id, amountCents: …)`, with a fixed amount exactly
  `t.amount.cents`. On
  the wire `type` may be missing (the kind then comes from the type): such a
  wish read with `fromJson` goes out again without `type`. Behaviour change:
  `isValid` is `false` for a multi- or single-purpose sale without `typeId`,
  and `sellReceipt` and the register's `sell` reject it before sending
  (message starts with `voucher_type_required`); `typeId` on any other
  action or kind is rejected as `voucher_invalid`, and so are `typeName` and
  `payout` on a wish (both are now in `serverFields`). Reason: the server
  answers a value sale without type `voucher_type_required`; nothing is sent
  that it would refuse.
- **`KeckVoucher.hasType`; `KeckVoucher.type` throws without a type.**
  Behaviour change: `fromJson` no longer turns an explicit sale
  (`action: sell`) with a missing or unknown `type` into `promo`. Such a
  voucher has no type (`hasType` is `false`), reading `type` throws
  `StateError`, and an unknown value is written back unchanged; it is never
  sendable, except the sale through a type without kind above. Every other
  action keeps the fallback to `promo`, and every receipt entry of the server
  carries a type. The package's own readers (receipt sums, Bon, receipt
  widget, cancellation helpers, due amount) treat a voucher without type as
  neither value nor promo voucher. Reason: a sale must never count as a
  discount, and a kind must not be guessed.
- **Due amount with voucher types: `voucherTypes` on `receiptDueCents`,
  `receiptDueBreakdown`, `receiptDueBreakdownForLines`,
  `voucherRedeemMaxCents` and `voucherRedeemMaxCentsForLines`.** A sale
  through a type takes kind and rate from the type (multi-purpose as value
  flow, from the zero-rate date in the 0 % bucket; single-purpose as an item
  at the rate of the type, 0 % for a small business). A type that is not
  passed or that the server would not sell (rate not matching the kind,
  fixed amount out of range, reserved id) throws `voucher_type_not_found`, a
  different fixed amount `voucher_amount_mismatch`, and so does a `type`
  other than the kind of the type (the owner switched the kind after the
  register loaded its types; the register reloads them on this code).
  Behaviour change: a value sale without
  `typeId` still computes with a `voucherSettings` that names a kind exactly
  as in 11.7, but without `voucherSettings` or with one naming no kind
  (`valueVoucherType: null`, as every stage-4b server sends) it now throws
  `voucher_type_required` instead of `voucher_settings_missing`. Reason: the
  register computes the amount to charge before the card terminal, with the
  same rules and codes as the server's `gutschein-beleg.plane`.
- **Payout locked per voucher: `VoucherCheck.payout` (`VoucherPayout`, frozen
  at sale) and `VoucherCheck.typeName` from `checkVoucher`.** A payout of a
  `never` voucher throws `voucher_payout_not_allowed` in the due amount (also
  when expired). An unknown payout value reads as `never` without throwing;
  a `typeName` that is not a non-empty text is a read error. Reason: a
  business may exclude payouts for unlimited voucher types; redeeming must
  not fail on a new value.
- **Validity in years: `VoucherValidity.redeemableYears`** (constructor
  parameter, part of `==`) from `checkVoucher`, a whole number from 1
  (anything else is a read error, like the other fields of the answer). The
  patterns stay `unlimited`, `1+3`, `custom` (`voucherValidityPatterns`); the
  type's own pattern `years` never appears on a voucher. A voucher of a type
  with N years comes as `1+3` for every N, with the explicit dates
  (`redeemableUntil` = sale + N years, `refundableUntil` = sale + N + 3
  years) and `redeemableYears` = N; read N from `redeemableYears`, never from
  the pattern. Reason: registers before 11.8 keep redeeming such vouchers and
  print "einlösbar bis <date>" from `redeemableUntil` on a reprint (with
  `custom` and no `validUntil` they printed no validity line at all).
- **Service vouchers only for approved articles: `PosArticle.serviceVoucher`**
  (read from `serviceVoucher`, only `true` counts; in `toJson` and
  `PosArticle.fields`) and `VoucherDueArticle.serviceVoucher`: `false` throws
  `voucher_service_not_allowed`, absent computes as before. Reason: the tile
  "Leistungsgutschein" offers only approved articles; the server sells no
  other.
- **Receipt entries of a sale through a type** read and write back `typeId`,
  `typeName` and `payout` (`KeckVoucher.typeName`, `KeckVoucher.payout`, as
  text: an unknown value stays). Reason: the receipt and the label show the
  type name, and a cached receipt must write back unchanged.
- **Catalogue: 5 labels and 5 sentences.** `voucher.tab` (Gutscheine),
  `voucher.enter_amount` (Betrag eingeben), `voucher.service_tile`
  (Leistungsgutschein), `voucher.kind_multi_short` (Mehrzweck),
  `voucher.kind_single_short` (Einzweck {rate} %); `voucherErrorMessage` maps
  `voucher_type_required`, `voucher_type_not_found`,
  `voucher_amount_mismatch`, `voucher_service_not_allowed` and
  `voucher_payout_not_allowed` to `voucher_error.*`. The codes of the
  customer area (`invalid_voucher_type`, `voucher_type_in_use`,
  `too_many_voucher_types`) are not register codes and get no sentence.
  Reason: web register and app say the same words.
- **One sentence of the register itself: `voucher.type_changed`** ("Diese
  Gutschein-Sorte hat sich geändert. Bitte die Zeile entfernen und die Kachel
  neu antippen."). The register shows it on a voucher sale line in the cart
  that no longer matches the reloaded types (type changed, deactivated or
  deleted); the sentences after a server rejection stay
  `voucher_error.type_not_found` and `voucher_error.amount_mismatch`. Reason:
  those say "Die Kasse lädt die Sorten neu", which is over once the types are
  reloaded; the line blocks payment until it is removed and the tile tapped
  again.
- Contract re-fetched (stage 4b): the generated due cases
  (`receipt-due-voucher-generated.json`) now sell through types, with and
  without `type`, free and fixed, and cover the rejections above; the server
  names the item of a single-purpose sale with the type name.

## 11.7.0 (2026-10-28)

`getReceipts` reads through `listReceipts`, and the full view of
`listReceipts` carries the header data of the business. Reason: the server
now refuses `getReportV2` for more than 62 calendar days
(`range_too_long`) and lists belong to the bounded, paged `listReceipts`;
the registers only need to raise the package to move over. Additive; the
return of `getReceipts` is unchanged.

- **`getReceipts(start, end)`** now calls `listAllFullReceipts` (`view:
  full`, `order: asc`, pages of 500 over `nextCursor`) instead of
  `getReportV2`. It still returns `List<KasseneckReceipt>`, oldest first,
  each with company, address, tax number, footers and logo URL, and still
  loads the logo (`init()`). `start` and `end` are formatted exactly as
  before (`toIso8601String().split('.').first`, the fields of the `DateTime`
  as Vienna wall clock, no zone), `end` stays exclusive. A range over 31 days
  is split into consecutive windows of at most 31 calendar days (counted
  without time zone, also across the clock changes); each window's `to` is
  the next one's `from`, so no receipt falls into a gap or into two windows.
  An error on any page or window throws; the receipts fetched before are
  dropped, never returned as if the range were complete. A receipt that
  cannot be read is still skipped. `start` equal to `end` returns an empty
  list without a call (`listReceipts` refuses an empty window).
- **`ReceiptListPage.metadata`** (`view: full` only): the business data for
  the receipt header, the same fields as `metadata` of `getReportV2` (read
  only). `listFullReceipts` and `listAllFullReceipts` build every receipt with
  it through `KasseneckReceipt.fromMetadata`, the same path `getReceipts`
  took. A backend without `metadata` (before 28.10.2026) gives receipts
  without header, as in 11.6; a `metadata` that is not an object is a
  response error (`KasseneckValidationError`, `kind: response`), like npm
  1.16.0. Reason: an empty header would look like a business without a name
  (§ 132a Abs. 3 Z 1 BAO).
- Behaviour change for a broken answer: `getReceipts` without `metadata` no
  longer throws „keine Metadaten“; the receipts come without header instead,
  because that is how an older backend answers `listReceipts`.
- **Contract pinned to npm `1.16.0`** (fetched from the locally packed
  tarball, not yet on the registry). From the backend it brings
  `idempotency_conflict` in `receiptErrorCodes` (readable only; this package
  sends no `idempotencyKey` on receipts), `invoice_number_taken` at the end of
  `invoiceErrorCodes`, and the old settings field `vouchers.label`, which the
  package does not read (registers before voucher stage 4b), as npm. The text
  catalogue and the code table layout source were regenerated; the layout
  itself is unchanged (same sha256).

## 11.6.0 (2026-10-28)

List the receipts of the cash register page by page over the new backend
endpoint `listReceipts` (only `/v3`, api_key and `cashregister-token` like
`getReportV2`). Reason: `getReportV2` returns every receipt of any period in
one answer, without limit or paging; `listReceipts` is bounded (at most 500
receipts per page, at most 31 days per window) and has a slim line view.
Additive; `getReceipts` is unchanged in this release.

- **`listReceipts({date, from, to, limit, order, cursor})`** returns
  `ReceiptListPage<ReceiptListEntry>` (`view: summary`): per receipt
  `receiptId`, `counter`, `receiptType`, `zeroKind`, `timeStamp`,
  `totalCents`, `grossByRateCents` (`ReceiptGrossByRate`: `standard`,
  `reduced1`, `reduced2`, `zero`, `special`), `paymentMethod` (`null` when
  missing or unknown, never guessed as cash), `payments`, `tipCents`,
  `operator` (name only), `cancellationOf`, `cancellationReason`,
  `cancellationStatus`, `signatureOk`, `customProjectId`, `fullReceiptId`.
  All amounts are whole cents; an amount that is not an integer ends the call
  with a `KasseneckValidationError` (`kind: response`) instead of a guessed 0.
- **`listFullReceipts(...)`** returns `ReceiptListPage<KasseneckReceipt>`
  (`view: full`, the stored receipts in the shape of `getReportV2`, read the
  same way as `getReceipts`). The answer carries no header data of the
  business, so `companyName`, address, footer and logo stay empty; print a
  single receipt via `getReceipt`. Like `getReceipts`, a receipt that cannot
  be read is skipped, not the whole page.
- Why two methods and one generic page: the view decides the type of the
  lines, so it is fixed by the method, not by a parameter that could be read
  the wrong way round. Paging, cursor and `daySummary` are the same in both.
- **`ReceiptListPage`**: `receipts`, `hasMore`, `nextCursor` (the next page
  needs the same window and `order`; only `limit` may change) and
  `daySummary` (`ReceiptDaySummary`: `date`, `receiptCount`, `revenueCents`,
  `revenueByRate` as records `(rateBp, grossCents)`), only with `date` and only
  on the first page, `null` without daily statistics. `revenueCents` is not
  the sum of `totalCents` of the list. `hasMore` and `nextCursor` must agree,
  otherwise the answer is rejected (paging would stop silently).
- **`listAllReceipts(...)` and `listAllFullReceipts(...)`** stream every
  receipt of the window, page by page, with page size 500 unless `limit` is
  given. They stop with an error after 100 pages (`receiptListPagesMax`) or
  when the server repeats a cursor; an error on a later page ends the stream
  after the receipts already delivered.
- **Input is checked before sending** and throws `KasseneckValidationError`
  (`kind: request`), the same rules as the server: exactly one of `date` or
  `from` + `to`; `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm:ss` (Vienna local time as
  text, no zone, impossible dates such as `2026-02-30` rejected); `to` after
  `from` and at most 31 calendar days later (also across the clock changes);
  `limit` 1–500; `order` `desc` or `asc`; no empty `cursor`.
- New exports from `package:kasseneck_api/kasseneck_api.dart`:
  `ReceiptListEntry`, `ReceiptListPage`, `ReceiptDaySummary`,
  `ReceiptGrossByRate`, `receiptListErrorCodes` (`invalid_date`,
  `invalid_range`, `range_too_long`, `invalid_limit`, `invalid_order`,
  `invalid_view`, `invalid_cursor`, `server_error`), `receiptListOrders`,
  `receiptListLimitMax`, `receiptListDaysMax`, `receiptListPagesMax`, and
  `CancellationState` and `ReceiptOperator` (already public through
  `pos.dart`, same types). The line type is not called `ReceiptSummary`: that
  name is the line of `listMyReceipts` on the register path (`pos.dart`).
- `Aufrufe.listReceipts` is a reading call (outcome `rejected` on every
  error). The endpoint is not yet in the contract of npm `1.14.0`; the
  contract pin stays at `1.14.0`.

## 11.5.0 (2026-10-23)

Twin of `@kreiseck/kasseneck-api` `1.14.0` (contract files pulled from that
version): vouchers follow the final Bon and payment rules. Notes for callers:

- **A voucher never covers the tip.** `receiptDueCents` throws
  `ReceiptDueError` (`voucher_exceeds_total`) when the amount due after
  vouchers is below the sum of the tip lines (staff or owner tip); the
  pre-fill `voucherRedeemMaxCentsForLines` stops at goods (goods plus payout
  minus tip) and never turns negative. Not applied to a cancellation.
  Reason: the tip is paid in cash or by card, never from a voucher balance.
  The server's contract cases (staff and owner tip, `payments[].tipCents`,
  promotion plus voucher, single-purpose, the boundary 20.00 accepted and
  20.01 rejected, each with the largest redemption the server accepts) now
  check `receiptDueCents` and `voucherRedeemMaxCentsForLines`; an unknown
  contract case fails the tests.
- **Bon text.** The voucher code is always the short mask `····-XXXX` on the
  Bon (the long form `····-····-XXXX` is gone; the `code` field on the
  receipt itself is unchanged). The rest of a single-purpose or service
  voucher carries the currency (`19,50 EUR`) like a multi-purpose one. The
  promotion voucher is called "Aktionsgutschein" (old receipts that still say
  "Promotionsgutschein" print that name alone). A receipt that a voucher
  covers completely prints no "Zahlungsart" line; with several payments,
  payments of 0 cent are left out. `PrintPaper` and `KeckReceiptWidget`
  follow the same rule.
- **Cancelling a voucher payout.** `cancelReceipt` accepts the one positive
  cash payment that refunds a payout; with the original at hand, a
  cancellation without a payout in it is still rejected before sending.
  `paymentsError(..., payoutCancellation: true)` is additive.
- **Catalogue.** 24 new labels (`nav.*`, `receipt_done.*`, `quantity.at_most`,
  `quantity.at_least`, `receipts.*`, `cart.close`, `voucher.code_mask`,
  `drawer.reason_voucher_payout`); new placeholder `{method}`.
- **Drawer reason `voucher_payout`** is appended to `openingReasons` (the
  register reports it itself at a payout); it is not in `manualOpeningReasons`.
- **Shortcut actions `shiftStatus`, `openDrawer`, `voucherPayout`** join
  `posShortcutActions`, without a default key (empty list in
  `posShortcutDefaults`; the server leaves them out of its default map, so a
  missing key reads as "no key", never as a guessed one). A card that is sent
  must still carry every action.
- **`createReceipt` hides voucher codes in error texts**, on both ways
  (`KasseneckApi` and the register's `sell`): the code as typed (trimmed, from
  8 characters, also an invalid one), its normal form and its formatted form
  become `****`; the error code and details stay. Four-character endings are
  never touched.
- **`RegisterDeviceUsers.settings`**: the reply of `listRegisterUsersForDevice`
  has no `vouchers` block. `settings.vouchers` stays the fail-closed default
  (`PosVoucherSettings.off`) and is not part of `settings.toJson()`; only
  `getKasseSettings` delivers the real block. No type change was needed
  (unlike npm, where the type was narrowed).
- **Mark a reprint as a duplicate (Nachdruck als Duplikat kennzeichnen):
  `markAsDuplicate(layout, printedAt: ...)`** (top-level function in
  `package:kasseneck_api/models/receipt_layout.dart`, also exported from
  `package:kasseneck_api/kasseneck_api.dart`). It returns a new
  `ReceiptLayout` with one plain (not bold) two-column line `Duplikat am:`
  and the time of the reprint, placed right after the line `Beleg-ID:`
  (column widths 5/7, the time at the right edge like `Datum:`): on 32
  characters `Duplikat am: 24.10.2026 14:10:05`, on 48 characters
  `Duplikat am:` and the time 17 spaces apart. `printedAt` (required) is an
  instant, UTC or local; the line shows it in Europe/Vienna time (EU summer
  time rule, `DD.MM.YYYY HH:MM:SS`, fractions cut), never in the time zone of
  the device. A layout without a `Beleg-ID:` columns line (shift receipts)
  gets the line on top. Applying it again replaces the time (one line, the
  latest reprint counts); the input is never changed (lines and column lists
  are new). Registers must call it on **every reprint and on "print copy"**
  with the print time, never on the first print and never for mail, link or
  PDF (the customer gets the receipt itself there), and pass the result to
  the same print path (`PrintPaper.setReceiptSheet`, `receiptSheet`,
  `KeckReceiptSheetWidget`). Reason: Erlass BMF-AV Nr. 2/2026, section 4.5.6,
  requires a receipt duplicate to be labelled as such (a reprint of the
  stored receipt is already not signed again, not in the DEP and does not
  move the counter). On the printer the reprint is the first print plus
  exactly this line, byte for byte. The cases (around the summer time changes
  in March and October, 58 and 80 mm, zero receipt, cancellation, voucher
  redemption, with logo, without `Beleg-ID:`, applied twice) and the printed
  bytes come from the contract file `duplicate-cases.json` (version 2) of
  npm 1.14.0; the result matches npm layout for layout and byte for byte.
- **Receipt outputs (Ausgaben eines Belegs): `logReceiptOutputs`** on
  `RegisterReceiptClient` and on `KasseneckApi` (register path `/api/v3`
  only; `KasseneckApi` sends this one call to `kPosBaseUrl` with its api_key
  and `cashregister-token`). The register reports its prints and shares of a
  receipt: `entries` (1-50, `receiptOutputEntriesMax`) of
  `ReceiptOutputEntry(key, receiptId, kind, at, result)`, `kind` from
  `receiptOutputLogKinds` (`print` first print, `reprint` duplicate,
  `link_shared`, `pdf_shared`), `at` as milliseconds (`int`), `DateTime`
  (sent as milliseconds, like the drawer openings) or ISO 8601 text with a
  zone, `result` from `receiptOutputResults` (`ok`, `failed`, `unclear`;
  required for prints). `toJson`/`fromJson` keep a buffered entry; `fromJson`
  throws on an unknown field or a wrong type. The answer
  `LogReceiptOutputsResult(accepted, rejected)` names each rejected entry
  (`RejectedReceiptOutput(key, code)`) with a code from
  `receiptOutputEntryErrorCodes`; one entry never fails the others. A call
  with effect (`unknownOutcomeCalls`): after an unclear outcome send the same
  entries with the same keys again. Rejected before sending: no or more than
  50 entries, a missing receipt, a key outside the server's rule (8-64
  characters `[A-Za-z0-9_-]`), a kind or result outside the catalogue, a time
  that is neither whole milliseconds from 0 nor ISO 8601 text with a zone;
  `email` and `opened` go out and come back as `invalid_output_kind`. A broken
  success answer is a response error, never "0 accepted". Errors of the whole
  request: `receiptOutputErrorCodes` with `isReceiptOutputError`,
  `receiptOutputErrorCode`, `isReceiptOutputErrorCode`,
  `receiptOutputFieldErrors`. Reason: Erlass BMF-AV Nr. 2/2026, section 4.2,
  requires the way a receipt was handed over to be documented; the server
  keeps the log next to the receipt (never on it, never in the DEP).
- **`KasseneckReceipt.outputs`** (`List<ReceiptOutput>?`) from `getReceipt`
  (both ways): the latest 20 outputs, newest first, each
  `ReceiptOutput(kind, at, result, by, count)` (`by` a `ReceiptOutputActor`
  or `null`, `count` only on `opened`). `null` when the answer has no list
  (sale); not part of `toJson` (the log grows next to the receipt, a stored
  copy would be stale). Read leniently, the same rule as npm: an entry
  without kind, time or result is dropped, an actor without id reads as
  `null`, an unknown kind or result stays readable; a broken log never fails
  reading or reprinting the receipt.
- **Shared contract file `receipt-outputs-cases.json`** (npm 1.14.0,
  `fixtures:ausgaben`, pulled and verified by `tool/zwillinge.sh`): the read
  cases of `outputs` (with `receiptOutputLabel` of each entry) and the request
  cases of `logReceiptOutputs` (body sent or rejection with its reason). The
  tests run every case on both ways, so npm and Dart cannot drift apart.
  `ReceiptOutputEntry.fromJson` reads a missing `key`, `receiptId`, `kind` or
  `at` as empty, so sending rejects it with the same reason as npm; an
  explicit `"result": null` throws (outside the catalogue, as in npm), only a
  missing `result` means none.
- **9 labels for the receipt detail** (`receipt.outputs_title`,
  `receipt.outputs_count`, `receipt.output_<kind>` for the six kinds,
  `receipt.output_failed`) and **`receiptOutputLabel(output)`** in
  `package:kasseneck_api/pos.dart`: the label of the kind, never throws;
  `null` for a kind this package does not know, `opened` without a valid count
  (whole number from 1) counts as one open; the register adds
  `receipt.output_failed` itself when `result` is `failed`. Catalogues
  `receiptOutputKinds` and `receiptOutputResults` equal the contract
  (`surface.json`, `pos.receiptOutputKinds`/`receiptOutputResults`).
- No model for `issuedVouchers` exists in this package, so the optional
  `articleName` (service voucher) has no place here; the Bon layout of the
  server already carries it.
- Test data: placeholder VAT id `ATU12345675` in doc comments and tests (valid
  check digit).

## 11.4.0

Twin of `@kreiseck/kasseneck-api` `1.13.0` (contract files pulled from that
version): the sentences and words of the voucher screens are part of the shared
text catalogue, so the web register and the app register say the same.
Additive; no existing key changes.

- **14 sentences and 8 labels** (`voucher.reentry_needed`, `voucher.not_this_voucher`,
  `voucher.sale_max_amount`, `voucher.payout_check_first`, `cancellation.voucher_sale_cancelled`,
  `voucher.apply`, `voucher.redeemable_until`, `voucher.article`, `voucher.add` ...).
  Reason: the web register kept these words in its own constant until the
  catalogue had keys for them; both registers now take them from the catalogue.
  The generated `texte_katalog.dart` and the contract copy under
  `test/fixtures/vertrag/` carry them.

## 11.3.0

Twin of `@kreiseck/kasseneck-api` `1.12.0` (contract files pulled from that
version): vouchers in the new form at the register (multi-purpose,
single-purpose, service, promotional; the clear code is shown once and never
stored). Additive for existing calls; notes for callers:

- **Two imports.** `VoucherCheck`, `VoucherStatus`, `VoucherValidity`,
  `PosVoucherSettings`, `checkVoucher`/`reprintVoucherLabel` and the voucher
  rights live in `package:kasseneck_api/pos.dart`; the due options
  (`VoucherDueInfo`, `VoucherDueArticle`, `voucherRedeemMaxCents`,
  `voucherRedeemMaxCentsForLines`, `voucherZeroRateBucketFrom`) are in the
  package root `package:kasseneck_api/kasseneck_api.dart`. A register that
  pre-fills a voucher amount needs both.
- **`PosSettings.vouchers` is always set** (non-nullable, fail-closed: a
  missing or inconsistent `vouchers` block reads as `PosVoucherSettings.off`;
  the constructor defaults to `off`). Reason: an unreadable block must switch
  voucher sales off, never on.
- **A sale of a multi- or single-purpose voucher needs `voucherSettings`** in
  the due options (`receiptDueCents`, `receiptDueBreakdown…`); without it the
  calculation throws `ReceiptDueError` with `voucherErrorCode`
  `voucher_settings_missing`. Reason: the rate and the kind of a sold voucher
  come from the confirmed register setting, as on the server.
- **New runtime dependency `kreiseck_validator ^0.14.1`** (`VoucherCode`:
  check character and normal form of a typed code before anything is sent).

Changes:

- **Model.** `VoucherType` gains `multiPurpose`, `singlePurpose`, `service`,
  `promotion` with `wire`, `fromWire` and `isNewForm`; `VoucherAction.payout`.
  `KeckVoucher` gains `amountCents`, `articleId`, `quantity`, `positions`,
  `reason` and the server-only fields `voucherType`, `voucherId`,
  `codeSuffix`, `vatRateBp`, `article` (`VoucherArticle`), `balanceAfterCents`,
  `remainingQuantityAfter`, `taxedWith`, `exempt`, `zeroRateBucket`, plus
  `isNewForm` and `serverFields`; `valueCents` is no longer a required
  constructor argument. `KasseneckItem.isVoucher`/`isVoucherFloat` (`kind`
  `voucher`/`voucher_float`). Reason: the backend keeps vouchers as typed
  records with balance, validity and rate; a receipt in the new form must read
  without loss and never fail to open (list, detail, cache). Note:
  `KeckVoucher.fromJson` now reads `payout` and the new types instead of
  falling back to `sell`/`promo`, and `toJson` writes `type` as its wire value
  (unchanged for `value`/`promo`).
- **Request checks before sending** (`sell(vouchers:)` on
  `RegisterReceiptClient`, `sellReceipt`): server-only fields on a wish,
  voucher items and forbidden combinations are rejected with
  `voucher_invalid` before anything goes out; `paymentsError(..., payout:)`
  for a pure payout (exactly one negative cash payment). Reason: a request the
  server would reject must not cost a receipt number.
- **`checkVoucher` and `reprintVoucherLabel`** (function and method on
  `RegisterReceiptClient`): the code goes out in normal form after a local
  check character test; a server message naming the code is masked. Reason:
  the cashier checks a code before redeeming it; a wrong check character is
  red at once, without a call.
- **Rights**: `RegisterUserPerms.voucherSell`, `voucherRedeem`,
  `voucherManage`, `VoucherPerms`, `voucherPermsOf`. Catalogues
  `voucherKinds`, `voucherStatuses`, `voucherValidityPatterns` (equal to
  `surface.json`). Reason: redeem, sell and pay out are separate rights per
  role, and both registers decide on the same function.
- **Due amount**: `receiptDueCents`/`receiptDueBreakdown…` take
  `voucherInfo`, `voucherSettings`, `voucherArticles`, `smallBusiness`,
  `zeroRateBucketFrom`, `today`; `ReceiptDueLine.kind`/`articleId`,
  `ReceiptDueError.voucherErrorCode`, `voucherRedeemMaxCents(ForLines)`.
  Reason: a single-purpose voucher covers at most the items of its rate and
  at most its balance; the register pre-fills exactly that, so the server never
  answers `voucher_exceeds_total`/`voucher_rate_mismatch` for an honest input.
  A voucher that covers everything gives a due amount of 0 (no payment, no
  card terminal). The pre-filled maximum is checked with the same computation
  as the due amount, including half-cent rounding and the proportional split
  of exempt or small-business vouchers (also next to vouchers already chosen
  on the receipt: each bucket bounds its share plus the redemptions already
  there), so it is never above what the server accepts and never 0 when the
  server accepts at least one cent (64 cents down, then bisection, then 16
  cents up).
- **Sums count each amount once.** `sumCents`/`subSumCents` skip entries with
  `zeroRateBucket` (their amount is already the 0 % item), single-purpose and
  service vouchers count only through their items, and a payout of a value
  voucher without `zeroRateBucket` reduces the total like a redemption.
  Reason: incident of 16.10.2026, a sale of a 30 € voucher showed
  "Gesamt 60,00".
- **Receipt lines of the new form** in the fallback without a server layout
  (`PrintPaper.setKeckReceipt`, `KeckReceiptWidget`), as in the package layout:
  sale with the code mask (multi-purpose with „USt bei Einlösung“), redemption
  „Gutschein ····-XXXX“ with „Einzweck, versteuert mit Beleg …“ or
  „…, befreit verkauft (Kleinunternehmer)“ and „Rest am Gutschein“ (amount or
  „n Stück“), multi-purpose redemption after „Zwischensumme“ with the rest,
  payout „Auszahlung Gutschein ····-XXXX“ with „Grund: …“ (a value voucher
  payout without the multi-purpose mark reads „Auszahlung Wertgutschein …“ as
  in the npm layout). Items are matched
  to entries per action and in order; the server placeholder `no-code` never
  appears. `KeckVoucher.receiptText` follows the same form and never shows the
  clear code. Receipts without new-form vouchers print the same bytes as
  before. Reason: a receipt without a server layout (cancellation answer,
  older backend) must show the same receipt.
- **Hanging indent.** `ReceiptGrid` (and so the printed sheet and
  `KeckReceiptSheetWidget`), the fallback print and both line widgets wrap a
  left-aligned text with leading spaces under the same indent, at 32 and 48
  characters. Reason: the notes below a voucher line are long; without the
  indent the continuation line looked like a new item. No existing receipt has
  such a text, so all older goldens are unchanged.
- **Texts**: 23 labels (22 `voucher.*`, `cancellation.voucher_back`) and 17
  sentences (`voucher_error.*`); `voucherErrorMessages` and
  `voucherErrorMessage(code)` map each voucher error code (`voucher_not_found`
  … `too_many_voucher_checks`) to a sentence (`voucherErrors` in
  `pos-texts.json`). Reason: both registers say the same words for the same
  error and decide on the code, never on the server's text.
- **Contract catch-up**: `receiptErrorCodes` gains `server_error` and
  `voucher_balance_changed`, `unknownOutcomeCalls` gains
  `orderSignatureCard`, `Aufrufe` gains `checkVoucher` and
  `reprintVoucherLabel`; the signature card order is an account task and is
  listed as not applicable in `zwillinge.yaml`. Code that compares these lists
  with a fixed length needs the new entries. Reason: the re-fetched export
  contains them, and the tests keep the lists equal to it.

## 11.2.1

- `sumCents`, `subSumCents`, the printed receipt and `KeckReceiptWidget` count
  value vouchers with the opposite sign on a cancellation receipt; new getter
  `KasseneckReceipt.valueVoucherSign`. Reason: the backend mirrors value
  vouchers onto a full cancellation with the same `action` and a positive
  value, and reverses the flow there (`receiptDueCents` already did). The
  cancellation of a sale paid partly with a value voucher (22.40, 17.50 by
  voucher, 4.90 cash) showed "Total -39.90" instead of the -4.90 actually
  refunded.
- On a cancellation receipt a mirrored promotional voucher no longer reduces
  `subSumCents`/`sumCents`; print and widget show it as a reference without
  an amount. Reason: the backend takes the discount back through compensation
  items ("Gutschein-Ausgleich") and applies a promo entry only to a positive
  bucket total. The cancellation of a 34.30 sale with a 10.00 promotional
  voucher showed "Total -34.30" instead of the -24.30 refunded.
- Other receipts are unchanged. npm twin 1.11.1.

## 11.2.0

Twin of `@kreiseck/kasseneck-api` `1.11.0` (contract files pulled from that
version): shifts, cash balance and the drawer log at the register (backend
„Schicht und Kassenstand“). Reason: a business with several staff or drawers
could not tell who held how much cash; sales, cash movements and counts now
belong to a shift in a drawer, and the register can open and close the shift,
book deposits and withdrawals and print the bons itself.

Cash position and tip list at the register: `ShiftRunningTotals.voucherRedeemedCents`
(0 when an older server omits it), `durationText(minutes)` (shared cases in
`shift-cases.json`) and the texts for the cash position card and the tip payout
list (`shift.*`, `duration.*`, `tip_payout.*`).

Printer warning: four short labels for the quiet warning line at the print
buttons (`printer.warn_unreachable`, `printer.warn_none`, `printer.check`,
`printer.set_up`).

Change float and take out / put in at shift close: a drawer can keep a fixed
change float; after counting, the register takes out the rest or puts money in.
`DrawerInfo.changeFloatCents` and `DrawerState.suggestedFromShiftNumber` (null
unless sent), `closeMyShift(afterCount: AfterCount(type: 'cash_drop' |
'change_in', amountCents: …))` (catalogue `afterCountTypes`; the type is checked
by the server), `Shift.afterCount`/`leftInDrawerCents`,
`ShiftSummaryReceipt.afterCount`/`leftInDrawerCents` (blind null) and
`ShiftCloseResult.afterCountReceipt` (the envelope receipt). New code
`after_count_not_permitted` in `posErrorCodes`. `shiftReceiptLayout` prints, after a
rule below the count, „Entnommen“ (negative) or „Eingelegt“ and „Bleibt in der
Kassenlade“ (bold); without `afterCount` the Z report is unchanged. For the bold
line `LayoutColumnsLine` gains `bold` (default false, written to JSON only when
true; grid, widget and printing follow it). Goldens `shift-close-take-out`,
`shift-close-put-in` from the contract; texts `drawer.change_float*`, `shift.*`
for the step „Geld entnehmen“, `shift_receipt.taken_out|put_in|left_in_drawer`,
`shift.counted|back|done|edit_amount` (row „Gezählt“, „Zurück“, step „Fertig“,
accessibility label „{title} ändern“), message `shift.change_float_missing`;
the bold column line is pinned in the byte twin test. Reason: the drawer kept everything after a
shift, so the next shift started with the whole day's cash.

Register polish: `shift.pay_ins`/`shift.pay_outs` (deposits and withdrawals as
two rows of the cash position instead of one net row),
`cash_movement.pay_in_amount`/`pay_out_amount` („{amount} einzahlen“, the book
button with the amount) and message `logout.cart_cleared` (second press logs
out and clears the cart). `shift.recount` now names the reason: „Der gezählte
Betrag weicht ab – bitte noch einmal zählen.“

Check before taking out: `closeMyShift(checkOnly: true)` runs the same check as
closing but closes nothing and books nothing (no `afterCount` either); the
result is `ShiftCloseResult.ready()` (`ready`, status `ready`) when closing with
this amount would go through, otherwise `recount` or the error
`comment_required` as before. Only `true` is sent; without it the call sends
the same bytes as before. The count still uses one of the two attempts; closing
afterwards with the same amount counts as the same attempt. Contract cases
`success_manager_check_ready` and `success_cashier_check_recount`. Reason: the
register asked for money to be taken out before it knew whether the count had
to be repeated or explained.

Additive; every existing call sends the same bytes as in 11.1.1 unless you
pass the new `drawerId`. The lists `posErrorCodes` (18 new codes),
`unknownOutcomeCalls` (4 more) and `Aufrufe.alle` (6 more) gain entries; code
that compares them with a fixed length needs the new ones.

- **Six calls** on `RegisterReceiptClient`: `getMyDrawerState`, `openMyShift`,
  `recordMyCashMovement`, `logMyDrawerOpenings`, `getMyShiftReport`,
  `closeMyShift`, same names and parameters as in npm. The four that write
  require an `idempotencyKey` (each entry of `logMyDrawerOpenings` its own) and
  end with an unknown outcome after a timeout (`isOutcomeUnknown`): send the
  same operation again with the **same** key, it takes effect once. Checked
  before sending: missing ids, missing key, empty list, a number beyond 2^53 - 1.
  Everything factual (catalogue, required fields per type, balance, claim) is the
  server's call.
- **Blind counting.** Without the right `cashView` the server sends no expected
  amount, no counted amount, no running totals and no suggestion; the model has
  `null` there, never `0`. `closeMyShift` returns a `ShiftCloseResult`:
  `recount` (count once more, not an error) or closed with the Z bon.
- **Without the right `shift`** `getMyDrawerState` still returns the open
  shift with its basic data only (`id`, `drawerId`, `cashregisterId`, `number`,
  `status`, `openedAt`, `openedBy`); every other field is `null`, so
  `Shift.openingFloatTakenOver` is a `bool?`. Reason: a user without the right
  saw no shift and the register blocked the sale although one was open.
- **Buffered drawer openings.** `DrawerOpeningEntry` takes `drawerId` and an
  `operator` (`DrawerOpeningOperator`: who opened the drawer while the entry was
  buffered; the server takes it only for a user of the business assigned to the
  register, otherwise the sending user). `DrawerOpeningsResult.drawerId` names
  the drawer that was logged into (the main drawer for a decommissioned one).
- **Models** (`pos.dart`): `DrawerState`, `Shift`, `CashMovement`,
  `ShiftSummaryReceipt` (also `ShiftReceiptData`), `CashMovementReceipt`,
  `OpenShiftResult`, `CashMovementResult`, `DrawerOpeningsResult`, `ShiftReport`,
  `ShiftCloseResult`, `DrawerOpeningEntry`, `TipPayout` and their parts, each
  with `toJson()` in the wire form. Catalogues `eurDenominations`,
  `movementTypes`, `manualMovementTypes`, `cashLocations`, `openingReasons`,
  `manualOpeningReasons`, `shiftReceiptKinds`.
- **Helpers** with shared cases (`shift-cases.json`): `sumDenominations`,
  `parseCentsAllowZero` (0 is valid: an empty drawer, no float; no floating
  point), `newIdempotencyKey` (`kasse-` and 32 hex characters, like the
  stocktake key).
- **Bons.** `shiftReceiptLayout` (Z bon „Schichtabschluss“, X bon
  „Zwischenbericht“) and `cashMovementLayout` („Kassenbewegung“) build a
  `ReceiptLayout` from the bon data of the response; the same goldens as npm,
  character by character. Blind values (`null`) leave their lines out, a real
  `0` is printed. No signature, no QR, no DEP. Print it like any other layout.
- **Bank or safe is optional.** `recordMyCashMovement` checks `location` only
  when given (from `cashLocations`, otherwise it throws before sending); the
  movement bon prints „Ort“ only when it is set, the label of `change_in` is
  „Wechselgeld“, and no shift bon prints „Kein Registrierkassenbeleg“ (the text
  `shift.not_a_receipt` is gone), like npm 1.11.0. Reason: the register no
  longer asks where the change came from or the drop went, and the note at the
  foot was not wanted on the slips.
- **Tips during the shift.** `DrawerState.tips` lists per employee what the
  running shift earned (`receivedImmediatelyCents`, `retainedCents`), what was
  already paid out from the drawer in this shift (`paidOutCents`) and the open
  claim against the drawer (`openCents`), for every session, also without
  `cashView`. `ShiftTipTotals` gains `paidOutCents`, the new `ShiftTip` adds
  `openCents` (`ShiftReceiptTip` is now a typedef of it). The server lets a
  user with only the right `shift` pay out the own claim with
  `recordMyCashMovement(type: 'tip_payout', recipientId: …)`. New helper
  `shiftTipLines(tip)` with `ShiftTipLine`: „verdient“ (immediate + retained)
  always, „über Lohn“, „schon genommen“ and „offen“ only when not 0, no line
  when everything is 0 (shared cases in `shift-cases.json`); the shift bons use
  it. Labels `shift_receipt.tip_earned` and `shift_receipt.tip_open` are new,
  `shift_receipt.tip_paid_out` reads „schon genommen“,
  `shift_receipt.tip_immediately` is gone, like npm 1.11.0. Reason: staff take
  their tips at any time, not only at the end of the shift, and the slip showed
  lines with 0,00 nobody needed.
- **Cash tip kept right away.** `sell(tipKeptByEmployee: true)` sends
  `tip: {cents, keptByEmployee: true}` (without it the payload stays byte for
  byte as before); `KeckTip.keptByEmployee` (sent only when `true`) and
  `KasseneckItem.keptByEmployee` (read, written, kept by `negative` for a
  cancellation). The receipt stays as it was (signed, in the DEP); in the cash
  position the amount is not part of the expected cash and counts as „schon
  genommen“ at once, the open claim does not grow. The server takes it only for
  staff tips paid in cash and received immediately. New optional business
  setting `PosBusinessSettings.tipKeptByDefault` (`posBusinessOptionalFields`,
  sent by the server only when stored, `null` = off; `posTipKeptByDefault`)
  presets the switch at the register. Labels `checkout.tip_kept` „gleich
  behalten“ and `tip.kept_setting`, message `tip.kept_setting_hint`, like npm
  1.11.0. Reason: a waitress who keeps 2 € of a 22 € cash payment left 20 € in
  the drawer while the expected cash said 22 € — a difference that was none.
  The hint now says „zählt nicht ins Soll der Lade“.
- **Cancelling with or without the tip.** `cancelReceipt` (register path and
  `KasseneckApi`) takes `refundTip` (answer to „Trinkgeld auch zurückgeben?“;
  `false` leaves the staff tip on the receipt, without `items` = every
  remaining quantity except the tip; `true` with `items` adds the open tip)
  and `tipRefundSource` (`drawer` | `employee`, `tipRefundSources`, only for a
  cash refund). Without both the payload stays byte for byte as before; a
  source outside the list or together with `refundTip: false` throws before
  sending. The rules both registers ask by, twins of npm 1.11.0 against the
  shared cases `cancellation-tip-cases.json`: `openStaffTipCents`,
  `cancellationItemsForTip` (positions only; the return choice still goes as
  `itemReturnDispositions`), `cancellationCashRefundCents` and
  `asksTipRefundSource`. `cancellationErrorCodes` gains `tip_refund_conflict`,
  `invalid_tip_refund_source` and `tip_refund_source_requires_cash`. Labels
  `cancellation.tip_refund_question/yes/no`,
  `cancellation.tip_source_question/drawer/employee`, messages
  `cancellation.tip_refund_missing` and `cancellation.tip_source_missing`.
  Reason: whether a tip goes back with a cancelled sale, and from whose
  pocket, is a decision at the register; drawer and tip figures follow it.
  With a value voucher on the receipt there is no „Nein“ (`asksRefundTip`
  false, hint `cancellation.tip_refunded_with_voucher`, send `refundTip: true`;
  the server refuses `false` with `tip_keep_not_possible_with_voucher`).
  `refundTip: true` without `tipRefundSource` on a cash refund means: from the
  drawer. After „Nein“ the tip line reads `cancellation.tip_stays` „bleibt“.
- **Tip handed back by the employee.** `ShiftTipTotals.refundedByEmployeeCents`
  („selbst zurückgegeben“, default 0, read as 0 when missing) and the line
  `shift_receipt.tip_refunded_by_employee` in `shiftTipLines` (only when not 0),
  like npm 1.11.0. Reason: „schon genommen -2,00“ was correct but read wrong.
- **Tip carried over from earlier shifts.** `ShiftTip.carriedOverCents` („aus
  früheren Schichten“, default 0, read as 0 when missing) and the line
  `shift_receipt.tip_carried_over` first in `shiftTipLines` (only when not 0),
  like npm 1.11.0. Reason: „verdient 9,00 · offen 15,00“ left 6,00 unexplained.
- **Drawer on the receipt.** `sell` and `cancelReceipt` take an optional
  `drawerId` (the drawer whose cash balance the receipt counts in); empty or
  only whitespace throws before sending. The device setting `drawerId` is
  optional without a default (`PosDeviceSettings.drawerId`, `null` = the main
  drawer of the register): read only as a valid id, written as an id or `null`
  to remove it (`posDeviceOptionalFields`).
- **Texts and errors.** Catalogue entries `shift.*`, `cash_movement.*`,
  `drawer.*`, `shift_receipt.*` and rules for the 15 new codes (with
  `shift_mode_off`: `openMyShift` on a drawer without shift mode, text
  `shift.mode_off`); `shift.required_other` for a user without the `shift`
  right when no shift is open. `shift.recount_exhausted` asks for the amount of
  the second count (a comment only above the threshold, `comment_required`).
- **Confirmation in the Kasseneck app.** The error code lists and
  `paymentCallRejectedCodes` gain `second_factor_required` and
  `action_confirmation_required`. Reason: the backend /v3 contract contains them
  since keck#657 (rejected before the handler), like npm 1.11.0.
  15 more labels and 2 more messages (`cash_movement.pay_*`, `drawer.recent_openings`,
  `drawer.reason_*`, `shift.resend/next/print_*/later`, `time.yesterday`,
  `tip_payout.recipient_required`, `shift.pending_hint`) so the registers take every text from the package.

## 11.1.1

- Documentation of `getCashregisterReport`: the daily report is only
  available for a closed day (yesterday or earlier); today returns
  `period_not_closed` like the current month. Reason: the backend accepts only
  closed days. No code change; npm twin 1.10.1.

## 11.1.0

- New `getCashregisterReport({year, month, day, start, end})` for the report
  PDF (v2): a closed month, a day up to today or a date range. Exactly one
  form; a mixed or partial input throws an `ArgumentError` before anything is
  sent. Reason: one successor for the report downloads, same rules as the
  customer panel.
- Deprecated `downloadMonthlyReport` and `downloadDailyReport`. Reason: the
  endpoints are deprecated; closed periods now return the v2 report. They keep
  working until they are switched off.
- Error code `password_change_required` added to all error-code lists and to
  `paymentCallRejectedCodes`. Reason: the backend rejects calls while a
  mandatory password change is open (before the handler ran), so a payment call
  with this code is `rejected`, not `unknown`.
- `InvoiceVatIdProof` gains `afterSupplyDate` (always present) and
  `supplyDateProof` (new `InvoiceSupplyDateProof` or `null`, always present).
  Reason: the backend now reports whether the VAT ID was checked on or before
  the supply date or only afterwards.
- Contract pinned to npm 1.10.0.

## 11.0.0

**Breaking:** the package no longer depends on the `sumup` plugin.
`SumupService` (`services/sumup_service.dart`), `SumupCheckoutResponse.fromSumup`
and the unused `KasseneckApi.checkSumup` are gone. Reason: every app that used
this package inherited the SumUp SDK and its minimum iOS version, even without
SumUp; and the app could not choose its own `sumup` version (0.14.2+ builds
without the gated Tap-to-Pay repository).

What stays: `CreditCardProvider.sumup`, `SumupCheckoutResponse` as a plain data
model (`fromMap`, `toJson`) and the SumUp block on receipt, preview and paper.

Migration: add `sumup` to your app, call `Sumup.init`/`Sumup.checkout`
yourself and build the result with the `SumupCheckoutResponse` constructor;
pass `toJson()` as `providerData` of the card payment like before.

## 10.7.2

The pub.dev homepage now points to <https://kasseneck.at/api-doku> instead of
the GitHub repository. Reason: the repository is already linked as
`repository`, so both links led to the same place, and nobody coming from
pub.dev found the API documentation, the sandbox access or a contact. The
issue tracker stays on GitHub.

No code changes; nothing else moves.

## 10.7.1

The dependency on `kreiseck_design` now allows `>=0.7.0 <0.9.0` instead of
`^0.7.0`. Reason: `kreiseck_design` 0.8.0 adds role overrides to `kdTheme`
(a product of the family keeps the forms in its own colour — karteck uses it
for graphite). On 0.x `^0.7.0` excludes 0.8.0, so an app that needs 0.8.0
could not resolve together with this package. 0.8.0 is additive; this package
uses only the logo, the fonts and `kdTheme` without overrides. Tested against
both 0.7.0 and 0.8.0.

No code changes; nothing else moves.

## 10.7.0

Twin of `@kreiseck/kasseneck-api` `1.8.0` (contract files pulled from that
version): stocktakes in the Inventory API and counting at the register
(backend „Lager-Kern Stufe 3“). Reason: until now a business could only fix its
stock by hand with losses and receipts; a real count with an expected quantity
at the time of counting, a review, recounts and a stored stocktake record was
only possible in the panel. A shop system and the register app can now take
part: the shop creates, reviews and closes, the register counts blind.

Additive; every existing call sends the same bytes as in 10.6.1. The lists
`inventoryEndpoints` (32 → 44), `inventoryErrorCodes`, `inventoryWarningCodes`,
`posErrorCodes`, `unknownOutcomeCalls` and `Aufrufe.alle` gain entries; code
that compares them with a fixed length or a fixed last entry needs the new
ones.

- **Stocktakes** (`InventoryClient`): `createStocktake(CreateStocktakeRequest)`
  (`StocktakeScopeInput`, `type` `key_date` or `perpetual`, blind by default),
  `listStocktakes` (named `status`, `locationId`, `updatedSince`, `limit`,
  `cursor`; without `updatedSince` most recently changed first, with it
  ascending and inclusive) and `iterateStocktakes`, `getStocktake`,
  `listStocktakeItems`/`iterateStocktakeItems` (`stocktakeId`, `openOnly`),
  `listStocktakeCounts`/`iterateStocktakeCounts` (`stocktakeId`, `articleId`),
  `recordStocktakeCount(RecordStocktakeCountRequest)`,
  `voidStocktakeCount(VoidStocktakeCountRequest)` (both answer
  `StocktakeCountResult` with the count and the item after it),
  `reviewStocktake(ReviewStocktakeRequest)`,
  `recountStocktake(RecountStocktakeRequest)` with `StocktakeRecountItem`,
  `closeStocktake(CloseStocktakeRequest)` (answers `CloseStocktakeResult` with
  the head and `warnings`), `cancelStocktake(CancelStocktakeRequest)` and
  `getStocktakePdf`.
- **The stocktake record as file or link.** `getStocktakePdf` answers the
  sealed `StocktakePdf`: `StocktakePdfFile` (`pdf`, the bytes, up to 9 MiB) or
  `StocktakePdfLink` (`download`: `StocktakePdfDownload` with `url`,
  `expiresAt`, `sizeBytes`, `sha256`, `fileName`, `contentType`; signed, 15
  minutes). `kind` is `pdf` or `download` as in the JS twin. Reason: a large
  record does not fit into a function answer. The transport serves it through
  the new `InventoryTransport.callPdfOrData`, which returns the sealed
  `PdfOrData` (`PdfOrDataFile` or `PdfOrDataPayload`): the counterpart of
  `createPdfOrDataTransport` in npm, as a method like
  `InvoiceTransport.callBinary`. An error envelope is the same domain error as
  on the JSON path, an empty or unreadable body the same `KasseneckHttpError`.
  `InventoryTransport` thereby gains the method `callPdfOrData`: a test double
  of your own that `implements InventoryTransport` (instead of extending it or
  passing a mock `httpClient`) no longer compiles until it adds the method.
- **Models:** `Stocktake`, `StocktakeScope`, `StocktakeProgress`,
  `StocktakeReview`, `StocktakeClosing`, `StocktakeCancellation`,
  `StocktakeTotals`, `StocktakeWarning`, `StocktakeSeal`, `StocktakePdfInfo`,
  `StocktakeActor`, `StocktakeItem`, `StocktakeRecount`, `StocktakeNotBooked`,
  `StocktakeInventoryLine`, `StocktakeCount`, `StocktakeCountVoided`,
  `StocktakeCountResult`, `StocktakePage`, `StocktakeItemPage`,
  `StocktakeCountPage`, `CloseStocktakeResult`, each with `toJson()` in wire
  form. Blind: before `review` the expected quantity, the difference and
  `needsCheck` are absent and therefore `null`; values (`…Cents`, `…Micros`)
  only with `costs`. Required numbers (round, counts, items, the counted
  quantity, `sizeBytes`) are integers or a response error; `counted: true`
  without a quantity, a missing `countedBy`, an actor that is not an object
  (also inside `countedBy`) and a count without `serialNumbers` are response
  errors, never a guessed value. `StocktakeItem.serialNumbers` is `null` when
  the server does not send it (the answer of counting and voiding), never an
  invented empty list. `progress.counted` is `null` outside `getStocktake`,
  never 0.
- **Catalogues and limits:** `stocktakeStatuses`, `stocktakeTypes`,
  `stocktakeScopeTypes`, `stocktakeCheckReasons`, `stocktakeNotBookedReasons`,
  `stocktakeSources`, `stocktakeActorTypes`, `stocktakeInventoryAsOf`;
  `stocktakeItemsMax` (5000), `stocktakeRecountItemsMax` (200),
  `stocktakeCountsPerItemMax` (200). The client does not check the limits.
- **Error and warning codes:** `inventoryErrorCodes` gains
  `stocktake_not_found`, `stocktake_not_open`, `stocktake_closed`,
  `stocktake_not_in_review`, `stocktake_closing`, `stocktake_location_busy`,
  `stocktake_review_running`, `stocktake_recount_open`,
  `article_not_in_scope`, `article_not_tracked`, `count_not_found`,
  `count_already_voided`, `serial_already_counted`, `too_many_counts` and
  `stocktake_not_closed` (contract order); `inventoryWarningCodes` gains
  `defect_capped`, `uncounted_items`, `not_booked` and `recount_uncounted`.
  New `inventoryBusyStocktakeId(error)` returns the open stocktake of
  `stocktake_location_busy` (`details['stocktakeId']`), otherwise `null`.
- **Counting at the register** (`RegisterReceiptClient`, same names as the JS
  twin): `listMyStocktakes` (`locationId`, `status`; an empty location counts
  as none), `listMyStocktakeItems` (`stocktakeId`, `openOnly`, `limit`,
  `cursor`), `listMyStocktakeCounts` (`ownOnly`, `articleId`),
  `recordMyStocktakeCount` (`cashregisterId` defaults to the register of the
  session) and `voidMyStocktakeCount`. `pos.dart` exports the stocktake
  models and `stocktakeStatuses`; `posErrorCodes` gains the 18 codes of the
  five endpoints.
- **`parseQuantityMilli(text, unit, {rule})`** (`pos.dart`) turns typed text
  into thousandths without floating point (BigInt inside): comma or point, at
  most three decimals, trailing zeros do not count. A point with exactly three
  digits after a non-zero whole part (`'1.000'`, `'12.500'`) is `null` for
  every unit and rule: in Austrian notation it is a thousands separator, on a
  keypad a decimal point, and a factor of 1000 would be booked as a
  difference; `'1,000'`, `'0.500'`, `'1.5'` stay valid. Pieces take whole
  numbers without separator only; `rule` (the stored `PosArticle.quantityRule`)
  wins over the default of the unit (`quantityRuleForUnit`), pass
  `QuantityRule.piece` for a serial-number article. Surrounding whitespace is
  removed by the rules of JavaScript's `String.prototype.trim`, not Dart's
  `trim` (which also drops U+0085), so `'\u00851'` is `null` here as in the JS
  twin. The 50 shared cases of `stocktake-quantity-cases.json` run 1:1 as a
  test.
- **Texts:** the catalogue (generated from `pos-texts.json` 1.8.0) gains the
  messages `stocktake.none_open`, `scan_or_search`, `counted`, `blind_hint`,
  `recount_hint`, `unknown_code`, `quantity_invalid`, `serials_capture`,
  `serials_mismatch`, `reason_missing`, `outcome_unknown` and the labels
  `stocktake.title`, `quantity`, `defective`, `count_zero`, `next`, `void`,
  `reason`, `progress`, `serial_numbers`, `recount`, `resend`, `my_counts`,
  `sent`, `unconfirmed`, `voided`.
- **Unknown outcome:** `createStocktake`, `recordStocktakeCount`,
  `voidStocktakeCount`, `reviewStocktake`, `recountStocktake`,
  `closeStocktake`, `cancelStocktake`, `recordMyStocktakeCount` and
  `voidMyStocktakeCount` are in `unknownOutcomeCalls` (now 64, the list of the
  contract). All of them take a required `idempotencyKey`: after
  `ErrorOutcome.unknown` resend with the **same** key, a count is then counted
  exactly once; a new key would count the goods a second time. The eight
  reading calls stay `rejected`.
- **Checked before sending**, as in npm, only what is surely wrong without the
  network: the key, empty `stocktakeId`, `locationId`, `articleId`, `countId`
  or `cashregisterId`, an empty reason, an empty recount list or an item
  without `articleId`, `limit` outside 1–200 and integers beyond ±(2^53 − 1). A
  negative quantity goes out (the server answers `invalid_quantity`).
- **Sign-in codes `app_check_missing` and `app_check_invalid`** from the
  contract (`errorCodes.auth`) are in `registerErrorCodes`, `posErrorCodes`,
  `receiptErrorCodes`, `cancellationErrorCodes`, `paymentErrorCodes`,
  `receiptEmailErrorCodes`, `invoiceRequestErrorCodes`,
  `inventoryRequestErrorCodes` and in `paymentCallRejectedCodes` (24 → 26):
  they are raised before the handler, so on the money calls they mean
  `rejected`. The backend sends them only to three endpoints of the admin app;
  no call of this package can receive them today, the lists only follow the
  contract.

## 10.6.1

`KeckReceiptSheetWidget` no longer loses the last character of a full line.
Reason: the widget measures one character of DM Mono and sizes the sheet to
`charsPerLine` of them, but drew its lines with whatever they inherited — the
app theme's letter spacing (Material 3 puts 0.25 on every character), the
device text size and iOS "Bold Text". None of that was in the measurement, so a
full line came out wider than the sheet and was clipped (in karteck a 32-char
payment line read "Kartenzahlun"). Even a plain `MaterialApp` with the default
theme made a 48-char line 12 px too wide.

The sheet now pins `letterSpacing`/`wordSpacing` to 0 and draws without device
text scaling and without "Bold Text": it is a facsimile of the paper with a
fixed number of characters. To show it larger, pass a larger `fontSize`.
Apps that wrapped the widget to work around this (neutral `DefaultTextStyle`,
`MediaQuery.withNoTextScaling`, `boldText: false`) can drop the wrapper.

No public symbol changes; the printed bytes are unchanged.

## 10.6.0

Twin of `@kreiseck/kasseneck-api` `1.7.0` (contract files pulled from that
version): `CashregisterEntry` gains the optional `autoLogout`
(`CashregisterAutoLogout` with `autoLogoutMinutes` 0/1/5/15/30 and
`logoutAfterSale`, each `null` when absent). Reason: the backend now reports a
register's own sign-out settings in `listMyCashregisters`; a client that
ignored them showed the operator's defaults on a register that had its own.
`autoLogout` is `null` when the register has no values of its own; a minutes
value outside 0/1/5/15/30 is dropped instead of passed on.

Additive; nothing that compiled before stops compiling.

## 10.5.0

Twin of `@kreiseck/kasseneck-api` `1.6.0` (contract files pulled from that
version): the Inventory API learns variant groups (backend stage 5c). Reason: a
shop sells the same apron in three sizes and two colours. Until now it had to
create six unrelated articles and keep their names, prices and codes in step by
hand; nothing told the shop or the register that they belong together, and
nothing stopped a second "M red". A variant group holds what they share and
guarantees that each combination exists once.

Additive; every existing call sends the same bytes as in 10.4.1. **One case
breaks at compile time:** `InventoryWebhookEvent` is sealed and gains the
subclass `InventoryVariantGroupEvent`, so a `switch` without `default` that
lists all subclasses needs a new case (the README example had one). Until
10.4.1 `variant_group.*` came back as `null`; now it is parsed. The lists
`inventoryEndpoints`, `inventoryErrorCodes`, `inventoryWebhookEvents` and
`Aufrufe.alle` gain entries at the end; code that compares them with a fixed
length or a fixed last entry needs the new ones.

- **Variant groups** (`InventoryClient`):
  `createVariantGroup(CreateVariantGroupRequest)` (with `createMatrix: true`
  every combination of the values, at most 100, or the listed `variants`
  of `VariantInput`, at most 100; never both),
  `updateVariantGroup(UpdateVariantGroupRequest)` (`name`, `defaults` as a
  partial update, `addAttributeValues`, or `active: false` to deactivate the
  group and all its variants for good), `getVariantGroup`,
  `listVariantGroups` (named `active`, `updatedSince`, `limit`, `cursor`,
  `VariantGroupPage`, sorted by `updatedAt` ascending) and the stream
  `iterateVariantGroups`. `VariantGroup` carries `attributes`
  (`VariantAttribute`: `key`, `label`, 1 to 30 `values`, in group order),
  `defaults` (`VariantGroupDefaults`: `unitPriceCents`, `vatRate`, `unit`,
  `groupId`, `stockTracked`, only those with a default), `active`,
  `variants` (`VariantGroupMember`: `articleId` and `variantAttributes` of
  every active variant) and the times. The group answers carry no articles:
  read them with `listArticles(variantGroupId: …)`.
- **Variants are articles**: `addVariant(AddVariantRequest)` creates one more
  variant and answers with the `Article` as `createArticle` does. A variant
  takes the article fields of `createArticle` (the name is optional); fields
  it does not name are filled from the group defaults at creation, the name
  defaults to "group value1 value2" in attribute order.
  `Article.variantGroupId` and `Article.variantAttributes` (already read since
  10.3) are set only on variants; the keys of `variantAttributes` come sorted
  by code point, the attribute order is in `VariantGroup.attributes`.
- **Clearing defaults**: in `updateVariantGroup`,
  `VariantGroupDefaultsInput(clear: {...})` clears single defaults (`null` on
  the wire), `clearDefaults: true` all of them (`defaults: null`), the same
  pattern as `UpdateArticleRequest.clear`.
- **Idempotency**: the three writes take `idempotencyKey` (required, 1 to 120
  characters, refused before sending when empty, blank or too long) and are in
  `unknownOutcomeCalls`: after `ErrorOutcome.unknown` resend with the same key.
  An interrupted `updateVariantGroup(active: false)` is completed by any
  repeat, also with a new key. `getVariantGroup` and `listVariantGroups` are
  reads and stay `rejected`.
- **Checked before sending**, nothing else (as npm): the key, an empty
  `variantGroupId`, `createMatrix: true` together with `variants` (also an
  empty list), an update without a change, `active` other than `false` or not
  alone, `defaults` together with `clearDefaults`, a `clear` that names
  another field or a field that is also set, and integers beyond
  ±(2^53 − 1), also in `defaults` and in every variant (the message names the
  place, `variants[1].unitPriceCents`). Fractions, a `variants` that is no
  list and a missing `variantAttributes`, which npm checks at run time, are
  ruled out here by the types. The limits (3 attributes, 30 values, matrix
  100, 250 active variants per group) are left to the server, so it can raise
  them; they are exported as `variantAttributesMax`, `variantValuesMax`,
  `variantMatrixMax`, `variantGroupActiveMax`.
- **Events**: `variant_group.created` and `variant_group.updated` in
  `inventoryWebhookEvents`, parsed as `InventoryVariantGroupEvent` with the
  group as `getVariantGroup` returns it. `updated` fires only on a visible
  change (new value, new or deactivated variant, name, defaults, deactivating
  the group). Two deliveries may overtake each other: keep the one with the
  later `updatedAt`.
- **Errors**: `inventoryErrorCodes` appends `variant_group_not_found`,
  `variant_already_exists` (with `field`, and `articleId` of the existing
  variant), `invalid_variant_attributes` (with `field` and `errors`, see
  `inventoryFieldErrors`), `variant_group_inactive` and `variant_limit`.
  `too_many_positions` now also answers a variant request that would need more
  writes than fit into one operation, with `field` (`variants`,
  `createMatrix`, or `externalIds` for `addVariant`); nothing is written then.
- **Reading a group**: `attributes` and `variants` are promised lists; a
  response without them, a fractional default price, a default of the wrong
  type, a variant without `articleId` or values that are not text throw
  `KasseneckValidationError` with `kind: 'response'`, never a substitute.
  A default sent as `null` counts as not sent.
- **Contract**: `zwillinge.yaml` pins npm `1.6.0`; `test/fixtures/vertrag/`
  pulled again (`surface.json` gains the five calls and the three writes in
  `unknownOutcomeCalls`, `v3/antworten/lager.json` the variant cases and
  events, the other files only their version); the text catalogue and the code
  table layout regenerated (version note only). No new entry in `ausnahmen`.
  New tests in `test/lager_varianten_test.dart`.

## 10.4.1

Twin of `@kreiseck/kasseneck-api` `1.5.1` (contract files pulled from that
version): every call with an effect reports `ErrorOutcome.unknown` when it
fails after the request went out: timeout, network error, HTTP 5xx, HTTP 200
with the `/v3` marker but an empty, non-JSON, status-less or non-object body,
and HTML with the marker. Reason: until 10.4.0 only the six signing and money
calls did. A goods receipt, a reservation or `issueInvoice` came back as
`rejected` („did not happen“) although the server may have booked it, and
whoever believed that and sent again with a **new** `idempotencyKey` booked
twice. The 10.4.0 note „a timeout on a write carries the outcome `rejected`“
is withdrawn.

A change to the safe side, no change on the wire: requests send the same body
as in 10.4.0 (only `Kasseneck-Client` carries the new version). No public
symbol is added, removed or changed; what changes is the `outcome` of the
errors listed below.

- **Which calls**: the list of the contract (`surface.json`,
  `unknownOutcomeCalls`, 52 names). New among the calls this package makes:
  inventory writes (`createArticle`, `updateArticle`, `deactivateArticle`,
  `receiveGoods`, `transferStock`, `recordStockLoss`, `changeStockCondition`,
  `reverseStockMovement`), reservations (`createReservation`,
  `extendReservation`, `releaseReservation`), inventory webhooks (create,
  update, delete, rotate the secret, test delivery), the invoice API
  (`issueInvoice`, `cancelInvoice`, `createCreditNote`, `recordInvoicePayment`,
  `createCustomer`, `updateCustomer`) and on the register
  `pairRegisterDevice`, `unpairRegisterDevice`, `setMyKasseSettings`,
  `setMyKasseLogo`, `setMyRegisterDeviceSettings`,
  `setMyCashregisterStockLocation`, `createPrintJob`, `sendReceiptEmail`.
- **Which stay `rejected`**: reading calls, the dry runs (`previewGoodsReceipt`,
  `previewInvoice`), the register sign-in sessions (`registerUserLogin`,
  `registerPinLogin`, `renewRegisterSession`, `endRegisterSession`) and
  `createPaymentLinkStripe`: a repeat books nothing.
- **Dry run only when it really is one.** A call is lowered to `rejected` only
  if it is `receiveGoods` or `issueInvoice` **and** the parameters that go out
  carry `dryRun` exactly `true`; both handlers check it that strictly.
  `dryRun: false`, `'true'` or `1` stay `unknown`, and so does any other call
  with `dryRun` in its parameters, because its handler does not know the field.
  There is no switch a caller could set: the transports
  (`InventoryTransport.call`, `InvoiceTransport.call`) decide from the
  parameters they encode. This differs from npm on purpose: npm's open
  transport takes `{ hasEffect }` and lowers only with `hasEffect: false` plus
  `dryRun: true`; the wrappers behave the same on both sides.
- **What to do**: with an `idempotencyKey`, send the same request with the
  **same** key; it takes effect once and returns the stored answer
  (`replayed: true` on invoices; inventory writes return the stored answer
  unchanged). Never a new key. Without a key (receipts, cancellations, money
  calls, settings, webhooks, `updateCustomer`, `createCustomer` without one)
  read the state first. The rule for receipts and payments is unchanged: look
  it up, never resend.
- **Register texts**: `callsWithEffect` and `pos-texts.json` are unchanged.
  `messageOutcome` follows the transport first, so a timeout or network error
  on the settings, pairing, unpairing or stock location calls now shows
  `network.outcome_unknown` instead of „try again“, the same sentence the web
  register shows with npm 1.5.1.
- **Guard**: `test/ausgang_einordnung_test.dart` compares the list in
  `lib/src/v3.dart` with `unknownOutcomeCalls` of the contract (equal and
  sorted), requires every name in `Aufrufe.alle` to be classified exactly once
  (with effect, reading, or repeatable), and checks each failure kind through
  the real `InventoryClient` and `InvoiceApi`: with effect `unknown`, reading
  and dry runs `rejected`.
- **Contract**: `zwillinge.yaml` pins npm `1.5.1`; `test/fixtures/vertrag/`
  pulled again (`surface.json` gains `unknownOutcomeCalls`, the other files only
  their version); the text catalogue and the code table layout regenerated
  (version note only). No new entry in `ausnahmen`.

## 10.4.0

Twin of `@kreiseck/kasseneck-api` `1.5.0` (contract files pulled from that
version): the Inventory API learns to write and to reserve, and the invoice API
learns `reservationId` and the VAT ID check. Reason: a shop that only reads
stock still oversells. It has to hold the goods at checkout, book what arrives
and leaves, keep its articles in sync and turn the reservation into a sale when
the order is invoiced, all with retries that never book twice. The invoice API
catches up with the VAT ID check of the backend, because a caller has to
decide by the code whether to retry later or not to issue at all.

Additive; every existing call sends the same bytes as in 10.3.0. **One case
breaks at compile time:** `InventoryWebhookEvent` is sealed and gains the
subclass `InventoryReservationEvent`, so a `switch` without `default` that
lists all subclasses needs a new case (the README example had one). Until 10.3
`reservation.*` came back as `null`; now it is parsed.

- **Writing** (`InventoryClient`, every write with `idempotencyKey`):
  `createArticle(CreateArticleRequest)`, `updateArticle(UpdateArticleRequest)`,
  `deactivateArticle(DeactivateArticleRequest)`, answering with the `Article`
  as `getArticle` returns it; `receiveGoods(ReceiveGoodsRequest)`,
  `transferStock(TransferStockRequest)`,
  `recordStockLoss(RecordStockLossRequest)`,
  `changeStockCondition(ChangeStockConditionRequest)`,
  `reverseStockMovement(ReverseStockMovementRequest)`, answering with a
  `StockOperation` (`operationId`, `movementIds`, `lotIds`, `warnings` of
  `InventoryWarning`); `previewGoodsReceipt(GoodsReceiptPreviewRequest)` is
  `receiveGoods` with `dryRun: true`, books nothing, needs no key and returns
  `GoodsReceiptPreview` (`GoodsReceiptPreviewLine`, the four values only with
  the permission `costs`, `hasValues`). Request parts: `ArticleInput`,
  `GoodsReceiptItem`, `LandedCost`, `GoodsReceiptSupplier`, `StockItem`.
- **Reservations**: `createReservation(CreateReservationRequest)` (all or
  nothing against `available`; `ReservationItemInput`),
  `extendReservation(ExtendReservationRequest)`,
  `releaseReservation(ReleaseReservationRequest)` (all, or per
  `ReleaseReservationItem`), `getReservation`, `listReservations` (named
  `status`, `reference`, `limit`, `cursor`, `ReservationPage`) and the stream
  `iterateReservations`. `Reservation` carries `status`, `reference`, `items`
  (`ReservationItem` with `quantity`, `redeemed`, `released` and the getter
  `open`) and `expiresAt`. `insufficient_available` lists the missing
  positions in `inventoryShortfalls(error)` (`InventoryShortfall`).
- **Idempotency key**: `idempotencyKey` is required on every write (1 to 120
  characters, `inventoryIdempotencyKeyMax`). The client refuses to send an
  empty, blank or too long key and never trims or shortens it. After a timeout
  or network error, send the same request with the same key: it takes effect
  once and returns the stored answer; the same key with other content gives
  `idempotency_conflict`. Nothing is retried automatically.
- **Checked before sending**, nothing else: the key, required ids (also
  `items[].articleId`), integers beyond ±(2^53 − 1) anywhere in the request
  (the server computes in JavaScript and would receive another number),
  `expiresInMinutes` outside 5 to 43,200 (`reservationMinutesMin`,
  `reservationMinutesMax`), an update without a field, an empty release list.
  All throw `KasseneckValidationError` with `kind: 'request'`.
- **Models**: `Article` gains `description`, `stockKind` and
  `minStockByLocation` (missing on an older server: `null`, `null`, `{}`).
  `StockMovement` gains `reservedDelta` (0 for every other movement and on an
  older server) and `StockAfter.reserved` (only on reservation movements,
  otherwise `null`). The minimum stock (`below_minimum`,
  `listStock(belowMinimum: true)`, `stock.below_minimum`) is measured against
  `available = onHand − reserved`. A fractional value in any of these throws
  `KasseneckValidationError` with `kind: 'response'`.
- **Events**: `reservation.expired`, `reservation.released` and
  `reservation.redeemed` in `inventoryWebhookEvents`, parsed as
  `InventoryReservationEvent` with the reservation and its status afterwards;
  `released` and `redeemed` also fire for a partial release or redemption.
- **Catalogues and errors**: `inventoryErrorCodes` keeps its 12 codes in front
  and appends the codes of the write side in contract order
  (`idempotency_key_required`, `idempotency_conflict`, `exceeds_stock`,
  `code_taken`, `external_id_taken`, `stock_kind_locked`, `article_inactive`,
  `insufficient_available`, `reservation_not_found`, `reservation_not_active`
  …). New lists `inventoryWarningCodes` (with `isInventoryWarningCode`; a
  warning is not an error, the booking took effect), `stockKinds`,
  `stockLossReasons`, `withdrawalTypes`, `landedCostTypes`,
  `landedCostAllocations`, `reservationStatuses`; `stockMovementTypes` gains
  `reservation` at the end.
- **Invoice API, reservations**: `IssueInvoiceItemInput` (an
  `InvoiceItemInput` with `reservationId`, needs `articleId`) redeems a
  reservation when the invoice is issued; `IssueInvoiceRequest.fromJson` reads
  items as `IssueInvoiceItemInput`. New codes `reservation_not_found`,
  `reservation_mismatch`, `reservation_not_active` at the end of
  `invoiceErrorCodes`; new notice `reservation_expired` with
  `InvoiceNotice.reservationId`: the invoice is issued and sells without the
  reservation. Credit notes do not take the field (`validation`).
- **Invoice API, VAT ID check**: codes `vat_id_invalid` and
  `vat_id_check_pending` (with `details['retryAfter']` in seconds) after
  `amount_too_large`, before the reservation codes, as in the backend.
  `IssueInvoiceRequest.acceptVatIdRisk` issues despite a pending check, the
  issuer bears the risk; an invalid VAT ID blocks even with it. It does not
  count towards idempotency, so the retry keeps its key. `Invoice.vatIdProof`
  (`InvoiceVatIdProof`: `checkedOn`, `source`, `level`, `code`) and
  `Invoice.vatIdRisk` (`InvoiceVatIdRisk`: `acceptedOn`), otherwise `null`.
- **Differences from npm, on purpose.** Requests are classes, so a fractional
  quantity or a missing key cannot be written at all (npm checks both at run
  time). `null` in a request means „not given“ and is not sent; clearing a
  field in `updateArticle` goes through `UpdateArticleRequest.clear`, which
  refuses a field that cannot be cleared or is set at the same time.
  `receiveGoods` has no `dryRun`: the preview is its own call and type.
  `listReservations` takes named parameters like the other lists here.
  `ReservationItem.open` is a convenience npm does not have. As in npm, a
  timeout on a write carries the outcome `rejected`; the key, not the outcome,
  makes the retry safe.
- **Contract**: `zwillinge.yaml` pins npm `1.5.0`; `test/fixtures/vertrag/`
  pulled again (the 13 new calls, which `Aufrufe.alle` now knows, catalogues,
  `warningCodes`, the 5b cases in `v3/antworten/lager.json`, the VAT ID cases
  in `v3/antworten/rechnungen.json`, five new invoice examples); the text
  catalogue and the code table layout regenerated from the same version
  (content unchanged). No new entry in `ausnahmen`.

## 10.3.0

Twin of `@kreiseck/kasseneck-api` `1.4.0` (contract files pulled from that
version): the Inventory API, read side and account webhooks, as the new
library `package:kasseneck_api/inventory.dart` (twin of `./inventory`).
Reason: since stage 5a the backend offers articles, locations, stock and the
stock ledger under `/v3` with the account's `api_key`, plus webhooks that
report every stock change within seconds. A shop backend written in Dart
needs a typed client and, above all, a signature check it cannot get wrong.

Additive, no breaking change; every existing call sends and reads the same
bytes as in 10.2.0.

- **`InventoryClient(apiKey: …)`** (`inventory.dart`, server only, base
  `https://api.kasseneck.at/v3`, `kInventoryBaseUrl`; `InventoryTransport` and
  `InventoryClient.withTransport` as for the invoice API): `getArticle`,
  `listArticles`, `lookupArticleByCode` (`code:`, or `externalSystem:` with
  `externalId:`), `listLocations`, `getStock`, `listStock`,
  `listStockMovements`, and the streams `iterateArticles`, `iterateStock`,
  `iterateStockMovements` that follow `nextCursor` until `null` (the same
  cursor twice, the start cursor included, ends the stream with a response
  error instead of looping). Webhook management: `createWebhook`,
  `updateWebhook` (`removeDescription: true` sends `description: null`),
  `deleteWebhook` (record `({webhookId, deleted})`), `listWebhooks`,
  `sendWebhookTest`, `rotateWebhookSecret`, `listWebhookDeliveries`. Checked
  before sending, nothing goes out: an empty id or cursor, `limit` outside
  1–200, `code` together with `externalSystem`/`externalId`, an empty
  `events` list, an update without a change. A partner key (`pk_…`) or a
  cashbox token (`cb_…`) throws when the client is created.
- **No Flutter behind `inventory.dart`.** The package still needs the
  Flutter SDK to resolve (`flutter: sdk: flutter` in `pubspec.yaml`), but
  `lib/inventory.dart` imports no Flutter code, so a shop server runs it
  without `dart:ui`. `test/lager_ohne_flutter_test.dart` follows every import
  and export behind it and fails on `package:flutter` or `dart:ui`.
- **Models**: `Article` (incl. `stockLocationIds`; `purchasePriceMicros` only
  with the account permission `costs`, `hasPurchasePriceMicros` says whether
  the field was sent), `ArticlePage`, `Location`, `LocationAddress`,
  `StockLevel` (`onHand`, `reserved`, `available`, `defective`, `sequence`,
  `updatedAt`), `StockResult`, `StockPage`, `StockMovement` (with
  `StockAfter`, `StockMovementSourceRef`, `StockMovementLot`; value fields
  with `has…`), `StockMovementPage`, `InventoryWebhook`
  (`consecutiveFailures`, `InventoryWebhookLastDelivery`),
  `InventoryWebhookWithSecret`, `InventoryWebhookList`,
  `InventoryWebhookDelivery` (`deliveryId`, status `delivered`, `pending`,
  `failed`, `dropped`), `InventoryWebhookTestResult`,
  `InventoryWebhookTestDelivery`, `StockChangedEventData`,
  `StockBelowMinimumEventData`. `StockValue` is the register's type, exported
  again. Each model has `toJson()` in the wire form; optional fields the server
  sent are kept, absent ones stay absent. Quantities are integer thousandths,
  money integer cents, purchase prices integer micro-euros; `available` may be
  negative. A fractional or missing quantity, amount or `sequence` throws
  `KasseneckValidationError` (`response`), as for register stock since
  10.2.0; `4000.0` counts as an integer, as in JavaScript. Catalogue values
  (type, source, cause, status) stay `String`, so an unknown value arrives
  unchanged; an unknown location type becomes `null`, as in npm.
- **Incoming webhooks**: `verifyInventoryWebhookSignature(secret, header,
  rawBody, {toleranceSec = 300, now})` returns `bool` and never throws:
  HMAC-SHA256 over `"<t>.<raw body>"`, constant-time comparison, 300 seconds
  in both directions, several `v1=` parts allowed, `t` only as 1 to 15 digits,
  `secret` a `String` or a list of them, `rawBody` a `String` or bytes;
  checked against the backend's test vector (t=1700000000). Synchronous,
  unlike npm (which uses WebCrypto): `package:crypto` is pure Dart.
  `parseInventoryWebhookEvent(rawBody)` returns the sealed
  `InventoryWebhookEvent` (`InventoryStockChangedEvent`,
  `InventoryStockBelowMinimumEvent`, `InventoryArticleEvent`) with
  `accountId` in the envelope; an event type this version does not know
  returns `null`, a body that is no envelope throws `KasseneckValidationError`
  (`response`). Header names `webhookSignatureHeader`, `webhookEventHeader`,
  `webhookDeliveryHeader`, window `webhookToleranceSec`.
- **Errors** through the existing classes: `inventoryErrorCodes`
  (`rate_limited` with `retryAfterSec`, `inventory_api_not_enabled`,
  `module_inactive`, `article_not_found`, `invalid_cursor`, `webhook_limit`
  and the other webhook codes), `inventoryRequestErrorCodes`,
  `isInventoryErrorCode`, `inventoryErrorCode`, `isInventoryError`,
  `inventoryFieldErrors`, `inventoryRetryAfterSec` (a fractional wait is
  rounded up).
- **Lists as data**: `inventoryEndpoints`, `inventoryWebhookEvents`,
  `inventoryWebhookEnvelopeFields`, `locationTypes`, `stockMovementTypes`,
  `stockMovementSources`, `stockConditions`, `stockChangeCauses`,
  `webhookDeliveryStatuses`, `inventoryWebhookLimit`, `inventoryListLimitMax`,
  each held against `surface.json` (key `inventory`) and the backend
  catalogues. A goods receipt is `goods_receipt`, opening stock taken over is
  `takeover`; `receipt` only ever means a sales receipt (`source.type`).
- **Differences from npm, on purpose.** Time filters (`updatedSince`,
  `changedSince`, `from`, `to`) take a `DateTime`, not a string: the server
  accepts only full ISO 8601 timestamps, and a `DateTime` always produces one
  (UTC, milliseconds, like `Date.toISOString()`). A bad key throws
  `KasseneckValidationError` (`request`) as in `InvoiceApi`; Dart has no
  `KasseneckAuthError`. `createdAt` of an event must be an integer.
  `StockLevel` shares its name with the register's `StockLevel` in
  `pos.dart`, as in npm; import one of the two libraries with a prefix if you
  need both.
- **Dependency**: `crypto` moves from `dev_dependencies` to `dependencies`
  (dart-lang, pure Dart) for the HMAC.
- **Contract**: `zwillinge.yaml` pins npm `1.4.0`; `test/fixtures/vertrag/`
  pulled again (`v3/antworten/lager.json` with real responses and delivered
  webhook events, the 14 new calls in `surface.json`, which the call list
  `Aufrufe.alle` now knows); the text catalogue and the code table layout
  regenerated from the same version (content unchanged).

## 10.2.0

Twin of `@kreiseck/kasseneck-api` `1.3.0` (contract files pulled from that
version): the stock feature of npm 1.2.0 and the article codes and stock
labels of npm 1.3.0. Closes issue #85. Reason: since stage 2 of the stock
module the backend books sales, cancellations and invoices against the stock
of a location; the register app has to show locations and stock, choose its
own location, say where returned goods go and tell the server which article a
line is, and external invoicing systems have to name the article.

Additive, no breaking change: receipts, cancellations and invoices without the
new fields send the same bytes as in 10.1.2. One behaviour change in
`bookTile`, see "Article id in the cart".

- **Stock at the register** (`pos.dart`, register path `/api/v3` only):
  `RegisterReceiptClient.stockLocations()` (`listMyStockLocations`),
  `.stock({locationId, articleId, belowMinimum})` (`listMyStock`) and
  `.setStockLocation({required stockLocationId, cashregisterId})`
  (`setMyCashregisterStockLocation`; `stockLocationId: null` resets to the
  default location, the parameter is required so a reset is never an
  accident). Models `StockLocation`, `StockLocationAddress`,
  `StockLocationType`, `StockLevel`, `StockValue`, `StockList`,
  `CashregisterStockLocation` and the list `stockLocationTypes`. Quantities are
  integer thousandths of the base unit and keep their sign; `values` is `null`
  without the permission `stockCosts`. A missing or fractional quantity is
  never read as `0`: it throws `KasseneckValidationError` (`response`), and a
  register treats that as "stock temporarily unavailable" and keeps selling.
  New fields `PosArticle.stockLocationIds`, `CashregisterEntry.stockLocationId`
  and `RegisterCashregisterState.stockLocationId`.
- **Stock permissions** on `RegisterUserPerms`: `stockView` (`bool?`),
  `stockCosts`, `stockMove`, `stockLoss`, `stocktakeCount`, `stocktakeClose`,
  `stockLocation`; they no longer land in `other`. New
  `stockViewOf(perms)` (`pos.dart` and `register.dart`): a missing `stockView`
  counts as granted, only an explicit `false` blocks it, as in the backend.
  **Note:** `perms['stockView']` still returns the raw value and gives `false`
  when the key is missing, while `stockViewOf` gives `true`. For the display
  always use `stockViewOf`.
- **Returns on cancellation.** Both `cancelReceipt` (`KasseneckApi` and
  `RegisterReceiptClient`) take `returnDisposition` (default for the call) and
  `itemReturnDispositions` (`Map<int, String>`, line index as in `items` to
  the choice for that line). Values from the new `returnDispositions`
  (`restock`, `defective`, `disposed`; also `ReturnDisposition` and
  `isReturnDisposition`, exported from `pos.dart`, `kasseneck_api.dart` and
  `invoice.dart`). Checked before sending: an unknown value, a per-line choice
  without `items` or for an index not in `items` throws
  `KasseneckValidationError` (`request`). Why a map and not a third field on
  `CancellationItem`: `CancellationItem` is the record
  `({int index, int quantity})`, and record literals `(index: 0, quantity: 1)`
  are used in apps and examples; records have no optional fields, so a third
  field would break every one of them. Cancellation lines read from the server
  carry `KasseneckItem.originalIndex` and `.returnDisposition`; an unknown
  choice in `cancellations[]` is dropped when reading, as in npm.
- **Article codes** on `PosArticle`: `number`, `ean`, `internalCode`
  (unchanged text; empty, whitespace-only or wrong type becomes `null`) and `stockTracked`
  (`bool?`, `null` = the response says nothing).
- **Article id in the cart.** `CartItemDraft.articleId` and
  `Position.articleId` (optional); `draftFromArticle` sets it, the cart keeps
  it through `withQuantity` and `subtracted`, and the receipt item sends it
  as `articleId`. **Behaviour change:** `bookTile(bundle: true)` now bundles
  only lines with the same article id. Two articles that look the same (name,
  price, rate) stay two lines, as do an article and a free item, because each
  books its own stock. Free items (no id, or an empty one, also on a
  hand-built `Position(articleId: '')`) bundle as before and send the same
  bytes as before.
- **Stored form.** `migrateStoredReceiptJson` drops the internal
  `lagerStandortId` and turns `rueckgabe` into `returnDisposition` on items and
  in `cancellations[].items` (`lager`/`defekt`/`entsorgt` to
  `restock`/`defective`/`disposed`, unknown values are dropped). Stored
  articles (`PosArticle.toJson`) carry `stockLocationIds` and the codes.
- **Invoice API** (`invoice.dart`, as npm 1.2.0):
  `InvoiceItemInput.articleId` and `IssueInvoiceRequest.stockLocationId`;
  `returnDisposition` on `cancelInvoice` and `CreditNoteRequest`, per line
  through the new `CreditNoteItemInput` (a subclass of `InvoiceItemInput`, so
  `CreditNoteRequest.items` keeps its type and existing callers stay valid).
  Fields go out only when set and exactly as given. As in npm, the server
  checks them: an unknown return choice, a choice on an invoice line or an
  id of the wrong shape comes back as `validation` with the field path
  (`invoiceFieldErrors`). The six stock examples of the
  contract (`invoice-api-examples/`) now run in `rechnung_api_test`; the skip
  is gone.
- **Contract npm 1.3.0**: the `stock.*` labels (`stock.all_articles`,
  `stock.location`, `stock.default_location`, `stock.resolved`,
  `stock.where_to`, `stock.available`, `stock.return_restock`,
  `stock.return_defective`, `stock.return_disposed`), the message
  `cancellation.input_rejected` and `returnDispositionLabels` (each return
  choice to its label key) in the generated catalogue. The `offen` lines of
  issue #85 in `zwillinge.yaml` are gone.

## 10.1.2

Twin of `@kreiseck/kasseneck-api` `1.2.2` (contract files pulled from that
version). Patch: no change to what a receipt or a request looks like, and the
stock feature of npm 1.2.0 is **not** part of this release (open in
issue #85).

- **Test fixtures carry a made-up signature card serial.** The serial of a real
  signature card (signature card line, machine-readable code of the receipt
  fixtures) is replaced by the made-up `5A1C3E07` (same length), as in npm
  1.2.2. Reason: fixtures only carry made-up identifiers. Every changed
  fixture differs from its predecessor by exactly that serial (checked file by
  file, hex goldens on decoded bytes); the recorded hashes of the ESC/POS byte
  streams (`zwilling_bytestrom_test`, `code_table_receipt_test`,
  `stored_layout_test`) are recorded anew and equal the ones the npm twin
  records. No code change in the printing path.
- **En dash in the invoice texts.** npm 1.2.1 swapped the em dash for the
  spaced en dash in five invoice texts per language
  (`pdf.direct_debit.warning`, `pdf.footer.note`, `tax.reverse_charge.text`,
  `einvoice.exemption.small_business`, `einvoice.exemption.outside_scope`).
  Reason: German typography uses the en dash; the frozen 0.x catalog in
  `test/fixtures/vor-1.0/` follows, so the rename check stays character-exact.
  Anyone comparing these texts byte by byte updates the five sentences.
  `texte_katalog.dart` is regenerated (version note only).
- **Error codes of the contract caught up** (additive lists). `api_not_approved`
  (the developer area has not approved the account for the live API) is in
  `registerErrorCodes`, `posErrorCodes`, `invoiceRequestErrorCodes` and the
  Auth/edge codes of the receipt lists; `posErrorCodes` also gains
  `location_inactive`, `location_not_found` and `server_error`, and
  `cancellationErrorCodes` gains `invalid_return_disposition`. Reason: the
  lists are compared to the contract in both directions. **Behaviour change:**
  `api_not_approved` is in `paymentCallRejectedCodes`, so a payment call
  answered with it now has the outcome `rejected` instead of `unknown`:
  nothing was charged, the approval gate runs before the handler.
- **Not yet carried (issue #85):** the stock calls, the stock permissions,
  `returnDisposition` and the stock fields of the invoice API. They are listed
  as `offen` in `zwillinge.yaml`; the invoice examples that use them are
  skipped in `rechnung_api_test` until then.

## 10.1.1

Twin of `@kreiseck/kasseneck-api` `1.1.1` (contract files pulled from that
version). Additive; receipts are byte for byte the same as in 10.1.0 (the
shared cases `code-table-receipt.*` are unchanged).

- **Test sheet asks for the right row.** Reason: a Bluetooth printer that
  only knows PC437 printed rows 2 and 3 with correct umlauts but wrong glyphs
  for `€` and `§` (`╒`, `⌡`), and row 4 correct with gaps for `€` and `§`.
  "The first line that looks like the reference" confused users, and "the
  row with correct umlauts" would pick row 2. The sheet now says: the row
  with no wrong character; a gap is fine; if several fit, the one with the
  fewest gaps; if none fits, 6. The reference heading reads "So sehen die
  Zeichen richtig aus" (32 columns, no colon, which would make it wrap).
  Everything outside the test rows stays pure ASCII, so "Lücke" from the
  catalogue stands as "Luecke" on the sheet. Rows, big numbers, margins and
  the end reset are unchanged. Lines and bytes match the shared cases
  `code-table-test-sheet.*` of npm.
- **Screen texts** (`pos.dart`, regenerated from `pos-texts.json`):
  `codetable.question` is now "In welcher Zeile steht kein falsches
  Zeichen?"; new `codetable.question_hint`, `codetable.preview_title`,
  `codetable.apply`, `codetable.other_row`, and for the sheet
  `codetable.instruction_title` and `codetable.instruction_none`.
- **Preview** (`printing.dart`, new): `codeTablePreviewText(CodeTableId)`
  returns the sample "Käsekrainer 3,50 €" / "Tee 80°" as it prints with that
  table (lines joined by `\n`), e.g. `pc437` gives "Käsekrainer 3,50 EUR".
  Reason: the cashier sees the effect of a row before applying it. Matches
  the shared case `code-table-preview.json`.

## 10.1.0

Twin of `@kreiseck/kasseneck-api` `1.1.0` (contract files pulled from that
version). Additive: a receipt printed without a chosen code table is byte for
byte the same as in 10.0.0. One fix changes bytes, see the last point.

- **Code tables for thermal printers** (`printing.dart`, new). `CodeTableId`
  (`wpc1252`, `pc858`, `pc850`, `pc437`, `iso8859_15`, `replacement`),
  `CodeTable` (`id`, `number`, `escT`, `missing`), `codeTables`,
  `codeTableById`, `codeTableFromSetting` (the stored `codePage` setting to a
  table) and `encodeForCodeTable`. Every table prints the ten German
  characters (ä ö ü Ä Ö Ü ß € § °) as one byte or, where the table lacks one,
  as replacement letters (`€` -> `EUR`, `§` -> `Par.`), never as `?`. Bytes
  and `ESC t` numbers as in the shared case `code-tables.json`. Reason: `ESC
  t n` is not numbered the same on every printer; many printers printed
  umlauts wrong, and the register had no way to pick the right table.
- **Test sheet** (`printing.dart`, new). `codeTableTestSheet` gives the sheet
  in the receipt sheet model (`CodeTableTestSheet` with `rows`),
  `codeTableTestSheetBytes` the ESC/POS bytes: the reference line as a raster
  image, then one line per table, its number large, switched with `ESC t n`.
  Always 32 columns; on 80 mm the block is centred with `GS L`. Also
  `CodeTableTestSheetRow`, `codeTableTestSheetChars`,
  `codeTableReferenceImage`. Lines and bytes match the shared cases
  `code-table-test-sheet.*` of npm. Reason: the cashier picks the table by
  the first line that looks like the reference.
- **Receipts with a chosen table.** New optional `codeTable` on
  `PrintPaper`, `KeckPrinterService.getPaperFromReceipt`,
  `KeckPrinterService.getBytesFromReceipt`, `KasseneckReceipt.getPrintBytes`
  and `KeckPrinter.printReceipt`. With a table, every line announces its `ESC
  t`, `€` stays a real byte where the table has it, and characters the table
  lacks become replacement letters before the columns are computed, so no
  column shifts. Byte for byte the shared cases `code-table-receipt.*` (four
  receipts, six tables). Without `codeTable` nothing changes (table 16,
  `EUR`).
- **Sheet model and widget.** `SheetLine.doubleSizeLead` (optional): the
  first n columns are one cell printed double width and height (only the test
  sheet sets it; `toJson` writes it only when set). New
  `KeckReceiptSheetWidget.fromSheet(sheet: ...)` draws a finished sheet and
  shows such a line two lines high with the number double size and bold, as
  on paper.
- **Texts.** The catalogue carries the new `codetable.*` sentences and labels
  of `pos-texts.json` 1.1.0 (`codetable.question`, `codetable.instruction`;
  `codetable.title`, `codetable.reference`, `codetable.replacement_note`,
  `codetable.missing` with `{chars}`, `codetable.print_again`,
  `codetable.not_checked`, `codetable.check`, `codetable.current` with
  `{number}`).
- **Fix: `CP437` sent Latin-1.** `EscPosGenerator` announced `ESC t 0` for
  `setGlobalCodeTable('CP437')` (or `PosStyles(codeTable: 'CP437')`) but sent
  the Latin-1 bytes, so an `ä` (0xE4) printed as `Σ`. It now sends the CP437
  bytes (`ä` = 0x84, as `pc437`); `§`, which CP437 lacks, prints as `Par.`.
  `CP1252` and no table are unchanged. The generator also accepts the table
  names of the catalogue (`setGlobalCodeTable('pc858')`). Reason: a device
  set to CP437 printed wrong umlauts on every line.
  **`PosStyles.defaults()` carries `codeTable: 'CP437'`**, so text printed
  with it changes the same way: `EscPosGenerator.text`/`row`,
  `KeckPrinter.printText`, `KeckPrinterService.printText` and
  `CustomPrintJob.text` when the caller passes `PosStyles.defaults()` (or
  another style with `CP437`). No path of the package itself uses that
  style: receipts, the printer test print, logo, brand mark and QR print the
  same bytes as in 10.0.

Migration: `doc/migration-10.md`, section "10.1".

## 10.0.0

First stable release of 10.0, the twin of `@kreiseck/kasseneck-api` `1.0.0`
(contract files pulled from that version). Content identical to
`10.0.0-rc.2`; the sections below list what 10.0 changes against 9.x and what
changed between the release candidates. 8.x and 9.x stay frozen on the
`release/8.x` and `release/9.x` branches. Migration: `doc/migration-10.md`.

## 10.0.0-rc.2

Second release candidate of 10.0.0, the twin of `@kreiseck/kasseneck-api`
`1.0.0-rc.5` (contract files pulled from that version). Changes since
`10.0.0-rc.1`:

- **The register's sentences and the rules that pick them** (`pos.dart`, new).
  `posMessages`, `posLabels`, `messageText`, `labelText` and
  `messageAppliesTo` are generated from the contract file `pos-texts.json`
  (`tool/texte_erzeugen.dart`; a test fails when the generated file and the
  contract differ), so the app shows the web register's sentence word for word.
  `findErrorRule(kind, code:, outcome:)` applies a rule from `errorCodeRules`,
  then from `errorOutcomeRules`, then the one rule of the kind from
  `errorRules`. `errorRules` is the list of `1.0.0-rc.4`, one rule per kind:
  code that looks rules up by kind only keeps showing the same sentences.
  Reason: the edge codes (`route_missing`, `dialect_mismatch`, ...) put a
  technical sentence in front of the cashier.
- **Timeout and network error on a call with an effect.** `messageOutcome`
  treats them as outcome unknown on every call from `callsWithEffect`
  (`createReceipt`, `cancelReceipt`, `financeWebService`, `hobexPayApi`,
  `hobexRefundApi`, `stripeCaptureIntent`, `createPrintJob`,
  `sendReceiptEmail`), and the sentence is the new `network.outcome_unknown`
  ("... der Vorgang kann trotzdem gebucht sein ..."), never "erneut
  versuchen". The transport keeps its own `outcome` (print job and receipt
  email stay `rejected`). Reason: a retry after a lost answer booked, printed
  or mailed twice.
- **New sentences and labels:** `server.connection_disturbed`,
  `server.response_unreadable`, `network.outcome_unknown`;
  `register.device_unnamed`, `login.locked_seconds` (`{seconds}`),
  `split.remaining_with_rounding` (`{amount}`, `{cents}`).
- **`ReceiptDueError` instead of `ArgumentError`.** `receiptDueCents` and its
  siblings throw a typed error with `code` `receipt_due_unavailable`, a
  `reason` from `receiptDueErrorReasons` (the same nine names as npm) and
  `outcome` `rejected`: nothing was sent. The shared cases of
  `receipt-due-errors.json` pass; the generated cases compute unchanged.
  `ReceiptDueTip.fromKeckTip` throws the same error (`invalid_tip`) when the
  tip names recipients but `isOwner` is missing (was `ArgumentError`), and now
  also for an empty `recipients` list, which rc.1 treated as a tip without
  recipients (as npm, the direct `ReceiptDueTip(cents, recipients: [])` and
  the server do).
- **Stored layouts.** `migrateStoredReceiptJson` leaves out a layout that is
  only partly readable (no or empty `lines`, a line that is not an object, no
  `paperSize`), so the receipt is rebuilt locally with TESTKASSE and the
  warning lines; keys are renamed in place, an unknown banner tone goes
  through as it is. New `storedLayoutJson` does the same for a layout on its
  own (twin of npm `fromStoredLayout`). There is no `toStoredLayout`: this
  package never writes the 0.x inner form.
- `pos.dart` also exports `ErrorOutcome` and `isOutcomeUnknown`.

The table of these changes is part H of [`doc/migration-10.md`](doc/migration-10.md).

## 10.0.0-rc.1

Release candidate of 10.0.0. The package speaks the English API `/v3` and
nothing else, and its own surface is English as well: class, field, method,
parameter and enum names, library paths, error codes and the contract files it
is tested against. Reason: the backend now runs `/v3` for every endpoint group
used here, including the register path, and a half-German client on an English
wire would translate twice and drift from its JavaScript twin
`@kreiseck/kasseneck-api` 1.0 (checked against `1.0.0-rc.3`). One breaking
release instead of several: every app migrates once. Printed receipts are byte
for byte the same as in 9.1.0 for every golden receipt.

This entry is written in English, like the README; older entries stay German.

### Migrating from 9.x

#### The 8.x and 9.x lines

8.x and 9.x keep talking to the old routes (`/v1` and `/api`) and are frozen:
fixes only, from the branches `release/8.x` and `release/9.x`. Pin `^9.1.0` or
`^8.0.0` if you are not ready to move; nothing forces an upgrade while the old
routes are served. Data stored by 9.x stays readable (see "Stored data" below).

#### Wire: `/v3` only

- **Base URLs.** `KasseneckApi` calls `https://api.kasseneck.at/v3`
  (`kPublicBaseUrl`, was `/v1`), `InvoiceApi` the same host (`kInvoiceBaseUrl`),
  and the register path (`RegisterClient`, `RegisterTransport`,
  `RegisterSessionClient`) `https://kasse.kasseneck.at/api/v3`
  (`kPosBaseUrl`/`kRegisterBaseUrl`, was `/api`). A custom `baseUrl` must end
  in `/v3` once trailing slashes are removed; `/v1`, `/api` or any other base
  throws when the client is created. Reason: a 10.x client must never speak an
  old route by accident. Emulator and test bases need `/v3` as well.
- **Marker, fail closed.** Requests to a Kasseneck base carry
  `Kasseneck-Api-Version: v3` and `Kasseneck-Client: kasseneck_api/<version>`
  (new options `clientHeader` for apps that name themselves, e.g.
  `kasse-app/1.0.3+34`, and `omitKasseneckHeaders`). Every response is
  checked before its body is read: HTTP 200 with HTML is `route_missing`, a
  response without `Kasseneck-Api-Version: v3` is `dialect_mismatch` (outcome
  unknown), HTTP 404 with marker and error envelope is the envelope's error.
  All three are `KasseneckApiError`s. Test doubles and proxies in your own
  tests must send the marker. Reason: an answer from an edge without `/v3` may
  still have signed a receipt, and reading it as a normal answer would hide
  that.
- **HTTP status first.** On the register, pairing and invoice paths a status
  other than 200 is a `KasseneckHttpError` (`server-error`) without code; 9.x
  read the error envelope there. Exception: the 404 of the `/v3` edge with
  marker (above).
- **UTF-8, strictly.** Every response is decoded as UTF-8 from its bytes,
  whatever the content type says; invalid UTF-8 is `not-json`. Report PDFs
  (`downloadDailyReport`, `downloadMonthlyReport`) come back as the raw bytes.
- **English keys, values and codes.** Error codes are English, lower case,
  `snake_case` (`bereits_storniert` is `already_cancelled`,
  `PAYMENTS_SUM_MISMATCH` is `payments_sum_mismatch`, `adresse_ungueltig` is
  `invalid_address`, `zu_oft` is `too_many_requests`). Cancellation reasons are
  `input_error`, `customer_cancelled`, `wrong_payment_method`, `duplicate`,
  `other`; the German display text stays in `cancellationReasons`. Register
  settings are `{business, device}` with English keys and values
  (`stil: 'nacht'` is `theme: 'night'`). The invoice API uses `docType`
  `invoice`/`credit_note` (was `RE`/`GU`) and `taxScheme`
  `intraCommunitySupply` (was `igLieferung`). Texts for people (`message`,
  `nextSteps`) and BMF and FinanzOnline terms stay German. Hard-coded old
  values (`'RE'`, `'igLieferung'`, `'STORNO_…'`) still compile but fail at run
  time, so search your code for them.

#### Renamed names

Every public German name is English now: 11 library paths, about 200
top-level names, 340 members, 350 parameters and 11 record fields, plus about
110 fields, values and parameters that changed with the `/v3` wire. The
complete table, old name to new name with the file it was declared in, is
**[`doc/migration-10.md`](doc/migration-10.md)** (it ships with the package).
It is a separate file and not part of this entry on purpose: at more than a
thousand rows it would bury the changes that need thought, which are listed
here, while the compiler already points at every renamed name and the table
only has to answer "what is it called now". The most visible ones:

- Libraries: `kasse.dart` is `pos.dart`, `rechnung.dart` is `invoice.dart`,
  `models/beleg_layout.dart` is `models/receipt_layout.dart`,
  `models/beleg_blatt.dart` is `models/receipt_sheet.dart`,
  `services/druck_logo.dart` is `services/print_logo.dart`,
  `widgets/keck_beleg_blatt_widget.dart` is
  `widgets/keck_receipt_sheet_widget.dart`.
- Receipts: `stornieren` is `cancelReceipt`, `belegSenden` is
  `sendReceiptEmail`, `verkaufen` is `sell`, `holen` is `get`, `auflisten` is
  `list`, `Stornoergebnis` is `CancelReceiptResult`, `StornoStand` is
  `CancellationState`, `BelegLayout` is `ReceiptLayout`, `BelegBlatt` is
  `ReceiptSheet`, `restmengen` is `remainingQuantities`.
- **Watch out:** `KasseneckApi.cancelReceipt` existed in 9.x as the old
  cancellation without reference (`cancelReceipt(receipt:)`). In 10.0 the name
  belongs to the cancellation with reference (the former `stornieren`, with
  `cashregisterId`, `originalReceiptId`, `reason`). A 9.x call
  `cancelReceipt(receipt: r)` fails to compile; rewrite it, do not just rename.
- Register: `KasseSettings` is `PosSettings`, `KasseSettingsBetrieb` is
  `PosBusinessSettings`, `KasseSettingsGeraet` is `PosDeviceSettings`,
  `KasseEinstellungenClient` is `PosSettingsClient` (`laden`/`betriebSpeichern`/
  `geraetSpeichern` are `load`/`saveBusiness`/`saveDevice`), `KasseArtikel` is
  `PosArticle`, `KasseDruckerClient` is `PosPrinterClient`, the `Kasse…`
  enums are `Pos…` enums with English values (`KasseStil.nacht` is
  `PosTheme.night`, `KasseDruckerArt.bt` is `PosPrinterType.bluetooth`).
- Invoices: `RechnungApi` is `InvoiceApi`, `RechnungTransport` is
  `InvoiceTransport`, `rechnungSummen` is `computeInvoiceTotals`,
  `rechnungFehlerCode` is `invoiceErrorCode`, `steuerfreieFaelle` is
  `zeroRatedTaxSchemes`.
- Receipt fields: `uid` is `vatId`, `taxnr` is `taxNumber`, `testKasse` is
  `testCashregister`, `testSignatur` is `testSignature`, `kopfId` is
  `headerVersionId`, `logoStufe` is `logoScale`; `KeckTip.sofortErhalten` is
  `receivedImmediately`; `VatRate.vat4komma9` is `VatRate.vat4_9`;
  `KeckUser.taxnr` is `taxNumber`, `KeckUser.benid` is `webserviceUserId` (the
  wire keys of the FinanzOnline data stay).

Three FinanzOnline status values keep their German names on purpose:
`CashboxStatus.IN_BETRIEB`, `SignatureStatus.IN_BETRIEB` and
`SignatureStatus.AUSFALL` are the values FinanzOnline sends.

#### Text keys and placeholders

The package has no text catalogue of its own, but the contract files it is
tested against (`pos-texts.json`, `invoice-texts.json` of the npm twin) are
English now, and apps that generate their texts from them must follow:

- Keys: `netz.keine_verbindung` is `network.no_connection`,
  `kopplung.code_fehlt` is `pairing.code_missing`, `allgemein.abbrechen` is
  `common.cancel`, `pdf.titel.rechnung` is `pdf.title.invoice` and so on (the
  complete list is `texts` in `renames-1.0.json`).
- Structure: `meldungen`/`beschriftungen`/`fehlerregeln` are
  `messages`/`labels`/`errorRules`, an entry's `platzhalter`/`nur` are
  `placeholders`/`only`, an error rule's `art`/`verhalten`/`schluessel` are
  `kind`/`behavior`/`key`; `belegMailFehler` and `stornoZahlungFehler` are
  `receiptEmailErrors` and `cancellationPaymentErrors`, keyed by the `/v3`
  codes.
- Placeholders, 25 of 30 renamed: `{an}` → `{recipient}`, `{antwort}` →
  `{response}`, `{beleg}` → `{receipt}`, `{betrag}` → `{amount}`, `{betrieb}`
  → `{business}`, `{datum}` → `{date}`, `{gegeben}` → `{tendered}`,
  `{gesamt}` → `{total}`, `{grund}` → `{reason}`, `{kaeufer}` → `{buyer}`,
  `{kennung}` → `{reference}`, `{meldung}` → `{message}`, `{netto}` →
  `{net}`, `{nummer}` → `{number}`, `{offen}` → `{open}`, `{ort}` →
  `{place}`, `{prozent}` → `{percent}`, `{rueckgeld}` → `{change}`, `{satz}`
  → `{rate}`, `{sekunden}` → `{seconds}`, `{uid}` → `{vatId}`,
  `{verkaeufer}` → `{seller}`, `{weg}` → `{channel}`, `{zeit}` → `{time}`,
  `{ziel}` → `{target}`.
- The texts themselves are unchanged, character for character (checked
  against the 0.31.0 files).

#### Removed

- `KasseneckApi.cancelReceipt(receipt:)` and `createCancelReceipt`: the old
  cancellation through `createReceipt` without a reference to the original.
  `/v3` rejects it. Use `cancelReceipt(cashregisterId:, originalReceiptId:,
  reason:)`.
- The single payment method: `sellReceipt(paymentMethod:,
  creditCardProvider:, cardPaymentId:, cardPaymentData:)`,
  `RegisterReceiptClient.verkaufen(zahlungsart:, kartenanbieter:,
  kartenzahlungId:, kartenzahlungsdaten:)` (now `sell`) and the same
  parameters on both cancellations. Card
  data travels on each `KeckPaymentInput` (`provider`, `providerPaymentId`,
  `providerData`).
- The German 0.x names in `KasseneckReceipt.fromJson` (use
  `migrateStoredReceiptJson`, below), the upper-case payment and cancellation
  codes of `/v1`, the German settings keys and values in `merge` and in the
  settings client.

#### Behaviour changes

- **`payments` is mandatory** on every sale: `sellReceipt(payments:)`,
  `RegisterReceiptClient.sell(payments:)`, and `createReceipt` with a standard
  or training receipt (empty only when the amount due is 0; a zero receipt
  takes none). The payments must add up to the amount due. The new
  `receiptDueCents(items, vouchers, receiptType, {tip, payments,
  tipRecipient})` computes it as the backend does, including its rounding
  (checked against the 1206 cases of `receipt-due-generated.json`);
  `receiptDueBreakdown` adds the buckets, `receiptDueBreakdownForLines` takes
  fractional quantities, `paymentsExpectedCents(error)` reads the amount of a
  `payments_sum_mismatch`. `tipRecipient` (`owner` or `staff`) is required for
  a tip without recipients, and `ReceiptDueTip.fromKeckTip(tip, isOwner:)`
  bridges a `KeckTip`. Reason: `/v3` knows no single payment method, and only
  the register knows whether the signed-in user is the owner.
- **Errors are typed, and carry an outcome.** Nothing the backend or the
  transport reports arrives as a plain `Exception`, `TimeoutException` or
  `ClientException` any more:
  - timeouts and network errors are `KasseneckHttpError` (`reason` `timeout`
    or `network`, `timeout`, `statusCode` 0); a timeout now aborts the
    request;
  - HTTP errors and empty bodies are `KasseneckHttpError` (`server-error`,
    `empty-body`);
  - the error envelope of `createReceipt` (`sellReceipt`, `zeroReceipt`),
    `getReceipt`, `getReceipts` (reported as `getReportV2`),
    `getFirstReceiptDate`, `listTipRecipients`, `createStripeLink`,
    `hobexPay`, `stripeCaptureIntent`, `getCashboxStatus` and
    `getSignatureStatus` is a `KasseneckApiError` with `code` and `details`;
  - `hobexRefund` throws on refusal instead of returning `false`, so it only
    ever returns `true`;
  - a response without `status` is `missing-status`.
  
  `KasseneckApiError` and `KasseneckHttpError` have an `outcome`
  (`ErrorOutcome.unknown` or `.rejected`), and `isOutcomeUnknown(error)`
  answers it for any error. Unknown are the codes `dialect_mismatch`,
  `receipt_outcome_unknown`, `cancellation_outcome_unknown`,
  `response_unreadable` and `response_translation_failed` (unless
  `details['handled'] == false`), and on `createReceipt`, `cancelReceipt`,
  `financeWebService`, `hobexPayApi`, `hobexRefundApi` and
  `stripeCaptureIntent` a network error, timeout or HTTP 5xx after sending and
  an unreadable success body. **Never retry those; read the result back.** Do
  not pass a `RetryClient` or any other resending `http.Client` as
  `httpClient`. Reason: a retried receipt is a second signed receipt in the
  chain, and a retried card call can charge or refund twice.
- **Money calls: an error without a code is an unknown outcome.** On
  `hobexPay`, `hobexRefund` and `stripeCaptureIntent` every error envelope is
  `ErrorOutcome.unknown` unless its code is an explicit rejection raised before
  the backend contacts hobex or Stripe: the sign-in and request checks
  (`method_not_allowed`, `validation`, `cashregister_token_missing`,
  `cashregister_token_invalid`, `cashregister_not_found`, `account_not_found`,
  `live_not_enabled`, `unauthorized`, `mfa_required`,
  `user_verification_failed`, `admin_required`, `register_user_not_allowed`,
  `register_user_no_business`, `register_user_not_found`, `user_disabled`,
  `session_expired`, `cashregister_not_assigned`,
  `session_other_cashregister`), the `/v3` edge before the handler
  (`not_found`, `internal_translation_error`), `module_inactive`,
  `not_permitted` and `route_missing`. Reason: the backend's catch-all answers
  without a code even after the provider accepted the charge or refund, and a
  new attempt would charge or refund twice. All other calls keep the rule
  "no code means rejected".
- **hobex cloud amounts in cents.** `hobexPay` and `hobexRefund` take
  `amountCents` and `tipCents` (integers) instead of the euro doubles `amount`
  and `tip`, like the npm twin; the package converts to euros once, at the
  hobex boundary. An empty `transactionId`, an amount below one cent or a
  negative tip throws `KasseneckValidationError` (`kind: 'request'`) before
  sending. Reason: money is an integer with a fixed scale everywhere else in
  the package, and code moved between the web and Flutter apps would otherwise
  charge a hundred times the amount. `HobexCloudPayments.pay` and
  `HpsPayments` keep euro amounts, as the hobex terminal APIs expect;
  `HobexCloudPayments.pay` rejects a fraction of a cent or an amount below one
  cent with an `ArgumentError` before sending.
- **`sellReceipt` and `zeroReceipt` throw `KasseneckValidationError`**
  (`kind: 'request'`) for invalid input before sending, instead of
  `ArgumentError`, the same as `RegisterReceiptClient.sell` and the npm
  package.
- **`response_unreadable` instead of format errors.** A sale, cancellation,
  `hobexPay` or `stripeCaptureIntent` that reported success but whose answer
  cannot be read (receipt, reference, remaining quantities, Hobex receipt or
  payment intent missing or broken) throws `KasseneckApiError`
  `response_unreadable` with an unknown outcome and `details['receiptId']`
  where readable. 9.x threw `KasseneckReceiptFormatError`,
  `KasseneckValidationError`, `KasseneckHttpError` (`data-not-object`) or a
  plain `Exception` there. `KasseneckReceiptFormatError` remains for reading
  calls (`getReceipt`, `RegisterReceiptClient.get`).
- **Strict validation before sending.** The 0.x payment fields are gone (see
  Removed). Register settings: an unknown key, a German key from 9.x, a value
  outside a field's list, a `vatRates` map without any rate switched on, an
  unknown shortcut action and a key bound twice throw a
  `KasseneckValidationError` (`kind: 'request'`) before sending;
  `saveDevice` takes `shortcuts` only as the whole map of all 16 known
  actions; `merge` throws an `ArgumentError` with the current name for a 9.x
  key (`qrModus`, now `qrMode`) or a 0.x value (`nacht`, now `night`). A
  cancellation checks its reason against `cancellationReasons`, requires
  `original` to be the receipt named by `originalReceiptId`, and refuses a
  card refund through a provider without its own `providerPaymentId` and
  without the original payment's id. `issueInvoice` rejects `dryRun: true`
  (use `previewInvoice`). A card payment through a provider other than
  `custom` without `providerPaymentId` is no longer rejected locally (9.x threw
  an `ArgumentError`); the server answers with a code.
- **Register settings: patches, and unknown values stay.** Values this
  version does not know (from a newer server) are kept verbatim in
  `unknownValues`, written back unchanged, and listed by
  `unknownPosSettingValues(settings)` so the screen can show them as "set on
  the server"; the typed field then holds the default. `posSettingsChanges`
  produces the patch of changed fields only, with `vatRates` and `shortcuts`
  as whole maps. Reason: the server merges deeply, and a whole block would
  overwrite values a newer server knows. (npm keeps such a value in the field
  itself; the wire effect is the same.)
- **New defaults.** `checkoutMode` is `panel` (9.x: `seite`): registers
  without a stored setting check out in the panel after the update.
  `terminalPort` is 8080 (was 20008). The 16 shortcut actions and their
  defaults follow the contract (`customAmount` Mod+D, `receipts` Mod+J,
  `fullscreen` Mod+F; new actions `settings`, `logout`, `tip`, `fullscreen`,
  `clearTendered`, `clearCart`, `splitPayment`). `InvoiceItem.unit` without a
  value is `piece` (was `Stk`).
- **Server layout first.** `receiptLayoutFromResult(receipt,
  fallbackPaperSize:)` (new) returns the server's layout (80 mm) whenever the
  response carries one and otherwise `layout == null` with the fallback width
  (default `mm58`); the local fallback then draws. Unlike npm there is no
  local line-model builder in Dart. `KeckPrinterService.getPaperFromReceipt`
  prints a server layout always (9.x fell back to the local builder when a
  card block seemed missing), and the local fallback now prints the TESTKASSE
  and TESTSIGNATUR frames and the receipt type block (STORNOBELEG,
  TRAININGSBELEG, STARTBELEG, NULLBELEG and the others). A cancellation copies
  the test marks of `original`; a `kr_test_` key or
  `RegisterReceiptClient(testEnvironment: true)` sets TESTKASSE.
  `ReceiptLayout.fromJson` without `paperSize` means `mm80`.
- **Unknown values stay visible.** `ReceiptSummary.cancellationState` is
  `none`/`partial`/`full`, or `unknown` for a value this version does not
  know, and `null` when the field is missing (never `none`). Print job status
  `unknown` counts as finished.
- **Receipt e-mail.** `sendReceiptEmail(language:)` (was `sprache`); `via`
  is `own`, `platform`, `platform_fallback` or `null`. The success reply is
  read leniently: without `to` the sent address, without `at` `null`, because
  the mail is already out and an error would invite a second one.
- **Register sign-in.** `PairedRegisterDevice.testEnvironment`,
  `RegisterUserSummary.pinPolicyOutdated`, `RegisterPinPolicy.length`/
  `charset` (`digits`/`alphanumeric`), `RegisterLoginMode.selectUser`,
  `RegisterDeviceUsers.locationLock`/`receiptHeader`/`testEnvironment` and the
  new `cashregister` (`ready`, `reason`), `RegisterSession.own`;
  `RegisterSession.deviceLabel` is nullable (9.x filled in "Kasse").
  `RegisterClientInfo.app` names the app at pairing and sign-in.
- **Printers and articles.** `PosPrinterClient.printers()` without
  `data.printers` and `createPrintJob`/`getPrintJob` without `data.jobId`
  throw a `KasseneckValidationError` (`kind: 'response'`) instead of an empty
  list or id. `PosArticle.toJson` writes the wire form (`tile`,
  `quantityRule`, `askQuantity`, `maxQuantity`, `revenueGroupId`);
  `QuantityRule` is `piece`/`decimal`.
- **Invoices.** `getInvoiceXml` returns `InvoiceXml {xml, format, filename}`
  instead of a `String` and throws if one is missing. `EInvoiceStatus.missing`
  and `details.missing` of `invoice_requirements_missing` are codes (`vat_id`,
  `street`, ...) instead of German labels; `details.expected`/`given` of
  `tax_scheme_mismatch` are English. `Invoice` reads every detail field of
  the contract (`customer`, `payments`, `einvoice`, `taxScheme`,
  `writeOffReasonCode`, `serviceStart`/`End`, ...), `InvoiceItem.kind`
  defaults to `goods`.
- **Vouchers** go out without the euro `value` (`KeckVoucher.toPayload`).

#### Stored data

- A receipt map written by 9.x (`KasseneckReceipt.toJson`) has German keys;
  `KasseneckReceipt.fromJson` reads only the `/v3` form. Convert it with
  `migrateStoredReceiptJson(map)` (input untouched, an English key wins).
- Register settings and articles cached by 9.x (`{betrieb, geraet}`) are read
  by `PosSettings.fromJson` and `PosArticle.fromJson` as they are, and written
  back in the `/v3` form. The 9.x shortcut map is untangled on the way
  (`untangleShortcuts`); the other 9.x defaults apply until the first answer
  from the server.

#### New

`receiptDueCents` and relatives, `receiptLayoutFromResult`,
`migrateStoredReceiptJson`, `isOutcomeUnknown`, `ErrorOutcome`,
`clientErrorCodes`, `kPublicBaseUrl`, `kPosBaseUrl`, per-group code catalogues
(`receiptErrorCodes`, `cancellationErrorCodes`, `paymentErrorCodes`,
`receiptEmailErrorCodes`, `registerErrorCodes`, `posErrorCodes`,
`invoiceRequestErrorCodes`, `einvoiceMissingCodes`, `writeOffReasonCodes`)
with `is…Error`/`…FieldErrors` helpers, `registerErrorDetails`,
`cardRefundReference`, `RegistrationInfo`, `CancellationOf`,
`KasseneckReceipt.zeroKind`, the print jobs of the register
(`PosPrinterClient`, `NetworkPrinter`, `PrintJob`, `rasterRowsBase64`),
`RegisterReceiptClient.fullReceiptId` and `cashregisters()`,
`PosSettingsClient.setLogo`/`removeLogo`, and `fields` constants on the
response models (the field sets the tests check against the contract).

### Also in this release

- The twins are pinned to `@kreiseck/kasseneck-api` `1.0.0-rc.3`. Its three
  rc.3 findings (start receipt fields `start_receipt_*`, lenient e-mail reply,
  missing printer list or job id as a response error, shortcuts only as the
  whole map) were already in place here.
- A test compiles every Dart example of the README and README.de.md against
  the current surface, so an example can no longer go stale silently.

## 9.1.0 and older

The entries for 9.1.0 and all earlier versions are in [doc/changelog-9-and-older.md](doc/changelog-9-and-older.md).
