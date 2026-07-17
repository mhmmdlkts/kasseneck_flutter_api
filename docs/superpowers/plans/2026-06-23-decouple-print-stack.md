# Druck-Stack entkoppeln (kein `image`, kein `esc_pos_utils`) — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kasseneck_api` druckt Belege (Text, Tabellen, QR, Logo) ohne Abhängigkeit von `image` oder `esc_pos_utils_plus`, sodass das Hauptprojekt frei in seiner `image`-Version ist — und der Rasterizer-Bug (Crash bei Breite ≠ Vielfaches von 8) ist beseitigt.

**Architecture:** Wir vendoren den korrekten ESC/POS-Generator aus `esc_pos_utils 1.1.0` nach `lib/src/printing/escpos/`, umgestellt von `image.Image` auf eine eigene `RasterImage` (RGBA-Puffer). Bild-Primitive (resize/composite/grayscale/threshold/packing) schreiben wir selbst als pure-Dart-Funktionen; PNG decode/encode läuft über Flutters `dart:ui`. `print_paper.dart`/`printer_service.dart`/`keck_paper_size.dart` werden auf die internen Module umgestellt; `image` und `esc_pos_utils_plus` fliegen aus `pubspec.yaml`.

**Tech Stack:** Dart/Flutter, `dart:ui` (PNG-Codec), `dart:typed_data`, `dart:convert`. Beibehaltene Pakete: `my_pos`, `qr_flutter`, `flutter_blue_plus`, `path_provider`, `http`.

## Global Constraints

- **Keine Abhängigkeit** auf `image` oder `esc_pos_utils*` in `pubspec.yaml` (Endzustand).
- **Keine neuen pub-Abhängigkeiten** (kein `hex`, kein `gbk_codec`, kein `archive`).
- `flutter analyze` = **0 Issues**; `flutter test` grün.
- Öffentliche API bleibt signaturgleich außer `KeckPaperSize.paperSize` (Typ → `EscPaperSize`). Version-Bump auf **4.0.0**.
- **Keine** Hinweise auf KI/Generatoren in Code, Kommentaren, Commits.
- Chinesisch/Kanji-Pfade und Barcodes werden **nicht** vendiert (ungenutzt → YAGNI).
- QR-Korrektheit ist kritisch: native QR byte-exakt; Bild-QR auf Weiß komponiert (Alpha→Weiß); Threshold 127; Breite des Bild-QR bleibt 312 px.
- Vendier-Quelle (auf dieser Maschine vorhanden): `~/.pub-cache/hosted/pub.dev/esc_pos_utils-1.1.0/lib/src/`.

---

## Dateistruktur (neu)

```
lib/src/printing/
  raster/
    raster_image.dart     # RasterImage (RGBA) + geometrische/Farb-Ops (pure Dart)
    raster_ops.dart       # toEscPosRaster (GS v 0), toColumnFormat (ESC *), compositeOnWhite, luma
    raster_codec.dart     # dart:ui: decodePng / encodePng (async)
  escpos/
    commands.dart         # ESC/POS-Byte-Konstanten (verbatim aus 1.1.0)
    enums.dart            # PosAlign, PosCutMode, PosFontType, PosDrawer, PosImageFn, PosTextSize, EscPaperSize
    pos_styles.dart       # PosStyles (verbatim)
    pos_column.dart       # PosColumn (verbatim)
    qrcode.dart           # QRSize/QRCorrection/QRCode (verbatim, kleingeschriebene size-Namen)
    capability_profile.dart # CapabilityProfile minimal {0:CP437, 16:CP1252}
    generator.dart        # EscPosGenerator auf RasterImage
    escpos.dart           # Barrel: exportiert alle escpos-Teile + raster
```

Geändert: `lib/enums/keck_paper_size.dart`, `lib/models/print_paper.dart`, `lib/services/printer_service.dart`, `pubspec.yaml`, `CHANGELOG.md`, betroffene Tests.

---

## Task 1: RasterImage + geometrische/Farb-Ops

**Files:**
- Create: `lib/src/printing/raster/raster_image.dart`
- Test: `test/printing/raster_image_test.dart`

**Interfaces:**
- Produces: `class RasterImage { final int width; final int height; final Uint8List rgba; RasterImage(this.width, this.height, this.rgba); factory RasterImage.filled(int w, int h, int r,int g,int b,int a); RasterImage clone(); void invertRgb(); RasterImage flipHorizontal(); RasterImage rotate270(); int pixel(int x,int y) }` — `rgba` ist Länge `width*height*4`, Reihenfolge R,G,B,A pro Pixel.

- [ ] **Step 1: Failing-Test schreiben**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

void main() {
  test('filled setzt alle Pixel', () {
    final img = RasterImage.filled(2, 1, 255, 0, 0, 255);
    expect(img.width, 2);
    expect(img.height, 1);
    expect(img.rgba, Uint8List.fromList([255,0,0,255, 255,0,0,255]));
  });

  test('invertRgb invertiert RGB, Alpha bleibt', () {
    final img = RasterImage.filled(1, 1, 10, 20, 30, 128);
    img.invertRgb();
    expect(img.rgba, Uint8List.fromList([245, 235, 225, 128]));
  });

  test('flipHorizontal spiegelt Spalten', () {
    // 2x1: links rot, rechts gruen
    final img = RasterImage(2, 1, Uint8List.fromList([255,0,0,255, 0,255,0,255]));
    final f = img.flipHorizontal();
    expect(f.rgba, Uint8List.fromList([0,255,0,255, 255,0,0,255]));
  });

  test('rotate270 dreht 2x1 zu 1x2', () {
    final img = RasterImage(2, 1, Uint8List.fromList([1,1,1,255, 2,2,2,255]));
    final r = img.rotate270();
    expect(r.width, 1);
    expect(r.height, 2);
  });
}
```

- [ ] **Step 2: Test laufen lassen, FAIL bestätigen**

Run: `flutter test test/printing/raster_image_test.dart`
Expected: FAIL ("Target of URI doesn't exist" / RasterImage undefined).

- [ ] **Step 3: Implementierung schreiben**

```dart
import 'dart:typed_data';

/// Einfaches RGBA-Bild (4 Bytes/Pixel: R,G,B,A) als Ersatz fuer image.Image.
/// Bewusst minimal — nur was der Druckpfad braucht.
class RasterImage {
  final int width;
  final int height;
  final Uint8List rgba;

  RasterImage(this.width, this.height, this.rgba)
      : assert(rgba.length == width * height * 4);

