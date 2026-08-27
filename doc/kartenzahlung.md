# Kartenzahlung: was das Terminal tatsächlich tut

Stand 27.08.2026. Diese Datei hält fest, was am echten Gerät **gemessen** wurde —
nicht, was die Dokumentation verspricht. Drei Annahmen, die plausibel klangen und
mehrere Code-Reviews überstanden haben, sind an der Messung gescheitert.

Wer den Zahlweg ändert, liest das hier zuerst. Die daraus destillierten Regeln
stehen in [`../AGENTS.md`](../AGENTS.md).

## Warum es diese Datei gibt

Am 24.08.2026 wurde ein Kunde zweimal mit 25 € belastet. Die App meldete beide
Male „Kartenzahlung fehlgeschlagen"; bei hobex waren beide Vorgänge genehmigt.

Die Ursache war nicht ein einzelner Bug, sondern eine Denkweise: **ein
unbekannter Ausgang wurde wie ein fehlgeschlagener behandelt.** Die
Transaktionskennung entstand erst mit der Antwort — blieb die aus, war sie
verloren, und weder Statusabfrage noch Storno waren erreichbar. Jede Wiederholung
wurde damit zwangsläufig ein zweiter Vorgang.

Beim Beheben ist derselbe Fehler zweimal neu entstanden, an anderer Stelle. Er
ist verführerisch, weil „fehlgeschlagen" sich wie die vorsichtige Annahme anfühlt.
Sie ist es nicht: Sie behauptet, dass nichts passiert ist.

## Messumgebung

hobex HPS im selben Netz. TID `3600335`, HPS `1.10.0`, Firmware `7.3.6`,
Autorisierungshost `tecstest.hobex.at:23443` (Testsystem). Erreicht über
`http://<ip>:8080`; im Betrieb läuft die App auf dem Terminal selbst und spricht
`127.0.0.1:8080`.

## Was welche Antwort bedeutet

| Lage | Antwort der Zahlung | `transactionStatus` | `abort` |
|---|---|---|---|
| genehmigt | `0` Genehmigt | `0` Genehmigt, bleibt erhalten | `100010` — **scheitert** |
| Kartenfluss läuft | (offen) | `9027` | `0` — **gelingt** |
| Karte nicht aufgelegt | `100003` Card not present | `9027` | — |
| abgebrochen | `100002` Aborted | `9027` | — |
| Kennung nie gesehen | — | `9027` | — |
| aufgehoben (Void) | — | `9011` Transaction Canceled | — |

### `9027` ist keine Aussage

`9027 "Original Tx not found"` steht **gleichermaßen** für „nie angekommen",
„läuft gerade" und „abgebrochen". Es ist ein vorhandener Ergebniscode ungleich
`'0'` — wer daraus `declined` macht, meldet für einen **laufenden** Vorgang
„nichts belastet, Wiederholung gefahrlos". Der Kunde legt die Karte auf, der
erste Vorgang geht durch, die Wiederholung belastet ein zweites Mal.

Genau das hätte die erste Fassung dieses Pakets getan.

### `abort` unterscheidet, was der Status nicht unterscheidet

Der Abbruch gelingt, solange der Vorgang abbrechbar ist, und scheitert mit
`100010`, sobald er abgeschlossen ist — die genehmigte Zahlung bleibt dabei
unangetastet. Das ist der Diskriminator, den die Statusabfrage nicht liefert.

**Falle:** Das Terminal meldet das Scheitern mit **HTTP 200** und `100010` im
Rumpf. Wer nur auf „hat nicht geworfen" prüft, hält einen gescheiterten Abbruch
für einen geglückten — und macht daraus wieder `declined` für eine echte
Belastung.

### Der Klärweg, der daraus folgt

Bleibt die Antwort auf eine Zahlung aus:

1. **`abort` einmalig versuchen.**
2. `responseCode == '0'` → der Vorgang war noch abbrechbar, also nicht
   abgeschlossen → **`declined`**, beweisbar.
