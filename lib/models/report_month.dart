import 'package:kasseneck_api/enums/keck_month.dart';

class ReportMonth {
  final KeckMonth month;
  final int year;

  const ReportMonth(this.month, this.year);

  factory ReportMonth.fromDateTime(DateTime dateTime) {
    return ReportMonth(KeckMonth.values[dateTime.month - 1], dateTime.year);
  }

  factory ReportMonth.now() {
    return ReportMonth.fromDateTime(DateTime.now());
  }

  ReportMonth previousMonth() {
    if (month == KeckMonth.january) {
      return ReportMonth(KeckMonth.december, year - 1);
    } else {
      return ReportMonth(KeckMonth.values[month.index - 1], year);
    }
  }

  ReportMonth nextMonth() {
    if (month == KeckMonth.december) {
      return ReportMonth(KeckMonth.january, year + 1);
    } else {
      return ReportMonth(KeckMonth.values[month.index + 1], year);
    }
  }

  DateTime toDateTime() {
    return DateTime(year, month.id);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportMonth &&
      other.month == month &&
      other.year == year;
  }

  @override
  int get hashCode => month.hashCode ^ year.hashCode;

  @override
  String toString() {
    return '${month.name}_$year';
  }
}