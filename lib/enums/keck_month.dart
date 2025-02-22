enum KeckMonth {
  january(1, 'Januar'),
  february(2, 'Februar'),
  march(3, 'März'),
  april(4, 'April'),
  may(5, 'Mai'),
  june(6, 'Juni'),
  july(7, 'Juli'),
  august(8, 'August'),
  september(9, 'September'),
  october(10, 'Oktober'),
  november(11, 'November'),
  december(12, 'Dezember');

  final String germanName;
  final int id;

  const KeckMonth(this.id, this.germanName);
}