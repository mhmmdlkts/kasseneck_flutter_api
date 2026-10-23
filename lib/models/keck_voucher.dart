import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';

/// Artikel eines Leistungsgutscheins, wie der Server ihn festhaelt (am Beleg
/// und in `checkVoucher`). Zwilling von `VoucherArticle` im npm-Paket.
class VoucherArticle {
  const VoucherArticle({required this.id, required this.name, required this.vatRateBp, required this.priceCents});

  final String id;
  final String name;

  /// Steuersatz in Basispunkten (2000 = 20 %).
  final int vatRateBp;

  /// Einzelpreis in Cent.
  final int priceCents;

  /// Nachsichtig gelesen (Beleg): `null`, wenn ein Feld fehlt oder keine
  /// ganze Zahl ist. Der strenge Leser fuer `checkVoucher` steht dort.
  static VoucherArticle? _nachsichtig(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final satz = _ganz(raw['vatRateBp']);
    final preis = _ganz(raw['priceCents']);
    if (id is! String || name is! String || satz == null || preis == null) return null;
    return VoucherArticle(id: id, name: name, vatRateBp: satz, priceCents: preis);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'vatRateBp': vatRateBp, 'priceCents': priceCents};

  @override
  bool operator ==(Object other) =>
      other is VoucherArticle &&
      other.id == id &&
      other.name == name &&
      other.vatRateBp == vatRateBp &&
      other.priceCents == priceCents;

  @override
  int get hashCode => Object.hash(id, name, vatRateBp, priceCents);
}

/// Gutschein am Beleg bzw. Gutscheinwunsch an `createReceipt`. Zwilling von
/// `Voucher` im npm-Paket.
///
/// **Altform** ([VoucherType.value], [VoucherType.promo]): Wert in
/// [valueCents]. **Neue Form** (Mehrzweck, Einzweck, Leistung, Aktion,
/// Auszahlung): Betrag in [amountCents], dazu je nach Art [articleId],
/// [quantity], [positions] und [reason]. Die Felder unter „nur gelesen“ setzt
/// allein der Server; ein Wunsch mit einem davon wird vor dem Senden
/// abgewiesen ([serverFields], Server: `voucher_invalid`).
///
/// Der Klartext-Code eines Gutscheins der neuen Form steht nie am Beleg: der
/// Server schreibt dort `····-····-XXXX` in [code] und die letzten vier
/// Zeichen in [codeSuffix].
class KeckVoucher {

  final String? name;
  final String? code;
  final VoucherAction action;
  final VoucherType type;

  /// Gutscheinwert in **Cent** (z. B. 500 = 5,00 EUR), Altform.
  ///
  /// Geld wird intern exakt in Integer-Cent gerechnet. Das JSON-Format
  /// Richtung Backend bleibt unveraendert in Euro (siehe [toJson]).
  int? valueCents;

  /// Neue Form: Betrag in Cent (Verkauf, Einloesung, Auszahlung).
  final int? amountCents;

  /// Neue Form, Leistungsgutschein verkaufen: der Artikel.
  final String? articleId;

  /// Neue Form, Leistungsgutschein: Menge (Verkauf) bzw. eingeloeste Menge (gelesen).
  final int? quantity;

  /// Neue Form, Leistungsgutschein einloesen: Indizes der Belegpositionen.
  final List<int>? positions;

  /// Neue Form, Auszahlung: Grund, 1 bis 200 Zeichen.
  final String? reason;

  // ---- nur gelesen (setzt der Server, ein Wunsch traegt sie nie) ----------

  /// Art des Gutscheins am Server (Drahtwert, z. B. `multi_purpose`); an
  /// einer gelesenen Mehrzweck-Einloesung steht [type] auf `value`.
  final String? voucherType;
  final String? voucherId;

  /// Letzte vier Zeichen des Codes; der Klartext steht nie am Beleg.
  final String? codeSuffix;

  /// Steuersatz in Basispunkten.
  final int? vatRateBp;
  final VoucherArticle? article;
  final int? balanceAfterCents;
  final int? remainingQuantityAfter;

  /// Beleg, mit dem der Gutschein beim Verkauf versteuert wurde.
  final String? taxedWith;

  /// Befreit verkauft (Kleinunternehmer, Satz 0).
  final bool? exempt;

  /// Der Betrag steht schon als Position im 0-%-Topf (Server `imNullTopf`):
  /// er zaehlt nicht noch einmal als Wertgutschein-Fluss.
  final bool? zeroRateBucket;

