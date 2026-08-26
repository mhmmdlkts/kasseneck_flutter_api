/// Die Belegaufrufe der Kasse — Verkauf, Verlauf, Storno — auf dem
/// Kassen-Benutzer-Weg. Zwilling von `client/receipts.ts` im JS-Paket, aber
/// bewusst nur mit dem, was eine Kasse am Tresen wirklich braucht.
///
/// **Der Verkauf ist der einzige Aufruf dieser Anwendung, der nicht folgenlos
/// wiederholbar ist.** Ein Beleg geht in die Signaturkette und ins DEP; ein
/// zweiter wäre ein zweiter Umsatz, den nur noch ein Storno aufhebt. Deshalb
/// geht hier genau **ein** Aufruf hinaus — auch nach einem Netzhänger, bei dem
/// es aussieht, als wäre nichts angekommen (der Beleg kann längst signiert
/// sein). Der [RegisterTransport] hält dieselbe Zusage; hier wird sie nicht
/// aufgeweicht.
///
/// Gerufen wird `createReceipt` und die Antwort **mitsamt Firmendaten**
/// gelesen: der Belegbildschirm braucht neben dem Beleg den Belegkopf
/// (Unternehmen, Anschrift, Steuerangabe, Fußzeilen), und das Backend liefert
/// beides in derselben Antwort. Ein zweiter Aufruf dafür wäre ein zweiter Weg,
/// auf dem etwas schiefgehen kann — mitten zwischen Beleg und Gast.
library;

import '../../enums/keck_payment_method.dart';
import '../../models/kasseneck_item.dart';
import '../../models/kasseneck_receipt.dart';
import '../../models/keck_tip_person.dart';
import '../aufrufe.dart';
import '../register/fehler.dart';
import '../register/transport.dart';
import 'artikel.dart';

/// Storno-Stand eines Belegs. Ein unbekannter künftiger Wert gilt als
/// [StornoStand.offen] — beim Lesen ist dieses Paket tolerant, die Grenze
/// zieht ohnehin das Backend.
enum StornoStand { offen, teil, voll }

/// Eine Position, die storniert werden soll.
typedef Stornoposition = ({int index, int menge});

/// Bediener an einem Beleg.
class Belegbediener {
  const Belegbediener({required this.uid, required this.name});

  /// Kann fehlen (Altbeleg, Gerätebenutzer).
  final String? uid;
  final String name;
}

/// Ein Beleg in der Liste — eine **Zusammenfassung**, kein vollständiger
/// Beleg. Für Nachdruck oder Storno gehört der Beleg über
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
    required this.stornoStand,
    this.zaehler,
    this.bediener,
    this.storniertBeleg,
    this.stornogrund,
    this.nullbelegAnlass,
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

  final KeckPaymentMethod zahlungsart;

  /// Wurde der Beleg mit funktionierender Signatureinheit ausgestellt?
  final bool signaturOk;

  /// Positionen kurz (Name, Menge) — nur zur Anzeige in der Liste.
  final List<({String name, int menge})> positionen;

  final StornoStand stornoStand;

  /// Fortlaufender Belegzähler der Kasse; fehlt bei Alt-Belegen.
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
      stornoStand: switch (json['stornoStand']) {
        'teil' => StornoStand.teil,
        'voll' => StornoStand.voll,
        _ => StornoStand.offen,
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
  });

  final KasseneckReceipt beleg;
  final String originalReceiptId;
  final String? originalFullReceiptId;

  /// Was von jeder Position des Originals noch offen ist — daraus weiß die
  /// Kasse, ob ein weiteres Teilstorno noch möglich ist.
  final List<int> restmengen;
}

const int _anmerkungHoechstlaenge = 200;

class RegisterReceiptClient {
  RegisterReceiptClient(this.transport, {Duration? abschlussFrist})
      : abschlussFrist = abschlussFrist ?? const Duration(seconds: 90);

  final RegisterTransport transport;

  /// Der Abschluss darf länger warten als eine Belegliste: die Signatureinheit
  /// braucht ihre Zeit, und ein Abbruch beendet nur das Warten der Kasse, nicht
  /// die Arbeit des Servers.
  final Duration abschlussFrist;

