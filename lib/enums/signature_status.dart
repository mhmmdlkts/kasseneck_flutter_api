// Die Namen muessen exakt den Status-Werten der FinanzOnline-Antwort
// (rkdbMessage.status) entsprechen — das Parsing matcht ueber element.name.
// ignore_for_file: constant_identifier_names
enum SignatureStatus {
  IN_BETRIEB,
  AUSFALL,
  NOT_REGISTERED,
}
