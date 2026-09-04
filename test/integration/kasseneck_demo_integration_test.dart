// test/integration/kasseneck_demo_integration_test.dart
//
// Echte Requests gegen die Kasseneck-DEMO-Kasse. Bewusst OHNE
// TestWidgetsFlutterBinding: nur so ist echtes HTTP in flutter test möglich.
// Ohne credentials.local.json werden alle Tests übersprungen.
//
// Diese Ebene ist die einzige, die gegen die VERÖFFENTLICHTE Adresse spricht.
// Unit-Tests, Handler-Tests und Emulator-Läufe reden mit Attrappen oder mit
// 127.0.0.1 — eine fehlende Hosting-Weiterleitung sieht keiner von ihnen.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_tip.dart';
import 'package:kasseneck_api/src/aufrufe.dart';

import 'credentials.dart';

/// Die **öffentliche** Adresse, hier bewusst ausgeschrieben statt aus dem Paket
/// übernommen: Geprüft werden soll, dass unter der Adresse, die Fremdsysteme
/// benutzen, wirklich eine Function antwortet. Ein Test, der sich die Basis vom
/// Paket geben ließe, folgte einem falschen Wert stillschweigend mit.
const String _oeffentlicheBasis = 'https://api.kasseneck.at/v1';

/// Setzt einen Aufruf **ohne Anmeldung** ab und gibt zurück, was zurückkam.
///
/// Ohne Anmeldung antwortet eine erreichbare Function mit
/// `{"status":"error","message":"Ungültiger Request: Authorization key
/// erwartet."}` — genau das ist der Beweis, dass dort eine Function steht.
/// Fehlt die Hosting-Weiterleitung, liefert dieselbe Adresse stattdessen die
/// HTML-Auffangseite („Page Not Found"). Beides ist ein Fehler, aber nur eines
/// davon ist ein *Anmelde*fehler — und genau diese Unterscheidung ist der Kern.
Future<({int status, String rumpf})> _ohneAnmeldung(String aufruf) async {
  final antwort = await http
      .post(
        Uri.parse('$_oeffentlicheBasis/$aufruf'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'params': const <String, dynamic>{}}),
      )
      .timeout(const Duration(seconds: 30));
  return (status: antwort.statusCode, rumpf: antwort.body);
}

