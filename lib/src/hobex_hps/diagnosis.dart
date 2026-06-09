/// Result of `GET /api/terminals/{tid}/diagnosis` — a health snapshot of the
/// terminal and its connection to the hobex host.
class Diagnosis {
  const Diagnosis({
    required this.raw,
    this.deviceStatus,
    this.responseCode,
    this.responseText,
    this.hps,
    this.firmware,
    this.hardware,
    this.sdk,
    this.softwareName,
    this.packageVersion,
    this.emv,
    this.serialNumber,
    this.host,
    this.port,
    this.media,
    this.ip,
    this.gateway,
    this.mac,
    this.tid,
  });

  /// e.g. `IN_OPERATION`.
  final String? deviceStatus;

  /// `"0"` indicates a successful/authorized diagnosis.
  final String? responseCode;

  /// e.g. `Authorized`.
  final String? responseText;

  /// HPS software version, e.g. `1.8.4`.
  final String? hps;

  final String? firmware;
  final String? hardware;
  final String? sdk;

  /// e.g. `HPS_AT_DE`.
  final String? softwareName;
  final String? packageVersion;
  final String? emv;

  /// Terminal serial number.
  final String? serialNumber;

  /// Authorization host URL — contains `tecstest` for the test environment.
  final String? host;
  final String? port;

  /// Connection media, e.g. `WIFI`.
  final String? media;

  /// Primary IP address.
  final String? ip;
  final String? gateway;
  final String? mac;
  final String? tid;

  /// The raw decoded JSON, for fields not modelled explicitly.
  final Map<String, dynamic> raw;

  /// `true` when [deviceStatus] is `IN_OPERATION`.
  bool get isInOperation => deviceStatus == 'IN_OPERATION';

  /// `true` when the diagnosis reported success (`responseCode == "0"`).
  bool get isAuthorized => responseCode == '0';

  /// Heuristic: `true` when the terminal points at the hobex **test** host.
  bool get isTestEnvironment => (host ?? '').toLowerCase().contains('test');

  factory Diagnosis.fromJson(Map<String, dynamic> json) {
    return Diagnosis(
      raw: json,
      deviceStatus: json['deviceStatus'] as String?,
      responseCode: json['responseCode']?.toString(),
      responseText: json['responseText'] as String?,
      hps: json['hps'] as String?,
      firmware: json['fw'] as String?,
      hardware: json['hw'] as String?,
      sdk: json['sdk'] as String?,
      softwareName: json['swName'] as String?,
      packageVersion: json['pkg'] as String?,
      emv: json['emv'] as String?,
      serialNumber: json['sn'] as String?,
      host: json['host'] as String?,
      port: json['port']?.toString(),
      media: json['media'] as String?,
      ip: json['ip1'] as String?,
      gateway: json['gw'] as String?,
      mac: json['mac'] as String?,
      tid: json['tid'] as String?,
    );
  }

  @override
  String toString() =>
      'Diagnosis(deviceStatus=$deviceStatus, hps=$hps, host=$host, '
      'test=$isTestEnvironment, tid=$tid, responseText=$responseText)';
}
