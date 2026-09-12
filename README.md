<p align="center">
  <img src="https://raw.githubusercontent.com/mhmmdlkts/kasseneck_flutter_api/main/doc/kasseneck.gif" alt="Kasseneck — RKSV-Registrierkasse aus Österreich" width="420">
</p>

<h1 align="center">kasseneck_api</h1>

<p align="center">
  <b>Austrian fiscal cash register (RKSV) for Flutter — signed receipts, card payments, receipt printing.</b>
</p>

<p align="center">
  <a href="https://pub.dev/packages/kasseneck_api"><img src="https://img.shields.io/pub/v/kasseneck_api?color=136B6B&label=pub" alt="pub"></a>
  <a href="https://pub.dev/packages/kasseneck_api/score"><img src="https://img.shields.io/pub/points/kasseneck_api?color=136B6B" alt="pub points"></a>
  <img src="https://img.shields.io/badge/RKSV-%C2%A7%20131b%20BAO-136B6B" alt="RKSV">
  <img src="https://img.shields.io/badge/Lizenz-MIT-136B6B" alt="MIT">
  <a href="https://kasseneck.at"><img src="https://img.shields.io/badge/Kasseneck-kasseneck.at-132A2A" alt="kasseneck.at"></a>
  <a href="https://kreiseck.com"><img src="https://img.shields.io/badge/von-Kreiseck-132A2A" alt="Kreiseck Software Solutions"></a>
</p>

