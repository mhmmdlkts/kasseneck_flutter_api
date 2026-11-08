import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';

import 'package:kreiseck_validator/kreiseck_validator.dart' show VoucherCode;

import '../src/kasse/gutschein_wunsch.dart' show wunschFormGueltig;
import '../src/kasse/lager.dart' show jsTrim;
import '../src/receipt/gutschein_bon.dart' show externalVoucherLine;

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
///
/// **Verkauf ueber eine Gutschein-Sorte** (seit 11.8.0): ein Mehrzweck- oder
/// Einzweckgutschein wird nur mit [typeId] verkauft. Empfohlen ist die Form
/// mit der Art der Sorte:
/// `KeckVoucher(action: sell, type: sorte.kind, typeId: sorte.id, amountCents: …)`.
/// Am Draht darf die Art fehlen; ein so gelesener Wunsch hat keine Art
/// ([hasType] ist `false`) und geht ohne `type` wieder hinaus.
///
/// **Fremdgutschein** (seit 11.21.0, Server 2026-11): ein Gutschein eines
/// anderen Systems (Warenwirtschaft, Webshop) mit [source] `external` und
/// seiner Nummer in [number]. Kein Code, kein Saldo, keine Pruefung: Art,
/// Satz und Betrag sagt der Betrieb.
/// `KeckVoucher(source: voucherSourceExternal, action: redeem, type: VoucherType.multiPurpose, number: 'W-77', amountCents: 300)`;
/// Einzweck mit [vatRateBp] aus [externalVoucherVatRatesBp].
class KeckVoucher {

  final String? name;

  /// Code eines eigenen Gutscheins (Einloesung, Auszahlung); am gelesenen
  /// Eintrag die Maske. Ein Wertgutschein der Altform mit frei getipptem Code
  /// ist veraltet ([KeckVoucher.legacyValue]).
  final String? code;

  /// Herkunft: [voucherSourceExternal] fuer einen Fremdgutschein, sonst
  /// `null` (eigener Gutschein). Ein unbekannter Wert bleibt, wie gelesen.
  final String? source;

  /// Nummer des Fremdgutscheins (nur mit [source] `external`): nach
  /// [normalizeExternalVoucherNumber] 1 bis 40 Zeichen aus `A-Z a-z 0-9 - _ . /`;
  /// ein eigener Gutscheincode ist keine Fremdnummer. Steht voll am Bon.
  final String? number;

  final VoucherAction action;

  /// Die Art; `null` nur bei einem gelesenen Verkauf ohne bekannte Art.
  final VoucherType? _type;

  /// Eine unbekannte Art eines gelesenen Verkaufs, wie sie am Draht stand;
  /// sie geht beim Schreiben unveraendert zurueck.
  final Object? _typeRoh;

  /// Die Art des Gutscheins.
  ///
  /// Wirft [StateError], wenn der Gutschein keine Art hat ([hasType] ist
  /// `false`): ein Verkauf ueber eine Sorte, der ohne `type` gelesen wurde
  /// (die Art kommt dann aus der Sorte), oder ein Verkauf mit einer Art, die
  /// dieses Paket nicht kennt. Eine Art wird dort bewusst nicht geraten: ein
  /// Verkauf, der still zum Rabatt (`promo`) oder zu einer anderen Art wuerde,
  /// rechnete im Zahlbetrag und am Bon falsch. Ein Beleg des Servers traegt an
  /// jedem Eintrag eine Art.
  VoucherType get type {
    final art = _type;
    if (art == null) throw StateError('KeckVoucher ohne bekannte Art (Verkauf ueber eine Gutschein-Sorte): hasType pruefen.');
    return art;
  }

  /// Hat der Gutschein eine bekannte Art? Nur ein Verkauf kann ohne sein
  /// (siehe [type]); jeder andere Gutschein hat eine.
  bool get hasType => _type != null;

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

  /// Neue Form, Wertgutschein verkaufen: die Gutschein-Sorte
  /// (`PosVoucherType.id` aus `getKasseSettings`). Pflicht fuer jeden Verkauf
  /// eines Mehrzweck- oder Einzweckgutscheins (Server:
  /// `voucher_type_required`), an jeder anderen Aktion oder Art verboten. Am
  /// gelesenen Eintrag die Sorte des Verkaufs (fehlt ohne Sorte).
  final String? typeId;

  // ---- nur gelesen (setzt der Server, ein Wunsch traegt sie nie) ----------

  /// Name der Sorte beim Verkauf (eingefroren).
  final String? typeName;

