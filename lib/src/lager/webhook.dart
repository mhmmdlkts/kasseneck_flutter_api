/// Eingehende Konto-Webhooks der Lager-API: Signatur pruefen, Ereignis lesen –
/// Zwilling von `src/inventory/webhook.ts` (und der Pruefung in
/// `src/partner/webhook-signatur.ts`) im JS-Paket.
///
/// Dasselbe Verfahren wie bei Partner-Webhooks (Backend
/// `gemeinsam/webhook-core.js`): Kopf
/// `X-Kasseneck-Signature: t=<unix-sekunden>,v1=<hex>` mit
/// `v1 = HMAC-SHA256(secret, "<t>.<roher Rumpf>")`.
///
/// Vier Dinge muessen stimmen, und jedes einzelne fehlt in der Praxis
/// regelmaessig:
///
/// 1. **Der rohe Rumpf.** Signiert sind die Bytes, die ankommen, nicht das
///    Ergebnis von `jsonDecode` und erneutem `jsonEncode` (Reihenfolge,
///    Zahlenschreibweise und Leerraum aendern sich dabei).
/// 2. **Das Zeitfenster.** Ohne Pruefung von `t` waere eine mitgeschnittene,
///    gueltig signierte Zustellung fuer immer wiederverwendbar. 300 Sekunden in
///    beide Richtungen, auch in die Zukunft: sonst hilft eine falsch gestellte
///    Uhr auf der Gegenseite dem Angreifer.
/// 3. **Der zeitkonstante Vergleich.** Ein `==` auf Hex-Text bricht beim ersten
///    abweichenden Zeichen ab; wer die Dauer der Ablehnung messen kann, raet
///    die Signatur Zeichen fuer Zeichen.
/// 4. **Jede Ausnahme ist eine Ablehnung.** Ein `catch`, das weiterlaufen
///    laesst, machte aus einem Formfehler ein Ja.
///
/// Anders als im JS-Zwilling ist die Pruefung **synchron** (`bool`, kein
/// `Future`): `package:crypto` rechnet in reinem Dart. Ein vergessenes `await`
/// kann es hier nicht geben.
///
/// Reihenfolge im Empfaenger: **erst pruefen, dann lesen**.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../register/fehler.dart';
import 'lesen.dart';
import 'modelle.dart';
import 'vertrag.dart';

/// Der Kopf, in dem die Signatur steht.
const String webhookSignatureHeader = 'X-Kasseneck-Signature';

/// Der Kopf mit dem Ereignisnamen (dasselbe wie `type` im Rumpf).
const String webhookEventHeader = 'X-Kasseneck-Event';

/// Der Kopf mit der Zustell-Kennung; bei Wiederholungen **dieselbe**.
const String webhookDeliveryHeader = 'X-Kasseneck-Delivery';

/// Erlaubte Abweichung des Zeitstempels in Sekunden, in beide Richtungen.
const int webhookToleranceSec = 300;

/// Prueft die Signatur einer Zustellung. `true` nur, wenn Kopf, Zeitfenster
/// und HMAC stimmen; jede schlechte Eingabe und jede Ausnahme ist `false`,
/// nie ein Wurf.
///
/// - [secret]: das Secret aus `createWebhook`/`rotateWebhookSecret` als
///   `String`, oder eine Liste davon fuer den eigenen Wechsel (es reicht, wenn
///   eines passt).
/// - [header]: der Wert von `X-Kasseneck-Signature`, unveraendert. Mehrere
///   `v1=`-Anteile sind erlaubt.
/// - [rawBody]: der **rohe** Rumpf als `String` oder als Bytes (`List<int>`,
///   etwa `Uint8List`).
/// - [now]: jetzt; Vorgabe ist die Systemuhr.
bool verifyInventoryWebhookSignature(
  Object? secret,
  String? header,
  Object? rawBody, {
  int toleranceSec = webhookToleranceSec,
  DateTime? now,
}) {
  try {
    final secrets = <String>[
      if (secret is String) secret else if (secret is Iterable) ...secret.whereType<String>(),
    ].where((s) => s.isNotEmpty).toList();
    if (secrets.isEmpty || header == null || header.trim().isEmpty) return false;
    final kopf = _kopfLesen(header);
    if (kopf == null) return false;
    final List<int> rumpf;
    if (rawBody is String) {
      rumpf = utf8.encode(rawBody);
    } else if (rawBody is List<int>) {
      rumpf = rawBody;
    } else {
      return false;
    }
    // Abgerundet wie Math.floor(ms / 1000) im JS-Zwilling.
    final jetzt = ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000).floor();
    // In BEIDE Richtungen: eine vorgehende Uhr auf der Gegenseite darf ein
    // altes Ereignis nicht wieder gueltig machen.
    if ((jetzt - kopf.t).abs() > toleranceSec) return false;
    final nachricht = [...utf8.encode('${kopf.t}.'), ...rumpf];
    for (final s in secrets) {
      final soll = Hmac(sha256, utf8.encode(s)).convert(nachricht).bytes;
      for (final v1 in kopf.v1) {
        final ist = _hexZuBytes(v1);
        if (ist != null && _gleichZeitkonstant(ist, soll)) return true;
      }
    }
    return false;
  } on Object {
    // Punkt 4 oben: eine Ausnahme ist eine Ablehnung, nie ein Ja (auch ein
    // Byte ausserhalb 0–255 in rawBody).
    return false;
  }
}