  factory RasterImage.filled(int w, int h, int r, int g, int b, int a) {
    final buf = Uint8List(w * h * 4);
    for (int i = 0; i < buf.length; i += 4) {
      buf[i] = r;
      buf[i + 1] = g;
      buf[i + 2] = b;
      buf[i + 3] = a;
    }
    return RasterImage(w, h, buf);
  }

  RasterImage clone() => RasterImage(width, height, Uint8List.fromList(rgba));

  /// RGB invertieren (255 - v), Alpha unveraendert.
  void invertRgb() {
    for (int i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255 - rgba[i];
      rgba[i + 1] = 255 - rgba[i + 1];
      rgba[i + 2] = 255 - rgba[i + 2];
    }
  }

  RasterImage flipHorizontal() {
    final out = Uint8List(rgba.length);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final src = (y * width + x) * 4;
        final dst = (y * width + (width - 1 - x)) * 4;
        out[dst] = rgba[src];
        out[dst + 1] = rgba[src + 1];
        out[dst + 2] = rgba[src + 2];
        out[dst + 3] = rgba[src + 3];
      }
    }
    return RasterImage(width, height, out);
  }

  /// 270 Grad im Uhrzeigersinn (entspricht copyRotate(img, 270) aus image 3.x).
  RasterImage rotate270() {
    final out = Uint8List(rgba.length);
    final int nw = height, nh = width;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final src = (y * width + x) * 4;
        // 270 cw: (x,y) -> (y, width-1-x)
        final int dx = y;
        final int dy = width - 1 - x;
        final dst = (dy * nw + dx) * 4;
        out[dst] = rgba[src];
        out[dst + 1] = rgba[src + 1];
        out[dst + 2] = rgba[src + 2];
        out[dst + 3] = rgba[src + 3];
      }
    }
    return RasterImage(nw, nh, out);
  }
}
```

- [ ] **Step 4: Test laufen lassen, PASS bestätigen**

Run: `flutter test test/printing/raster_image_test.dart`
Expected: PASS (4 Tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/printing/raster/raster_image.dart test/printing/raster_image_test.dart
git commit -m "feat(print): RasterImage RGBA-Primitive"
```

---

## Task 2: Raster-Ops — Resize, Composite-auf-Weiss, GS-v-0 + ESC-*-Packing

**Files:**
- Create: `lib/src/printing/raster/raster_ops.dart`
- Test: `test/printing/raster_ops_test.dart`

**Interfaces:**
- Consumes: `RasterImage` (Task 1).
- Produces:
  - `int luma(int r, int g, int b)` → Rec.601-Luminanz, gerundet.
  - `RasterImage resizeWidth(RasterImage src, int targetWidth)` — Breite skalieren, Höhe proportional (nearest).
  - `RasterImage resizeTo(RasterImage src, int w, int h)` — auf exakte Maße (nearest).
  - `RasterImage compositeOnWhite(RasterImage fg, {int canvasWidth, int canvasHeight, int dstX = 0, int dstY = 0})` — fg per straight-alpha auf weißen Hintergrund blenden; Default-Canvas = fg-Maße.
  - `List<int> toEscPosRaster(RasterImage img)` — GS-v-0-Rohdaten (`((w+7)~/8)*h` Bytes), Punkt wenn Luminanz < 128 (ignoriert Alpha).
  - `List<List<int>> toColumnFormat(RasterImage img, int lineHeight)` — ESC-*-Spalten-Blobs (Breite auf Vielfaches von `lineHeight` mit Schwarz aufgefüllt, Luminanz je Pixel).

- [ ] **Step 1: Failing-Test schreiben**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';
import 'package:kasseneck_api/src/printing/raster/raster_ops.dart';

void main() {
  test('toEscPosRaster: Laenge = ((w+7)~/8)*h, auch bei Breite NICHT durch 8', () {
    // 10x4 -> widthBytes = 2 -> 8 Bytes. Frueherer esc_pos_utils_plus-Bug: Crash.
    final img = RasterImage.filled(10, 4, 0, 0, 0, 255); // schwarz
    final data = toEscPosRaster(img);
    expect(data.length, 8);
  });

  test('toEscPosRaster: schwarz -> Punkte gesetzt, weiss -> keine', () {
    final black = RasterImage.filled(8, 1, 0, 0, 0, 255);
    final white = RasterImage.filled(8, 1, 255, 255, 255, 255);
    expect(toEscPosRaster(black), [0xFF]);
    expect(toEscPosRaster(white), [0x00]);
  });

  test('toEscPosRaster: linkes Pixel ist MSB', () {
    // 8 Pixel: nur erstes schwarz -> 0x80
    final buf = RasterImage.filled(8, 1, 255, 255, 255, 255);
    buf.rgba[0] = 0; buf.rgba[1] = 0; buf.rgba[2] = 0; // Pixel 0 schwarz
    expect(toEscPosRaster(buf), [0x80]);
  });

  test('compositeOnWhite: transparentes Schwarz wird Weiss (Alpha->Weiss-Fix)', () {
    final fg = RasterImage.filled(1, 1, 0, 0, 0, 0); // schwarz, voll transparent
    final out = compositeOnWhite(fg);
    expect(out.rgba, [255, 255, 255, 255]);
  });

  test('compositeOnWhite: opakes Schwarz bleibt Schwarz', () {
    final fg = RasterImage.filled(1, 1, 0, 0, 0, 255);
    final out = compositeOnWhite(fg);
    expect(out.rgba, [0, 0, 0, 255]);
  });

  test('compositeOnWhite + toEscPosRaster: transparenter QR-Pixel druckt NICHT', () {
    final fg = RasterImage.filled(8, 1, 0, 0, 0, 0); // transparent schwarz
    final flat = compositeOnWhite(fg);
    expect(toEscPosRaster(flat), [0x00]); // kein schwarzes Quadrat
  });

  test('resizeWidth: skaliert Breite, Hoehe proportional', () {
    final src = RasterImage.filled(10, 5, 0, 0, 0, 255);
    final out = resizeWidth(src, 20);
    expect(out.width, 20);
    expect(out.height, 10);
  });

  test('toColumnFormat: Breite auf Vielfaches von lineHeight', () {
    final img = RasterImage.filled(10, 8, 0, 0, 0, 255);
    final blobs = toColumnFormat(img, 8); // gepadded auf 16 -> 2 Slices
    expect(blobs.length, 2);
    expect(blobs[0].length, 8 * 8); // lineHeight*height Luminanzbytes
  });
}
```

- [ ] **Step 2: Test laufen lassen, FAIL bestätigen**

Run: `flutter test test/printing/raster_ops_test.dart`
Expected: FAIL (Funktionen undefiniert).

- [ ] **Step 3: Implementierung schreiben**

```dart
import 'dart:typed_data';
import 'raster_image.dart';