  /// Auszahlung des verkauften Gutscheins (`allowed`/`never`, beim Verkauf
  /// eingefroren), wie am Draht: ein unbekannter Wert bleibt erhalten.
  final String? payout;

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

  /// Rueckgabe als Gutschein (Server 2026-11, Zwilling von `Voucher.fromReturn`
  /// im npm-Paket 1.25.0): der Eintrag am Storno-Beleg ist die Ausgabe eines
  /// neuen Mehrzweck-Gutscheins statt einer Rueckzahlung (`redeem`). Am Bon
  /// Zahlweg statt Einloesung. Setzt nur der Server.
  final bool? fromReturn;

  KeckVoucher({
    String? name,
    String? code,
    String? source,
    String? number,
    required VoucherAction action,
    required VoucherType type,
    int? valueCents,
    int? amountCents,
    String? articleId,
    int? quantity,
    List<int>? positions,
    String? reason,
    String? typeId,
    String? typeName,
    String? payout,
    String? voucherType,
    String? voucherId,
    String? codeSuffix,
    int? vatRateBp,
    VoucherArticle? article,
    int? balanceAfterCents,
    int? remainingQuantityAfter,
    String? taxedWith,
    bool? exempt,
    bool? zeroRateBucket,
    bool? fromReturn,
  }) : this._(
          name: name,
          code: code,
          source: source,
          number: number,
          action: action,
          type: type,
          valueCents: valueCents,
          amountCents: amountCents,
          articleId: articleId,
          quantity: quantity,
          positions: positions,
          reason: reason,
          typeId: typeId,
          typeName: typeName,
          payout: payout,
          voucherType: voucherType,
          voucherId: voucherId,
          codeSuffix: codeSuffix,
          vatRateBp: vatRateBp,
          article: article,
          balanceAfterCents: balanceAfterCents,
          remainingQuantityAfter: remainingQuantityAfter,
          taxedWith: taxedWith,
          exempt: exempt,
          zeroRateBucket: zeroRateBucket,
          fromReturn: fromReturn,
        );

  KeckVoucher._({
    this.name,
    this.code,
    this.source,
    this.number,
    required this.action,
    required VoucherType? type,
    Object? typeRoh,
    this.valueCents,
    this.amountCents,
    this.articleId,
    this.quantity,
    this.positions,
    this.reason,
    this.typeId,
    this.typeName,
    this.payout,
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
    this.fromReturn,
  })  : _type = type,
        _typeRoh = type == null ? typeRoh : null;

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

  /// Wunsch der Altform: Wertgutschein mit frei getipptem Code
  /// (`{action, type: value, code, valueCents}`). Gleich dem Konstruktor mit
  /// [VoucherType.value]; nur damit der veraltete Weg einen Namen hat. Ein
  /// gelesener Beleg ist davon nicht betroffen ([VoucherType.value] steht dort
  /// an jedem Mehrzweck-Eintrag und bleibt gueltig).
  @Deprecated('Server 2026-11: der Weg bleibt gueltig, die Antwort traegt deprecation '
      '(KasseneckReceipt.deprecation). Den Code prueft niemand, steuerlich ist das ein fremder Mehrzweckgutschein: '
      'einen Gutschein eines anderen Systems als Fremdgutschein senden (source: voucherSourceExternal, '
      'type: VoucherType.multiPurpose, number, amountCents), eigene ueber eine Sorte (typeId) verkaufen und mit ihrem Code einloesen.')
  factory KeckVoucher.legacyValue({
    required VoucherAction action,
    required String code,
    required int valueCents,
    String? name,
  }) =>
      KeckVoucher(action: action, type: VoucherType.value, code: code, valueCents: valueCents, name: name);

  /// Wert in Euro (Anzeige/Format — fuer Arithmetik [valueCents] nutzen).
  double? get value => valueCents == null ? null : valueCents! / 100;

  /// Gehoert der Gutschein zur neuen Form (Art der neuen Form, Aktion
  /// [VoucherAction.payout] oder Verkauf ueber eine Sorte ohne Art)? Ein
  /// gelesener Auszahlungseintrag (`type: value`, `action: payout`) zaehlt
  /// dazu, ein Verkauf mit unbekannter Art nicht.
  bool get isNewForm => (_type?.isNewForm ?? _sortenVerkaufOhneArt) || action == VoucherAction.payout || isExternal;

  /// Fremdgutschein ([source] `external`)? Zwilling von `isExternalVoucher`
  /// im npm-Paket.
  bool get isExternal => source == voucherSourceExternal;

