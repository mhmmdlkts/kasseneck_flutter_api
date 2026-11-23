/// Kartenleser (SumUp Solo ueber die Cloud) an der Kasse: das Konto
/// verbinden, Leser koppeln und dem Geraet zuweisen, eine Kartenzahlung
/// starten, nachfragen, abbrechen oder aufloesen, eine Rueckbuchung
/// veranlassen. Die dreizehn Aufrufe stehen an `RegisterReceiptClient` und
/// gehen nur ueber den Kassenweg `/api/v3`; die Rechte prueft der Server.
/// Zwilling von `pos/kartenleser.ts` im npm-Paket 1.43.0, gleiche Namen und
/// gleiche Regeln (Backend-Spec 2026-11-18-sumup-solo-cloud-design).
///
/// **Eine Zahlung ist ein Vorgang mit Kennung (`reference`), kein einzelner
/// Aufruf:** die Kasse erzeugt die Kennung selbst ([newCardReaderReference]),
/// bevor etwas hinausgeht, startet die Zahlung und fragt danach mit DERSELBEN
/// Kennung nach, bis [isCardReaderFinal] wahr ist. Ein Netzfehler beim Starten
/// oder Nachfragen heisst nie „nicht bezahlt“; ein Start mit neuer Kennung
/// nach einem unklaren Ausgang waere eine zweite Belastung.
///
/// **Ganzzahlen:** Betraege sind ganze Cent. Eine Antwort ohne ganze Zahl oder
/// ohne Kennung endet als Antwortfehler, nie mit einem Ersatzwert; auf den
/// Wegen mit Wirkung (Start, Abbrechen, Aufloesen, Rueckbuchen) als
/// `response_unreadable` mit Ausgang unklar.
library;

import 'dart:math';

import '../../enums/credit_card_provider.dart';
import '../../enums/keck_payment_method.dart';
import '../../models/keck_payment.dart';
import '../register/fehler.dart';
import '../register/transport.dart';

/// Stand der Verbindung zum SumUp-Konto (`connection.state`).
const List<String> cardAccountStates = ['none', 'connected', 'expired'];

/// Wie das Konto verbunden ist (`connection.method`).
const List<String> cardAccountMethods = ['oauth', 'api_key'];

/// Stand eines Lesers (`status`): nur `paired` kann kassieren.
const List<String> cardReaderStatuses = ['pairing', 'paired', 'expired'];

/// Stand einer Kartenzahlung oder Rueckbuchung. Ein Wert, den dieses Paket
/// nicht kennt, kommt als `unclear` an: weiter fragen, nie „bezahlt“.
const List<String> cardReaderPaymentStatuses = ['pending', 'successful', 'failed', 'cancelled', 'declined', 'unclear'];

/// Gruende neben dem Stand (`reason`); ein unbekannter kommt als `null` an.
const List<String> cardReaderReasons = [
  'busy', 'offline', 'declined', 'cancelled', 'expired', 'setup', 'amount_mismatch', 'no_response', 'not_refundable',
  'amount_too_high',
];

/// Entscheidung der Kasse bei unklarer Zahlung (`resolveCardReaderPayment`).
const List<String> cardReaderDecisions = ['receipt', 'discard'];

/// Kennung fuer „Leser am Geraet per Bluetooth“ (`setDeviceCardReader`,
/// `CardReaderSetup.deviceReader`).
const String cardReaderBluetooth = 'bluetooth';

/// Kleinster Betrag einer Kartenzahlung am Solo in Cent (1 €).
const int cardReaderMinCents = 100;

/// Groesster Betrag einer Kartenzahlung bzw. Rueckbuchung in Cent (10.000 €).
const int cardReaderMaxCents = 1000000;

/// Verbindung des Betriebs zu SumUp.
class CardAccountConnection {
  const CardAccountConnection({
    required this.state,
    this.method,
    this.merchantCode,
    this.refundsEnabled = false,
    this.connectAvailable = false,
  });

  /// Die Felder, die [CardAccountConnection.fromJson] liest.
  static const Set<String> fields = {'state', 'method', 'merchantCode', 'refundsEnabled', 'connectAvailable'};

  /// Aus [cardAccountStates]; ein unbekannter Stand gilt als `none`: die Kasse
  /// bietet dann das Verbinden an, nie eine Zahlung.
  final String state;