/// Rec.601-Luminanz (entspricht grayscale aus image 3.x), gerundet 0..255.
int luma(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();

/// Komponiert [fg] per straight-alpha auf weissen Hintergrund.
/// Transparente Pixel werden weiss (verhindert das "schwarze Quadrat" beim
/// alpha-ignorierenden ESC/POS-Rasterizer). Ergebnis ist voll opak.
RasterImage compositeOnWhite(RasterImage fg,
    {int? canvasWidth, int? canvasHeight, int dstX = 0, int dstY = 0}) {
  final int w = canvasWidth ?? fg.width;
  final int h = canvasHeight ?? fg.height;
  final out = Uint8List(w * h * 4);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = 255;
    out[i + 1] = 255;
    out[i + 2] = 255;
    out[i + 3] = 255;
  }
  for (int y = 0; y < fg.height; y++) {
    final int oy = y + dstY;
    if (oy < 0 || oy >= h) continue;
    for (int x = 0; x < fg.width; x++) {
      final int ox = x + dstX;
      if (ox < 0 || ox >= w) continue;
      final s = (y * fg.width + x) * 4;
      final int a = fg.rgba[s + 3];
      if (a == 0) continue; // bleibt weiss
      final d = (oy * w + ox) * 4;
      // over white: out = src*a + 255*(255-a), /255
      out[d] = (fg.rgba[s] * a + 255 * (255 - a)) ~/ 255;
      out[d + 1] = (fg.rgba[s + 1] * a + 255 * (255 - a)) ~/ 255;
      out[d + 2] = (fg.rgba[s + 2] * a + 255 * (255 - a)) ~/ 255;
      out[d + 3] = 255;
    }
  }
  return RasterImage(w, h, out);
}

RasterImage resizeTo(RasterImage src, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    final int sy = (y * src.height ~/ h).clamp(0, src.height - 1);
    for (int x = 0; x < w; x++) {
      final int sx = (x * src.width ~/ w).clamp(0, src.width - 1);
      final s = (sy * src.width + sx) * 4;
      final d = (y * w + x) * 4;
      out[d] = src.rgba[s];
      out[d + 1] = src.rgba[s + 1];
      out[d + 2] = src.rgba[s + 2];
      out[d + 3] = src.rgba[s + 3];
    }
  }
  return RasterImage(w, h, out);
}

RasterImage resizeWidth(RasterImage src, int targetWidth) {
  final int targetHeight = (src.height * targetWidth / src.width).round();
  return resizeTo(src, targetWidth, targetHeight);
}

/// GS v 0 Rohdaten: ein Bit pro Pixel, 8 Pixel/Byte, linkes Pixel = MSB.
/// Punkt gesetzt, wenn Luminanz < 128 (grayscale -> invert -> Threshold 127).
/// Alpha wird ignoriert (wie der ESC/POS-Generator) — daher VORHER auf Weiss
/// komponieren. Breite wird implizit auf Vielfaches von 8 gepadded (Padding-Bits
/// = 0 = kein Punkt). Korrekt fuer JEDE Breite (kein Crash, anders als
/// esc_pos_utils_plus 2.0.4).
List<int> toEscPosRaster(RasterImage img) {
  final int w = img.width, h = img.height;
  final int widthBytes = (w + 7) >> 3;
  final out = Uint8List(widthBytes * h);
  final rgba = img.rgba;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = (y * w + x) * 4;
      if (luma(rgba[p], rgba[p + 1], rgba[p + 2]) < 128) {
        out[y * widthBytes + (x >> 3)] |= (0x80 >> (x & 7));
      }
    }
  }
  return out;
}

/// ESC * Spalten-Format: Breite auf Vielfaches von [lineHeight] mit Schwarz
/// aufgefuellt, dann je [lineHeight] breiter Slice die Luminanz jedes Pixels.
/// Entspricht _toColumnFormat aus esc_pos_utils 1.1.0.
List<List<int>> toColumnFormat(RasterImage img, int lineHeight) {
  final int widthPx = (img.width + lineHeight) - (img.width % lineHeight);
  final int heightPx = img.height;
  // Schwarzer Canvas, Originalbild oben-links eingesetzt.
  final canvas = Uint8List(widthPx * heightPx * 4); // alles 0 -> schwarz, Alpha 0
  for (int i = 3; i < canvas.length; i += 4) {
    canvas[i] = 255; // opak schwarz
  }
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final s = (y * img.width + x) * 4;
      final d = (y * widthPx + x) * 4;
      canvas[d] = img.rgba[s];
      canvas[d + 1] = img.rgba[s + 1];
      canvas[d + 2] = img.rgba[s + 2];
      canvas[d + 3] = img.rgba[s + 3];
    }
  }
  final List<List<int>> blobs = [];
  int left = 0;
  while (left < widthPx) {
    final blob = <int>[];
    for (int x = left; x < left + lineHeight; x++) {
      for (int y = 0; y < heightPx; y++) {
        final p = (y * widthPx + x) * 4;
        blob.add(luma(canvas[p], canvas[p + 1], canvas[p + 2]));
      }
    }
    blobs.add(blob);
    left += lineHeight;
  }
  return blobs;
}
```

- [ ] **Step 4: Test laufen lassen, PASS bestätigen**

Run: `flutter test test/printing/raster_ops_test.dart`
Expected: PASS (alle Tests, inkl. Nicht-÷8-Regression + Alpha→Weiß).

- [ ] **Step 5: Commit**

```bash
git add lib/src/printing/raster/raster_ops.dart test/printing/raster_ops_test.dart
git commit -m "feat(print): Raster-Ops (GS v 0 + ESC * Packing, Alpha-auf-Weiss); fixt Nicht-/8-Crash"
```

---

## Task 3: PNG-Codec über dart:ui

**Files:**
- Create: `lib/src/printing/raster/raster_codec.dart`
- Test: `test/printing/raster_codec_test.dart`

**Interfaces:**
- Consumes: `RasterImage` (Task 1), `compositeOnWhite`/`toEscPosRaster` (Task 2) im Test.
- Produces:
  - `Future<RasterImage> decodePng(Uint8List bytes)` — via `ui.instantiateImageCodec`, liefert **straight** (nicht-premultiplied) RGBA.
  - `Future<Uint8List> encodePng(RasterImage img)` — via `ui.ImageDescriptor`/`toByteData(format: png)`.

- [ ] **Step 1: Failing-Test schreiben**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';
import 'package:kasseneck_api/src/printing/raster/raster_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encode->decode Roundtrip erhaelt Maße + opake Farbe', () async {
    final src = RasterImage.filled(4, 3, 12, 34, 56, 255);
    final png = await encodePng(src);
    final back = await decodePng(png);
    expect(back.width, 4);
    expect(back.height, 3);
    // erstes Pixel ~ Ausgangsfarbe (PNG verlustfrei)
    expect(back.rgba.sublist(0, 4), [12, 34, 56, 255]);
  });

  test('decode liefert straight Alpha (transparent schwarz bleibt 0-Alpha)', () async {
    final src = RasterImage.filled(2, 2, 0, 0, 0, 0);
    final png = await encodePng(src);
    final back = await decodePng(png);
    expect(back.rgba[3], 0); // Alpha 0
  });
}
```

