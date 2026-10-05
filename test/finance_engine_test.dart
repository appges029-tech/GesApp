import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/services/finance_engine.dart';

void main() {
  const engine = FinanceEngine();

  test('calcule les statuts de paiement', () {
    expect(engine.statusFor(amountDue: 10000, amountPaid: 0), PaymentStatus.unpaid);
    expect(engine.statusFor(amountDue: 10000, amountPaid: 5000), PaymentStatus.partial);
    expect(engine.statusFor(amountDue: 10000, amountPaid: 10000), PaymentStatus.paid);
  });

  test('alloue un paiement aux anciennes échéances en premier', () {
    expect(engine.allocateOldestFirst(paymentAmount: 25000, remainingBalances: [10000, 10000, 10000]), [10000, 10000, 5000]);
  });
}
