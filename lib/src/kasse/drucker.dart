/// Netzwerk-Bondrucker über Epson „Server Direct Print", Zwilling von
/// `pos/drucker.ts` im JS-Paket.
///
/// Das Backend führt je Konto Drucker mit einer geheimen Abhol-Adresse; die
/// Kasse legt Druckjobs aus einem Zeilenmodell ([BelegLayout]) an, der
/// Drucker holt sie selbst ab (alle paar Sekunden) und meldet das Ergebnis.
/// Das ePOS-XML baut das Backend aus dem Zeichenraster.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../models/beleg_layout.dart';
import '../../models/print_paper.dart';
import '../aufrufe.dart';
import '../register/fehler.dart';
import '../register/transport.dart';

/// Ein Netzwerk-Drucker des Kontos (`listMyPrinters`).
class NetworkPrinter {
  const NetworkPrinter({
    required this.id,
    required this.name,
    required this.kind,
    required this.paperSize,
    required this.active,
    this.createdAt,
    this.lastSeenAt,
    this.lastResult,
    this.printerSerial,
    this.sdpUrl,
  });

  final String id;
  final String name;

  /// Art des Druckers; heute nur `epson-sdp`.
  final String kind;

  /// `mm58` oder `mm80`.
  final String paperSize;
  final bool active;

  /// Millisekunden seit 1970.
  final int? createdAt;

  /// Letzter Abruf des Druckers; `null` = noch nie verbunden.
  final int? lastSeenAt;
  final PrintResult? lastResult;

  /// Kennung, die der Drucker selbst schickt (Feld ID im Drucker-Menü).
  final String? printerSerial;

  /// Abhol-Adresse für das Drucker-Menü, nur für den Chef bzw. das Konto.
  final String? sdpUrl;

  factory NetworkPrinter.aus(Map<String, dynamic> d) {
    final e = d['lastResult'];
    return NetworkPrinter(
      id: d['id']?.toString() ?? '',
      name: d['name']?.toString() ?? '',
      kind: d['kind']?.toString() ?? 'epson-sdp',
      paperSize: d['paperSize'] == 'mm58' ? 'mm58' : 'mm80',
      active: d['active'] != false,
      createdAt: _zahl(d['createdAt']),
      lastSeenAt: _zahl(d['lastSeenAt']),
      lastResult: e is Map ? PrintResult._aus(e) : null,
      printerSerial: _text(d['printerSerial']),
      sdpUrl: _text(d['sdpUrl']),
    );
  }
}

/// Ergebnis eines Drucks, wie der Drucker es meldet.
class PrintResult {
  const PrintResult({required this.success, this.code, this.status, this.at});

  final bool success;
  final String? code;
  final String? status;

  /// Millisekunden seit 1970.
  final int? at;

  static PrintResult _aus(Map<dynamic, dynamic> e) => PrintResult(
        success: e['success'] == true,
        code: _text(e['code']),
        status: _text(e['status']),
        at: _zahl(e['at']),
      );
}

/// Stände eines Druckjobs (Katalog `DRUCKJOB`).
const List<String> printJobStatuses = ['pending', 'sent', 'printed', 'failed', 'expired'];

/// Stand, wenn der Server einen nennt, den dieses Paket nicht kennt (oder
/// keinen). Er beendet die Abfrage, gilt aber nie als gedruckt.
const String printJobStatusUnknown = 'unknown';

/// Bekannte Werte für `source` (Katalog `DRUCK_QUELLE`): die Kasse oder das
/// Panel. Der Server nimmt Freitext bis 40 Zeichen an und übersetzt nur diese
/// beiden.
const List<String> printJobSources = ['pos', 'panel'];

/// Endet die Abfrage bei diesem Stand? `printed`, `failed`, `expired`, `unknown`.
bool isPrintJobFinished(String status) =>
    status == 'printed' || status == 'failed' || status == 'expired' || status == printJobStatusUnknown;

class PrintJob {
  const PrintJob({required this.jobId, required this.status, this.createdAt, this.sentAt, this.result});

  final String jobId;

