import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/features/finance/payment_amount_policy.dart';

void main() {
  test('suggest full amount only if cashier has not edited the field', () {
    expect(suggestedPaymentAmount(current: '', selectedRemaining: 30000,
      editedByCashier: false), '30000');
    expect(suggestedPaymentAmount(current: '20000', selectedRemaining: 15000,
      editedByCashier: true), '20000');
    expect(suggestedPaymentAmount(current: '20000', selectedRemaining: 45000,
      editedByCashier: true), '20000');
    expect(suggestedPaymentAmount(current: '', selectedRemaining: 0,
      editedByCashier: false), '');
  });
}
