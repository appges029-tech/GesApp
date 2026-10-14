/// Automatic billing periods for the Congolese school year.
/// No operator-managed installments or billing-calendar configuration required.
class SchoolBillingPeriod {
  const SchoolBillingPeriod(this.key, this.start, this.end);
  final String key;
  final DateTime start;
  final DateTime end;
}

abstract final class SchoolBillingPeriods {
  static String _two(int v) => v.toString().padLeft(2, '0');

  static int startingYear(DateTime schoolYearStart, DateTime schoolYearEnd) =>
      schoolYearStart.month >= 8
          ? schoolYearStart.year
          : schoolYearEnd.year - 1;

  /// Recognizes common class names. The setting
  /// `billing_exam_class:<classroomId>` can explicitly override this result.
  static bool isExamClass(String label) {
    final text = label.toLowerCase()
        .replaceAll('é', 'e').replaceAll('è', 'e')
        .replaceAll('ê', 'e').replaceAll('è', 'e')
        .replaceAll('ième', 'ieme').trim();
    return text.contains('terminale') ||
        RegExp(r'(^|[^a-z0-9])cm\s*2([^a-z0-9]|$)').hasMatch(text) ||
        RegExp(r'(^|[^a-z0-9])3\s*(e|eme|ieme)([^a-z0-9]|$)').hasMatch(text) ||
        RegExp(r'(^|[^a-z0-9])t[abcd]([^a-z0-9]|$)').hasMatch(text);
  }

  static List<SchoolBillingPeriod> forYear({
    required DateTime schoolYearStart,
    required DateTime schoolYearEnd,
    required String periodicity,
    bool isExamClass = false,
  }) {
    final y = startingYear(schoolYearStart, schoolYearEnd);
    final starts = <SchoolBillingPeriod>[];
    if (periodicity == 'mensuelle') {
      for (var step = 0; step < (isExamClass ? 10 : 9); step++) {
        final begin = DateTime(y, 10 + step, 1);
        final end = DateTime(y, 11 + step, 0);
        starts.add(SchoolBillingPeriod('${begin.year}-${_two(begin.month)}', begin, end));
      }
    } else if (periodicity == 'trimestrielle') {
      for (var t = 0; t < 3; t++) {
        final begin = DateTime(y, 10 + 3 * t, 1);
        final end = DateTime(y, 13 + 3 * t, 0);
        starts.add(SchoolBillingPeriod('$y-T${t + 1}', begin, end));
      }
    } else if (periodicity == 'annuelle' || periodicity == 'unique') {
      starts.add(SchoolBillingPeriod('$y-$periodicity',
        DateTime(y, 10, 1), DateTime(y + 1, 6, 30)));
    } else {
      throw ArgumentError.value(periodicity, 'periodicity');
    }
    // Exam classes have the explicit July exception, even when the standard
    // school year closes on 30 June. Other periods obey the configured year.
    final effectiveEnd = isExamClass &&
            schoolYearEnd.year == y + 1 && schoolYearEnd.month == 6
        ? DateTime(y + 1, 7, 31) : schoolYearEnd;
    return starts.where((period) =>
        !period.end.isBefore(schoolYearStart) &&
        !period.start.isAfter(effectiveEnd)).toList(growable: false);
  }
}
