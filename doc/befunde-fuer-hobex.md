# Befunde am HPS-Terminal — zur Weitergabe an hobex

Gemessen am 27.08.2026 an einem hobex-HPS im lokalen Netz.

**Gerät:** TID 3600335 · HPS 1.10.0 · Firmware 7.3.6 · Paket 1.11.1-20260706073501
· Autorisierungshost `tecstest.hobex.at` (Testsystem) · Gerätestatus durchgehend
`IN_OPERATION`, Diagnose `responseCode 0`.

Diese Datei ist als Grundlage für eine Rückmeldung an hobex gedacht. Sie
enthält nur Beobachtungen und keine Vermutungen über Ursachen im Terminal.

---

## 1. Eine nicht-numerische `transactionId` wird erst nach der Kartenverarbeitung abgewiesen

**Das ist der gewichtigste Befund.**

Wird eine Zahlung mit einer Transaktionskennung gestartet, die Buchstaben
enthält (z. B. `A1787860907`), dann

1. nimmt das Terminal die Anfrage an,
2. **verarbeitet die Karte** — die Antwort enthält `panEntryMode: CTLS`, die
   maskierte Kartennummer, das Ablaufdatum und ein Kryptogramm,
   `transactionType: SELL`,
3. und liefert erst danach `responseCode 9900` / `Technical Error Database`.

Der Vorgang ist anschließend über `GET /api/v2/transactions/{tid}/{txid}`
**dauerhaft nicht mehr auffindbar** — jede Abfrage liefert erneut `9900`.

Für ein Kassensystem ist das die ungünstigste Reihenfolge: die Karte war in
der Hand des Terminals, und der einzige Faden zum Vorgang ist danach zerstört.
Ob beim Autorisierungshost etwas gebucht wurde, lässt sich von außen nicht
mehr klären.

**Gegenprobe, identische Karte und identischer Betrag, nur numerische
Kennung:** `responseCode 0` / `Genehmigt`, mit Genehmigungscode und
Belegnummer.

**Frage an hobex:** Welches Zeichenformat ist für `transactionId` zulässig?
Wäre eine Abweisung **vor** der Kartenverarbeitung möglich (analog zu
`100019` bei ungültigem Betrag)?

---

## 2. Führende Nullen werden normalisiert

`1787863085110`, `01787863085110` und `000001787863085110` liefern bei der
Statusabfrage **denselben** Vorgang, mit identischem `approvalCode`.

Zwei Kennungen, die sich nur in führenden Nullen unterscheiden, sind am
Terminal also dieselbe Transaktion. Für aufrufende Systeme, die Kennungen mit
Nullen auffüllen, ist das eine Kollisionsgefahr.

**Frage:** Ist die Normalisierung beabsichtigt und dokumentiert?

---

## 3. Ein zweiter Void meldet Erfolg wie der erste

| Aufruf | Antwort |
|---|---|
| Void auf eine genehmigte Zahlung | `0` / `Genehmigt` |
| Void auf dieselbe, bereits aufgehobene Zahlung | `0` / `Tx Canceled` |

Der `responseCode` ist in beiden Fällen `0`; nur der `responseText`
unterscheidet sich. Wer nur den Code auswertet, kann „ich habe eben
aufgehoben" nicht von „war längst aufgehoben" unterscheiden.

Ergänzend: ein Void mit **falschem Betrag** (9,99 € statt 0,01 €) wurde
ebenfalls mit `0` / `Tx Canceled` beantwortet — der Betrag wird offenbar
nicht gegen die Originalzahlung geprüft.

**Frage:** Ist ein eigener Code für „bereits aufgehoben" vorgesehen?

---

## 4. `9027` deckt vier verschiedene Lagen ab

`Original Tx not found` antwortet gleichermaßen auf

- eine nie gesehene Kennung,
- einen gerade laufenden Kartenfluss,
- einen abgebrochenen Vorgang,
- eine Zahlung, bei der die Karte nicht aufgelegt wurde.

Für die Klärung eines Vorgangs mit ausgebliebener Antwort ist `9027` damit
keine Aussage, sondern eine Wissenslücke. Wir verwenden deshalb den Abbruch
als Unterscheidungsmerkmal: er gelingt (`0`), solange der Vorgang abbrechbar
ist, und scheitert (`100010`), sobald er abgeschlossen ist.

**Anmerkung:** Das Feld `state` ist auf dieser Firmware in **jeder** bisher
gesehenen Antwort `null` — auch bei genehmigten, abgebrochenen und
aufgehobenen Vorgängen. Es ist als Unterscheidungsmerkmal nicht nutzbar.

