# Druck-Stack entkoppeln: kein `image`, kein `esc_pos_utils_plus`

**Datum:** 2026-06-22
**Status:** Freigegeben (Design)

## Problem

Der Belegdruck — besonders über Bluetooth-Thermodrucker — ist seit dem Umstieg auf
`image 4.x` instabil. Ursache ist nicht das `image`-Paket selbst, sondern der
ESC/POS-Generator `esc_pos_utils_plus 2.0.4`, der mit `image 4.x` hereinkam.

### Belegte Ursache (reproduziert)

`Generator._toRasterFormat` (generator.dart:166 in `esc_pos_utils_plus 2.0.4`) ist für
jedes Bild kaputt, dessen **Breite kein Vielfaches von 8** ist:

```dart
if (widthPx % 8 != 0) {
  oneChannelBytes = List<int>.filled(heightPx * targetWidth, 0); // ① echte Pixel weg, ② fixed-length
  for (int i = 0; i < heightPx; i++) {
    final pos = (i * widthPx) + i * missingPx;                   // ③ falsche Position (Zeilen-Anfang)
    oneChannelBytes.insertAll(pos, extra);                       // -> CRASH auf fixed-length list
  }
}
```

Minimaler Reproduktions-Test bestätigt: Breite 16 (÷8) funktioniert; Breite 10 wirft
`Unsupported operation: Cannot add to a fixed-length list` bei `generator.dart:192`.
Das deckt sich mit CHANGELOG 3.2.0 ("Fixed an ESC/POS rasterizer crash for images whose
width is not a multiple of 8").

Die **alte** Version `esc_pos_utils 1.1.0` hat denselben Algorithmus **korrekt**
(wachsende Liste, Padding am Zeilen-ENDE, Pixel bleiben erhalten). Der `_plus`-Fork hat
hier eine Regression eingebaut. Der einzige sachliche Grund für den Fork war die
`image`-4.x-API (`getBytes(order: ChannelOrder.rgba)` statt `getBytes(format: Format.rgba)`).

### Dependency-Dilemma

| Option | Rasterizer | image-Version | Wartung |
|---|---|---|---|
| `esc_pos_utils` (alt 1.1.0) | korrekt | pinnt `image: ^3.0.2` | tot |
| `esc_pos_utils_plus` (2.0.4) | kaputt (÷8-Workaround nötig) | `image: ^4.0.17` | aktiv |

Eine Dart-App kann nur **eine** `image`-Version haben. Solange `kasseneck_api` `image`
(oder `esc_pos_utils*`) als Abhängigkeit deklariert, zwingt es dem Hauptprojekt diese
Version auf. Zurück auf `esc_pos_utils` würde `image` sogar auf 3.x festnageln.

## Ziel

`kasseneck_api` deklariert **weder `image` noch `esc_pos_utils_plus`** als Abhängigkeit.
Das Hauptprojekt ist damit frei in seiner `image`-Version. Gleichzeitig ist der
Rasterizer-Bug beseitigt, weil wir die **korrekte** Packing-Logik aus
`esc_pos_utils 1.1.0` ins Paket vendoren.

`my_pos` und `qr_flutter` bleiben unverändert als Abhängigkeiten.

## Architektur

Zwei neue interne Module unter `lib/src/printing/`. Keine pub-Abhängigkeit auf `image`
oder `esc_pos_utils*`.

### 1. `lib/src/printing/raster/` — Bild-Primitive (RGBA)

- **`RasterImage`** — Datenklasse: `int width`, `int height`, `Uint8List rgba`
  (4 Bytes/Pixel, R,G,B,A). Keine Logik außer Pixelzugriff.
- **Synchrone Pixelops** (pure Dart, host-testbar, ohne Flutter-Engine):
  - `RasterImage resizeWidth(RasterImage src, int targetWidth)` — Breite skalieren,
    Höhe proportional (entspricht `copyResize(width: …)`).
  - `RasterImage compositeOnWhite(RasterImage src, {int dstX = 0, int dstY = 0, int? canvasWidth, int? canvasHeight})`
    — transparenten Vordergrund auf weißen Hintergrund komponieren (Alpha-Blend).
    Deckt `fill(white)` + `compositeImage` ab (inkl. QR-Ruhezone via dstX/dstY + Canvas-Größe).
  - `List<int> toEscPosRaster(RasterImage img)` — **der korrekte Algorithmus aus
    esc_pos_utils 1.1.0**: grayscale → invert → 1 Kanal → Padding auf Breite ÷8
    (wachsende Liste, Padding am Zeilen-Ende) → Bit-Packing (Threshold 127). Liefert die
    Rohdaten für den GS-v-0-Befehl (`imageRaster`).
  - `List<List<int>> toColumnFormat(RasterImage img, int lineHeight)` — Column-Packer aus
    esc_pos_utils 1.1.0 für den ESC-*-Bit-Image-Befehl (`image`, genutzt von
    `QrPrintMode.imageBitImage`). Padding der Breite auf Vielfaches von `lineHeight`,
    Luminanz pro Spalten-Slice.
- **dart:ui-Brücke** (async, nur an der Codec-Grenze):
  - `Future<RasterImage> decodePng(Uint8List bytes)` — via
    `ui.instantiateImageCodec(bytes)` → erstes Frame → `image.toByteData(format: rawRgba)`.
    Ersetzt jedes `decodeImage(...)`.
  - `Future<Uint8List> encodePng(RasterImage img)` — RasterImage → `ui.Image` →
    `toByteData(format: png)`. Nur für den myPos-Pfad nötig.

### 2. `lib/src/printing/escpos/` — vendierter ESC/POS-Generator

Aus `esc_pos_utils 1.1.0` übernommen, aber von `image.Image` auf `RasterImage` umgestellt.

- **`EscPosGenerator`** mit genau den genutzten Befehlen:
  `reset`, `text`, `row` (Spalten), `feed`, `reverseFeed`, `hr`, `cut`, `drawer`,
  `setGlobalCodeTable`, `qrcode` (nativer ESC/POS-QR), `image` (ESC * Bit-Image),
  `imageRaster` (GS v 0, nutzt `toEscPosRaster`). Bild-Methoden nehmen `RasterImage`.
- **`PosStyles`, `PosAlign`, `PosColumn`, `EscPaperSize`** — vendiert (nur das Genutzte).
- **`CapabilityProfile`** — **minimal & hartkodiert**: nur die tatsächlich genutzten
  Codepages (CP1252 + Default CP437). Die 66-KB-`capabilities.json` und ihr Asset-Laden
  entfallen komplett. `text()` kodiert Latin-1-Bereich direkt (passt zum bestehenden
  `_printable()`, das ohnehin auf Latin-1 reduziert).

## Anpassungen am bestehenden Code

- **`lib/models/print_paper.dart`**: Importe auf interne Module. `Image` → `RasterImage`,
  `decodeImage` → `await decodePng`, `encodePng` → `await encodePng`,
  `copyResize` → `resizeWidth`, `fill`+`compositeImage` → `compositeOnWhite`,
  `ColorRgb8` entfällt. Die vorhandene „auf Weiß komponieren"-Logik (QR-Ruhezone,
  Alpha-Fix) bleibt inhaltlich identisch. `generator.*` → `EscPosGenerator`.