(Import von `RasterImage` kommt transitiv über `raster_ops.dart`; falls Analyzer meckert, zusätzlich `raster_image.dart` importieren.)

- [ ] **Step 2: Test laufen lassen, FAIL bestätigen**

Run: `flutter test test/printing/raster_codec_test.dart`
Expected: FAIL (Funktionen undefiniert).

- [ ] **Step 3: Implementierung schreiben**

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'raster_image.dart';

/// PNG -> RasterImage. Nutzt Flutters eingebauten Codec (keine image-Lib).
/// Liefert STRAIGHT (nicht-premultiplied) RGBA, damit halbtransparente Kanten
/// (Logos) nicht zu dunkel werden.
Future<RasterImage> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? bd =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final int w = image.width;
  final int h = image.height;
  image.dispose();
  codec.dispose();
  if (bd == null) {
    throw StateError('PNG-Decode lieferte keine Bytes');
  }
  return RasterImage(w, h, bd.buffer.asUint8List().sublist(0, w * h * 4));
}

/// RasterImage -> PNG-Bytes (fuer den myPos-Druckpfad).
Future<Uint8List> encodePng(RasterImage img) async {
  final descriptor = ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(img.rgba),
    width: img.width,
    height: img.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final ByteData? bd =
      await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  if (bd == null) {
    throw StateError('PNG-Encode lieferte keine Bytes');
  }
  return bd.buffer.asUint8List();
}
```

- [ ] **Step 4: Test laufen lassen, PASS bestätigen**

Run: `flutter test test/printing/raster_codec_test.dart`
Expected: PASS. Falls der Roundtrip-Farbtest unter dem Headless-Engine flackert, Test mit `tester.runAsync` in einem `testWidgets` kapseln (Engine-Codec braucht echten Async-Tick).

- [ ] **Step 5: Commit**

```bash
git add lib/src/printing/raster/raster_codec.dart test/printing/raster_codec_test.dart
git commit -m "feat(print): PNG decode/encode ueber dart:ui (ohne image-Lib)"
```

---

## Task 4: Pure-Byte ESC/POS-Teile vendieren (commands, enums, pos_styles, pos_column, qrcode)

**Files:**
- Create: `lib/src/printing/escpos/commands.dart`
- Create: `lib/src/printing/escpos/enums.dart`
- Create: `lib/src/printing/escpos/pos_styles.dart`
- Create: `lib/src/printing/escpos/pos_column.dart`
- Create: `lib/src/printing/escpos/qrcode.dart`
- Test: `test/printing/escpos_qrcode_test.dart`

**Interfaces:**
- Produces: `PosAlign`, `PosCutMode`, `PosFontType`, `PosDrawer`, `PosImageFn`, `PosTextSize`, `EscPaperSize` (`.value`, `.width`: mm58→372, mm80→558), `PosStyles` (+`copyWith`), `PosColumn`, `QRSize` (`size1..size8`), `QRCorrection` (`L/M/Q/H`), `QRCode(text,size,level).bytes`.

- [ ] **Step 1: `commands.dart` — verbatim kopieren**

Inhalt 1:1 aus `~/.pub-cache/hosted/pub.dev/esc_pos_utils-1.1.0/lib/src/commands.dart` übernehmen (nur die ESC/POS-Konstanten `esc,gs,fs,cInit,...,cQrHeader`). Lizenz-/Autor-Header oben **entfernen** (kein Fremd-Footprint), keine sonstigen Änderungen.

- [ ] **Step 2: `enums.dart` schreiben**

Aus `esc_pos_utils-1.1.0/lib/src/enums.dart` übernehmen, mit dieser Änderung: Klasse `PaperSize` → **`EscPaperSize`** umbenennen (Felder/Logik identisch):

```dart
enum PosAlign { left, center, right }
enum PosCutMode { full, partial }
enum PosFontType { fontA, fontB }
enum PosDrawer { pin2, pin5 }

/// bitImageRaster: GS v 0 (obsolete); graphics: GS ( L
enum PosImageFn { bitImageRaster, graphics }

class PosTextSize {
  const PosTextSize._internal(this.value);
  final int value;
  static const size1 = PosTextSize._internal(1);
  static const size2 = PosTextSize._internal(2);
  static const size3 = PosTextSize._internal(3);
  static const size4 = PosTextSize._internal(4);
  static const size5 = PosTextSize._internal(5);
  static const size6 = PosTextSize._internal(6);
  static const size7 = PosTextSize._internal(7);
  static const size8 = PosTextSize._internal(8);

  static int decSize(PosTextSize height, PosTextSize width) =>
      16 * (width.value - 1) + (height.value - 1);
}

class EscPaperSize {
  const EscPaperSize._internal(this.value);
  final int value;
  static const mm58 = EscPaperSize._internal(1);
  static const mm80 = EscPaperSize._internal(2);

  int get width => value == EscPaperSize.mm58.value ? 372 : 558;
}
```

(`PosBeepDuration` weglassen — beep wird nicht vendiert.)

- [ ] **Step 3: `pos_styles.dart` + `pos_column.dart` verbatim kopieren**

Beide 1:1 aus 1.1.0 übernehmen, Autoren-Header entfernen, Importpfade auf relativ anpassen:
- `pos_styles.dart`: `import 'enums.dart';` bleibt.
- `pos_column.dart`: `import 'pos_styles.dart';` bleibt; `import 'dart:typed_data' show Uint8List;` bleibt. Veraltete `:`-Default-Syntax in `PosStyles.defaults` (z. B. `this.bold: false`) auf `=`-Syntax umstellen (`this.bold = false`), damit der aktuelle Analyzer 0 Issues meldet.

- [ ] **Step 4: `qrcode.dart` schreiben** (size-Namen klein, Import lokal)

```dart
import 'dart:convert';
import 'commands.dart';