3. Ein anderer Code (gemessen: `100010`) → der Vorgang ist über den abbrechbaren
   Punkt hinaus → **jetzt** `transactionStatus` pollen; sie liefert nun eine
   echte Aussage.
4. Scheitert der Abbruch am Transport → pollen wie in 3.
5. Beim Pollen ist `9027` **kein Ergebnis**: weiter klären. Budget erschöpft →
   `unresolved`.

Ein Abbruch, der gelingt, während der Kunde gerade die Karte auflegt, reißt
dessen Zahlung ab. Geldseitig sicher, und die bewusste Wahl: lieber ein
abgerissener Vorgang als eine ungeklärte Belastung.

## Zwei widerlegte Annahmen

**Eine Wiederholung unter derselben Kennung ist nicht idempotent.** Für eine
bereits genehmigte Kennung hat das Terminal einen zweiten Kartenfluss gestartet.
Es entdeckelt nichts. Wer eine Wiederholung anbietet, bietet eine zweite
Belastung an — die Kennung ändert daran nichts.

Immerhin: eine genehmigte Kennung bleibt in der Statusabfrage genehmigt, auch
nachdem unter ihr ein zweiter Versuch abgebrochen wurde.

**`state` ist auf dieser Firmware durchgehend `null`.** In jeder gemessenen
Antwort — genehmigt, abgebrochen, unbekannt, aufgehoben. Eine Storno-Klärung
über `state == 'VOID'` greift nie und läuft immer ins Budget. Der gemessene
Diskriminator ist `responseCode 9011` auf der **Original**-Kennung.

Dabei gilt weiterhin die Trennung, ohne die es gefährlich wird: Der `responseCode`
der **Originalzahlung** ist niemals der Erfolg der **Aufhebung**. Ein `0` dort
heißt ausdrücklich, dass die Aufhebung **nicht** gewirkt hat.

### Gutschriften verhalten sich wie Zahlungen

`abort` auf eine laufende **Gutschrift** liefert ebenfalls `responseCode "0"`,
und die Gutschrift endet mit `100002 Aborted`. Der Klärweg oben gilt dort
unverändert.

Das ist der entscheidende Unterschied zur **Aufhebung**: Bei `refund` ist die
übergebene Kennung die des *neuen* Vorgangs, wie bei `pay`. Bei `cancel` ist sie
die der längst abgeschlossenen Originalzahlung — ein Abbruch könnte dort nur
`100010` ernten. Deshalb hat `cancel` eine eigene Klärung.

### Das Terminal serialisiert — die Klärung kann sich selbst im Weg stehen

Eine zweite Anfrage, während eine läuft, wird mit **HTTP 409**, `text/plain`,
Rumpf `Terminal is busy` abgewiesen. Der Client macht daraus eine
`HpsHttpException` mit genau dieser Meldung — kein `FormatException`, obwohl es
kein JSON ist.

Das ist keine Randnotiz: Bei einem Polling im 200-ms-Takt kam ein parallel
abgesetzter Void **gar nicht durch**. Wer die Klärung zu dicht taktet, hungert
den Vorgang aus, den er klären will. Der Backoff ist deshalb kein Schönheits-,
sondern ein Funktionsmerkmal.

