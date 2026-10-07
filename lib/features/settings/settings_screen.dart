import 'package:flutter/material.dart';

import '../../core/session/operator_session.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import 'appearance_screen.dart';
import 'audit_log_screen.dart';
import 'backup_screen.dart';
import 'classes_screen.dart';
import 'cloud_sync_screen.dart';
import 'data_integrity_screen.dart';
import 'document_requirements_screen.dart';
import 'establishment_screen.dart';
import 'notification_settings_screen.dart';
import 'payment_accounts_screen.dart';
import 'receipt_printing_settings_screen.dart';
import 'school_years_screen.dart';
import 'security_settings_screen.dart';
import '../security/super_admin_console_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowsPageScaffold(
      title: 'Réglages',
      subtitle: 'Affichage, établissement, sécurité et données',
      body: ListView(
        padding: WindowsUi.isDesktop(context) ? EdgeInsets.zero : const EdgeInsets.all(16),
        children: [
          _header(context),
          const SizedBox(height: 22),
          const _SectionTitle('Expérience'),
          WindowsModuleGrid(children: [
            _tile(context, Icons.palette_outlined, 'Apparence', 'Mode clair, sombre ou automatique', const AppearanceScreen()),
            _tile(context, Icons.notifications_active_outlined, 'Notifications hors ligne', 'Alertes locales sans Internet, même en arrière-plan', const NotificationSettingsScreen()),
          ]),
          const SizedBox(height: 20),
          const _SectionTitle('Établissement'),
          WindowsModuleGrid(children: [
            _tile(context, Icons.apartment_rounded, 'Établissement', 'Identité, coordonnées, logo et agrément', const EstablishmentScreen()),
            _tile(context, Icons.calendar_month_outlined, 'Années scolaires', 'Historique, année active et bascule annuelle', const SchoolYearsScreen()),
            _tile(context, Icons.account_tree_outlined, 'Cycles et classes', 'Créer et administrer les cycles et salles', const ClassesScreen()),
            _tile(context, Icons.folder_copy_outlined, 'Pièces du dossier élève', 'Documents obligatoires, facultatifs et complétude', const DocumentRequirementsScreen()),
            _tile(context, Icons.account_balance_wallet_outlined, 'Paiements & comptes', 'Moyens de paiement, caisses, Mobile Money et banque', const PaymentAccountsScreen()),
            _tile(context, Icons.print_outlined, 'Reçus & imprimante POS', 'A5, tickets 80/58 mm, imprimante par défaut et impression automatique', const ReceiptPrintingSettingsScreen()),
          ]),
          const SizedBox(height: 20),
          const _SectionTitle('Sécurité & données'),
          WindowsModuleGrid(children: [
            _tile(context, Icons.cloud_sync_outlined, 'Compte & synchronisation', 'Tenant Supabase, état cloud et synchronisation automatique', const CloudSyncScreen()),
            if (OperatorSession.isAdmin)
              _tile(context, Icons.admin_panel_settings_outlined, 'Console Super Admin', 'Contrôler les écoles, comptes, appareils et flux du SaaS', const SuperAdminConsoleScreen()),
            _tile(context, Icons.shield_outlined, 'Sécurité', 'Administrateur et comptes gestionnaires', const SecuritySettingsScreen()),
            _tile(context, Icons.history_outlined, 'Journal d’audit', 'Opérations sensibles, annulations et traçabilité', const AuditLogScreen()),
            _tile(context, Icons.health_and_safety_outlined, 'Diagnostic des données', 'Contrôler la cohérence SQLite et comptable', const DataIntegrityScreen()),
            if (OperatorSession.isManager)
              _tile(context, Icons.backup_outlined, 'Sauvegarde', 'Sauvegarde locale, restauration et import/export JSON', const BackupScreen()),
          ]),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WindowsPanel(
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.tune_rounded, color: scheme.onPrimary)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Personnaliser GesApp', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 3),
          Text('Tous les paramètres essentiels sont regroupés par domaine.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, Widget destination) => WindowsModuleCard(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination)),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
        child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