**Frage:** Gibt es einen vorgesehenen Weg, „läuft gerade" von „nie gesehen"
zu unterscheiden?

---

## 5. Die `reference` steht nicht im gespeicherten Datensatz

Eine mitgegebene `reference` wird in der **direkten** Antwort unverändert
zurückgegeben (geprüft mit 20 Zeichen). Die Statusabfrage zum selben Vorgang
liefert jedoch `reference: null`.

Ein Vorgang lässt sich damit nachträglich nicht über die Referenz
wiederfinden.

**Frage:** Ist das beabsichtigt?

---

## 6. Das Wartefenster für die Karte lässt sich über die Anfrage nicht steuern

Wird eine Zahlung gestartet und keine Karte aufgelegt, antwortet das Terminal
nach rund **63 Sekunden** mit `100003 "Card not present"`.

Ein Feld `timeout` im Transaktionsrumpf wird **ohne Fehlermeldung angenommen**
und hat keine Wirkung:

| Anfrage | Antwort nach |
|---|---|
| ohne `timeout` | 64,3 s |
| `"timeout": 180` | 63,5 s |

Für eine Kasse ist das Fenster relevant: eine Minute reicht am Automaten, an
der Theke mit Beratung nicht immer. Weil ein unbekanntes Feld stillschweigend
angenommen wird, lässt sich auch nicht erkennen, ob der Name nur falsch
geraten war.

**Frage:** Gibt es einen Weg, das Wartefenster zu setzen — über die Anfrage
oder als Geräteeinstellung? Und werden unbekannte Felder im
Transaktionsrumpf absichtlich ignoriert statt abgewiesen?

## 7. Ein Teil der Endpunkte antwortet mit „Endpoint not implemented"

Auf dem gemessenen Gerät (TID 3600335, 28.08.2026) beantwortet die HPS-API
die Transaktions- und Diagnosewege, aber nicht die Auflistung:

| Aufruf | Antwort |
|---|---|
| `GET /api/terminals` | **404** `Endpoint not implemented` |
| `GET /api/terminals/{tid}/status` | **404** |
| `GET /api`, `/api/status`, `/api/version`, `/api/info` | **404** |
| `GET /api/terminals/{tid}/diagnosis` | 200, vollständige Gerätedaten |
| `GET /api/terminals/0/diagnosis` | 200, `100108 "Invalid TID"` |
| `GET /api/terminals/{tid}/batchtotal/{seit}` | 200 |
| `GET /api/v2/transactions/{tid}/{txId}` | 200 |
| `POST /api/transaction/payment` / `abort` | 200 |

Auffällig ist das Paar: `/api/terminals/{tid}/diagnosis` arbeitet,
`/api/terminals/{tid}/status` daneben nicht.

Praktische Folge: eine Kasse kann die TID nicht am Gerät erfragen — sie muss
bei der Einrichtung von Hand eingetragen werden. Für die Erkennung im Netz
genügt `/api/terminals/0/diagnosis`, das ohne bekannte TID mit
`100108 "Invalid TID"` antwortet.

**Frage:** Sind `/api/terminals` und `/api/terminals/{tid}/status` in dieser
Firmware nicht enthalten, oder müssen sie freigeschaltet werden? Und gibt es
einen vorgesehenen Weg, die TID am Gerät abzufragen?

## Beobachtete Antwortcodes

| Code | Text | Lage |
|---|---|---|
| `0` | Genehmigt / Authorized / Tx Canceled | genehmigt bzw. gelungener Abbruch/Void |
| `9002` | Invalid Transaction | Gutschrift oder Void auf unbekannte Original-Kennung |
| `9011` | Transaction Canceled | Originalkennung nach erfolgreichem Void |
| `9027` | Original Tx not found | keine Auskunft (siehe 4.) |
| `9900` | Technical Error Database | Kennung nicht numerisch (siehe 1.) |
| `100002` | — | abgebrochen |
| `100003` | Card not present | Karte nicht aufgelegt (nach 63 s) |
| `100010` | Unable to abort transaction | Vorgang nicht mehr abbrechbar |
| `100019` | Amount is not in a valid range | negativer Betrag |
| `100108` | Invalid TID | falsche TID |
| HTTP 409 | Terminal is busy | zweiter Vorgang während eines laufenden; Abweisung nach 87 ms, keine Spur |
| HTTP 400 | Bad Request / Missing amount | fehlender Betrag, kein JSON |

**Ohne Vorabprüfung angenommen** (Kartenfluss startet, Fehler erst danach):
Währung `USD`, leere `transactionId`, Kennung mit Bindestrich, Kennung mit
19 Stellen.