  /// Aus [cardAccountMethods] oder `null`.
  final String? method;
  final String? merchantCode;
  final bool refundsEnabled;

  /// Der Chef kann das Konto von der Kasse aus verbinden.
  final bool connectAvailable;

  factory CardAccountConnection.fromJson(Map<String, dynamic> json) => CardAccountConnection(
        state: _imKatalog(cardAccountStates, json['state']) ?? 'none',
        method: _imKatalog(cardAccountMethods, json['method']),
        merchantCode: _textOderNull(json['merchantCode']),
        refundsEnabled: json['refundsEnabled'] == true,
        connectAvailable: json['connectAvailable'] == true,
      );

  Map<String, dynamic> toJson() => {
        'state': state,
        'method': method,
        'merchantCode': merchantCode,
        'refundsEnabled': refundsEnabled,
        'connectAvailable': connectAvailable,
      };
}

/// Ein gekoppelter oder koppelnder Solo.
class CardReader {
  const CardReader({
    required this.readerId,
    this.name = '',
    this.serial,
    this.model,
    this.status,
    this.online,
    this.battery,
    this.busy = false,
    this.busyDevice,
  });

  /// Die Felder, die [CardReader.fromJson] liest.
  static const Set<String> fields = {
    'readerId', 'name', 'serial', 'model', 'status', 'online', 'battery', 'busy', 'busyDevice',
  };

  final String readerId;
  final String name;
  final String? serial;
  final String? model;

  /// Aus [cardReaderStatuses]; `null`: ein Stand, den dieses Paket nicht kennt.
  final String? status;

  /// Nur mit `withStatus`; sonst `null`.
  final bool? online;
  final num? battery;

  /// Ein anderes Geraet des Betriebs bedient diesen Leser gerade.
  final bool busy;
  final String? busyDevice;

  /// `null` ohne Kennung: ein Leser, den niemand ansprechen kann, gibt es nicht.
  static CardReader? fromJson(Map<String, dynamic> json) {
    final id = json['readerId'];
    if (id is! String || id.isEmpty) return null;
    final batterie = json['battery'];
    return CardReader(
      readerId: id,
      name: json['name'] is String ? json['name'] as String : '',
      serial: _textOderNull(json['serial']),
      model: _textOderNull(json['model']),
      status: _imKatalog(cardReaderStatuses, json['status']),
      online: json['online'] is bool ? json['online'] as bool : null,
      battery: batterie is num && batterie.isFinite ? batterie : null,
      busy: json['busy'] == true,
      busyDevice: _textOderNull(json['busyDevice']),
    );
  }

  Map<String, dynamic> toJson() => {
        'readerId': readerId,
        'name': name,
        'serial': serial,
        'model': model,
        'status': status,
        'online': online,
        'battery': battery,
        'busy': busy,
        'busyDevice': busyDevice,
      };
}

/// Konto, Leser und Zuweisung eines Geraets (`getCardReaderSetup`).
class CardReaderSetup {
  const CardReaderSetup({
    required this.connection,
    this.readers = const [],
    this.deviceReader,
    this.canManage = false,
  });

  /// Die Felder, die [CardReaderSetup.fromJson] liest.
  static const Set<String> fields = {'connection', 'readers', 'deviceReader', 'canManage'};

  final CardAccountConnection connection;

  /// Leser ohne Kennung fallen weg.
  final List<CardReader> readers;

  /// Kennung des zugewiesenen Lesers, [cardReaderBluetooth] oder `null`
  /// (automatisch).
  final String? deviceReader;

  /// Verwalten (Verbinden, Koppeln, Entfernen) darf nur, wer das Recht fuer
  /// Kassen-Einstellungen hat.
  final bool canManage;

