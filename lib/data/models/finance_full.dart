class FeeGridItem {
  const FeeGridItem({required this.id, required this.feeName, required this.targetName, required this.amount, required this.validFrom});
  final String id, feeName, targetName;
  final int amount;
  final DateTime validFrom;
}
class DueItem {
  const DueItem({required this.id, required this.studentId, required this.studentName, required this.feeName, required this.periodKey, required this.amountDue, required this.amountPaid, required this.status, this.dueDate});
  final String id, studentId, studentName, feeName, periodKey, status;
  final int amountDue, amountPaid;
  final DateTime? dueDate;
  int get balance => amountDue - amountPaid;
}
class PackageItem {
  const PackageItem({required this.id, required this.type, required this.beneficiary, required this.feeName, required this.amount, required this.validFrom, this.validTo, this.reason, required this.active});
  final String id, type, beneficiary, feeName; final int amount; final DateTime validFrom; final DateTime? validTo; final String? reason; final bool active;
}
class RecoverySummary { const RecoverySummary({required this.expected,required this.collected,required this.outstanding}); final int expected,collected,outstanding; double get rate=>expected==0?0:collected/expected; }

class DueGenerationPreview {
  const DueGenerationPreview({
    required this.schoolYearId,
    required this.schoolYearLabel,
    required this.periodKey,
    required this.periodicity,
    required this.studentCount,
    required this.candidateCount,
    required this.alreadyExistingCount,
    required this.totalAmount,
  });

  final String schoolYearId;
  final String schoolYearLabel;
  final String periodKey;
  final String periodicity;
  final int studentCount;
  final int candidateCount;
  final int alreadyExistingCount;
  final int totalAmount;
}

class BillingBatchItem {
  const BillingBatchItem({
    required this.id,
    required this.schoolYearLabel,
    required this.periodKey,
    required this.periodicity,
    required this.dueDate,
    required this.generatedCount,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String schoolYearLabel;
  final String periodKey;
  final String periodicity;
  final DateTime dueDate;
  final int generatedCount;
  final int totalAmount;
  final String status;
  final DateTime createdAt;

  bool get canCancel => status == 'posted';
}
