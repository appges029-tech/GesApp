import 'package:flutter/material.dart';

import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import 'accounting_screen.dart';
import '../../core/session/operator_session.dart';
import 'simple_fee_setup_screen.dart';
import 'accounting_settings_screen.dart';
import 'bank_reconciliation_screen.dart';
import 'cash_screen.dart';
import 'dues_screen.dart';
import 'fee_categories_screen.dart';
import 'fee_grid_screen.dart';
import 'manual_journal_entry_screen.dart';
import 'packages_screen.dart';
import 'payments_screen.dart';
import 'payment_form_screen.dart';
import 'receipt_verification_screen.dart';
import 'recovery_screen.dart';
import 'supplier_accounting_screen.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = <Widget>[
      _module(context, Icons.payments_outlined, 'Encaisser un paiement',
        'Choisir l’élève et enregistrer directement', const PaymentFormScreen()),
      _module(context, Icons.receipt_long_outlined, 'Paiements et reçus',
        'Rechercher, réimprimer ou rembourser', const PaymentsScreen()),
      _module(context, Icons.account_balance_wallet_outlined, 'Caisse et clôture',
        'Contrôler les opérations et le solde de caisse', const CashScreen()),
      _module(context, Icons.warning_amber_rounded, 'Suivi des impayés',
        'Retards et sommes restant à régler', const DuesScreen()),
      _module(context, Icons.phone_in_talk_outlined, 'Recouvrement',
        'Relances et suivi des engagements', const RecoveryScreen()),
    ];
    final configuration = <Widget>[
      _module(context, Icons.category_outlined, 'Rubriques de paiement',
        'Définir les types de frais', const FeeCategoriesScreen()),
      _module(context, Icons.price_change_outlined, 'Grille tarifaire',
        'Tarifs par cycle ou par classe', const FeeGridScreen()),
      _module(context, Icons.workspace_premium_outlined, 'Forfaits et remises',
        'Ajustements autorisés', const PackagesScreen()),
    ];
    final accounting = <Widget>[
      _module(context, Icons.account_tree_outlined, 'Comptabilité générale',
        'Journaux, grand-livre et balance', const AccountingScreen()),
      _module(context, Icons.local_shipping_outlined, 'Dettes fournisseurs',
        'Factures et règlements fournisseurs', const SupplierAccountingScreen()),
      _module(context, Icons.edit_note_outlined, 'Écritures manuelles',
        'Saisie contrôlée', const ManualJournalEntryScreen()),
      _module(context, Icons.account_balance_outlined, 'Rapprochement bancaire',
        'Comparer les mouvements', const BankReconciliationScreen()),
      _module(context, Icons.tune_outlined, 'Paramétrage comptable',
        'Comptes et affectations', const AccountingSettingsScreen()),
      _module(context, Icons.verified_user_outlined, 'Vérifier un reçu',
        'Authenticité des documents', const ReceiptVerificationScreen()),
    ];

    return WindowsPageScaffold(
      title: 'Finances',
      subtitle: 'Encaissements, périodes dues, caisse, recouvrement et comptabilité',
      body: ListView(
        padding: WindowsUi.isDesktop(context) ? EdgeInsets.zero : const EdgeInsets.all(16),
        children: [
          _section(context, 'Opérations quotidiennes', 'Retrouver rapidement les actions essentielles'),
          WindowsModuleGrid(children: primary),
          const SizedBox(height: 26),
          _section(context, 'Configuration scolaire', 'Rubriques, tarifs et remises'),
          if (OperatorSession.isManager)
            WindowsModuleGrid(children: [
              _module(context, Icons.add_circle_outline_rounded,
                'Créer des frais scolaires',
                'Nom, fréquence et montant dans un seul formulaire',
                const SimpleFeeSetupScreen()),
            ]),
          ExpansionTile(
            title: const Text('Gérer les rubriques et tarifs existants'),
            subtitle: const Text('Options avancées : modifications, historique et remises'),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [WindowsModuleGrid(children: configuration)],
          ),
          const SizedBox(height: 26),
          _section(context, 'Comptabilité et contrôles', 'Outils administratifs et vérification'),
          ExpansionTile(
            title: const Text('Outils avancés de comptabilité'),
            subtitle: const Text('Grand livre, fournisseurs et rapprochement bancaire'),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [WindowsModuleGrid(children: accounting)],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );

  Widget _module(BuildContext context, IconData icon, String title, String subtitle, Widget destination) => WindowsModuleCard(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination)),
      );
}
