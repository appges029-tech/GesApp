import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../services/report_pdf_service.dart';
import '../../services/document_number_service.dart';
import '../../services/document_identity.dart';
import '../../services/excel_export_service.dart';

class HrReportsScreen extends ConsumerWidget {
  const HrReportsScreen({super.key});

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    if (rows.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter.')));
      }
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Exporter en PDF'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: const Text('Exporter en Excel'),
              onTap: () => Navigator.pop(sheetContext, 'excel'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'pdf') {
      final establishment = await ref.read(establishmentProvider.future);
      final identity = await DocumentIdentity.fromEstablishment(establishment);
      final registry = DocumentNumberService();
      final reference = await registry.getOrCreate(type: 'RHR', entityId: '$title:${DateTime.now().microsecondsSinceEpoch}');
      final bytes = await ReportPdfService().table(title: title, headers: headers, rows: rows, identity: identity, reference: reference);
      await registry.recordFingerprint(reference: reference, bytes: bytes);
      if (!context.mounted) return;
      await downloadBytes(bytes: bytes, fileName: '${fileName.replaceAll('.pdf', '')}_$reference.pdf', mimeType: 'application/pdf');
    } else if (choice == 'excel') {
      final path = await ExcelExportService().export(fileName: title, headers: headers, rows: rows);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Excel : $path'), duration: const Duration(seconds: 5)),
      );
    }
  }

  Future<void> _staff(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(hrRepositoryProvider).employees(
          status: null,
          limit: 5000,
        );
    if (!context.mounted) return;
    await _export(
      context,
      ref,
      title: 'Liste du personnel',
      fileName: 'RH_Personnel.pdf',
      headers: const [
        'Matricule',
        'Nom',
        'Poste',
        'Service',
        'Statut',
        'Téléphone',
      ],
      rows: rows
          .map(
            (employee) => [
              employee.employeeNumber,
              employee.fullName,
              employee.positionName ?? '',
              employee.departmentName ?? '',
              employee.status,
              employee.phone ?? '',
            ],
          )
          .toList(),
    );
  }

  Future<void> _department(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(hrRepositoryProvider).hrReportByDepartment();
    if (!context.mounted) return;
    await _export(
      context,
      ref,
      title: 'Effectifs & masse salariale par service',
      fileName: 'RH_Services.pdf',
      headers: const ['Service', 'Effectif', 'Salaires de base'],
      rows: rows
          .map(
            (row) => [
              row['label'].toString(),
              row['employees'].toString(),
              formatXaf((row['base_payroll'] as num).toInt()),
            ],
          )
          .toList(),
    );
  }

  Future<void> _contracts(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(hrRepositoryProvider).expiringContracts(days: 90);
    if (!context.mounted) return;
    await _export(
      context,
      ref,
      title: 'Contrats expirant dans 90 jours',
      fileName: 'RH_Contrats_90j.pdf',
      headers: const ['Matricule', 'Employé', 'Contrat', 'Échéance', 'Salaire'],
      rows: rows
          .map(
            (row) => [
              row['employee_number'].toString(),
              row['employee_name'].toString(),
              row['contract_type'].toString(),
              row['end_date'].toString().split('T').first,
              formatXaf((row['base_salary'] as num).toInt()),
            ],
          )
          .toList(),
    );
  }

  Future<DateTimeRange?> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Période du rapport',
      saveText: 'Générer',
    );
  }

  Future<void> _attendance(BuildContext context, WidgetRef ref) async {
    final range = await _pickRange(context);
    if (range == null) return;
    if (!context.mounted) return;
    final rows = await ref.read(hrRepositoryProvider).attendanceReport(
          from: range.start,
          to: range.end,
        );
    if (!context.mounted) return;
    final formatter = DateFormat('dd/MM/yyyy');
    await _export(
      context,
      ref,
      title:
          'Présences du ${formatter.format(range.start)} au ${formatter.format(range.end)}',
      fileName: 'RH_Presences.pdf',
      headers: const [
        'Matricule',
        'Employé',
        'Présent',
        'Absent',
        'Retard',
        'Congé',
      ],
      rows: rows
          .map(
            (row) => [
              row['employee_number'].toString(),
              row['employee_name'].toString(),
              row['present_days'].toString(),
              row['absent_days'].toString(),
              row['late_days'].toString(),
              row['leave_days'].toString(),
            ],
          )
          .toList(),
    );
  }

  Future<void> _payroll(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(hrRepositoryProvider).payrollReport();
    if (!context.mounted) return;
    await _export(
      context,
      ref,
      title: 'Historique de paie',
      fileName: 'RH_Historique_paie.pdf',
      headers: const ['Période', 'Statut', 'Employés', 'Brut', 'Retenues', 'Net'],
      rows: rows
          .map(
            (row) => [
              row['label'].toString(),
              row['status'].toString(),
              row['employees'].toString(),
              formatXaf((row['gross'] as num).toInt()),
              formatXaf((row['deductions'] as num).toInt()),
              formatXaf((row['net'] as num).toInt()),
            ],
          )
          .toList(),
    );
  }

  Future<void> _leaves(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(hrRepositoryProvider).leaveReport();
    if (!context.mounted) return;
    await _export(
      context,
      ref,
      title: 'Historique des congés et permissions',
      fileName: 'RH_Conges.pdf',
      headers: const ['Matricule', 'Employé', 'Type', 'Début', 'Fin', 'Jours', 'Statut'],
      rows: rows
          .map(
            (row) => [
              row['employee_number'].toString(),
              row['employee_name'].toString(),
              row['leave_type'].toString(),
              row['start_date'].toString().split('T').first,
              row['end_date'].toString().split('T').first,
              row['days'].toString(),
              row['status'].toString(),
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapports RH')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportTile(
            icon: Icons.groups_outlined,
            title: 'Liste du personnel',
            subtitle: 'Matricule, poste, service, statut et téléphone.',
            onTap: () => _staff(context, ref),
          ),
          _ReportTile(
            icon: Icons.apartment,
            title: 'Effectifs & masse salariale par service',
            subtitle: 'Effectifs actifs et total des salaires de base.',
            onTap: () => _department(context, ref),
          ),
          _ReportTile(
            icon: Icons.event_busy,
            title: 'Contrats arrivant à échéance',
            subtitle: 'Contrats actifs expirant dans les 90 prochains jours.',
            onTap: () => _contracts(context, ref),
          ),
          _ReportTile(
            icon: Icons.how_to_reg,
            title: 'Présences & absences',
            subtitle: 'Synthèse par employé sur une période choisie.',
            onTap: () => _attendance(context, ref),
          ),
          _ReportTile(
            icon: Icons.payments_outlined,
            title: 'Historique de paie',
            subtitle: 'Brut, retenues et net par période.',
            onTap: () => _payroll(context, ref),
          ),
          _ReportTile(
            icon: Icons.beach_access_outlined,
            title: 'Congés & permissions',
            subtitle: 'Historique des demandes et décisions.',
            onTap: () => _leaves(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.picture_as_pdf_outlined),
        onTap: onTap,
      ),
    );
  }
}
