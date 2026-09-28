/// Die Belegaufrufe der Kasse — Verkauf, Verlauf, Storno — auf dem
/// Kassen-Benutzer-Weg. Zwilling von `client/receipts.ts` im JS-Paket, aber
/// bewusst nur mit dem, was eine Kasse am Tresen wirklich braucht.
///
/// **Der Verkauf ist der einzige Aufruf dieser Anwendung, der nicht folgenlos
/// wiederholbar ist.** Ein Beleg geht in die Signaturkette und ins DEP; ein
/// zweiter waere ein zweiter Umsatz, den nur noch ein Storno aufhebt. Deshalb
/// geht hier genau **ein** Aufruf hinaus — auch nach einem Netzhaenger, bei dem
/// es aussieht, als waere nichts angekommen (der Beleg kann laengst signiert
/// sein). Der [RegisterTransport] haelt dieselbe Zusage; hier wird sie nicht
/// aufgeweicht.
///
/// Gerufen wird `createReceipt` und die Antwort **mitsamt Firmendaten**
/// gelesen: der Belegbildschirm braucht neben dem Beleg den Belegkopf
/// (Unternehmen, Anschrift, Steuerangabe, Fusszeilen), und das Backend liefert
/// beides in derselben Antwort. Ein zweiter Aufruf dafuer waere ein zweiter Weg,
/// auf dem etwas schiefgehen kann — mitten zwischen Beleg und Gast.
library;

import '../../enums/keck_payment_method.dart';
import '../../models/kasseneck_item.dart';
import '../../models/kasseneck_receipt.dart';
import '../../models/keck_payment.dart';
import '../../models/keck_tip_person.dart';
import '../aufrufe.dart';
import '../register/fehler.dart';
import '../register/transport.dart';
import 'artikel.dart';
import '../../models/registration_info.dart';
import 'belegmail.dart';
import 'storno.dart' show pruefeKartenRueckbuchung, stornogruende;

/// Storno-Stand eines Belegs in der Liste (Drahtfeld `cancellationStatus`,
/// Katalog `STORNO_STAND`): `none`, `partial`, `full`. Ein unbekannter
/// kuenftiger Wert kommt als [StornoStand.unknown] an und nie als `none`: die
/// Kasse bietet dann keinen Storno an (siehe `stornoErlaubt`), der Server
/// haelt ohnehin die Restmengen.
enum StornoStand { none, partial, full, unknown }

/// Eine Position, die storniert werden soll.
typedef Stornoposition = ({int index, int menge});

/// Bediener an einem Beleg.
class Belegbediener {
  const Belegbediener({required this.uid, required this.name});

  /// Kann fehlen (Altbeleg, Geraetebenutzer).
  final String? uid;
  final String name;
}

/// Ein Beleg in der Liste — eine **Zusammenfassung**, kein vollstaendiger
/// Beleg. Fuer Nachdruck oder Storno gehoert der Beleg ueber
/// [RegisterReceiptClient.holen] einzeln geholt.
class Belegzusammenfassung {
  const Belegzusammenfassung({
    required this.receiptId,
    required this.belegart,
    required this.zeitstempel,
    required this.summeCents,
    required this.zahlungsart,
    required this.signaturOk,
    required this.positionen,
    this.stornoStand,
    this.zaehler,
    this.bediener,
    this.storniertBeleg,
    this.stornogrund,
    this.nullbelegAnlass,
    this.zahlungen,
  });

  final String receiptId;

  /// Roher Wert des Backends (`standard`, `cancellation`, `zero`, …).
  final String belegart;

  /// Roher Belegzeitstempel (Wiener Wanduhrzeit ohne Offset).
  final String zeitstempel;

  /// Belegsumme in ganzen Cent. Das Backend liefert **Euro**; hier wird
  /// einmal gerundet, damit sich der Gleitkommafehler nicht bis in die
  /// Tagessumme fortpflanzt.
  final int summeCents;

  /// Einzel-Zahlungsart des Belegs; `mixed` bei mehreren Zahlarten. Ein
  /// unbekannter kuenftiger Wert gilt als Barzahlung.
  final KeckPaymentMethod zahlungsart;

  /// Zahlungsliste, nur bei Belegen, die eine tragen. Die Liste liefert nur die
  /// oeffentlichen Felder (id, method, amountCents, provider, tenderedCents,
  /// changeCents, refundOf, tipCents) -- Anbieter-Interna bleiben im Backend.
  final List<KeckPayment>? zahlungen;