- **`lib/services/printer_service.dart`**: `Generator`/`CapabilityProfile` → vendierte
  Typen. `CapabilityProfile.load()` (async, Asset) → synchroner Konstruktor des
  Minimalprofils.
- **`lib/enums/keck_paper_size.dart`**: Feld `paperSize` vom esc-Typ `PaperSize` →
  `EscPaperSize`.
- **`pubspec.yaml`**: `image` und `esc_pos_utils_plus` **entfernen**. Version-Bump auf
  `4.0.0`. CHANGELOG-Eintrag.

## QR-Druck — Korrektheits-Garantien (kritisch)

Der QR-Druck war historisch der fragilste Teil (Alpha→Schwarz-Bug in 2.1.2, ÷8-Crash in
3.2.0) und **muss** über die Entkopplung hinweg byte-/pixelgenau gleich bleiben. Es gibt
**drei Modi** (`QrPrintMode`), alle werden 1:1 erhalten:

| Modus | Pfad heute | Vendiert |
|---|---|---|
| `native` | `generator.qrcode(data, size: QRSize.size6)` — nativer ESC/POS-QR | exakte Befehlsbytes übernehmen |
| `imageRaster` (Default) | QrPainter→PNG→decode→auf Weiß→`generator.imageRaster` (GS v 0) | korrekter Raster-Packer |
| `imageBitImage` | …→`generator.image` (ESC *) | korrekter Column-Packer (`_toColumnFormat`) |

Garantien:

1. **Nativer QR byte-exakt.** Die ESC/POS-QR-Befehlssequenz wird verbatim aus
   `esc_pos_utils 1.1.0` übernommen: FN167 (Modulgröße `size.value`), FN169
   (Fehlerkorrektur `L`), FN180 (Datenspeicher, `latin1.encode(text)`), FN182 (Größe), FN181
   (Druck). Default `QRSize.size6`. Identisch zur aktuellen `_plus`-Ausgabe (deren *nativer*
   QR ist korrekt — nur der Bild-Rasterizer war kaputt).
