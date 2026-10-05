class DashboardSummary {
  const DashboardSummary({
    required this.studentCount,
    required this.expectedDue,
    required this.collectedDue,
    required this.overdueBalance,
    required this.futureBalance,
    required this.monthRevenue,
    required this.monthExpenses,
    required this.unreadAlerts,
  });

  final int studentCount;
  final int expectedDue;
  final int collectedDue;
  final int overdueBalance;
  final int futureBalance;
  final int monthRevenue;
  final int monthExpenses;
  final int unreadAlerts;

  int get netBalance => monthRevenue - monthExpenses;
  double get recoveryRate => expectedDue <= 0 ? 0 : (collectedDue / expectedDue).clamp(0, 1);
}