/// Zerlegt den Signaturkopf; `null`, wenn kein brauchbarer Zeitstempel oder
/// gar kein `v1=`-Anteil darin steht.
({int t, List<String> v1})? _kopfLesen(String header) {
  final teile = header.split(',').map((x) => x.trim()).toList();
  final tTeil = teile.where((x) => x.startsWith('t=')).firstOrNull;
  final v1 = [for (final x in teile) if (x.startsWith('v1=')) x.substring(3)];
  if (tTeil == null || v1.isEmpty) return null;
  final roh = tTeil.substring(2);
  // Nur ganze Zahlen: `1e9`, `+12` oder ` 12 ` waeren sonst gueltige Zeitstempel.
  if (!RegExp(r'^\d{1,15}$').hasMatch(roh)) return null;
  return (t: int.parse(roh), v1: v1);
}

final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

/// Hex zu Bytes; `null` bei ungerader Laenge oder Nicht-Hex.
List<int>? _hexZuBytes(String hex) {
  if (hex.isEmpty || hex.length.isOdd || !_hex.hasMatch(hex)) return null;
  return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

/// Vergleich ohne fruehes Abbrechen. Die Laengenpruefung davor verraet nur die
/// Laenge des Hashs, und die ist bekannt (SHA-256, 32 Bytes); der Inhalt wird
/// immer vollstaendig durchlaufen.
bool _gleichZeitkonstant(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var unterschied = 0;
  for (var i = 0; i < a.length; i++) {
    unterschied |= a[i] ^ b[i];
  }
  return unterschied == 0;
}

// ---- Ereignisse ------------------------------------------------------------------

/// Eine Zustellung als typisiertes Ereignis; die Unterklasse sagt, welches.
///
/// ```dart
/// switch (event) {
///   case InventoryStockChangedEvent(:final data): ...
///   case InventoryStockBelowMinimumEvent(:final data): ...
///   case InventoryArticleEvent(:final data): ...
///   case InventoryReservationEvent(:final data): ...
///   case InventoryVariantGroupEvent(:final data): ...
/// }
/// ```
///
/// Seit 10.4 gibt es [InventoryReservationEvent], seit 10.5
/// [InventoryVariantGroupEvent]. Ein `switch` ohne `default`, der alle
/// Unterklassen aufzaehlt, braucht fuer jede einen Zweig.
sealed class InventoryWebhookEvent {
  const InventoryWebhookEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.accountId,
    required this.test,
  });

  /// `evt_…`: darauf entdoppeln.
  final String id;

  /// Ein Wert aus `inventoryWebhookEvents`.
  final String type;

  /// Millisekunden seit 1970 (UTC).
  final int createdAt;

  /// Das Konto, dessen Lager das Ereignis betrifft.
  final String accountId;

  /// `true` nur bei einer Probe aus `sendWebhookTest` (erfundene Nutzlast).
  /// An den Anfang jedes Handlers: `if (event.test) return;`
  final bool test;

  /// Die Nutzlast; in den Unterklassen mit ihrem Typ.
  Object get data;
}

/// `stock.changed`: der aktuelle Stand eines Artikels an einem Standort.
/// Einen gespeicherten Stand nur ueberschreiben, wenn `data.sequence` groesser ist.
final class InventoryStockChangedEvent extends InventoryWebhookEvent {
  const InventoryStockChangedEvent({
    required super.id,
    required super.createdAt,
    required super.accountId,
    required super.test,
    required this.data,
  }) : super(type: 'stock.changed');

  @override
  final StockChangedEventData data;
}

/// `stock.below_minimum`: einmal beim Unterschreiten des Mindestbestands des
/// Standorts.
final class InventoryStockBelowMinimumEvent extends InventoryWebhookEvent {
  const InventoryStockBelowMinimumEvent({
    required super.id,
    required super.createdAt,
    required super.accountId,
    required super.test,
    required this.data,
  }) : super(type: 'stock.below_minimum');

  @override
  final StockBelowMinimumEventData data;
}

/// `article.created`, `article.updated` oder `article.deactivated` ([type]):
/// der Artikel wie `getArticle` ihn liefert, ohne Einkaufspreise.
final class InventoryArticleEvent extends InventoryWebhookEvent {
  const InventoryArticleEvent({
    required super.id,
    required super.type,
    required super.createdAt,
    required super.accountId,
    required super.test,
    required this.data,
  });

  @override
  final Article data;
}

