/// Kasseninfo fuer die Pruefung (Kassennachschau, Stufe 2b): was die Kasse
/// dem Pruefer ueber sich sagt – Produkt, Hersteller, Kassen-ID, Signatur,
/// DEP, Abschluesse und Kontakt. Zwilling von `pos/kasseninfo.ts` im
/// npm-Paket.
///
/// Die Werte kommen vom Kassenweg (`RegisterReceiptClient.getRegisterInspectionInfo`),
/// die Woerter aus dem Katalog (`inspection.*`). Am Bildschirm und auf dem
/// Ausdruck steht derselbe Text: [inspectionInfoRows] fuer den Bildschirm,
/// [inspectionInfoLines] fuer den Bondrucker. Die Prueffaelle stehen im
/// Vertrag (`inspection-info-cases.json`); beide Pakete liefern dieselben
/// Zeilen. Fehlt ein Wert, entfaellt die Zeile; ein „unbekannt“ steht nie da.
library;

import '../../services/vienna_time.dart';
import '../register/fehler.dart';
import 'texte.dart' show labelText, messageText;

/// Stand der Signatureinheit: in Betrieb.
const String inspectionSignatureActive = 'active';

/// Stand der Signatureinheit: offener Ausfall der Kasse.
const String inspectionSignatureOutage = 'outage';