  factory CardReaderSetup.fromJson(Map<String, dynamic> json) {
    final verbindung = json['connection'];
    final roh = json['readers'];
    return CardReaderSetup(
      connection: CardAccountConnection.fromJson(verbindung is Map ? Map<String, dynamic>.from(verbindung) : const {}),
      readers: [
        if (roh is List)
          for (final e in roh)
            if (e is Map) ?CardReader.fromJson(Map<String, dynamic>.from(e)),
      ],
      deviceReader: _textOderNull(json['deviceReader']),
      canManage: json['canManage'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'connection': connection.toJson(),
        'readers': [for (final l in readers) l.toJson()],
        'deviceReader': deviceReader,
        'canManage': canManage,
      };
}

/// Die Buchung bei SumUp zu einer Zahlung; jedes Feld kann fehlen.
class CardReaderTransaction {
  const CardReaderTransaction({
    this.id,
    this.code,
    this.cardType,
    this.cardLastDigits,
    this.entryMode,
    this.authCode,
    this.amountCents,
    this.timeMs,
  });

  /// Die Felder, die [CardReaderTransaction.fromJson] liest.
  static const Set<String> fields = {
    'id', 'code', 'cardType', 'cardLastDigits', 'entryMode', 'authCode', 'amountCents', 'timeMs',
  };

  final String? id;
  final String? code;
  final String? cardType;
  final String? cardLastDigits;
  final String? entryMode;
  final String? authCode;
  final int? amountCents;
  final int? timeMs;

  factory CardReaderTransaction.fromJson(Map<String, dynamic> json) => CardReaderTransaction(
        id: _textOderNull(json['id']),
        code: _textOderNull(json['code']),
        cardType: _textOderNull(json['cardType']),
        cardLastDigits: _textOderNull(json['cardLastDigits']),
        entryMode: _textOderNull(json['entryMode']),
        authCode: _textOderNull(json['authCode']),
        amountCents: _ganz(json['amountCents']),
        timeMs: _ganz(json['timeMs']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'cardType': cardType,
        'cardLastDigits': cardLastDigits,
        'entryMode': entryMode,
        'authCode': authCode,
        'amountCents': amountCents,
        'timeMs': timeMs,
      };
}

/// Stand einer Kartenzahlung am Leser.
class CardReaderPayment {
  const CardReaderPayment({
    required this.reference,
    required this.status,
    required this.amountCents,
    this.reason,
    this.readerId,
    this.readerName,
    this.transaction,
    this.receiptPayment,
  });

  /// Die Felder der Antwort, die dieses Paket liest.
  static const Set<String> fields = {
    'reference', 'status', 'reason', 'amountCents', 'readerId', 'readerName', 'transaction', 'receiptPayment',
  };

  /// Die Felder von `receiptPayment`, die dieses Paket liest; `providerData`
  /// geht unveraendert in den Beleg.
  static const Set<String> receiptPaymentFields = {'provider', 'providerPaymentId', 'providerData'};

  final String reference;

  /// Aus [cardReaderPaymentStatuses].
  final String status;

  /// Aus [cardReaderReasons] oder `null`.
  final String? reason;
  final int amountCents;
  final String? readerId;
  final String? readerName;
  final CardReaderTransaction? transaction;

  /// Nur bei `successful`: die Zahlung, wie sie in den Verkauf gehoert
  /// (`payments: [..., payment.receiptPayment!]`), Kartenzahlung ueber den
  /// Betrag dieser Zahlung mit Anbieter `sumup`. Die Anbieterdaten
  /// (`providerData`, `channel: 'cloud'`) gehen unveraendert hinaus, so wie der
  /// Server sie liefert; Zahlart und Betrag setzt das Paket.
  final KeckPaymentInput? receiptPayment;

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'status': status,
        'reason': reason,
        'amountCents': amountCents,
        'readerId': readerId,
        'readerName': readerName,
        'transaction': transaction?.toJson(),
        'receiptPayment': receiptPayment?.toJson(),
      };
}

/// Stand einer Rueckbuchung auf die Karte. Bei `declined` mit Grund
/// `no_response` heisst das NICHT, dass nichts zurueckging.
class CardReaderRefund {
  const CardReaderRefund({
    required this.reference,
    required this.paymentReference,
    required this.status,
    required this.amountCents,
    this.reason,
  });

  /// Die Felder der Antwort, die dieses Paket liest.
  static const Set<String> fields = {'reference', 'paymentReference', 'status', 'reason', 'amountCents'};

  final String reference;
  final String paymentReference;

  /// Aus [cardReaderPaymentStatuses].
  final String status;

  /// Aus [cardReaderReasons] oder `null`.
  final String? reason;
  final int amountCents;

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'paymentReference': paymentReference,
        'status': status,
        'reason': reason,
        'amountCents': amountCents,
      };
}

/// Endstand dieses Abfragens: die Kasse fragt nicht weiter. `pending` und
/// `unclear` (und jeder unbekannte Stand) gelten nicht als Ende. Aber: auch
/// `failed` und `cancelled` koennen spaeter noch `successful` werden
/// (verspaetete Zahlung, Klaerung bei SumUp); die Kasse behandelt sie als nicht
/// bezahlt, bis ein spaeteres Nachfragen etwas anderes meldet.
bool isCardReaderFinal(String status) =>
    status == 'successful' || status == 'failed' || status == 'cancelled' || status == 'declined';

/// Ein Leser zur Auswahl: der Server schickt bei `card_reader_choice_needed`
/// nur Kennung und Name.
class CardReaderChoiceOption {
  const CardReaderChoiceOption({required this.readerId, required this.name});