/// `reservation.expired`, `reservation.released` oder `reservation.redeemed`
/// ([type]): die Reservierung wie `getReservation` sie liefert, mit dem Status
/// nach dem Vorgang. `released` und `redeemed` kommen bei jeder wirksamen
/// Freigabe bzw. Einloesung, auch einer teilweisen; dann bleibt der Status
/// `active`. Seit 10.4.
final class InventoryReservationEvent extends InventoryWebhookEvent {
  const InventoryReservationEvent({
    required super.id,
    required super.type,
    required super.createdAt,
    required super.accountId,
    required super.test,
    required this.data,
  });

  @override
  final Reservation data;
}

/// `variant_group.created` oder `variant_group.updated` ([type]): die
/// Variantengruppe wie `getVariantGroup` sie liefert. `updated` kommt nur bei
/// einer aussen sichtbaren Aenderung (neuer Wert, neue oder stillgelegte
/// Variante, Name, Vorgaben, Stilllegen der Gruppe). Zwei Zustellungen koennen
/// sich ueberholen: den Stand nur uebernehmen, wenn `data.updatedAt` neuer ist
/// als der gespeicherte. Seit 10.5.
final class InventoryVariantGroupEvent extends InventoryWebhookEvent {
  const InventoryVariantGroupEvent({
    required super.id,
    required super.type,
    required super.createdAt,
    required super.accountId,
    required super.test,
    required this.data,
  });

  @override
  final VariantGroup data;
}

const String _parseName = 'parseInventoryWebhookEvent';

KasseneckValidationError _kaputt(String grund) => KasseneckValidationError(_parseName, grund, 'response');

/// Liest eine Zustellung als typisiertes Ereignis. Vorher die Signatur pruefen
/// ([verifyInventoryWebhookSignature]).
///
/// - [rawBody]: der Rumpf als `String` oder als Bytes (`List<int>`).
/// - Ein Ereignis, das diese Paketversion nicht kennt (eines einer spaeteren
///   Stufe), ergibt `null`: mit 2xx antworten und uebergehen.
/// - `reservation.expired|released|redeemed` tragen die Reservierung wie
///   `getReservation`, mit dem Status nach dem Vorgang (seit 10.4).
/// - `variant_group.created|updated` tragen die Gruppe wie `getVariantGroup`
///   (seit 10.5); den Stand nur uebernehmen, wenn `data.updatedAt` neuer ist.
/// - Ein Rumpf, der keine Huelle ist, oder eine Bruchzahl in einer Menge wirft
///   [KasseneckValidationError] (`kind: response`).
///
/// **Entdoppeln** auf `event.id`; **Stand statt Aenderung**: einen gespeicherten
/// Bestand nur ueberschreiben, wenn `data.sequence` groesser ist.
InventoryWebhookEvent? parseInventoryWebhookEvent(Object? rawBody) {
  final String text;
  if (rawBody is String) {
    text = rawBody;
  } else if (rawBody is List<int>) {
    // Wie TextDecoder im JS-Zwilling: kaputte Folgen werden ersetzt, das JSON
    // entscheidet dann.
    text = utf8.decode(rawBody, allowMalformed: true);
  } else {
    throw _kaputt('Rumpf ist weder Text noch Bytes');
  }
  final Object? roh;
  try {
    roh = jsonDecode(text);
  } on FormatException {
    throw _kaputt('Rumpf ist kein JSON');
  }
  final e = objekt(roh);
  if (e == null) throw _kaputt('Rumpf ist kein Ereignis (kein Objekt)');
  final id = e['id'];
  final type = e['type'];
  final accountId = e['accountId'];
  if (id is! String || id.isEmpty || type is! String || type.isEmpty) throw _kaputt('Ereignis ohne id oder type');
  final createdAt = ganzzahlVon(e['createdAt']);
  if (createdAt == null) throw _kaputt('Ereignis ohne createdAt');
  if (accountId is! String || accountId.isEmpty) throw _kaputt('Ereignis ohne accountId');
  if (!inventoryWebhookEvents.contains(type)) return null;
  final data = e['data'];
  if (objekt(data) == null) throw _kaputt('Ereignis ohne data');
  const ort = Ort(_parseName, 'data');
  // Nur ein ausdrueckliches `true` ist eine Probe; im Zweifel der Ernstfall.
  final test = e['test'] == true;
  return switch (type) {
    'stock.changed' => InventoryStockChangedEvent(
        id: id, createdAt: createdAt, accountId: accountId, test: test, data: bestandGeaendert(ort, data)),
    'stock.below_minimum' => InventoryStockBelowMinimumEvent(
        id: id, createdAt: createdAt, accountId: accountId, test: test, data: unterMindestbestand(ort, data)),
    'reservation.expired' || 'reservation.released' || 'reservation.redeemed' => InventoryReservationEvent(
        id: id, type: type, createdAt: createdAt, accountId: accountId, test: test, data: reservierung(ort, data)),
    'variant_group.created' || 'variant_group.updated' => InventoryVariantGroupEvent(
        id: id, type: type, createdAt: createdAt, accountId: accountId, test: test, data: variantengruppe(ort, data)),
    _ => InventoryArticleEvent(
        id: id, type: type, createdAt: createdAt, accountId: accountId, test: test, data: artikel(ort, data)),
  };
}
