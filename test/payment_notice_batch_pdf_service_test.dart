import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/services/payment_notice_batch_pdf_service.dart';

void main() {
  test('regroupe seulement les échéances ayant un solde à payer', () {
    final notices = groupDuesByStudent([
      {
        'student_id': 'student-1',
        'student': 'Élève Test',
        'registration_number': 'EL-2026-00001',
        'cycle': 'Primaire',
        'classroom': 'CM1',
        'family': 'Famille Test',
        'guardian_name': 'Parent Test',
        'guardian_phone': '060000000',
        'fee': 'Scolarité',
        'period_key': '2026-09',
        'amount_due': 25000,
        'amount_paid': 5000,
        'due_date': '2026-09-25',
      },
      {
        'student_id': 'student-1',
        'student': 'Élève Test',
        'registration_number': 'EL-2026-00001',
        'cycle': 'Primaire',
        'classroom': 'CM1',
        'family': 'Famille Test',
        'guardian_name': 'Parent Test',
        'guardian_phone': '060000000',
        'fee': 'Transport',
        'period_key': '2026-09',
        'amount_due': 10000,
        'amount_paid': 10000,
        'due_date': '2026-09-20',
      },
    ]);

    expect(notices, hasLength(1));
    expect(notices.single.lines, hasLength(1));
    expect(notices.single.totalBalance, 20000);
    expect(notices.single.paymentDeadline, '2026-09-25');
  });
}
