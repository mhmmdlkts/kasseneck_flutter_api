# Kartenzahlung: was das Terminal tatsächlich tut

Stand 02.09.2026. Diese Datei hält fest, was am echten Gerät **gemessen** wurde —
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
| Kartenfluss wartet auf die Karte | (offen) | `9027` | `0`, die Zahlung endet `100002` |
| Abbruch 4 s nach dem Start einer kontaktlosen Zahlung (10.11.2026; ob die Karte schon gelesen war, ist ungemessen) | (offen), endet `0` Genehmigt | danach `0` Genehmigt | `0` „Authorized“ – **greift nicht** |
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

### Ein quittierter Abbruch ist keine Aussage (10.11.2026)

Bis 11.26.0 galt hier: der Abbruch gelingt (`0`), solange der Vorgang
abbrechbar ist, und scheitert mit `100010`, sobald er abgeschlossen ist – also
heißt `0` „nichts belastet“. Gemessen war das am 26.08.2026 an einem Abbruch,
der kam, während das Terminal noch auf die Karte wartete.

Am 10.11.2026 widerlegt, Testterminal 3600335, HPS 1.14.4, Firmware 7.3.6,
Testsystem `tecstest.hobex.at`:

1. Zahlung über 0,01 € gestartet (`POST /api/transaction/payment`).
2. Nach 4 s `POST /api/transaction/abort/3600335/<kennung>`, Antwort nach
   0,18 s: HTTP 200, `{"responseCode":"0","responseText":"Authorized",…}`.
3. Die laufende Zahlung endete trotzdem **genehmigt** (kontaktlos).
4. Die Statusabfrage danach: genehmigt.

`0` auf den Abbruch heißt also nur, dass das Terminal die Anfrage angenommen
hat. Ob die Zahlung danach abbricht, sagt es nicht. Als `declined` gelesen,
hätte die Kasse „nichts belastet, noch einmal versuchen“ gemeldet – für eine
belastete Karte, also der Weg zur Doppelbelastung vom 24.08.2026.

Auch ein `9027` kurz nach einem angenommenen Abbruch beweist nichts: solange
eine Zahlung läuft, antwortet die Statusabfrage `9027` (Tabelle oben), und die
Messung zeigt, dass sie nach dem Abbruch weiterlaufen kann. Wie lange danach
noch eine Genehmigung kommen kann, ist **ungemessen**.

**Falle, unverändert:** Das Terminal meldet auch das Scheitern des Abbruchs mit
**HTTP 200** (`100010` im Rumpf). Den Ausgang liest man nie am Abbruch ab.

### Der Klärweg, der daraus folgt

Bleibt die Antwort auf eine Zahlung aus oder sagt sie nichts:

1. **`abort` einmalig versuchen.** Die Absicht: ein Kartenfluss, der noch auf
   die Karte wartet, soll enden, damit nach der Klärung keine spät aufgelegte
   Karte mehr belastet wird. Eine Garantie ist das nicht, ob der Abbruch
   greift, sagt seine Quittung nicht.
2. Die Antwort auf den Abbruch **entscheidet nichts**, auch `0` nicht. Sie
   steht nur im Nachweis (`steps`).
3. Dann `transactionStatus` pollen: `0` → **`approved`**, mit der Antwort des
   Status als Beleg; ein schlüssiger Code (etwa `9011` aufgehoben) →
   **`declined`**.
4. Beim Pollen ist `9027` **kein Ergebnis**: weiter klären. Nur wenn die Zahlung
   selbst mit einem Code beantwortet war, macht die Zwei-`9027`-Regel daraus
   `declined` (siehe unten). Budget erschöpft → `unresolved`.

Eine Zahlung ohne Antwort, ein angenommener Abbruch und ein Status, der bei
`9027` bleibt, enden damit bei `unresolved`, nicht mehr bei `declined`. Das
kostet im seltenen Fall eines Leitungsabrisses einen Blick auf den
Terminal-Beleg, statt ihn mit einer Behauptung zu ersparen.

Bricht die **Kasse** eine laufende Zahlung selbst ab (Abbrechen-Knopf, eigener
`abort`, während `pay` noch wartet), entscheidet die Antwort auf die Zahlung:
genehmigt, wenn sie genehmigt meldet, abgelehnt mit `100002`. `pay` liest die
Quittung dieses fremden Abbruchs nicht.

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
und die Gutschrift endete am 26.08.2026 mit `100002 Aborted`. Der Klärweg oben
gilt dort unverändert – auch darin, dass die Quittung allein nichts beweist:
eine Gutschrift, die nach dem angenommenen Abbruch doch durchgeht, als
`declined` zu melden, lädt zu einer zweiten Gutschrift ein.

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

