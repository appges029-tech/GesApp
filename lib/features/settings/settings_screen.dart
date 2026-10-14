import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
import '../security/quick_unlock_settings_screen.dart';

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
          const SizedBox(height: 16),
          _settingsSearch(context),
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
            _tile(context, Icons.shield_outlined, 'Sécurité', 'Administrateur et comptes gestionnaires', const SecuritySettingsScreen()),
            _tile(context, Icons.fingerprint_rounded, 'Schéma et empreinte', 'Déverrouillage rapide sur Android', const QuickUnlockSettingsScreen()),
            _tile(context, Icons.history_outlined, 'Journal d’audit', 'Opérations sensibles, annulations et traçabilité', const AuditLogScreen()),
            _tile(context, Icons.health_and_safety_outlined, 'Diagnostic des données', 'Contrôler la cohérence SQLite et comptable', const DataIntegrityScreen()),
            if (OperatorSession.isManager)
              _tile(context, Icons.backup_outlined, 'Sauvegarde', 'Sauvegarde locale, restauration et import/export JSON', const BackupScreen()),
          ]),
          const SizedBox(height: 20),
          ExpansionTile(
            title: const Text('Outils avancés'),
            subtitle: const Text('Contrôle, traçabilité et diagnostic'),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              WindowsModuleGrid(children: [
                if (OperatorSession.isAdmin)
                  _tile(context, Icons.admin_panel_settings_outlined,
                    'Console Super Admin', 'Contrôler les écoles et leurs accès',
                    const SuperAdminConsoleScreen()),
                _tile(context, Icons.history_outlined, 'Journal d’audit',
                  'Historique des opérations sensibles', const AuditLogScreen()),
                _tile(context, Icons.health_and_safety_outlined,
                  'Diagnostic des données', 'Vérifier la cohérence des données',
                  const DataIntegrityScreen()),
              ]),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _settingsSearch(BuildContext context) {
    final links = <({String title, String subtitle, IconData icon, Widget page})>[
      (title: 'Apparence', subtitle: 'Couleur et thème',
        icon: Icons.palette_outlined, page: const AppearanceScreen()),
      (title: 'Notifications hors ligne', subtitle: 'Alertes',
        icon: Icons.notifications_active_outlined, page: const NotificationSettingsScreen()),
      (title: 'Établissement', subtitle: 'Identité et logo',
        icon: Icons.apartment_rounded, page: const EstablishmentScreen()),
      (title: 'Années scolaires', subtitle: 'Année active',
        icon: Icons.calendar_month_outlined, page: const SchoolYearsScreen()),
      (title: 'Cycles et classes', subtitle: 'Classes de l’école',
        icon: Icons.account_tree_outlined, page: const ClassesScreen()),
      (title: 'Pièces du dossier élève', subtitle: 'Documents scolaires',
        icon: Icons.folder_copy_outlined, page: const DocumentRequirementsScreen()),
      (title: 'Paiements et comptes', subtitle: 'Caisses et Mobile Money',
        icon: Icons.account_balance_wallet_outlined, page: const PaymentAccountsScreen()),
      (title: 'Reçus et imprimante', subtitle: 'Impression A5 et POS',
        icon: Icons.print_outlined, page: const ReceiptPrintingSettingsScreen()),
      (title: 'Compte et synchronisation', subtitle: 'Accès en ligne et données',
        icon: Icons.cloud_sync_outlined, page: const CloudSyncScreen()),
      (title: 'Sécurité', subtitle: 'Accès des utilisateurs',
        icon: Icons.shield_outlined, page: const SecuritySettingsScreen()),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        (title: 'Schéma et empreinte', subtitle: 'Biométrie Android',
          icon: Icons.fingerprint, page: const QuickUnlockSettingsScreen()),
      if (OperatorSession.isManager)
        (title: 'Sauvegarde', subtitle: 'Sauvegarder et restaurer',
          icon: Icons.backup_outlined, page: const BackupScreen()),
      if (OperatorSession.isAdmin)
        (title: 'Console Super Admin', subtitle: 'Contrôle des écoles',
          icon: Icons.admin_panel_settings_outlined, page: const SuperAdminConsoleScreen()),
      (title: 'Journal d’audit', subtitle: 'Historique et contrôles',
        icon: Icons.history_outlined, page: const AuditLogScreen()),
      (title: 'Diagnostic des données', subtitle: 'Cohérence des données',
        icon: Icons.health_and_safety_outlined, page: const DataIntegrityScreen()),
    ];
    return SearchAnchor.bar(
      barHintText: 'Rechercher un réglage…',
      suggestionsBuilder: (searchContext, controller) {
        final query = controller.text.trim().toLowerCase();
        final matching = links.where((item) =>
          (item.title + ' ' + item.subtitle).toLowerCase().contains(query)).toList();
        if (matching.isEmpty) {
          return [const ListTile(title: Text('Aucun réglage trouvé.'))];
        }
        return matching.map((item) => ListTile(
          leading: Icon(item.icon),
          title: Text(item.title),
          subtitle: Text(item.subtitle),
          onTap: () {
            controller.closeView('');
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => item.page));
          },
        )).toList();
      },
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
          Text('Les réglages courants sont affichés en premier. Les outils techniques restent disponibles dans Options avancées.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
