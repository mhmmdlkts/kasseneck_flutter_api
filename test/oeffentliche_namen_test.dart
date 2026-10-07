// Waechter: die oeffentliche Oberflaeche von 10.0 ist englisch.
//
// Geprueft wird alles, was ein Verbraucher ueber
// `package:kasseneck_api/<pfad>.dart` erreicht (siehe
// `helpers/oeffentliche_api.dart`): Bibliothekspfade, Top-Level-Namen,
// Klassen, Enums samt Werten, Methoden, oeffentliche Felder, Parameter
// (benannt und positionell, auch in Funktionstypen) und benannte
// Record-Felder. Positionelle Namen gehoeren nicht zum Aufrufvertrag, der
// Verbraucher sieht sie aber im Tooltip der IDE; npm prueft sie ebenso.
//
// Jeder Name wird in Teilwoerter zerlegt (`receiptEmailVias` -> receipt,
// email, vias; `RKSVService` -> rksv, service). Jedes Teilwort muss in einer
// der Positivlisten unten stehen: englische Woerter, technische Kuerzel oder
// Marken. Ein unbekanntes Teilwort laesst den Test fallen, auch wenn es kein
// bekanntes deutsches Wort ist; wer einen neuen englischen Namen einfuehrt,
// traegt sein Teilwort hier ein. Umlaute und andere Zeichen ausserhalb von
// ASCII fallen immer auf.
//
// Deutsch bleibt nur, was als fester Begriff von BMF oder FinanzOnline
// vorgegeben ist, und nur mit Grund:
// - [fachbegriffe]: Teilwoerter, die ueberall erlaubt sind (`rksv`).
// - [ausnahmen]: gebunden an die Deklaration (`<Datei>:<Besitzer>.<Name>`),
//   ein gleichnamiger Name an anderer Stelle bleibt ein Fund.
//
// Drahtschluessel (Strings in `toJson`/`fromJson`) und Menschentexte prueft
// der Waechter nicht; sie sind Vertrag bzw. bleiben deutsch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/oeffentliche_api.dart';

