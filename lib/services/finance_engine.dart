class FinanceEngine {
  const FinanceEngine();

  PaymentStatus statusFor({required int amountDue, required int amountPaid}) {
    if (amountDue <= 0 || amountPaid >= amountDue) return PaymentStatus.paid;
    if (amountPaid > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }

  int remaining({required int amountDue, required int amountPaid}) {
    final value = amountDue - amountPaid;
    return value < 0 ? 0 : value;
  }

  double recoveryRate({required int expected, required int collected}) {
    if (expected <= 0) return 0;
    return (collected / expected).clamp(0, 1);
  }

  List<int> allocateOldestFirst({
    required int paymentAmount,
    required List<int> remainingBalances,
  }) {
    var left = paymentAmount;
    final allocations = <int>[];
    for (final balance in remainingBalances) {
      if (left <= 0) {
        allocations.add(0);
        continue;
      }
      final allocated = left >= balance ? balance : left;
      allocations.add(allocated);
      left -= allocated;
    }
    return allocations;
  }
}

enum PaymentStatus { unpaid, partial, paid }
