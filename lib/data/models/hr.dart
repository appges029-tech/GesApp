class HrDepartment {
  const HrDepartment({required this.id, required this.name, this.description, required this.active});
  final String id;
  final String name;
  final String? description;
  final bool active;
}

class HrPosition {
  const HrPosition({required this.id, required this.name, this.departmentId, this.departmentName, this.description, required this.active});
  final String id;
  final String name;
  final String? departmentId;
  final String? departmentName;
  final String? description;
  final bool active;
}

class EmployeeItem {
  const EmployeeItem({
    required this.id,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.hireDate,
    this.gender,
    this.phone,
    this.email,
    this.address,
    this.birthDate,
    this.birthPlace,
    this.photoPath,
    this.idNumber,
    this.socialSecurityNumber,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.positionName,
    this.departmentName,
  });
  final String id, employeeNumber, firstName, lastName, status;
  final DateTime hireDate;
  final String? gender, phone, email, address, birthPlace, photoPath, idNumber, socialSecurityNumber, emergencyContactName, emergencyContactPhone, positionName, departmentName;
  final DateTime? birthDate;
  String get fullName => '$lastName $firstName'.trim();
  bool get isActive => status == 'active';
}

class EmployeeContract {
  const EmployeeContract({required this.id, required this.employeeId, required this.contractType, required this.startDate, this.endDate, required this.baseSalary, required this.status, this.positionId, this.positionName, this.documentPath, this.notes});
  final String id, employeeId, contractType, status;
  final DateTime startDate;
  final DateTime? endDate;
  final int baseSalary;
  final String? positionId, positionName, documentPath, notes;
}

class EmployeeAssignment {
  const EmployeeAssignment({required this.id, required this.employeeId, required this.positionId, required this.positionName, this.departmentName, this.schoolYearId, required this.startDate, this.endDate, this.notes});
  final String id, employeeId, positionId, positionName;
  final String? departmentName, schoolYearId, notes;
  final DateTime startDate;
  final DateTime? endDate;
}

class AttendanceItem {
  const AttendanceItem({required this.id, required this.employeeId, required this.employeeName, required this.date, required this.status, this.arrivalTime, this.departureTime, this.lateMinutes = 0, this.note});
  final String id, employeeId, employeeName, status;
  final DateTime date;
  final String? arrivalTime, departureTime, note;
  final int lateMinutes;
}

class LeaveRequestItem {
  const LeaveRequestItem({required this.id, required this.employeeId, required this.employeeName, required this.leaveTypeName, required this.startDate, required this.endDate, required this.days, required this.status, this.reason, this.note});
  final String id, employeeId, employeeName, leaveTypeName, status;
  final DateTime startDate, endDate;
  final int days;
  final String? reason, note;
}

class PayrollPeriodItem {
  const PayrollPeriodItem({required this.id, required this.label, required this.startDate, required this.endDate, required this.status, required this.totalGross, required this.totalDeductions, required this.totalNet, required this.entryCount});
  final String id, label, status;
  final DateTime startDate, endDate;
  final int totalGross, totalDeductions, totalNet, entryCount;
}

class PayrollEntryItem {
  const PayrollEntryItem({required this.id, required this.periodId, required this.employeeId, required this.employeeName, required this.baseSalary, required this.grossSalary, required this.totalDeductions, required this.netSalary, required this.status, this.paymentMethod, this.cashAccountId, this.paymentReference, this.paidAt, this.expenseId});
  final String id, periodId, employeeId, employeeName, status;
  final int baseSalary, grossSalary, totalDeductions, netSalary;
  final String? paymentMethod, cashAccountId, paymentReference, expenseId;
  final DateTime? paidAt;
}

class SalaryAdvanceItem {
  const SalaryAdvanceItem({required this.id, required this.employeeId, required this.employeeName, required this.amount, required this.balance, required this.grantedAt, required this.status, this.note});
  final String id, employeeId, employeeName, status;
  final int amount, balance;
  final DateTime grantedAt;
  final String? note;
}

class HrSummary {
  const HrSummary({required this.activeEmployees, required this.absentToday, required this.onLeaveToday, required this.expiringContracts, required this.incompleteFiles, required this.pendingPayroll, required this.monthlyPayroll});
  final int activeEmployees, absentToday, onLeaveToday, expiringContracts, incompleteFiles, pendingPayroll, monthlyPayroll;
}
