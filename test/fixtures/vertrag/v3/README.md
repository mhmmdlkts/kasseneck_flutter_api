# Vertrags-Export `/v3`

Quelle der Wahrheit für die Pakete `@kreiseck/kasseneck-api` 1.x (npm) und
`kasseneck_api` 10.x (Dart). Jeder Name, Wert und Code in diesen Dateien ist genau
das, was der Server unter `/v3` bzw. `/api/v3` sendet.

**Nicht von Hand pflegen.** Jede Datei wird aus den echten Handlern hinter dem echten
Rand erzeugt. Ein Handeingriff macht den Test „Export ist aktuell“ rot; die CI zählt
eine Änderung unter `functions/vertrag/` nie als „nur Doku“.

## Herkunft

Erzeugt von Jest-Tests in zwei Codebases (jede übersetzt mit ihrem eigenen Rand):

| Test | schreibt |
| --- | --- |
| `functions/test/unit/v3-vertrag-export.test.js` | `v3-vokabular.json`, `antworten/belege.json`, `antworten/kasse-belege.json`, `antworten/storno.json`, `antworten/belegmail.json`, `antworten/rechnungen.json`, `stored/belege.json`, `stored/rechnungen.json`, `zahlbetrag-faelle.json` |
| `functions/test/unit/v3-vertrag-export-kassenweg.test.js` | Teil `default` von `antworten/kasse.json` und `stored/kasse.json` (6 Beleg-Endpunkte der Kasse) |
| `functions-kasse/test/unit/v3-vertrag-export.test.js` | Teil `kasse` derselben zwei Dateien (die übrigen 19 Kassen-Endpunkte) |
| `functions-kasse/test/unit/v3-vertrag-export-lager.test.js` | `antworten/lager.json` (Lager-API, Stufe 5a) |

Fest injiziert, damit zwei Läufe dieselben Bytes liefern: eine Uhr für alle Welten
(26.09.2026 08:00 UTC), `crypto.randomBytes`/`randomUUID`, fortlaufende Dokument-IDs
der Firestore-Attrappe, Serverzeitstempel aus derselben Uhr und die Signatur der
Testkarte (AT100). In `antworten/belege.json` und `kasse-belege.json` ist `sig` ein
JWS in echter Form, dessen Signaturteil SHA-512 über den Signaturtext ist (kein
ECDSA). In `antworten/kasse.json` stehen `sig`, `signaturePreviousReceipt` und die
zwei Signatursegmente des QR-Codes als Platzhalter (`<signatur>`, `<verkettung>`).

Rechnungen laufen über die echten Endpunkte aus `index.js` samt echtem Festschreiben
(Nummernvergabe, Summen, `totalsCents`, E-Rechnung-Prüfung, Meldungen). Einzig
`writtenOff` am Fall `get_invoice_written_off` setzt der Ablauf von Hand in
Firestore, wie das Panel es tut; die API kennt keine Abschreibung.

### Zugangsdaten

Alles Zugangsartige ist in Anfragen und Antworten formgerecht und erkennbar falsch
ersetzt; derselbe Originalwert ergibt überall denselben Platzhalter, verschiedene
bleiben verschieden:

| Feld | Platzhalter |
| --- | --- |
| Kassen-Token (`token`, auch im Text) | `cb_test_EXAMPLE<8 hex>` |
| `deviceSecret` | `EXAMPLE<8 hex>AAAA…` (43 Zeichen) |
| `customToken` | `EXAMPLE-custom-token-<8 hex>` |
| `pin` | `0001`, `0002`, … (je Original-PIN eine) |
| `fullReceiptId` (auch im Text) | `000…0.000…0<8 hex>` |
| `statusPassword`, Token in `statusUrl` (gespeichert: `public_password`, `public_token`) | `EXAM-<4 hex>`, `000…0<8 hex>` |
| Kopplungscode (`code` bei `pairRegisterDevice`, `register_pairings/<CODE>`) | `EXMP<4 Zeichen>` (Alphabet ohne 0/1/I/O) |
| Webhook-Secret (`secret` bei `createWebhook`/`rotateWebhookSecret`, auch im Text) | `whsec_EXAMPLE<8 hex>AAAA…` (38 Zeichen) |
| ungültige Eingaben dieser Felder | `INVALID_EXAMPLE_<8 hex>` |

In `stored/` stehen Schlüssel, Hashes und Salze als `<geheim>`. Ein Test prüft jede Datei
der Ablage: kein `_live_`, kein Wert unter einem geheimen Schlüssel außer einem
Platzhalter, und jeder Schlüssel, der nach Zugang klingt (token, password, secret, pin,
key), steht entweder unter den Geheimnissen oder mit Grund in `KEIN_GEHEIMNIS`
(`functions/test/unit/fixtures/vertrag-v3/ablage.js`).

### `_quelle`

- `sha256`: Fingerabdruck des Inhalts, SHA-256 über `JSON.stringify(inhalt, null, 2) + "\n"`,
  wobei `inhalt` die Datei ohne `_hinweis` und `_quelle` ist. Ändert sich mit jedem
  exportierten Byte; daran prüfen die Pakete ihre Kopie.
- In `antworten/kasse.json` und `stored/kasse.json` je Schreiber (`default`, `kasse`):
  `sha256` über `JSON.stringify({ head, endpoints }, null, 2) + "\n"` mit `head` = die in
  `_quelle.<teil>.head` genannten Kopfeinträge und `endpoints` = die Einträge mit
  `codebase: <teil>` in Dateireihenfolge. Die Kopfeinträge (`channel`, `note`, `baseline`)
  gehören allein dem Teil `kasse`; der Teil `default` führt nur seine Endpunkte.