  /// Wurde der Beleg mit funktionierender Signatureinheit ausgestellt?
  final bool signaturOk;

  /// Positionen kurz (Name, Menge) — nur zur Anzeige in der Liste.
  final List<({String name, int menge})> positionen;

  /// `null`, wenn die Liste den Stand nicht nennt (der Server laesst ihn in
  /// manchen Listen weg); das wird nie zu [StornoStand.none].
  final StornoStand? stornoStand;

  /// Fortlaufender Belegzaehler der Kasse; fehlt bei Alt-Belegen.
  final int? zaehler;

  final Belegbediener? bediener;

  /// Nur am Storno-Beleg: das Original.
  final String? storniertBeleg;
  final String? stornogrund;

  /// Nur am Nullbeleg: Anlass (`monthly`, `annual`, `outage_end`, `final`, …).
  final String? nullbelegAnlass;

  bool get istStorno => belegart == 'cancellation' || storniertBeleg != null;
  bool get istVerkauf => belegart == 'standard' && storniertBeleg == null;

  factory Belegzusammenfassung.aus(Map<String, dynamic> json) {
    final bediener = json['operator'];
    final bezug = json['cancellationOf'];
    return Belegzusammenfassung(
      receiptId: json['receiptId'] is String ? json['receiptId'] as String : '',
      belegart: json['receiptType'] is String ? json['receiptType'] as String : '',
      zeitstempel: json['timeStamp'] is String ? json['timeStamp'] as String : '',
      summeCents: _euroInCent(json['total']),
      zahlungsart: KeckPaymentMethod.values.firstWhere(
        (z) => z.name == json['paymentMethod'],
        orElse: () => KeckPaymentMethod.cash,
      ),
      // Das Backend meldet hier `signatureSuccess != false` — also true,
      // solange nichts Gegenteiliges vermerkt ist.
      signaturOk: json['signature_ok'] != false,
      positionen: [
        for (final p in (json['items'] as List?) ?? const [])
          if (p is Map)
            (
              name: p['name'] is String ? p['name'] as String : '',
              menge: p['quantity'] is num ? (p['quantity'] as num).toInt() : 0,
            ),
      ],
      stornoStand: switch (json['cancellationStatus']) {
        null => null,
        'none' => StornoStand.none,
        'partial' => StornoStand.partial,
        'full' => StornoStand.full,
        _ => StornoStand.unknown,
      },
      zaehler: json['counter'] is num ? (json['counter'] as num).toInt() : null,
      bediener: bediener is Map
          ? Belegbediener(
              uid: bediener['uid'] is String ? bediener['uid'] as String : null,
              name: bediener['name'] is String ? bediener['name'] as String : '',
            )
          : null,
      storniertBeleg: bezug is Map && bezug['receiptId'] is String ? bezug['receiptId'] as String : null,
      stornogrund: json['cancellationReason'] is String ? json['cancellationReason'] as String : null,
      nullbelegAnlass: json['zeroKind'] is String ? json['zeroKind'] as String : null,
      zahlungen: KeckPayment.listeAus(json['payments']),
    );
  }
}

/// Ergebnis eines Stornos: der neue, signierte Storno-Beleg, der Bezug zum
/// Original und die verbliebenen Restmengen je Position.
class Stornoergebnis {
  const Stornoergebnis({
    required this.beleg,
    required this.originalReceiptId,
    required this.restmengen,
    this.originalFullReceiptId,
    this.originalTimeStamp,
  });

  final KasseneckReceipt beleg;
  final String originalReceiptId;
  final String? originalFullReceiptId;

  /// Zeitstempel des Originals (`cancellationOf.timeStamp`, Wiener Wanduhr);
  /// fehlt bei Altbelegen.
  final String? originalTimeStamp;

