/// Was die Kasse dem Kassier sagt: Saetze, Beschriftungen und die Regeln,
/// welcher Fehler welchen Satz bekommt. Zwilling von `src/pos/texte.ts` im
/// npm-Paket; beide Kassen (Web und App) zeigen so denselben Satz.
///
/// Die Texte selbst stehen in `texte_katalog.dart`, erzeugt aus dem Vertrag
/// (`pos-texts.json`) mit `tool/texte_erzeugen.dart`; hier steht nur, wie sie
/// gelesen werden.
library;

import '../register/fehler.dart';

part 'texte_katalog.dart';

/// Die Seite, auf der ein Satz gilt (`only` im Vertrag).
enum PosSurface { web, app }

/// Ein Eintrag des Katalogs.
class PosText {
  const PosText(this.text, {this.placeholders, this.only});

  /// Der Text mit Platzhaltern der Form `{name}`.
  final String text;

  /// Die Platzhalter im Text; `null`, wenn er keine hat.
  final List<String>? placeholders;

  /// Die Seiten, auf denen der Satz gilt; `null` heisst: auf beiden.
  final List<PosSurface>? only;

  /// Die Form des Vertrags (`pos-texts.json`).
  Map<String, Object> toJson() => {
        'text': text,
        'placeholders': ?placeholders,
        if (only case final seiten?) 'only': [for (final s in seiten) s.name],
      };
}

/// Wie ein Fehler fuer die Einordnung heisst (`kind` im Vertrag):
///
/// * [api]: HTTP 200, `status: 'error'`, der Satz des Backends woertlich
///   ([KasseneckApiError]);
/// * [plainText]: schon fuer den Bildschirm geschrieben, sein eigener Text;
/// * [timeout]: die Frist lief ab, die Anfrage war draussen
///   ([KasseneckHttpError.reasonTimeout]);
/// * [network]: keine Verbindung oder abgerissen
///   ([KasseneckHttpError.reasonNetwork]);
/// * [unexpected]: der Server hat geantwortet, aber nicht wie zugesagt
///   (HTML, 500, fehlende Huelle; Platzhalter `{status}` = HTTP-Code);
/// * [other]: alles Uebrige ist technisch, es gilt der Ersatzsatz des Vorgangs.
enum ErrorKind {
  api('api'),
  plainText('plain_text'),
  timeout('timeout'),
  network('network'),
  unexpected('unexpected'),
  other('other');

  const ErrorKind(this.wire);

  /// Der Wert im Vertrag.
  final String wire;
}

/// Was eine Regel ohne eigenen Satz tut (`behavior` im Vertrag).
enum ErrorRuleBehavior {
  /// Der Satz des Backends, woertlich.
  serverText('server_text'),

  /// Der eigene Text des Fehlers.
  ownText('own_text'),

  /// Der Ersatzsatz des Vorgangs.
  fallback('fallback');

  const ErrorRuleBehavior(this.wire);

  /// Der Wert im Vertrag.
  final String wire;
}

/// Eine Regel: fuer eine Art (und optional bestimmte Codes oder einen
/// Ausgang) entweder ein Satz des Katalogs ([key]) oder ein Verhalten
/// ([behavior]).
class ErrorRule {
  const ErrorRule({required this.kind, this.codes, this.outcome, this.behavior, this.key});

  final ErrorKind kind;

  /// Nur in [errorCodeRules]: die Codes, fuer die die Regel gilt.
  final List<String>? codes;

  /// Nur in [errorOutcomeRules]: der Ausgang, fuer den die Regel gilt.
  final ErrorOutcome? outcome;

  final ErrorRuleBehavior? behavior;

  /// Schluessel des Satzes in [posMessages].
  final String? key;

  /// Die Form des Vertrags (`pos-texts.json`).
  Map<String, Object> toJson() => {
        'kind': kind.wire,
        'codes': ?codes,
        if (outcome case final a?) 'outcome': a.name,
        if (behavior case final b?) 'behavior': b.wire,
        'key': ?key,
      };
}

/// Die Regel fuer einen Fehler, in derselben Reihenfolge wie im Web: zuerst
/// eine Regel aus [errorCodeRules] mit passender Art und passendem [code],
/// dann eine aus [errorOutcomeRules] mit passender Art und passendem
/// [outcome], sonst die eine Regel der Art aus [errorRules].
///
/// [code] ist `KasseneckApiError.code`, [outcome] der Ausgang aus
/// [messageOutcome]. Wer nur [errorRules] nach der Art durchsucht, zeigt den
/// Satz von 1.0.0-rc.4: richtig, aber ohne die Verfeinerungen.
ErrorRule findErrorRule(ErrorKind kind, {String? code, ErrorOutcome? outcome}) {
  if (code != null) {
    for (final r in errorCodeRules) {
      if (r.kind == kind && r.codes!.contains(code)) return r;
    }
  }
  if (outcome != null) {
    for (final r in errorOutcomeRules) {
      if (r.kind == kind && r.outcome == outcome) return r;
    }
  }
  return errorRules.firstWhere((r) => r.kind == kind);
}