class QRSize {
  const QRSize(this.value);
  final int value;
  static const size1 = QRSize(0x01);
  static const size2 = QRSize(0x02);
  static const size3 = QRSize(0x03);
  static const size4 = QRSize(0x04);
  static const size5 = QRSize(0x05);
  static const size6 = QRSize(0x06);
  static const size7 = QRSize(0x07);
  static const size8 = QRSize(0x08);
}

class QRCorrection {
  const QRCorrection._internal(this.value);
  final int value;
  static const L = QRCorrection._internal(48);
  static const M = QRCorrection._internal(49);
  static const Q = QRCorrection._internal(50);
  static const H = QRCorrection._internal(51);
}

class QRCode {
  List<int> bytes = <int>[];
  QRCode(String text, QRSize size, QRCorrection level) {
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x43] + [size.value];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x45] + [level.value];
    List<int> textBytes = latin1.encode(text);
    bytes +=
        cQrHeader.codeUnits + [textBytes.length + 3, 0x00, 0x31, 0x50, 0x30];
    bytes += textBytes;
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x52, 0x30];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x51, 0x30];
  }
}
```

- [ ] **Step 5: Golden-Test für nativen QR schreiben**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/qrcode.dart';

void main() {
  test('QRCode nativer Befehl ist byte-exakt (FN167/169/180/182/181)', () {
    final qr = QRCode('ABC', QRSize.size6, QRCorrection.L);
    final h = '\x1D(k'.codeUnits; // cQrHeader
    final expected = <int>[
      ...h, 0x03, 0x00, 0x31, 0x43, 0x06, // Modulgroesse 6
      ...h, 0x03, 0x00, 0x31, 0x45, 48,   // Korrektur L
      ...h, 3 + 3, 0x00, 0x31, 0x50, 0x30, ...latin1.encode('ABC'), // store
      ...h, 0x03, 0x00, 0x31, 0x52, 0x30, // Groesse
      ...h, 0x03, 0x00, 0x31, 0x51, 0x30, // Druck
    ];
    expect(qr.bytes, expected);
  });
}
```

- [ ] **Step 6: Tests laufen lassen + PASS**

Run: `flutter test test/printing/escpos_qrcode_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/printing/escpos/ test/printing/escpos_qrcode_test.dart
git commit -m "feat(print): ESC/POS Konstanten/Enums/Styles/QR vendiert (pure bytes)"
```

---

## Task 5: Minimale CapabilityProfile

**Files:**
- Create: `lib/src/printing/escpos/capability_profile.dart`
- Test: `test/printing/capability_profile_test.dart`

**Interfaces:**
- Produces: `class CapabilityProfile { CapabilityProfile(); int getCodePageId(String? codePage) }` — synchroner Konstruktor (kein Asset). Nur CP437→0, CP1252→16; unbekannt → 0 (Fallback Default-Tabelle).

- [ ] **Step 1: Failing-Test schreiben**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/capability_profile.dart';

void main() {
  test('getCodePageId kennt CP1252 und CP437', () {
    final p = CapabilityProfile();
    expect(p.getCodePageId('CP437'), 0);
    expect(p.getCodePageId('CP1252'), 16);
  });

  test('unbekannte Codepage faellt auf 0 zurueck', () {
    expect(CapabilityProfile().getCodePageId('CP999'), 0);
  });
}
```

- [ ] **Step 2: FAIL bestätigen**

Run: `flutter test test/printing/capability_profile_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementierung**

```dart
/// Minimales Ersatz-Profil fuer den ESC/POS-Generator. Statt der 66-KB-
/// capabilities.json nur die tatsaechlich genutzten Codepages.
class CapabilityProfile {
  CapabilityProfile();

  static const Map<String, int> _codePages = {
    'CP437': 0,
    'CP1252': 16,
  };

  int getCodePageId(String? codePage) => _codePages[codePage] ?? 0;
}
```

- [ ] **Step 4: PASS bestätigen**

Run: `flutter test test/printing/capability_profile_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/printing/escpos/capability_profile.dart test/printing/capability_profile_test.dart
git commit -m "feat(print): minimale CapabilityProfile (CP437/CP1252, kein Asset)"
```

---

## Task 6: EscPosGenerator (auf RasterImage)

**Files:**
- Create: `lib/src/printing/escpos/generator.dart`
- Test: `test/printing/escpos_generator_test.dart`

**Interfaces:**
- Consumes: `EscPaperSize`, `CapabilityProfile`, `PosStyles`, `PosColumn`, `PosAlign`, `PosCutMode`, `PosDrawer`, `PosImageFn`, `QRSize`, `QRCorrection`, `QRCode`, `RasterImage`, `toEscPosRaster`, `toColumnFormat`.
- Produces: `class EscPosGenerator { EscPosGenerator(EscPaperSize, CapabilityProfile, {int spaceBetweenRows=5}); List<int> reset(); List<int> setGlobalCodeTable(String?); List<int> setStyles(PosStyles); List<int> text(String, {PosStyles styles, int linesAfter}); List<int> emptyLines(int); List<int> feed(int); List<int> reverseFeed(int); List<int> cut({PosCutMode mode}); List<int> hr({String ch, int? len, int linesAfter}); List<int> row(List<PosColumn>); List<int> drawer({PosDrawer pin}); List<int> qrcode(String, {PosAlign align, QRSize size, QRCorrection cor}); List<int> image(RasterImage, {PosAlign align}); List<int> imageRaster(RasterImage, {PosAlign align, bool highDensityHorizontal, bool highDensityVertical, PosImageFn imageFn}) }`

- [ ] **Step 1: Generator aus 1.1.0 übernehmen + adaptieren**

Quelle: `esc_pos_utils-1.1.0/lib/src/generator.dart`. Übernimm die Klasse als `EscPosGenerator` mit folgenden **exakten** Änderungen:

1. **Imports** ersetzen durch:
```dart
import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import '../raster/raster_image.dart';
import '../raster/raster_ops.dart';
import 'enums.dart';
import 'commands.dart';
import 'pos_styles.dart';
import 'pos_column.dart';
import 'qrcode.dart';
import 'capability_profile.dart';
```
(Entfällt: `package:hex`, `package:image`, `package:gbk_codec`, `package:esc_pos_utils/...`.)

2. **Klassenname + Typen:** `class Generator` → `class EscPosGenerator`; Konstruktorname mitziehen; `PaperSize` → `EscPaperSize` (Feld `_paperSize`, `_getMaxCharsPerLine`, `_colIndToPosition`, `_getCharWidth`).

