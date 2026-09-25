import '../enums/credit_card_provider.dart';
import '../enums/keck_payment_method.dart';

/// Eine Zahlung am Beleg — Zwilling von `ReceiptPayment` in
/// `@kreiseck/kasseneck-api` (models/receipt-payment.ts) und der Eintraege,
/// die `functions/gemeinsam/zahlungen-core.js` unter `payments` ablegt.
///
/// Ein Beleg kann ueber mehrere Zahlungen bezahlt sein (zwei Karten, Rest
/// bar). Dann steht die Liste unter `payments`, und das Einzelfeld
/// `paymentMethod` ist `mixed`, sobald verschiedene Zahlarten vorkommen (zwei
/// Karten ergeben `creditCard`). Altbelege haben keine Liste; dort gilt weiter
/// `paymentMethod` samt Kartenfeldern.
///
/// Betraege in ganzen Cent: am Verkauf positiv, am Storno negativ
/// (Rueckzahlung).
///
/// Zahlart und Anbieter werden roh gehalten und nur beim Lesen gedeutet: ein
/// Wert, den dieses Paket noch nicht kennt, ergibt `null` statt eines
/// geratenen Enum-Eintrags -- und geht beim Zurueckschreiben (lokale Ablage)
/// unveraendert wieder hinaus.
class KeckPayment {
  const KeckPayment({
    this.id,
    required this.methodValue,
    required this.amountCents,
    this.tenderedCents,
    this.changeCents,
    this.providerValue,
    this.providerPaymentId,
    this.providerData,
    this.refundOf,
    this.tipCents,
  });

  /// Vom Server vergeben (`p1`, `p2`, …); Bezugspunkt fuer `refundOf`.
  final String? id;

  /// Zahlart, wie sie am Beleg steht.
  final String methodValue;
  final int amountCents;

  /// Nur bei Barzahlung: gegebener Betrag.
  final int? tenderedCents;

  /// Nur neben [tenderedCents]: Rueckgeld (vom Server gerechnet).
  final int? changeCents;

  /// Kartenanbieter bzw. Terminal, wie er am Beleg steht.
  final String? providerValue;

  /// Kennung der Zahlung am Terminal/Anbieter.
  final String? providerPaymentId;

  /// Terminaldaten fuer den Kartenblock (frueher `cardPaymentData`).
  final Map<String, dynamic>? providerData;

  /// Nur am Storno: `id` der Originalzahlung, die erstattet wird.
  final String? refundOf;

  /// Trinkgeld, das mit dieser Zahlung gegeben wurde -- TEIL von
  /// [amountCents] (das Terminal bucht Betrag und Trinkgeld zusammen).
  final int? tipCents;

  /// Die Zahlart; `null`, wenn dieses Paket den Wert nicht kennt.
  KeckPaymentMethod? get method {
    for (final m in KeckPaymentMethod.values) {
      if (m.name == methodValue) return m;
    }
    return null;
  }

  /// Der Anbieter; `null`, wenn keiner angegeben ist oder dieses Paket ihn
  /// nicht kennt (dann gibt es auch keinen Kartenblock).
  CreditCardProvider? get provider {
    for (final p in CreditCardProvider.values) {
      if (p.name == providerValue) return p;
    }
    return null;
  }

  /// Lesepfad: nur vorhandene Felder uebernehmen, nichts ergaenzen.
  factory KeckPayment.fromJson(Map<dynamic, dynamic> json) {
    int? ganz(Object? wert) => wert is num ? wert.toInt() : null;
    final daten = json['providerData'];
    return KeckPayment(
      id: json['id'] is String ? json['id'] as String : null,
      methodValue: json['method'] is String ? json['method'] as String : '',
      amountCents: ganz(json['amountCents']) ?? 0,
      tenderedCents: ganz(json['tenderedCents']),
      changeCents: ganz(json['changeCents']),
      providerValue: json['provider'] is String ? json['provider'] as String : null,
      providerPaymentId: json['providerPaymentId'] is String ? json['providerPaymentId'] as String : null,
      providerData: daten is Map ? Map<String, dynamic>.from(daten) : null,
      refundOf: json['refundOf'] is String ? json['refundOf'] as String : null,
      tipCents: ganz(json['tipCents']),
    );
  }

