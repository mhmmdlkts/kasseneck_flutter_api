/// Art eines Ereignisses im Zahlweg.
enum HpsEventKind {
  /// Ein Request geht hinaus.
  requestStarted,

  /// Ein Request kam mit einer Antwort zurueck.
  requestSucceeded,

  /// Ein Request scheiterte am Transport oder an einem HTTP-Status.
  requestFailed,

  /// Der Ausgang ist offen, die Klaerung laeuft.
  resolving,

  /// Der Ausgang steht fest.
  resolved,
}

/// Ein Ereignis im Zahlweg. Bewusst schlank und ohne Kartendaten -- was hier
/// hineingegeben wird, landet im Protokoll der App.
class HpsEvent {
  const HpsEvent(this.kind, this.message, {this.transactionId, this.error});

  final HpsEventKind kind;
  final String message;
  final String? transactionId;
  final Object? error;

  @override
  String toString() =>
      'HpsEvent(${kind.name}, $message, tx=$transactionId, error=$error)';
}

/// Empfaenger der Ereignisse. Die App legt ihn typischerweise auf ihr
/// Absturzprotokoll.
typedef HpsObserver = void Function(HpsEvent event);