2. **Alpha→Weiß bleibt.** QrPainter zeichnet schwarze Module auf **transparentem** Grund.
   `compositeOnWhite` **muss** transparente Pixel zu Weiß blenden (sonst druckt
   grayscale+invert sie als Schwarz → komplett schwarzes Quadrat, der 2.1.2-Bug). QR-Bild
   wird wie heute mit **16 px Ruhezone** auf Weiß komponiert (Scanner-Lesbarkeit).
3. **Straight (nicht-premultiplied) RGBA.** dart:ui-Decode liefert via
   `ImageByteFormat.rawStraightRgba` unmultipliziertes RGBA. Für QR (Alpha nur 0/255)
   unkritisch, für anti-aliaste Logo-Kanten aber zwingend, damit halbtransparente Pixel
   nicht zu dunkel werden.
4. **Packing identisch.** grayscale→invert→Threshold 127, Breiten-Padding auf ÷8 am
   Zeilen-Ende (korrekte 1.1.0-Logik). QR-Bild ist 280+2·16 = **312 px (÷8)**.
5. **Native-Mode unverändert** auch für myPos (`myPosPaper.addQrCode(data, size: 280)`).

QR-spezifische Tests:

- **Golden Native-QR:** `EscPosGenerator.qrcode("…feste Beleg-QR…", size: size6)` ergibt exakt
  die erwartete Bytefolge (Golden-Fixture, einmalig aus der bewährten Ausgabe eingefroren).
  Pure-Dart, host-testbar.
- **Golden Image-QR-Raster:** Für einen festen Beleg wird die heutige (für ÷8 korrekte)
  GS-v-0-Rasterausgabe als Golden eingefroren; der vendierte Rasterizer muss sie
  **byte-identisch** reproduzieren.
- **Alpha→Weiß:** synthetischer RGBA-Puffer mit (a) schwarzen Pixeln Alpha 0 und (b)
  schwarzen Pixeln Alpha 255 → `compositeOnWhite` → `toEscPosRaster`: Alpha-0-Bereich ergibt
  **keine** Druckpunkte, Alpha-255-Bereich ergibt Punkte. Sichert den 2.1.2-Fix ab.
  Pure-Dart.
- **Kein-Schwarz-Quadrat:** Gesamt-QR-Raster ist nicht durchgehend gesetzt (Gegenprobe zum
  Alpha-Bug).

## Async / Tests

- Raster-Mathematik (resize/composite/grayscale/threshold/**packing**) bleibt **synchron
  und pure-Dart** → voll host-testbar.
- **Neuer Regressions-Test**: `toEscPosRaster` für eine Breite, die *nicht* durch 8 teilbar
  ist, liefert korrekte Datenlänge (`((w+7)~/8) * h` Bytes) und stürzt nicht ab — sichert
  genau den alten `_plus`-Bug ab.
- PNG decode/encode ist async (dart:ui). Betroffene Aufrufer sind bereits `async`
  (`setKeckReceipt`, `addQrCodeAsImage`, `_addKreiseckBranding`); `addBase64Image` und
  `addImageFromBytes` werden `async` (interne Aufrufstellen anpassen).
- Konsistenz-Test (Print↔Widget) läuft weiter über `QrPrintMode.native` (kein Decode).
  Tests mit echtem Decode (`logo_service_test`, `print_rendering_test`,
  `kreiseck_branding_test`, `models_misc_test`) nutzen `tester.runAsync` und
  `TestWidgetsFlutterBinding`.
- Akzeptanz: `flutter analyze` = 0 Issues; `flutter test` grün (inkl. der vom Decode
  betroffenen Tests).

## Breaking Changes (→ 4.0.0)

- `KeckPaperSize.paperSize` ändert den Typ von esc `PaperSize` auf internes `EscPaperSize`.
- Alle übrigen öffentlichen APIs (`getPrintBytes`, `printReceiptBluetooth/Wifi/MyPos`,
  `QrPrintMode`, `KeckPaperSize`, `openCashDrawer`) bleiben signaturgleich.

## Nicht im Scope (YAGNI)

- Kein vollständiger Nachbau von `image` oder `esc_pos_utils` — nur die genutzten Teile.
- Kein eigener PNG-Codec (dart:ui übernimmt das).
- Keine neuen Druckfeatures, kein Umbau des Bluetooth-/WLAN-Transports.
- Kein Web-Support-Ziel (Druck ist Android; dart:ui-Decode genügt).