**Entschieden am 27.08.2026** (siehe unten, „HTTP 409: ein eigener, benannter
Fall"): `409 "Terminal is busy"` heißt streng genommen „ich habe diese Anfrage
**nicht angenommen**" — eine Aussage, kein Nichtwissen. Für die abgewiesene
**erzeugende** Anfrage ist damit nachweislich nichts belastet, und der
Klärweg liest sie jetzt als `declined`. Für jede andere Anfrage (Abbruch,
Statusabfrage während der Klärung — wie beim Polling-Vorfall oben) bleibt
`409` unverändert ein gewöhnlicher Transportfehler: er sagt dort nur, dass
DIESE Anfrage nicht durchkam, nichts über den Vorgang, den sie klären sollte.

### Nach einem gelandeten Void schlägt der Status sofort um

Kein Nachlauf: Sobald der Void am Terminal durch ist, antwortet die
Statusabfrage `9011`. Das `'0'`-Fenster ist genau die Ausführungsdauer des
Voids — nicht eine Verzögerung danach. Wer nach einem abgerissenen
Void-Request `'0'` sieht, sieht also entweder einen Void, der nie ankam, oder
einen, der noch läuft.

## 9900: eine nicht rein numerische Kennung

Am 27.08.2026 zunächst falsch gedeutet: eine Serie von Statusabfragen lieferte
`9900 "Technical Error Database"` auf genehmigte, abgelehnte, abgebrochene und
nie existierende Vorgänge gleichermaßen — das sah zuerst nach einem defekten
Gerät aus (die Diagnose blieb dabei `IN_OPERATION`, nichts warnte). Weiter
gemessen zeigte sich der wahre Zusammenhang:

| Kennung | Antwort |
|---|---|
| `999999999999999999` (rein numerisch) | `9027` Original Tx not found |
| `888888888888` (rein numerisch) | `9027` Original Tx not found |
| `GIBTESNICHT999` | `9900` Technical Error Database |
| `A1787860907` | `9900` Technical Error Database |
| `X999999999` | `9900` Technical Error Database |

**Nicht die Statusabfrage ist krank, sondern die Kennung war es.** Rein
numerisch → die erwartbare Antwort (`9027` oder `0`). Mit Buchstaben →
`9900`, unabhängig davon, was unter der Kennung tatsächlich geschah.

Wichtig zur Einordnung: **die HPS-Schnittstelle verlangt laut hobex-Dokumentation
schon immer eine numerische Kennung.** Das Paket hat bis zu dieser Messung nur
die Länge geprüft und Buchstaben klaglos durchgelassen — es ließ Aufrufer also
einen dokumentierten Vertrag verletzen, ohne dass irgendetwas widersprach.

Was das Verletzen kostet, ist schlimmer als ein Gerätedefekt: bei einer
**echten** Kartenzahlung mit der Kennung `A1787860907` hat das Terminal die
Anfrage angenommen, die Karte verarbeitet (`panEntryMode: CTLS`, PAN gelesen,
Kryptogramm vorhanden, `transactionType: SELL`) — und danach `9900` geliefert.
Der Vorgang ist seither **dauerhaft** nicht mehr auffindbar; jede weitere
Statusabfrage darauf liefert wieder `9900`. Ob beim Host autorisiert wurde,
lässt sich nie mehr klären. Erst wird das Geld bewegt, dann der Nachweis
vernichtet — der Vorfall vom 24.08.2026 in Reinform, nur ausgelöst durch einen
Eingabewert statt durch eine ausbleibende Antwort.

Das Risiko dafür ist in der Praxis **gering, nicht abstrakt**: jeder Erzeuger
im Ökosystem liefert bereits rein numerische Kennungen
(`HpsClient.newTransactionId()`, `Order.createTransactionId()` in sastre, der
JS-Zwilling). Der Fall greift nur, wenn ein Aufrufer eine EIGENE Kennung
übergibt — das erlaubt `CreditCardProvider.custom` ausdrücklich. Die Prüfung
schließt eine Fußangel, sie behebt keinen Dauerbrand.

**Zwei Korrekturen im Code, die zusammengehören, aber unabhängig begründet
sind:**

1. Der Client prüft die Kennung jetzt auf reine Ziffern, an derselben Stelle
   und mit derselben Härte wie die Längenprüfung (`HpsClient`, `ArgumentError`,
   bevor irgendetwas hinausgeht) — für `transactionId` **und**
   `originalTransactionId`. Das setzt den dokumentierten Vertrag durch und
   verhindert `9900` für jede Kennung, die dieser Client selbst erzeugt oder
   entgegennimmt.
2. Unabhängig davon — der Grund ist nicht `9900` selbst, sondern die Denkweise
   dahinter — galt bis dahin `TransactionResponse.isConclusive` für
   **jeden** Code außer `null` und `9027` — eine Positivliste, die sich als
   Negativliste ausgab und unterstellte, alle nicht-aussagekräftigen Codes zu
   kennen. `9900` war darüber schlüssig, und der Klärweg machte daraus
   `declined` für einen Vorgang, unter dem tatsächlich Geld geflossen sein
   kann. Seit dieser Messung ist `isConclusive` eine echte Positivliste: nur
   ein **gemessener und benannter** Code (`0`, `9011`, `100002`, `100003`,
   `100010`) gilt als Aussage; jeder andere — auch ein zukünftiger, heute noch
   unbekannter Code — ist eine Wissenslücke und führt zu `unresolved`. `9900`
   selbst ist jetzt benannt (`TransactionResponse.technicalErrorCode`), zählt
   aber ausdrücklich NICHT als Aussage über den Vorgang.

Ungemessen bleibt, ob `9900` **ausschließlich** bei einer nicht rein
numerischen Kennung auftritt, oder ob dieselbe Meldung auch andere Ursachen
haben kann — der Name "Technical Error Database" legt einen allgemeineren
Fehler nahe. Gemessen ist nur der eine Zusammenhang oben; der Nachweistext im
Zahlweg behauptet deshalb keine Ursache, wenn `9900` auftritt.

## `9002`: ein ungültiger Vorgang — und der Unterschied zu `9900`

Am 27.08.2026 dieselbe Lage wie oben, aber mit **rein numerischer** Kennung:
eine Gutschrift auf eine unbekannte, rein numerische Original-Kennung
antwortet nach 1,2 Sekunden mit `9002 "Invalid Transaction"` — kein
Kartenfluss, keine Auszahlung, die Karte wurde nie angefordert.

**Das ist die Kontrollprobe zu `9900`.** Dieselbe Anfrage, einmal mit einer
Kennung voller Buchstaben (→ `9900`, das Terminal kommt über die Kennung
selbst nicht hinaus) und einmal mit einer rein numerischen, aber unbekannten
Kennung (→ `9002`, das Terminal prüft die Kennung und weist den Vorgang als
ungültig ab). Zwei verschiedene Codes für zwei verschiedene Gründe des
Scheiterns — und ein Beleg dafür, warum die Umkehrung von `isConclusive`
nötig war: `9002` war vor dieser Messung ebenso unbenannt wie `9900`, und die
alte Fassung hätte auch ihn blind als Aussage gelesen (richtigerweise, wie
sich zeigt — aber aus dem falschen Grund: nicht weil er gemessen war, sondern
weil er zufällig nicht `9027` war).

Anders als `9027` ("ich habe dazu keinen Eintrag") und `9900` ("technischer
Fehler, keine Aussage") ist `9002` eine **positive** Aussage: das Terminal hat
den Vorgang selbst als unzulässig verworfen, bevor irgendetwas in Bewegung
kam. `9002` gehört deshalb in die Positivliste (`isConclusive`) und führt zu
`declined`.

## HTTP `409`: „Terminal is busy" ist jetzt ein eigener, benannter Fall

Ergänzend zur Messung unter „Das Terminal serialisiert" oben: läuft bereits
ein Vorgang und wird ein zweiter gestartet, kommt `409` nach **87
Millisekunden**. Der abgewiesene Vorgang hinterlässt **keine Spur** — die
Statusabfrage auf seine Kennung liefert `9027`, zweimal geprüft. Es wurde
nichts angelegt und kein Kartenfluss gestartet.

Die früher offene Entwurfsfrage („als `declined` wäre sie schneller und immer
noch korrekt") ist damit entschieden: `HpsPayments` liest ein `409` auf die
**erzeugende** Anfrage (Zahlung, Gutschrift, der direkte Aufhebungs-Request)
jetzt als `declined`, ohne erst einen Abbruch zu versuchen oder zu pollen —
die Statusabfrage würde ohnehin nur den ohnehin schon bekannten Befund `9027`
liefern.

**Wichtig, weil `409` auf einer anderen Ebene liegt als ein `responseCode`:**
Es ist ein HTTP-Status, kein Feld im Antwortrumpf — er entsteht, bevor
überhaupt ein Rumpf gelesen wird. Er gehört deshalb **nicht** in
`TransactionResponse.isConclusive`, sondern in eine eigene, davon getrennte
Prüfung (`HpsHttpException.isTerminalBusy`, ausgewertet in `HpsPayments`).

Und die positive Aussage gilt **ausdrücklich nur für die erzeugende Anfrage**:
ein `409` auf einen `abort`-Versuch oder auf eine Statusabfrage während der
Klärung sagt nur, dass DIESE Anfrage nicht durchkam — nichts über den
Vorgang, den sie klären sollte (siehe die Messung zum Polling-Backoff oben,
"ein parallel abgesetzter Void kam gar nicht durch"). Dort bleibt `409` ein
gewöhnlicher Transportfehler, unverändert.

## Der gemessene Stand, auf einen Blick

Alle bisher gemessenen und im Code benannten Ausgänge (Stand 27.08.2026, TID
3600335, HPS 1.10.0, Firmware 7.3.6):

`0` genehmigt · `9002` ungültiger Vorgang · `9011` aufgehoben · `9027` keine
Aussage · `9900` Kennung nicht numerisch · `100002` abgebrochen · `100003`
Karte nicht aufgelegt · `100010` nicht abbrechbar · HTTP `409` Terminal
beschäftigt.

Jeder andere Code ist eine Wissenslücke, keine Aussage — siehe
`TransactionResponse.isConclusive`.

## Weitere Messwerte

- **Void ohne `amount`** → `HTTP 400 "Missing amount"`. Der Pflichtparameter ist
  richtig, auch wenn die REST-Spezifikation ihn nicht führt.
- Ein Void erzeugt eine **eigene** neue `transactionId` und verweist über
  `originalTransactionId` auf die Zahlung.
- **`/api/terminals`** → `404 Endpoint not implemented`. Die `terminals()`-Methode
  läuft auf dieser Firmware ins Leere.
- Das Diagnose-Feld **`transactionId` bleibt auch während eines laufenden
  Kartenflusses `null`** — als Unterscheidungshilfe unbrauchbar.
- Die Diagnose ist ein brauchbarer, folgenloser Erreichbarkeitstest:
  `deviceStatus`, Firmware, HPS-Version, Autorisierungshost.

## Was weiterhin ungemessen ist

- Was ein leerer `200`-Rumpf bedeutet.
- Ob `9900` ausschließlich bei einer nicht rein numerischen Kennung auftritt,
  oder ob dieselbe Meldung noch andere Ursachen hat (siehe oben).
- Wie lange das Terminal eine genehmigte Transaktion abrufbar hält.
- Das Verhalten einer echten Ablehnung (Deckung, gesperrte Karte) — deshalb
  hat `TransactionResponse.isConclusive` dafür (noch) keinen benannten Code.

## Selbst nachmessen

Alles Folgende ist folgenlos und braucht keine Karte:

```bash
T=<ip>:8080; TID=<tid>

# Erreichbarkeit, Firmware, Autorisierungshost
curl -s "http://$T/api/terminals/$TID/diagnosis"

# Was sagt der Status zu einer unbekannten Kennung?
curl -s "http://$T/api/v2/transactions/$TID/999999999999999999"

# Zahlung starten und abbrechen, ohne Karte aufzulegen
curl -s -X POST "http://$T/api/transaction/payment" -H 'Content-Type: application/json' \
  -d "{\"transaction\":{\"tid\":\"$TID\",\"amount\":0.01,\"currency\":\"EUR\",\"transactionType\":1,\"transactionId\":\"260101120000\"}}" &
sleep 4
curl -s -X POST "http://$T/api/transaction/abort/$TID/260101120000"
```

Für alles Weitere — genehmigte Zahlung, Abbruch nach Kartenvorlage, Void — muss
jemand mit einer Karte am Gerät stehen. Kleine Beträge nehmen und am Testsystem
bleiben (`diagnosis` zeigt den Autorisierungshost; `tecstest` ist Test,
alles andere ist es nicht).