  /// Verkauf ueber eine Sorte, bei dem die Art fehlt (nicht: unbekannt ist).
  /// Zwilling von `istSortenVerkaufOhneArt` im npm-Paket.
  bool get _sortenVerkaufOhneArt => action == VoucherAction.sell && _type == null && _typeRoh == null && typeId != null;

  /// Die Felder, die nur der Server setzt und die hier gesetzt sind (leer =
  /// keines). An einem Wunsch ist jedes davon `voucher_invalid`. Sortenname
  /// und Auszahlung friert der Server beim Verkauf ein.
  List<String> get serverFields => [
        if (voucherId != null) 'voucherId',
        if (codeSuffix != null) 'codeSuffix',
        if (zeroRateBucket != null) 'zeroRateBucket',
        if (voucherType != null) 'voucherType',
        if (typeName != null) 'typeName',
        if (payout != null) 'payout',
        if (fromReturn != null) 'fromReturn',
      ];

  /// Nachsichtig gelesen: ein gespeicherter oder empfangener Beleg darf am
  /// Gutschein nie scheitern (die Liste muss ihn oeffnen). `valueCents` wird
  /// bevorzugt (exakt); Fallback: Euro mit einmaliger Rundung. Eine
  /// unbekannte Aktion faellt auf `sell` zurueck, eine unbekannte Art auf
  /// `promo` – ausser an einem ausdruecklichen Verkauf: dort bleibt die Art
  /// offen ([hasType] ist `false`), denn ein Verkauf ueber eine Sorte darf
  /// ohne Art kommen, und ein Verkauf ist nie ein Rabatt. Ein Feld der neuen
  /// Form mit falschem Typ faellt weg.
  factory KeckVoucher.fromJson(Map<String, dynamic> json) {
    final cents = json['valueCents'];
    final positionen = json['positions'];
    final typRoh = json['type'];
    final art = VoucherType.fromWire(typRoh);
    final verkauf = json['action'] == VoucherAction.sell.name;
    return KeckVoucher._(
      name: json['name'] as String?,
      code: json['code'] as String?,
      source: _text(json['source']),
      number: _text(json['number']),
      action: VoucherAction.values.firstWhere((e) => e.name == json['action'], orElse: () => VoucherAction.sell),
      type: art ?? (verkauf ? null : VoucherType.promo),
      typeRoh: typRoh,
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
      typeId: _text(json['typeId']),
      typeName: _text(json['typeName']),
      payout: _text(json['payout']),
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
      fromReturn: json['fromReturn'] is bool ? json['fromReturn'] as bool : null,
    );
  }

  /// Die Art am Draht: bekannt als Drahtwert, unbekannt wie gelesen, ohne Art
  /// gar nicht (ein Verkauf ueber eine Sorte ohne Art bleibt ohne `type`).
  Map<String, Object?> _art() {
    final art = _type;
    return {
      if (art != null) 'type': art.wire else if (_typeRoh != null) 'type': _typeRoh,
    };
  }

  /// Die Felder der neuen Form, soweit gesetzt (Altbelege bleiben schlank).
  Map<String, dynamic> _neueFelder() => {
        'source': ?source,
        'number': ?number,
        'amountCents': ?amountCents,
        'articleId': ?articleId,
        'quantity': ?quantity,
        'positions': ?positions,
        'reason': ?reason,
        'typeId': ?typeId,
        'typeName': ?typeName,
        'payout': ?payout,
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
        'fromReturn': ?fromReturn,
      };

  /// Gespeicherte Form. Sendet BEIDE Felder: `value` (Euro, altes Backend) +
  /// `valueCents` (neu, exakt); die Felder der neuen Form nur, wenn gesetzt
  /// (ein Altbeleg bleibt Byte fuer Byte gleich).
  Map <String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'action': action.name,
      ..._art(),
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
  /// gespeicherte Form. Ein Verkauf ueber eine Sorte ohne Art geht ohne
  /// `type` hinaus.
  Map<String, dynamic> toPayload() => {
        'action': action.name,
        ..._art(),
        if (!(isNewForm && valueCents == null)) 'valueCents': valueCents,
        'code': ?code,
        'name': ?name,
        ..._neueFelder(),
      };