3. **Kanji/Chinese entfernen** (ungenutzt): Methoden `_getLexemes`, `_isChinese`, `_mixedKanji` löschen; in `_encode` den `isKanji`-Zweig (`gbk_bytes`) entfernen; `text(...)` vereinfachen auf den Nicht-Chinese-Pfad; in `row(...)` den `containsChinese`-Zweig (CASE mit `_getLexemes`) löschen und nur den `_encode`-Pfad behalten; `_encode` ohne `isKanji`-Parameter.

4. **HEX entfernen:** In `_text` die Positionsbytes ohne `package:hex` erzeugen:
```dart
final int pos = fromPos.round();
bytes += Uint8List.fromList(
  List.from(cPos.codeUnits)..addAll([pos & 0xFF, (pos >> 8) & 0xFF]),
);
```
(Ersetzt `hexStr`/`HEX.decode`/`[hexPair[1], hexPair[0]]` — gleiche Low/High-Byte-Reihenfolge.)

5. **`_encode` vereinfachen:**
```dart
Uint8List _encode(String text) {
  text = text
      .replaceAll('’', "'")
      .replaceAll('´', "'")
      .replaceAll('»', '"')
      .replaceAll('•', '.');
  return latin1.encode(text);
}
```
(Alle `_encode(x, isKanji: ...)`-Aufrufstellen auf `_encode(x)` reduzieren.)

6. **Bild-Methoden auf RasterImage** (die 4 image-Methoden ersetzen):

```dart
List<int> image(RasterImage imgSrc, {PosAlign align = PosAlign.center}) {
  List<int> bytes = [];
  bytes += setStyles(const PosStyles().copyWith(align: align));

  final RasterImage img = imgSrc.clone();
  img.invertRgb();
  final RasterImage flipped = img.flipHorizontal();
  final RasterImage rotated = flipped.rotate270();

  const int lineHeight = 3; // highDensityVertical
  final List<List<int>> blobs = toColumnFormat(rotated, lineHeight * 8);
  for (int i = 0; i < blobs.length; i++) {
    blobs[i] = _packBitsIntoBytes(blobs[i]);
  }

  final int heightPx = rotated.height;
  const int densityByte = 1 + 32; // highDensityHorizontal + highDensityVertical
  final List<int> header = List.from(cBitImg.codeUnits);
  header.add(densityByte);
  header.addAll(_intLowHigh(heightPx, 2));

  bytes += [27, 51, 16];
  for (int i = 0; i < blobs.length; ++i) {
    bytes += List.from(header)
      ..addAll(blobs[i])
      ..addAll('\n'.codeUnits);
  }
  bytes += [27, 50];
  return bytes;
}

List<int> imageRaster(
  RasterImage image, {
  PosAlign align = PosAlign.center,
  bool highDensityHorizontal = true,
  bool highDensityVertical = true,
  PosImageFn imageFn = PosImageFn.bitImageRaster,
}) {
  List<int> bytes = [];
  bytes += setStyles(const PosStyles().copyWith(align: align));

  final int widthPx = image.width;
  final int heightPx = image.height;
  final int widthBytes = (widthPx + 7) ~/ 8;
  final List<int> rasterizedData = toEscPosRaster(image);

  if (imageFn == PosImageFn.bitImageRaster) {
    final int densityByte =
        (highDensityVertical ? 0 : 1) + (highDensityHorizontal ? 0 : 2);
    final List<int> header = List.from(cRasterImg2.codeUnits);
    header.add(densityByte);
    header.addAll(_intLowHigh(widthBytes, 2));
    header.addAll(_intLowHigh(heightPx, 2));
    bytes += List.from(header)..addAll(rasterizedData);
  } else {
    final List<int> header1 = List.from(cRasterImg.codeUnits);
    header1.addAll(_intLowHigh(widthBytes * heightPx + 10, 2));
    header1.addAll([48, 112, 48]);
    header1.addAll([1, 1]);
    header1.addAll([49]);
    header1.addAll(_intLowHigh(widthBytes, 2));
    header1.addAll(_intLowHigh(heightPx, 2));
    bytes += List.from(header1)..addAll(rasterizedData);
    final List<int> header2 = List.from(cRasterImg.codeUnits);
    header2.addAll([2, 0]);
    header2.addAll([48, 50]);
    bytes += List.from(header2);
  }
  return bytes;
}
```
Behalte `_packBitsIntoBytes`/`_transformUint32Bool`/`_intLowHigh` aus 1.1.0 (für die ESC-*-Blobs). Lösche `_toColumnFormat`/`_toRasterFormat` aus dem Generator (jetzt in `raster_ops.dart`), ebenso `barcode(...)`, `beep(...)`, `printCodeTable(...)`, `rawBytes(...)`, `textEncoded(...)`, `setGlobalFont` bleibt (von `reset` genutzt). Lizenz-/Autoren-Header entfernen.

- [ ] **Step 2: Generator-Test schreiben**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/generator.dart';
import 'package:kasseneck_api/src/printing/escpos/enums.dart';
import 'package:kasseneck_api/src/printing/escpos/capability_profile.dart';
import 'package:kasseneck_api/src/printing/escpos/pos_styles.dart';
import 'package:kasseneck_api/src/printing/escpos/pos_column.dart';
import 'package:kasseneck_api/src/printing/escpos/qrcode.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