  /// Liest die Storno-Antwort `{receipt, cancellationOf, remaining}`. Wirft
  /// [KasseneckValidationError] (Antwortfehler), wenn Bezug oder Restmengen
  /// fehlen; die Aufrufer machen daraus `response_unreadable`.
  static Stornoergebnis ausAntwort(String name, Map<String, dynamic> daten, KasseneckReceipt Function() beleg) {
    final bezug = CancellationOf.fromJson(daten['cancellationOf']);
    if (bezug == null) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen Bezug (data.cancellationOf fehlt)', 'response');
    }
    final rest = daten['remaining'];
    if (rest is! List || rest.any((n) => n is! int)) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keine Restmengen (data.remaining fehlt)', 'response');
    }
    return Stornoergebnis(
      beleg: beleg(),
      originalReceiptId: bezug.receiptId,
      originalFullReceiptId: bezug.fullReceiptId,
      originalTimeStamp: bezug.timeStamp,
      restmengen: rest.cast<int>(),
    );
  }

  /// Was von jeder Position des Originals noch offen ist — daraus weiss die
  /// Kasse, ob ein weiteres Teilstorno noch moeglich ist.
  final List<int> restmengen;
}

const int _anmerkungHoechstlaenge = 200;

/// Eine Kasse aus `listMyCashregisters` (Draht `/v3`). Zeitpunkte bleiben
/// Text (ISO, UTC); ein fehlender ist `null`, nie ein erfundenes Datum.
class KassenEintrag {
  const KassenEintrag({
    required this.id,
    required this.onboarding,
    this.label,
    this.description,
    this.createTime,
    this.signatureId,
    this.token,
    this.finalReceiptId,
    this.decommissioned = false,
    this.licenses,
    this.monthlyReportJournal = false,
  });

  final String id;
  final String? label;
  final String? description;
  final String? createTime;
  final String? signatureId;

  /// Kassen-Token; für Kassen-Benutzer ist er bewusst `null`.
  final String? token;
  final String? finalReceiptId;

  /// Außer Betrieb genommen (Schlussbeleg); es entstehen keine Belege mehr.
  final bool decommissioned;
  final int? licenses;
  final bool monthlyReportJournal;
  final KassenInbetriebnahme onboarding;

  factory KassenEintrag.aus(Map<String, dynamic> j) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final ob = j['onboarding'];
    final o = ob is Map ? ob : const {};
    return KassenEintrag(
      id: text(j['id']) ?? '',
      label: text(j['label']),
      description: text(j['description']),
      createTime: text(j['create_time']),
      signatureId: text(j['signature_id']),
      token: text(j['token']),
      finalReceiptId: text(j['final_receipt_id']),
      decommissioned: j['decommissioned'] == true,
      licenses: j['licenses'] is num ? (j['licenses'] as num).toInt() : null,
      monthlyReportJournal: j['monthly_report_journal'] == true,
      onboarding: KassenInbetriebnahme(
        cashboxRegistered: o['cashbox_registered'] == true,
        startReceiptCreated: o['start_receipt_created'] == true,
        startReceiptTransmitted: o['start_receipt_transmitted'] == true,
        cashboxRegisteredAt: text(o['cashbox_registered_at']),
        startReceiptCreatedAt: text(o['start_receipt_created_at']),
        startReceiptTransmittedAt: text(o['start_receipt_transmitted_at']),
      ),
    );
  }
}

/// Stand der Inbetriebnahme (RKSV): bei FinanzOnline registriert, Startbeleg
/// erzeugt und übermittelt.
class KassenInbetriebnahme {
  const KassenInbetriebnahme({
    required this.cashboxRegistered,
    required this.startReceiptCreated,
    required this.startReceiptTransmitted,
    this.cashboxRegisteredAt,
    this.startReceiptCreatedAt,
    this.startReceiptTransmittedAt,
  });

  final bool cashboxRegistered;
  final bool startReceiptCreated;
  final bool startReceiptTransmitted;
  final String? cashboxRegisteredAt;
  final String? startReceiptCreatedAt;
  final String? startReceiptTransmittedAt;
}

class RegisterReceiptClient {
  /// [testEnvironment]: das Gerät hängt an einer Test-Umgebung
  /// ([PairedRegisterDevice.testEnvironment] bzw. die Benutzerliste). Dann
  /// trägt jeder Storno-Beleg TESTKASSE, auch ohne das Original.
  RegisterReceiptClient(this.transport, {Duration? abschlussFrist, this.testEnvironment = false})
      : abschlussFrist = abschlussFrist ?? const Duration(seconds: 90);

  final RegisterTransport transport;

  /// Siehe Konstruktor.
  final bool testEnvironment;