- `inputsSha256`, `inputs`, `backendPackage`: Herkunft (Hash der Eingaben plus Version
  von `@kreiseck/kasseneck-api` im Backend). Kein Commit-Hash.

## Neu erzeugen

```bash
cd functions-kasse && npm run vertrag:v3
cd ../functions && npm run vertrag:v3
```

In dieser Reihenfolge (functions prüft auch den Teil aus functions-kasse). Danach
`npm test` in beiden Codebases (ohne `V3_VERTRAG_SCHREIBEN` vergleichen die Tests nur;
in der CI ist der Schreibmodus verboten) und die geänderten Dateien mit der
Code-Änderung zusammen einchecken.

## Dateien

- **`v3-vokabular.json`**
  - `endpoints`: Endpunktlisten des Rands (öffentlich, `/v3` geroutet, Kasse, nur intern).
  - `names`: Endpunktnamen, die unter `/v3` anders heißen (außen → innen).
  - `catalogs`: Wertkataloge, gespeichert (innen, deutsch) → Draht (außen, englisch);
    Grundlage für den Einstieg `./stored`.
  - `errorCodes`: `all` (jeder Code, den `/v3` senden kann), `translation` (innere →
    äußere Codes) und je Quelle: Rand (`edge`), Anmeldung (`auth`),
    `receiptMessages`, Kassen-Handler (`registerHandlers`, je Endpunkt in
    `registerHandlersByEndpoint`), Fälle der Kassen-Welt (`registerCases`), Storno,
    Zahlungen, Belegmail, Rechnung, Partner, Lager-API (`inventory`). Jeder Code, der irgendwo in `antworten/`
    vorkommt, steht in `all` (Test).
  - `noticeCodes`: Hinweis-Codes (`notice[].code` der Rechnungs-API), keine Fehler.
  - `schemas`: je Endpunkt der Eintrag des Vokabulars (Notation außen → innen);
    `{ "$catalog": … }`, `{ "$function": … }` und `{ "$pattern": … }` benennen Teile,
    die sich nicht als Daten schreiben lassen.
  - `events`: Webhook-Ereignisse; `articleFields`, `articleGroupFields`.
- **`antworten/belege.json`**: `createReceipt`, `getReceipt`, `getReportV2` unter `/v3`
  (Kanal `api`): ohne Anbieterdaten. Erfolg und Fehler (`payments_required`,
  `payments_sum_mismatch` mit `expectedCents`, …).
- **`antworten/kasse-belege.json`**: derselbe Ablauf unter `/api/v3` (Kanal `app`):
  mit `payments[].providerData`/`providerPaymentId`.
- **`antworten/storno.json`**: `cancelReceipt` in beiden Kanälen (Voll-, Teilstorno, Fehler).
- **`antworten/belegmail.json`**: `sendReceiptEmail` (Wege `own`, `platform`,
  `platform_fallback`, Fehler).
- **`antworten/rechnungen.json`**: Rechnungs-API (Probelauf, Festschreiben, Lesen,
  Liste, Storno, Gutschrift, Zahlung, Fehler).
- **`antworten/kasse.json`**: alle 25 Kassen-Endpunkte unter `/api/v3`, je Fall
  (englischer Name) Methode, Aufrufer, Parameter, HTTP-Status, Kopfzeilen und Antwort.
- **`antworten/lager.json`**: Lager-API unter `/v3` (Kanal `api`) in Ablaufreihenfolge an
  einem Konto (Bäckerei Kornblum, Standort `haupt`): Artikel, Standorte, Bestand, Bewegungen,
  mit und ohne Schalter `lagerApi.kosten`, Konto-Webhooks verwalten samt Fehlern
  (`webhook_limit`, `rate_limited` der Tagesgrenze für Probesendungen …). Dazu
  `webhookEvents`: die zugestellten Konto-Webhooks (`stock.changed`, `stock.below_minimum`,
  `article.*`), Hülle wie gesendet.
- **`stored/`**: die inneren Firestore-Dokumente (deutsch, ohne Geheimnisse), aus denen
  die Antworten entstanden; für `./stored` (gespeicherte Form → englisches Modell).
- **`zahlbetrag-faelle.json`**: Rechenfälle für `receiptDueCents(items, vouchers,
  receiptType)` (Nachtrag §8), Geld nur in ganzen Cent (`bucketsCents`: die RKSV-Töpfe je
  auf Cent gerundet, Summe = `counterDeltaCents`). `verifiedBy`: `createReceipt` bzw.
  `cancelReceipt` = gegen den echten Handler geprüft (`dueCents` wird angenommen,
  `dueCents + 1` gibt `payments_sum_mismatch` mit `expectedCents = dueCents`),
  `computed` = nur mit dem Kern gerechnet (Inhaber-Trinkgeld; die Welt kennt keinen
  Inhaber-Kassenbenutzer). `serverItems`: die Trinkgeld-Positionen genau so, wie der
  Server sie im Beleg sendet.

Jede Antwort in `antworten/` besteht den Wächter aus Stufe 4a Aufgabe 7
(`functions-kasse/test/unit/fixtures/v3-waechter.js`): kein deutsches Wort außer
Menschentext, BMF-Begriffen, freien Eingaben und Kennungen; jeder Fehler mit Code.
