import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/hobex_hps.dart';

/// Die Codetabelle gegen den Vertrag des npm-Zwillings
/// (`test/fixtures/vertrag/hobex-hps-codes.json`, gezogen ueber
/// `tool/zwillinge.sh`).
///
/// Beide Zwillinge muessen sich einig sein, welcher Code einen Ausgang
/// festschreibt, welcher ungewiss ist und welcher nur die Anfrage abweist.
/// Liefe das auseinander, faende die Browser-Kasse einen Vorgang schluessig,
/// den die App fuer offen haelt -- und niemand merkte es vor der ersten echten
/// Zahlung.
void main() {
  final Map<String, dynamic> vertrag = jsonDecode(
    File('test/fixtures/vertrag/hobex-hps-codes.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('jeder Code steht gleich in beiden Zwillingen', () {
    final List<Map<String, dynamic>> dort =
        (vertrag['codes'] as List<dynamic>).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> hier = [
      for (final c in HpsCodes.all)
        {
          'code': c.code,
          'title': c.title,
          'meaning': c.meaning,
          'conclusive': c.conclusive,
          'effect': c.effect.name,
          'reason': c.reason.name,
          'source': c.source.name,
          'rejectsRequest': c.rejectsRequest,
        },
    ];
    expect(hier, dort);
  });

  test('jeder Grund hat denselben Satz', () {
    final Map<String, dynamic> dort = vertrag['gruende'] as Map<String, dynamic>;
    expect(
      {for (final r in HpsCodeReason.values) r.name: r.hint},
      dort,
    );
  });

  test('HTTP 409 ist in beiden "Terminal beschaeftigt"', () {
    expect(vertrag['terminalBusyHttpStatus'], 409);
  });
}
