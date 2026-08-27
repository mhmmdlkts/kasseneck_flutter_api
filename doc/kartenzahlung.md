# Kartenzahlung: was das Terminal tatsächlich tut

Stand 26.08.2026. Diese Datei hält fest, was am echten Gerät **gemessen** wurde —
nicht, was die Dokumentation verspricht. Zwei Annahmen, die plausibel klangen und
drei Code-Reviews überstanden haben, sind an der Messung gescheitert.

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

Offen zur Entscheidung: `409 "Terminal is busy"` heißt streng genommen
„ich habe diese Anfrage **nicht angenommen**" — eine Aussage, kein Nichtwissen.
Für die abgewiesene Anfrage ist damit nachweislich nichts belastet. Derzeit
behandelt der Code sie wie einen Transportfehler; als `declined` wäre sie
schneller und immer noch korrekt.

### Nach einem gelandeten Void schlägt der Status sofort um

Kein Nachlauf: Sobald der Void am Terminal durch ist, antwortet die
Statusabfrage `9011`. Das `'0'`-Fenster ist genau die Ausführungsdauer des
Voids — nicht eine Verzögerung danach. Wer nach einem abgerissenen
Void-Request `'0'` sieht, sieht also entweder einen Void, der nie ankam, oder
einen, der noch läuft.

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
- Ob eine nicht rein numerische Kennung angenommen wird (der Client prüft
  derzeit nur die Länge ≤ 18).
- Wie lange das Terminal eine genehmigte Transaktion abrufbar hält.
- Das Verhalten einer echten Ablehnung (Deckung, gesperrte Karte).

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