  KeckVoucher({
    this.name,
    this.code,
    required this.action,
    required this.type,
    this.valueCents,
    this.amountCents,
    this.articleId,
    this.quantity,
    this.positions,
    this.reason,
    this.voucherType,
    this.voucherId,
    this.codeSuffix,
    this.vatRateBp,
    this.article,
    this.balanceAfterCents,
    this.remainingQuantityAfter,
    this.taxedWith,
    this.exempt,
    this.zeroRateBucket,
  });

  /// Komfort-Konstruktor mit Wert in **Euro** (einmalige Rundung auf Cent).
  factory KeckVoucher.euro({
    String? name,
    String? code,
    required VoucherAction action,
    required VoucherType type,
    required double value,
  }) {
    return KeckVoucher(
      name: name,
      code: code,
      action: action,
      type: type,
      valueCents: (value * 100).round(),
    );
  }

  /// Wert in Euro (Anzeige/Format — fuer Arithmetik [valueCents] nutzen).
  double? get value => valueCents == null ? null : valueCents! / 100;

  /// Gehoert der Gutschein zur neuen Form (Art der neuen Form oder Aktion
  /// [VoucherAction.payout])? Ein gelesener Auszahlungseintrag (`type: value`,
  /// `action: payout`) zaehlt dazu.
  bool get isNewForm => type.isNewForm || action == VoucherAction.payout;

  /// Die Felder, die nur der Server setzt und die hier gesetzt sind (leer =
  /// keines). An einem Wunsch ist jedes davon `voucher_invalid`.
  List<String> get serverFields => [
        if (voucherId != null) 'voucherId',
        if (codeSuffix != null) 'codeSuffix',
        if (zeroRateBucket != null) 'zeroRateBucket',
        if (voucherType != null) 'voucherType',
      ];

  /// Nachsichtig gelesen: ein gespeicherter oder empfangener Beleg darf am
  /// Gutschein nie scheitern (die Liste muss ihn oeffnen). `valueCents` wird
  /// bevorzugt (exakt); Fallback: Euro mit einmaliger Rundung. Eine
  /// unbekannte Aktion bzw. Art faellt auf `sell`/`promo` zurueck; ein Feld
  /// der neuen Form mit falschem Typ faellt weg.
  factory KeckVoucher.fromJson(Map<String, dynamic> json) {
    final cents = json['valueCents'];
    final positionen = json['positions'];
    return KeckVoucher(
      name: json['name'] as String?,
      code: json['code'] as String?,
      action: VoucherAction.values.firstWhere((e) => e.name == json['action'], orElse: () => VoucherAction.sell),
      type: VoucherType.fromWire(json['type']) ?? VoucherType.promo,
      valueCents: cents is num
          ? cents.round()
          : (json['value'] == null ? null : ((json['value'] as num) * 100).round()),
      amountCents: _ganz(json['amountCents']),
      articleId: _text(json['articleId']),
      quantity: _ganz(json['quantity']),
      positions: positionen is List && positionen.every((i) => _ganz(i) != null)
          ? List.unmodifiable([for (final i in positionen) _ganz(i)!])
          : null,
      reason: _text(json['reason']),
      voucherType: _text(json['voucherType']),
      voucherId: _text(json['voucherId']),
      codeSuffix: _text(json['codeSuffix']),
      vatRateBp: _ganz(json['vatRateBp']),
      article: VoucherArticle._nachsichtig(json['article']),
      balanceAfterCents: _ganz(json['balanceAfterCents']),
      remainingQuantityAfter: _ganz(json['remainingQuantityAfter']),
      taxedWith: _text(json['taxedWith']),
      exempt: json['exempt'] is bool ? json['exempt'] as bool : null,
      zeroRateBucket: json['zeroRateBucket'] is bool ? json['zeroRateBucket'] as bool : null,
    );
  }

  /// Die Felder der neuen Form, soweit gesetzt (Altbelege bleiben schlank).
  Map<String, dynamic> _neueFelder() => {
        'amountCents': ?amountCents,
        'articleId': ?articleId,
        'quantity': ?quantity,
        'positions': ?positions,
        'reason': ?reason,
        'voucherType': ?voucherType,
        'voucherId': ?voucherId,
        'codeSuffix': ?codeSuffix,
        'vatRateBp': ?vatRateBp,
        if (article != null) 'article': article!.toJson(),
        'balanceAfterCents': ?balanceAfterCents,
        'remainingQuantityAfter': ?remainingQuantityAfter,
        'taxedWith': ?taxedWith,
        'exempt': ?exempt,
        'zeroRateBucket': ?zeroRateBucket,
      };

