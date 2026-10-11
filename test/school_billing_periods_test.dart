import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/services/school_billing_periods.dart';

void main() {
  final start = DateTime(2026, 9, 1);
  final end = DateTime(2027, 7, 31);

  test('ordinary classes have nine months from October through June', () {
    final periods = SchoolBillingPeriods.forYear(
      schoolYearStart: start, schoolYearEnd: end,
      periodicity: 'mensuelle',
    );
    expect(periods.length, 9);
    expect(periods.first.key, '2026-10');
    expect(periods.last.key, '2027-06');
    expect(periods.any((p) => p.key == '2026-09'), false);
    expect(periods.any((p) => p.key == '2027-07'), false);
  });

  test('exam classes get July on top of the nine standard months', () {
    for (final name in ['CM2', '3e', '3ème', 'Terminale A', 'TA', 'TD']) {
      expect(SchoolBillingPeriods.isExamClass(name), true, reason: name);
    }
    for (final name in ['CP1', 'CE2', '4e', '2nde', 'T1']) {
      expect(SchoolBillingPeriods.isExamClass(name), false, reason: name);
    }
    final periods = SchoolBillingPeriods.forYear(
      schoolYearStart: start, schoolYearEnd: end,
      periodicity: 'mensuelle', isExamClass: true,
    );
    expect(periods.length, 10);
    expect(periods.last.key, '2027-07');
  });

  test('quarterly means exactly three obligations', () {
    final periods = SchoolBillingPeriods.forYear(
      schoolYearStart: start, schoolYearEnd: end,
      periodicity: 'trimestrielle',
    );
    expect(periods.map((p) => p.key).toList(),
        ['2026-T1', '2026-T2', '2026-T3']);
    expect(periods.first.start, DateTime(2026, 10, 1));
    expect(periods.last.end, DateTime(2027, 6, 30));
  });

  test('single and annual fees are each billed once', () {
    for (final periodicity in ['unique', 'annuelle']) {
      final periods = SchoolBillingPeriods.forYear(
        schoolYearStart: start, schoolYearEnd: end,
        periodicity: periodicity,
      );
      expect(periods, hasLength(1));
    }
  });

  test('July extends a June-ending year only for exam classes', () {
    final periods = SchoolBillingPeriods.forYear(
      schoolYearStart: start,
      schoolYearEnd: DateTime(2027, 6, 30),
      periodicity: 'mensuelle',
      isExamClass: true,
    );
    expect(periods, hasLength(10));
    expect(periods.last.key, '2027-07');
  });
}