  /// Normalbeleg (Verkauf) — der signierte Beleg samt Belegkopf.
  Future<KasseneckReceipt> verkaufen({
    required List<KasseneckItem> positionen,
    required KeckPaymentMethod zahlungsart,
    int? trinkgeldCents,
    List<String>? kundendaten,
    List<String>? rechtshinweise,
    String? kartenzahlungId,
    Map<String, dynamic>? kartenzahlungsdaten,
  }) async {
    const name = Aufrufe.createReceipt;
    if (positionen.isEmpty) {
      // Ein leerer Verkauf ist kein Verkauf — und der Fehler soll fallen,
      // bevor irgendetwas in die Signaturkette gerät.
      throw const KasseneckValidationError(name, 'Positionen fehlen', 'request');
    }
    if (positionen.any((p) => !p.isValid)) {
      throw const KasseneckValidationError(name, 'Ungueltige Position uebergeben', 'request');
    }
    if (trinkgeldCents != null && trinkgeldCents < 0) {
      throw const KasseneckValidationError(name, 'Trinkgeld muss >= 0 sein', 'request');
    }

    final daten = await transport.rufen(
      name,
      params: {
        'receiptType': 'standard',
        'items': positionen.map((p) => p.toJson()).toList(),
        'paymentMethod': zahlungsart.name,
        if (trinkgeldCents != null && trinkgeldCents > 0) 'tip': trinkgeldCents,
        if (kundendaten != null && kundendaten.isNotEmpty) 'customerDetails': kundendaten.join('\n'),
        if (rechtshinweise != null && rechtshinweise.isNotEmpty) 'legalMessage': rechtshinweise.join('\n'),
        if (kartenzahlungId != null) 'cardPaymentId': kartenzahlungId,
        if (kartenzahlungsdaten != null) 'cardPaymentData': kartenzahlungsdaten,
      },
      frist: abschlussFrist,
    );
    return _belegAus(daten, name);
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
        // Klein geschrieben — anders als das `cashregisterId` der Sitzung. So
        // heisst der Pflichtparameter dieses Endpunkts im Backend.
        'cashregisterid': transport.cashregisterId,
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

  /// Einen Beleg vollständig holen — samt Belegkopf, für Nachdruck und Storno.
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
  /// dagegen ein Fehler: sonst würde aus einem missglückten Teilstorno still
  /// ein Vollstorno.
  ///
  /// Die Restmengen und die Reichweite des Rechts hält der Server; die Kasse
  /// bietet nur an, was sie für möglich hält.
  Future<Stornoergebnis> stornieren({
    required String originalReceiptId,
    required String grund,
    List<Stornoposition>? positionen,
    String? anmerkung,
    KeckPaymentMethod? zahlungsart,
  }) async {
    const name = Aufrufe.cancelReceipt;
    if (originalReceiptId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'originalReceiptId fehlt', 'request');
    }
    if (grund.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'Storno-Grund fehlt', 'request');
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

    final daten = await transport.rufen(
      name,
      params: {
        'originalReceiptId': originalReceiptId,
        'reason': grund.trim(),
        if (positionen != null) 'items': [for (final p in positionen) {'index': p.index, 'quantity': p.menge}],
        if (anmerkung != null && anmerkung.isNotEmpty) 'note': anmerkung,
        if (zahlungsart != null) 'paymentMethod': zahlungsart.name,
      },
      frist: abschlussFrist,
    );

    // Ab hier ist der Storno-Beleg ausgestellt und signiert. Jeder Fehler
    // dieses Abschnitts traegt deshalb die Kennung mit, sofern die Antwort sie
    // mitbrachte: ohne sie ist der gesetzlich vorgeschriebene Storno-Beleg da,
    // aber fuer die Kasse unerreichbar — sie kann ihn weder drucken noch
    // nachholen, und ein zweiter Storno waere eine zweite Ruecknahme.
    final String? kennung = _kennungAus(daten);

    final bezug = daten['cancellationOf'];
    if (bezug is! Map || bezug['receiptId'] is! String) {
      throw KasseneckValidationError(
          name, 'Antwort enthaelt keinen Bezug (data.cancellationOf fehlt)', 'response',
          receiptId: kennung);
    }
    final rest = daten['remaining'];
    if (rest is! List || rest.any((n) => n is! int)) {
      throw KasseneckValidationError(
          name, 'Antwort enthaelt keine Restmengen (data.remaining fehlt)', 'response',
          receiptId: kennung);
    }
    return Stornoergebnis(
      beleg: _belegAus(daten, name),
      originalReceiptId: bezug['receiptId'] as String,
      originalFullReceiptId: bezug['fullReceiptId'] is String ? bezug['fullReceiptId'] as String : null,
      restmengen: rest.cast<int>(),
    );
  }

  /// Artikelgruppen (Kategorien der Kachel-Kasse).
  Future<List<Artikelgruppe>> artikelgruppen() async =>
      _liste(Aufrufe.listMyArticleGroups, 'groups', Artikelgruppe.aus);

  /// Artikel in der Form, die die Kacheln brauchen.
  Future<List<KasseArtikel>> artikel() async => _liste(Aufrufe.listMyArticles, 'articles', KasseArtikel.aus);

  /// Personen, denen sich Trinkgeld zuweisen lässt. Dieselbe Menge, die der
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

  /// Beleg samt Belegkopf aus der Antworthülle. Fehlt der Beleg, ist das ein
  /// Antwortfehler — nicht ein leerer Beleg, mit dem der Bildschirm dann
  /// hantieren müsste.
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

/// Die Belegkennung aus einer Antworthülle — defensiv, wirft nie.
String? _kennungAus(Map<String, dynamic> daten) {
  final beleg = daten['receipt'];
  final wert = beleg is Map ? beleg['receiptId'] : null;
  return wert is String && wert.isNotEmpty ? wert : null;
}

/// Euro-Betrag des Backends in ganze Cent. Einmal gerundet, damit sich der
/// Gleitkommafehler nicht fortpflanzt.
int _euroInCent(Object? wert) => wert is num ? (wert * 100).round() : 0;