**Kasseneck** ist eine österreichische Registrierkasse nach RKSV. Dieses Paket ist
der Flutter-Client dafür: Ihre App stellt Belege aus, storniert sie, nimmt
Kartenzahlungen entgegen und druckt Bons. Es ist der Zwilling des
JavaScript-Pakets
[`@kreiseck/kasseneck-api`](https://www.npmjs.com/package/@kreiseck/kasseneck-api):
dieselben Endpunkte, dieselben Modelle, dieselben Enum-Werte, im Test
gegeneinander geprüft.

## Was eine Registrierkasse in Österreich können muss

Die Registrierkassen- und Belegerteilungspflicht steht in § 131b der
Bundesabgabenordnung, die technischen Anforderungen an die Sicherheitseinrichtung
in der Registrierkassensicherheitsverordnung (RKSV). Daraus ergibt sich eine
ganze Kette von Aufgaben — die Tabelle zeigt, welche davon **diese Software**
übernimmt und welche beim Betrieb selbst bleiben:

| Aufgabe | Wo sie erledigt wird |
| --- | --- |
| [Signaturerstellungseinheit](https://kasseneck.at/wissen/signaturerstellungseinheit) — jede Barzahlung wird signiert | Kasseneck, nichts zu installieren |
| [Verkettung und DEP](https://kasseneck.at/wissen/dep) — jeder Beleg trägt den vorigen, das Protokoll ist exportierbar | Kasseneck-Backend |
| [Startbeleg, Monatsbeleg, Jahresbeleg](https://kasseneck.at/wissen/startbeleg-monatsbeleg-jahresbeleg) | Kasseneck, automatisch |
| [Meldungen an FinanzOnline](https://kasseneck.at/wissen/finanzonline) — Anmeldung, Ausfall, Außerbetriebnahme | Kasseneck-Backend |
| [Belegerteilungspflicht](https://kasseneck.at/wissen/belegerteilungspflicht) — jeder Kunde bekommt einen Beleg | **dieses Paket** — Bon, Bildschirm, PDF oder Link |
| [Ausfall der Signatureinheit](https://kasseneck.at/wissen/ausfall) — Sammelbeleg, Meldung, Nachsignatur | Kasseneck, automatisch |
| [Kassennachschau](https://kasseneck.at/wissen/kassennachschau) — der Prüfer verlangt das DEP | Kasseneck, Export auf Knopfdruck |
| Anmeldung der Kasse, Aufbewahrung, steuerliche Würdigung | **beim Unternehmer** |

Kurz: Sie bauen die Kassenoberfläche, nicht die Sicherheitseinrichtung. Ein
`sellReceipt(...)` erzeugt einen signierten, verketteten und im DEP abgelegten
Beleg. Die Signaturkette wird gegen das offizielle Prüfwerkzeug des BMF getestet.

> **Kein Rechts- oder Steuerrat.** Dieser Abschnitt beschreibt, was die Software
> tut. Er ersetzt keine Beratung und begründet keine Zusicherung, dass ein
> bestimmter Betrieb damit alle Pflichten erfüllt. Verbindlich sind die
> Bundesabgabenordnung, die RKSV und die Erlässe des BMF; die Verantwortung für
> Anmeldung, Betrieb und Aufbewahrung bleibt beim Unternehmer. Ausführlicher und
> mit Quellen: [kasseneck.at/wissen](https://kasseneck.at/wissen).
> Stand: September 2026.

## Lieber eine fertige Kasse?

Dieses Paket ist für alle, die eine eigene App bauen. Wer einfach kassieren will,
muss nichts davon programmieren:

- **[Kasseneck — die fertige Registrierkasse](https://kasseneck.at)** für Telefon,
  Tablet und Browser, inklusive Signaturerstellungseinheit und
  FinanzOnline-Anmeldung.
- **[Lösungen nach Branche](https://kasseneck.at/branchen)** — vom Lokal bis zum Taxi.
- **[Preise](https://kasseneck.at/preise)** · **[API-Doku](https://kasseneck.at/api-doku)**
- **[Kontakt](https://kasseneck.at/kontakt)** — auch für Kassenwechsel,
  Partnerschaften und eigene Integrationen.

## Was drin ist

- **RKSV-Belege** — Standard, Storno, Null und Training; signierte JWS-Kette samt QR-Code
- **Alle österreichischen Steuersätze** — inklusive der **4,9 % für Grundnahrungsmittel** (seit 1. Juli 2026)
- **Beträge in ganzen Cent** — intern nie Fließkomma, also keine Rundungsdrift
- **Kartenzahlung ab Werk** — hobex (Cloud und Terminal-**HPS**), myPOS, GP Tom, SumUp — und **jedes andere Verfahren** über `CreditCardProvider.custom`
- **Gutscheine** — Wert- und Rabattgutscheine, verkaufen und einlösen, mit anteiliger Steueraufteilung
- **Trinkgeld** — je Kassen-Benutzer, bar oder mit Karte; Mitarbeiter-Trinkgeld läuft als 0-%-Durchlauf, Chef-Trinkgeld als Erlös, auf die Steuersätze des Belegs verteilt
- **Druck** — Bluetooth und WLAN (ESC/POS) sowie der eingebaute myPOS-Drucker
- **Fertiges Beleg-Widget** für die Anzeige am Schirm
- **Berichte und Rechnungen** — Tages- und Monats-PDF
- **Stripe-Zahllinks** für Fern- und Onlinezahlungen

## Voraussetzungen

- Flutter, Dart ab 3.6
- Ein Kasseneck-**API-Schlüssel** und ein **Kassen-Token** — [Kontakt](https://kasseneck.at/kontakt)
- Für Kartenzahlung und Bluetooth-Druck ein **Android**-Gerät oder -Terminal: die Terminal-Pakete (myPOS, SumUp) sind Android-only. Der Rest des Pakets läuft überall, wo Flutter läuft.

## Einbinden

```yaml
dependencies:
  kasseneck_api: ^6.12.1
```

```bash
flutter pub get
```

## Schnellstart

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';

final kasseneck = KasseneckApi(
  apiKey: 'IHR_API_SCHLUESSEL',
  cashregisterToken: 'IHR_KASSEN_TOKEN',
);

// Ein Barverkauf mit zwei Posten — Preise sind ganze Cent (320 = 3,20 €)
final receipt = await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.cash,
  customerDetails: ['Max Mustermann'],
  items: [
    KasseneckItem(name: 'Kaffee', quantity: 2, vat: VatRate.vat20,      priceCents: 320),
    KasseneckItem(name: 'Brot',   quantity: 1, vat: VatRate.vat4komma9, priceCents: 240),
    // oder, wenn Sie Euro-Doubles haben: KasseneckItem.euro(..., singlePrice: 3.20)
  ],
);

print('Beleg ${receipt?.receiptId} — signiert: ${receipt?.signatureSuccess}');
```

> Modelle und Enums liegen in eigenen Dateien — importieren Sie die, die Sie
> brauchen (`models/…`, `enums/…`). Zahlung, Gutschrift, Null- und
> Trainingsbelege laufen alle über dieselbe `KasseneckApi`-Instanz.
> **Stornos gehen über `RegisterReceiptClient.stornieren`** (siehe unten);
> `cancelReceipt` und `createCancelReceipt` auf `KasseneckApi` sind der
> veraltete alte Weg.

## Storno, ganz oder in Teilen

Ein Storno ist ein **neuer signierter Beleg**, der einen bestehenden umkehrt —
vollständig oder teilweise. Der Kassen-Client
(`package:kasseneck_api/kasse.dart`, `RegisterReceiptClient`) spricht den
Endpunkt `cancelReceipt` des Backends an; der Server negiert die Zeilen, prüft
Restmengen und Rechte, verknüpft beide Belege und druckt die Bezugszeile auf den
Stornobeleg.

```dart
import 'package:kasseneck_api/kasse.dart';

final ergebnis = await client.stornieren(
  originalReceiptId: 'KASSE1-ID-42',
  grund: 'fehleingabe',                       // Katalog: stornogruende
  positionen: [(index: 0, menge: 1)],         // weglassen = alles Verbliebene stornieren
  anmerkung: 'Kunde wollte nur eine',         // interne Notiz, wird nie gedruckt
);
ergebnis.beleg;        // der signierte Stornobeleg
ergebnis.restmengen;   // was je Zeile des Originals noch offen ist
```

**Entscheiden Sie am Fehlercode, nie an der Meldung.** Jeder fachliche Fehler von
`cancelReceipt` trägt `KasseneckApiError.code` aus `stornoFehlercodes` — etwa
`bereits_storniert`, `menge_ueber_rest`, `nur_eigene_belege`. Die deutsche
`message` ist für die Anzeige und kann sich ändern.

```dart
try {
  await client.stornieren(originalReceiptId: id, grund: 'fehleingabe');
} on KasseneckApiError catch (e) {
  switch (e.code) {
    case 'bereits_storniert': // Beleg als storniert zeigen, Knopf sperren
    case 'menge_ueber_rest':  // Restmengen neu laden (jemand war schneller)
    case 'nur_eigene_belege': // den Chef fragen
      break;
    default:
      rethrow;
  }
}
```

**Gutscheine.** Ein Wertgutschein wird nur bei einem Vollstorno gespiegelt (ohne
`positionen`) — er ist unteilbar. Ein Rabattgutschein steckt bereits im Umsatz des
Originals; **jedes** Storno nimmt ihn anteilig zur stornierten Menge zurück:
3 × 10 € mit 6 € Rabatt sind 8 € je Stück, der Stornobeleg zeigt also „−10,00"
und dazu eine Zeile „Gutschein-Ausgleich +2,00". Was ein Storno gewährt hat,
steht an seinem Eintrag in `receipt.cancellations` als `promoAdjustmentCents`
(Cent je Steuerkorb) — die Kasse kann es anzeigen und muss es nie selbst rechnen.

Vor einem Storno liefert `restmengen(beleg)` die Restmengen aus der
`cancellations`-Liste des Originals; maßgeblich bleibt der Server.

## Beleg per E-Mail senden

Der Gast nennt an der Kasse eine Adresse und bekommt einen **Link auf die
öffentliche Belegseite** — ohne PDF im Anhang: diese Seite nutzt dasselbe
Zeilenmodell wie Schirm und Bondrucker und bietet dort ein PDF an. Das
Belegdokument selbst bleibt byteidentisch (es ist das DEP, § 131 BAO); das
Backend protokolliert den Versand daneben.

```dart
// Kassen-Anmeldung (package:kasseneck_api/kasse.dart)
final erg = await client.belegSenden(fullReceiptId: beleg.fullReceiptId, an: 'gast@example.com');
// API-Schlüssel (package:kasseneck_api/kasseneck_api.dart)
final erg2 = await kasseneck.belegSenden(fullReceiptId: id, an: 'gast@example.com');

erg.to;   // normalisierte Adresse, wie das Backend sie protokolliert hat
erg.at;   // ISO-Zeitstempel in Wiener Zeit
erg.via;  // 'eigen' | 'plattform' | 'plattform-fallback'
```

**Entscheiden Sie auch hier am Fehlercode** — `KasseneckApiError.code` aus
`belegMailFehlercodes`: `adresse_ungueltig` (korrigieren lassen), `zu_oft` (das
Backend erlaubt fünf Mails je Beleg in 24 Stunden und 30 je Kasse pro Stunde —
später, nicht jetzt), `versand_fehlgeschlagen` (nichts ist hinausgegangen, ein
neuer Versuch ist in Ordnung), `beleg_nicht_gefunden` (unbekannter Beleg **oder**
einer, der zu einer anderen Kasse gehört — das Backend antwortet bewusst in
beiden Fällen gleich). Die Adresse prüft allein das Backend: eine zweite,
strengere Prüfung hier würde Adressen abweisen, die der Server annimmt.

## Kartenzahlung

Kartenzahlung läuft **ab Werk** mit mehreren Terminals — und Sie sind an keines
gebunden:

| Verfahren | Wie |
|---|---|
| **hobex Cloud** (empfohlen) | `HobexCloudPayments` — `pay(...)` mit aufgelöstem, dreiwertigem Ausgang |
| **hobex HPS** (Terminal vor Ort, empfohlen) | `HpsPayments` — `pay`/`refund`/`cancel`, derselbe dreiwertige Ausgang |
| **myPOS · GP Tom · SumUp** | unterstützt und am Beleg ausgewiesen |
| **Jedes andere Terminal** | `CreditCardProvider.custom` — eigene Kartendaten übergeben |

Welches Terminal auch immer: das Ergebnis geht als `cardPaymentData` an
`sellReceipt(...)` und wird am Beleg gespeichert und gedruckt.

**Warum `HpsPayments`/`HobexCloudPayments` statt des Terminals direkt:** Eine
Kartenzahlung hat drei mögliche Ausgänge, nicht zwei — genehmigt, sicher
abgelehnt, oder *unbekannt* (Zeitablauf, abgerissene Verbindung, das Terminal hat
nie geantwortet). „Unbekannt" als „abgelehnt" zu behandeln und es erneut zu
versuchen, ist genau der Weg, auf dem ein Kunde zweimal belastet wird. Beide
Klassen legen die Transaktionskennung **vor** dem ersten Netzaufruf fest und
lösen dieselbe Kennung beim Terminal bzw. in der Cloud auf, wenn die erste
Antwort verlorengeht, statt still einen neuen Versuch zu starten — eine verlorene
Antwort endet also in `CardPaymentOutcome.unresolved` (Kennung behalten, später
auflösen) statt geraten zu werden.

<details>
<summary><b>Beispiel — hobex-Terminal vor Ort (HPS) zum signierten Beleg</b></summary>

```dart
import 'package:kasseneck_api/hobex_hps.dart'; // HpsClient, HpsPayments, HpsResult, CardPaymentOutcome, HobexReceipt

final hps = HpsPayments(HpsClient(tid: '3600335')); // TID ohne führende Null

// Die Kennung steht fest, BEVOR die Anfrage hinausgeht — sofort speichern, damit
// eine verlorene Antwort später aufgelöst und nicht blind wiederholt wird.
final transactionId = HpsClient.newTransactionId();

final result = await hps.pay(amount: 12.50, transactionId: transactionId);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // weiter unten
  case CardPaymentOutcome.declined:
    return; // sicher kein Geld geflossen — ein neuer Versuch ist unbedenklich
  case CardPaymentOutcome.unresolved:
    // Nicht innerhalb des Auflösungsbudgets geklärt (90 s, einstellbar).
    //
    // Hier NICHT wiederholen. Am echten Terminal gemessen (26.08.2026): dieselbe
    // transactionId erneut zu senden startet einen ZWEITEN Kartenvorgang — das
    // Terminal erkennt sie nicht als dieselbe Transaktion. Eine Wiederholung ist
    // eine echte zweite Belastung, keine gefahrlose Wiedervorlage.
    //
    // `transactionId` behalten, den Ausgang zuerst auflösen —
    // `HpsClient.transactionStatus(...)`, sobald das Terminal wieder antwortet —
    // und erst auf einen bekannten Ausgang hin handeln.
    // doc/kartenzahlung.md beschreibt, was die einzelnen Antwortcodes bedeuten.
    return;
}

// Terminal-Ergebnis übernehmen, dann den signierten Beleg erzeugen.
final card = HobexReceipt.fromHps(result.response!);
await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider, // hobexHps
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
  items: [KasseneckItem(name: 'Mittagessen', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

Ebenfalls vorhanden: `hps.refund(...)`, `hps.cancel(...)` — mit demselben
aufgelösten Ausgang. Ein `HpsObserver` am Konstruktor von `HpsPayments`
protokolliert Anfragen, Fehlschläge und den Weg, auf dem ein Ausgang aufgelöst
wurde.
</details>

<details>
<summary><b>Beispiel — hobex Cloud zum signierten Beleg</b></summary>

```dart
import 'package:kasseneck_api/kasseneck_api.dart'; // HobexCloudPayments, HobexCloudResult, CardPaymentOutcome

final cloud = HobexCloudPayments(kasseneck);

// Dieselbe Regel wie bei HPS: die Kennung legt der Aufrufer fest, bevor die Anfrage hinausgeht.
final transactionId = KasseneckApi.newHobexTransactionId();

final result = await cloud.pay(transactionId: transactionId, amount: 12.50);

switch (result.outcome) {
  case CardPaymentOutcome.approved:
    break; // weiter unten
  case CardPaymentOutcome.declined:
    return; // sicher kein Geld geflossen — ein neuer Versuch ist unbedenklich
  case CardPaymentOutcome.unresolved:
    // Nicht im Auflösungsbudget geklärt. NICHT blind wiederholen — `transactionId`
    // behalten und später auflösen, siehe das HPS-Beispiel oben.
    return;
}

final card = result.receipt!;
await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.creditCard,
  creditCardProvider: card.creditCardProvider,
  cardPaymentId: card.transactionId,
  cardPaymentData: card.toCardPaymentData(),
  items: [KasseneckItem(name: 'Mittagessen', quantity: 1, vat: VatRate.vat10, priceCents: 1250)],
);
```

`HobexCloudPayments` hat kein `cancel()` — eine Cloud-Gutschrift läuft weiterhin
über den rohen Aufruf `kasseneck.hobexRefund(...)` (siehe unten), unaufgelöst wie
der einfache Aufruf.
</details>

<details>
<summary><b>Roher Zugriff — <code>HpsClient</code> / <code>kasseneck.hobexPay(...)</code></b></summary>

Sowohl der lokale `HpsClient` (`import 'package:kasseneck_api/hobex_hps.dart';`)
als auch die Cloud-Aufrufe `kasseneck.hobexPay(...)` / `hobexRefund(...)` bleiben
direkt verfügbar, für volle Kontrolle über die Anfrage. **Keiner von beiden löst
den Ausgang auf:** ein roher Aufruf, der nie eine Antwort bekommt, bleibt für
immer ungeklärt — einen Zahlungsablauf darauf zu bauen heißt, genau das Problem
noch einmal zu lösen, das `HpsPayments` und `HobexCloudPayments` bereits lösen,
mit dem echten Risiko, die Frage „wurde belastet?" ausgerechnet unter den
Bedingungen falsch zu beantworten (Zeitablauf, Verbindungsabriss), unter denen
eine falsche Antwort teuer ist. Zum rohen Client greifen Sie nur, wenn Sie etwas
brauchen, das die aufgelöste Hülle nicht zeigt (etwa `hps.diagnosis()`,
`hps.transactionStatus(...)`).
</details>

## Drucken

```dart
// Bluetooth (ESC/POS)
await kasseneck.initBluetoothPrinter(printerAddress: 'AA:BB:CC:DD:EE:FF');
await receipt!.printReceiptBluetooth();

// QR verstümmelt oder fehlt? Drucker verstehen unterschiedliche Befehle:
await receipt.printReceiptBluetooth(qrMode: QrPrintMode.imageBitImage); // oder .native
// Manche günstigen Drucker kennen nur das ältere QR-Modell 1:
await receipt.printReceiptBluetooth(qrMode: QrPrintMode.nativeModel1);

// Der native Befehl bemisst seine Module selbst am Papier (Ruhezone inbegriffen),
// der QR wird also nie breiter als der Kopf drucken kann. Begrenzen Sie ihn, wenn
// er kleiner oder größer sein soll — die Grenze vergrößert nie über das Passende hinaus:
await receipt.printReceiptBluetooth(qrGroesse: QrModulGroesse.gross);

// WLAN
await kasseneck.initWifiPrinter('192.168.0.50', KeckPaperSize.mm80);
await receipt.printReceiptWifi();

// Kassenlade öffnen
await KasseneckApi.openCashDrawer();
```

## Beleg am Schirm

Ein fertiges Widget zeichnet den ganzen Beleg (Logo, Posten, Steuertabelle, QR,
Kartendaten):

```dart
KeckReceiptWidget(receipt: receipt);
```

## Berichte und Rechnungen

```dart
final monthly = await kasseneck.downloadMonthlyReport(ReportMonth.now()); // Uint8List (PDF)
final daily   = await kasseneck.downloadDailyReport(DateTime.now());
final history = await kasseneck.getReceipts(start, end);
```

## RKSV im Detail

Jeder Beleg ist verkettet und signiert (ES256 / JWS) und liegt als
maschinenlesbare QR-Nutzlast vor, genau wie die RKSV es verlangt. Ausfälle der
Signatureinheit werden erkannt (`receipt.signatureSuccess` /
`receipt.isSigFailed`) und am Beleg ausgewiesen.

## Versionen

Das Paket folgt der semantischen Versionierung — was sich wann geändert hat,
steht im [CHANGELOG](CHANGELOG.md).

## Lizenz

MIT — siehe [LICENSE](LICENSE).

---

**Kasseneck** ist ein Produkt von
[Kreiseck Software Solutions](https://kreiseck.com) aus Salzburg — Apps,
Kassensysteme und Automatisierungen. Fragen zur Schnittstelle, zu eigenen
Integrationen oder zu einer Partnerschaft:
[kasseneck.at/kontakt](https://kasseneck.at/kontakt).
