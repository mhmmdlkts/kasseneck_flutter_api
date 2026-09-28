# Migrating to 10.0: renamed names

Every public name of `kasseneck_api` that changed between 9.x and 10.0, old name
on the left, new name on the right. The [CHANGELOG](../CHANGELOG.md) explains
why and what else changed (wire, behaviour, removed calls); this file is the
lookup table.

The renaming happened in two steps, and the table follows them:

1. **The `/v3` rebuild** changed fields, values and parameters whose wire name
   changed (register settings, receipt fields, register sign-in). Part A maps
   those 9.x names straight to their 10.0 name.
2. **The English naming pass** renamed every remaining German name: library
   paths, classes, enums, functions, constants, members, parameters and record
   fields. Parts B to F list it. A member whose owner was renamed but whose own
   name stayed is not listed (for example `BelegBlatt.blocks` is
   `ReceiptSheet.blocks`); owners in parts C to F appear under their old name,
   the last column names the file the declaration lived in before 10.0.

Look a 9.x name up in part A first, then in parts B to F. Wire keys are not
Dart names: a JSON key sent or read by the package is only listed where the
Dart name follows it. Parts listing values give the enum value, not its
display text.

Contents:

- [A. Changed by the /v3 rebuild](#a-changed-by-the-v3-rebuild)
- [B. Library paths](#b-library-paths)
- [C. Top-level names](#c-top-level-names)
- [D. Members](#d-members)
- [E. Parameters](#e-parameters)
- [F. Named record fields](#f-named-record-fields)
- [G. Removed without a direct successor](#g-removed-without-a-direct-successor)

## A. Changed by the /v3 rebuild

112 names. Register settings fields and enum values follow the contract file
`renames-1.0.json` of the npm twin (`test/fixtures/vertrag/`); the Dart field
is named like its wire key.

| 9.x | 10.0 |
|---|---|
| `BelegBanner(warnung)` | `LayoutBannerLine(tone): LayoutBannerTone, getter warning` |
| `BelegLayout.regelwerk` | `ReceiptLayout.ruleset` |
| `KasseBelegAusgabe.druck` | `PosReceiptOutput.print` |
| `KasseBelegAusgabe.fragen` | `PosReceiptOutput.ask` |
| `KasseBelegAusgabe.mail` | `PosReceiptOutput.email` |
| `KasseDruckerArt.bt` | `PosPrinterType.bluetooth` |
| `KasseDruckerArt.netz` | `PosPrinterType.network` |
| `KasseKachelstil.streifen` | `PosTileStyle.stripe` |
| `KasseKachelstil.voll` | `PosTileStyle.full` |
| `KasseKartenanbieter.extern` | `PosCardProvider.external` |
| `KasseKartenanbieter.keiner` | `PosCardProvider.none` |
| `KasseKassierenModus.seite` | `PosCheckoutMode.page` |
| `KasseKatpos.links` | `PosCategoryPosition.left` |
| `KasseKatpos.oben` | `PosCategoryPosition.top` |
| `KasseLadeAuto.bar` | `PosDrawerAutoOpen.cash` |
| `KasseLadeAuto.immer` | `PosDrawerAutoOpen.always` |
| `KasseLadeAuto.nie` | `PosDrawerAutoOpen.never` |
| `KasseLayout.links` | `PosLayout.left` |
| `KasseLayout.rechts` | `PosLayout.right` |
| `KasseLayout.vollbild` | `PosLayout.fullscreen` |
| `KasseMenge.aus` | `PosQuantity.off` |
| `KasseneckApi.belegSenden(sprache)` | `KasseneckApi.sendReceiptEmail(language)` |
| `KasseneckReceipt.kopfId` | `KasseneckReceipt.headerVersionId` |
| `KasseneckReceipt.logoStufe` | `KasseneckReceipt.logoScale` |
| `KasseneckReceipt.taxnr` | `KasseneckReceipt.taxNumber` |
| `KasseneckReceipt.testKasse` | `KasseneckReceipt.testCashregister` |
| `KasseneckReceipt.testSignatur` | `KasseneckReceipt.testSignature` |
| `KasseneckReceipt.uid` | `KasseneckReceipt.vatId` |
| `KasseRabatt.an` | `PosDiscount.on` |
| `KasseRabatt.aus` | `PosDiscount.off` |
| `KasseSettings.betrieb` | `PosSettings.business` |
| `KasseSettings.geraet` | `PosSettings.device` |
| `KasseSettingsBetrieb.abNachVerkauf` | `PosBusinessSettings.logoutAfterSale` |
| `KasseSettingsBetrieb.autoAbMin` | `PosBusinessSettings.autoLogoutMinutes` |
| `KasseSettingsBetrieb.belegAusgabe` | `PosBusinessSettings.receiptOutput` |
| `KasseSettingsBetrieb.farbe` | `PosBusinessSettings.color` |
| `KasseSettingsBetrieb.fertigSekunden` | `PosBusinessSettings.doneScreenSeconds` |
| `KasseSettingsBetrieb.foto` | `PosBusinessSettings.staffPhotos` |
| `KasseSettingsBetrieb.freiErlaubt` | `PosBusinessSettings.customAmountAllowed` |
| `KasseSettingsBetrieb.kachelstil` | `PosBusinessSettings.tileStyle` |
| `KasseSettingsBetrieb.kartenanbieter` | `PosBusinessSettings.cardProvider` |
| `KasseSettingsBetrieb.kassierenModus` | `PosBusinessSettings.checkoutMode` |
| `KasseSettingsBetrieb.katFarben` | `PosBusinessSettings.categoryColors` |
| `KasseSettingsBetrieb.logoAn` | `PosBusinessSettings.logoEnabled` |
| `KasseSettingsBetrieb.logoGroesse` | `PosBusinessSettings.logoSize` |
| `KasseSettingsBetrieb.menge` | `PosBusinessSettings.quantity` |
| `KasseSettingsBetrieb.notiz` | `PosBusinessSettings.note` |
| `KasseSettingsBetrieb.preisAnzeigen` | `PosBusinessSettings.showPrices` |
| `KasseSettingsBetrieb.rabatt` | `PosBusinessSettings.discount` |
| `KasseSettingsBetrieb.rueckgeld` | `PosBusinessSettings.change` |
| `KasseSettingsBetrieb.saetze` | `PosBusinessSettings.vatRates` |
| `KasseSettingsBetrieb.schnellbar` | `PosBusinessSettings.exactCash` |
| `KasseSettingsBetrieb.schnellLogin` | `PosBusinessSettings.fastLogin` |
| `KasseSettingsBetrieb.schrift` | `PosBusinessSettings.fontSize` |
| `KasseSettingsBetrieb.schriftEinst` | `PosBusinessSettings.settingsFontSize` |
| `KasseSettingsBetrieb.sperrbild` | `PosBusinessSettings.lockScreen` |
| `KasseSettingsBetrieb.stil` | `PosBusinessSettings.theme` |
| `KasseSettingsBetrieb.suche` | `PosBusinessSettings.search` |
| `KasseSettingsBetrieb.tgChips` | `PosBusinessSettings.tipChips` |
| `KasseSettingsBetrieb.tgModus` | `PosBusinessSettings.tipMode` |
| `KasseSettingsBetrieb.tgSplit` | `PosBusinessSettings.tipSplit` |
| `KasseSettingsBetrieb.tgStufen` | `PosBusinessSettings.tipSteps` |
| `KasseSettingsBetrieb.trinkgeld` | `PosBusinessSettings.tip` |
| `KasseSettingsBetrieb.uhr` | `PosBusinessSettings.clock` |
| `KasseSettingsBetrieb.ustAnzeigen` | `PosBusinessSettings.showVat` |
| `KasseSettingsBetrieb.wasserzeichen` | `PosBusinessSettings.watermark` |
| `KasseSettingsBetrieb.zahlBar` | `PosBusinessSettings.payCash` |
| `KasseSettingsBetrieb.zahlKarte` | `PosBusinessSettings.payCard` |
| `KasseSettingsGeraet.druckerAn` | `PosDeviceSettings.printerEnabled` |
| `KasseSettingsGeraet.druckerArt` | `PosDeviceSettings.printerType` |
| `KasseSettingsGeraet.druckerBt` | `PosDeviceSettings.printerBluetoothId` |
| `KasseSettingsGeraet.druckerDevid` | `PosDeviceSettings.printerDeviceId` |
| `KasseSettingsGeraet.druckerId` | `PosDeviceSettings.printerId` |
| `KasseSettingsGeraet.druckerIp` | `PosDeviceSettings.printerIp` |
| `KasseSettingsGeraet.druckerName` | `PosDeviceSettings.printerName` |
| `KasseSettingsGeraet.druckerPort` | `PosDeviceSettings.printerPort` |
| `KasseSettingsGeraet.hoehe` | `PosDeviceSettings.tileHeight` |
| `KasseSettingsGeraet.katpos` | `PosDeviceSettings.categoryPosition` |
| `KasseSettingsGeraet.ladeAn` | `PosDeviceSettings.drawerEnabled` |
| `KasseSettingsGeraet.ladeAuto` | `PosDeviceSettings.drawerAutoOpen` |
| `KasseSettingsGeraet.papier` | `PosDeviceSettings.paperSize` |
| `KasseSettingsGeraet.qrModus` | `PosDeviceSettings.qrMode` |
| `KasseSettingsGeraet.schnitt` | `PosDeviceSettings.cut` |
| `KasseSettingsGeraet.spaltenExtra` | `PosDeviceSettings.extraColumns` |
| `KasseSettingsGeraet.tasten` | `PosDeviceSettings.shortcuts` |
| `KasseSettingsGeraet.zeichensatz` | `PosDeviceSettings.codePage` |
| `KasseStil.klar` | `PosTheme.clear` |
| `KasseStil.kontrast` | `PosTheme.contrast` |
| `KasseStil.nacht` | `PosTheme.night` |
| `KasseTgModus.beides` | `PosTipMode.both` |
| `KasseTgModus.betrag` | `PosTipMode.amount` |
| `KasseTgModus.gesamt` | `PosTipMode.total` |
| `KasseWasserzeichen.anmeldung` | `PosWatermark.login` |
| `KasseWasserzeichen.aus` | `PosWatermark.off` |
| `KasseWasserzeichen.ueberall` | `PosWatermark.everywhere` |
| `KeckTip.sofortErhalten` | `KeckTip.receivedImmediately` |
| `Mengenregel.dezimal` | `QuantityRule.decimal` |
| `Mengenregel.stueck` | `QuantityRule.piece` |
| `PairedRegisterDevice.testUmgebung` | `PairedRegisterDevice.testEnvironment` |
| `RegisterDeviceUsers.betriebsdaten` | `RegisterDeviceUsers.receiptHeader` |
| `RegisterDeviceUsers.standortsperre` | `RegisterDeviceUsers.locationLock` |
| `RegisterDeviceUsers.testUmgebung` | `RegisterDeviceUsers.testEnvironment` |
| `RegisterLoginMode.auswahl` | `RegisterLoginMode.selectUser` |
| `RegisterPinPolicy.stellen` | `RegisterPinPolicy.length` |
| `RegisterPinPolicy.zeichen` | `RegisterPinPolicy.charset` |
| `RegisterReceiptClient.belegSenden(sprache)` | `RegisterReceiptClient.sendReceiptEmail(language)` |
| `RegisterSession.selbst` | `RegisterSession.own` |
| `RegisterUserSummary.altbestand` | `RegisterUserSummary.pinPolicyOutdated` |
| `StornoStand.offen` | `CancellationState.none` |
| `StornoStand.teil` | `CancellationState.partial` |
| `StornoStand.voll` | `CancellationState.full` |
| `VatRate.vat4komma9` | `VatRate.vat4_9` |

## B. Library paths

11 names. Import `package:kasseneck_api/<path without lib/>`.

| 9.x | 10.0 |
|---|---|
| `lib/enums/keck_invoice_payment_methode.dart` | `lib/enums/keck_invoice_payment_method.dart` |
| `lib/kasse.dart` | `lib/pos.dart` |
| `lib/models/beleg_layout.dart` | `lib/models/receipt_layout.dart` |
| `lib/services/druck_logo.dart` | `lib/services/print_logo.dart` |
| `lib/models/beleg_blatt.dart` | `lib/models/receipt_sheet.dart` |
| `lib/models/marke.dart` | `lib/models/brand_mark.dart` |
| `lib/widgets/keck_beleg_blatt_widget.dart` | `lib/widgets/keck_receipt_sheet_widget.dart` |
| `lib/models/beleg_raster.dart` | `lib/models/receipt_grid.dart` |
| `lib/models/marke_daten.dart` | `lib/models/brand_mark_data.dart` |
| `lib/models/stripe_url_seesion.dart` | `lib/models/stripe_url_session.dart` |
| `lib/rechnung.dart` | `lib/invoice.dart` |

## C. Top-level names

202 names. Classes, enums, typedefs, functions and constants.

| before | 10.0 | declared in (path before 10.0) |
|---|---|---|
| `kartenblockUeberschrift` | `cardBlockHeadings` | lib/enums/credit_card_provider.dart |
| `KeckInvoicePaymentMethode` | `KeckInvoicePaymentMethod` | lib/enums/keck_invoice_payment_methode.dart |
| `KasseQrModusDruck` | `PosQrModePrint` | lib/enums/qr_print_mode.dart |
| `BelegBlatt` | `ReceiptSheet` | lib/models/beleg_blatt.dart |
| `BlattBlock` | `SheetBlock` | lib/models/beleg_blatt.dart |
| `BlattLogo` | `SheetLogo` | lib/models/beleg_blatt.dart |
| `BlattLogoBlock` | `SheetLogoBlock` | lib/models/beleg_blatt.dart |
| `BlattMarke` | `SheetBrandMark` | lib/models/beleg_blatt.dart |
| `BlattQr` | `SheetQr` | lib/models/beleg_blatt.dart |
| `BlattZeile` | `SheetLine` | lib/models/beleg_blatt.dart |
| `LogoMass` | `LogoDimensions` | lib/models/beleg_blatt.dart |
| `LogoStufe` | `SheetLogoSize` | lib/models/beleg_blatt.dart |
| `belegBlatt` | `receiptSheet` | lib/models/beleg_blatt.dart |
| `logoMass` | `logoDimensions` | lib/models/beleg_blatt.dart |
| `logoRasterMass` | `logoRasterSize` | lib/models/beleg_blatt.dart |
| `papierFuerZeichen` | `paperSizeForChars` | lib/models/beleg_blatt.dart |
| `punkteJeZeichen` | `dotsPerChar` | lib/models/beleg_blatt.dart |
| `punkteJeZeile` | `dotsPerLine` | lib/models/beleg_blatt.dart |
| `qrBlattAnteil` | `qrSheetWidthFraction` | lib/models/beleg_blatt.dart |
| `qrModulAnzahlWieNpm` | `qrModuleCount` | lib/models/beleg_blatt.dart |
| `qrPasstInVersionWieNpm` | `qrFitsInVersion` | lib/models/beleg_blatt.dart |
| `BelegAlign` | `LayoutAlign` | lib/models/beleg_layout.dart |
| `BelegBanner` | `LayoutBannerLine` | lib/models/beleg_layout.dart |
| `BelegLayout` | `ReceiptLayout` | lib/models/beleg_layout.dart |
| `BelegLeerraum` | `LayoutSpaceLine` | lib/models/beleg_layout.dart |
| `BelegLinie` | `LayoutRuleLine` | lib/models/beleg_layout.dart |
| `BelegQr` | `LayoutQrLine` | lib/models/beleg_layout.dart |
| `BelegSpalte` | `LayoutColumn` | lib/models/beleg_layout.dart |
| `BelegSpalten` | `LayoutColumnsLine` | lib/models/beleg_layout.dart |
| `BelegText` | `LayoutTextLine` | lib/models/beleg_layout.dart |
| `BelegZeile` | `LayoutLine` | lib/models/beleg_layout.dart |
| `BelegRaster` | `ReceiptGrid` | lib/models/beleg_raster.dart |
| `RasterArt` | `GridLineKind` | lib/models/beleg_raster.dart |
| `RasterZeile` | `GridLine` | lib/models/beleg_raster.dart |
| `rasterSpaltenBreiten` | `gridColumnWidths` | lib/models/beleg_raster.dart |
| `wortzeilen` | `wrapWords` | lib/models/beleg_raster.dart |
| `zeichen58mm` | `charsPer58mm` | lib/models/beleg_raster.dart |
| `zeichen80mm` | `charsPer80mm` | lib/models/beleg_raster.dart |
| `mixedNichtSenden` | `mixedNotSentReason` | lib/models/keck_payment.dart |
| `zahlungenFehler` | `paymentsError` | lib/models/keck_payment.dart |
| `zahlungenHoechstzahl` | `maxPayments` | lib/models/keck_payment.dart |
| `zahlungsKonflikt` | `paymentsConflict` | lib/models/keck_payment.dart |
| `logoPixelZulaessig` | `isLogoPixelSizeAllowed` | lib/models/logo_raster.dart |
| `entpackeRasterBits` | `unpackRasterBits` | lib/models/marke.dart |
| `markeBild` | `brandMarkImage` | lib/models/marke.dart |
| `MarkeRasterDaten` | `BrandMarkRaster` | lib/models/marke_daten.dart |
| `markeRaster` | `brandMarkRasters` | lib/models/marke_daten.dart |
| `DruckLogo` | `PrintLogo` | lib/models/print_paper.dart |
| `PixelLader` | `PixelLoader` | lib/services/druck_logo.dart |
| `druckLogoSpeicherLeeren` | `clearPrintLogoCache` | lib/services/druck_logo.dart |
| `ladeDruckLogo` | `loadPrintLogo` | lib/services/druck_logo.dart |
| `standardNegativFrist` | `defaultNegativeCacheTtl` | lib/services/druck_logo.dart |
| `Artikelgruppe` | `ArticleGroup` | lib/src/kasse/artikel.dart |
| `KasseArtikel` | `PosArticle` | lib/src/kasse/artikel.dart |
| `Mengenregel` | `QuantityRule` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe` | `QuantityDefaults` | lib/src/kasse/artikel.dart |
| `mengeErlaubt` | `allowedQuantity` | lib/src/kasse/artikel.dart |
| `mengenVorgabe` | `quantityDefaults` | lib/src/kasse/artikel.dart |
| `mengenregelFuerEinheit` | `quantityRuleForUnit` | lib/src/kasse/artikel.dart |
| `Belegbediener` | `ReceiptOperator` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung` | `ReceiptSummary` | lib/src/kasse/belege.dart |
| `KassenEintrag` | `CashregisterEntry` | lib/src/kasse/belege.dart |
| `KassenInbetriebnahme` | `CashregisterOnboarding` | lib/src/kasse/belege.dart |
| `StornoStand` | `CancellationState` | lib/src/kasse/belege.dart |
| `Stornoergebnis` | `CancelReceiptResult` | lib/src/kasse/belege.dart |
| `Stornoposition` | `CancellationItem` | lib/src/kasse/belege.dart |
| `BelegartFilter` | `ReceiptTypeFilter` | lib/src/kasse/belegliste.dart |
| `Belegfilter` | `ReceiptFilter` | lib/src/kasse/belegliste.dart |
| `Tagesgruppe` | `ReceiptDayGroup` | lib/src/kasse/belegliste.dart |
| `ZahlungFilter` | `PaymentFilter` | lib/src/kasse/belegliste.dart |
| `Zeitraum` | `ReceiptPeriod` | lib/src/kasse/belegliste.dart |
| `bediener` | `operatorNames` | lib/src/kasse/belegliste.dart |
| `belegartText` | `receiptTypeLabel` | lib/src/kasse/belegliste.dart |
| `gefiltert` | `filterReceipts` | lib/src/kasse/belegliste.dart |
| `tagesgruppen` | `groupByDay` | lib/src/kasse/belegliste.dart |
| `uhrzeit` | `receiptTime` | lib/src/kasse/belegliste.dart |
| `wienDatum` | `viennaDate` | lib/src/kasse/belegliste.dart |
| `zeitfenster` | `periodRange` | lib/src/kasse/belegliste.dart |
| `Belegmailergebnis` | `SendReceiptEmailResult` | lib/src/kasse/belegmail.dart |
| `belegMailFehlercodes` | `receiptEmailErrorCodes` | lib/src/kasse/belegmail.dart |
| `istBelegMailFehlercode` | `isReceiptEmailErrorCode` | lib/src/kasse/belegmail.dart |
| `KasseDruckerClient` | `PosPrinterClient` | lib/src/kasse/drucker.dart |
| `rasterZeilenBase64` | `rasterRowsBase64` | lib/src/kasse/drucker.dart |
| `KasseBelegAusgabe` | `PosReceiptOutput` | lib/src/kasse/einstellungen.dart |
| `KasseDruckerArt` | `PosPrinterType` | lib/src/kasse/einstellungen.dart |
| `KasseEinstellSchrift` | `PosSettingsFontSize` | lib/src/kasse/einstellungen.dart |
| `KasseGroesse` | `PosLogoSize` | lib/src/kasse/einstellungen.dart |
| `KasseHoehe` | `PosTileHeight` | lib/src/kasse/einstellungen.dart |
| `KasseKachelstil` | `PosTileStyle` | lib/src/kasse/einstellungen.dart |
| `KasseKartenanbieter` | `PosCardProvider` | lib/src/kasse/einstellungen.dart |
| `KasseKassierenModus` | `PosCheckoutMode` | lib/src/kasse/einstellungen.dart |
| `KasseKatpos` | `PosCategoryPosition` | lib/src/kasse/einstellungen.dart |
| `KasseLadeAuto` | `PosDrawerAutoOpen` | lib/src/kasse/einstellungen.dart |
| `KasseLayout` | `PosLayout` | lib/src/kasse/einstellungen.dart |
| `KasseMenge` | `PosQuantity` | lib/src/kasse/einstellungen.dart |
| `KassePapier` | `PosPaperSize` | lib/src/kasse/einstellungen.dart |
| `KasseQrModus` | `PosQrMode` | lib/src/kasse/einstellungen.dart |
| `KasseRabatt` | `PosDiscount` | lib/src/kasse/einstellungen.dart |
| `KasseSchnitt` | `PosCut` | lib/src/kasse/einstellungen.dart |
| `KasseSchrift` | `PosFontSize` | lib/src/kasse/einstellungen.dart |
| `KasseSettings` | `PosSettings` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb` | `PosBusinessSettings` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet` | `PosDeviceSettings` | lib/src/kasse/einstellungen.dart |
| `KasseSkala` | `PosLogoScale` (logoScale) und `PosWatermarkScale` (watermarkScale), getrennt wie npm | lib/src/kasse/einstellungen.dart |
| `KasseStil` | `PosTheme` | lib/src/kasse/einstellungen.dart |
| `KasseTerminalArt` | `PosTerminalType` | lib/src/kasse/einstellungen.dart |
| `KasseTerminalVia` | `PosTerminalVia` | lib/src/kasse/einstellungen.dart |
| `KasseTgModus` | `PosTipMode` | lib/src/kasse/einstellungen.dart |
| `KasseWasserzeichen` | `PosWatermark` | lib/src/kasse/einstellungen.dart |
| `KasseWasserzeichenSeite` | `PosWatermarkSide` | lib/src/kasse/einstellungen.dart |
| `KasseWert` | `PosSettingValue` | lib/src/kasse/einstellungen.dart |
| `KasseZeichensatz` | `PosCodePage` | lib/src/kasse/einstellungen.dart |
| `altformBetriebSchluessel` | `legacyBusinessKeys` | lib/src/kasse/einstellungen.dart |
| `altformGeraetSchluessel` | `legacyDeviceKeys` | lib/src/kasse/einstellungen.dart |
| `altformTastenAktionen` | `legacyShortcutActions` | lib/src/kasse/einstellungen.dart |
| `altformWerte` | `legacyValues` | lib/src/kasse/einstellungen.dart |
| `entwirreTasten` | `untangleShortcuts` | lib/src/kasse/einstellungen.dart |
| `istAltwert0x` | `isLegacyValue0x` | lib/src/kasse/einstellungen.dart |
| `kasseAutoAbmeldenMinuten` | `posAutoLogoutMinutes` | lib/src/kasse/einstellungen.dart |
| `kasseFertigSekunden` | `posDoneScreenSeconds` | lib/src/kasse/einstellungen.dart |
| `kasseSaetzeReihenfolge` | `posVatRateOrder` | lib/src/kasse/einstellungen.dart |
| `kasseTastenAktionen` | `posShortcutActions` | lib/src/kasse/einstellungen.dart |
| `kasseTastenStandard` | `posShortcutDefaults` | lib/src/kasse/einstellungen.dart |
| `kasseWasserzeichenStaerken` | `posWatermarkStrengths` | lib/src/kasse/einstellungen.dart |
| `KasseEinstellungenClient` | `PosSettingsClient` | lib/src/kasse/einstellungen_client.dart |
| `Farbe` | `PosColor` | lib/src/kasse/farbe.dart |
| `farbeAusHsv` | `colorFromHsv` | lib/src/kasse/farbe.dart |
| `kontrast` | `contrastRatio` | lib/src/kasse/farbe.dart |
| `lesbarAuf` | `readableOn` | lib/src/kasse/farbe.dart |
| `markeTaugt` | `isUsableBrandColor` | lib/src/kasse/farbe.dart |
| `Kachelbuchung` | `TileBooking` | lib/src/kasse/kacheln.dart |
| `Kategorie` | `TileCategory` | lib/src/kasse/kacheln.dart |
| `alsEntwurf` | `draftFromArticle` | lib/src/kasse/kacheln.dart |
| `gebucht` | `bookTile` | lib/src/kasse/kacheln.dart |
| `kategorien` | `tileCategories` | lib/src/kasse/kacheln.dart |
| `ohneGruppeFarbe` | `ungroupedColor` | lib/src/kasse/kacheln.dart |
| `ohneGruppeId` | `ungroupedId` | lib/src/kasse/kacheln.dart |
| `steuersatzZu` | `vatRateFor` | lib/src/kasse/kacheln.dart |
| `suche` | `searchTiles` | lib/src/kasse/kacheln.dart |
| `textAuf` | `textColorOn` | lib/src/kasse/kacheln.dart |
| `AbschlussPruefung` | `CompletionCheck` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung` | `CheckoutTotals` | lib/src/kasse/kassieren.dart |
| `Kassierstand` | `CheckoutState` | lib/src/kasse/kassieren.dart |
| `RabattArt` | `DiscountKind` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung` | `completionCheck` | lib/src/kasse/kassieren.dart |
| `barzahlung` | `cashPayment` | lib/src/kasse/kassieren.dart |
| `belegPositionen` | `receiptItems` | lib/src/kasse/kassieren.dart |
| `kassierrechnung` | `checkoutTotals` | lib/src/kasse/kassieren.dart |
| `rabattCents` | `discountCentsFor` | lib/src/kasse/kassieren.dart |
| `rueckgeld` | `computeChange` | lib/src/kasse/kassieren.dart |
| `schnellbetraege` | `quickAmounts` | lib/src/kasse/kassieren.dart |
| `ustSumme` | `vatTotalCents` | lib/src/kasse/kassieren.dart |
| `ustSummePositionen` | `vatTotalCentsOfItems` | lib/src/kasse/kassieren.dart |
| `verteileRabatt` | `distributeDiscount` | lib/src/kasse/kassieren.dart |
| `zahlungsarten` | `offeredPaymentMethods` | lib/src/kasse/kassieren.dart |
| `zuZahlen` | `amountDue` | lib/src/kasse/kassieren.dart |
| `belegSichtbar` | `isReceiptVisible` | lib/src/kasse/storno.dart |
| `idHoechststellen` | `receiptNumberMaxDigits` | lib/src/kasse/storno.dart |
| `idNummer` | `receiptNumber` | lib/src/kasse/storno.dart |
| `istStornoFehlercode` | `isCancellationErrorCode` | lib/src/kasse/storno.dart |
| `pruefeKartenRueckbuchung` | `assertCardRefunds` | lib/src/kasse/storno.dart |
| `restmengen` | `remainingQuantities` | lib/src/kasse/storno.dart |
| `stornoErlaubt` | `canCancel` | lib/src/kasse/storno.dart |
| `stornoFehlercodes` | `cancellationErrorCodes` | lib/src/kasse/storno.dart |
| `stornoReservierungMs` | `cancellationReservationMs` | lib/src/kasse/storno.dart |
| `stornogruende` | `cancellationReasons` | lib/src/kasse/storno.dart |
| `volleId` | `fullReceiptIdFromNumber` | lib/src/kasse/storno.dart |
| `belegIstTest` | `receiptIsTest` | lib/src/kasse/testkennzeichen.dart |
| `signaturIstTest` | `signatureIsTest` | lib/src/kasse/testkennzeichen.dart |
| `Kassenthema` | `PosThemeData` | lib/src/kasse/thema.dart |
| `kachelhoehen` | `tileHeights` | lib/src/kasse/thema.dart |
| `modusFuer` | `modeFor` | lib/src/kasse/thema.dart |
| `schriftfaktoren` | `fontScales` | lib/src/kasse/thema.dart |
| `Korbzeile` | `CartLine` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf` | `CartItemDraft` | lib/src/kasse/warenkorb.dart |
| `Warenkorb` | `Cart` | lib/src/kasse/warenkorb.dart |
| `alsEuro` | `formatEuro` | lib/src/kasse/warenkorb.dart |
| `betragAusText` | `parseAmountCents` | lib/src/kasse/warenkorb.dart |
| `hoechstbetragCent` | `maxAmountCents` | lib/src/kasse/warenkorb.dart |
| `steuersaetze` | `vatRateChoices` | lib/src/kasse/warenkorb.dart |
| `steuersatzText` | `formatVatRate` | lib/src/kasse/warenkorb.dart |
| `vorgabeSteuersatz` | `defaultVatRate` | lib/src/kasse/warenkorb.dart |
| `istZahlungFehlercode` | `isPaymentErrorCode` | lib/src/kasse/zahlungen.dart |
| `zahlungFehlercodes` | `paymentErrorCodes` | lib/src/kasse/zahlungen.dart |
| `QrGroesse` | `QrSizing` | lib/src/printing/qr_groesse.dart |
| `QrMass` | `QrMetrics` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse` | `QrModuleSize` | lib/src/printing/qr_groesse.dart |
| `RechnungApi` | `InvoiceApi` | lib/src/rechnung/api.dart |
| `rechnungFehlerCode` | `invoiceErrorCode` | lib/src/rechnung/api.dart |
| `rechnungFeldFehler` | `invoiceFieldErrors` | lib/src/rechnung/api.dart |
| `SummenPosition` | `TotalsItem` | lib/src/rechnung/modelle.dart |
| `rechnungSummen` | `computeInvoiceTotals` | lib/src/rechnung/summen.dart |
| `RechnungTransport` | `InvoiceTransport` | lib/src/rechnung/transport.dart |
| `kRechnungBaseUrl` | `kInvoiceBaseUrl` | lib/src/rechnung/transport.dart |
| `istRechnungFehlercode` | `isInvoiceErrorCode` | lib/src/rechnung/vertrag.dart |
| `rechnungAufrufe` | `invoiceCalls` | lib/src/rechnung/vertrag.dart |
| `steuerfreieFaelle` | `zeroRatedTaxSchemes` | lib/src/rechnung/vertrag.dart |
| `fehlercodeAus` | `errorCodeFrom` | lib/src/register/fehler.dart |
| `RegisterSessionsStand` | `RegisterSessionOverview` | lib/src/register/pairing.dart |
| `nettoCentsAusBrutto` | `netCentsFromGross` | lib/src/vat_math.dart |
| `ustCentsAusBrutto` | `vatCentsFromGross` | lib/src/vat_math.dart |
| `KeckBelegBlattWidget` | `KeckReceiptSheetWidget` | lib/widgets/keck_beleg_blatt_widget.dart |

## D. Members

343 names. Enum values, fields, getters, methods and named constructors.

| before | 10.0 | declared in (path before 10.0) |
|---|---|---|
| `KeckPaperSize.druckPunkte` | `KeckPaperSize.printWidthDots` | lib/enums/keck_paper_size.dart |
| `KasseQrModusDruck.druckmodusOder` | `PosQrModePrint.printModeOr` | lib/enums/qr_print_mode.dart |
| `KasseneckApi.belegSenden` | `KasseneckApi.sendReceiptEmail` | lib/kasseneck_api.dart |
| `KasseneckApi.stornieren` | `KasseneckApi.cancelReceipt` | lib/kasseneck_api.dart |
| `BelegBlatt.bloecke` | `ReceiptSheet.blocks` | lib/models/beleg_blatt.dart |
| `BelegBlatt.zeichen` | `ReceiptSheet.charsPerLine` | lib/models/beleg_blatt.dart |
| `BlattLogo.pxBreite` | `SheetLogo.pixelWidth` | lib/models/beleg_blatt.dart |
| `BlattLogo.pxHoehe` | `SheetLogo.pixelHeight` | lib/models/beleg_blatt.dart |
| `BlattLogo.stufe` | `SheetLogo.size` | lib/models/beleg_blatt.dart |
| `BlattLogoBlock.breiteAnteil` | `SheetLogoBlock.widthFraction` | lib/models/beleg_blatt.dart |
| `BlattLogoBlock.hoeheZeilen` | `SheetLogoBlock.heightLines` | lib/models/beleg_blatt.dart |
| `BlattMarke.breite` | `SheetBrandMark.width` | lib/models/beleg_blatt.dart |
| `BlattMarke.hoehe` | `SheetBrandMark.height` | lib/models/beleg_blatt.dart |
| `BlattQr.breiteAnteil` | `SheetQr.widthFraction` | lib/models/beleg_blatt.dart |
| `BlattQr.nutzlast` | `SheetQr.payload` | lib/models/beleg_blatt.dart |
| `BlattZeile.fett` | `SheetLine.bold` | lib/models/beleg_blatt.dart |
| `BlattZeile.leer` | `SheetLine.blank` | lib/models/beleg_blatt.dart |
| `LogoMass.breiteAnteil` | `LogoDimensions.widthFraction` | lib/models/beleg_blatt.dart |
| `LogoMass.hoeheZeilen` | `LogoDimensions.heightLines` | lib/models/beleg_blatt.dart |
| `LogoStufe.ausKuerzel` | `SheetLogoSize.fromCode` | lib/models/beleg_blatt.dart |
| `LogoStufe.breiteAnteil` | `SheetLogoSize.widthFraction` | lib/models/beleg_blatt.dart |
| `LogoStufe.hoeheZeilen` | `SheetLogoSize.heightLines` | lib/models/beleg_blatt.dart |
| `LogoStufe.kuerzel` | `SheetLogoSize.code` | lib/models/beleg_blatt.dart |
| `BelegLayout.bannerTexte` | `ReceiptLayout.bannerTexts` | lib/models/beleg_layout.dart |
| `BelegLayout.qrDaten` | `ReceiptLayout.qrPayload` | lib/models/beleg_layout.dart |
| `LayoutBannerTone.aus` | `LayoutBannerTone.fromWire` | lib/models/beleg_layout.dart |
| `BelegRaster.alsText` | `ReceiptGrid.toText` | lib/models/beleg_raster.dart |
| `BelegRaster.zeichen` | `ReceiptGrid.charsPerLine` | lib/models/beleg_raster.dart |
| `RasterZeile.art` | `GridLine.kind` | lib/models/beleg_raster.dart |
| `RasterZeile.warnung` | `GridLine.warning` | lib/models/beleg_raster.dart |
| `KasseneckReceipt.fehlendePflichtangaben` | `KasseneckReceipt.missingMandatoryFields` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.kartenzahlungen` | `KasseneckReceipt.cardPayments` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.layoutIstVollstaendig` | `KasseneckReceipt.isLayoutComplete` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.pflichtangabenVollstaendig` | `KasseneckReceipt.hasMandatoryFields` | lib/models/kasseneck_receipt.dart |
| `KeckPayment.listeAus` | `KeckPayment.listFromJson` | lib/models/keck_payment.dart |
| `KeckPrintResult.qrAusweich` | `KeckPrintResult.qrFallback` | lib/models/keck_print_result.dart |
| `KeckPrintResult.qrFehler` | `KeckPrintResult.qrError` | lib/models/keck_print_result.dart |
| `KeckTip.fehler` | `KeckTip.validationError` | lib/models/keck_tip.dart |
| `KeckTip.fuer` | `KeckTip.forRecipient` | lib/models/keck_tip.dart |
| `KeckTipPerson.aus` | `KeckTipPerson.fromJson` | lib/models/keck_tip_person.dart |
| `KeckTipPerson.felder` | `KeckTipPerson.fields` | lib/models/keck_tip_person.dart |
| `KeckTipPerson.mit` | `KeckTipPerson.share` | lib/models/keck_tip_person.dart |
| `KeckUser.benid` | `KeckUser.webserviceUserId` | lib/models/keck_user.dart |
| `KeckUser.taxnr` | `KeckUser.taxNumber` | lib/models/keck_user.dart |
| `LogoRaster.alsRasterImage` | `LogoRaster.toRasterImage` | lib/models/logo_raster.dart |
| `LogoRaster.breite` | `LogoRaster.width` | lib/models/logo_raster.dart |
| `LogoRaster.hoehe` | `LogoRaster.height` | lib/models/logo_raster.dart |
| `LogoRaster.punkte` | `LogoRaster.dots` | lib/models/logo_raster.dart |
| `MarkeRasterDaten.breite` | `BrandMarkRaster.width` | lib/models/marke_daten.dart |
| `MarkeRasterDaten.hoehe` | `BrandMarkRaster.height` | lib/models/marke_daten.dart |
| `DruckLogo.pxBreite` | `PrintLogo.pixelWidth` | lib/models/print_paper.dart |
| `DruckLogo.pxHoehe` | `PrintLogo.pixelHeight` | lib/models/print_paper.dart |
| `DruckLogo.stufe` | `PrintLogo.size` | lib/models/print_paper.dart |
| `PrintPaper.qrAusweich` | `PrintPaper.qrFallback` | lib/models/print_paper.dart |
| `PrintPaper.qrFehler` | `PrintPaper.qrError` | lib/models/print_paper.dart |
| `PrintPaper.setBelegBlatt` | `PrintPaper.setReceiptSheet` | lib/models/print_paper.dart |
| `PrintPaper.setBelegLayout` | `PrintPaper.setReceiptLayout` | lib/models/print_paper.dart |
| `LogoService.auffrischenNach` | `LogoService.refreshAfter` | lib/services/logo_service.dart |
| `LogoService.dauerhaftAblegen` | `LogoService.enablePersistentStorage` | lib/services/logo_service.dart |
| `LogoService.frist` | `LogoService.timeout` | lib/services/logo_service.dart |
| `LogoService.istBilddatei` | `LogoService.isImageFile` | lib/services/logo_service.dart |
| `LogoService.maxDateiBytes` | `LogoService.maxFileBytes` | lib/services/logo_service.dart |
| `LogoService.maxDateien` | `LogoService.maxFiles` | lib/services/logo_service.dart |
| `LogoService.speicherLeeren` | `LogoService.clearCache` | lib/services/logo_service.dart |
| `LogoService.speicherOrdner` | `LogoService.storageDirectory` | lib/services/logo_service.dart |
| `LogoService.standardFrist` | `LogoService.defaultTimeout` | lib/services/logo_service.dart |
| `KeckPrinterService.letzterQrAusweich` | `KeckPrinterService.lastQrFallback` | lib/services/printer_service.dart |
| `KeckPrinterService.letzterQrFehler` | `KeckPrinterService.lastQrError` | lib/services/printer_service.dart |
| `KeckPrinterService.logoLader` | `KeckPrinterService.logoLoader` | lib/services/printer_service.dart |
| `Artikelgruppe.aus` | `ArticleGroup.fromJson` | lib/src/kasse/artikel.dart |
| `Artikelgruppe.farbe` | `ArticleGroup.color` | lib/src/kasse/artikel.dart |
| `Artikelgruppe.felder` | `ArticleGroup.fields` | lib/src/kasse/artikel.dart |
| `Artikelgruppe.steuersatz` | `ArticleGroup.vatRate` | lib/src/kasse/artikel.dart |
| `KasseArtikel.aktiv` | `PosArticle.active` | lib/src/kasse/artikel.dart |
| `KasseArtikel.aus` | `PosArticle.fromJson` | lib/src/kasse/artikel.dart |
| `KasseArtikel.einheit` | `PosArticle.unit` | lib/src/kasse/artikel.dart |
| `KasseArtikel.erloesgruppeId` | `PosArticle.revenueGroupId` | lib/src/kasse/artikel.dart |
| `KasseArtikel.felder` | `PosArticle.fields` | lib/src/kasse/artikel.dart |
| `KasseArtikel.gruppeId` | `PosArticle.groupId` | lib/src/kasse/artikel.dart |
| `KasseArtikel.kachelFelder` | `PosArticle.tileFields` | lib/src/kasse/artikel.dart |
| `KasseArtikel.maxMenge` | `PosArticle.maxQuantity` | lib/src/kasse/artikel.dart |
| `KasseArtikel.mengeFragen` | `PosArticle.askQuantity` | lib/src/kasse/artikel.dart |
| `KasseArtikel.mengenregel` | `PosArticle.quantityRule` | lib/src/kasse/artikel.dart |
| `KasseArtikel.preisCents` | `PosArticle.unitPriceCents` | lib/src/kasse/artikel.dart |
| `KasseArtikel.sichtbar` | `PosArticle.visible` | lib/src/kasse/artikel.dart |
| `KasseArtikel.steuersatz` | `PosArticle.vatRate` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe.fragen` | `QuantityDefaults.ask` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe.regel` | `QuantityDefaults.rule` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe.stellen` | `QuantityDefaults.decimals` | lib/src/kasse/artikel.dart |
| `Belegzusammenfassung.aus` | `ReceiptSummary.fromJson` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.bediener` | `ReceiptSummary.operator` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.belegart` | `ReceiptSummary.receiptType` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.istStorno` | `ReceiptSummary.isCancellation` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.istVerkauf` | `ReceiptSummary.isSale` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.nullbelegAnlass` | `ReceiptSummary.zeroKind` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.positionen` | `ReceiptSummary.items` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.signaturOk` | `ReceiptSummary.signatureOk` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.storniertBeleg` | `ReceiptSummary.cancellationOfReceiptId` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.stornoStand` | `ReceiptSummary.cancellationState` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.stornogrund` | `ReceiptSummary.cancellationReason` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.summeCents` | `ReceiptSummary.totalCents` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.zaehler` | `ReceiptSummary.counter` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.zahlungen` | `ReceiptSummary.payments` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.zahlungsart` | `ReceiptSummary.paymentMethod` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung.zeitstempel` | `ReceiptSummary.timeStamp` | lib/src/kasse/belege.dart |
| `KassenEintrag.aus` | `CashregisterEntry.fromJson` | lib/src/kasse/belege.dart |
| `KassenEintrag.felder` | `CashregisterEntry.fields` | lib/src/kasse/belege.dart |
| `KassenInbetriebnahme.felder` | `CashregisterOnboarding.fields` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.abschlussFrist` | `RegisterReceiptClient.signingTimeout` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.artikel` | `RegisterReceiptClient.articles` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.artikelgruppen` | `RegisterReceiptClient.articleGroups` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.auflisten` | `RegisterReceiptClient.list` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.belegSenden` | `RegisterReceiptClient.sendReceiptEmail` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.holen` | `RegisterReceiptClient.get` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.kassen` | `RegisterReceiptClient.cashregisters` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.stornieren` | `RegisterReceiptClient.cancelReceipt` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.tipEmpfaenger` | `RegisterReceiptClient.tipRecipients` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen` | `RegisterReceiptClient.sell` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.volleBelegId` | `RegisterReceiptClient.fullReceiptId` | lib/src/kasse/belege.dart |
| `Stornoergebnis.ausAntwort` | `CancelReceiptResult.fromResponse` | lib/src/kasse/belege.dart |
| `Stornoergebnis.beleg` | `CancelReceiptResult.receipt` | lib/src/kasse/belege.dart |
| `Stornoergebnis.restmengen` | `CancelReceiptResult.remaining` | lib/src/kasse/belege.dart |
| `BelegartFilter.alle` | `ReceiptTypeFilter.all` | lib/src/kasse/belegliste.dart |
| `BelegartFilter.sonstige` | `ReceiptTypeFilter.other` | lib/src/kasse/belegliste.dart |
| `BelegartFilter.storno` | `ReceiptTypeFilter.cancellation` | lib/src/kasse/belegliste.dart |
| `BelegartFilter.verkauf` | `ReceiptTypeFilter.sale` | lib/src/kasse/belegliste.dart |
| `Belegfilter.belegart` | `ReceiptFilter.receiptType` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie` | `ReceiptFilter.copyWith` | lib/src/kasse/belegliste.dart |
| `Belegfilter.wer` | `ReceiptFilter.operator` | lib/src/kasse/belegliste.dart |
| `Belegfilter.zahlung` | `ReceiptFilter.payment` | lib/src/kasse/belegliste.dart |
| `Belegfilter.zeitraum` | `ReceiptFilter.period` | lib/src/kasse/belegliste.dart |
| `Tagesgruppe.belege` | `ReceiptDayGroup.receipts` | lib/src/kasse/belegliste.dart |
| `Tagesgruppe.datum` | `ReceiptDayGroup.date` | lib/src/kasse/belegliste.dart |
| `ZahlungFilter.alle` | `PaymentFilter.all` | lib/src/kasse/belegliste.dart |
| `ZahlungFilter.bar` | `PaymentFilter.cash` | lib/src/kasse/belegliste.dart |
| `ZahlungFilter.karte` | `PaymentFilter.card` | lib/src/kasse/belegliste.dart |
| `Zeitraum.dreissigTage` | `ReceiptPeriod.last30Days` | lib/src/kasse/belegliste.dart |
| `Zeitraum.gestern` | `ReceiptPeriod.yesterday` | lib/src/kasse/belegliste.dart |
| `Zeitraum.heute` | `ReceiptPeriod.today` | lib/src/kasse/belegliste.dart |
| `Zeitraum.siebenTage` | `ReceiptPeriod.last7Days` | lib/src/kasse/belegliste.dart |
| `Belegmailergebnis.aus` | `SendReceiptEmailResult.fromResponse` | lib/src/kasse/belegmail.dart |
| `KasseDruckerClient.drucker` | `PosPrinterClient.printers` | lib/src/kasse/drucker.dart |
| `KasseDruckerClient.druckjobAnlegen` | `PosPrinterClient.createPrintJob` | lib/src/kasse/drucker.dart |
| `KasseDruckerClient.druckjobHolen` | `PosPrinterClient.getPrintJob` | lib/src/kasse/drucker.dart |
| `NetworkPrinter.aus` | `NetworkPrinter.fromJson` | lib/src/kasse/drucker.dart |
| `NetworkPrinter.felder` | `NetworkPrinter.fields` | lib/src/kasse/drucker.dart |
| `PrintJob.felder` | `PrintJob.fields` | lib/src/kasse/drucker.dart |
| `PrintResult.felder` | `PrintResult.fields` | lib/src/kasse/drucker.dart |
| `KasseBelegAusgabe.wert` | `PosReceiptOutput.value` | lib/src/kasse/einstellungen.dart |
| `KasseDruckerArt.wert` | `PosPrinterType.value` | lib/src/kasse/einstellungen.dart |
| `KasseEinstellSchrift.wert` | `PosSettingsFontSize.value` | lib/src/kasse/einstellungen.dart |
| `KasseGroesse.wert` | `PosLogoSize.value` | lib/src/kasse/einstellungen.dart |
| `KasseHoehe.wert` | `PosTileHeight.value` | lib/src/kasse/einstellungen.dart |
| `KasseKachelstil.wert` | `PosTileStyle.value` | lib/src/kasse/einstellungen.dart |
| `KasseKartenanbieter.wert` | `PosCardProvider.value` | lib/src/kasse/einstellungen.dart |
| `KasseKassierenModus.wert` | `PosCheckoutMode.value` | lib/src/kasse/einstellungen.dart |
| `KasseKatpos.wert` | `PosCategoryPosition.value` | lib/src/kasse/einstellungen.dart |
| `KasseLadeAuto.wert` | `PosDrawerAutoOpen.value` | lib/src/kasse/einstellungen.dart |
| `KasseLayout.wert` | `PosLayout.value` | lib/src/kasse/einstellungen.dart |
| `KasseMenge.wert` | `PosQuantity.value` | lib/src/kasse/einstellungen.dart |
| `KassePapier.wert` | `PosPaperSize.value` | lib/src/kasse/einstellungen.dart |
| `KasseQrModus.wert` | `PosQrMode.value` | lib/src/kasse/einstellungen.dart |
| `KasseRabatt.wert` | `PosDiscount.value` | lib/src/kasse/einstellungen.dart |
| `KasseSchnitt.wert` | `PosCut.value` | lib/src/kasse/einstellungen.dart |
| `KasseSchrift.wert` | `PosFontSize.value` | lib/src/kasse/einstellungen.dart |
| `KasseSettings.aus` | `PosSettings.fromJson` | lib/src/kasse/einstellungen.dart |
| `KasseSettings.betrieb` | `PosSettings.business` | lib/src/kasse/einstellungen.dart |
| `KasseSettings.geraet` | `PosSettings.device` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.aktiveSaetze` | `PosBusinessSettings.activeVatRates` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.ausJson` | `PosBusinessSettings.fromJson` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.fremdeWerte` | `PosBusinessSettings.unknownValues` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.kartenAktiv` | `PosBusinessSettings.cardPaymentEnabled` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.mit` | `PosBusinessSettings.merge` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet.ausJson` | `PosDeviceSettings.fromJson` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet.fremdeWerte` | `PosDeviceSettings.unknownValues` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet.mit` | `PosDeviceSettings.merge` | lib/src/kasse/einstellungen.dart |
| `KasseSkala.wert` | `PosLogoScale.value` / `PosWatermarkScale.value` | lib/src/kasse/einstellungen.dart |
| `KasseStil.wert` | `PosTheme.value` | lib/src/kasse/einstellungen.dart |
| `KasseTerminalArt.wert` | `PosTerminalType.value` | lib/src/kasse/einstellungen.dart |
| `KasseTerminalVia.wert` | `PosTerminalVia.value` | lib/src/kasse/einstellungen.dart |
| `KasseTgModus.wert` | `PosTipMode.value` | lib/src/kasse/einstellungen.dart |
| `KasseWasserzeichen.wert` | `PosWatermark.value` | lib/src/kasse/einstellungen.dart |
| `KasseWasserzeichenSeite.wert` | `PosWatermarkSide.value` | lib/src/kasse/einstellungen.dart |
| `KasseWert.wert` | `PosSettingValue.value` | lib/src/kasse/einstellungen.dart |
| `KasseZeichensatz.wert` | `PosCodePage.value` | lib/src/kasse/einstellungen.dart |
| `KasseEinstellungenClient.betriebSpeichern` | `PosSettingsClient.saveBusiness` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.geraetSpeichern` | `PosSettingsClient.saveDevice` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.laden` | `PosSettingsClient.load` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.logoEntfernen` | `PosSettingsClient.removeLogo` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.logoSetzen` | `PosSettingsClient.setLogo` | lib/src/kasse/einstellungen_client.dart |
| `Farbe.ausColor` | `PosColor.fromColor` | lib/src/kasse/farbe.dart |
| `Farbe.ausHex` | `PosColor.fromHex` | lib/src/kasse/farbe.dart |
| `Farbe.gemischt` | `PosColor.mixedWith` | lib/src/kasse/farbe.dart |
| `Farbe.helligkeit` | `PosColor.luminance` | lib/src/kasse/farbe.dart |
| `Farbe.istHex` | `PosColor.isHex` | lib/src/kasse/farbe.dart |
| `Farbe.wert` | `PosColor.value` | lib/src/kasse/farbe.dart |
| `Kachelbuchung.korb` | `TileBooking.cart` | lib/src/kasse/kacheln.dart |
| `Kachelbuchung.menge` | `TileBooking.quantity` | lib/src/kasse/kacheln.dart |
| `Kachelbuchung.zeileId` | `TileBooking.lineId` | lib/src/kasse/kacheln.dart |
| `Kategorie.farbe` | `TileCategory.color` | lib/src/kasse/kacheln.dart |
| `Kategorie.kacheln` | `TileCategory.tiles` | lib/src/kasse/kacheln.dart |
| `AbschlussPruefung.bereit` | `CompletionCheck.ready` | lib/src/kasse/kassieren.dart |
| `AbschlussPruefung.grund` | `CompletionCheck.reason` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.bar` | `CheckoutTotals.cash` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.bereit` | `CheckoutTotals.ready` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.fehltCents` | `CheckoutTotals.missingCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.gegebenCents` | `CheckoutTotals.tenderedCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.gesamtCents` | `CheckoutTotals.totalCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.grund` | `CheckoutTotals.reason` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.rabattCents` | `CheckoutTotals.discountCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.rueckgeldCents` | `CheckoutTotals.changeCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.summeCents` | `CheckoutTotals.subtotalCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.trinkgeldCents` | `CheckoutTotals.tipCents` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung.zuZahlenCents` | `CheckoutTotals.dueCents` | lib/src/kasse/kassieren.dart |
| `Kassierstand.gegebenCents` | `CheckoutState.tenderedCents` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie` | `CheckoutState.copyWith` | lib/src/kasse/kassieren.dart |
| `Kassierstand.rabattCents` | `CheckoutState.discountCents` | lib/src/kasse/kassieren.dart |
| `Kassierstand.trinkgeldCents` | `CheckoutState.tipCents` | lib/src/kasse/kassieren.dart |
| `Kassierstand.zahlungsart` | `CheckoutState.paymentMethod` | lib/src/kasse/kassieren.dart |
| `RabattArt.betrag` | `DiscountKind.amount` | lib/src/kasse/kassieren.dart |
| `RabattArt.prozent` | `DiscountKind.percent` | lib/src/kasse/kassieren.dart |
| `Kassenthema.aufMarke` | `PosThemeData.onBrand` | lib/src/kasse/thema.dart |
| `Kassenthema.aus` | `PosThemeData.fromSettings` | lib/src/kasse/thema.dart |
| `Kassenthema.fehler` | `PosThemeData.danger` | lib/src/kasse/thema.dart |
| `Kassenthema.fehlerHell` | `PosThemeData.dangerSurface` | lib/src/kasse/thema.dart |
| `Kassenthema.flaeche` | `PosThemeData.surface` | lib/src/kasse/thema.dart |
| `Kassenthema.flaecheHoch` | `PosThemeData.surfaceRaised` | lib/src/kasse/thema.dart |
| `Kassenthema.gross` | `PosThemeData.large` | lib/src/kasse/thema.dart |
| `Kassenthema.grund` | `PosThemeData.ground` | lib/src/kasse/thema.dart |
| `Kassenthema.gut` | `PosThemeData.success` | lib/src/kasse/thema.dart |
| `Kassenthema.gutHell` | `PosThemeData.successSurface` | lib/src/kasse/thema.dart |
| `Kassenthema.hell` | `PosThemeData.isLight` | lib/src/kasse/thema.dart |
| `Kassenthema.kachelhoehe` | `PosThemeData.tileHeight` | lib/src/kasse/thema.dart |
| `Kassenthema.kachelstil` | `PosThemeData.tileStyle` | lib/src/kasse/thema.dart |
| `Kassenthema.katFarben` | `PosThemeData.categoryColors` | lib/src/kasse/thema.dart |
| `Kassenthema.klein` | `PosThemeData.small` | lib/src/kasse/thema.dart |
| `Kassenthema.leise` | `PosThemeData.textMuted` | lib/src/kasse/thema.dart |
| `Kassenthema.linie` | `PosThemeData.lineWidth` | lib/src/kasse/thema.dart |
| `Kassenthema.marke` | `PosThemeData.brand` | lib/src/kasse/thema.dart |
| `Kassenthema.markeHell` | `PosThemeData.brandSurface` | lib/src/kasse/thema.dart |
| `Kassenthema.markeTief` | `PosThemeData.brandPressed` | lib/src/kasse/thema.dart |
| `Kassenthema.modus` | `PosThemeData.mode` | lib/src/kasse/thema.dart |
| `Kassenthema.radiusKachel` | `PosThemeData.radiusTile` | lib/src/kasse/thema.dart |
| `Kassenthema.radiusKlein` | `PosThemeData.radiusSmall` | lib/src/kasse/thema.dart |
| `Kassenthema.rand` | `PosThemeData.border` | lib/src/kasse/thema.dart |
| `Kassenthema.riesig` | `PosThemeData.huge` | lib/src/kasse/thema.dart |
| `Kassenthema.schattenTiefe` | `PosThemeData.shadowDepth` | lib/src/kasse/thema.dart |
| `Kassenthema.schriftfaktor` | `PosThemeData.fontScale` | lib/src/kasse/thema.dart |
| `Kassenthema.spaltenExtra` | `PosThemeData.extraColumns` | lib/src/kasse/thema.dart |
| `Kassenthema.stil` | `PosThemeData.theme` | lib/src/kasse/thema.dart |
| `Kassenthema.strich` | `PosThemeData.divider` | lib/src/kasse/thema.dart |
| `Kassenthema.titel` | `PosThemeData.title` | lib/src/kasse/thema.dart |
| `Kassenthema.warnung` | `PosThemeData.warning` | lib/src/kasse/thema.dart |
| `Kassenthema.warnungHell` | `PosThemeData.warningSurface` | lib/src/kasse/thema.dart |
| `Korbzeile.betragCents` | `CartLine.amountCents` | lib/src/kasse/warenkorb.dart |
| `Korbzeile.menge` | `CartLine.quantity` | lib/src/kasse/warenkorb.dart |
| `Korbzeile.position` | `CartLine.item` | lib/src/kasse/warenkorb.dart |
| `Position.alsBelegposition` | `Position.toReceiptItem` | lib/src/kasse/warenkorb.dart |
| `Position.maxMenge` | `Position.maxQuantity` | lib/src/kasse/warenkorb.dart |
| `Position.mitMenge` | `Position.withQuantity` | lib/src/kasse/warenkorb.dart |
| `Position.zeilensummeCents` | `Position.lineTotalCents` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf.betragCents` | `CartItemDraft.unitPriceCents` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf.bezeichnung` | `CartItemDraft.name` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf.maxMenge` | `CartItemDraft.maxQuantity` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf.steuersatz` | `CartItemDraft.vatRate` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.abgezogen` | `Cart.subtracted` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.entfernt` | `Cart.removed` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.hinzugefuegt` | `Cart.added` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.istLeer` | `Cart.isEmpty` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.leer` | `Cart.empty` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.mengeGesetzt` | `Cart.withQuantity` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.positionen` | `Cart.items` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.summeCents` | `Cart.totalCents` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.zeilen` | `Cart.lines` | lib/src/kasse/warenkorb.dart |
| `EscPosGenerator.setDruckbereich` | `EscPosGenerator.setPrintArea` | lib/src/printing/escpos/generator.dart |
| `QRCode.maxNutzlast` | `QRCode.maxPayload` | lib/src/printing/escpos/qrcode.dart |
| `QrGroesse.breitePunkte` | `QrSizing.widthDots` | lib/src/printing/qr_groesse.dart |
| `QrGroesse.module` | `QrSizing.modules` | lib/src/printing/qr_groesse.dart |
| `QrGroesse.passt` | `QrSizing.fits` | lib/src/printing/qr_groesse.dart |
| `QrGroesse.punkte` | `QrSizing.moduleDots` | lib/src/printing/qr_groesse.dart |
| `QrGroesse.unterMindestmass` | `QrSizing.belowMinimum` | lib/src/printing/qr_groesse.dart |
| `QrMass.ausnahmePunkte` | `QrMetrics.exceptionModuleDots` | lib/src/printing/qr_groesse.dart |
| `QrMass.berechne` | `QrMetrics.compute` | lib/src/printing/qr_groesse.dart |
| `QrMass.fuer` | `QrMetrics.forPayload` | lib/src/printing/qr_groesse.dart |
| `QrMass.hoechstPunkte` | `QrMetrics.maxModuleDots` | lib/src/printing/qr_groesse.dart |
| `QrMass.mindestPunkte` | `QrMetrics.minModuleDots` | lib/src/printing/qr_groesse.dart |
| `QrMass.modulAnzahl` | `QrMetrics.moduleCount` | lib/src/printing/qr_groesse.dart |
| `QrMass.ruhezoneModule` | `QrMetrics.quietZoneModules` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse.deckelPunkte` | `QrModuleSize.capDots` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse.gross` | `QrModuleSize.large` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse.klein` | `QrModuleSize.small` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse.mittel` | `QrModuleSize.medium` | lib/src/printing/qr_groesse.dart |
| `RechnungApi.mitTransport` | `InvoiceApi.withTransport` | lib/src/rechnung/api.dart |
| `Brand.felder` | `Brand.fields` | lib/src/rechnung/modelle.dart |
| `CancelResult.felder` | `CancelResult.fields` | lib/src/rechnung/modelle.dart |
| `CancelResult.originalFelder` | `CancelResult.originalFields` | lib/src/rechnung/modelle.dart |
| `CreditNoteResult.felder` | `CreditNoteResult.fields` | lib/src/rechnung/modelle.dart |
| `CreditNoteSummary.felder` | `CreditNoteSummary.fields` | lib/src/rechnung/modelle.dart |
| `EInvoiceStatus.felder` | `EInvoiceStatus.fields` | lib/src/rechnung/modelle.dart |
| `Invoice.brandFelder` | `Invoice.brandFields` | lib/src/rechnung/modelle.dart |
| `Invoice.detailFelder` | `Invoice.detailFields` | lib/src/rechnung/modelle.dart |
| `Invoice.felder` | `Invoice.fields` | lib/src/rechnung/modelle.dart |
| `Invoice.relatedFelder` | `Invoice.relatedFields` | lib/src/rechnung/modelle.dart |
| `InvoiceDetailPayment.felder` | `InvoiceDetailPayment.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceItem.felder` | `InvoiceItem.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceItem.preisInCent` | `InvoiceItem.priceInCents` | lib/src/rechnung/modelle.dart |
| `InvoiceItemInput.preisInCent` | `InvoiceItemInput.priceInCents` | lib/src/rechnung/modelle.dart |
| `InvoiceNotice.felder` | `InvoiceNotice.fields` | lib/src/rechnung/modelle.dart |
| `InvoicePage.felder` | `InvoicePage.fields` | lib/src/rechnung/modelle.dart |
| `InvoicePayment.felder` | `InvoicePayment.fields` | lib/src/rechnung/modelle.dart |
| `InvoicePreview.felder` | `InvoicePreview.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceRecipient.felder` | `InvoiceRecipient.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceSetupGap.felder` | `InvoiceSetupGap.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceSetupStatus.felder` | `InvoiceSetupStatus.fields` | lib/src/rechnung/modelle.dart |
| `InvoiceTotals.felder` | `InvoiceTotals.fields` | lib/src/rechnung/modelle.dart |
| `IssueResult.felder` | `IssueResult.fields` | lib/src/rechnung/modelle.dart |
| `PreviewResult.felder` | `PreviewResult.fields` | lib/src/rechnung/modelle.dart |
| `RecordPaymentResult.felder` | `RecordPaymentResult.fields` | lib/src/rechnung/modelle.dart |
| `SummenPosition.preisInCent` | `TotalsItem.priceInCents` | lib/src/rechnung/modelle.dart |
| `VatRateTotal.felder` | `VatRateTotal.fields` | lib/src/rechnung/modelle.dart |
| `RechnungTransport.rufen` | `InvoiceTransport.call` | lib/src/rechnung/transport.dart |
| `RechnungTransport.rufenBinaer` | `InvoiceTransport.callBinary` | lib/src/rechnung/transport.dart |
| `KasseneckHttpError.netz` | `KasseneckHttpError.reasonNetwork` | lib/src/register/fehler.dart |
| `KasseneckHttpError.zeitablauf` | `KasseneckHttpError.reasonTimeout` | lib/src/register/fehler.dart |
| `PairedRegisterDevice.felder` | `PairedRegisterDevice.fields` | lib/src/register/pairing.dart |
| `RegisterCashregisterState.felder` | `RegisterCashregisterState.fields` | lib/src/register/pairing.dart |
| `RegisterClient.sitzung` | `RegisterClient.session` | lib/src/register/pairing.dart |
| `RegisterDeviceUsers.felder` | `RegisterDeviceUsers.fields` | lib/src/register/pairing.dart |
| `RegisterPinPolicy.felder` | `RegisterPinPolicy.fields` | lib/src/register/pairing.dart |
| `RegisterSession.felder` | `RegisterSession.fields` | lib/src/register/pairing.dart |
| `RegisterSessionClient.aus` | `RegisterSessionClient.fromTransport` | lib/src/register/pairing.dart |
| `RegisterSessionsStand.felder` | `RegisterSessionOverview.fields` | lib/src/register/pairing.dart |
| `RegisterUser.felder` | `RegisterUser.fields` | lib/src/register/pairing.dart |
| `RegisterUserPerms.aus` | `RegisterUserPerms.fromJson` | lib/src/register/pairing.dart |
| `RegisterUserPerms.weitere` | `RegisterUserPerms.other` | lib/src/register/pairing.dart |
| `RegisterUserSession.felder` | `RegisterUserSession.fields` | lib/src/register/pairing.dart |
| `RegisterUserSummary.felder` | `RegisterUserSummary.fields` | lib/src/register/pairing.dart |
| `RegisterTransport.rufen` | `RegisterTransport.call` | lib/src/register/transport.dart |
| `KeckBelegBlattWidget.logoStufe` | `KeckReceiptSheetWidget.logoSize` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget.marke` | `KeckReceiptSheetWidget.brandMark` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget.qrFehltBuilder` | `KeckReceiptSheetWidget.qrMissingBuilder` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget.qrGroesse` | `KeckReceiptSheetWidget.qrModuleSize` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget.zeichen` | `KeckReceiptSheetWidget.charsPerLine` | lib/widgets/keck_beleg_blatt_widget.dart |

## E. Parameters

353 names. Named and positional parameters, also inside function types. `Owner(param)` is a constructor parameter, `Owner.method(param)` a method parameter.

| before | 10.0 | declared in (path before 10.0) |
|---|---|---|
| `KeckPaperSize(druckPunkte)` | `KeckPaperSize(printWidthDots)` | lib/enums/keck_paper_size.dart |
| `KasseQrModusDruck.druckmodusOder(vorgabe)` | `PosQrModePrint.printModeOr(fallback)` | lib/enums/qr_print_mode.dart |
| `KasseneckApi.belegSenden(an)` | `KasseneckApi.sendReceiptEmail(to)` | lib/kasseneck_api.dart |
| `KasseneckApi.getSignatureStatus(zertifikatNrHex)` | `KasseneckApi.getSignatureStatus(certificateSerialHex)` | lib/kasseneck_api.dart |
| `KasseneckApi.newHobexTransactionId(zeitpunkt)` | `KasseneckApi.newHobexTransactionId(now)` | lib/kasseneck_api.dart |
| `KasseneckApi.newHobexTransactionId(zufall)` | `KasseneckApi.newHobexTransactionId(random)` | lib/kasseneck_api.dart |
| `KasseneckApi.stornieren(anmerkung)` | `KasseneckApi.cancelReceipt(note)` | lib/kasseneck_api.dart |
| `KasseneckApi.stornieren(grund)` | `KasseneckApi.cancelReceipt(reason)` | lib/kasseneck_api.dart |
| `KasseneckApi.stornieren(positionen)` | `KasseneckApi.cancelReceipt(items)` | lib/kasseneck_api.dart |
| `KasseneckApi.stornieren(zahlungen)` | `KasseneckApi.cancelReceipt(payments)` | lib/kasseneck_api.dart |
| `BelegBlatt(bloecke)` | `ReceiptSheet(blocks)` | lib/models/beleg_blatt.dart |
| `BelegBlatt(zeichen)` | `ReceiptSheet(charsPerLine)` | lib/models/beleg_blatt.dart |
| `BlattLogo(pxBreite)` | `SheetLogo(pixelWidth)` | lib/models/beleg_blatt.dart |
| `BlattLogo(pxHoehe)` | `SheetLogo(pixelHeight)` | lib/models/beleg_blatt.dart |
| `BlattLogo(stufe)` | `SheetLogo(size)` | lib/models/beleg_blatt.dart |
| `BlattLogoBlock(breiteAnteil)` | `SheetLogoBlock(widthFraction)` | lib/models/beleg_blatt.dart |
| `BlattLogoBlock(hoeheZeilen)` | `SheetLogoBlock(heightLines)` | lib/models/beleg_blatt.dart |
| `BlattMarke(breite)` | `SheetBrandMark(width)` | lib/models/beleg_blatt.dart |
| `BlattMarke(hoehe)` | `SheetBrandMark(height)` | lib/models/beleg_blatt.dart |
| `BlattQr(breiteAnteil)` | `SheetQr(widthFraction)` | lib/models/beleg_blatt.dart |
| `BlattQr(nutzlast)` | `SheetQr(payload)` | lib/models/beleg_blatt.dart |
| `BlattZeile(fett)` | `SheetLine(bold)` | lib/models/beleg_blatt.dart |
| `BlattZeile(leer)` | `SheetLine(blank)` | lib/models/beleg_blatt.dart |
| `LogoMass(breiteAnteil)` | `LogoDimensions(widthFraction)` | lib/models/beleg_blatt.dart |
| `LogoMass(hoeheZeilen)` | `LogoDimensions(heightLines)` | lib/models/beleg_blatt.dart |
| `LogoStufe(breiteAnteil)` | `SheetLogoSize(widthFraction)` | lib/models/beleg_blatt.dart |
| `LogoStufe(hoeheZeilen)` | `SheetLogoSize(heightLines)` | lib/models/beleg_blatt.dart |
| `LogoStufe(kuerzel)` | `SheetLogoSize(code)` | lib/models/beleg_blatt.dart |
| `LogoStufe.ausKuerzel(kuerzel)` | `SheetLogoSize.fromCode(code)` | lib/models/beleg_blatt.dart |
| `belegBlatt(marke)` | `receiptSheet(brandMark)` | lib/models/beleg_blatt.dart |
| `belegBlatt(qrGroesse)` | `receiptSheet(qrModuleSize)` | lib/models/beleg_blatt.dart |
| `belegBlatt(zeichen)` | `receiptSheet(charsPerLine)` | lib/models/beleg_blatt.dart |
| `logoMass(zeichen)` | `logoDimensions(chars)` | lib/models/beleg_blatt.dart |
| `logoRasterMass(mass)` | `logoRasterSize(dimensions)` | lib/models/beleg_blatt.dart |
| `logoRasterMass(zeichen)` | `logoRasterSize(chars)` | lib/models/beleg_blatt.dart |
| `papierFuerZeichen(vorgabe)` | `paperSizeForChars(fallback)` | lib/models/beleg_blatt.dart |
| `papierFuerZeichen(zeichen)` | `paperSizeForChars(chars)` | lib/models/beleg_blatt.dart |
| `qrBlattAnteil(groesse)` | `qrSheetWidthFraction(moduleSize)` | lib/models/beleg_blatt.dart |
| `qrBlattAnteil(nutzlast)` | `qrSheetWidthFraction(payload)` | lib/models/beleg_blatt.dart |
| `qrBlattAnteil(papier)` | `qrSheetWidthFraction(paper)` | lib/models/beleg_blatt.dart |
| `qrModulAnzahlWieNpm(nutzlast)` | `qrModuleCount(payload)` | lib/models/beleg_blatt.dart |
| `qrPasstInVersionWieNpm(nutzlast)` | `qrFitsInVersion(payload)` | lib/models/beleg_blatt.dart |
| `LayoutBannerTone.aus(wert)` | `LayoutBannerTone.fromWire(value)` | lib/models/beleg_layout.dart |
| `BelegRaster(zeichen)` | `ReceiptGrid(charsPerLine)` | lib/models/beleg_raster.dart |
| `BelegRaster.render(zeichen)` | `ReceiptGrid.render(charsPerLine)` | lib/models/beleg_raster.dart |
| `RasterZeile(art)` | `GridLine(kind)` | lib/models/beleg_raster.dart |
| `RasterZeile(warnung)` | `GridLine(warning)` | lib/models/beleg_raster.dart |
| `rasterSpaltenBreiten(zeichen)` | `gridColumnWidths(chars)` | lib/models/beleg_raster.dart |
| `rasterSpaltenBreiten(zwoelftel)` | `gridColumnWidths(twelfths)` | lib/models/beleg_raster.dart |
| `KasseneckReceipt.getPrintBytes(qrGroesse)` | `KasseneckReceipt.getPrintBytes(qrModuleSize)` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.printReceiptBluetooth(qrGroesse)` | `KasseneckReceipt.printReceiptBluetooth(qrModuleSize)` | lib/models/kasseneck_receipt.dart |
| `migrateStoredReceiptJson(alt)` | `migrateStoredReceiptJson(stored)` | lib/models/kasseneck_receipt.dart |
| `KeckPayment.listeAus(roh)` | `KeckPayment.listFromJson(raw)` | lib/models/keck_payment.dart |
| `zahlungenFehler(storno)` | `paymentsError(cancellation)` | lib/models/keck_payment.dart |
| `zahlungenFehler(zahlungen)` | `paymentsError(payments)` | lib/models/keck_payment.dart |
| `zahlungsKonflikt(felder)` | `paymentsConflict(fields)` | lib/models/keck_payment.dart |
| `KeckPrintResult.failure(qrAusweich)` | `KeckPrintResult.failure(qrFallback)` | lib/models/keck_print_result.dart |
| `KeckPrintResult.failure(qrFehler)` | `KeckPrintResult.failure(qrError)` | lib/models/keck_print_result.dart |
| `KeckPrintResult.success(qrAusweich)` | `KeckPrintResult.success(qrFallback)` | lib/models/keck_print_result.dart |
| `KeckPrintResult.success(qrFehler)` | `KeckPrintResult.success(qrError)` | lib/models/keck_print_result.dart |
| `KeckTipPerson.aus(roh)` | `KeckTipPerson.fromJson(raw)` | lib/models/keck_tip_person.dart |
| `KeckUser(benid)` | `KeckUser(webserviceUserId)` | lib/models/keck_user.dart |
| `KeckUser(taxnr)` | `KeckUser(taxNumber)` | lib/models/keck_user.dart |
| `LogoRaster(breite)` | `LogoRaster(width)` | lib/models/logo_raster.dart |
| `LogoRaster(hoehe)` | `LogoRaster(height)` | lib/models/logo_raster.dart |
| `LogoRaster(punkte)` | `LogoRaster(dots)` | lib/models/logo_raster.dart |
| `logoPixelZulaessig(breite)` | `isLogoPixelSizeAllowed(width)` | lib/models/logo_raster.dart |
| `logoPixelZulaessig(hoehe)` | `isLogoPixelSizeAllowed(height)` | lib/models/logo_raster.dart |
| `logoRaster(mass)` | `logoRaster(dimensions)` | lib/models/logo_raster.dart |
| `logoRaster(pxBreite)` | `logoRaster(pixelWidth)` | lib/models/logo_raster.dart |
| `logoRaster(pxHoehe)` | `logoRaster(pixelHeight)` | lib/models/logo_raster.dart |
| `logoRaster(zeichen)` | `logoRaster(chars)` | lib/models/logo_raster.dart |
| `entpackeRasterBits(breite)` | `unpackRasterBits(width)` | lib/models/marke.dart |
| `entpackeRasterBits(hoehe)` | `unpackRasterBits(height)` | lib/models/marke.dart |
| `MarkeRasterDaten(breite)` | `BrandMarkRaster(width)` | lib/models/marke_daten.dart |
| `MarkeRasterDaten(hoehe)` | `BrandMarkRaster(height)` | lib/models/marke_daten.dart |
| `DruckLogo(pxBreite)` | `PrintLogo(pixelWidth)` | lib/models/print_paper.dart |
| `DruckLogo(pxHoehe)` | `PrintLogo(pixelHeight)` | lib/models/print_paper.dart |
| `DruckLogo(stufe)` | `PrintLogo(size)` | lib/models/print_paper.dart |
| `PrintPaper.addQrCode(groesse)` | `PrintPaper.addQrCode(moduleSize)` | lib/models/print_paper.dart |
| `PrintPaper.addQrCode(modell1)` | `PrintPaper.addQrCode(model1)` | lib/models/print_paper.dart |
| `PrintPaper.addQrCode(myPosGroesse)` | `PrintPaper.addQrCode(myPosSize)` | lib/models/print_paper.dart |
| `PrintPaper.setBelegBlatt(marke)` | `PrintPaper.setReceiptSheet(brandMark)` | lib/models/print_paper.dart |
| `PrintPaper.setBelegBlatt(qrGroesse)` | `PrintPaper.setReceiptSheet(qrModuleSize)` | lib/models/print_paper.dart |
| `PrintPaper.setBelegLayout(qrGroesse)` | `PrintPaper.setReceiptLayout(qrModuleSize)` | lib/models/print_paper.dart |
| `PrintPaper.setKeckReceipt(qrGroesse)` | `PrintPaper.setKeckReceipt(qrModuleSize)` | lib/models/print_paper.dart |
| `CancellationOf.fromJson(roh)` | `CancellationOf.fromJson(raw)` | lib/models/registration_info.dart |
| `RegistrationInfo.fromJson(roh)` | `RegistrationInfo.fromJson(raw)` | lib/models/registration_info.dart |
| `ladeDruckLogo(frist)` | `loadPrintLogo(timeout)` | lib/services/druck_logo.dart |
| `ladeDruckLogo(negativFrist)` | `loadPrintLogo(negativeCacheTtl)` | lib/services/druck_logo.dart |
| `ladeDruckLogo(papier)` | `loadPrintLogo(paper)` | lib/services/druck_logo.dart |
| `ladeDruckLogo(stufe)` | `loadPrintLogo(size)` | lib/services/druck_logo.dart |
| `KeckPrinter.printReceipt(qrGroesse)` | `KeckPrinter.printReceipt(qrModuleSize)` | lib/services/keck_printer.dart |
| `KeckPrinterService.getBytesFromReceipt(marke)` | `KeckPrinterService.getBytesFromReceipt(brandMark)` | lib/services/printer_service.dart |
| `KeckPrinterService.getBytesFromReceipt(qrGroesse)` | `KeckPrinterService.getBytesFromReceipt(qrModuleSize)` | lib/services/printer_service.dart |
| `KeckPrinterService.getMyPosPaperFromReceipt(marke)` | `KeckPrinterService.getMyPosPaperFromReceipt(brandMark)` | lib/services/printer_service.dart |
| `KeckPrinterService.getPaperFromReceipt(marke)` | `KeckPrinterService.getPaperFromReceipt(brandMark)` | lib/services/printer_service.dart |
| `KeckPrinterService.getPaperFromReceipt(qrGroesse)` | `KeckPrinterService.getPaperFromReceipt(qrModuleSize)` | lib/services/printer_service.dart |
| `KeckPrinterService.logoLader{papier}` | `KeckPrinterService.logoLoader{paper}` | lib/services/printer_service.dart |
| `KeckPrinterService.logoLader{stufe}` | `KeckPrinterService.logoLoader{size}` | lib/services/printer_service.dart |
| `KeckPrinterService.printReceiptBluetooth(qrGroesse)` | `KeckPrinterService.printReceiptBluetooth(qrModuleSize)` | lib/services/printer_service.dart |
| `Artikelgruppe(farbe)` | `ArticleGroup(color)` | lib/src/kasse/artikel.dart |
| `Artikelgruppe(steuersatz)` | `ArticleGroup(vatRate)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(aktiv)` | `PosArticle(active)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(einheit)` | `PosArticle(unit)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(erloesgruppeId)` | `PosArticle(revenueGroupId)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(gruppeId)` | `PosArticle(groupId)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(maxMenge)` | `PosArticle(maxQuantity)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(mengeFragen)` | `PosArticle(askQuantity)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(mengenregel)` | `PosArticle(quantityRule)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(preisCents)` | `PosArticle(unitPriceCents)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(sichtbar)` | `PosArticle(visible)` | lib/src/kasse/artikel.dart |
| `KasseArtikel(steuersatz)` | `PosArticle(vatRate)` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe(fragen)` | `QuantityDefaults(ask)` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe(regel)` | `QuantityDefaults(rule)` | lib/src/kasse/artikel.dart |
| `Mengenvorgabe(stellen)` | `QuantityDefaults(decimals)` | lib/src/kasse/artikel.dart |
| `mengeErlaubt(gewuenscht)` | `allowedQuantity(wanted)` | lib/src/kasse/artikel.dart |
| `mengenregelFuerEinheit(einheit)` | `quantityRuleForUnit(unit)` | lib/src/kasse/artikel.dart |
| `Belegzusammenfassung(bediener)` | `ReceiptSummary(operator)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(belegart)` | `ReceiptSummary(receiptType)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(nullbelegAnlass)` | `ReceiptSummary(zeroKind)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(positionen)` | `ReceiptSummary(items)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(signaturOk)` | `ReceiptSummary(signatureOk)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(storniertBeleg)` | `ReceiptSummary(cancellationOfReceiptId)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(stornoStand)` | `ReceiptSummary(cancellationState)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(stornogrund)` | `ReceiptSummary(cancellationReason)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(summeCents)` | `ReceiptSummary(totalCents)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(zaehler)` | `ReceiptSummary(counter)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(zahlungen)` | `ReceiptSummary(payments)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(zahlungsart)` | `ReceiptSummary(paymentMethod)` | lib/src/kasse/belege.dart |
| `Belegzusammenfassung(zeitstempel)` | `ReceiptSummary(timeStamp)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient(abschlussFrist)` | `RegisterReceiptClient(signingTimeout)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.auflisten(bis)` | `RegisterReceiptClient.list(to)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.auflisten(hoechstens)` | `RegisterReceiptClient.list(limit)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.auflisten(von)` | `RegisterReceiptClient.list(from)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.belegSenden(an)` | `RegisterReceiptClient.sendReceiptEmail(to)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.stornieren(anmerkung)` | `RegisterReceiptClient.cancelReceipt(note)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.stornieren(grund)` | `RegisterReceiptClient.cancelReceipt(reason)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.stornieren(positionen)` | `RegisterReceiptClient.cancelReceipt(items)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.stornieren(zahlungen)` | `RegisterReceiptClient.cancelReceipt(payments)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen(kundendaten)` | `RegisterReceiptClient.sell(customerLines)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen(positionen)` | `RegisterReceiptClient.sell(items)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen(rechtshinweise)` | `RegisterReceiptClient.sell(legalNotices)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen(trinkgeldCents)` | `RegisterReceiptClient.sell(tipCents)` | lib/src/kasse/belege.dart |
| `RegisterReceiptClient.verkaufen(zahlungen)` | `RegisterReceiptClient.sell(payments)` | lib/src/kasse/belege.dart |
| `Stornoergebnis(beleg)` | `CancelReceiptResult(receipt)` | lib/src/kasse/belege.dart |
| `Stornoergebnis(restmengen)` | `CancelReceiptResult(remaining)` | lib/src/kasse/belege.dart |
| `Stornoergebnis.ausAntwort(beleg)` | `CancelReceiptResult.fromResponse(receipt)` | lib/src/kasse/belege.dart |
| `Stornoergebnis.ausAntwort(daten)` | `CancelReceiptResult.fromResponse(data)` | lib/src/kasse/belege.dart |
| `Belegfilter(belegart)` | `ReceiptFilter(receiptType)` | lib/src/kasse/belegliste.dart |
| `Belegfilter(wer)` | `ReceiptFilter(operator)` | lib/src/kasse/belegliste.dart |
| `Belegfilter(zahlung)` | `ReceiptFilter(payment)` | lib/src/kasse/belegliste.dart |
| `Belegfilter(zeitraum)` | `ReceiptFilter(period)` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie(belegart)` | `ReceiptFilter.copyWith(receiptType)` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie(wer)` | `ReceiptFilter.copyWith(operator)` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie(werLoeschen)` | `ReceiptFilter.copyWith(clearOperator)` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie(zahlung)` | `ReceiptFilter.copyWith(payment)` | lib/src/kasse/belegliste.dart |
| `Belegfilter.kopie(zeitraum)` | `ReceiptFilter.copyWith(period)` | lib/src/kasse/belegliste.dart |
| `Tagesgruppe(belege)` | `ReceiptDayGroup(receipts)` | lib/src/kasse/belegliste.dart |
| `Tagesgruppe(datum)` | `ReceiptDayGroup(date)` | lib/src/kasse/belegliste.dart |
| `bediener(belege)` | `operatorNames(receipts)` | lib/src/kasse/belegliste.dart |
| `belegartText(beleg)` | `receiptTypeLabel(receipt)` | lib/src/kasse/belegliste.dart |
| `gefiltert(belege)` | `filterReceipts(receipts)` | lib/src/kasse/belegliste.dart |
| `tagesgruppen(belege)` | `groupByDay(receipts)` | lib/src/kasse/belegliste.dart |
| `uhrzeit(zeitstempel)` | `receiptTime(timestamp)` | lib/src/kasse/belegliste.dart |
| `wienDatum(zeitpunkt)` | `viennaDate(instant)` | lib/src/kasse/belegliste.dart |
| `zeitfenster(jetzt)` | `periodRange(now)` | lib/src/kasse/belegliste.dart |
| `zeitfenster(zeitraum)` | `periodRange(period)` | lib/src/kasse/belegliste.dart |
| `Belegmailergebnis.aus(daten)` | `SendReceiptEmailResult.fromResponse(data)` | lib/src/kasse/belegmail.dart |
| `Belegmailergebnis.aus(gesendetAn)` | `SendReceiptEmailResult.fromResponse(sentTo)` | lib/src/kasse/belegmail.dart |
| `istBelegMailFehlercode(wert)` | `isReceiptEmailErrorCode(value)` | lib/src/kasse/belegmail.dart |
| `isPosError(fehler)` | `isPosError(error)` | lib/src/kasse/codes.dart |
| `isPosErrorCode(wert)` | `isPosErrorCode(value)` | lib/src/kasse/codes.dart |
| `posErrorCode(fehler)` | `posErrorCode(error)` | lib/src/kasse/codes.dart |
| `posFieldErrors(fehler)` | `posFieldErrors(error)` | lib/src/kasse/codes.dart |
| `KasseDruckerClient.druckjobAnlegen(markeZeigen)` | `PosPrinterClient.createPrintJob(brandMark)` | lib/src/kasse/drucker.dart |
| `KasseDruckerClient.druckjobAnlegen(quelle)` | `PosPrinterClient.createPrintJob(source)` | lib/src/kasse/drucker.dart |
| `KasseDruckerClient.druckjobAnlegen(titel)` | `PosPrinterClient.createPrintJob(title)` | lib/src/kasse/drucker.dart |
| `KasseEinstellSchrift(wert)` | `PosSettingsFontSize(value)` | lib/src/kasse/einstellungen.dart |
| `KasseGroesse(wert)` | `PosLogoSize(value)` | lib/src/kasse/einstellungen.dart |
| `KasseHoehe(wert)` | `PosTileHeight(value)` | lib/src/kasse/einstellungen.dart |
| `KasseSchrift(wert)` | `PosFontSize(value)` | lib/src/kasse/einstellungen.dart |
| `KasseSettings(betrieb)` | `PosSettings(business)` | lib/src/kasse/einstellungen.dart |
| `KasseSettings(geraet)` | `PosSettings(device)` | lib/src/kasse/einstellungen.dart |
| `KasseSettings.aus(gespeichert)` | `PosSettings.fromJson(stored)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb(fremdeWerte)` | `PosBusinessSettings(unknownValues)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.ausJson(roh)` | `PosBusinessSettings.fromJson(raw)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsBetrieb.mit(aenderung)` | `PosBusinessSettings.merge(patch)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet(fremdeWerte)` | `PosDeviceSettings(unknownValues)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet.ausJson(roh)` | `PosDeviceSettings.fromJson(raw)` | lib/src/kasse/einstellungen.dart |
| `KasseSettingsGeraet.mit(aenderung)` | `PosDeviceSettings.merge(patch)` | lib/src/kasse/einstellungen.dart |
| `KasseSkala(wert)` | `PosLogoScale(value)` / `PosWatermarkScale(value)` | lib/src/kasse/einstellungen.dart |
| `KasseZeichensatz(wert)` | `PosCodePage(value)` | lib/src/kasse/einstellungen.dart |
| `entwirreTasten(gemischt)` | `untangleShortcuts(mixed)` | lib/src/kasse/einstellungen.dart |
| `entwirreTasten(gespeichert)` | `untangleShortcuts(stored)` | lib/src/kasse/einstellungen.dart |
| `istAltwert0x(feld)` | `isLegacyValue0x(field)` | lib/src/kasse/einstellungen.dart |
| `istAltwert0x(wert)` | `isLegacyValue0x(value)` | lib/src/kasse/einstellungen.dart |
| `posSettingsChanges(nachher)` | `posSettingsChanges(after)` | lib/src/kasse/einstellungen.dart |
| `posSettingsChanges(vorher)` | `posSettingsChanges(before)` | lib/src/kasse/einstellungen.dart |
| `KasseEinstellungenClient.betriebSpeichern(aenderung)` | `PosSettingsClient.saveBusiness(patch)` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.geraetSpeichern(aenderung)` | `PosSettingsClient.saveDevice(patch)` | lib/src/kasse/einstellungen_client.dart |
| `KasseEinstellungenClient.logoSetzen(bild)` | `PosSettingsClient.setLogo(image)` | lib/src/kasse/einstellungen_client.dart |
| `Farbe.ausHex(ersatz)` | `PosColor.fromHex(fallback)` | lib/src/kasse/farbe.dart |
| `Farbe.gemischt(andere)` | `PosColor.mixedWith(other)` | lib/src/kasse/farbe.dart |
| `Farbe.gemischt(anteil)` | `PosColor.mixedWith(fraction)` | lib/src/kasse/farbe.dart |
| `farbeAusHsv(helligkeit)` | `colorFromHsv(value)` | lib/src/kasse/farbe.dart |
| `farbeAusHsv(saettigung)` | `colorFromHsv(saturation)` | lib/src/kasse/farbe.dart |
| `farbeAusHsv(ton)` | `colorFromHsv(hue)` | lib/src/kasse/farbe.dart |
| `lesbarAuf(dunkel)` | `readableOn(dark)` | lib/src/kasse/farbe.dart |
| `lesbarAuf(grund)` | `readableOn(background)` | lib/src/kasse/farbe.dart |
| `lesbarAuf(hell)` | `readableOn(light)` | lib/src/kasse/farbe.dart |
| `markeTaugt(farbe)` | `isUsableBrandColor(color)` | lib/src/kasse/farbe.dart |
| `Kachelbuchung(korb)` | `TileBooking(cart)` | lib/src/kasse/kacheln.dart |
| `Kachelbuchung(menge)` | `TileBooking(quantity)` | lib/src/kasse/kacheln.dart |
| `Kachelbuchung(zeileId)` | `TileBooking(lineId)` | lib/src/kasse/kacheln.dart |
| `Kategorie(farbe)` | `TileCategory(color)` | lib/src/kasse/kacheln.dart |
| `Kategorie(kacheln)` | `TileCategory(tiles)` | lib/src/kasse/kacheln.dart |
| `gebucht(buendeln)` | `bookTile(bundle)` | lib/src/kasse/kacheln.dart |
| `gebucht(entwurf)` | `bookTile(draft)` | lib/src/kasse/kacheln.dart |
| `gebucht(korb)` | `bookTile(cart)` | lib/src/kasse/kacheln.dart |
| `kategorien(artikel)` | `tileCategories(articles)` | lib/src/kasse/kacheln.dart |
| `kategorien(gruppen)` | `tileCategories(groups)` | lib/src/kasse/kacheln.dart |
| `suche(kategorien)` | `searchTiles(categories)` | lib/src/kasse/kacheln.dart |
| `AbschlussPruefung(bereit)` | `CompletionCheck(ready)` | lib/src/kasse/kassieren.dart |
| `AbschlussPruefung(grund)` | `CompletionCheck(reason)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(bar)` | `CheckoutTotals(cash)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(bereit)` | `CheckoutTotals(ready)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(fehltCents)` | `CheckoutTotals(missingCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(gegebenCents)` | `CheckoutTotals(tenderedCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(gesamtCents)` | `CheckoutTotals(totalCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(grund)` | `CheckoutTotals(reason)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(rabattCents)` | `CheckoutTotals(discountCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(rueckgeldCents)` | `CheckoutTotals(changeCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(summeCents)` | `CheckoutTotals(subtotalCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(trinkgeldCents)` | `CheckoutTotals(tipCents)` | lib/src/kasse/kassieren.dart |
| `Kassierrechnung(zuZahlenCents)` | `CheckoutTotals(dueCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand(gegebenCents)` | `CheckoutState(tenderedCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand(rabattCents)` | `CheckoutState(discountCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand(trinkgeldCents)` | `CheckoutState(tipCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand(zahlungsart)` | `CheckoutState(paymentMethod)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie(gegebenCents)` | `CheckoutState.copyWith(tenderedCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie(gegebenLoeschen)` | `CheckoutState.copyWith(clearTendered)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie(rabattCents)` | `CheckoutState.copyWith(discountCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie(trinkgeldCents)` | `CheckoutState.copyWith(tipCents)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.kopie(zahlungsart)` | `CheckoutState.copyWith(paymentMethod)` | lib/src/kasse/kassieren.dart |
| `Kassierstand.start(betrieb)` | `CheckoutState.start(business)` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung(gegeben)` | `completionCheck(tenderedCents)` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung(leer)` | `completionCheck(cartEmpty)` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung(rueckgeldAn)` | `completionCheck(changeEnabled)` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung(zahlungsart)` | `completionCheck(paymentMethod)` | lib/src/kasse/kassieren.dart |
| `abschlussPruefung(zuZahlen)` | `completionCheck(dueCents)` | lib/src/kasse/kassieren.dart |
| `barzahlung(betragCents)` | `cashPayment(amountCents)` | lib/src/kasse/kassieren.dart |
| `barzahlung(rechnung)` | `cashPayment(invoice)` | lib/src/kasse/kassieren.dart |
| `belegPositionen(rabatt)` | `receiptItems(discount)` | lib/src/kasse/kassieren.dart |
| `belegPositionen(warenkorb)` | `receiptItems(cart)` | lib/src/kasse/kassieren.dart |
| `kassierrechnung(betrieb)` | `checkoutTotals(business)` | lib/src/kasse/kassieren.dart |
| `kassierrechnung(stand)` | `checkoutTotals(state)` | lib/src/kasse/kassieren.dart |
| `kassierrechnung(warenkorb)` | `checkoutTotals(cart)` | lib/src/kasse/kassieren.dart |
| `rabattCents(art)` | `discountCentsFor(kind)` | lib/src/kasse/kassieren.dart |
| `rabattCents(summe)` | `discountCentsFor(total)` | lib/src/kasse/kassieren.dart |
| `rabattCents(wert)` | `discountCentsFor(value)` | lib/src/kasse/kassieren.dart |
| `rueckgeld(gegebenCents)` | `computeChange(tenderedCents)` | lib/src/kasse/kassieren.dart |
| `rueckgeld(zuZahlenCents)` | `computeChange(dueCents)` | lib/src/kasse/kassieren.dart |
| `schnellbetraege(zuZahlenCents)` | `quickAmounts(dueCents)` | lib/src/kasse/kassieren.dart |
| `ustSumme(rabattCents)` | `vatTotalCents(discountCents)` | lib/src/kasse/kassieren.dart |
| `ustSumme(warenkorb)` | `vatTotalCents(cart)` | lib/src/kasse/kassieren.dart |
| `ustSummePositionen(positionen)` | `vatTotalCentsOfItems(items)` | lib/src/kasse/kassieren.dart |
| `verteileRabatt(positionen)` | `distributeDiscount(items)` | lib/src/kasse/kassieren.dart |
| `verteileRabatt(rabattCents)` | `distributeDiscount(discountCents)` | lib/src/kasse/kassieren.dart |
| `zahlungsarten(betrieb)` | `offeredPaymentMethods(business)` | lib/src/kasse/kassieren.dart |
| `zuZahlen(rabatt)` | `amountDue(discount)` | lib/src/kasse/kassieren.dart |
| `zuZahlen(warenkorb)` | `amountDue(cart)` | lib/src/kasse/kassieren.dart |
| `belegSichtbar(beleg)` | `isReceiptVisible(receipt)` | lib/src/kasse/storno.dart |
| `belegSichtbar(eigeneUid)` | `isReceiptVisible(ownUid)` | lib/src/kasse/storno.dart |
| `belegSichtbar(reichweite)` | `isReceiptVisible(scope)` | lib/src/kasse/storno.dart |
| `istStornoFehlercode(wert)` | `isCancellationErrorCode(value)` | lib/src/kasse/storno.dart |
| `pruefeKartenRueckbuchung(zahlungen)` | `assertCardRefunds(payments)` | lib/src/kasse/storno.dart |
| `restmengen(beleg)` | `remainingQuantities(receipt)` | lib/src/kasse/storno.dart |
| `restmengen(jetzt)` | `remainingQuantities(nowMs)` | lib/src/kasse/storno.dart |
| `stornoErlaubt(beleg)` | `canCancel(receipt)` | lib/src/kasse/storno.dart |
| `stornoErlaubt(eigeneUid)` | `canCancel(ownUid)` | lib/src/kasse/storno.dart |
| `stornoErlaubt(reichweite)` | `canCancel(scope)` | lib/src/kasse/storno.dart |
| `volleId(nummer)` | `fullReceiptIdFromNumber(number)` | lib/src/kasse/storno.dart |
| `belegIstTest(testKasse)` | `receiptIsTest(testCashregister)` | lib/src/kasse/testkennzeichen.dart |
| `Kassenthema(kachelhoehe)` | `PosThemeData(tileHeight)` | lib/src/kasse/thema.dart |
| `Kassenthema(kachelstil)` | `PosThemeData(tileStyle)` | lib/src/kasse/thema.dart |
| `Kassenthema(katFarben)` | `PosThemeData(categoryColors)` | lib/src/kasse/thema.dart |
| `Kassenthema(linie)` | `PosThemeData(lineWidth)` | lib/src/kasse/thema.dart |
| `Kassenthema(modus)` | `PosThemeData(mode)` | lib/src/kasse/thema.dart |
| `Kassenthema(radiusKachel)` | `PosThemeData(radiusTile)` | lib/src/kasse/thema.dart |
| `Kassenthema(radiusKlein)` | `PosThemeData(radiusSmall)` | lib/src/kasse/thema.dart |
| `Kassenthema(schattenTiefe)` | `PosThemeData(shadowDepth)` | lib/src/kasse/thema.dart |
| `Kassenthema(schriftfaktor)` | `PosThemeData(fontScale)` | lib/src/kasse/thema.dart |
| `Kassenthema(spaltenExtra)` | `PosThemeData(extraColumns)` | lib/src/kasse/thema.dart |
| `Kassenthema(stil)` | `PosThemeData(theme)` | lib/src/kasse/thema.dart |
| `Kassenthema.aus(betrieb)` | `PosThemeData.fromSettings(business)` | lib/src/kasse/thema.dart |
| `Kassenthema.aus(geraet)` | `PosThemeData.fromSettings(device)` | lib/src/kasse/thema.dart |
| `modusFuer(stil)` | `modeFor(style)` | lib/src/kasse/thema.dart |
| `Korbzeile(betragCents)` | `CartLine(amountCents)` | lib/src/kasse/warenkorb.dart |
| `Korbzeile(menge)` | `CartLine(quantity)` | lib/src/kasse/warenkorb.dart |
| `Korbzeile(position)` | `CartLine(item)` | lib/src/kasse/warenkorb.dart |
| `Position(maxMenge)` | `Position(maxQuantity)` | lib/src/kasse/warenkorb.dart |
| `Position.mitMenge(menge)` | `Position.withQuantity(quantity)` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf(betragCents)` | `CartItemDraft(unitPriceCents)` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf(bezeichnung)` | `CartItemDraft(name)` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf(maxMenge)` | `CartItemDraft(maxQuantity)` | lib/src/kasse/warenkorb.dart |
| `Positionsentwurf(steuersatz)` | `CartItemDraft(vatRate)` | lib/src/kasse/warenkorb.dart |
| `Warenkorb(positionen)` | `Cart(items)` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.abgezogen(verkauft)` | `Cart.subtracted(sold)` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.hinzugefuegt(entwurf)` | `Cart.added(draft)` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.mengeGesetzt(menge)` | `Cart.withQuantity(quantity)` | lib/src/kasse/warenkorb.dart |
| `Warenkorb.zeilen(modus)` | `Cart.lines(mode)` | lib/src/kasse/warenkorb.dart |
| `steuersatzText(satz)` | `formatVatRate(rate)` | lib/src/kasse/warenkorb.dart |
| `istZahlungFehlercode(wert)` | `isPaymentErrorCode(value)` | lib/src/kasse/zahlungen.dart |
| `EscPosGenerator.qrcode(modell1)` | `EscPosGenerator.qrcode(model1)` | lib/src/printing/escpos/generator.dart |
| `EscPosGenerator.setStyles(zeilenanfang)` | `EscPosGenerator.setStyles(atLineStart)` | lib/src/printing/escpos/generator.dart |
| `QRCode(modell1)` | `QRCode(model1)` | lib/src/printing/escpos/qrcode.dart |
| `QrMass.berechne(groesse)` | `QrMetrics.compute(moduleSize)` | lib/src/printing/qr_groesse.dart |
| `QrMass.berechne(moduleAnzahl)` | `QrMetrics.compute(moduleCount)` | lib/src/printing/qr_groesse.dart |
| `QrMass.berechne(papierbreitePunkte)` | `QrMetrics.compute(paperWidthDots)` | lib/src/printing/qr_groesse.dart |
| `QrMass.fuer(groesse)` | `QrMetrics.forPayload(moduleSize)` | lib/src/printing/qr_groesse.dart |
| `QrMass.fuer(nutzlast)` | `QrMetrics.forPayload(payload)` | lib/src/printing/qr_groesse.dart |
| `QrMass.fuer(papierbreitePunkte)` | `QrMetrics.forPayload(paperWidthDots)` | lib/src/printing/qr_groesse.dart |
| `QrMass.modulAnzahl(nutzlast)` | `QrMetrics.moduleCount(payload)` | lib/src/printing/qr_groesse.dart |
| `QrModulGroesse(deckelPunkte)` | `QrModuleSize(capDots)` | lib/src/printing/qr_groesse.dart |
| `isReceiptErrorCode(wert)` | `isReceiptErrorCode(value)` | lib/src/receipt/codes.dart |
| `ReceiptDueTip.fromKeckTip(istInhaber)` | `ReceiptDueTip.fromKeckTip(isOwner)` | lib/src/receipt/due.dart |
| `RechnungApi.createCreditNote(anfrage)` | `InvoiceApi.createCreditNote(request)` | lib/src/rechnung/api.dart |
| `RechnungApi.issueInvoice(anfrage)` | `InvoiceApi.issueInvoice(request)` | lib/src/rechnung/api.dart |
| `RechnungApi.previewInvoice(anfrage)` | `InvoiceApi.previewInvoice(request)` | lib/src/rechnung/api.dart |
| `RechnungApi.recordInvoicePayment(anfrage)` | `InvoiceApi.recordInvoicePayment(request)` | lib/src/rechnung/api.dart |
| `rechnungFehlerCode(fehler)` | `invoiceErrorCode(error)` | lib/src/rechnung/api.dart |
| `rechnungFeldFehler(fehler)` | `invoiceFieldErrors(error)` | lib/src/rechnung/api.dart |
| `fieldErrors(fehler)` | `fieldErrors(error)` | lib/src/register/codes.dart |
| `isRegisterError(fehler)` | `isRegisterError(error)` | lib/src/register/codes.dart |
| `isRegisterErrorCode(wert)` | `isRegisterErrorCode(value)` | lib/src/register/codes.dart |
| `registerErrorCode(fehler)` | `registerErrorCode(error)` | lib/src/register/codes.dart |
| `registerErrorDetails(fehler)` | `registerErrorDetails(error)` | lib/src/register/codes.dart |
| `registerFieldErrors(fehler)` | `registerFieldErrors(error)` | lib/src/register/codes.dart |
| `fehlercodeAus(huelle)` | `errorCodeFrom(envelope)` | lib/src/register/fehler.dart |
| `readSignedResponse(kennung)` | `readSignedResponse(receiptId)` | lib/src/register/fehler.dart |
| `readSignedResponse(lesen)` | `readSignedResponse(read)` | lib/src/register/fehler.dart |
| `RegisterUserPerms(weitere)` | `RegisterUserPerms(other)` | lib/src/register/pairing.dart |
| `RegisterUserPerms.aus(roh)` | `RegisterUserPerms.fromJson(raw)` | lib/src/register/pairing.dart |
| `RegisterTransport.rufen(frist)` | `RegisterTransport.call(timeout)` | lib/src/register/transport.dart |
| `nettoCentsAusBrutto(bruttoCents)` | `netCentsFromGross(grossCents)` | lib/src/vat_math.dart |
| `ustCentsAusBrutto(bruttoCents)` | `vatCentsFromGross(grossCents)` | lib/src/vat_math.dart |
| `KeckBelegBlattWidget(logoStufe)` | `KeckReceiptSheetWidget(logoSize)` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget(marke)` | `KeckReceiptSheetWidget(brandMark)` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget(qrFehltBuilder)` | `KeckReceiptSheetWidget(qrMissingBuilder)` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget(qrGroesse)` | `KeckReceiptSheetWidget(qrModuleSize)` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget(zeichen)` | `KeckReceiptSheetWidget(charsPerLine)` | lib/widgets/keck_beleg_blatt_widget.dart |
| `KeckBelegBlattWidget.qrFehltBuilder{nutzlast}` | `KeckReceiptSheetWidget.qrMissingBuilder{payload}` | lib/widgets/keck_beleg_blatt_widget.dart |

## F. Named record fields

11 names. `name{field}` is a field of a record type in that declaration.

| before | 10.0 | declared in (path before 10.0) |
|---|---|---|
| `logoRasterMass{breite}` | `logoRasterSize{width}` | lib/models/beleg_blatt.dart |
| `logoRasterMass{hoehe}` | `logoRasterSize{height}` | lib/models/beleg_blatt.dart |
| `KasseneckReceipt.kartenzahlungen{anbieter}` | `KasseneckReceipt.cardPayments{provider}` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.kartenzahlungen{daten}` | `KasseneckReceipt.cardPayments{data}` | lib/models/kasseneck_receipt.dart |
| `KasseneckReceipt.kartenzahlungen{kennung}` | `KasseneckReceipt.cardPayments{paymentId}` | lib/models/kasseneck_receipt.dart |
| `PixelLader{breite}` | `PixelLoader{width}` | lib/services/druck_logo.dart |
| `PixelLader{hoehe}` | `PixelLoader{height}` | lib/services/druck_logo.dart |
| `Belegzusammenfassung.positionen{menge}` | `ReceiptSummary.items{quantity}` | lib/src/kasse/belege.dart |
| `Stornoposition{menge}` | `CancellationItem{quantity}` | lib/src/kasse/belege.dart |
| `zeitfenster{bis}` | `periodRange{to}` | lib/src/kasse/belegliste.dart |
| `zeitfenster{von}` | `periodRange{from}` | lib/src/kasse/belegliste.dart |

## G. Removed without a direct successor

| 9.x | use instead |
|---|---|
| `KasseneckApi.cancelReceipt(receipt: ...)` (the 9.x cancellation without reference) | `KasseneckApi.cancelReceipt(cashregisterId:, originalReceiptId:, reason:, ...)`, the former `stornieren`. The name now belongs to the cancellation with reference. |
| `KasseneckApi.createCancelReceipt` | `KasseneckApi.cancelReceipt` (with reference) |
| `KasseneckApi.sellReceipt(paymentMethod, creditCardProvider, cardPaymentId, cardPaymentData)` | `sellReceipt(payments: [KeckPaymentInput(method:, provider:, providerPaymentId:, providerData:)])` |
| `RegisterReceiptClient.verkaufen(zahlungsart, kartenanbieter, kartenzahlungId, kartenzahlungsdaten)` | `RegisterReceiptClient.sell(payments: [KeckPaymentInput(...)])` |
| `KasseneckApi.stornieren(zahlungsart, kartenanbieter, kartenzahlungId, kartenzahlungsdaten)` | `KasseneckApi.cancelReceipt(payments: [KeckPaymentInput(...)], original:)` |
| `RegisterReceiptClient.stornieren(zahlungsart)` | `RegisterReceiptClient.cancelReceipt(payments: [KeckPaymentInput(...)])` |