  /// Gespeicherte Form. Sendet BEIDE Felder: `value` (Euro, altes Backend) +
  /// `valueCents` (neu, exakt); die Felder der neuen Form nur, wenn gesetzt
  /// (ein Altbeleg bleibt Byte fuer Byte gleich).
  Map <String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'action': action.name,
      'type': type.wire,
      'value': valueCents == null ? null : valueCents! / 100,
      'valueCents': valueCents,
      ..._neueFelder(),
    };
  }

  /// Die Nutzlast fuer `createReceipt` unter `/v3` (Zwilling von
  /// `toVoucherPayload` im npm-Paket): Altform nur `valueCents` (ganze Cent),
  /// kein Euro-Wert; die neue Form roh mit `amountCents` und den gesetzten
  /// Feldern, ohne `valueCents` (nur ein gelesener Auszahlungseintrag traegt
  /// es weiter). `name` und `code` nur, wenn gesetzt. [toJson] bleibt die
  /// gespeicherte Form.
  Map<String, dynamic> toPayload() => {
        'action': action.name,
        'type': type.wire,
        if (!(isNewForm && valueCents == null)) 'valueCents': valueCents,
        'code': ?code,
        'name': ?name,
        ..._neueFelder(),
      };

  /// Sendbar? Altform: Wert- und Aktionsgutscheine brauchen einen Wert,
  /// Aktionsgutscheine nur einloesen, ein Wert ist positiv. Neue Form:
  /// die Regeln des Servers (siehe [_neueFormGueltig]).
  bool get isValid {
    if (isNewForm) return _neueFormGueltig();
    if (type == VoucherType.value && valueCents == null) {
      return false;
    }
    if (type == VoucherType.promo && action != VoucherAction.redeem) {
      return false;
    }
    if (type == VoucherType.promo && valueCents == null) {
      return false;
    }
    if (valueCents != null && valueCents! <= 0) {
      return false;
    }
    return true;
  }

  /// Wunsch der neuen Form sendbar? Wie `newFormVoucherIsValid` im npm-Paket
  /// und die Pruefung des Servers (gutschein-beleg): Serverfelder nie, Betrag
  /// 1 bis 1.000.000 Cent, Menge 1 bis 100, Code (getrimmt nicht leer) bei
  /// Einloesung und Auszahlung, Auszahlung nur Mehrzweck/Einzweck mit Grund
  /// (getrimmt 1 bis 200 Zeichen), Aktion nur einloesbar, Leistung braucht
  /// Artikel und Menge (Verkauf) bzw. Positionen ohne Doppel (Einloesung).
  /// Ein Feld, das zu einer anderen Aktion/Art gehoert, weist der Server ab.
  bool _neueFormGueltig() {
    if (serverFields.isNotEmpty) return false;
    if (vatRateBp != null || article != null || balanceAfterCents != null || remainingQuantityAfter != null ||
        taxedWith != null || exempt != null) {
      return false;
    }
    if (valueCents != null) return false;
    final allein = type == VoucherType.multiPurpose || type == VoucherType.singlePurpose;
    if (action == VoucherAction.payout) {
      final grund = reason?.trim() ?? '';
      return allein &&
          _hatText(code) &&
          _istCent(amountCents) &&
          grund.isNotEmpty &&
          grund.length <= _maxGrund &&
          articleId == null &&
          quantity == null &&
          positions == null;
    }
    if (reason != null) return false;
    if (allein) {
      if (articleId != null || quantity != null || positions != null) return false;
      if (action == VoucherAction.sell) return _istCent(amountCents);
      return _hatText(code) && _istCent(amountCents);
    }
    if (type == VoucherType.service) {
      if (amountCents != null) return false;
      if (action == VoucherAction.sell) {
        return _hatText(articleId) && _istMenge(quantity) && positions == null;
      }
      final p = positions;
      return _hatText(code) &&
          p != null &&
          p.isNotEmpty &&
          p.every((i) => i >= 0) &&
          p.toSet().length == p.length &&
          articleId == null &&
          quantity == null;
    }
    // Aktion: nur einloesen, nur mit Code. (Altart mit Auszahlung ist oben schon raus.)
    return type == VoucherType.promotion &&
        action == VoucherAction.redeem &&
        _hatText(code) &&
        amountCents == null &&
        articleId == null &&
        quantity == null &&
        positions == null;
  }

  /// Belegtext. Altform: Art, Wert und Name (ein Name, der die Art schon
  /// nennt, steht allein). Neue Form (auch eine gelesene Mehrzweck-Einloesung
  /// mit `type: value`) wie die Zeilen am Bon (Spec 2026-10-14, „Bon und
  /// Beleg“): Einloesung „Gutschein ····-9DWT“, Auszahlung „Auszahlung
  /// Gutschein ····-9DWT“, Verkauf Bezeichnung und kurze Code-Maske. Vom Code steht
  /// nie mehr als die Maske bzw. die letzten vier Zeichen da: ein Wunsch traegt
  /// den Klartext, der nie auf einen Beleg gehoert.
  String get receiptText {
    if (isNewForm || voucherType == VoucherType.multiPurpose.wire) return _neueFormText;
    String text = '';
    if (type == VoucherType.value) {
      text += 'Wertgutschein';
    } else if (type == VoucherType.promo) {
      text += 'Aktionsgutschein';
    }

    // Alte Belege nennen den Aktionsgutschein noch „Promotionsgutschein“: auch dieser Name steht allein.
    final klein = name?.toLowerCase();
    if (klein != null && (klein.contains(text.toLowerCase()) || (type == VoucherType.promo && klein.contains('promotionsgutschein')))) {
      return name!;
    }
    if (value != null) {
      text += ' ${formatVoucherAmount(value!)} EUR';
    }
    if (name != null && name!.isNotEmpty) {
      text += ' - $name';
    }
    return text;
  }



  String get _neueFormText {
    final art = VoucherType.fromWire(voucherType) ?? type;
    if (action == VoucherAction.sell) {
      final n = name?.trim() ?? '';
      final bezeichnung = n.toLowerCase().contains('gutschein') ? n : _artText(art);
      // Am Bon immer die kurze Maske, auch wenn der Eintrag die lange traegt.
      final maske = code != null && code!.startsWith('····') && _ende != null ? ' ····-$_ende' : '';
      return '$bezeichnung$maske';
    }
    final ende = _ende;
    final text = art == VoucherType.promotion ? 'Aktionsgutschein' : 'Gutschein';
    return '${action == VoucherAction.payout ? 'Auszahlung ' : ''}$text${ende == null ? '' : ' ····-$ende'}';
  }

  /// Die vier letzten Zeichen des Codes ([codeSuffix], sonst aus dem Code), oder `null`.
  String? get _ende => codeSuffix != null && codeSuffix!.isNotEmpty
      ? codeSuffix
      : (code != null && code!.length >= 4 && code != 'no-code' ? code!.substring(code!.length - 4) : null);

  static String _artText(VoucherType art) => switch (art) {
        VoucherType.multiPurpose || VoucherType.value => 'Mehrzweckgutschein',
        VoucherType.singlePurpose => 'Einzweckgutschein',
        VoucherType.service => 'Leistungsgutschein',
        VoucherType.promotion || VoucherType.promo => 'Aktionsgutschein',
      };

  /// Ganze Betraege kurz ("10"), krumme exakt mit 2 Nachkommastellen ("1,50") —
  /// frueher wurde gerundet ("~2"), was auf dem Beleg wie ein falscher Betrag wirkte.
  String formatVoucherAmount(num value) {
    if (value % 1 != 0) {
      return value.toStringAsFixed(2).replaceAll('.', ',');
    }
    return value.toStringAsFixed(0);
  }
}

/// Grenzen wie der Server (gutschein-beleg).
const int _maxBetragCents = 1000000;
const int _maxStueck = 100;
const int _maxGrund = 200;

bool _istCent(int? n) => n != null && n >= 1 && n <= _maxBetragCents;
bool _istMenge(int? n) => n != null && n >= 1 && n <= _maxStueck;
bool _hatText(String? t) => t != null && t.trim().isNotEmpty;

/// Ganze Zahl oder `null` (auch `3.0` gilt als ganz, `3.5` nicht).
int? _ganz(Object? w) {
  if (w is int) return w;
  if (w is double && w.isFinite && w == w.truncateToDouble()) return w.toInt();
  return null;
}

String? _text(Object? w) => w is String ? w : null;
