import 'package:flutter/material.dart';

import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import 'accounting_screen.dart';
import 'accounting_settings_screen.dart';
import 'bank_reconciliation_screen.dart';
import 'cash_screen.dart';
import 'dues_generation_screen.dart';
import 'billing_calendar_screen.dart';
import 'dues_screen.dart';
import 'fee_categories_screen.dart';
import 'fee_grid_screen.dart';
import 'manual_journal_entry_screen.dart';
import 'packages_screen.dart';
import 'payments_screen.dart';
import 'receipt_verification_screen.dart';
import 'recovery_screen.dart';
import 'supplier_accounting_screen.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = <Widget>[
      _module(context, Icons.category_outlined, 'Rubriques de paiement', 'Créer et configurer les frais', const FeeCategoriesScreen()),
      _module(context, Icons.price_change_outlined, 'Grille tarifaire', 'Tarifs par cycle ou classe', const FeeGridScreen()),
      _module(context, Icons.calendar_month_outlined, 'Calendrier de facturation', 'Génération automatique dès l’inscription', const BillingCalendarScreen()),
      _module(context, Icons.auto_awesome_outlined, 'Outil de génération historique', 'À utiliser uniquement après vérification', const DuesGenerationScreen()),
      _module(context, Icons.workspace_premium_outlined, 'Forfaits', 'Réductions familiales et individuelles', const PackagesScreen()),
      _module(context, Icons.account_balance_wallet_outlined, 'Caisse & clôture', 'Ouverture, solde théorique et clôture journalière', const CashScreen()),
      _module(context, Icons.payments_outlined, 'Encaissements', 'Paiements, reçus, remboursements et annulations', const PaymentsScreen()),
      _module(context, Icons.verified_user_outlined, 'Vérifier un document', 'Contrôler un reçu ou une référence documentaire GesApp', const ReceiptVerificationScreen()),
      _module(context, Icons.warning_amber_rounded, 'Impayés', 'Suivre les soldes et retards', const DuesScreen()),
      _module(context, Icons.phone_in_talk_outlined, 'Recouvrement', 'Relances, promesses de paiement et suivi des contacts', const RecoveryScreen()),
      _module(context, Icons.account_tree_outlined, 'Comptabilité générale', 'Plan comptable, livre-journal, grand-livre et balance', const AccountingScreen()),
      _module(context, Icons.local_shipping_outlined, 'Dettes fournisseurs', 'Factures, échéances et règlements fournisseurs', const SupplierAccountingScreen()),
      _module(context, Icons.edit_note_outlined, 'Écritures manuelles', 'Opérations diverses avec contrôle débit/crédit', const ManualJournalEntryScreen()),
      _module(context, Icons.account_balance_outlined, 'Rapprochement bancaire', 'Pointer banque et Mobile Money avec le relevé', const BankReconciliationScreen()),
      _module(context, Icons.tune_outlined, 'Paramétrage comptable', 'Comptes de créances, produits, fournisseurs et trésorerie', const AccountingSettingsScreen()),
    ];

    return WindowsPageScaffold(
      title: 'Finances',
      subtitle: 'Encaissements, échéances, caisse, recouvrement et comptabilité',
      body: ListView(
        padding: WindowsUi.isDesktop(context) ? EdgeInsets.zero : const EdgeInsets.all(16),
        children: [
          WindowsModuleGrid(children: modules),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _module(BuildContext context, IconData icon, String title, String subtitle, Widget destination) => WindowsModuleCard(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination)),
      );
}
