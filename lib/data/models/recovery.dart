class RecoveryCaseItem {
  const RecoveryCaseItem({
    required this.dueId,
    required this.studentId,
    required this.studentName,
    required this.classroomName,
    required this.feeName,
    required this.periodKey,
    required this.balance,
    required this.dueDate,
    required this.daysLate,
    this.familyName,
    this.guardianName,
    this.guardianPhone,
    this.lastActionAt,
    this.nextFollowUpAt,
    this.promiseAmount,
    this.promiseDate,
  });

  final String dueId;
  final String studentId;
  final String studentName;
  final String classroomName;
  final String feeName;
  final String periodKey;
  final int balance;
  final DateTime dueDate;
  final int daysLate;
  final String? familyName;
  final String? guardianName;
  final String? guardianPhone;
  final DateTime? lastActionAt;
  final DateTime? nextFollowUpAt;
  final int? promiseAmount;
  final DateTime? promiseDate;
}

class RecoveryActionItem {
  const RecoveryActionItem({
    required this.id,
    required this.dueId,
    required this.actionType,
    required this.createdAt,
    this.channel,
    this.contactName,
    this.outcome,
    this.promiseAmount,
    this.promiseDate,
    this.nextFollowUpAt,
    this.note,
    this.status = 'open',
  });

  final String id;
  final String dueId;
  final String actionType;
  final String? channel;
  final String? contactName;
  final String? outcome;
  final int? promiseAmount;
  final DateTime? promiseDate;
  final DateTime? nextFollowUpAt;
  final String? note;
  final String status;
  final DateTime createdAt;
}