## `55`: die erste echte Host-Ablehnung (02.09.2026, Betrieb)

Bis dahin war „echte Ablehnung" (Deckung, gesperrte Karte, falsche PIN)
ausdrücklich ungemessen — das Testgerät wird per Apple Pay bedient, eine
ablehnende Karte stand nie zur Verfügung. Am 02.09.2026 lieferte der Betrieb
die Messung von selbst: Produktivterminal TID `3556988`, HPS `1.11.4`,
Firmware `2.3.9`.

| Schritt | Antwort |
|---|---|
| Zahlung, direkte Antwort | `55` „PIN falsch" |
| `abort` | HTTP `404` |
| Statusabfrage, elfmal über 90 s | `55` „PIN falsch", jedes Mal |

Drei Befunde:

1. **Ein Host-Code ist zweistellig.** `55` ist der ISO-8583-Antwortcode des
   Autorisierungshosts („Incorrect PIN"), kein `9xxx`-Terminalcode und kein
   `100xxx`-Code der HPS-Anwendung. In dieser Klasse sind die
   Alltagsablehnungen (Deckung, gesperrt, abgelaufen) zu erwarten.
2. **Eine Host-Ablehnung wird aufbewahrt.** Anders als nach `100002`/`100003`
   (Status danach `9027`, siehe oben) antwortet die Statusabfrage mit
   demselben Code wie die Zahlung — dauerhaft. Der Vorgang steht mit seinem
   Ablehnungsgrund im Terminal.
3. **Kein Familienschluss.** Aus einem gemessenen zweistelligen Code folgt
   keine Regel für die anderen: ISO 8583 führt in derselben Familie
   Genehmigungen (`08`, `10`, `11`, `85`). Jeder weitere Host-Code bleibt eine
   Wissenslücke, bis er gemessen ist. Die Zwei-`9027`-Regel aus 5.2.0 fängt
   ihn nicht: der Status antwortet nicht `9027`, sondern mit dem Code selbst
   — er endet also weiterhin bei `unresolved`.

Was der Fall ohne den Eintrag gekostet hat: 90 s Klärung ins Budget, ein
Vorfall mit ungeklärtem Ausgang, ein stehender Merker und eine Rückfrage an
den Bediener — für eine falsch getippte PIN.

**Nebenbefund zum Abbruch auf dieser Firmware:** `abort` auf einen bereits
beendeten Vorgang antwortet am Produktivterminal mit HTTP `404`, nicht mit
`100010` wie am Testgerät — fünf Vorfälle vom 28.08. bis 02.09.2026, alle
nach einer Antwort mit Ergebniscode. Die Fähigkeitsprobe der App auf eine nie
gesehene Kennung bekommt dort keinen 404, der Endpunkt existiert also. Was 404
auf einen LAUFENDEN Vorgang heißt, ist ungemessen; der Nachweistext behauptet
deshalb weiterhin keine Ursache.

## Die Antwortcodeliste von hobex (11.09.2026)

Am 11.09.2026 kam von hobex die Liste der `100xxx`-Codes der HPS-Anwendung,
jeweils mit Titel und einem Satz Beschreibung. Sie beantwortet die offene Frage
aus `befunde-fuer-hobex.md` (Abschnitt 8) nach `100004`, `100005` und
`100015`, bestätigt fünf gemessene Codes und benennt 23, die an keinem Gerät
aufgetreten sind.

Die Liste ist eine Beschreibung des Herstellers, keine Messung. Sie ändert
deshalb nichts an der Regel, dass nur ein Code mit feststehender Bedeutung
einen Ausgang festschreibt — sie erweitert nur, was feststeht. Ein Code, der
weder gemessen noch von hobex beschrieben ist, bleibt eine Wissenslücke.

Eingeordnet wird danach, **wo im Ablauf** der Code entsteht:

| Wo | Codes | Ausgang |
|---|---|---|
| vor dem Host: Anfrage, Karte, EMV-Kernel, Eingaben, Gerätezustand | `100001`–`100005`, `100008`, `100009`, `100012`–`100015`, `100017`–`100022`, `100025`, `100028`, `100998` | abgelehnt, nichts belastet |
| Zeitüberschreitung zum Host, **mit** auto-reversal | `100029` | abgelehnt, das Terminal storniert selbst |
| beim oder nach dem Host, **ohne** auto-reversal | `100006`, `100007`, `100023`, `100024`, `100026`, `100027` | ungewiss |
| Sammelcode, an jeder Stelle möglich | `100999` | ungewiss |
| „Not Found“ | `100011` | keine Aussage |
| Abbruch nicht möglich | `100010` | wie gemessen |

**„Ungewiss“ ist eine eigene Wirkung, nicht dasselbe wie „keine Aussage“.**
Bei diesen Codes war der Host beteiligt, und hobex vermerkt bei `100006` und
`100007` ausdrücklich, dass das Terminal **nicht** selbst storniert. Die
Statusabfrage spiegelt aber nur den Speicher des Terminals. Antwortet sie
danach `9027`, heißt das: das Terminal hat nichts gespeichert. Ob der Host
belastet hat, sagt es nicht. Die Zwei-`9027`-Regel, die sonst aus einer
Antwort mit Code plus zweimal `9027` „nichts belastet“ schließt, greift für
diese Codes deshalb nicht. Die Klärung endet nach zwei Abfragen ohne Neues als
`unresolved`, statt 90 Sekunden zu warten. Meldet der Status doch `0`, gilt die
Genehmigung; jede andere Aussage des Terminals entscheidet danach nichts mehr.
Ein Abbruchversuch entfällt: der Vorgang ist am Terminal schon beendet, ein
quittierter Abbruch bewiese nichts über den Host.

**Eine abgewiesene Anfrage ist keine Aussage über einen anderen Vorgang.**
Zehn Codes weisen die Anfrage selbst ab (`9002`, `100001`, `100008`, `100108`,
`100009`, `100010`, `100013`, `100018`, `100022`, `100998`). Auf eine Zahlung
sind sie deren Ablehnung. Auf eine Statusabfrage heißen sie nur, dass diese
Abfrage nicht bedient wurde — gemessen für `100108`, das die Statusabfrage mit
falscher TID liefert. Die Klärung liest den Status deshalb über
`TransactionResponse.isConclusiveAsStatus`. Sonst hätte ein gesperrtes
Terminal (`100022`) eine verlorene Zahlung als „nicht belastet“ ausgewiesen.

Dasselbe gilt für eine Aufhebung, die mit einem solchen Code endet: ein
unverändertes `0` auf die Originalzahlung beweist dann nicht, dass die
Aufhebung beim Host nicht ankam. „Hat nicht gegriffen“ würde nach dem
Tagesabschluss zu einer Rückerstattung führen, die der Kunde doppelt bekäme.

**Zwei Abweichungen zur Messung, beide bewusst stehen gelassen:**

- Für eine falsche TID nennt hobex `100008`, gemessen wurde am Gerät 3600335
  `100108`. Beide stehen in der Tabelle.
- `409 Terminal is busy` kam gemessen als HTTP-Status mit Textrumpf. hobex
  führt denselben Titel als `100998`. Beide werden als „beschäftigt, nichts
  belastet“ gelesen.

Zu jedem Code gehört ein **Grund** (`HpsCodeReason`) mit einem Satz für den
Bediener. Mehrere Codes teilen sich einen Grund, wenn am Tresen dasselbe zu tun
ist. `HpsResult.reason` trägt ihn für jeden Ausgang, an der Stelle gesetzt, die
entschieden hat: ein bestätigter Abbruch antwortet `0` und ist trotzdem
„abgebrochen“.

Die vollständige Tabelle steht in `lib/src/hobex_hps/response_codes.dart`
(`HpsCodes.all`) und im npm-Zwilling als `HPS_CODES`, festgenagelt über
`fixtures/hobex-hps-codes.json`.

## Die TECS-Liste (16.09.2026)

Nachgereicht von hobex auf die Frage nach `9908` und den Host-Codes: das HPS
reicht die Antwortcodes der TECS-Plattform durch, auf der hobex autorisiert
(„Fehlercodes ist aktuell gleich Tecs NaTALI. Hier hat sich bei HPS noch
nichts geändert“). Die Liste führt rund 330 Codes. Sechs davon waren schon
gemessen, ohne dass wir ihre Herkunft kannten: `0`, `9002`, `9003`, `9011`,
`9027`, `9900` — und `55` als `0055`.

**Schreibweise.** TECS führt die ISO-8583-Antworten des Hosts vierstellig
(`0055`), das Terminal sendet sie ohne führende Nullen (`55`, gemessen). Die
Tabelle führt die Form des Terminals, `HpsCodes.normalize` bzw.
`normalizeHpsCode` gleicht beim Einlesen an. Ohne das wäre ein `0000` keine
Genehmigung, sondern über die Positivliste eine Ablehnung.

Eingeordnet nach derselben Regel wie die HPS-Liste — **wo der Code entsteht**:

| Lage | Beispiele | Ausgang |
|---|---|---|
| Antwort des Hosts ohne Genehmigung | `5`, `14`, `33`, `43`, `51`, `54`, `55`, `57`, `61`, `75`, `77`, `91`, `96` | abgelehnt, nichts belastet |
| Abweisung vor der Weiterleitung (Anfrage, Terminal, Risikoprüfung) | `3018`, `3019`, `81xx`, `9001`, `9004`, `9009`, `6000`–`6003` | abgelehnt |
| vom System selbst storniert | `3053`, `9032`, `8009` | abgelehnt |
| **Genehmigung, die nicht `0` ist** | `8`, `10` (Teilbetrag), `11`, `16`, `32` | ungewiss, **nie** abgelehnt |
| **keine oder keine brauchbare Host-Antwort** | `9`, `20`, `22`, `68`, `81`, `94`, `5274`–`5278`, `8006`, `8008`, `8010`, `8016`, `9006`, `9007`, `9022`, `9905`–`9909` | ungewiss, **Storno wird nachgeschickt** |
| interner Fehler im Backend | `3036`, `5127`, `5256`, `8999`, `9900`–`9902` | ungewiss |
| andere TECS-Produkte (Webservices, mPOS, TecsWeb, SEPA) | `35xx`, `36xx`, `40xx`, `70xx`, `85xx`, `9024`, `30091`–`30099` | keine Aussage |

**Storno nach ausbleibender Host-Antwort.** Zu `9908` schreibt hobex: „ein
Timeout wie jeder andere. Richtigerweise sollte in dem Fall ein Storno
nachgeschickt werden.“ Dasselbe gilt für die HPS-Codes, bei denen hobex „No
auto-reversal“ vermerkt (`100006`, `100007`) und die übrigen ungewissen
Host-Codes der HPS-Liste (`100023`, `100024`, `100026`, `100027`).
`HpsCode.sendReversal` markiert sie; `HpsPayments.pay` schickt dann **genau
einmal** einen Void mit der Kennung der Zahlung und dem Betrag, den das
Terminal belastet hat – Betrag **und** Trinkgeld, wie die Rückbuchung der
Web-Kasse. Danach läuft immer die Statusabfrage (Stand 10.11.2026):

- Status `9011` → `declined`, Grund `voidedAfterHostFault`. Nur so schreibt
  das Storno einen Ausgang fest.
- Die Quittung `0` auf den Void beweist allein nichts – dieselbe Lehre wie
  beim Abbruch. Hat der Void womöglich gewirkt (quittiert, abgerissen, ohne
  oder mit unbekanntem Code), ist auch `0` im Status keine Aussage: der Void
  kann noch unterwegs sein oder nicht gegriffen haben. Zweimal ohne Neues
  (`0` oder `9027`) → `unresolved`.
- Nur wenn der Void nach einer ausdrücklichen Positivliste nicht ausgeführt
  wurde, gilt `0` im Status als Genehmigung: nicht angenommen (HTTP 409) oder
  abgewiesen mit einem Code, der die Anfrage selbst abweist
  (`rejectsRequest`), die Aufhebung ablehnt (`cancelDenied`: `9023`, `9222`)
  oder den Betrag ablehnt (`amountInvalid`). Gemessen ist davon nur `9002`
  auf eine unbekannte Kennung (27.08.2026), der Rest stützt sich auf die
  Codelisten von hobex und TECS. Ein Code, der selbst „storniert“ heißt
  (`8009`, `100029`, `3053`–`3063`, `9032`, `9011`), ein Abbruch-Code und
  jede Host-Ablehnung zählen nicht dazu: der Void kann gewirkt haben, und
  `0` im Status bleibt `unresolved`. Zeigt der Status `9011`, obwohl der
  Void nicht ausgeführt wurde, ist die Zahlung trotzdem aufgehoben
  (`declined`, Grund `canceled`).

Bis 11.26.0 hieß die Quittung `0` sofort `declined`. Das ist zurückgenommen:
die Kasse hätte „nichts belastet“ gemeldet, ohne dass der Status es zeigt.
**Am Gerät ungemessen** ist, wie das Terminal einen Void nach einem
Host-Timeout beantwortet und ob es den Betrag samt Trinkgeld so erwartet;
gemessen ist nur `0` auf eine bestehende und `9002` auf eine unbekannte
Kennung. Eine Gutschrift bekommt kein Storno — TECS lässt ihre Aufhebung
nicht zu (`9031`).

**Zwei Einordnungen, die vom ersten Blick abweichen:**

- `9900` war als „keine Aussage“ geführt. Gemessen kam er aber, **nachdem**
  die Karte verarbeitet war, und der Vorgang blieb unauffindbar; TECS nennt
  ihn einen Datenbankfehler im Backend. Als „keine Aussage“ hätte die
  Zwei-`9027`-Regel daraus „nichts belastet“ gemacht. Jetzt: ungewiss.
- `9033` („Original TX declined – cannot cancel“) antwortet auf eine
  Aufhebung. Als Ablehnung gelesen hieße das „Aufhebung hat nicht gegriffen,
  weiter belastet“ — für eine Zahlung, die nie belastet war. Jetzt: keine
  Aussage, Grund `originalDeclined`.

Neue Gründe: `approvedWithCondition`, `issuerDeclined`, `cardBlocked`,
`cardExpired`, `insufficientFunds`, `pinTriesExceeded`, `pinRequired`,
`acquirerSetup`, `hostRejected`, `hostUnavailable`, `refundRejected`,
`reversedByHost`, `voidedAfterHostFault`, `hostTimeout`, `cancelDenied`,
`originalDeclined`. Eine Kasse mit eigener Übersetzung braucht für jeden
einen Text.

Die Tabelle steht in `lib/src/hobex_hps/tecs_codes.dart` (eine Zeile je
Code) und im npm-Zwilling in `src/payments/hobex-hps/tecs-codes.ts`.

## Der gemessene Stand, auf einen Blick

Alle bisher gemessenen und im Code benannten Ausgänge (Stand 27.08.2026, TID
3600335, HPS 1.10.0, Firmware 7.3.6):

`0` genehmigt · `9002` ungültiger Vorgang · `9011` aufgehoben · `9027` keine
Aussage · `9900` Kennung nicht numerisch · `100002` abgebrochen · `100003`
Karte nicht aufgelegt · `100010` nicht abbrechbar · HTTP `409` Terminal
beschäftigt · `55` PIN falsch (Host-Ablehnung; Produktivterminal `3556988`,
Firmware 2.3.9, 02.09.2026).

Dazu kommen seit 11.09.2026 die Codes aus der Antwortcodeliste von hobex
(siehe oben). Jeder andere Code ist eine Wissenslücke, keine Aussage — siehe
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
- Andere Host-Ablehnungen als `55` (Deckung, gesperrte Karte, abgelaufen) —
  gemessen ist nur die falsche PIN. Seit 16.09.2026 sind sie über die
  TECS-Liste benannt, aber an keinem Gerät gesehen.
- Wie das Terminal ein nachgeschicktes Storno nach `9908` beantwortet, und ob
  es einen Vorgang mit Host-Timeout überhaupt aufbewahrt.
- Welche der „ungewissen“ Codes (`100006` usw.) die Statusabfrage danach
  aufbewahrt, und ob `100029` die Stornierung wirklich immer durchbringt.
  Keiner davon ist bisher an einem Gerät aufgetreten.
- Was HTTP `404` beim `abort` auf einen LAUFENDEN Vorgang heißt (Firmware
  2.3.9, siehe oben).
- Wie lange nach einem angenommenen Abbruch (`0`) eine Zahlung noch genehmigt
  werden kann, und ob es einen Aufruf gibt, der sicher sagt, dass am Terminal
  nichts mehr läuft. Erst damit ließe sich ein anhaltendes `9027` nach dem
  Abbruch als „nichts belastet“ lesen.

## TID nur ohne führende Null (10.11.2026)

Auf Beleg und Gerät steht die TID achtstellig mit führender Null (`03600335`).
Das HPS nimmt sie nur ohne an: `GET /api/terminals/03600335/diagnosis` und eine
Zahlung mit `"tid":"03600335"` antworten sofort `100108 "Invalid TID"`, es wird
nichts belastet; `003600335`, `0360033` und `36003350` ebenso. `HpsClient`
entfernt deshalb Leerraum am Rand und führende Nullen, aber nur bei einer rein
ziffrigen TID mit mindestens einer Ziffer ungleich `0` – alles andere geht
unverändert hinaus. Dieselbe Regel gilt im npm-Zwilling (`normalizeHpsTid`),
die Prüffälle stehen im Vertrag `hobex-hps-cases.json`.

## Selbst nachmessen

Alles Folgende ist folgenlos und braucht keine Karte:

```bash
T=<ip>:8080; TID=<tid ohne führende Null>  # 3600335, nicht 03600335

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