/// Englische Woerter, die in oeffentlichen Namen vorkommen.
final Set<String> woerter = _liste('''
  abort abortable aborted above accept accepted account acquirer action actions active add
  added address affiliate after agent align all allocation allocations allowed allows always amount
  amounts and applies approval approved april area article articles as ask assert
  assign at attempt attempts attribute attributes august auth authority authorization authorized auto available average background
  backoff bad bank banner barcode base batch before behavior below between binary bit
  bits blank block blocked blocks body bold bolt book booking border both
  brand brands breakdown buckets budget build builder bundle business busy by
  byte bytes cache call calls can cancel canceled cancellation cancellations
  cap capability capture card cart cash cashbox cashregister cashregisters
  categories category cause causes cent center cents certificate change changed changes char
  charge chars charset check checked checker checkout chinese chip chips choices city
  clear cleared client clock clone close cloud code codes color colors column
  columns combination commands communication company compare complete
  completion compute conclusive concurrency condition conditions conflict connect
  connection consecutive consumed contains contrast copy correction cost costs count counter country covered
  create created credit currency cursor custom customer customers cut daily
  damaged danger dark data date day days deactivate debtor december decimal decimals
  declined decommissioned default defaults defective delete deleted deliveries delivery delta denied density depth
  description detail details device devices diagnosis differs digits
  dimensions direct directory disabled discount discover discovered discovery
  dispose disposed disposition dispositions distance distribute divider documented done dots double download
  draft drawer dry due effect email emoji empty enable enabled encode encoded end endpoints
  enrollment entered entry enums envelope environment error errors euro event events
  everywhere exact exceeded exception expected expired expires expiry extend external
  extra failed failure failures fallback fast fault fax february feed field
  fields file filename files filled filter final finalized find finished firmware
  first fits flip flow font footer for force foreign form format formats found
  fraction free from full fullscreen function funds gap gateway generator
  german get glass global goods graphics grid gross ground group groups hand hardware has
  hash header headers headings height heights held high hint hints horizontal
  host hosts house hue huge idempotency ids image immediately in included index
  info input installments instant insufficient intent interface interfaces
  internal intro invalid inventory invert invoice invoices is issue issuer item items iterate
  january job journal july june key keys kind kinds label landed language languages
  large last layout lead left legacy legal length level license licenses light limit line
  lines link list load loader local location locations lock login logo logout lookup loss
  lossy lot lots luminance mandate mandatory map march mark matrix may meaning measured
  media medium member merchant merge message metadata method methods metrics migrate
  minimum minutes mismatch missing mixed mode model models modes module
  modules month monthly move movement movements muted my name names native need needs negative net
  network never new next night no none normal normalize not note notes notice
  notices november now number numbers observer october of off offered offset omit on
  onboarding online only open operation operator or order original other out
  outcome outdated output overdue overview own owner package page paid pair
  paired pairs panel paper parse partial password patch pay payload payment
  payments per percent period persistent person phone photos piece pixel
  placeholders plain plate
  platform policy port position present pressed preview previous price prices
  print printer printers printing probe production profile progress project
  promo proof provider public purchase quantities quantity quick quiet radius raised random
  range raster rasters rate rated rates ratio raw read readable reader ready
  reason reasons receipt receipts receive received recipient recipients record redeem
  redeemed reference refresh refund refunds register registered registration rejected
  rejects related release released remaining remove removed render renew replacement replayed report
  reports request requested required requirement requirements reservation reservations reserved reset resolve restock
  resolved resolving response result retries retry return revenue reversal reverse
  reversed right risk rotate row rows rule rules ruleset run safely sale saturation
  save scale scales scan scanned scheme schemes scope screen search seconds
  secret seen select selected selection sell sellable send sent september sequence serial server
  service services session sessions set setting settings setup shadow share
  shared sheet short shortcut shortcuts shorten shortfall shortfalls show side signature signed
  signing since single site size sizing skip sleep small software sold sort
  source sources space split staff stamp standard start started state
  statement status statuses step steps stock stocktake stop storage store stored street strength
  strengths string style styles subnet subtitle subtotal subtracted succeeded
  success sum summary supplier supported surface symbol system table tables takeover tax technical
  tendered term terminal terminals test text texts thanks theme tile tiles
  time timeout timestamp tip title to today token tolerance tone top total totals touch
  tracked tracking training transaction transfer transmitted transport tries turn
  turnover twelfths type types unavailable uncertain underline ungrouped unit
  unexpected units unknown unpack unpaid unpair unresolved unsupported untangle until
  update updated usable user users valid validation value values variant variants vehicle verification
  verify version vertical via vias vienna view virtual visible voided voucher vouchers wall
  wanted warehouse warm warning warnings watermark web webhook webhooks webservice widget widgets width widths
  wire with withdrawal words wrap write written wrong year yesterday zero zone
''');

/// Technische Kuerzel und Einzelbuchstaben (Farbkanaele, Groessen S/M/L,
/// QR-Fehlerkorrektur, Barcode-Arten, Terminalfelder von Hobex/ZVT,
/// Code-Tabellen `pc858`/`wpc1252`/`iso8859_15` und `ESC t`).
final Set<String> kuerzel = _liste('''
  a acc aes aid api app b bic bin c ch codabar cols cor cp cvm d dec doc e ean
  einvoice elv emv esc escpos f fn g gen geo girocode gln h hex hps hr hri hsv
  http iban icm id img init ios ip ipv iso itf j json k kg l lat len lng m mac max
  micros millis min mm ms n ok params pc pct pdf perms pin pos pre pro q qr
  qrcode r ref res rgb rgba s scep sdk sdp sec sepa sig sms src sub t tcp tid
  tids ttl tx tz uid uint upc url usb vat vu w wifi wpc x xl xml y zip
''');

/// Produkt- und Firmennamen.
final Set<String> marken = _liste('''
  android bluetooth gp gptom hobex kasseneck keck kreiseck mypos stripe sumup tecs tom
  uber
''');