  final String readerId;
  final String name;

  Map<String, dynamic> toJson() => {'readerId': readerId, 'name': name};
}

/// Die Leser aus `card_reader_choice_needed` (`details.readers`); sonst leer.
/// Nur eine Notliste: die Kasse laedt bei diesem Fehler `getCardReaderSetup`
/// neu und waehlt mit [cardReaderFor] (gekoppelte Leser, Belegung); die
/// Zahlung startet sie dann mit der gewaehlten `readerId` erneut (nichts war
/// gestartet).
List<CardReaderChoiceOption> cardReaderChoices(Object? error) {
  if (error is! KasseneckApiError || error.code != 'card_reader_choice_needed') return const [];
  final roh = error.details['readers'];
  if (roh is! List) return const [];
  return [
    for (final e in roh)
      if (e is Map && e['readerId'] is String && (e['readerId'] as String).isNotEmpty)
        CardReaderChoiceOption(readerId: e['readerId'] as String, name: e['name'] is String ? e['name'] as String : ''),
  ];
}

/// Name des Geraets, das den Leser belegt (`details.busyDevice` bei
/// `card_reader_busy`); sonst `null`.
String? cardReaderBusyDevice(Object? error) {
  if (error is! KasseneckApiError || error.code != 'card_reader_busy') return null;
  return _textOderNull(error.details['busyDevice']);
}

const int _kennungMax = 64;
const String _zufallsZeichen = 'abcdefghijklmnopqrstuvwxyz0123456789';
final Random _zufall = Random.secure();
final RegExp _zufallsMuster = RegExp(r'^[a-z0-9]{6}$');
final RegExp _fremdeZeichen = RegExp(r'[^A-Za-z0-9_-]');

/// Neue Kennung einer Kartenzahlung: `kk-<kasse>-<epochMs>-<zufall>`,
/// hoechstens 64 Zeichen, eine je Versuch. Von [cashregisterId] bleiben nur
/// `A-Z a-z 0-9 _ -` (leer: `x`); wird es zu lang, kuerzt die Kassen-ID, nie
/// Zeit oder Zufall. [nowMs] (Vorgabe: die Uhr des Geraets) und [random]
/// (Vorgabe: sechs Zeichen `a-z0-9` aus einem sicheren Zufall) sind fuer
/// Tests; ein [random], das nicht genau sechs Zeichen `a-z0-9` sind, oder ein
/// negatives [nowMs] ist ein Eingabefehler.
String newCardReaderReference(String cashregisterId, {int? nowMs, String? random}) {
  const name = 'newCardReaderReference';
  final jetzt = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (jetzt < 0) throw _anfrage(name, 'nowMs ist keine ganze Zahl ab 0');
  if (random != null && !_zufallsMuster.hasMatch(random)) {
    throw _anfrage(name, 'random besteht nicht aus genau sechs Zeichen a-z0-9');
  }
  final zufall = random ??
      String.fromCharCodes([for (var i = 0; i < 6; i++) _zufallsZeichen.codeUnitAt(_zufall.nextInt(_zufallsZeichen.length))]);
  final ende = '-$jetzt-$zufall';
  final platz = max(1, _kennungMax - 'kk-'.length - ende.length);
  final sauber = cashregisterId.replaceAll(_fremdeZeichen, '');
  final kasse = sauber.isEmpty ? 'x' : sauber.substring(0, min(platz, sauber.length));
  return 'kk-$kasse$ende';
}

/// Welchen Leser die Kasse nimmt ([cardReaderFor]). [kind] ist der Name im
/// npm-Paket und in den Prueffaellen (`reader`, `choose`, `bluetooth`, `none`).
sealed class CardReaderChoice {
  const CardReaderChoice();