/// Der Ausgang, nach dem der Satz gewaehlt wird:
///
/// * [ErrorOutcome.unknown], wenn der Fehler ihn selbst so fuehrt
///   ([isOutcomeUnknown]); seit 10.4.1 tut das der Transport fuer jeden
///   Aufruf mit Wirkung (`unknownOutcomeCalls` in `lib/src/v3.dart`), auch
///   fuer Druckjob, Belegmail, Einstellungen und Kopplung;
/// * [ErrorOutcome.unknown] fuer jede Frist und jeden Netzfehler
///   ([KasseneckHttpError.reasonTimeout], [KasseneckHttpError.reasonNetwork])
///   auf einem Aufruf aus [callsWithEffect], auch wenn ein Fehler selbst
///   `rejected` fuehrt (etwa von Hand gebaut): ob die Anfrage vor dem Abriss
///   schon draussen war, sieht das Paket nicht, und ein zweiter Versuch
///   druckte oder mailte doppelt. Die Liste ist eine Teilmenge der
///   Transport-Liste und bleibt als Vertrag der Kassentexte;
/// * sonst der Ausgang des Fehlers, `null` fuer fremde Fehler.
///
/// Der Transport behaelt seinen Ausgang; nur die Wahl des Satzes ist vorsichtig.
ErrorOutcome? messageOutcome(Object? error) {
  if (isOutcomeUnknown(error)) return ErrorOutcome.unknown;
  if (error is KasseneckHttpError) {
    final netz = error.reason == KasseneckHttpError.reasonTimeout || error.reason == KasseneckHttpError.reasonNetwork;
    if (netz && _mitWirkung.contains(error.functionName.split('/').first)) return ErrorOutcome.unknown;
    return error.outcome;
  }
  if (error is KasseneckApiError) return error.outcome;
  return null;
}

final Set<String> _mitWirkung = callsWithEffect.toSet();

final RegExp _platzhalter = RegExp(r'\{([a-z]+)\}');

String _ersetze(String wo, String text, Map<String, Object> werte) => text.replaceAllMapped(_platzhalter, (m) {
      final wert = werte[m[1]];
      if (wert == null) throw ArgumentError('$wo: Platzhalter {${m[1]}} ohne Wert');
      return '$wert';
    });

/// Der Satz zum Schluessel, Platzhalter ersetzt. Fehlt ein Wert oder ist der
/// Schluessel unbekannt, wirft es: ein `{status}` am Tresen waere schlimmer.
String messageText(String key, [Map<String, Object> values = const {}]) {
  final eintrag = posMessages[key];
  if (eintrag == null) throw ArgumentError.value(key, 'key', 'kein Satz im Katalog');
  return _ersetze('messageText($key)', eintrag.text, values);
}

/// Die Beschriftung zum Schluessel, Platzhalter ersetzt; wirft wie [messageText].
String labelText(String key, [Map<String, Object> values = const {}]) {
  final eintrag = posLabels[key];
  if (eintrag == null) throw ArgumentError.value(key, 'key', 'keine Beschriftung im Katalog');
  return _ersetze('labelText($key)', eintrag.text, values);
}

/// Gilt der Satz auf dieser Seite?
bool messageAppliesTo(String key, PosSurface surface) {
  final eintrag = posMessages[key];
  if (eintrag == null) throw ArgumentError.value(key, 'key', 'kein Satz im Katalog');
  return eintrag.only?.contains(surface) ?? true;
}

/// Der Satz zu einem `code` des Backends beim Senden eines Belegs per
/// E-Mail. Einen unbekannten Code faengt der allgemeine Satz auf.
String receiptEmailErrorMessage(String? code) => receiptEmailErrorMessages[code] ?? 'receipt.mail_failed';

/// Der Satz zu einem `code` des Backends beim Storno mit mehreren Zahlungen.
/// Einen unbekannten Code faengt der allgemeine Storno-Satz auf.
String cancellationPaymentErrorMessage(String? code) =>
    cancellationPaymentErrorMessages[code] ?? 'cancellation.failed';