  /// Liest eine Zahlungsliste; alles ausser einer Liste (auch `null`) gilt als
  /// „keine Liste" -- wie im Backend.
  static List<KeckPayment>? listeAus(Object? roh) {
    if (roh is! List) return null;
    return [
      for (final e in roh)
        if (e is Map) KeckPayment.fromJson(e),
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': ?id,
        'method': methodValue,
        'amountCents': amountCents,
        'tenderedCents': ?tenderedCents,
        'changeCents': ?changeCents,
        'provider': ?providerValue,
        'providerPaymentId': ?providerPaymentId,
        'providerData': ?providerData,
        'refundOf': ?refundOf,
        'tipCents': ?tipCents,
      };
}

/// Eine Zahlung, wie der Aufrufer sie an `sellReceipt`/`verkaufen`/
/// `stornieren` schickt — Zwilling von `ReceiptPaymentInput`. `id` und
/// `changeCents` vergibt der Server.
///
/// - [method]: jede Zahlungsart ausser [KeckPaymentMethod.mixed].
/// - [amountCents]: ganze Cent, am Verkauf > 0, am Storno < 0.
/// - [tenderedCents]: nur bei Barzahlung am Verkauf, hoechstens an einer Zahlung.
/// - [provider]/[providerPaymentId]/[providerData]: bei Karten Pflicht
///   ([providerPaymentId] ausser bei `custom`), bei `online` optional, sonst
///   nicht erlaubt; am Storno beschreiben sie die Erstattung und sind optional.
/// - [refundOf]: nur am Storno.
/// - [tipCents]: Trinkgeld dieser Zahlung, ganze Cent > 0, Teil von
///   [amountCents]; nur am Verkauf, nie neben `tip`.
///
/// Hier geprueft wird nur die Form ([zahlungenFehler]); Summe,
/// Anbieter-Pflicht und Trinkgeld prueft der Server, der den Zahlbetrag kennt.
class KeckPaymentInput {
  const KeckPaymentInput({
    required this.method,
    required this.amountCents,
    this.tenderedCents,
    this.provider,
    this.providerPaymentId,
    this.providerData,
    this.refundOf,
    this.tipCents,
  });

  final KeckPaymentMethod method;
  final int amountCents;
  final int? tenderedCents;
  final CreditCardProvider? provider;
  final String? providerPaymentId;
  final Map<String, dynamic>? providerData;
  final String? refundOf;
  final int? tipCents;

  /// Nutzlast; nur gesetzte Felder, der Enum-Name ist das Drahtformat.
  Map<String, dynamic> toJson() => {
        'method': method.name,
        'amountCents': amountCents,
        'tenderedCents': ?tenderedCents,
        'tipCents': ?tipCents,
        'provider': ?provider?.name,
        'providerPaymentId': ?providerPaymentId,
        'providerData': ?providerData,
        'refundOf': ?refundOf,
      };
}

/// Hoechstzahl der Zahlungen je Beleg (Backend: MAX_ZAHLUNGEN).
const int zahlungenHoechstzahl = 20;

/// Was an der Zahlungsliste nicht stimmt -- `null`, wenn die Form passt.
///
/// Zwilling von `gepruefteZahlungen` im Client des npm-Pakets, Wortlaut
/// inklusive; [storno] kehrt das Vorzeichen um und erlaubt `refundOf`, verbietet
/// `tenderedCents`.
String? zahlungenFehler(List<KeckPaymentInput> zahlungen, {required bool storno}) {
  if (zahlungen.length > zahlungenHoechstzahl) {
    return 'payments: es sind hoechstens $zahlungenHoechstzahl Eintraege erlaubt.';
  }
  for (final (i, z) in zahlungen.indexed) {
    final nr = i + 1;
    if (z.method == KeckPaymentMethod.mixed) {
      return 'Zahlung $nr: $mixedNichtSenden';
    }
    if (storno ? z.amountCents >= 0 : z.amountCents <= 0) {
      return 'Zahlung $nr: amountCents muss eine ganze Zahl ${storno ? 'kleiner' : 'groesser'} als 0 sein.';
    }
    final gegeben = z.tenderedCents;
    if (gegeben != null && (storno || gegeben < z.amountCents)) {
      return 'Zahlung $nr: tenderedCents muss eine ganze Zahl von mindestens amountCents sein (nur am Verkauf).';
    }
    final trinkgeld = z.tipCents;
    if (trinkgeld != null && trinkgeld <= 0) {
      return 'Zahlung $nr: tipCents muss eine ganze Zahl groesser als 0 sein.';
    }
    if (z.providerPaymentId != null && z.providerPaymentId!.isEmpty) {
      return 'Zahlung $nr: providerPaymentId muss ein nicht-leerer Text sein.';
    }
    if (z.refundOf != null && (!storno || z.refundOf!.isEmpty)) {
      return 'Zahlung $nr: refundOf gibt es nur am Storno, als id der Originalzahlung.';
    }
  }
  return null;
}

/// Warum `mixed` nie hinausgeht -- derselbe Satz fuer Einzel-Zahlungsart und
/// Zahlungsliste.
const String mixedNichtSenden =
    'Zahlungsart "mixed" vergibt nur der Server – mehrere Zahlarten gehen als payments hinaus.';

/// `payments` neben einer Einzel-Zahlungsart oder Kartenfeldern? Liefert den
/// Grund (Backend: `PAYMENTS_CONFLICT`), sonst `null`. Nie still eines
/// bevorzugen. [felder] nennt die Felder mit ihrem Drahtnamen.
String? zahlungsKonflikt(Map<String, Object?> felder) {
  for (final MapEntry(:key, :value) in felder.entries) {
    if (value != null) {
      return 'payments und $key duerfen nicht gemeinsam gesendet werden – Kartenangaben gehoeren in die Zahlung.';
    }
  }
  return null;
}
