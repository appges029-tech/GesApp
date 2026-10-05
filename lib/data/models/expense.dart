class ExpenseItem {
  const ExpenseItem({
    required this.id,
    required this.categoryName,
    required this.amount,
    required this.spentAt,
    this.description,
    this.expenseNumber,
    this.beneficiary,
    this.paymentMethod,
    this.cashAccountId,
    this.externalReference,
    this.proofPath,
    this.status = 'posted',
    this.approvalStatus = 'approved',
    this.submittedBy,
    this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.approvalNote,
  });

  final String id;
  final String categoryName;
  final String status;
  final String approvalStatus;
  final int amount;
  final DateTime spentAt;
  final String? description;
  final String? expenseNumber;
  final String? beneficiary;
  final String? paymentMethod;
  final String? cashAccountId;
  final String? externalReference;
  final String? proofPath;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? approvalNote;

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved' && status == 'posted';
  bool get isRejected => approvalStatus == 'rejected' || status == 'rejected';
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});
  final String id;
  final String name;
}
