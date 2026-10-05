class FeeCategoryItem {
  const FeeCategoryItem({required this.id, required this.name, required this.periodicity});
  final String id;
  final String name;
  final String periodicity;
}

class PaymentItem {
  const PaymentItem({
    required this.id,
    required this.receiptNumber,
    required this.studentName,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.note,
    this.status = 'posted',
    this.cancelReason,
    this.isFamilyPayment = false,
    this.refundedAmount = 0,
  });
  final String id;
  final String receiptNumber;
  final String studentName;
  final int amount;
  final String method;
  final DateTime paidAt;
  final String? note;
  final String status;
  final String? cancelReason;
  final bool isFamilyPayment;
  final int refundedAmount;
  int get refundableAmount { final value = amount - refundedAmount; return value < 0 ? 0 : (value > amount ? amount : value); }

  bool get isCancelled => status == 'annule';
}

class ReceiptVerificationLine {
  const ReceiptVerificationLine({required this.label, required this.amount});
  final String label;
  final int amount;
}

class ReceiptVerificationResult {
  const ReceiptVerificationResult({
    required this.paymentId,
    required this.receiptNumber,
    required this.beneficiaryName,
    required this.amount,
    required this.refundedAmount,
    required this.method,
    required this.paidAt,
    required this.status,
    required this.schoolYearLabel,
    required this.lines,
    this.cancelReason,
    this.transactionReference,
    this.payerPhone,
  });

  final String paymentId;
  final String receiptNumber;
  final String beneficiaryName;
  final int amount;
  final int refundedAmount;
  final String method;
  final DateTime paidAt;
  final String status;
  final String? cancelReason;
  final String? transactionReference;
  final String? payerPhone;
  final String? schoolYearLabel;
  final List<ReceiptVerificationLine> lines;

  bool get isCancelled => status == 'annule';
  int get netAmount => amount - refundedAmount;
}