String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;
bool? _wahr(Object? v) => v is bool ? v : null;
Map<String, dynamic>? _objekt(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// Produkt der Kasse (`product`).
class RegisterInspectionProduct {
  const RegisterInspectionProduct({this.name, this.cloudBased});

  factory RegisterInspectionProduct.fromJson(Map<String, dynamic> json) =>
      RegisterInspectionProduct(name: _text(json['name']), cloudBased: _wahr(json['cloudBased']));

  final String? name;

  /// `true`: cloudbasierte Registrierkasse.
  final bool? cloudBased;

  Map<String, dynamic> toJson() => {'name': ?name, 'cloudBased': ?cloudBased};
}

/// Hersteller der Kasse (`manufacturer`).
class RegisterInspectionManufacturer {
  const RegisterInspectionManufacturer({this.name, this.vatId});

  factory RegisterInspectionManufacturer.fromJson(Map<String, dynamic> json) =>
      RegisterInspectionManufacturer(name: _text(json['name']), vatId: _text(json['vatId']));

  final String? name;

  /// UID des Herstellers.
  final String? vatId;

  Map<String, dynamic> toJson() => {'name': ?name, 'vatId': ?vatId};
}

/// Signatureinheit der Kasse, wie das Zertifikat sie nennt. Zeitpunkte als
/// ISO-8601 in UTC; die Seriennummer dezimal als Text (sie kann groesser als
/// 2^53 sein). Was der Server nicht sicher weiss, ist `null`.
class RegisterInspectionSignature {
  const RegisterInspectionSignature({
    this.provider,
    this.serialHex,
    this.serialDecimal,
    this.holder,
    this.issuer,
    this.validFrom,
    this.validTo,
    this.holderChecked,
    this.testCard = false,
    this.status,
    this.outageSince,
  });

  /// Positivliste wie im npm-Paket: nur die bekannten Felder mit passendem
  /// Typ; ein unbekannter Stand wird `null`, eine fehlende Angabe zur
  /// Testkarte `false`.
  factory RegisterInspectionSignature.fromJson(Map<String, dynamic> json) {
    final stand = json['status'];
    return RegisterInspectionSignature(
      provider: _text(json['provider']),
      serialHex: _text(json['serialHex']),
      serialDecimal: _text(json['serialDecimal']),
      holder: _text(json['holder']),
      issuer: _text(json['issuer']),
      validFrom: _text(json['validFrom']),
      validTo: _text(json['validTo']),
      holderChecked: _wahr(json['holderChecked']),
      testCard: json['testCard'] == true,
      status: stand == inspectionSignatureActive || stand == inspectionSignatureOutage ? stand as String : null,
      outageSince: _text(json['outageSince']),
    );
  }

  /// Anbieter der Karte; heute nur `a_trust`. Fehlt bei Testkarten und
  /// unbekanntem Anbieter.
  final String? provider;
  final String? serialHex;
  final String? serialDecimal;

  /// Inhaber laut Zertifikat, etwa `UID ATU12345675`.
  final String? holder;

  /// Aussteller laut Zertifikat.
  final String? issuer;
  final String? validFrom;
  final String? validTo;

  /// `true` nur, wenn der Inhaber mit A-Trust abgeglichen ist und passt.
  final bool? holderChecked;

  /// Testkarte (Sandbox).
  final bool testCard;

  /// [inspectionSignatureActive] oder [inspectionSignatureOutage]; `null`,
  /// wenn der Server keinen oder einen diesem Paket unbekannten Stand meldet.
  final String? status;

  /// Beginn eines offenen Ausfalls (nur bei [inspectionSignatureOutage]).
  final String? outageSince;

  Map<String, dynamic> toJson() => {
        'provider': ?provider,
        'serialHex': ?serialHex,
        'serialDecimal': ?serialDecimal,
        'holder': ?holder,
        'issuer': ?issuer,
        'validFrom': ?validFrom,
        'validTo': ?validTo,
        'holderChecked': ?holderChecked,
        'testCard': testCard,
        'status': ?status,
        'outageSince': ?outageSince,
      };
}

/// Zeitplan des Monatsbelegs (`closings`); [monthlyTime] als `HH:MM` in
/// [timeZone].
class RegisterInspectionClosings {
  const RegisterInspectionClosings({this.monthlyDay, this.monthlyTime, this.timeZone, this.annualIsDecember});

  factory RegisterInspectionClosings.fromJson(Map<String, dynamic> json) {
    // Ganze Zahl wie `Number.isInteger` im npm-Paket: auch 15.0 ist der 15.
    final roh = json['monthlyDay'];
    final tag = roh is int ? roh : (roh is double && roh.isFinite && roh == roh.truncateToDouble() ? roh.toInt() : null);
    return RegisterInspectionClosings(
      monthlyDay: tag != null && tag >= 1 && tag <= 31 ? tag : null,
      monthlyTime: _text(json['monthlyTime']),
      timeZone: _text(json['timeZone']),
      annualIsDecember: _wahr(json['annualIsDecember']),
    );
  }

  /// Tag im Monat (1 = Monatserster).
  final int? monthlyDay;
  final String? monthlyTime;
  final String? timeZone;

  /// `true`: der Dezember-Beleg ist der Jahresbeleg.
  final bool? annualIsDecember;

  Map<String, dynamic> toJson() => {
        'monthlyDay': ?monthlyDay,
        'monthlyTime': ?monthlyTime,
        'timeZone': ?timeZone,
        'annualIsDecember': ?annualIsDecember,
      };
}

/// Antwort von `getRegisterInspectionInfo`. Jedes Feld kann fehlen.
class RegisterInspectionInfo {
  const RegisterInspectionInfo({
    this.cashregisterId,
    this.product,
    this.manufacturer,
    this.signature,
    this.closings,
    this.contactEmail,
  });

  /// Liest `data` der Antwort ueber eine Positivliste: ein Feld mit falschem
  /// Typ faellt weg, alles Unbekannte wird nicht gelesen.
  factory RegisterInspectionInfo.fromJson(Map<String, dynamic> json) {
    final produkt = _objekt(json['product']);
    final hersteller = _objekt(json['manufacturer']);
    final signatur = _objekt(json['signature']);
    final abschluesse = _objekt(json['closings']);
    return RegisterInspectionInfo(
      cashregisterId: _text(json['cashregisterId']),
      product: produkt == null ? null : RegisterInspectionProduct.fromJson(produkt),
      manufacturer: hersteller == null ? null : RegisterInspectionManufacturer.fromJson(hersteller),
      signature: signatur == null ? null : RegisterInspectionSignature.fromJson(signatur),
      closings: abschluesse == null ? null : RegisterInspectionClosings.fromJson(abschluesse),
      contactEmail: _text(json['contactEmail']),
    );
  }

  final String? cashregisterId;
  final RegisterInspectionProduct? product;
  final RegisterInspectionManufacturer? manufacturer;

  /// `null` ohne Signatureinheit oder ohne lesbares Zertifikat einer echten
  /// Karte.
  final RegisterInspectionSignature? signature;
  final RegisterInspectionClosings? closings;

  /// Kontaktadresse fuer den Pruefer; kommt nur vom Server, nie fest aus der
  /// Kasse.
  final String? contactEmail;

  /// Die Drahtform: fehlende Werte fehlen, `signature` steht immer da.
  Map<String, dynamic> toJson() => {
        'cashregisterId': ?cashregisterId,
        'product': ?product?.toJson(),
        'manufacturer': ?manufacturer?.toJson(),
        'signature': signature?.toJson(),
        'closings': ?closings?.toJson(),
        'contactEmail': ?contactEmail,
      };
}

/// Eine Zeile der Kasseninfo am Bildschirm: Bezeichnung und eine oder mehrere
/// Wertzeilen (die Seriennummer hat zwei).
///
/// [key] ist `product`, `manufacturer`, `cashregister_id`, `unit`, `hosting`,
/// `certificate`, `holder`, `issuer`, `valid`, `check`, `status`, `dep`,
/// `closings` oder `contact`; [section] ist `register`, `signature` (unter
/// der Ueberschrift `inspection.signature`) oder `operation`. [label] ist leer
/// bei `product`: die Zeile steht ohne Bezeichnung ueber die ganze Breite.
class InspectionInfoRow {
  const InspectionInfoRow({required this.key, required this.section, required this.label, required this.value});

  final String key;
  final String section;
  final String label;
  final List<String> value;

  Map<String, dynamic> toJson() => {'key': key, 'section': section, 'label': label, 'value': value};

  @override
  String toString() => 'InspectionInfoRow($key, $label: ${value.join(' / ')})';
}

/// Breite der Bezeichnungsspalte im Ausdruck (die laengste Bezeichnung hat 10
/// Zeichen).
const int _spalte = 13;

/// Schmaler darf der Bon nicht sein: die Wertspalte braucht noch 11 Zeichen.
const int _mindestbreite = 24;

/// Geschuetztes Leerzeichen, nur innerhalb dieser Datei: haelt etwa
/// „UID ATU76279224“ beim Umbruch zusammen. Hinaus geht immer ein
/// gewoehnliches Leerzeichen.
const String _geschuetzt = '\u00a0';

/// Steuerzeichen (auch Zeilenumbruch, Tabulator und C1) aus Serverwerten werden Leerzeichen.
final RegExp _steuerzeichen = RegExp(r'[\u0000-\u001f\u007f-\u009f]+');

String? _bereinigt(String? v) {
  if (v == null) return null;
  final t = v.replaceAll(_steuerzeichen, ' ').trim();
  return t.isEmpty ? null : t;
}

/// [teil] in [text] haelt beim Umbruch zusammen (seine Leerzeichen werden geschuetzt).
String _zusammen(String text, String teil) => text.replaceFirst(teil, teil.split(' ').join(_geschuetzt));

/// Der ganze [text] haelt zusammen, soweit er in die Zeile passt.
String _ganz(String text) => _zusammen(text, text);

String _offen(String t) => t.split(_geschuetzt).join(' ');

String _zwei(int n) => n.toString().padLeft(2, '0');

/// `TT.MM.JJJJ` und `HH:MM` eines Zeitpunkts in Wiener Zeit, nie aus der
/// Zeitzone des Geraets.
({String date, String time}) _wienerZeit(DateTime zeitpunkt) {
  final t = ViennaTime.toWallClock(zeitpunkt);
  return (date: '${_zwei(t.day)}.${_zwei(t.month)}.${t.year}', time: '${_zwei(t.hour)}:${_zwei(t.minute)}');
}

/// Dieselben Formen wie `parseServerTimeStamp` im npm-Paket: mit Zone (`Z`
/// oder Versatz) ein Zeitpunkt, ohne Zone Wiener Wanduhrzeit mit Sekunden.
/// `DateTime.parse` naehme mehr (etwa einen Tag ohne Uhrzeit), das npm-Paket
/// nicht; beide Kassen sollen dieselbe Zeile zeigen.
final RegExp _mitZone = RegExp(r'Z$|[+-]\d{2}:?\d{2}$');
final RegExp _ohneZone = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?$');

/// Ein Zeitpunkt des Servers in Wiener Zeit; unlesbar = `null` (die Angabe entfaellt).
({String date, String time})? _wien(String? iso) {
  if (iso == null) return null;
  final roh = iso.trim();
  if (!_mitZone.hasMatch(roh) && !_ohneZone.hasMatch(roh)) return null;
  try {
    return _wienerZeit(ViennaTime.parseServerTimeStamp(roh));
  } on FormatException {
    return null;
  }
}

/// Die Zeilen mit geschuetzten Leerzeichen; [inspectionInfoRows] und
/// [inspectionInfoLines] teilen sie.
List<InspectionInfoRow> _zeilenRoh(RegisterInspectionInfo info) {
  final zeilen = <InspectionInfoRow>[];
  void zeile(String key, String section, String? label, List<String?> werte) {
    final value = [for (final w in werte) ?w];
    if (value.isNotEmpty) {
      zeilen.add(InspectionInfoRow(key: key, section: section, label: label == null ? '' : labelText(label), value: value));
    }
  }

  // --- Kasse
  final produkt = _bereinigt(info.product?.name);
  if (produkt != null) {
    zeile('product', 'register', null,
        [info.product?.cloudBased == true ? labelText('inspection.product_cloud', {'name': produkt}) : produkt]);
  }
  final herstellerName = _bereinigt(info.manufacturer?.name);
  final uid = _bereinigt(info.manufacturer?.vatId);
  final uidText = uid == null ? null : _ganz(labelText('inspection.vat_id', {'number': uid}));
  final hersteller = [?herstellerName, ?uidText];
  zeile('manufacturer', 'register', 'inspection.manufacturer', [hersteller.isNotEmpty ? hersteller.join(', ') : null]);
  zeile('cashregister_id', 'register', 'inspection.cashregister_id', [_bereinigt(info.cashregisterId)]);

  // --- Signatur
  final s = info.signature;
  if (s != null) {
    final aTrust = !s.testCard && s.provider == 'a_trust';
    zeile('unit', 'signature', 'inspection.unit', [
      s.testCard
          ? labelText('inspection.unit_test_card')
          : aTrust
              ? labelText('inspection.unit_a_trust')
              : null,
    ]);
    zeile('hosting', 'signature', 'inspection.hosting', [aTrust ? labelText('inspection.hosting_server') : null]);
    final hex = _bereinigt(s.serialHex);
    final dezimal = _bereinigt(s.serialDecimal);
    // Die Zahl bleibt beim Umbruch bei ihrer Angabe in Klammern („11c6c7cd (hex)“).
    String seriennr(String key, String nummer) => _zusammen(labelText(key, {'number': nummer}), '$nummer (');
    zeile('certificate', 'signature', 'inspection.certificate', [
      hex == null ? null : seriennr('inspection.serial_hex', hex),
      dezimal == null
          ? null
          : seriennr(hex == null ? 'inspection.serial_decimal_only' : 'inspection.serial_decimal', dezimal),
    ]);
    zeile('holder', 'signature', 'inspection.holder', [_bereinigt(s.holder)]);
    zeile('issuer', 'signature', 'inspection.issuer', [_bereinigt(s.issuer)]);
    final von = _wien(s.validFrom);
    final bis = _wien(s.validTo);
    zeile('valid', 'signature', 'inspection.valid', [
      von != null && bis != null
          ? labelText('inspection.valid_range', {'from': von.date, 'to': bis.date})
          : von != null
              ? labelText('inspection.valid_from', {'date': von.date})
              : bis != null
                  ? labelText('inspection.valid_to', {'date': bis.date})
                  : null,
    ]);
    zeile('check', 'signature', 'inspection.check', [s.holderChecked == true ? labelText('inspection.check_holder') : null]);
    final seit = s.status == inspectionSignatureOutage ? _wien(s.outageSince) : null;
    // Datum und Uhrzeit des Ausfalls bleiben beim Umbruch zusammen.
    final ausfall = seit == null
        ? labelText('inspection.status_outage')
        : _zusammen(labelText('inspection.status_outage_since', {'date': seit.date, 'time': seit.time}),
            '${seit.date}, ${seit.time}');
    zeile('status', 'signature', 'inspection.status', [
      s.status == inspectionSignatureActive
          ? labelText('inspection.status_active')
          : s.status == inspectionSignatureOutage
              ? ausfall
              : null,
    ]);
  }

  // --- DEP, Abschluesse, Kontakt
  zeile('dep', 'operation', 'inspection.dep', [labelText('inspection.dep_online')]);
  final tag = info.closings?.monthlyDay;
  final uhrzeit = _bereinigt(info.closings?.monthlyTime);
  if (tag != null && uhrzeit != null) {
    final monat = tag == 1
        ? labelText('inspection.closings_monthly_first', {'time': uhrzeit})
        : labelText('inspection.closings_monthly_day', {'n': tag, 'time': uhrzeit});
    final satz = info.closings?.annualIsDecember == true
        ? '$monat, ${labelText('inspection.closings_annual_december')}'
        : monat;
    zeile('closings', 'operation', 'inspection.closings', [satz]);
  }
  zeile('contact', 'operation', 'inspection.contact', [_bereinigt(info.contactEmail)]);
  return zeilen;
}

/// Die Zeilen der Kasseninfo fuer den Bildschirm, in der Reihenfolge des
/// Ausdrucks. Ueberschrift (`inspection.title`), die Ueberschrift vor dem Teil
/// `signature` (`inspection.signature`) und der Absatz „So arbeitet die
/// Kasse:“ (`inspection.how_it_works`, `inspection.how_it_works_text`) kommen
/// aus dem Katalog.
List<InspectionInfoRow> inspectionInfoRows(RegisterInspectionInfo info) => [
      for (final z in _zeilenRoh(info))
        InspectionInfoRow(key: z.key, section: z.section, label: z.label, value: [for (final w in z.value) _offen(w)]),
    ];

/// Wortweiser Umbruch auf [breite] Zeichen. Getrennt wird nur an
/// gewoehnlichen Leerzeichen; ein Wort, das allein zu lang ist, wird an
/// seinen geschuetzten Leerzeichen und dann hart geteilt. Nie laenger als
/// [breite].
List<String> _umbrechen(String eingabe, int breite) {
  final woerter = <String>[];
  for (final wort in eingabe.split(' ')) {
    if (wort.isEmpty) continue;
    if (wort.length <= breite) {
      woerter.add(wort);
      continue;
    }
    for (final teil in wort.split(_geschuetzt)) {
      for (var i = 0; i < teil.length; i += breite) {
        woerter.add(teil.substring(i, i + breite > teil.length ? teil.length : i + breite));
      }
    }
  }
  final zeilen = <String>[];
  var zeile = '';
  for (final wort in woerter) {
    if (zeile.isEmpty) {
      zeile = wort;
    } else if (zeile.length + 1 + wort.length <= breite) {
      zeile += ' $wort';
    } else {
      zeilen.add(zeile);
      zeile = wort;
    }
  }
  if (zeile.isNotEmpty) zeilen.add(zeile);
  return [for (final z in zeilen) _offen(z)];
}

/// Eine Zeile im Ausdruck: Bezeichnung in der Spalte, Werte rechts davon;
/// ohne Bezeichnung ueber die ganze Breite.
List<String> _druckzeilen(InspectionInfoRow z, int breite) {
  if (z.label.isEmpty) return [for (final w in z.value) ..._umbrechen(w, breite)];
  final aus = <String>[];
  String? kopf = z.label.padRight(_spalte);
  if (z.label.length >= _spalte) {
    // Passt die Bezeichnung nicht in die Spalte, steht sie allein darueber.
    aus.addAll(_umbrechen(z.label, breite));
    kopf = null;
  }
  for (final w in z.value) {
    for (final teil in _umbrechen(w, breite - _spalte)) {
      aus.add((kopf ?? ' ' * _spalte) + teil);
      kopf = null;
    }
  }
  return aus;
}

/// Die Kasseninfo als Textzeilen fuer den Bondrucker: kein Belegkopf, keine
/// Belegnummer, nicht signiert (kein Beleg). Ueberschriften in Grossschrift,
/// Bezeichnungen in einer Spalte von 13 Zeichen, lange Werte brechen
/// wortweise in der Wertspalte um. Zwischen den Bloecken eine Leerzeile, am
/// Ende „Gedruckt TT.MM.JJJJ, HH:MM“ ([printedAt] in Wiener Zeit). Keine Zeile
/// ist laenger als [width] (Zeichen je Zeile, meist 32, 42 oder 48,
/// mindestens 24; sonst [KasseneckValidationError] vor dem Rechnen).
List<String> inspectionInfoLines(RegisterInspectionInfo info, {required int width, required DateTime printedAt}) {
  if (width < _mindestbreite) {
    throw const KasseneckValidationError('inspectionInfoLines', 'width muss eine ganze Zahl ab $_mindestbreite sein', 'request');
  }
  final zeilen = _zeilenRoh(info);
  List<String> teil(String section) => [
        for (final z in zeilen)
          if (z.section == section) ..._druckzeilen(z, width),
      ];
  final signatur = teil('signature');
  final wann = _wienerZeit(printedAt);
  final bloecke = <List<String>>[
    _umbrechen(labelText('inspection.title').toUpperCase(), width),
    teil('register'),
    if (signatur.isNotEmpty) [..._umbrechen(labelText('inspection.signature').toUpperCase(), width), ...signatur],
    teil('operation'),
    [..._umbrechen(labelText('inspection.how_it_works'), width), ..._umbrechen(messageText('inspection.how_it_works_text'), width)],
    _umbrechen(
        _zusammen(labelText('inspection.printed_at', {'date': wann.date, 'time': wann.time}), '${wann.date}, ${wann.time}'),
        width),
  ];
  final aus = <String>[];
  for (final b in bloecke.where((b) => b.isNotEmpty)) {
    if (aus.isNotEmpty) aus.add('');
    aus.addAll(b);
  }
  return aus;
}