  /// Der Abschluss darf laenger warten als eine Belegliste: die Signatureinheit
  /// braucht ihre Zeit, und ein Abbruch beendet nur das Warten der Kasse, nicht
  /// die Arbeit des Servers.
  final Duration abschlussFrist;

  /// Normalbeleg (Verkauf): der signierte Beleg samt Belegkopf.
  ///
  /// Unter `/v3` gehen die Zahlungen **immer** als [zahlungen] hinaus (siehe
  /// [KeckPaymentInput]: Karte mit Anbieter und Kennung, Bar mit
  /// `tenderedCents`), nie die Einzelfelder `paymentMethod`,
  /// `creditCardProvider`, `cardPaymentId`, `cardPaymentData` aus 0.x; `mixed`
  /// wird nie gesendet. Den Zahlbetrag rechnet der Server; weicht die Summe
  /// ab, kommt `payments_sum_mismatch` mit `expectedCents`
  /// ([paymentsExpectedCents]), und es wurde nichts signiert.
  Future<KasseneckReceipt> verkaufen({
    required List<KasseneckItem> positionen,
    required List<KeckPaymentInput> zahlungen,
    int? trinkgeldCents,
    List<String>? kundendaten,
    List<String>? rechtshinweise,
  }) async {
    const name = Aufrufe.createReceipt;
    if (positionen.isEmpty) {
      // Ein leerer Verkauf ist kein Verkauf, und der Fehler soll fallen,
      // bevor irgendetwas in die Signaturkette geraet.
      throw const KasseneckValidationError(name, 'Positionen fehlen', 'request');
    }
    if (positionen.any((p) => !p.isValid)) {
      throw const KasseneckValidationError(name, 'Ungueltige Position uebergeben', 'request');
    }
    if (trinkgeldCents != null && trinkgeldCents < 0) {
      throw const KasseneckValidationError(name, 'Trinkgeld muss >= 0 sein', 'request');
    }
    final fehler = zahlungenFehler(zahlungen, storno: false);
    if (fehler != null) throw KasseneckValidationError(name, fehler, 'request');

    final daten = await _signiertRufen(
      name,
      params: {
        'receiptType': 'standard',
        'items': positionen.map((p) => p.toJson()).toList(),
        'payments': [for (final z in zahlungen) z.toJson()],
        if (trinkgeldCents != null && trinkgeldCents > 0) 'tip': trinkgeldCents,
        if (kundendaten != null && kundendaten.isNotEmpty) 'customerDetails': kundendaten.join('\n'),
        if (rechtshinweise != null && rechtshinweise.isNotEmpty) 'legalMessage': rechtshinweise.join('\n'),
      },
    );
    // Ab hier ist der Beleg signiert: wer ihn nicht lesen kann, bekommt
    // `response_unreadable` (Ausgang unklar) mit der Kennung, nie einen
    // gewoehnlichen Fehler, der zum zweiten Verkauf einluede.
    return readSignedResponse(name, () => _belegAus(daten, name), kennung: () => _kennungAus(daten));
  }

  /// Belege dieser Kasse — Zusammenfassungen, neueste zuerst (Serverordnung).
  ///
  /// [von] und [bis] sind Wiener Kalendertage (`YYYY-MM-DD`); der Server
  /// deckelt das Fenster auf 90 Tage und die Anzahl auf 200.
  Future<List<Belegzusammenfassung>> auflisten({String? von, String? bis, int? hoechstens}) async {
    const name = Aufrufe.listMyReceipts;
    for (final (feld, wert) in [('von', von), ('bis', bis)]) {
      if (wert != null && !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(wert)) {
        throw KasseneckValidationError(name, '$feld muss mit YYYY-MM-DD beginnen', 'request');
      }
    }
    if (hoechstens != null && hoechstens < 1) {
      throw const KasseneckValidationError(name, 'hoechstens muss eine ganze Zahl ab 1 sein', 'request');
    }

    final daten = await transport.rufen(
      name,
      params: {
        'cashregisterId': transport.cashregisterId,
        'from': von,
        'to': bis,
        'limit': hoechstens,
      },
    );
    final liste = daten['receipts'];
    if (liste is! List) {
      // Keine Liste ist etwas anderes als eine leere Liste: „heute nichts
      // verkauft" darf nicht aussehen wie „Antwort kaputt".
      throw const KasseneckValidationError(name, 'Antwort enthaelt keine Belegliste (data.receipts fehlt)', 'response');
    }
    return [
      for (final eintrag in liste)
        if (eintrag is Map) Belegzusammenfassung.aus(Map<String, dynamic>.from(eintrag)),
    ];
  }