  String get kind;
}

/// Genau dieser gekoppelte Solo.
final class ChosenCardReader extends CardReaderChoice {
  const ChosenCardReader(this.reader);

  final CardReader reader;

  @override
  String get kind => 'reader';
}

/// Mehrere gekoppelte Solos, keiner zugewiesen: die Kasse fragt. Besetzte
/// bleiben in der Liste (die Kasse graut sie aus).
final class CardReadersToChoose extends CardReaderChoice {
  const CardReadersToChoose(this.readers);

  final List<CardReader> readers;

  @override
  String get kind => 'choose';
}

/// Der Leser am Geraet per Bluetooth (SDK-Weg, nicht die Cloud).
final class BluetoothCardReader extends CardReaderChoice {
  const BluetoothCardReader();

  @override
  String get kind => 'bluetooth';
}

/// Kein Leser: [why] ist `not_connected` (Konto nicht verbunden), `expired`
/// (Verbindung abgelaufen) oder `no_reader` (kein gekoppelter Solo).
final class NoCardReader extends CardReaderChoice {
  const NoCardReader(this.why);

  final String why;

  @override
  String get kind => 'none';
}

/// Welchen Leser die Kasse nimmt (gleiche Regel in Browser-Kasse und App,
/// Prueffaelle `card-reader-choice-cases.json`). Es zaehlen nur gekoppelte
/// Solos (`status == 'paired'`). Reihenfolge: Bluetooth am Geraet (der
/// Air-Leser haengt nicht an der Cloud-Verbindung, gilt also auch bei nicht
/// verbundenem oder abgelaufenem Konto), dann Konto nicht verbunden oder
/// abgelaufen, der zugewiesene gekoppelte Solo, genau ein gekoppelter,
/// mehrere zur Auswahl, sonst kein Leser.
CardReaderChoice cardReaderFor(CardReaderSetup setup) {
  if (setup.deviceReader == cardReaderBluetooth) return const BluetoothCardReader();
  final stand = setup.connection.state;
  if (stand == 'none') return const NoCardReader('not_connected');
  if (stand == 'expired') return const NoCardReader('expired');
  final gekoppelt = [for (final l in setup.readers) if (l.status == 'paired') l];
  for (final l in gekoppelt) {
    if (l.readerId == setup.deviceReader) return ChosenCardReader(l);
  }
  if (gekoppelt.length == 1) return ChosenCardReader(gekoppelt.single);
  if (gekoppelt.length > 1) return CardReadersToChoose(gekoppelt);
  return const NoCardReader('no_reader');
}

/// Schluessel des Kassentexts (`messageText`) zu einem Stand der Zahlung
/// ([kind] `payment`) oder Rueckbuchung (`refund`); `null`: kein Text noetig
/// (bezahlt, oder die Kasse zeigt ihre eigene Warte-Zeile). Gleiche Zuordnung
/// in Browser-Kasse und App (Prueffaelle `card-reader-message-cases.json`).
/// Ein Stand, den das Paket nicht kennt, gilt wie `unclear` (nie wie bezahlt).
/// Platzhalter der Texte (`{name}`, `{device}`, ...) fuellt die Kasse. Eine
/// andere Art als `payment` oder `refund` ist ein Programmierfehler
/// ([ArgumentError]).
String? cardReaderMessageKey(String kind, {required String status, String? reason}) {
  if (kind != 'payment' && kind != 'refund') {
    throw ArgumentError.value(kind, 'kind', 'payment oder refund');
  }
  final stand = cardReaderPaymentStatuses.contains(status) ? status : 'unclear';
  if (kind == 'payment') {
    // Ein abweichender Betrag warnt in jedem Stand, vor allem anderen.
    if (reason == 'amount_mismatch') return 'solo.amount_mismatch';
    return switch (stand) {
      'successful' || 'pending' => null,
      'unclear' => 'solo.checking',
      'cancelled' => 'solo.cancelled',
      'declined' => 'solo.declined',
      _ => switch (reason) {
          'busy' => 'solo.busy_short',
          'offline' => 'solo.offline',
          'setup' => 'solo.setup',
          'expired' => 'solo.expired',
          _ => 'solo.declined',
        },
    };
  }
  return switch (stand) {
    'successful' => null,
    'pending' => 'solo.refund_running',
    'unclear' => 'solo.refund_checking',
    'declined' => switch (reason) {
        'no_response' => 'solo.refund_unknown',
        'amount_too_high' => 'solo.refund_too_high',
        _ => 'solo.refund_declined',
      },
    _ => 'solo.refund_not_sent',
  };
}

// ---- Paketintern: Pruefen vor dem Senden, Lesen der Antworten --------------

final RegExp _kennungsMuster = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

KasseneckValidationError _anfrage(String name, String grund) => KasseneckValidationError(name, grund, 'request');
KasseneckValidationError _antwort(String name, String grund) => KasseneckValidationError(name, grund, 'response');

String? _textOderNull(Object? w) => w is String && w.isNotEmpty ? w : null;

String? _imKatalog(List<String> katalog, Object? w) => w is String && katalog.contains(w) ? w : null;

/// Eine ganze Zahl; ein Gleitkommawert nur, wenn er ganz ist (JSON kennt den
/// Unterschied nicht).
int? _ganz(Object? w) {
  if (w is int) return w;
  if (w is double && w.isFinite && w == w.truncateToDouble()) return w.toInt();
  return null;
}

/// Das Geraet, dessen Zuweisung gilt: ein nicht leerer Text.
String kartenleserGeraet(String name, String deviceId) {
  if (deviceId.trim().isEmpty) throw _anfrage(name, 'deviceId fehlt');
  return deviceId;
}

/// Kennung einer Zahlung oder Rueckbuchung: 8 bis 64 Zeichen `A-Z a-z 0-9 _ -`.
String kartenleserKennung(String name, String feld, String wert) {
  if (!_kennungsMuster.hasMatch(wert)) {
    throw _anfrage(name, '$feld ist keine Kennung (8 bis 64 Zeichen aus A-Z, a-z, 0-9, _ und -)');
  }
  return wert;
}

/// Kennung eines Lesers: ein nicht leerer Text.
String kartenleserLeser(String name, String readerId) {
  if (readerId.trim().isEmpty) throw _anfrage(name, 'readerId ist leer');
  return readerId;
}

/// Betrag einer Kartenzahlung: [cardReaderMinCents] bis [cardReaderMaxCents].
int kartenzahlungBetrag(String name, int cents) {
  if (cents < cardReaderMinCents || cents > cardReaderMaxCents) {
    throw _anfrage(name, 'amountCents ist keine ganze Zahl von $cardReaderMinCents bis $cardReaderMaxCents Cent');
  }
  return cents;
}

/// Betrag einer Rueckbuchung: jede ganze Zahl ab 1 Cent; die Obergrenze (Rest
/// der Zahlung) prueft der Server.
int rueckbuchungBetrag(String name, int cents) {
  if (cents < 1 || cents > cardReaderMaxCents) {
    throw _anfrage(name, 'amountCents ist keine ganze Zahl von 1 bis $cardReaderMaxCents Cent');
  }
  return cents;
}

String kartenleserEntscheidung(String name, String decision) {
  if (!cardReaderDecisions.contains(decision)) throw _anfrage(name, 'decision ist weder receipt noch discard');
  return decision;
}

/// Ein Aufruf mit Wirkung auf den Ausgang einer Zahlung (Start, Abbrechen,
/// Aufloesen, Rueckbuchen): `data` kein Objekt nach gemeldetem Erfolg ist wie
/// jede unlesbare Erfolgsantwort `response_unreadable` mit Ausgang unklar
/// (derselbe Code wie beim Lesen der Antwort, siehe [readSignedResponse]).
Future<Map<String, dynamic>> kartenleserGeldweg(RegisterTransport transport, String name, Map<String, dynamic> params) async {
  try {
    return await transport.call(name, params: params);
  } on KasseneckHttpError catch (e) {
    if (e.reason != 'data-not-object') rethrow;
    return readSignedResponse(name, () => throw e);
  }
}

CardReader kartenleserAntwort(String name, Map<String, dynamic> daten) {
  final l = CardReader.fromJson(daten);
  if (l == null) throw _antwort(name, 'Antwort enthaelt keinen Leser (data.readerId fehlt)');
  return l;
}

String kartenleserAnmeldelink(String name, Map<String, dynamic> daten) {
  final url = _textOderNull(daten['authorizeUrl']);
  if (url == null) throw _antwort(name, 'Antwort enthaelt keine Adresse (data.authorizeUrl fehlt)');
  return url;
}

/// Ein neuer Stand des Servers ist kein Absturz und kein „bezahlt“: weiter fragen.
String _zahlungsstand(Object? w) => _imKatalog(cardReaderPaymentStatuses, w) ?? 'unclear';

KeckPaymentInput? _belegZahlung(String name, String status, Object? roh, String referenz, int betrag) {
  if (status != 'successful' || roh is! Map) return null;
  final daten = roh['providerData'];
  if (daten is! Map || daten['channel'] != 'cloud') return null;
  final kennung = roh['providerPaymentId'];
  if (kennung is! String || kennung.isEmpty) return null;
  // Echo: der Zahlungsblock gehoert zu genau dieser Kennung, sonst landete eine fremde Zahlung auf dem Beleg.
  if (daten['foreignTransactionId'] != referenz) {
    throw _antwort(name, 'Zahlungsblock gehoert zu einer anderen Kennung (providerData.foreignTransactionId)');
  }
  return KeckPaymentInput(
    method: KeckPaymentMethod.creditCard,
    amountCents: betrag,
    provider: CreditCardProvider.sumup,
    providerPaymentId: kennung,
    providerData: Map<String, dynamic>.from(daten),
  );
}

/// Stand einer Zahlung aus der Antwort; die Kennung muss die gesendete sein.
CardReaderPayment kartenzahlungLesen(String name, Map<String, dynamic> d, String erwartet) {
  final referenz = d['reference'];
  if (referenz is! String || referenz.isEmpty) throw _antwort(name, 'Antwort enthaelt keine Kennung (data.reference fehlt)');
  if (referenz != erwartet) throw _antwort(name, 'Antwort gehoert zu einer anderen Kennung (data.reference)');
  final betrag = _ganz(d['amountCents']);
  if (betrag == null) throw _antwort(name, 'Antwort enthaelt keine ganze Zahl (data.amountCents)');
  final status = _zahlungsstand(d['status']);
  final buchung = d['transaction'];
  return CardReaderPayment(
    reference: referenz,
    status: status,
    reason: _imKatalog(cardReaderReasons, d['reason']),
    amountCents: betrag,
    readerId: _textOderNull(d['readerId']),
    readerName: _textOderNull(d['readerName']),
    transaction: buchung is Map ? CardReaderTransaction.fromJson(Map<String, dynamic>.from(buchung)) : null,
    receiptPayment: _belegZahlung(name, status, d['receiptPayment'], erwartet, betrag),
  );
}

/// Stand einer Rueckbuchung aus der Antwort; Kennung und (beim Veranlassen)
/// die Zahlung muessen die gesendeten sein.
CardReaderRefund rueckbuchungLesen(String name, Map<String, dynamic> d, String erwartet, {String? zahlung}) {
  final referenz = d['reference'];
  if (referenz is! String || referenz.isEmpty) throw _antwort(name, 'Antwort enthaelt keine Kennung (data.reference fehlt)');
  if (referenz != erwartet) throw _antwort(name, 'Antwort gehoert zu einer anderen Kennung (data.reference)');
  final bezug = d['paymentReference'];
  if (bezug is! String || bezug.isEmpty) throw _antwort(name, 'Antwort enthaelt keine Zahlung (data.paymentReference fehlt)');
  if (zahlung != null && bezug != zahlung) {
    throw _antwort(name, 'Antwort gehoert zu einer anderen Zahlung (data.paymentReference)');
  }
  final betrag = _ganz(d['amountCents']);
  if (betrag == null) throw _antwort(name, 'Antwort enthaelt keine ganze Zahl (data.amountCents)');
  return CardReaderRefund(
    reference: referenz,
    paymentReference: bezug,
    status: _zahlungsstand(d['status']),
    reason: _imKatalog(cardReaderReasons, d['reason']),
    amountCents: betrag,
  );
}
