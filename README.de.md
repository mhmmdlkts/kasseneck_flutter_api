# kasseneck_api (Deutsch)

**RKSV-Registrierkasse für Flutter aus Österreich.** Dieses Paket ist der
Flutter-Client für **Kasseneck**: Ihre App stellt Belege aus, storniert sie,
nimmt Kartenzahlungen entgegen und druckt Bons. Signatur, Verkettung, DEP und
FinanzOnline-Meldungen übernimmt das Kasseneck-Backend.

Die vollständige Dokumentation steht im englischen README:
**[README.md](https://github.com/mhmmdlkts/kasseneck_flutter_api/blob/main/README.md)**.

## Einbinden

```yaml
dependencies:
  kasseneck_api: ^9.1.0
```

Voraussetzungen: Dart SDK `^3.12.1`, Flutter `>=3.44.0`, ein Kasseneck-API-Schlüssel
und ein Kassen-Token ([kasseneck.at/kontakt](https://kasseneck.at/kontakt)).

## Ein Beleg in wenigen Zeilen

```dart
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';

final kasseneck = KasseneckApi(apiKey: 'IHR_API_SCHLUESSEL', cashregisterToken: 'IHR_KASSEN_TOKEN');

// Preise in ganzen Cent (320 = 3,20 €)
final beleg = await kasseneck.sellReceipt(
  paymentMethod: KeckPaymentMethod.cash,
  items: [KasseneckItem(name: 'Kaffee', quantity: 2, vat: VatRate.vat20, priceCents: 320)],
);
print('Beleg ${beleg?.receiptId}, signiert: ${beleg?.signatureSuccess}');
```

Stornos laufen über `kasseneck.stornieren(...)` bzw. `RegisterReceiptClient.stornieren(...)`,
nicht über das veraltete `cancelReceipt`.

## Welche RKSV-Pflichten die Software abdeckt

| Aufgabe | Wo sie erledigt wird |
| --- | --- |
| [Signaturerstellungseinheit](https://kasseneck.at/wissen/signaturerstellungseinheit) | Kasseneck, nichts zu installieren |
| [Verkettung und DEP](https://kasseneck.at/wissen/dep) | Kasseneck-Backend |
| [Startbeleg, Monatsbeleg, Jahresbeleg](https://kasseneck.at/wissen/startbeleg-monatsbeleg-jahresbeleg) | Kasseneck, automatisch |
| [Meldungen an FinanzOnline](https://kasseneck.at/wissen/finanzonline) | Kasseneck-Backend |
| [Belegerteilungspflicht](https://kasseneck.at/wissen/belegerteilungspflicht) | **dieses Paket**: Bon, Bildschirm oder Link per E-Mail |
| [Ausfall der Signatureinheit](https://kasseneck.at/wissen/ausfall) | Kasseneck, automatisch |
| [Kassennachschau](https://kasseneck.at/wissen/kassennachschau) | Kasseneck, DEP-Export |
| Anmeldung der Kasse, Aufbewahrung, steuerliche Würdigung | **beim Unternehmer** |

> **Kein Rechts- oder Steuerrat.** Die Tabelle beschreibt, was die Software tut.
> Verbindlich sind die Bundesabgabenordnung, die RKSV und die Erlässe des BMF;
> Anmeldung, Betrieb und Aufbewahrung bleiben Pflicht des Unternehmers.
> Mehr mit Quellen: [kasseneck.at/wissen](https://kasseneck.at/wissen).
> Stand: September 2026.

## Kontakt

**Kasseneck** ist ein Produkt von [Kreiseck Software Solutions](https://kreiseck.com)
aus Salzburg. Fragen zur Schnittstelle oder zu eigenen Integrationen:
[kasseneck.at/kontakt](https://kasseneck.at/kontakt).
