## 5.0.0

**Anlass:** Am 24.08.2026 wurde ein Kunde am Kartenterminal zweimal mit 25 € belastet. Die App meldete beide Male „Kartenzahlung fehlgeschlagen", bei hobex waren beide Vorgänge genehmigt. Ursache: `HpsClient.payment()` erzeugte die Transaktionskennung intern und gab sie erst mit der Antwort heraus — blieb die Antwort aus (Verbindungsabbruch, Frist), war die Kennung nie bekannt, und damit waren Statusabfrage und Storno strukturell unerreichbar. Jede Wiederholung wurde dadurch zwangsläufig ein zweiter, eigenständiger Vorgang. Dieses Release macht die Kennung zum ersten Schritt eines Zahlvorgangs statt zu dessen Nebenprodukt und ersetzt geratene Fehlschläge durch geklärte Ausgänge.

- **Zahlung, Rückerstattung und Aufhebung mit geklärtem Ausgang statt geratenem Fehlschlag.** Neu: `HpsPayments` (`pay`/`refund`/`cancel`, HPS-Terminal) und `HobexCloudPayments` (`pay`, Hobex-Cloud) legen die Transaktionskennung fest, **bevor** der erste Request hinausgeht, und liefern ein dreiwertiges `CardPaymentOutcome` statt eines Booleans: `approved` (Geld ist geflossen), `declined` (definitiv kein Geld geflossen — Wiederholung gefahrlos) oder `unresolved` (Ausgang unbekannt — keine automatische Wiederholung). Bleibt die erste Antwort aus, wird geklärt statt aufgegeben: auf dem HPS-Weg zuerst mit einem einmaligen Abbruchversuch, danach — und auf dem Cloud-Weg von Anfang an — mit einer Abfrageschleife mit Backoff (1 s, 2 s, 4 s, 8 s, gedeckelt bei 10 s, Gesamtbudget 90 s, einstellbar über den Konstruktor). Zum Ablauf im Einzelnen siehe die beiden folgenden Punkte. Das Ergebnis (`HpsResult`/`HobexCloudResult`) trägt in **jedem** Fall die Transaktionskennung und einen Klärverlauf (`steps`) für Anzeige und Protokoll — auch bei `unresolved`.
- **Der Bug vom 24.08. ist damit geschlossen:** eine ausbleibende Antwort führt nicht mehr zu einer neuen, kennungslosen Wiederholung, sondern zu einer Klärung über dieselbe Kennung.
- **Der Klärweg beruht auf Messungen am Terminal, nicht auf Annahmen.** Am 26.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0, Firmware 7.3.6, Host `tecstest.hobex.at`): die Statusabfrage antwortet mit `9027` „Original Tx not found" **gleichermaßen** auf eine nie gesehene Kennung, auf einen gerade laufenden Kartenfluss, auf „Karte nicht aufgelegt" und auf einen abgebrochenen Vorgang; nur eine genehmigte Zahlung antwortet mit `0`, und dieser Wert bleibt erhalten. **`9027` ist damit kein Ergebnis, sondern eine Wissenslücke** — es ist als benannter Begriff im Modell geführt (`TransactionResponse.noStatementCode`, `isNoStatement`, `isConclusive`) statt als verstreute Zeichenkettenprüfung. Es über `!= '0'` als Ablehnung zu lesen, hätte für einen **laufenden** Vorgang „nichts belastet, Wiederholung gefahrlos" gemeldet — genau die Doppelbelastung, gegen die dieses Release gebaut ist.
- **Der Abbruch steht jetzt vorne, nicht hinter der Statusabfrage.** Der Abbruch ist der Diskriminator, den die Statusabfrage nicht liefert: gemessen gelingt er (`responseCode '0'`), solange der Vorgang abbrechbar ist, und scheitert (`100010`), sobald er abgeschlossen ist — die genehmigte Zahlung bleibt dabei unangetastet. Bleibt die Antwort auf eine Zahlung aus, läuft die Klärung deshalb: `abort` einmalig versuchen → `responseCode == '0'` ergibt **beweisbar `declined`** (ohne jede Statusabfrage) → jeder andere Code oder ein Transportfehler beim Abbruch führt ins Pollen der Statusabfrage, die nun eine echte Aussage liefert → `9027` beim Pollen ist **kein Ergebnis**, sondern ein Grund weiterzumachen → Budget erschöpft ergibt `unresolved`. Die vorherige Reihenfolge (erst pollen, abbrechen nur wenn der Status „läuft noch" meldet) war wirkungslos: diesen Zustand meldet die Statusabfrage nie. Damit wird `unresolved` zum seltenen Randfall statt zum Regelfall. Bewusst in Kauf genommen: gelingt der Abbruch, während der Kunde die Karte auflegt, reißt er dessen Zahlung ab — geldseitig die sichere Richtung, und er wird ohnehin nur ausgelöst, wenn die Zahlung schon ohne Antwort dasteht. **`refund` folgt demselben Weg, `cancel` nicht:** bei `refund` ist die übergebene Kennung die des neuen Vorgangs, und der Abbruch-Endpunkt kennt keinen Transaktionstyp — ohne Abbruch hätte die Klärung einer Rückerstattung gar keinen Diskriminator und endete fast immer bei `unresolved`. Bei `cancel` ist die Kennung die der längst abgeschlossenen Originalzahlung; ein Abbruch darauf wäre sinnlos (gemessen: `100010`).
- **Die eiserne Regel bleibt, mit einer zweiten belegten Quelle:** `declined` entsteht ausschließlich aus einer **positiven Aussage** — einem echten Ergebniscode des Terminals ungleich `'0'` **und** ungleich `9027`, oder einem nachweislich gelungenen Abbruch. Niemals aus einem Transportfehler, einem Zeitablauf oder einer Wissenslücke. Die Kennung ist in **jedem** zurückgegebenen Ergebnis gesetzt.
- **Breaking: `HpsClient.abort()` liefert jetzt eine `TransactionResponse` statt `String?`.** Das Terminal meldet ein **gescheitertes** Abbrechen mit **HTTP 200** und `100010` im Rumpf. Die bisherige Fassung las nur `json['transactionId']` und warf nur bei Nicht-2xx — ein gescheiterter Abbruch hätte damit ausgesehen wie ein geglückter, und aus einer echten Belastung wäre `declined` geworden. Aufrufer lesen die Kennung jetzt über `response.transactionId` und den Ausgang über `response.responseCode`.
- **Die Storno-Klärung beruht auf einem gemessenen Ergebniscode statt auf einem Feld, das diese Firmware nicht liefert.** Bis 26.08. entschied `state == 'VOID'` — auf HPS 1.10.0 / FW 7.3.6 ist `state` jedoch in **jeder** bisher gesehenen Antwort `null`, bei genehmigten, abgebrochenen, unbekannten und aufgehobenen Vorgängen gleichermaßen. Die Bedingung wurde nie wahr; jede Storno-Klärung lief ins Budget und endete als `unresolved`, egal was tatsächlich geschah. Gemessen antwortet die Statusabfrage auf die Kennung der **Originalzahlung** nach einem erfolgreichen Void mit `9011` „Transaction Canceled". Neue Zuordnung im Klärweg: `9011` → die Aufhebung hat gewirkt (`approved`); `'0'` → die Originalzahlung steht unverändert, die Aufhebung hat **nicht** gegriffen (`declined` — weiterhin belastet, ein erneuter Void ist gefahrlos); `9027` und alles andere → weiter klären, am Ende `unresolved`. Der **direkte** Antwortweg von `cancel` wird unverändert über den `responseCode` **dieser** Antwort eingeordnet, die die Aufhebung selbst betrifft — der `responseCode` der Originalzahlung wird damit nie als Erfolg der Aufhebung gelesen. `state == 'VOID'` gilt nur noch zusätzlich, niemals als notwendige Bedingung.
- **Cloud-Weg neu im Paket:** `KasseneckApi.hobexGetStatus` fragt den Stand einer Hobex-Cloud-Transaktion ab und ist die Klärstufe hinter `HobexCloudPayments` — sie unterscheidet „Dienst hat geantwortet und kennt die Kennung nicht" (`null`, weiter pollen) von „konnte gar nicht erst fragen" (Transportfehler, wirft). Scheitern drei Statusabfragen in Folge am Transport, endet die Klärung vorzeitig mit `unresolved` statt den Mitarbeiter das volle Budget warten zu lassen. Dazu `KasseneckApi.cardTimeout` (3 Minuten, für `hobexPay`/`hobexRefund`) getrennt von `readTimeout` (30 s) — die bisher pauschale 30-Sekunden-Frist war für einen Belege-Cache gedacht und meldete am Terminal eine durchgelaufene Zahlung als Fehlschlag. `hobexGetStatus` selbst bleibt bei `readTimeout`: eine Abfrage, kein Kartenfluss.
- **Cloud-Rückerstattung bleibt roh, bewusst.** `HobexCloudPayments` deckt nur `pay` ab — kein `refund`. Eine Rückerstattung über die Hobex-Cloud läuft weiterhin unverändert über `KasseneckApi.hobexRefund` und bleibt damit ungeklärt: kein `CardPaymentOutcome`, keine Klärschleife. Bewusst nicht nachgebaut, denn ungeprüft ist, worauf `hobexGetStatus` mit der Kennung einer Rückerstattung überhaupt antwortet — genau diese Frage hat beim HPS-`cancel` einen Fehler aufgedeckt (die dort übergebene Kennung ist die der Originalzahlung, deren `responseCode` bleibt für immer `'0'` und wäre fälschlich als Erfolg der Aufhebung gelesen worden). Blind nachzubauen hätte denselben Fehler riskiert, diesmal ohne die Prüfung, die ihn dort gefangen hat. Betroffen von der Fristanhebung auf `cardTimeout` (siehe oben) ist `hobexRefund` trotzdem: der Aufrufer wartet jetzt bis zu 3 Minuten statt bisher 30 Sekunden auf dieselbe Nicht-Aussage.
- **Beobachter für den Zahlweg:** ein injizierbarer `HpsObserver`-Rückruf meldet Requests, Fehlschläge und den Stand der Klärung. Ohne Protokoll gab es zum Vorfall vom 24.08. keine Daten außer den hobex-Belegen; das soll sich beim nächsten Vorfall nicht wiederholen. `HpsPayments` nimmt ihn wie bisher entgegen, jetzt zusätzlich auch `HobexCloudPayments`. `HpsEvent`, `HpsEventKind` und `HpsObserver` werden dafür zusätzlich aus `kasseneck_api.dart` exportiert (bisher nur aus `hobex_hps.dart`).
- **Breaking: `HpsClient.cancel()` verlangt jetzt `amount`.** Das Terminal weist einen Void ohne Betrag mit `400 Missing amount` ab.
- **Der dreiwertige Ausgang heißt `CardPaymentOutcome`** und liegt in `lib/src/payments/card_payment_outcome.dart` statt im HPS-Baum, weil er jetzt auch vom Cloud-Weg geteilt wird. Die Werte `approved`/`declined`/`unresolved` sind unverändert; er ist der Typ von `HpsResult.outcome` und wird aus `hobex_hps.dart` exportiert.
- **Breaking (stille Verhaltensänderung): `HpsClient.close()` ist jetzt dauerhaft ein No-op.** Seit der Verbindungs-Robustheit baut jeder Request seine eigene Verbindung auf und schließt sie selbst wieder — es gibt keine wiederverwendete Verbindung mehr, die `close()` freigeben müsste. Aufrufer, die sich auf eine tatsächliche Freigabe verlassen, bekommen keine.
- **Breaking: eine zu lange Transaktionskennung wirft jetzt einen `ArgumentError`**, bevor irgendein Request hinausgeht — vorher lief das unbehandelt in ein `400` vom Terminal. Geprüft wird nur die Länge (max. 18 Stellen), nicht auf reinen Ziffernvorrat.
- **Erzeugte Transaktionskennung beweisbar kollisionsfrei statt zufallsbasiert:** `HpsClient.newTransactionId()` bildet die Kennung jetzt über Zeitstempel plus einen Zähler je Millisekunde (Snowflake-Verfahren) statt über Zeitstempel plus Zufallsziffern. Die Kollisionsfreiheit gilt **innerhalb eines Prozesses** — sie ist keine geräteübergreifende Garantie. Zwei getrennte Prozesse (etwa zwei App-Instanzen), die in derselben Millisekunde je eine Kennung für dasselbe Terminal bilden, können weiterhin dieselbe Kennung erzeugen, weil sie voneinander nichts wissen.
- **`tid` wird im Client normalisiert** (führende Null abgestreift) statt in jeder aufrufenden App einzeln.
- **Frist über den ganzen Abruf statt nur bis zum Antwortkopf:** ein Terminal, das Kopf und `200` schickt und den Rumpf offen lässt, hielt die App bisher unbegrenzt fest.

**Am Terminal gemessen und offen Gebliebenes:**
- **Die sechs Annahmen über das Terminal sind am 26.08.2026 abgearbeitet** (TID 3600335, HPS 1.10.0, Firmware 7.3.6). Vier davon sind gemessen, zwei bleiben offen:
  - *Wiederholung unter derselben Kennung* — **widerlegt.** Für eine bereits genehmigte Kennung startet das Terminal einen zweiten Kartenfluss; es entdoppelt nicht. Eine Wiederholung unter derselben Kennung schützt vor nichts. Eine bereits genehmigte Kennung bleibt in der Statusabfrage aber genehmigt, auch nachdem unter ihr ein zweiter Versuch abgebrochen wurde.
  - *Kennt das Terminal eine Kennung nach einem Abbruch noch* / *was antwortet `transactionStatus()` auf eine unbekannte Kennung* — **gemessen:** in beiden Fällen `9027`, ebenso bei laufendem Kartenfluss und bei abgebrochenem Vorgang. Nur eine genehmigte Zahlung antwortet mit `0`. Siehe den Klärweg oben.
  - *Scheitert `abort()` zuverlässig, sobald die Karte aufliegt* — **präzisiert:** die Grenze ist nicht der Kartenkontakt, sondern der Abschluss. `abort` gelingt (`0`), solange der Vorgang läuft — auch während der Kunde die Karte auflegt —, und scheitert (`100010`), sobald er genehmigt ist; die genehmigte Zahlung bleibt unangetastet. Genau darauf beruht der neue Klärweg.
  - *Was ein leerer `200`-Rumpf bedeutet* und *ob eine nicht rein numerische Kennung angenommen wird* — **weiterhin offen.** Beides ließ sich ohne künstlich herbeigeführte Fehlerlagen nicht auslösen. Die im Code hinterlegte konservative Behandlung (leerer Code wie fehlender Code; geprüft wird nur die Länge, nicht der Ziffernvorrat) bleibt.
- Zwei Nebenbefunde derselben Messung: die Diagnose führt ein Feld `transactionId`, das auch während eines laufenden Kartenflusses `null` bleibt und als Unterscheidungshilfe damit unbrauchbar ist; und `/api/terminals` antwortet auf dieser Firmware mit `404 Endpoint not implemented` — die in 4.8.0 ergänzte `terminals()`-Methode läuft dort ins Leere.
- Die Storno-Messung hat den Pflichtparameter aus 4.7.0 bestätigt: ein Void **ohne** `amount` wird mit `400 Missing amount` abgewiesen. Die Aufhebung selbst bekommt eine **eigene neue** `transactionId`; die an `cancel()` übergebene Kennung bleibt die der Originalzahlung.
- **Weiterhin unbestätigt:** die Erreichbarkeit von `hobexGetStatus` unter `api.kasseneck.at/v1` — die Methode ist bisher nur gegen Mocks geprüft, nicht gegen das Backend. Der Cloud-Weg ist von den HPS-Messungen nicht berührt: er kennt weder `abort()` noch `9027` und bleibt unverändert.

## 4.24.0
- **Trinkgeld-Empfänger abrufen** (`listMyTipRecipients`): `tipEmpfaenger()` am Kassen-Client und derselbe Aufruf auf dem `api_key`-Weg liefern die Personen, denen sich Trinkgeld zuweisen lässt — je Person `registerUserId`, `name` und `owner` — dieselbe Gestalt wie der Empfänger am Beleg-Item.
- Es ist **dieselbe Menge, die der Verkauf akzeptiert**: Wer in der Liste steht, wird von `createReceipt` nicht zurückgewiesen. Entschieden wird das im Backend an einer Stelle, die Liste und Annahme gemeinsam benutzen.
- `KeckTipPerson.mit(cents:)` macht aus einer Person einen `KeckTipRecipient`. Wer die Liste benutzt, kann keine Kennung erwischen, die der Server ablehnt.
- **`owner` entscheidet die Bezeichnung am Beleg**: „Trinkgeld" (Inhaber — Entgelt des Betriebs) gegen „Trinkgeld Personal" (durchlaufender Posten). Deshalb reist das Flag mit — als nicht nullbares `bool`, denn ein fehlendes Flag gäbe es bei dieser Frage nicht.
- Ist ein Kassen-Benutzer **ohne** das Recht `tipAssign` angemeldet, steht nur er selbst in der Liste.
- Vertrag auf `@kreiseck/kasseneck-api` **0.6.46** angehoben.

## 4.23.0
- **Die Hobex-Transaktionskennung entsteht jetzt nach demselben Verfahren wie im JS-Zwilling** (`@kreiseck/kasseneck-api`, `newHobexTransactionId` in `src/payments/hobex.ts`). Bisher rechneten beide Pakete unterschiedlich: hier Geraetezeit plus Mikrosekunden-Rest und eine Zufallsziffer, dort Wiener Wanduhrzeit plus vier Zufallsziffern. Ein Verfahren statt zweier.
- **Wiener Zeit statt Geraetezeit** (`ViennaTime.toWallClock`): zwei Kassen desselben Betriebs in verschiedenen Zeitzonen trugen sonst Kennungen, die sich um Stunden unterscheiden, und der Tageswechsel in der Kennung fand nicht zum Geschaeftstag statt.
- **Vier Zufallsziffern statt Mikrosekunden-Rest und einer Zufallsziffer.** Der Zwilling laeuft in JavaScript und hat keine Mikrosekunden-Uhr; vier Zufallsziffern unterscheiden zwei Zahlungen derselben Millisekunde besser als eine.
- **Die Form der Kennung aendert sich damit**: der Zeitanteil steht jetzt in den ersten 15 Stellen (JJMMTThhmmss + Millisekunde), der Zufallsanteil in den letzten vier. **Laenge und Zeichenvorrat bleiben unveraendert: 19 Stellen, rein numerisch.** Bereits erzeugte Kennungen bleiben gueltig; Hobex prueft nur Laenge und Ziffern.
- `newHobexTransactionId({DateTime? zeitpunkt, double Function()? zufall})`: neben dem Zeitpunkt ist jetzt auch die Zufallsquelle einspeisbar — beides dient dem Test. **Aufrufe ohne Parameter sind unveraendert.**
- **Gemeinsame Golden-Werte in beiden Testsuiten**: je ein fester Zeitpunkt in der Winter- und in der Sommerzeit, mit festem Zufallswert, ergibt eine Zeichenkette, die in `test/kasseneck_api_client_test.dart` und im npm-Paket in `test/payments.test.ts` wortgleich gepinnt ist. Beide Seiten rechnen die Sommerzeit-Umstellung selbst aus; laufen sie auseinander, faellt ein Test statt eines Terminals.

## 4.22.0
- **Absturz beim Anlegen einer Hobex-Kartentransaktion behoben.** `KasseneckApi.newHobexTransactionId()` baute die Transaktionskennung aus `DateTime.now().toString()` und schnitt daraus 19 Stellen zu. Dart laesst in dieser Textform den Mikrosekunden-Rest jedoch weg, sobald er 0 ist — dann war der Zwischenstring drei Stellen zu kurz und der Zuschnitt warf einen `RangeError`. Das traf rund jeden tausendsten Aufruf, und zwar im Zahlungsweg: beim Anlegen der Kartentransaktion, waehrend der Kunde am Terminal steht. Der Fehler steckte seit 1.1.0 in jeder veroeffentlichten Fassung.
- Die Kennung wird jetzt aus den Bestandteilen des Zeitpunkts mit fester Stellenzahl gebildet (Jahr ohne Jahrhundert, Monat, Tag, Stunde, Minute, Sekunde je 2 Stellen, Millisekunde 3, Mikrosekunden-Rest 3, dazu eine Zufallsziffer 1-9) statt aus einem zurechtgeschnittenen Text. **Das Format bleibt unveraendert**: 19 Stellen, rein numerisch, aus der Uhrzeit abgeleitet — im bisher funktionierenden Fall kommt Zeichen fuer Zeichen dasselbe heraus. Nur der Absturzfall faellt weg.
- `newHobexTransactionId({DateTime? zeitpunkt})`: der neue benannte Parameter dient allein dem Test, damit der Fehlerfall gezielt getroffen werden kann statt zufaellig. Aufrufe ohne Parameter sind unveraendert.
- Neue Tests fuer genau diese Faelle: Mikrosekunden 0, Millisekunden und Mikrosekunden 0, einstellige Werte in Monat/Tag/Stunde, Jahreswechsel, volle Stellen — sowie ein Vergleich ueber 500 Zeitpunkte, der die Gleichheit mit der bisherigen Bildung festhaelt.

## 4.21.0
- **Zwillingsprüfung**: Das Paket prüft sich gegen den Vertrag des JS-Pakets `@kreiseck/kasseneck-api` (angeheftete Version in `zwillinge.yaml`). Die Vertragsdateien werden mit `tool/zwillinge.sh ziehen` geholt und nie von Hand geändert; die CI vergleicht die Kopie byteweise mit dem veröffentlichten Tarball.
- Vier Prüfungen in `flutter test`: Standardwerte, Enum-Werte (jeder Wert muss das Einlesen überstehen), Rechte-Schlüssel (kein Schlüssel darf im Auffangbecken landen) und Aufrufnamen. Was fehlt, muss in `zwillinge.yaml` benannt werden — dauerhaft mit Grund oder als offene Schuld mit Issue-Nummer.
- Damit sind **33 Lücken** benannt, die dieses Paket bisher stillschweigend hatte: 20 Enum-Werte, 5 Aufrufe, 6 Tasten-Aktionen und 2 abweichende Standardwerte. Alle stehen als `art: offen` mit Issue-Nummer in `zwillinge.yaml` (#22 bis #26); die CI schreibt bei jedem Lauf, wie viele es noch sind.
- Die Buchführung ist in beide Richtungen streng: Wer eine Lücke schließt, ohne die Zeile aus `zwillinge.yaml` zu streichen, wird ebenso rot wie umgekehrt — sonst sänke die Zahl in der CI nie.
- **Vorgabefarbe ist `#116B6B`** (Petrol aus der Markenpalette) — betrifft Betriebe ohne eigene Farbe.
- **`belegAusgabe` steht standardmäßig auf `fragen`**: die Fertig-Seite bietet QR und Bon an, wie Backend und Browser-Kasse es längst tun.
- Die Aufrufnamen stehen als Konstanten in `Aufrufe` an einer Stelle.
- Zwei Standardwerte weichen weiterhin ab und stehen in `zwillinge.yaml` unter `wert_ausnahmen` — unter derselben Strenge wie die Hauptliste: die Tastenbelegung `tasten` (Issue #25) und `terminalPort`, Vertrag 8080 gegen 20008 hier (Issue #23).

## 4.20.0
- **Trinkgeld am Beleg** (`models/keck_tip.dart`): `sellReceipt(tip: …)` reicht Betrag, Zahlart und Empfänger an `createReceipt` durch; die Positionen baut das Backend (`tip-core`). Absicht: Ob ein Anteil Entgelt ist (Inhaber, anteilig auf die Steuersätze der Warenpositionen) oder durchlaufender Posten mit 0 % (Mitarbeiter, Erlass 2.4.6/2.4.2.1), entscheidet dort das `inhaber`-Flag des Kassen-Benutzers — der Aufrufer schickt für beide dasselbe.
- `KeckTip.fuer(registerUserId, cents: …)` für den Regelfall, `KeckTip.euro(…)` mit einmaliger Rundung, `KeckTipRecipient` für die Aufteilung auf mehrere.
- Geprüft wird schon im Client, mit dem Wortlaut des Backends: Betrag als ganze Zahl in Cent > 0, Empfängerliste nicht leer, Summe der Anteile gleich dem Betrag, keine Person zweimal. Ein falscher Betrag verursacht damit keinen Netzweg.
- `ReceiptType.allowsTip`: nur `standard` und `training`. Ein Storno spiegelt die Positionen des Originals — über den Parameter entstünde beim Zurücknehmen neues Trinkgeld. Ein Beleg nur mit Trinkgeld wird abgelehnt (er hängt an einer Leistung).
- **Trinkgeld auslesen**: `KasseneckReceipt.tipItems`/`tipCents`/`tip` sowie getrennt `staffTipCents` (durchlaufender Posten — bei Karte der Betrag, der weitergegeben werden muss) und `ownerTipCents` (Entgelt, in `sumCents` enthalten). An der Position: `KasseneckItem.isOwnerTip`, `tipRecipientId`, `tipRecipientName`. Gerechnet wird aus den Positionen, nicht aus dem abgeleiteten `tipCents` des Belegdokuments — signiert sind die Positionen.
- Nachgewiesen an den Golden-Belegen des JS-Pakets (`rabatt-trinkgeld`, `rabatt-chef-trinkgeld`) und gegen die **echte Demo-Kasse**: Beleg mit Trinkgeld ausstellen, 0-%-Position und Gesamtbetrag prüfen, stornieren — die Spiegelung nimmt das Trinkgeld vorzeichengetreu zurück.
- Ohne `tip` geht kein Feld hinaus; der Aufruf ist unverändert.

## 4.19.0

- `KasseneckItem`: neue optionale Felder `kind` (`'tip'`/`'discount'`), `recipient`, `paymentMethod`, `articleId` — Zwilling von `ReceiptItem` im JS-Paket 0.6.44. Die Kennzeichnungen reisen durch `toJson`/`fromJson` und `negative` (Storno-Spiegelung); Zeilen ohne bleiben schlank.
- `verteileRabatt` kennzeichnet seine Zeilen als `kind: 'discount'` — der Bon fasst sie zu einer Summenzeile mit Zwischensumme zusammen, der Bericht führt sie als „Rabatte“.
- `articleId` an Positionen ist die Grundlage der Erlösgruppen-Zuordnung im Monatsbericht.
- Golden-Belege auf den Stand des JS-Pakets 0.6.44 gehoben: 22 Fälle (neu: rabatt-einfach, rabatt-trinkgeld, rabatt-chef-trinkgeld, storno-rabatt, rabatt-wertgutschein).

## 4.18.0
- **Belegaufrufe der Kasse** (`package:kasseneck_api/kasse.dart`): `RegisterReceiptClient` mit `verkaufen` (Normalbeleg samt Belegkopf in einer Antwort), `auflisten` (Zusammenfassungen mit Summe in ganzen Cent, Bediener, Storno-Stand), `holen` und `stornieren` (voll oder in Teilen, mit Grund und Restmengen). Der Verkauf ist der einzige nicht folgenlos wiederholbare Aufruf — es geht genau ein Aufruf hinaus, auch nach einem Netzhaenger.
- **Gemeinsamer Weg der laufenden Sitzung**: `RegisterTransport` (ID-Token als Bearer, Sitzung als Kopfzeile `register-session`, Kasse als Parameter, eigene Frist je Aufruf). `RegisterSessionClient` laeuft jetzt darueber, statt die Huelle ein zweites Mal zu fuehren; sein Verhalten aendert sich nicht.
- Eine leere Storno-Positionsliste ist ein Fehler und **kein** Vollstorno — sonst wuerde aus einem missglueckten Teilstorno still ein voller.

## 4.17.0
- **Warenkorb und Kassieren** (`package:kasseneck_api/kasse.dart`), Zwilling von `warenkorb.ts` und `kassieren.ts` der Browser-Kasse: `Warenkorb` (erfassen, Menge setzen, Höchstmenge je Beleg, verkaufte Positionen abziehen, Anzeigezeilen je Mengenmodus), `betragAusText`/`alsEuro` (jeder Betrag eine ganze Zahl in Cent — gelesen über die Ziffern, nie über Fließkomma), `zahlungsarten`, `rabattCents`, `zuZahlen`, `rueckgeld`, `schnellbetraege`, `abschlussPruefung`, `ustCents`/`ustSumme`.
- `verteileRabatt`: Rabatt als negative Position je Steuersatz mit Rundung nach größtem Rest — die Summe der Zeilen ist immer genau der Rabatt, keine Zeile größer als der Umsatz ihres Satzes.

## 4.16.0
- **Behoben:** die Kopplungs- und Sitzungsaufrufe zeigten auf `api.kasseneck.at/v1` — dort antwortet auf sie eine HTML-404, die Kopplung schlug also immer fehl. Sie liegen hinter den Hosting-Umschreibungen der Kasse; die Vorgabe ist jetzt `https://kasse.kasseneck.at/api`.

## 4.15.0
- **Kassen-Einstellungen** (`package:kasseneck_api/kasse.dart`): `KasseSettings` mit allen 38 Betriebs- und 20 Gerätefeldern als Zwilling von `kasse/settings.ts` und `kasse-settings-core.js`. Standardwerte gegen die Golden-Datei des JS-Pakets geprüft; Gespeichertes wird gemischt (Landkarten je Schlüssel, damit neue Steuersätze beim Altbestand ankommen), Unbekanntes fällt auf den Standard zurück statt zu raten. Dazu `kartenAktiv` (Karte nur mit eingerichtetem Anbieter) und `aktiveSaetze` (feste Reihenfolge für den Bildschirm).
- `listRegisterUsersForDevice` liefert `settings` jetzt als `KasseSettings` statt als Rohdaten.

## 4.14.0
- `RegisterClient.sitzung(...)` liefert den `RegisterSessionClient` mit derselben Adresse, demselben HTTP-Client und demselben Zeitlimit — eine Verbindung statt zweier, und ein für Tests eingesetzter HTTP-Client erwischt beide Wege.

## 4.13.0
- **Laufende Sitzung** (`register.dart`): `RegisterSessionClient` mit `renewRegisterSession` (liefert den neuen Ablauf) und `endRegisterSession`. ID-Token und Sitzung werden bei jedem Aufruf frisch erfragt — Tokens laufen nach einer Stunde ab, die Kassen-Sitzung schon nach 90 Sekunden.

## 4.12.0
- **Kopplung und Anmeldung eines Kassengeräts** (`package:kasseneck_api/register.dart`), Zwilling von `register/pairing.ts` im JS-Paket: `RegisterClient` mit `pairRegisterDevice` (achtstelliger Code aus dem Panel → dauerhafter Geräte-Ausweis), `listRegisterUsersForDevice` (Benutzer, PIN-Regel, Anmeldemodus, Standortsperre), `registerUserLogin` / `registerPinLogin` (Sitzung: Custom Token + `sessionId`) und `unpairRegisterDevice`. Diese Aufrufe laufen ohne Anmeldung — der Code bzw. das Gerätegeheimnis ist der Nachweis; sie stehen deshalb neben `KasseneckApi` und nicht darin.
- Rechte werden gelesen wie im Backend: Schalter als ja/nein, `cancelScope`/`receiptsScope` als Reichweite (`none|own|all`), Altbestand ohne Reichweite migriert (`cancel` entscheidet, Belege gelten als „alle"). Ein fehlendes Recht gilt als nicht erteilt.
- Fehlerarten: `KasseneckValidationError` (Aufruf oder Antwort unvollständig), `KasseneckApiError` (fachlicher Fehler des Backends), `KasseneckHttpError`. Weder PIN noch Gerätegeheimnis stehen je in einer Meldung.

## 4.11.0
- **Zeichenraster `BelegRaster`** (`models/beleg_raster.dart`), Zwilling von `renderReceiptGrid` im JS-Paket: der Beleg als Zeilen mit exakt 32 (58 mm) bzw. 48 (80 mm) Zeichen — Spalten in ganzen Zeichen, rechte Spalte bündig, mindestens ein Leerzeichen zwischen Spalten, wortweiser Umbruch. Golden-Vergleich gegen `grid32.txt`/`grid48.txt` des JS-Pakets.
- `PrintPaper.setBelegLayout` druckt jetzt genau diese Rasterzeilen (keine eigene Spaltenrechnung mehr, kein `ESC $`) — dieselben Zeilen wie Browser-Kasse, Labor und Beleg-PDF. Verhalten von `setKeckReceipt` unverändert.
- 58-mm-Regeln des Rasters (wie JS-Paket 0.6.7): läuft in einer Spaltenzeile nur eine Spalte über die erste Zeile hinaus, bekommt ihr Rest die volle Breite (lange Artikelnamen); überlange Wörter brechen am Bindestrich; geschütztes Leerzeichen bricht nie („je 0,79“ bleibt zusammen). Fixtures auf Stand 0.6.7.

## 4.10.0
- **Beleg-Zeilenmodell des Backends** (rein additiv): `KasseneckReceipt.layout` (`BelegLayout`, aus `getReceipt` → `layout`), dazu `testKasse`, `testSignatur`, `kopfId`. Das Backend friert Kopf/Fuß je Beleg ein und baut das Zeilenmodell mit dem Belegart-Aufdruck (STORNOBELEG, TRAININGSBELEG, NULLBELEG/STARTBELEG/MONATSBELEG/JAHRESBELEG/SCHLUSSBELEG — RKSV § 11 Abs. 3), reduziertem Nullbeleg und TESTKASSE/TESTSIGNATUR-Warnrahmen.
  - `KeckReceiptLinesWidget(layout:, qrCovered:)` zeichnet das Modell in der App; `PrintPaper.setBelegLayout(layout)` druckt es (Banner fett, doppelt hoch, Warnungen invers).
  - Damit zeigen App, Bondrucker, Browser-Kasse und Beleg-PDF **dieselben Zeilen**; die 17 Golden-Belege des JS-Pakets liegen als Kopie unter `test/fixtures/belege` und werden per Prüfsumme gegen dessen Manifest gehalten.
  - Empfehlung: `layout != null` → Zeilenmodell zeichnen/drucken; sonst wie bisher `KeckReceiptWidget`/`setKeckReceipt` (Altbelege, altes Backend).

## 4.9.0
- **`KeckReceiptWidget.qrCovered`** (Vorgabe `false`, rein additiv): der RKSV-QR wird zunächst weichgezeichnet und nicht scannbar gezeigt (mit Hinweis `qrCoveredText`, Vorgabe „Antippen zum Anzeigen"); ein Tipp macht ihn lesbar, ein zweiter verdeckt ihn wieder. Für Bildschirme, auf denen der Beleg nur zur Kontrolle steht — der Signatur-QR gehört dem Kunden und wird erst auf Verlangen freigegeben. Druck und Belegdaten sind unberührt.

## 4.8.0
- **hobex HPS: lokale Terminal-Abfragen ergänzt** (rein additiv, keine bestehende Signatur geändert). Zwei neue read-only Methoden im `HpsClient`:
  - `terminalStatus()` → `GET /api/terminals/{tid}/status`: leichter Readiness-Check. `true` bei HTTP 200 (bereit), `false` bei 503 (nicht betriebsbereit); dieser Endpoint hat keinen Response-Body (im Gegensatz zum feldreichen `diagnosis()`).
  - `terminals()` → `GET /api/terminals`: Liste der konfigurierten Terminals als neues Modell **`TerminalInfo`** (tid, company/merchantName, Beleg-`header`-Zeilen, `terminalType`, `active`, …). Alle Felder optional, da Spec-Tabelle und Beispiel-Response divergieren; unmodellierte Keys bleiben über `TerminalInfo.raw` erreichbar.
  - Intern wurde das Senden in `_send()` extrahiert (frische-Verbindung-Logik aus 4.7.0 unverändert), damit `terminalStatus()` den 503-Status als Wert statt als Ausnahme behandeln kann.
- Bewusst NICHT enthalten: Beleg-Download (`/api/transaction/download`) und die Profil-Flags `canVoid`/`canRefund` sind reine **Cloud**-Endpoints (`online.hobex.at`, JWT-Auth) und gehören nicht in den authlosen lokalen HPS-Client. Ein `responseCode`-Fehlercode-Katalog ist nicht enthalten, da die REST-Spec v1.13 außer `"0"` (=OK) keine Codes enumeriert (weitere Codes stammen vom Acquirer).

## 4.7.0
- **hobex HPS: Storno/Refund-Robustheit.** Zwei Fehler behoben, die Rückabwicklungen am HPS-Terminal unzuverlässig machten:
  - **Verbindungs-Wiederverwendung:** `HpsClient` hielt eine Keep-Alive-Verbindung offen und verwendete sie wieder; das Terminal schließt inaktive Sockets aber, wodurch der nächste Request (typisch: Storno/Refund nach einer Bedien-Pause) mit „Connection closed before full header" abbrach — ohne Retry. Selbst erzeugte Clients bauen jetzt **pro Request eine frische Verbindung** auf (injizierte Clients für Tests bleiben unverändert; bewusst kein Auto-Retry wegen Doppelbuchungsgefahr bei Zahlung/Refund). `close()` ist damit ein No-op.
  - **Void ohne Betrag (`400 Missing amount`):** `cancel()` sendete keinen Betrag. Signatur jetzt `cancel({required transactionId, required amount, currency, language, technicalCancel})` — sendet `amount`/`currency` (+ optional `language`) als Query-Parameter (wie in der hobex-Postman-Collection; die REST-PDF v1.13 listet den Parameter nicht, die Firmware verlangt ihn). **Breaking:** `amount` ist jetzt Pflicht.

## 4.6.0
- **Zahlungsart-Zeile auf jedem Beleg** (Druck + `KeckReceiptWidget`): direkt unter dem Gesamtbetrag steht `Zahlungsart: Barzahlung/Kartenzahlung/Onlinezahlung/…` (`KeckPaymentMethod.label`, Labels identisch zum Backend-Beleg-PDF) — auch wenn zusätzlich ein Provider-Kartenblock folgt.

## 4.5.0
- **`ViennaTime`: Geschäftszeitzone Europe/Vienna** (`package:kasseneck_api/services/vienna_time.dart`). Der Kasseneck-Server liefert Beleg-Timestamps als Wiener Wanduhrzeit ohne Offset; auf Geräten mit fremder Zeitzone (z. B. im Ausland) verrutschten dadurch Beleg- und Buchungs-Tage gegeneinander. `ViennaTime` rechnet deterministisch per EU-Sommerzeitregel (letzter Sonntag März/Oktober, 01:00 UTC — kein tz-Paket nötig): `fromWallClock`/`toWallClock`, `parseServerTimeStamp`, `dayKey`, `now`/`today`, `deviceDiffersFromVienna`.
- `KasseneckReceipt.timeStamp` ist jetzt immer ein echter Zeitpunkt (UTC): Server-Timestamps werden beim Parsen als Wiener Wanduhrzeit interpretiert (`ViennaTime.parseServerTimeStamp`); `toReceiptJson` serialisiert UTC mit `Z` (Roundtrip-kompatibel, alte naive Strings werden weiterhin korrekt gelesen). `readableTime` zeigt unverändert Wiener Zeit — jetzt auch bei fremder Geräte-Zeitzone.
- `ReportMonth.now()` bestimmt den aktuellen Monat nach Wiener Zeit.
- **`CreditCardProvider.stripe`: Kartenblock für Online-Zahlungen** (Stripe-Payment-Link). Das Backend hängt an `online`-Belege `creditCardProvider: 'stripe'`, `cardPaymentId` (PaymentIntent-ID) und `cardPaymentData` an; Beleg-Druck (`print_paper.dart`) und App-Viewer (`KeckReceiptWidget`) rendern daraus einen zentrierten Block identisch zum Backend-Beleg-PDF: Titel „Online-Zahlung (Stripe)", Kartenmarke + Kartenart (Debit/Kredit/Prepaid) + Wallet (Apple/Google Pay), maskierte Kartennummer, „3-D Secure: ja", bei EPS die Bank, Gesamtbetrag, Zahlungszeitpunkt („Bezahlt:", Wiener Zeit via `ViennaTime`), Abrechnungstext und PaymentIntent-Referenz. Beide Renderer speisen sich aus einer gemeinsamen `stripeReceiptLines()` — Druck und Widget können nicht auseinanderlaufen (abgesichert durch `stripe_render_consistency_test.dart`). Fehlende Felder lassen ihre Zeile entfallen; kaputte Daten brechen den Druck nicht ab.

## 4.4.0
- **Unified `KeckPrinter` with a `PrinterTransport` abstraction.** New high-level printer facade that separates ESC/POS byte building from transport, replacing reliance on global printer state for new code. Ships two transports — `WifiTransport` (raw TCP, port 9100) and `BluetoothTransport` (its own `BluetoothDevice`, no shared global device) — and is USB-ready via the public `PrinterTransport` interface. Convenience factories `KeckPrinter.wifi(...)` / `KeckPrinter.bluetooth(...)`, plus DI-friendly `KeckPrinter(transport)`. High-level ops `printReceipt`/`printText`/`printQr`/`printBarcode`/`cut`/`openDrawer`/`feed`/`printJob`/`printRawBytes` each return a `KeckPrintResult` (never throw). All exported from `package:kasseneck_api/printing.dart`. Backward compatible: the static `KeckPrinterService` API is unchanged — the Bluetooth send logic (MTU negotiation, discovery, chunking, flow control) was extracted into a shared helper (`writeToBluetoothDevice`), behaviour identical.

## 4.3.0
- **1D barcode support** in the vendored ESC/POS engine: `EscPosGenerator.barcode(type, data, {align, height, width, hri})` and the fluent `CustomPrintJob.barcode(...)`. Emits GS k form 2 (length-prefixed) with the symbologies UPC-A, UPC-E, EAN-13, EAN-8, CODE39, ITF, CODABAR, CODE93 and CODE128 (auto code-set B — `{B` is prepended unless the data already starts a code-set sequence), plus height (GS h), width (GS w) and HRI position (GS H) options. `BarcodeType` and `BarcodeHri` are exported from `package:kasseneck_api/printing.dart`. This closes the last gap vs. esc_pos_utils_plus — the print stack is now fully self-contained.

## 4.2.0
- **Crisp image QR:** the image-based QR (`addQrCodeAsImage`, used by the imageRaster/bitImage print modes) is now rasterized directly from the QR module matrix with an integer per-module scale and no anti-aliasing — pure black/white pixels, sharp by construction. This replaces the previous `QrPainter → PNG encode/decode` path, whose non-integer pixel size (280 px over a variable module count) produced fringed edges and a larger image that was slow over Bluetooth; the new bitmap is smaller and faster to send. The native QR command (`addQrCode`) and the Bluetooth send path are unchanged.

## 4.1.1
- Cleans up the WiFi raw-print API from 4.1.0: dropped the unused `size` parameter (raw bytes are already rendered), renamed the result type `PrintResult` → **`KeckPrintResult`** (avoids clashing with app-level `PrintResult` types), documented that `success` means *sent* (bytes written to the socket) — not guaranteed *printed* (raw TCP to a thermal printer has no application ACK), and de-duplicated the socket send behind a shared internal helper. Final shape: `KeckPrinterService.printRawBytesWifi(bytes, {required ip, port = 9100, timeout = 5s}) → Future<KeckPrintResult>`.

## 4.1.0
- **Direct WiFi raw printing:** `KeckPrinterService.printRawBytesWifi(...)` sends finished ESC/POS bytes straight to a network printer over a short-lived socket, **without touching the globally initialized printer** (`ipAddress`/`port`/the active device stay untouched). It never throws — the outcome is reported as a result object, so callers can retry or show a hint. Exported from `package:kasseneck_api/printing.dart`. (Superseded by 4.1.1, which finalizes the signature and result type.)

## 4.0.0
- **Decoupled print stack.** The ESC/POS generator and the (correct) rasterizer from esc_pos_utils 1.1.0 are now vendored internally under `lib/src/printing/`; PNG de/encoding runs via `dart:ui`. The runtime no longer depends on `esc_pos_utils_plus`, and `image` is a dev-only dependency — apps that use this package are no longer version-locked to `image` and pull in no print dependencies at runtime.
- Fixes the Bluetooth/thermal print failure for image widths that are not a multiple of 8 (a crash in the old `esc_pos_utils_plus` rasterizer). QR and logo printing are unchanged in behaviour (native QR is byte-identical, image-QR keeps its white background and quiet zone).
- **New custom-print API** on `KeckPrinterService`, additive and sending to whichever printer is currently initialized (Bluetooth or WiFi, same send path as the receipt printers): `printRawBytes(List<int>)`, plus the high-level helpers `printText`, `printQr`, `cut`, `openDrawer` and `feed`. A `CustomPrintJob` batch builder (`text`/`qr`/`cut`/`drawer`/`feed`/`raw`, fluent) accumulates several commands into a single byte stream printed in one send via `printJob` (preferred for Bluetooth). The vendored `EscPosGenerator` and the required types (`PosStyles`, `PosAlign`, `PosCutMode`, `PosDrawer`, `QRSize`, `CapabilityProfile`, …) are exported from the new `package:kasseneck_api/printing.dart` barrel so integrators can build bytes themselves and send them with `printRawBytes`.
- **Branded API base URL:** the client now talks to `https://api.kasseneck.at/v1` instead of `europe-west1-kasseneck.cloudfunctions.net`. The receipt-download base URL is unchanged.
- **v2 item shape:** `KasseneckItem.toJson()` now sends `{ name, quantity, unitPriceCents, vatRate }` with the unit price as integer cents (no floating-point amounts). `fromJson()` reads both the new v2 form and the legacy v1 form (`priceOneCents`/`priceOne`, `amount`, `vat`), preferring cents for exactness — old stored receipts keep parsing.
- Breaking: `KeckPaperSize.paperSize` is now typed `EscPaperSize` (internal) instead of `PaperSize` from esc_pos_utils.

## 3.3.0
- Receipt download links now use the branded path-based URL `https://beleg.kasseneck.at/<token>` instead of `https://receipt.kreiseck.com/downloadReceipt?fullReceiptId=<token>`. The backend serves both the new path form and the old query form, so links on already printed or shared receipts keep working.

## 3.2.1
- GP Tom card details render correctly with `gptom_aidl_plugin` ≥ 0.1.0: `cardPaymentData` amounts arrive as integer cents and are now formatted as such (older stored receipts with euro doubles keep working); applies to thermal print and `KeckReceiptWidget`
- GP Tom transaction type is recognized via both `transactionType` and the plugin's `transacitonType` key; `Refund` (type 3) is now labelled

## 3.2.0
- Kreiseck branding on receipts: when the backend metadata flag `kreiseck_logo` is set (Firestore `users/{uid}.branding.kreiseck_logo`), the receipt ends with "powered by" and the Kreiseck logo — on thermal prints (85 % paper width), in `KeckReceiptWidget` and survives JSON round-trips for reprints
- The logo ships as a package asset (printing works offline; the backend only sends the flag); branding can never break receipt printing
- Fixed an ESC/POS rasterizer crash for images whose width is not a multiple of 8

## 3.1.1
- Zero analyzer issues: debug-only logging, migrated deprecated APIs (`License.nonprofit`, QR `eyeStyle`/`dataModuleStyle`), removed redundant imports; FinanzOnline status enum names are intentionally kept verbatim (they must match the `rkdbMessage` values)
- CI runs `flutter analyze` in strict mode again

## 3.1.0
- Comprehensive test suite (~100 new tests): money & receipt math, JSON round-trips and fallback parsing, voucher rules, mocked API client, and a print↔widget consistency check that guards the two independent VAT-table renderers against drift
- `KasseneckApi` and `LogoService` accept an injectable `http.Client` (useful for testing/mocking; default behaviour unchanged)
- `financeWebService` requests now also time out after 30 s
- Continuous integration: analyze + tests run on every push

## 3.0.1
- `getReceipts` no longer fails wholesale when a single receipt can't be parsed — broken receipts are skipped (and logged in debug builds)
- Zero receipts (no items) parse correctly; item quantities also accept `1.0`
- All HTTP requests time out after 30 s instead of hanging silently forever
- Odd voucher amounts are displayed exactly (e.g. € 1,50 instead of ~2)

## 3.0.0
**Breaking: money is now integer cents** — exact arithmetic, no floating-point drift. No backend update is required: requests carry BOTH representations (`priceOne`/`value` in euro for the current backend and `priceOneCents`/`valueCents`/`singlePriceCents`, preferred by newer backends). When reading, the cents fields are preferred; euro-only data (old receipts) still parses — the euro↔cents round-trip is lossless (verified by property tests).

Migration:
- `KasseneckItem(singlePrice: 19.99)` → `KasseneckItem(priceCents: 1999)` or `KasseneckItem.euro(singlePrice: 19.99)`
- `KeckVoucher(value: 5.0)` → `KeckVoucher(valueCents: 500)` or `KeckVoucher.euro(value: 5.0)`
- `KeckInvoiceItem(singlePrice: …)` → `priceCents` / `KeckInvoiceItem.euro(…)`
- Reading: `item.singlePrice`, `voucher.value`, `receipt.sum` / `subSum` still exist as euro views; for arithmetic use `priceCents` / `valueCents` / `sumCents` / `subSumCents` / `totalCents`
- Terminal APIs (`hobexPay`, `HpsClient`, SumUp) keep euro amounts — they mirror the external providers' formats

## 2.1.3
- Reliable Bluetooth thermal printing: flow control via write-with-response (backpressure), negotiated MTU with matching chunk size, and pacing for write-without-response printers
- Fixed garbled QR output: the QR image is now composited onto a white background with a quiet zone (QrPainter renders on transparent, which ESC/POS rasterization printed as solid black)
- New `QrPrintMode` (`imageRaster` / `imageBitImage` / `native`) on `printReceiptBluetooth` / `getPrintBytes` to pick the command your printer supports (replaces `qrAsImage`)
## 2.1.2
- Cleaner static analysis (0 warnings): `KeckVoucher.value` is now nullable; removed dead null-aware code and unused SumUp leftovers
- Loosened the `my_pos` version constraint to `^0.3.0`
## 2.1.1
- New README, a runnable `example/` and inline API documentation (dartdoc)
- Added repository & issue tracker metadata
## 2.1.0
- hobex Payment Service (HPS): lokaler Terminal-Client (HpsClient) mit Zahlung, Pre-Auth, Capture, Refund, Storno, Status, Abbruch, AVT und Diagnose
- HobexReceipt.fromHps + Karten-Beleg-Rendering (Provider hobexHps); HobexReceipt aus dem hobex_hps-Barrel exportiert
## 2.0.0
- image plugin update
- voucher logic implemented
## 1.1.0
- Added new endpoints
## 1.0.0
- Initial release of kasseneck_api