  /// Sendbar? Altform: Wert- und Aktionsgutscheine brauchen einen Wert,
  /// Aktionsgutscheine nur einloesen, ein Wert ist positiv. Neue Form:
  /// die Regeln des Servers (Zwilling von `newFormVoucherIsValid` im
  /// npm-Paket): Serverfelder nie, Betrag 1 bis 1.000.000 Cent, Menge 1 bis
  /// 100, Code bei Einloesung und Auszahlung, Auszahlung nur Mehrzweck/Einzweck
  /// mit Grund (1 bis 200 Zeichen), Aktion nur einloesbar, Leistung braucht
  /// Artikel und Menge bzw. Positionen, ein Wertgutschein wird nur ueber eine
  /// Sorte verkauft ([typeId], Form wie am Server). Ein Feld, das zu einer
  /// anderen Aktion/Art gehoert, weist der Server ab.
  bool get isValid {
    if (isExternal) return externalVoucherIsValid(this);
    if (isNewForm) return wunschFormGueltig(this, sorteNoetig: true);
    // Ohne bekannte Art (unbekannter Verkauf) ist nichts sendbar.
    final type = _type;
    if (type == null) return false;
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

  /// Belegtext. Altform: Art, Wert und Name (ein Name, der die Art schon
  /// nennt, steht allein). Neue Form (auch eine gelesene Mehrzweck-Einloesung
  /// mit `type: value`) wie die Zeilen am Bon (Spec 2026-10-14, „Bon und
  /// Beleg“): Einloesung „Gutschein ····-9DWT“, Auszahlung „Auszahlung
  /// Gutschein ····-9DWT“, Verkauf Bezeichnung und kurze Code-Maske. Vom Code steht
  /// nie mehr als die Maske bzw. die letzten vier Zeichen da: ein Wunsch traegt
  /// den Klartext, der nie auf einen Beleg gehoert.
  String get receiptText {
    if (isNewForm || voucherType == VoucherType.multiPurpose.wire) return _neueFormText;
    final type = _type;
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
    final art = VoucherType.fromWire(voucherType) ?? _type;
    final fremd = externalVoucherLine(this);
    if (fremd != null) {
      // Fremdgutschein: die Nummer voll, die Gutscheinart steht beim Verkauf im Namen der Position (vom Server).
      if (action == VoucherAction.sell) {
        final n = name?.trim() ?? '';
        return n.startsWith(fremd) ? n : fremd;
      }
      return '${action == VoucherAction.payout ? 'Auszahlung ' : ''}$fremd';
    }
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

  /// Ohne Art (Verkauf ueber eine Sorte, die Art kennt erst der Server) steht
  /// nur „Gutschein“ da; den Namen der Sorte setzt der Server am Beleg.
  static String _artText(VoucherType? art) => switch (art) {
        VoucherType.multiPurpose || VoucherType.value => 'Mehrzweckgutschein',
        VoucherType.singlePurpose => 'Einzweckgutschein',
        VoucherType.service => 'Leistungsgutschein',
        VoucherType.promotion || VoucherType.promo => 'Aktionsgutschein',
        null => 'Gutschein',
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

// ---- Fremdgutscheine (Server 2026-11) ---------------------------------------

/// Herkunft eines Fremdgutscheins ([KeckVoucher.source], Katalog `GUTSCHEIN_QUELLE`).
const String voucherSourceExternal = 'external';

/// Alle Herkuenfte eines Gutscheins (Zwilling von `VOUCHER_SOURCES`).
const List<String> voucherSources = [voucherSourceExternal];

/// Hoechstlaenge der Nummer eines Fremdgutscheins (nach dem Abschneiden des Rands).
const int externalVoucherNumberMax = 40;

/// Hoechstlaenge von [KeckVoucher.taxedWith] am Fremdgutschein (Beleg im
/// fremden System, mit dem der Einzweckgutschein versteuert ist).
const int externalVoucherTaxedWithMax = 40;

/// Saetze, mit denen ein fremder Einzweckgutschein verkauft sein kann
/// (Basispunkte): die Saetze der Kasse (20, 10, 13, 19, 4,9 %) und 0 =
/// befreit verkauft (Kleinunternehmer).
const List<int> externalVoucherVatRatesBp = [2000, 1000, 1300, 1900, 490, 0];

final RegExp _fremdNummerMuster = RegExp(r'^[A-Za-z0-9\-_./]{1,40}$');

/// Trenner einer Fremdnummer, die die Pruefung auf den eigenen Code wie `-` liest.
final RegExp _fremdTrenner = RegExp(r'[._/]');

/// Steuer- und Formatzeichen (`gutschein-core.STEUERZEICHEN`): nie in `taxedWith`.
final RegExp _steuerzeichen = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

/// Nummer eines Fremdgutscheins in der Form, mit der der Server sie speichert
/// und druckt (`gutschein-core.normiereFremdnummer`): Rand weg, **keine**
/// Unicode-Normalisierung, Gross-/Kleinschreibung bleibt; dann 1 bis 40
/// Zeichen aus `A-Z a-z 0-9 - _ . /`. Sonst `null`
/// (`external_voucher_number_invalid`). Einen eigenen Gutscheincode erkennt
/// erst [checkExternalVoucherNumber].
///
/// Der Rand ist der Leerraum von `String.prototype.trim` (ASCII, U+00A0,
/// U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF),
/// bewusst ohne U+0085 (NEL), das Dart-`trim` mitnaehme: ein Steuerzeichen
/// verschwindet nie still, es macht die Nummer ungueltig.
String? normalizeExternalVoucherNumber(Object? text) {
  if (text is! String) return null;
  final n = jsTrim(text);
  return _fremdNummerMuster.hasMatch(n) ? n : null;
}

/// Ergebnis von [checkExternalVoucherNumber]: die Nummer wie gespeichert
/// ([ok] `true`, [number]) oder der Fehlercode des Servers ([code]).
class ExternalVoucherNumberCheck {
  const ExternalVoucherNumberCheck.ok(String this.number) : code = null;
  const ExternalVoucherNumberCheck.rejected(String this.code) : number = null;

  /// Die Nummer, wie der Server sie speichert; `null`, wenn abgewiesen.
  final String? number;

  /// `external_voucher_number_is_own_code` oder `external_voucher_number_invalid`; `null`, wenn gueltig.
  final String? code;

  bool get ok => code == null;

  @override
  bool operator ==(Object other) => other is ExternalVoucherNumberCheck && other.number == number && other.code == code;

  @override
  int get hashCode => Object.hash(number, code);

  @override
  String toString() => ok ? 'ExternalVoucherNumberCheck.ok($number)' : 'ExternalVoucherNumberCheck.rejected($code)';
}

/// Prueft eine Fremdnummer in der Reihenfolge des Servers
/// (`gutschein-beleg.pruefeFremd`): zuerst, ob sie ein gueltiger eigener
/// Gutscheincode ist (12 Zeichen mit Pruefzeichen, in jeder Schreibweise der
/// Kasse, auch mit `.`, `_` oder `/` als Trenner) -- dann
/// `external_voucher_number_is_own_code`, der Gutschein gehoert als eigener
/// eingeloest --, danach die Form (`external_voucher_number_invalid`). Die
/// Trenner liest nur die Pruefung als `-`; die Nummer behaelt ihre
/// Schreibweise. Zwilling von `checkExternalVoucherNumber` im npm-Paket.
ExternalVoucherNumberCheck checkExternalVoucherNumber(Object? text) {
  if (text is String && VoucherCode.isValid(text.replaceAll(_fremdTrenner, '-'))) {
    return const ExternalVoucherNumberCheck.rejected('external_voucher_number_is_own_code');
  }
  final number = normalizeExternalVoucherNumber(text);
  return number == null
      ? const ExternalVoucherNumberCheck.rejected('external_voucher_number_invalid')
      : ExternalVoucherNumberCheck.ok(number);
}

/// Wie sehr eine Eingabe einem eigenen Gutscheincode gleicht ([ownVoucherCodeShape]):
/// `valid` = gueltiger eigener Code; `checksum` = 12 Zeichen des Code-Alphabets
/// mit falschem Pruefzeichen (etwa eine zwoelfstellige Webshop-Nummer);
/// `length` = Muster `4-4-x` mit Bindestrichen, aber nicht 12 Zeichen; `none` =
/// keine Aehnlichkeit. Zwilling von `OWN_VOUCHER_CODE_SHAPES`.
const List<String> ownVoucherCodeShapes = ['valid', 'checksum', 'length', 'none'];

/// Alphabet der eigenen Codes (Crockford-Base32 ohne U), nach der Normalisierung von `VoucherCode`.
final RegExp _codeAlphabet = RegExp(r'^[0-9A-HJKMNP-TV-Z]+$');
final RegExp _codeGruppen = RegExp(r'^[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]+$');
final RegExp _leerOderStrich = RegExp(r'[\s-]');

/// Form-Erkennung eigener Codes fuer das Feld „Code eingeben oder scannen“
/// (Web-Kasse und Kassen-App gleich), ein Wert aus [ownVoucherCodeShapes]:
/// `valid` laeuft als eigener Gutschein, `checksum`/`length` fragt die Kasse
/// nach (`external_voucher.looks_like_own_code`, Knopf
/// `external_voucher.use_as_external`), `none` geht bei Freigabe direkt in das
/// Blatt „Fremder Gutschein“. Gelesen wie [checkExternalVoucherNumber]: Rand
/// weg, `.`, `_`, `/` wie `-`, dann die Normalisierung von `VoucherCode`
/// (gross, ohne Leerraum und `-`, O -> 0, I/L -> 1). Eine Nachfrage weist
/// nichts ab: der Server prueft die Fremdnummer selbst
/// (`external_voucher_number_is_own_code` nur bei `valid`). Zwilling von
/// `ownVoucherCodeShape` im npm-Paket.
String ownVoucherCodeShape(Object? text) {
  if (text is! String) return 'none';
  final t = jsTrim(text).replaceAll(_fremdTrenner, '-');
  if (t.isEmpty) return 'none';
  if (VoucherCode.isValid(t)) return 'valid';
  final s = t.toUpperCase().replaceAll(_leerOderStrich, '').replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
  if (!_codeAlphabet.hasMatch(s)) return 'none';
  if (s.length == 12) return 'checksum';
  return _codeGruppen.hasMatch(t) ? 'length' : 'none';
}

bool _fremdCent(int? n) => n != null && n >= 1 && n <= 1000000;

/// Ist der Fremdgutschein sendbar? Die Form wie `gutschein-beleg.pruefeFremd`
/// (ohne die Freigabe des Kontos, die kennt nur der Server bzw.
/// [PosVoucherSettings.externalVouchers]): Aktion `sell`/`redeem`/`payout`,
/// Art [VoucherType.multiPurpose]/[VoucherType.singlePurpose], gueltige
/// Nummer (kein eigener Code), Betrag 1 bis 1.000.000 Cent; Einzweck mit
/// einem Satz aus [externalVoucherVatRatesBp], Mehrzweck ohne; `taxedWith`
/// nur bei Einzweck-Einloesung bzw. -Auszahlung (1 bis 40 Zeichen ohne
/// Steuerzeichen); Auszahlung mit Grund (1 bis 200 Zeichen). Felder eigener
/// Gutscheine (Code, Sorte, Artikel, Menge, Positionen), ein Wert der Altform
/// und Serverfelder nie. Zwilling von `externalVoucherIsValid` im npm-Paket.
bool externalVoucherIsValid(KeckVoucher voucher) {
  final v = voucher;
  if (!v.isExternal) return false;
  if (v.serverFields.isNotEmpty) return false;
  // gutschein-beleg.NICHT_BEI_FREMD (ein in Dart nie gesetztes Feld geht auch nie hinaus).
  if (v.code != null || v.typeId != null || v.articleId != null || v.article != null || v.quantity != null || v.positions != null) {
    return false;
  }
  if (v.balanceAfterCents != null || v.remainingQuantityAfter != null || v.exempt != null) return false;
  if (v.valueCents != null) return false;
  if (v.action != VoucherAction.sell && v.action != VoucherAction.redeem && v.action != VoucherAction.payout) return false;
  final art = v.hasType ? v.type : null;
  if (art != VoucherType.multiPurpose && art != VoucherType.singlePurpose) return false;
  if (!checkExternalVoucherNumber(v.number).ok) return false;
  if (!_fremdCent(v.amountCents)) return false;
  if (art == VoucherType.singlePurpose) {
    if (!externalVoucherVatRatesBp.contains(v.vatRateBp)) return false;
  } else if (v.vatRateBp != null) {
    return false;
  }
  final belegt = v.taxedWith;
  if (belegt != null) {
    if (art != VoucherType.singlePurpose || v.action == VoucherAction.sell) return false;
    final t = jsTrim(belegt);
    if (t.isEmpty || t.length > externalVoucherTaxedWithMax || _steuerzeichen.hasMatch(t)) return false;
  }
  if (v.action == VoucherAction.payout) {
    final g = jsTrim(v.reason ?? '');
    if (g.isEmpty || g.length > 200) return false;
  }
  return true;
}

/// Ganze Zahl oder `null` (auch `3.0` gilt als ganz, `3.5` nicht).
int? _ganz(Object? w) {
  if (w is int) return w;
  if (w is double && w.isFinite && w == w.truncateToDouble()) return w.toInt();
  return null;
}

String? _text(Object? w) => w is String ? w : null;