void main() {
  EscPosGenerator gen() => EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());

  test('text liefert Bytes inkl. Inhalt', () {
    final b = gen().text('Hallo');
    expect(b, isNotEmpty);
    expect(b.join(','), contains('Hallo'.codeUnits.join(',')));
  });

  test('row mit Spaltenbreite-Summe 12 wirft nicht', () {
    final b = gen().row([
      PosColumn(text: 'A', width: 6, styles: const PosStyles(align: PosAlign.left)),
      PosColumn(text: 'B', width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    expect(b, isNotEmpty);
  });

  test('qrcode delegiert an nativen QRCode-Befehl', () {
    final b = gen().qrcode('XYZ', size: QRSize.size6);
    expect(b.join(','), contains([0x31, 0x43, 0x06].join(','))); // Modulgroesse 6
  });

  test('imageRaster: 16x8 schwarz -> Header GS v 0 + Datenlaenge 2*8', () {
    final img = RasterImage.filled(16, 8, 0, 0, 0, 255);
    final b = gen().imageRaster(img);
    // Datenanteil = widthBytes(2)*height(8) = 16 schwarze Bytes (0xFF)
    expect(b.where((x) => x == 0xFF).length, greaterThanOrEqualTo(16));
  });

  test('image (ESC *) liefert Bytes ohne Crash fuer Nicht-/8-Breite', () {
    final img = RasterImage.filled(10, 24, 0, 0, 0, 255);
    expect(gen().image(img), isNotEmpty);
  });

  test('reset + setGlobalCodeTable(CP1252) setzt Codepage-Byte 16', () {
    final g = gen();
    g.reset();
    final b = g.setGlobalCodeTable('CP1252');
    expect(b.last, 16);
  });
}
```

- [ ] **Step 3: Tests laufen lassen** (erst FAIL, nach Step 1 schon vorhanden → PASS)

Run: `flutter test test/printing/escpos_generator_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/printing/escpos/generator.dart test/printing/escpos_generator_test.dart
git commit -m "feat(print): EscPosGenerator auf RasterImage (ohne image/hex/gbk)"
```

---

## Task 7: Barrels

**Files:**
- Create: `lib/src/printing/escpos/escpos.dart`
- Create: `lib/src/printing/raster/raster.dart`

- [ ] **Step 1: Barrels schreiben**

`raster/raster.dart`:
```dart
export 'raster_image.dart';
export 'raster_ops.dart';
export 'raster_codec.dart';
```

`escpos/escpos.dart`:
```dart
export 'enums.dart';
export 'commands.dart';
export 'pos_styles.dart';
export 'pos_column.dart';
export 'qrcode.dart';
export 'capability_profile.dart';
export 'generator.dart';
export '../raster/raster.dart';
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/src/printing`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/src/printing/escpos/escpos.dart lib/src/printing/raster/raster.dart
git commit -m "feat(print): Barrels fuer escpos/raster"
```

---

## Task 8: `keck_paper_size.dart` auf EscPaperSize

**Files:**
- Modify: `lib/enums/keck_paper_size.dart`

- [ ] **Step 1: Datei umstellen**

```dart
import 'package:kasseneck_api/src/printing/escpos/enums.dart';

enum KeckPaperSize {
  mm58(EscPaperSize.mm58, 32, 58, 296),
  mm80(EscPaperSize.mm80, 48, 80, 504);

  final int mm;
  final int defaultCharCount;
  final EscPaperSize paperSize;
  final int imageWidth;

  const KeckPaperSize(this.paperSize, this.defaultCharCount, this.mm, this.imageWidth);

  bool operator <(KeckPaperSize other) => mm < other.mm;
  bool operator >(KeckPaperSize other) => mm > other.mm;
  bool operator >=(KeckPaperSize other) => mm >= other.mm;
  bool operator <=(KeckPaperSize other) => mm <= other.mm;
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/enums/keck_paper_size.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/enums/keck_paper_size.dart
git commit -m "refactor(print): KeckPaperSize nutzt EscPaperSize"
```

---

## Task 9: `print_paper.dart` umbauen

**Files:**
- Modify: `lib/models/print_paper.dart`
- Test: `test/printing/print_paper_qr_test.dart` (neu)

**Interfaces:**
- Consumes: `EscPosGenerator`, `RasterImage`, `decodePng`, `encodePng`, `compositeOnWhite`, `resizeWidth`, `CapabilityProfile`, `EscPaperSize`, Enums/QR aus den Barrels.

- [ ] **Step 1: Importe ersetzen**

In `lib/models/print_paper.dart` die Zeilen
`import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';` und
`import 'package:image/image.dart';` ersetzen durch:
```dart
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
```
Feldtyp `final Generator generator;` → `final EscPosGenerator generator;`. Konstruktor:
```dart
PrintPaper({required this.paperSize, required CapabilityProfile profile})
    : generator = EscPosGenerator(paperSize.paperSize, profile) {
  reset();
}
```

- [ ] **Step 2: Bild-Methoden auf RasterImage/async umstellen**

`addImage` → async, `_onWhite` durch `compositeOnWhite` ersetzen:
```dart
Future<void> addImage(RasterImage image, {PosAlign align = PosAlign.center}) async {
  final RasterImage flat = compositeOnWhite(image);
  bytes.add(Uint8List.fromList(generator.imageRaster(flat)));
  final pngBytes = await encodePng(flat);
  myPosPaper.addImage(pngBytes);
}
```
`_onWhite` löschen. `addBase64Image`/`addUint8ListImage` async:
```dart
Future<void> addBase64Image(String base64, {PosAlign align = PosAlign.center}) async {
  final image = await decodePng(base64Decode(base64));
  await addImage(image, align: align);
}

Future<void> addUint8ListImage(Uint8List image, {PosAlign align = PosAlign.center}) async {
  final img = await decodePng(image);
  await addImage(img, align: align);
}
```

- [ ] **Step 3: `addQrCodeAsImage` umstellen**

Den `try`-Block ab `final Image? decoded = decodeImage(qrBytes);` ersetzen:
```dart
final RasterImage decoded = await decodePng(qrBytes);
const int quietZone = 16;
final RasterImage img = compositeOnWhite(
  decoded,
  canvasWidth: decoded.width + quietZone * 2,
  canvasHeight: decoded.height + quietZone * 2,
  dstX: quietZone,
  dstY: quietZone,
);
bytes.add(Uint8List.fromList(
  raster ? generator.imageRaster(img) : generator.image(img),
));
myPosPaper.addImage(await encodePng(img));
```
(Die QrPainter-Erzeugung darüber bleibt unverändert; `painter.toImageData(size)` → `qrBytes`.)

- [ ] **Step 4: `setKeckReceipt` + `_addKreiseckBranding` umstellen**

Logo-Block in `setKeckReceipt`:
```dart
if (receipt.logo != null) {
  final RasterImage image = await decodePng(receipt.logo!);
  final RasterImage resized = resizeWidth(image, paperSize.imageWidth);
  await addImage(resized);
  addFeed();
}
```
Branding:
```dart
static RasterImage? _kreiseckLogo;
...
if (_kreiseckLogo == null) {
  for (final key in [
    'packages/kasseneck_api/assets/kreiseck_logo_print.png',
    'assets/kreiseck_logo_print.png',
  ]) {
    try {
      final data = await rootBundle.load(key);
      _kreiseckLogo = await decodePng(data.buffer.asUint8List());
      break;
    } catch (_) {}
  }
}
final logo = _kreiseckLogo;
if (logo == null) return;
addFeed();
addText('powered by', styles: PosStyles(align: PosAlign.center));
final int width = ((paperSize.imageWidth * 0.85) ~/ 8) * 8;
await addImage(resizeWidth(logo, width));
```

- [ ] **Step 5: Aufrufstellen `await` setzen**

`addImage`/`addBase64Image`/`addUint8ListImage` sind jetzt `Future`. Alle Aufrufer awaiten (alle liegen in bereits-`async` Methoden: `setKeckReceipt`, `_addKreiseckBranding`). `generator.*`-Aufrufe (text/row/feed/reverseFeed/hr/cut/drawer/qrcode/image/imageRaster/reset/setGlobalCodeTable) bleiben unverändert (gleiche Namen). `QRSize.size6` bleibt (jetzt aus vendiertem `qrcode.dart`).

- [ ] **Step 6: QR-Verhaltenstest schreiben**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native QR-Modus erzeugt Modulgroesse-Byte', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    paper.addQrCode('TESTTOKEN'); // native
    final flat = paper.bytes.expand((e) => e).toList();
    expect(flat.join(','), contains([0x31, 0x43].join(','))); // FN167 QR-Modulgroesse
  });
}
```

(Der native-QR-Test braucht keinen Beleg. Für einen vollständigen `setKeckReceipt`-Durchlauf die vorhandene `test/helpers/test_receipts.dart` nutzen und in `tester.runAsync` ausführen.)

- [ ] **Step 7: Tests + Analyze**

Run: `flutter test test/printing/print_paper_qr_test.dart && flutter analyze lib/models/print_paper.dart`
Expected: PASS, 0 Issues.

- [ ] **Step 8: Commit**

```bash
git add lib/models/print_paper.dart test/printing/print_paper_qr_test.dart
git commit -m "refactor(print): print_paper nutzt RasterImage/EscPosGenerator (async Bildpfad)"
```

---

## Task 10: `printer_service.dart` umbauen

**Files:**
- Modify: `lib/services/printer_service.dart`

- [ ] **Step 1: Importe + Profil-Erzeugung**

`import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';` → `import 'package:kasseneck_api/src/printing/escpos/escpos.dart';`. Alle `await CapabilityProfile.load()` → `CapabilityProfile()` (synchron). `_profile`-Typ bleibt `CapabilityProfile?`. In `openCashDrawer`:
```dart
final generator = EscPosGenerator(paperSize.paperSize, CapabilityProfile());
final drawerBytes = generator.drawer();
await _sendToSocketPrinter(drawerBytes);
```
`initWifiPrinter`/`initBluetoothPrinter`: `_profile = CapabilityProfile();` (kein await/try mehr nötig — der frühere try/catch um `CapabilityProfile.load()` entfällt, da synchron und unfehlbar).

