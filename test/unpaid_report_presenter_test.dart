import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/services/unpaid_report_presenter.dart';

void main() {
  Map<String, Object?> row(String cycle, String classroom, String student,
      int due, int paid) => {
    'registration_number': student,
    'student': student,
    'cycle': cycle,
    'classroom': classroom,
    'family': 'Famille Test',
    'fee': 'Scolarité',
    'period_key': '2026-10',
    'amount_due': due,
    'amount_paid': paid,
    'balance': due - paid,
    'due_date': '2026-10-15T00:00:00',
  };

  test('regroupe les dettes par classe avec des sommes exactes', () {
    final displayed = UnpaidReportPresenter.rows([
      row('Collège', '6e A', 'Binta', 30000, 10000),
      row('Primaire', 'CP1 A', 'Alain', 15000, 5000),
      row('Collège', '6e A', 'Cécile', 20000, 0),
    ]);
    expect(displayed.last.first, 'TOTAL GÉNÉRAL');
    expect(displayed.last[7], contains('65'));
    expect(displayed.last[8], contains('15'));
    expect(displayed.last[9], contains('50'));
    expect(displayed.where((r) => r.first.startsWith('SOUS-TOTAL')), hasLength(2));
    expect(displayed.every((r) => r.length == UnpaidReportPresenter.headers.length), isTrue);
  });

  test('aucun total fabriqué en absence de dette', () {
    expect(UnpaidReportPresenter.rows([]), isEmpty);
  });

  test('les données sources restent inchangées', () {
    final original = [row('Primaire', 'CP1 A', 'David', 5000, 2500)];
    final before = List<Map<String, Object?>>.from(original.map((r) => {...r}));
    UnpaidReportPresenter.rows(original);
    expect(original, before);
  });
}
