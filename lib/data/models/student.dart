class Student {
  const Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.classroomId,
    required this.classroomName,
    required this.cycleId,
    required this.cycleName,
    required this.status,
    this.registrationNumber,
    this.familyId,
    this.familyName,
    this.guardianName,
    this.guardianPhone,
    this.gender,
    this.birthDate,
    this.birthPlace,
    this.photoPath,
    this.nationality,
    this.address,
    this.originSchool,
    this.enrollmentDate,
    this.paymentStatus = 'no_due',
    this.hasPackage = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String classroomId;
  final String classroomName;
  final String cycleId;
  final String cycleName;
  final String status;
  final String? registrationNumber;
  final String? familyId;
  final String? familyName;
  final String? guardianName;
  final String? guardianPhone;
  final String? gender;
  final DateTime? birthDate;
  final String? birthPlace;
  final String? photoPath;
  final String? nationality;
  final String? address;
  final String? originSchool;
  final DateTime? enrollmentDate;
  final String paymentStatus;
  final bool hasPackage;

  String get fullName => '$lastName $firstName'.trim();

  factory Student.fromMap(Map<String, Object?> map) => Student(
        id: map['id'] as String,
        firstName: map['first_name'] as String,
        lastName: map['last_name'] as String,
        classroomId: map['classroom_id'] as String,
        classroomName: (map['classroom_name'] as String?) ?? '',
        cycleId: (map['cycle_id'] as String?) ?? '',
        cycleName: (map['cycle_name'] as String?) ?? '',
        status: map['status'] as String,
        registrationNumber: map['registration_number'] as String?,
        familyId: map['family_id'] as String?,
        familyName: map['family_name'] as String?,
        guardianName: map['guardian_name'] as String?,
        guardianPhone: map['guardian_phone'] as String?,
        gender: map['gender'] as String?,
        birthDate: map['birth_date'] == null ? null : DateTime.tryParse(map['birth_date'] as String),
        birthPlace: map['birth_place'] as String?,
        photoPath: map['photo_path'] as String?,
        nationality: map['nationality'] as String?,
        address: map['address'] as String?,
        originSchool: map['origin_school'] as String?,
        enrollmentDate: map['enrollment_date'] == null ? null : DateTime.tryParse(map['enrollment_date'] as String),
        paymentStatus: (map['payment_status'] as String?) ?? 'no_due',
        hasPackage: (map['has_package'] as int? ?? 0) == 1,
      );
}

class StudentFilter {
  const StudentFilter({
    this.query = '',
    this.cycleId,
    this.classroomId,
    this.familyId,
    this.status,
    this.paymentStatus,
  });
  final String query;
  final String? cycleId;
  final String? classroomId;
  final String? familyId;
  final String? status;
  final String? paymentStatus;

  bool get isActive => query.trim().isNotEmpty || cycleId != null || classroomId != null || familyId != null || status != null || paymentStatus != null;
}

class ClassroomOption {
  const ClassroomOption({
    required this.id,
    required this.cycleId,
    required this.name,
    required this.cycleName,
    this.capacity,
    this.currentCount = 0,
    this.active = true,
  });
  final String id;
  final String cycleId;
  final String name;
  final String cycleName;
  final int? capacity;
  final int currentCount;
  final bool active;

  String get occupancyLabel => capacity == null || capacity! <= 0 ? '$currentCount élève(s)' : '$currentCount/$capacity élève(s)';
  String get label => '$cycleName · $name · $occupancyLabel';
}

class StudentDocumentItem {
  const StudentDocumentItem({required this.id, required this.documentType, required this.filePath, required this.isRequired, required this.addedAt, this.verificationCode, this.verificationStatus = 'valid'});
  final String id;
  final String documentType;
  final String filePath;
  final bool isRequired;
  final DateTime addedAt;
  final String? verificationCode;
  final String verificationStatus;
  bool get isVerificationValid => verificationStatus == 'valid';
}

class StudentStatusHistoryItem {
  const StudentStatusHistoryItem({required this.newStatus, required this.changedAt, this.oldStatus, this.note});
  final String? oldStatus;
  final String newStatus;
  final DateTime changedAt;
  final String? note;
}

class StudentFinancialSnapshot {
  const StudentFinancialSnapshot({required this.expected, required this.paid, required this.outstanding, required this.overdue, required this.paymentCount});
  final int expected;
  final int paid;
  final int outstanding;
  final int overdue;
  final int paymentCount;
}

class StudentDueLine {
  const StudentDueLine({required this.feeName, required this.periodKey, required this.amountDue, required this.amountPaid, required this.status, this.dueDate});
  final String feeName;
  final String periodKey;
  final int amountDue;
  final int amountPaid;
  final String status;
  final DateTime? dueDate;
  int get balance => amountDue - amountPaid;
}

class StudentPaymentLine {
  const StudentPaymentLine({required this.receiptNumber, required this.amount, required this.method, required this.paidAt});
  final String receiptNumber;
  final int amount;
  final String method;
  final DateTime paidAt;
}


class StudentEnrollmentHistoryItem {
  const StudentEnrollmentHistoryItem({
    required this.schoolYearLabel,
    required this.classroomName,
    required this.cycleName,
    required this.enrollmentType,
    required this.status,
    required this.effectiveFrom,
    this.effectiveTo,
    this.observations,
  });
  final String schoolYearLabel;
  final String classroomName;
  final String cycleName;
  final String enrollmentType;
  final String status;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? observations;
}

class StudentDetailBundle {
  const StudentDetailBundle({required this.student, required this.documents, required this.history, required this.enrollments, required this.finance, required this.dues, required this.payments});
  final Student student;
  final List<StudentDocumentItem> documents;
  final List<StudentStatusHistoryItem> history;
  final List<StudentEnrollmentHistoryItem> enrollments;
  final StudentFinancialSnapshot finance;
  final List<StudentDueLine> dues;
  final List<StudentPaymentLine> payments;
}