  /// Einer aus [printJobStatuses] oder [printJobStatusUnknown].
  final String status;
  final int? createdAt;
  final int? sentAt;
  final PrintResult? result;
}

String _status(Object? v) => v is String && printJobStatuses.contains(v) ? v : printJobStatusUnknown;

String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _zahl(Object? v) => v is num && v.isFinite ? v.toInt() : null;

/// Die Rasterzeilen eines Logos als Base64 (1 Bit je Punkt, links das höchste
/// Bit, Zeilen auf ganze Bytes aufgefüllt), Zwilling von `rasterRowsBase64`.
String rasterZeilenBase64(DruckLogo logo) {
  final r = logo.raster;
  final jeZeile = (r.breite + 7) >> 3;
  final bytes = Uint8List(jeZeile * r.hoehe);
  for (var y = 0; y < r.hoehe; y++) {
    for (var x = 0; x < r.breite; x++) {
      if (r.punkte[y * r.breite + x] != 1) continue;
      bytes[y * jeZeile + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return base64Encode(bytes);
}

/// Drucker und Druckjobs über die laufende Kassen-Sitzung.
class KasseDruckerClient {
  const KasseDruckerClient(this.transport);

  final RegisterTransport transport;

  /// Die Netzwerk-Drucker des Kontos.
  Future<List<NetworkPrinter>> drucker() async {
    const name = Aufrufe.listMyPrinters;
    final daten = await transport.rufen(name);
    final liste = daten['printers'];
    if (liste is! List) return const [];
    return [
      for (final e in liste) NetworkPrinter.aus(e is Map ? Map<String, dynamic>.from(e) : const {}),
    ];
  }

  /// Einen Druckjob anlegen. [logo] ist das fertige Rasterbild
  /// (`ladeDruckLogo`), der Server dekodiert keine Bilder. [markeZeigen] druckt
  /// das Kasseneck-Logo am Ende (am Draht `brand`). [quelle] ist Freitext,
  /// bekannt sind [printJobSources].
  Future<PrintJob> druckjobAnlegen({
    required String printerId,
    required BelegLayout layout,
    String? receiptId,
    String? titel,
    String? quelle,
    DruckLogo? logo,
    bool markeZeigen = false,
  }) async {
    const name = Aufrufe.createPrintJob;
    if (printerId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'printerId fehlt', 'request');
    }
    final daten = await transport.rufen(name, params: {
      'printerId': printerId,
      'layout': layout.toJson(),
      if (receiptId != null && receiptId.isNotEmpty) 'receiptId': receiptId,
      if (titel != null && titel.isNotEmpty) 'title': titel,
      if (quelle != null && quelle.isNotEmpty) 'source': quelle,
      if (logo != null)
        'logo': {
          'scale': logo.stufe.kuerzel,
          'pxWidth': logo.pxBreite,
          'pxHeight': logo.pxHoehe,
          'width': logo.raster.breite,
          'height': logo.raster.hoehe,
          'rows': rasterZeilenBase64(logo),
        },
      if (markeZeigen) 'brand': true,
    });
    return PrintJob(jobId: daten['jobId']?.toString() ?? '', status: _status(daten['status']));
  }

  /// Stand eines Druckjobs. Der Aufrufer fragt, bis [isPrintJobFinished] wahr
  /// ist, und begrenzt die Abfrage trotzdem selbst: ein Drucker, der nie
  /// abholt, bleibt `pending`.
  Future<PrintJob> druckjobHolen({required String printerId, required String jobId}) async {
    const name = Aufrufe.getPrintJob;
    if (printerId.trim().isEmpty || jobId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'printerId und jobId sind Pflicht', 'request');
    }
    final d = await transport.rufen(name, params: {'printerId': printerId, 'jobId': jobId});
    final e = d['result'];
    return PrintJob(
      jobId: d['jobId']?.toString() ?? jobId,
      status: _status(d['status']),
      createdAt: _zahl(d['createdAt']),
      sentAt: _zahl(d['sentAt']),
      result: e is Map ? PrintResult._aus(e) : null,
    );
  }
}