- [ ] **Step 2: Analyze + Test**

Run: `flutter analyze lib/services/printer_service.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/services/printer_service.dart
git commit -m "refactor(print): printer_service nutzt EscPosGenerator + sync CapabilityProfile"
```

---

## Task 11: `pubspec.yaml` bereinigen, 4.0.0, CHANGELOG, Tests grün

**Files:**
- Modify: `pubspec.yaml`, `CHANGELOG.md`
- Modify: betroffene Tests in `test/` (Bild-Decode → `runAsync`)

- [ ] **Step 1: `pubspec.yaml`**

`image: ^4.8.0` und `esc_pos_utils_plus: ^2.0.4` (samt Kommentar `# esc_pos_utils: ^1.1.0`) aus `dependencies` **entfernen**. `version: 3.3.0` → `version: 4.0.0`.

- [ ] **Step 2: pub get + globaler Analyze**

Run: `flutter pub get && flutter analyze`
Expected: No issues. Falls noch ein `package:image`/`esc_pos_utils`-Import irgendwo referenziert wird, meldet der Analyzer es hier — die Stelle auf die internen Module umstellen.

- [ ] **Step 3: Bestehende Tests anpassen**

Tests, die früher `image`/`esc_pos_utils_plus` importierten oder Bilder dekodierten, umstellen:
- `test/print_rendering_test.dart`, `test/print_widget_consistency_test.dart`: Profil über `CapabilityProfile()` statt `await CapabilityProfile.load()`; `PaperSize`→`EscPaperSize` falls referenziert; QR weiterhin `QrPrintMode.native` (kein Decode).
- `test/logo_service_test.dart`, `test/kreiseck_branding_test.dart`, `test/models_misc_test.dart`: Wo echte PNG-Dekodierung über `setKeckReceipt`/`addImage` läuft, Aufruf in `testWidgets` + `await tester.runAsync(() async { ... })` kapseln (dart:ui-Codec braucht echten Async-Tick), und `TestWidgetsFlutterBinding.ensureInitialized()`.

- [ ] **Step 4: Volle Suite + Analyze**

Run: `flutter test && flutter analyze`
Expected: Alle Tests grün, 0 Analyzer-Issues.

- [ ] **Step 5: CHANGELOG**

Oben in `CHANGELOG.md` einfügen:
```markdown
## 4.0.0
- Druck-Stack von den Paketen `image` und `esc_pos_utils_plus` entkoppelt: der ESC/POS-Generator und der (korrekte) Rasterizer aus esc_pos_utils 1.1.0 sind jetzt intern unter `lib/src/printing/`, PNG-De/Encode laeuft ueber `dart:ui`. Dadurch gibt es **keine** `image`-Versionssperre mehr fuer Apps, die dieses Paket nutzen.
- Behebt den Bluetooth-/Thermo-Druckfehler bei Bildbreiten, die kein Vielfaches von 8 sind (Crash im `esc_pos_utils_plus`-Rasterizer); QR- und Logo-Druck unveraendert in Funktion (nativer QR byte-identisch, Bild-QR weiter auf weissem Grund mit Ruhezone).
- Breaking: `KeckPaperSize.paperSize` hat jetzt den Typ `EscPaperSize` (intern) statt `PaperSize` aus esc_pos_utils.
```

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml CHANGELOG.md test/
git commit -m "build: image + esc_pos_utils_plus entfernt; v4.0.0; Tests auf interne Module"
```

---

## Self-Review-Notizen (Plan ↔ Spec)

- **Spec „RasterImage + Ops"** → Tasks 1–2. **dart:ui-Brücke** → Task 3. **escpos-Modul** → Tasks 4–6. **Minimal-Profil** → Task 5. **QR-Garantien** → Task 4 (Golden nativ), Task 2 (Alpha→Weiß, Nicht-÷8), Task 9 (QR-Modi). **Anpassungen** → Tasks 8–10. **pubspec/Breaking/4.0.0** → Task 11.
- **Golden Image-QR-Raster (Spec):** bewusst als *eigene*-Ausgaben-Regression umgesetzt (Task 2/6), nicht byte-identisch zur alten `image`-Lib (deren grayscale-Rundung wäre fragil) — die verhaltensbasierten QR-Tests (Alpha→Weiß, Maße, Threshold, nativ byte-exakt) sind die eigentliche Korrektheitsgarantie.
- **Offenes Risiko:** dart:ui-Codec im Headless-Test kann `runAsync` erfordern (in Tasks 3 & 11 adressiert). `qr_flutter`/`QrPainter` bleibt unverändert genutzt.