void main() {
  final creds = DemoCredentials.tryLoad();

  group('Kasseneck-Demo', () {
    late KasseneckApi api;

    setUp(() {
      api = KasseneckApi(
        apiKey: creds!.apiKey,
        cashregisterToken: creds.cashregisterToken,
      );
    });

    test('Nullbeleg wird ausgestellt und signiert', () async {
      final receipt = await api.zeroReceipt();
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, isNotEmpty);
      expect(receipt.receiptType, ReceiptType.zero);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Kartenzahlungs-Beleg + Storno (räumt sich selbst auf)', () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [
          KasseneckItem(
            name: 'Integrationstest Fahrt',
            quantity: 1,
            vat: VatRate.vat10,
            priceCents: 1250,
          ),
        ],
      );
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, isNotEmpty);
      expect(receipt.paymentMethod, KeckPaymentMethod.creditCard);
      expect(receipt.sumCents, 1250); // Integer-Cents bis in die Antwort
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);

      // Aufräumen gehört zum Test: Demo-Beleg sofort stornieren.
      // ignore: deprecated_member_use_from_same_package
      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.receiptType, ReceiptType.cancellation);
      expect(cancel.sumCents, -receipt.sumCents);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Trinkgeld kommt als eigene Position zurück (räumt sich selbst auf)',
        () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.cash,
        items: [
          KasseneckItem(
            name: 'Integrationstest Leistung',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 2000,
          ),
        ],
        // Ohne Empfänger: Über den API-Schlüssel ist niemand als
        // Kassen-Benutzer angemeldet, das Trinkgeld bleibt „nicht zugeordnet".
        // Genau dieser Fall trifft jede Anbindung ohne Kassen-Sitzung.
        tip: const KeckTip(cents: 150),
      );

      expect(receipt, isNotNull);
      // Der Server baut die Position — der Client hat nur den Betrag geschickt.
      expect(receipt!.tipItems.length, 1);
      expect(receipt.tipCents, 150);
      // Durchlaufender Posten: 0 %, und im Gesamtbetrag enthalten.
      expect(receipt.tipItems.single.vat.rate, 0);
      expect(receipt.staffTipCents, 150);
      expect(receipt.ownerTipCents, 0);
      expect(receipt.sumCents, 2150);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);

      // ignore: deprecated_member_use_from_same_package

      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.receiptType, ReceiptType.cancellation);
      expect(cancel.sumCents, -receipt.sumCents);
      // Die Spiegelung nimmt auch das Trinkgeld zurück — sonst bliebe der Topf
      // der Mitarbeiterin voll, obwohl der Beleg storniert ist.
      expect(cancel.tipCents, -150);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Trinkgeld an einen Kassen-Benutzer (räumt sich selbst auf)',
        () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [
          KasseneckItem(
            name: 'Integrationstest Leistung',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 2000,
          ),
        ],
        tip: KeckTip.fuer(creds!.registerUserId!, cents: 200),
      );

      expect(receipt, isNotNull);
      expect(receipt!.tipCents, 200);
      final pos = receipt.tipItems.single;
      expect(pos.tipRecipientId, creds.registerUserId);
      expect(pos.tipRecipientName, isNotNull);
      // Zahlart des Trinkgelds: ohne Angabe die des Belegs.
      expect(pos.paymentMethod, 'creditCard');

      // ignore: deprecated_member_use_from_same_package

      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.tipCents, -200);
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: creds?.registerUserId == null
            ? 'registerUserId fehlt in credentials.local.json'
            : null);

    test('Empfängerliste: unter der öffentlichen Adresse antwortet eine Function',
        () async {
      // Der Kern dieses Falls. Zwei Fehler gingen live, obwohl fünf
      // Prüfebenen grün waren — alle fünf sprachen mit Attrappen oder mit
      // 127.0.0.1. Keine sah, dass die veröffentlichte Adresse ohne
      // Hosting-Weiterleitung HTML statt JSON liefert.
      final roh = await _ohneAnmeldung(Aufrufe.listMyTipRecipients);

      // Erst die Unterscheidung HTML/JSON, und zwar mit Klartext: ein
      // blankes json.decode würde hier zwar auch werfen, aber mit einer
      // Meldung über ein unerwartetes '<' — und niemand käme darauf, dass
      // eine Route fehlt.
      final kopf = roh.rumpf.trimLeft();
      if (roh.status != 200 || kopf.startsWith('<')) {
        fail(
          'Unter $_oeffentlicheBasis/${Aufrufe.listMyTipRecipients} antwortet '
          'KEINE Function: HTTP ${roh.status}, Rumpf beginnt mit '
          '"${kopf.length > 60 ? kopf.substring(0, 60) : kopf}". '
          'Typisches Bild einer fehlenden Hosting-Weiterleitung — die Adresse '
          'landet auf der HTML-Auffangseite statt bei der Function.',
        );
      }

      final Object? geparst = jsonDecode(roh.rumpf);
      expect(geparst, isA<Map<String, dynamic>>(),
          reason: 'Antwort ist kein JSON-Objekt: ${roh.rumpf}');
      final antwort = geparst! as Map<String, dynamic>;
      // Strukturierte Antwort heißt: Erfolg/Fehler steht im Rumpf. Ein Test,
      // der nur auf status == 'error' prüfte, hätte den HTML-Fall verfehlt.
      expect(antwort['status'], isA<String>(),
          reason: 'Antwort trägt kein status-Feld: ${roh.rumpf}');
      expect(antwort['status'], 'error',
          reason: 'Ohne Anmeldung darf der Aufruf nicht durchgehen');
      expect(antwort['message'], isA<String>());
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Empfängerliste trägt je Person Kennung, Name und Inhaber-Flag',
        () async {
      final personen = await api.listTipRecipients();

      // Leer ist eine gültige Antwort (Betrieb ohne Kassen-Benutzer) — nur
      // beweist sie nichts über die Felder. Dann lieber ehrlich übersprungen
      // als still grün.
      if (personen.isEmpty) {
        markTestSkipped(
            'Demo-Kasse führt derzeit niemanden, dem sich Trinkgeld zuweisen ließe');
        return;
      }

      for (final person in personen) {
        expect(person.registerUserId, isNotEmpty,
            reason: 'Ohne Kennung lässt sich niemandem etwas zuweisen');
        expect(person.name, isNotEmpty,
            reason: 'Ohne Namen ist die Liste nicht bedienbar');
        // owner ist keine Anzeigefrage: davon hängt ab, ob das Trinkgeld
        // Entgelt des Betriebs oder durchlaufender Posten ist.
        expect(person.owner, isA<bool>());
      }
      // Kennungen müssen eindeutig sein, sonst trifft eine Zuweisung zwei.
      expect(
        personen.map((p) => p.registerUserId).toSet().length,
        personen.length,
        reason: 'Kennungen kommen doppelt vor',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Trinkgeld an eine Person AUS DER LISTE (räumt sich selbst auf)',
        () async {
      // Der geschlossene Weg: Liste holen → Person daraus nehmen → mit()
      // den Anteil bauen → verkaufen. Wer die Liste benutzt, kann keine
      // Kennung erwischen, die der Server ablehnt — hier steht, dass das
      // gegen eine echte Kasse auch stimmt.
      final personen = await api.listTipRecipients();
      if (personen.isEmpty) {
        markTestSkipped(
            'Demo-Kasse führt derzeit niemanden, dem sich Trinkgeld zuweisen ließe');
        return;
      }
      final person = personen.first;

      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [
          KasseneckItem(
            name: 'Integrationstest Leistung',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 2000,
          ),
        ],
        tip: KeckTip(cents: 300, recipients: [person.mit(cents: 300)]),
      );

      expect(receipt, isNotNull);
      expect(receipt!.tipCents, 300);
      final pos = receipt.tipItems.single;
      expect(pos.tipRecipientId, person.registerUserId,
          reason: 'Der Server hat die Kennung aus der Liste angenommen');
      expect(pos.tipRecipientName, isNotNull);
      expect(receipt.sumCents, 2300);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);

      // Aufräumen wie in den übrigen Fällen: Demo-Beleg sofort stornieren,
      // sonst bliebe der Topf der Person voll.
      // ignore: deprecated_member_use_from_same_package
      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.receiptType, ReceiptType.cancellation);
      expect(cancel.tipCents, -300);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('ein abgelehnter Betrag verursacht keinen Beleg', () async {
      // Die Prüfung liegt im Client — hier steht, dass sie auch scharf ist,
      // wenn eine echte Kasse dahinterhängt.
      expect(
        () => api.sellReceipt(
          paymentMethod: KeckPaymentMethod.cash,
          items: [
            KasseneckItem(
              name: 'Integrationstest Leistung',
              quantity: 1,
              vat: VatRate.vat20,
              priceCents: 2000,
            ),
          ],
          tip: const KeckTip(cents: 0),
        ),
        throwsArgumentError,
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('ungültiger API-Key → sauberer Serverfehler, kein Crash', () async {
      final bad = KasseneckApi(
        apiKey: 'invalid-demo-key',
        cashregisterToken: 'invalid-token',
      );
      await expectLater(bad.zeroReceipt(), throwsException);
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: creds == null
          ? 'test/integration/credentials.local.json fehlt — Demo-Integrationstests übersprungen'
          : null);
}
