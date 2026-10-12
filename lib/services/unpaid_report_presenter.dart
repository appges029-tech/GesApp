import '../core/utils/formatters.dart';

/// Génère un état lisible des impayés avec sous-totaux par cycle/classe.
/// Les calculs restent en entiers FCFA jusqu'à la présentation.
class UnpaidReportPresenter {
  const UnpaidReportPresenter._();

  static const headers = [
    'Matricule', 'Élève', 'Cycle', 'Classe', 'Famille',
    'Rubrique', 'Période', 'Dû', 'Payé', 'Solde', 'Échéance',
  ];

  static int _amount(Map<String, Object?> row, String column) =>
      (row[column] as num?)?.toInt() ?? 0;

  static List<List<String>> rows(List<Map<String, Object?>> source) {
    final ordered = [...source]..sort((a, b) {
      for (final key in ['cycle', 'classroom', 'student', 'period_key']) {
        final comparison = '${a[key] ?? ''}'.compareTo('${b[key] ?? ''}');
        if (comparison != 0) return comparison;
      }
      return 0;
    });
    final result = <List<String>>[];
    String? group;
    var sumDue = 0, sumPaid = 0, sumBalance = 0;
    var allDue = 0, allPaid = 0, allBalance = 0;

    void flush() {
      if (group == null) return;
      result.add([
        'SOUS-TOTAL $group', '', '', '', '', '', '',
        formatXaf(sumDue), formatXaf(sumPaid), formatXaf(sumBalance), '',
      ]);
      sumDue = 0; sumPaid = 0; sumBalance = 0;
    }

    for (final row in ordered) {
      final key = '${row['cycle'] ?? '—'} / ${row['classroom'] ?? '—'}';
      if (key != group) {
        flush();
        group = key;
      }
      final due = _amount(row, 'amount_due');
      final paid = _amount(row, 'amount_paid');
      final remaining = _amount(row, 'balance');
      sumDue += due; sumPaid += paid; sumBalance += remaining;
      allDue += due; allPaid += paid; allBalance += remaining;
      result.add([
        '${row['registration_number'] ?? ''}',
        '${row['student'] ?? ''}',
        '${row['cycle'] ?? ''}',
        '${row['classroom'] ?? ''}',
        '${row['family'] ?? ''}',
        '${row['fee'] ?? ''}',
        '${row['period_key'] ?? ''}',
        formatXaf(due), formatXaf(paid), formatXaf(remaining),
        row['due_date'] == null ? '' : '${row['due_date']}'.split('T').first,
      ]);
    }
    flush();
    if (ordered.isNotEmpty) {
      result.add([
        'TOTAL GÉNÉRAL', '', '', '', '', '', '',
        formatXaf(allDue), formatXaf(allPaid), formatXaf(allBalance), '',
      ]);
    }
    return result;
  }
}