/// Feste Begriffe, die als Teilwort ueberall erlaubt sind. Teilwort -> Grund.
const Map<String, String> fachbegriffe = {
  'rksv':
      'Registrierkassensicherheitsverordnung (BMF), fester Begriff wie in RKSVService',
};

/// Namen, die trotz deutschem Teilwort bleiben. Fundstelle -> Grund.
const Map<String, String> ausnahmen = {
  'lib/enums/cashbox_status.dart:CashboxStatus.IN_BETRIEB':
      'Statuswert der FinanzOnline-Antwort (rkdbMessage.status), das Parsing matcht ueber den Enum-Namen',
  'lib/enums/signature_status.dart:SignatureStatus.IN_BETRIEB':
      'Statuswert der FinanzOnline-Antwort fuer die Signaturerstellungseinheit, Parsing ueber den Enum-Namen',
  'lib/enums/signature_status.dart:SignatureStatus.AUSFALL':
      'Statuswert der FinanzOnline-Antwort fuer die Signaturerstellungseinheit, Parsing ueber den Enum-Namen',
};

Set<String> _liste(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

final _grenze = RegExp(r'[^A-Za-z]+');
final _wort = RegExp(r'[A-Z]+(?=[A-Z][a-z]|$)|[A-Z]?[a-z]+|[A-Z]+');

/// Zerlegt einen Namen in kleingeschriebene Teilwoerter.
List<String> teilwoerter(String name) => [
  for (final stueck in name.split(_grenze))
    for (final m in _wort.allMatches(stueck)) m.group(0)!.toLowerCase(),
];

/// Der zu pruefende Name: bei Pfaden ohne `lib/` und `.dart`.
String _pruefname(OeffentlicherName f) => f.art == 'pfad'
    ? f.name
          .replaceFirst(RegExp(r'^lib/'), '')
          .replaceFirst(RegExp(r'\.dart$'), '')
    : f.name;

/// Warum [f] nicht englisch ist, oder `null`.
String? befund(OeffentlicherName f) {
  final name = _pruefname(f);
  if (RegExp(r'[^\x00-\x7F]').hasMatch(name)) {
    return 'Zeichen ausserhalb von ASCII';
  }
  bool erlaubt(String t) =>
      woerter.contains(t) ||
      kuerzel.contains(t) ||
      marken.contains(t) ||
      fachbegriffe.containsKey(t);
  for (final t in teilwoerter(name)) {
    if (erlaubt(t)) continue;
    return 'Teilwort "$t" nicht in der Positivliste';
  }
  return null;
}

/// Alle Funde; [gebraucht] sammelt die Ausnahmen, die gegriffen haben.
List<String> funde(List<OeffentlicherName> api, Set<String> gebraucht) {
  final aus = <String>[];
  for (final f in api) {
    final grund = befund(f);
    if (grund == null) continue;
    if (ausnahmen.containsKey(f.herkunft)) {
      gebraucht.add(f.herkunft);
      continue;
    }
    aus.add('${f.herkunft} (${f.art}): $grund');
  }
  return aus;
}

void main() {
  final lib = Directory('lib');
  final api = oeffentlicheApi(lib);

  test(
    'der Leser findet die Oberflaeche (Pfade, Namen, Felder, Parameter)',
    () {
      final arten = {for (final f in api) f.art};
      expect(
        arten,
        containsAll([
          'pfad',
          'export',
          'erreichbar',
          'member',
          'parameter',
          'record',
        ]),
      );
      final herkunft = {for (final f in api) f.herkunft};
      expect(herkunft, contains('lib/pos.dart'));
      expect(
        herkunft,
        contains(
          'lib/src/kasse/belege.dart:RegisterReceiptClient.cancelReceipt',
        ),
      );
      expect(api.length, greaterThan(3000));
    },
  );

  test('jeder oeffentliche Name ist englisch', () {
    final gefunden = funde(api, <String>{});
    expect(gefunden, isEmpty, reason: gefunden.join('\n'));
  });

  test('jede Ausnahme hat einen Grund und wird gebraucht', () {
    final gebraucht = <String>{};
    funde(api, gebraucht);
    for (final MapEntry(:key, :value) in {
      ...ausnahmen,
      ...fachbegriffe,
    }.entries) {
      expect(value.length, greaterThan(20), reason: '$key: Grund fehlt');
    }
    expect(
      ausnahmen.keys.toSet().difference(gebraucht),
      isEmpty,
      reason: 'Ausnahmen ohne Fund bitte streichen',
    );
    final teile = {for (final f in api) ...teilwoerter(_pruefname(f))};
    expect(
      fachbegriffe.keys.toSet().difference(teile),
      isEmpty,
      reason: 'Fachbegriffe ohne Fund bitte streichen',
    );
  });

  test('die Positivliste haelt keine Leichen', () {
    final teile = {for (final f in api) ...teilwoerter(_pruefname(f))};
    final ungenutzt = {...woerter, ...kuerzel, ...marken}.difference(teile);
    expect(
      ungenutzt,
      isEmpty,
      reason:
          'nicht mehr gebrauchte Eintraege streichen: ${ungenutzt.join(' ')}',
    );
  });

  test('Rot-Probe: deutsche Namen fallen auf, auch ohne Sperrliste', () {
    const datei = 'lib/pos.dart';
    final quelle = File(datei).readAsStringSync();
    const versteckt = 'lib/src/aufrufe.dart';
    final probe = oeffentlicheApi(
      lib,
      quelltext: {
        datei:
            '$quelle\n'
            'class KundenProbe {\n'
            '  int menge = 0;\n'
            '  void speichern(int anzahl, {String? wochentag}) {}\n'
            '  ({int summe, int count}) get paar => (summe: 0, count: 0);\n'
            '}\n'
            'enum Farbe { hell }\n'
            'final int zahlungÜbrig = 0;\n'
            'enum StartProbe { IN_BETRIEB }\n'
            'class HiddenProbe { HiddenType? get hidden => null; }\n',
        // Nicht exportiert, aber ueber HiddenProbe.hidden erreichbar.
        versteckt:
            '${File(versteckt).readAsStringSync()}\n'
            'class HiddenType { int belegZahl = 0; void stornieren({int? menge}) {} }\n',
      },
    );
    final gefunden = funde(probe, <String>{});
    for (final erwartet in [
      'lib/pos.dart:KundenProbe (export)',
      'lib/pos.dart:KundenProbe.menge (member)',
      'lib/pos.dart:KundenProbe.speichern (member)',
      'lib/pos.dart:KundenProbe.speichern(anzahl) (parameter)',
      'lib/pos.dart:KundenProbe.speichern(wochentag) (parameter)',
      'lib/pos.dart:KundenProbe.paar{summe} (record)',
      'lib/pos.dart:Farbe (export)',
      'lib/pos.dart:Farbe.hell (member)',
      'lib/pos.dart:zahlungÜbrig (export)',
      // Die Ausnahme fuer IN_BETRIEB ist an CashboxStatus gebunden, nicht an den Namen.
      'lib/pos.dart:StartProbe.IN_BETRIEB (member)',
      // Erreichbar ueber eine oeffentliche Signatur, obwohl nicht exportiert.
      'lib/src/aufrufe.dart:HiddenType.belegZahl (member)',
      'lib/src/aufrufe.dart:HiddenType.stornieren (member)',
      'lib/src/aufrufe.dart:HiddenType.stornieren(menge) (parameter)',
    ]) {
      expect(
        gefunden.any((g) => g.startsWith(erwartet)),
        isTrue,
        reason: erwartet,
      );
    }
    expect(gefunden.where((g) => g.contains('count')), isEmpty);
  });

  test('Teilwoerter: Grossbuchstaben-Kuerzel und Ziffern trennen', () {
    expect(teilwoerter('RKSVService'), ['rksv', 'service']);
    expect(teilwoerter('CP437Checker'), ['cp', 'checker']);
    expect(teilwoerter('IN_BETRIEB'), ['in', 'betrieb']);
    expect(teilwoerter('receiptEmailVias'), ['receipt', 'email', 'vias']);
  });
}