  /// Einen Beleg vollstaendig holen — samt Belegkopf, fuer Nachdruck und Storno.
  Future<KasseneckReceipt> holen(String receiptId) async {
    const name = Aufrufe.getReceipt;
    if (receiptId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'receiptId fehlt', 'request');
    }
    return _belegAus(await transport.rufen(name, params: {'receiptId': receiptId}), name);
  }

  /// Storno-Beleg zu einem bestehenden Beleg — voll oder in Teilen.
  ///
  /// Ohne [positionen] ist es ein Vollstorno. Eine **leere** Positionsliste ist
  /// dagegen ein Fehler: sonst wuerde aus einem missglueckten Teilstorno still
  /// ein Vollstorno.
  ///
  /// Die Restmengen und die Reichweite des Rechts haelt der Server; die Kasse
  /// bietet nur an, was sie fuer moeglich haelt.
  ///
  /// [grund] ist ein Code aus `stornogruende` (`input_error` …, wie unter
  /// `/v3`); ein unbekannter wirft, bevor etwas hinausgeht.
  ///
  /// [zahlungen] sind die Rueckzahlungen je Zahlung (Betraege negativ,
  /// `refundOf` = `id` der Originalzahlung). Ohne Angabe spiegelt der Server
  /// die Restbetraege jeder Originalzahlung; ein Teilstorno eines Belegs mit
  /// mehreren Zahlungen braucht sie (`cancellation_payments_required`). Eine
  /// Einzel-Zahlungsart am Storno gibt es unter `/v3` nicht mehr.
  ///
  /// **Karten-Storno:** `provider`, `providerPaymentId` und `providerData` der
  /// Zahlung beschreiben die ERSTATTUNG am Terminal. Eine Karten-Rueckbuchung
  /// ueber einen Anbieter braucht einen Bezug: ihre eigene `providerPaymentId`
  /// oder, mit [original], die Kennung der erstatteten Kartenzahlung dort
  /// (`cardRefundReference`). Fehlt beides, wirft der Aufruf vor dem Senden.
  Future<Stornoergebnis> stornieren({
    required String originalReceiptId,
    required String grund,
    List<Stornoposition>? positionen,
    String? anmerkung,
    List<KeckPaymentInput>? zahlungen,
    KasseneckReceipt? original,
  }) async {
    const name = Aufrufe.cancelReceipt;
    if (originalReceiptId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'originalReceiptId fehlt', 'request');
    }
    if (!stornogruende.containsKey(grund)) {
      throw const KasseneckValidationError(name, 'Storno-Grund fehlt oder ist unbekannt', 'request');
    }
    if (positionen != null) {
      if (positionen.isEmpty) {
        throw const KasseneckValidationError(name, 'positionen muss eine nicht leere Liste sein', 'request');
      }
      if (positionen.any((p) => p.index < 0 || p.menge < 1)) {
        throw const KasseneckValidationError(name, 'Storno-Menge muss eine ganze Zahl >= 1 sein', 'request');
      }
    }
    if (anmerkung != null && anmerkung.length > _anmerkungHoechstlaenge) {
      throw const KasseneckValidationError(name, 'Anmerkung ist zu lang', 'request');
    }
    if (zahlungen != null) {
      final fehler = zahlungenFehler(zahlungen, storno: true);
      if (fehler != null) throw KasseneckValidationError(name, fehler, 'request');
    }
    if (original != null && original.receiptId != originalReceiptId) {
      throw KasseneckValidationError(
          name, 'original (${original.receiptId}) ist nicht der Beleg originalReceiptId ($originalReceiptId)', 'request');
    }
    if (zahlungen != null) pruefeKartenRueckbuchung(zahlungen, original);

    final daten = await _signiertRufen(
      name,
      params: {
        'originalReceiptId': originalReceiptId,
        'reason': grund,
        if (positionen != null) 'items': [for (final p in positionen) {'index': p.index, 'quantity': p.menge}],
        if (anmerkung != null && anmerkung.isNotEmpty) 'note': anmerkung,
        if (zahlungen != null) 'payments': [for (final z in zahlungen) z.toJson()],
      },
    );

    // Ab hier ist der Storno-Beleg ausgestellt und signiert. Scheitert das
    // Lesen, kommt `response_unreadable` (Ausgang unklar) mit der Kennung,
    // sofern die Antwort sie mitbrachte: ohne sie ist der gesetzlich
    // vorgeschriebene Storno-Beleg da, aber fuer die Kasse unerreichbar, und
    // ein zweiter Storno waere eine zweite Ruecknahme.
    final Stornoergebnis ergebnis = readSignedResponse(
      name,
      () => Stornoergebnis.ausAntwort(name, daten, () => _belegAus(daten, name)),
      kennung: () => _kennungAus(daten),
    );
    // Die Storno-Antwort trägt weder Layout noch Testkennzeichen. Damit der
    // Storno einer Testkasse nie wie ein gültiger Beleg gedruckt wird, gelten
    // die Kennzeichen des Originals, und eine Test-Umgebung steht für
    // TESTKASSE (wie `KasseneckApi.stornieren` mit `kr_test_`).
    final beleg = ergebnis.beleg;
    if (original?.testCashregister == true || testEnvironment) beleg.testCashregister = true;
    if (original?.testSignature == true && !beleg.testCashregister) beleg.testSignature = true;
    return ergebnis;
  }

  /// Verschlüsselte Volltext-Belegnummer (`generateFullReceiptId`): der
  /// Bezeichner, unter dem der Beleg öffentlich abrufbar ist.
  Future<String> volleBelegId(String receiptId) async {
    const name = Aufrufe.generateFullReceiptId;
    if (receiptId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'receiptId fehlt', 'request');
    }
    final daten = await transport.rufen(name, params: {'receiptId': receiptId});
    final id = daten['fullReceiptId'];
    if (id is! String || id.isEmpty) {
      throw const KasseneckValidationError(name, 'Antwort enthaelt keine fullReceiptId', 'response');
    }
    return id;
  }

  /// Die Kassen, die dem angemeldeten Benutzer offenstehen
  /// (`listMyCashregisters`); für einen Kassen-Benutzer genau die ihm
  /// zugewiesenen.
  Future<List<KassenEintrag>> kassen() async =>
      _liste(Aufrufe.listMyCashregisters, 'cashregisters', KassenEintrag.aus);

  /// Einen bereits ausgestellten Beleg als **Link auf die oeffentliche
  /// Belegseite** an [an] schicken (`sendReceiptEmail`).
  ///
  /// Der Beleg bleibt dabei byteidentisch: das Backend schreibt den Versand in
  /// die Unter-Sammlung `receipts/{id}/mails`, nie an den Beleg selbst (DEP,
  /// BAO §131). Welcher Beleg gemeint ist, sagt [fullReceiptId]; welche Kasse,
  /// entscheidet die **angemeldete** Sitzung — ein Beleg einer anderen Kasse
  /// kommt als `receipt_not_found` zurueck, genau wie ein Beleg, den es
  /// nicht gibt.
  ///
  /// [language] nimmt das Backend heute entgegen, ohne es auszuwerten (es gibt
  /// eine Fassung, Deutsch). Es steht im Vertrag, damit eine zweite Sprache
  /// spaeter kein neuer Aufruf wird.
  ///
  /// **Die Adresse wird hier nicht auf Form geprueft.** Es gibt genau eine
  /// Adresspruefung, und die steht im Backend; eine zweite, anders strenge
  /// wiese Adressen ab, die dort durchgehen — und mit einem Fehlertyp, an dem
  /// die Kasse nicht entscheiden kann. Abgewiesen wird hier nur die **leere**
  /// Angabe, die gar keine Adresse ist.
  ///
  /// Fachliche Ablehnungen kommen als [KasseneckApiError] mit einem Code aus
  /// [belegMailFehlercodes] — daran entscheiden, nie am Text.
  Future<Belegmailergebnis> belegSenden({
    required String fullReceiptId,
    required String an,
    String? language,
  }) async {
    const name = Aufrufe.sendReceiptEmail;
    final beleg = fullReceiptId.trim();
    final adresse = an.trim();
    if (beleg.isEmpty) {
      throw const KasseneckValidationError(name, 'fullReceiptId fehlt', 'request');
    }
    if (adresse.isEmpty) {
      throw const KasseneckValidationError(name, 'to fehlt', 'request');
    }
    final gewuenschteSprache = language?.trim() ?? '';

    // Die Kasse steht im Transport (er legt `cashregisterId` zu jeder Nutzlast)
    // — hier nicht ein zweites Mal, sonst gaebe es zwei Angaben, die sich
    // widersprechen koennten.
    final daten = await transport.rufen(
      name,
      params: {
        'fullReceiptId': beleg,
        'to': adresse,
        if (gewuenschteSprache.isNotEmpty) 'language': gewuenschteSprache,
      },
    );

    return Belegmailergebnis.aus(daten, gesendetAn: adresse);
  }

  /// Artikelgruppen (Kategorien der Kachel-Kasse).
  Future<List<Artikelgruppe>> artikelgruppen() async =>
      _liste(Aufrufe.listMyArticleGroups, 'groups', Artikelgruppe.aus);

  /// Artikel in der Form, die die Kacheln brauchen.
  Future<List<KasseArtikel>> artikel() async => _liste(Aufrufe.listMyArticles, 'articles', KasseArtikel.aus);

  /// Personen, denen sich Trinkgeld zuweisen laesst. Dieselbe Menge, die der
  /// Verkauf akzeptiert; ohne das Recht `tipAssign` steht nur der Angemeldete
  /// darin.
  Future<List<KeckTipPerson>> tipEmpfaenger() async =>
      _liste(Aufrufe.listMyTipRecipients, 'recipients', KeckTipPerson.aus);

  Future<List<T>> _liste<T>(String name, String feld, T Function(Map<String, dynamic>) lesen) async {
    final daten = await transport.rufen(name);
    final roh = daten[feld];
    if (roh is! List) {
      // Keine Liste ist etwas anderes als eine leere Liste: „noch keine
      // Artikel angelegt" darf nicht aussehen wie „Antwort kaputt".
      throw KasseneckValidationError(name, 'Antwort enthaelt keine Liste (data.$feld fehlt)', 'response');
    }
    return [
      for (final e in roh)
        if (e is Map) lesen(Map<String, dynamic>.from(e)),
    ];
  }

  /// Ein signierender Aufruf (Verkauf, Storno): `data` kein Objekt nach
  /// gemeldetem Erfolg ist wie jede unlesbare Erfolgsantwort
  /// `response_unreadable` mit Ausgang unklar, derselbe Code wie am
  /// API-Schluessel-Weg. Alle anderen Fehler bleiben, wie sie sind.
  Future<Map<String, dynamic>> _signiertRufen(String name, {required Map<String, dynamic> params}) async {
    try {
      return await transport.rufen(name, params: params, frist: abschlussFrist);
    } on KasseneckHttpError catch (e) {
      if (e.reason != 'data-not-object') rethrow;
      return readSignedResponse(name, () => throw e);
    }
  }

  /// Beleg samt Belegkopf aus der Antworthuelle. Fehlt der Beleg, ist das ein
  /// Antwortfehler — nicht ein leerer Beleg, mit dem der Bildschirm dann
  /// hantieren muesste.
  KasseneckReceipt _belegAus(Map<String, dynamic> daten, String name) {
    if (daten['receipt'] is! Map) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen Beleg (data.receipt fehlt)', 'response');
    }
    try {
      return KasseneckReceipt.fromJson(daten);
    } on KasseneckReceiptFormatError {
      // Traegt die Kennung bereits — durchreichen, nicht neu verpacken.
      rethrow;
    } catch (e) {
      // Der Beleg ist an dieser Stelle ausgestellt und signiert. Ohne die
      // Kennung bliebe nichts, womit er sich nachholen liesse, und der
      // naheliegende zweite Versuch waere ein zweiter Umsatz.
      throw KasseneckReceiptFormatError(
        'receipt',
        receiptId: _kennungAus(daten),
        causeType: e.runtimeType.toString(),
      );
    }
  }
}

/// Die Belegkennung aus einer Antworthuelle — defensiv, wirft nie.
String? _kennungAus(Map<String, dynamic> daten) {
  final beleg = daten['receipt'];
  final wert = beleg is Map ? beleg['receiptId'] : null;
  return wert is String && wert.isNotEmpty ? wert : null;
}

/// Euro-Betrag des Backends in ganze Cent. Einmal gerundet, damit sich der
/// Gleitkommafehler nicht fortpflanzt.
int _euroInCent(Object? wert) => wert is num ? (wert * 100).round() : 0;
