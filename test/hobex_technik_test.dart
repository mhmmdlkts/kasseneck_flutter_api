import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';
import 'package:kasseneck_api/pos.dart';

/// Technik von hobex und die HPS-Texte ohne Terminal-Beleg: Zwilling der
/// Faelle zu `HOBEX_SUPPORT` in `test/hobex-hps.test.ts` und der HPS-Faelle in
/// `test/texte.test.ts` im npm-Paket 1.37.0. Das hobex-HPS-Terminal druckt
/// keinen Beleg, an dem der Kassier nachsehen koennte (Inhaber, 12.11.2026).
void main() {
  test('hobexSupport: Technik von hobex, unveraenderlich, ueber hobex_hps.dart erreichbar', () {
    expect(hobexSupport, (phone: '+43 662 2255-88', display: '0662 2255-88', availability: '24/7'));
    // Dieselbe Nummer in beiden Schreibweisen: Durchwahl 88 der Zentrale 2255-0.
    expect(hobexSupport.phone.replaceAll(RegExp(r'[^\d+]'), ''), '+43662225588');
    expect('+43${hobexSupport.display.replaceAll(RegExp(r'\D'), '').substring(1)}', '+43662225588');
  });

  test('HPS: kein Satz schickt zum Terminal-Beleg, der lange Satz warnt trotzdem vor dem zweiten Kassieren', () {
    final terminalBeleg = RegExp(r'Terminal-?[Bb]eleg|Terminalbeleg');
    for (final k in [
      'card_payment.unknown_hps', 'card_payment.unknown_with_id_hps', 'split.card_reverse_failed_hps',
      'split.card_reverse_unknown_hps', 'split.card_already_reversed_hps', 'split.clarify_asking', 'split.clarify_open',
      'split.clarify_not_asked', 'split.clarify_busy', 'split.clarify_no_answer', 'split.clarify_manual',
    ]) {
      expect(posMessages[k]!.text, isNot(matches(terminalBeleg)), reason: k);
    }
    for (final r in HpsCodeReason.values) {
      expect(r.hint, isNot(matches(terminalBeleg)), reason: r.name);
    }
    expect(HpsCodeReason.approvedWithCondition.hint, contains('weiß hobex'));
    for (final k in ['card_payment.unknown_hps', 'card_payment.unknown_with_id_hps']) {
      expect(posMessages[k]!.text, contains('kann belastet sein'), reason: k);
      expect(posMessages[k]!.text, contains('erst klären, dann neu kassieren'), reason: k);
    }
    // Die Fassung mit Kennung ist die ohne plus dem Anker.
    expect(messageText('card_payment.unknown_with_id_hps', {'reference': '42'}),
        '${messageText('card_payment.unknown_hps')} Kennung der Zahlung: 42.');
  });

  test('Klaeren-Fenster: jeder Grund mit Stoerung beim hobex-Host hat seine kurze Zeile, Schluessel = Grund in snake_case', () {
    final host = [for (final r in HpsCodeReason.values) if (r.hostUncertain) r.name]..sort();
    expect(host, ['approvedWithCondition', 'hostFault', 'hostTimeout', 'internalError']);
    for (final grund in host) {
      final k = 'split.clarify_reason_${grund.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}';
      expect(posMessages.containsKey(k), isTrue, reason: k);
      expect(posMessages[k]!.text, startsWith('Grund: '), reason: k);
    }
    expect(messageText('split.clarify_reason_terminal', {'text': 'Etwas Neues', 'code': '4711'}),
        'Grund: Das Terminal meldete „Etwas Neues“ (Code 4711).');
  });

  test('Technik von hobex: Beschriftungen des Fensters auf beiden Seiten, ohne Platzhalter', () {
    expect(labelText('hobex_help.title'), 'Technik von hobex');
    expect(labelText('hobex_help.open'), 'Technik von hobex …');
    for (final k in [
      'hobex_help.open', 'hobex_help.title', 'hobex_help.data', 'hobex_help.tid', 'hobex_help.reference',
      'hobex_help.reversal_reference', 'hobex_help.amount', 'hobex_help.time', 'hobex_help.reason', 'hobex_help.protocol',
      'hobex_help.address', 'hobex_help.serial', 'hobex_help.copy', 'hobex_help.copied',
    ]) {
      expect(posLabels[k]!.only, isNull, reason: k);
      expect(posLabels[k]!.placeholders, isNull, reason: k);
    }
    // Die Nummer steht nur im Fenster, kein Satz traegt sie.
    expect(posMessages.containsKey('card_payment.hobex_support'), isFalse);
  });
}
