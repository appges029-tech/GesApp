import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../platform/platform_database.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Database get db {
    final value = _db;
    if (value == null) throw StateError('Base de données non initialisée');
    return value;
  }

  Future<String> get databasePath => platformDatabasePath();

  Future<void> initialize() async {
    if (_db != null) return;
    final path = await databasePath;
    _db = await platformDatabaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 29,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          try {
            await database.rawQuery('PRAGMA journal_mode = TRUNCATE');
          } catch (_) {
            // Le moteur SQLite Web ne permet pas toujours de modifier le journal.
          }
        },
      onCreate: (database, version) async {
        await _createSchema(database, version);
        await _seedDefaults(database);
        await _ensureSyncInfrastructure(database);
        await _ensureFinancialInvariantTriggers(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('''CREATE TABLE IF NOT EXISTS student_status_history(
            id TEXT PRIMARY KEY,
            student_id TEXT NOT NULL,
            old_status TEXT,
            new_status TEXT NOT NULL,
            changed_at TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
          )''');
          await database.execute('''CREATE TABLE IF NOT EXISTS app_settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
          await _seedDefaults(database);
        }
        if (oldVersion < 3) {
          // Traçabilité : quel opérateur a réalisé l'action, et gestion des
          // annulations/contre-passations de paiements et de dépenses.
          final auditColumns = await database.rawQuery('PRAGMA table_info(audit_log)');
          final hasOperator = auditColumns.any((c) => c['name'] == 'operator_name');
          if (!hasOperator) {
            await database.execute('ALTER TABLE audit_log ADD COLUMN operator_name TEXT');
          }
          final paymentColumns = await database.rawQuery('PRAGMA table_info(payments)');
          final hasCancelReason = paymentColumns.any((c) => c['name'] == 'cancel_reason');
          if (!hasCancelReason) {
            await database.execute('ALTER TABLE payments ADD COLUMN cancel_reason TEXT');
          }
          final hasCancelledAt = paymentColumns.any((c) => c['name'] == 'cancelled_at');
          if (!hasCancelledAt) {
            await database.execute('ALTER TABLE payments ADD COLUMN cancelled_at TEXT');
          }
        }
        if (oldVersion < 4) {
          // Les forfaits V4 sont rattachés à une rubrique précise afin qu'ils
          // puissent réellement remplacer la grille tarifaire sans double
          // facturation. Les anciens forfaits restent visibles mais sont
          // désactivés tant qu'ils n'ont pas été recréés avec une rubrique.
          final packageColumns = await database.rawQuery('PRAGMA table_info(packages)');
          final hasFeeId = packageColumns.any((c) => c['name'] == 'fee_id');
          if (!hasFeeId) {
            await database.execute('ALTER TABLE packages ADD COLUMN fee_id TEXT');
          }
          await database.execute('UPDATE packages SET active = 0 WHERE fee_id IS NULL');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_packages_fee ON packages(fee_id)');
        }
        if (oldVersion < 5) {
          // V5 : vraie notion d'année scolaire et historique annuel des
          // inscriptions. Les colonnes historiques de `students` restent
          // conservées comme cache de l'état courant pour compatibilité avec
          // les modules existants pendant la migration progressive.
          await database.execute('''CREATE TABLE IF NOT EXISTS school_years(
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
          await database.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_school_year_active
            ON school_years(is_active) WHERE is_active = 1''');
          await database.execute('''CREATE TABLE IF NOT EXISTS student_enrollments(
            id TEXT PRIMARY KEY,
            student_id TEXT NOT NULL,
            school_year_id TEXT NOT NULL,
            classroom_id TEXT NOT NULL,
            enrollment_type TEXT NOT NULL DEFAULT 'new',
            status TEXT NOT NULL DEFAULT 'active',
            effective_from TEXT NOT NULL,
            effective_to TEXT,
            origin_establishment TEXT,
            observations TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(student_id, school_year_id),
            FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE,
            FOREIGN KEY(school_year_id) REFERENCES school_years(id),
            FOREIGN KEY(classroom_id) REFERENCES classrooms(id)
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_enrollments_year ON student_enrollments(school_year_id)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_enrollments_student ON student_enrollments(student_id)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_enrollments_classroom ON student_enrollments(classroom_id)');

          final now = DateTime.now().toIso8601String();
          final establishment = await database.query('establishments', limit: 1);
          String? activeYearId;
          if (establishment.isNotEmpty) {
            activeYearId = const Uuid().v4();
            final e = establishment.first;
            await database.insert('school_years', {
              'id': activeYearId,
              'label': e['school_year_label'],
              'start_date': e['school_year_start'],
              'end_date': e['school_year_end'],
              'is_active': 1,
              'created_at': now,
              'updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          if (activeYearId != null) {
            final students = await database.query('students');
            for (final student in students) {
              await database.insert('student_enrollments', {
                'id': const Uuid().v4(),
                'student_id': student['id'],
                'school_year_id': activeYearId,
                'classroom_id': student['classroom_id'],
                'enrollment_type': 'legacy',
                'status': student['status'] == 'reinscrit' ? 'active' : student['status'],
                'effective_from': student['enrollment_date'] ?? student['created_at'] ?? now,
                'effective_to': null,
                'origin_establishment': null,
                'observations': 'Migration automatique depuis GesApp V4',
                'created_at': now,
                'updated_at': now,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            await database.update('students', {'status': 'active'}, where: "status = 'reinscrit'");
          }
        }
        if (oldVersion < 6) {
          // V6 : comptes locaux authentifiés, rôles et anti-brute-force
          // persisté. Aucun PIN n'est stocké en clair.
          await database.execute('''CREATE TABLE IF NOT EXISTS app_users(
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL COLLATE NOCASE UNIQUE,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL,
            pin_hash TEXT NOT NULL,
            pin_salt TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            failed_attempts INTEGER NOT NULL DEFAULT 0,
            locked_until TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_app_users_active ON app_users(active)');

          final auditColumns = await database.rawQuery('PRAGMA table_info(audit_log)');
          if (!auditColumns.any((c) => c['name'] == 'operator_id')) {
            await database.execute('ALTER TABLE audit_log ADD COLUMN operator_id TEXT');
          }
          if (!auditColumns.any((c) => c['name'] == 'operator_role')) {
            await database.execute('ALTER TABLE audit_log ADD COLUMN operator_role TEXT');
          }

          // Si l'ancienne installation possédait déjà un PIN global, on le
          // migre vers un premier compte Gestionnaire sans demander de nouveau
          // secret et sans jamais connaître le PIN en clair.
          final settings = await database.query('app_settings', where: "key IN ('pin_hash','pin_salt','operator_name')");
          final values = <String, String>{};
          for (final row in settings) {
            final key = row['key'] as String?;
            final value = row['value'] as String?;
            if (key != null && value != null) values[key] = value;
          }
          final legacyHash = values['pin_hash'];
          final legacySalt = values['pin_salt'];
          if (legacyHash != null && legacySalt != null) {
            final now = DateTime.now().toIso8601String();
            final displayName = (values['operator_name'] ?? 'Gestionnaire').trim();
            await database.insert('app_users', {
              'id': const Uuid().v4(),
              'username': 'gestionnaire',
              'display_name': displayName.isEmpty ? 'Gestionnaire' : displayName,
              'role': 'manager',
              'pin_hash': legacyHash,
              'pin_salt': legacySalt,
              'active': 1,
              'failed_attempts': 0,
              'locked_until': null,
              'created_at': now,
              'updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 7) {
          final studentColumns = await database.rawQuery('PRAGMA table_info(students)');
          for (final col in <String, String>{'nationality':'TEXT','address':'TEXT','origin_school':'TEXT'}.entries) {
            if (!studentColumns.any((c) => c['name'] == col.key)) await database.execute('ALTER TABLE students ADD COLUMN ${col.key} ${col.value}');
          }
          final paymentColumns = await database.rawQuery('PRAGMA table_info(payments)');
          for (final col in <String, String>{'cash_account_id':'TEXT','transaction_reference':'TEXT','payer_phone':'TEXT','payment_operator':'TEXT','credit_amount':'INTEGER NOT NULL DEFAULT 0'}.entries) {
            if (!paymentColumns.any((c) => c['name'] == col.key)) await database.execute('ALTER TABLE payments ADD COLUMN ${col.key} ${col.value}');
          }
          final expenseColumns = await database.rawQuery('PRAGMA table_info(expenses)');
          for (final col in <String, String>{'expense_number':'TEXT','beneficiary':'TEXT','payment_method':'TEXT','cash_account_id':'TEXT','external_reference':'TEXT','approval_status':"TEXT NOT NULL DEFAULT 'approved'"}.entries) {
            if (!expenseColumns.any((c) => c['name'] == col.key)) await database.execute('ALTER TABLE expenses ADD COLUMN ${col.key} ${col.value}');
          }
          await database.execute("CREATE TABLE IF NOT EXISTS payment_methods(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, requires_reference INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)");
          await database.execute("CREATE TABLE IF NOT EXISTS cash_accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, type TEXT NOT NULL, opening_balance INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
          await database.execute("CREATE TABLE IF NOT EXISTS payment_refunds(id TEXT PRIMARY KEY, payment_id TEXT NOT NULL, amount INTEGER NOT NULL, reason TEXT NOT NULL, refunded_at TEXT NOT NULL, operator_id TEXT)");
          await database.execute("CREATE TABLE IF NOT EXISTS payer_credits(id TEXT PRIMARY KEY, student_id TEXT, family_id TEXT, amount INTEGER NOT NULL, source_payment_id TEXT, status TEXT NOT NULL DEFAULT 'available', created_at TEXT NOT NULL)");
          await database.execute("CREATE TABLE IF NOT EXISTS cash_sessions(id TEXT PRIMARY KEY, cash_account_id TEXT NOT NULL, opened_by TEXT, opened_at TEXT NOT NULL, opening_amount INTEGER NOT NULL DEFAULT 0, closed_by TEXT, closed_at TEXT, theoretical_amount INTEGER, physical_amount INTEGER, variance INTEGER, status TEXT NOT NULL DEFAULT 'open')");
          await database.execute("CREATE TABLE IF NOT EXISTS student_guardians(id TEXT PRIMARY KEY, student_id TEXT NOT NULL, name TEXT NOT NULL, phone TEXT, relationship TEXT NOT NULL DEFAULT 'tuteur', is_primary INTEGER NOT NULL DEFAULT 0, is_financial INTEGER NOT NULL DEFAULT 0, is_emergency INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE)");
          final now = DateTime.now().toIso8601String();
          for (final m in [['cash','Espèces',0],['mobile','Mobile Money',1],['transfer','Virement',1]]) {
            await database.insert('payment_methods', {'id':m[0], 'name':m[1], 'requires_reference':m[2], 'active':1}, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          for (final a in [['main_cash','Caisse principale','cash'],['mobile_money','Mobile Money','mobile'],['bank','Compte bancaire','bank']]) {
            await database.insert('cash_accounts', {'id':a[0], 'name':a[1], 'type':a[2], 'opening_balance':0, 'active':1, 'created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          final students = await database.query('students', columns:['id','guardian_name','guardian_phone']);
          for (final st in students) {
            final name=(st['guardian_name'] as String?)?.trim();
            if (name != null && name.isNotEmpty) await database.insert('student_guardians', {'id':const Uuid().v4(),'student_id':st['id'],'name':name,'phone':st['guardian_phone'],'relationship':'tuteur','is_primary':1,'is_financial':1,'is_emergency':1,'created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 8) {
          final alertColumns = await database.rawQuery('PRAGMA table_info(alerts)');
          if (!alertColumns.any((c) => c['name'] == 'severity')) {
            await database.execute("ALTER TABLE alerts ADD COLUMN severity TEXT NOT NULL DEFAULT 'warning'");
          }
          if (!alertColumns.any((c) => c['name'] == 'status')) {
            await database.execute("ALTER TABLE alerts ADD COLUMN status TEXT NOT NULL DEFAULT 'new'");
          }
          await database.execute('CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status, severity)');
        }
        if (oldVersion < 9) {
          final alertColumns = await database.rawQuery('PRAGMA table_info(alerts)');
          if (!alertColumns.any((c) => c['name'] == 'notification_sent')) {
            await database.execute('ALTER TABLE alerts ADD COLUMN notification_sent INTEGER NOT NULL DEFAULT 0');
          }
          await database.execute('CREATE INDEX IF NOT EXISTS idx_alerts_notification ON alerts(notification_sent, status)');
        }
        if (oldVersion < 10) {
          // V10 : GesApp adopte une interface unique. Les rôles historiques
          // sont neutralisés et tous les comptes deviennent Gestionnaires.
          await database.update('app_users', {
            'role': 'manager',
            'updated_at': DateTime.now().toIso8601String(),
          });
          await database.update('audit_log', {'operator_role': 'manager'}, where: 'operator_role IS NOT NULL');
        }
        if (oldVersion < 11) {
          // V11 : workflow d'approbation des dépenses.
          final expenseColumns = await database.rawQuery('PRAGMA table_info(expenses)');
          final columns = <String, String>{
            'submitted_by': 'TEXT',
            'submitted_at': 'TEXT',
            'reviewed_by': 'TEXT',
            'reviewed_at': 'TEXT',
            'approval_note': 'TEXT',
          };
          for (final entry in columns.entries) {
            if (!expenseColumns.any((c) => c['name'] == entry.key)) {
              await database.execute('ALTER TABLE expenses ADD COLUMN ${entry.key} ${entry.value}');
            }
          }
          // Les anciennes dépenses restent approuvées et comptabilisées.
          await database.execute("UPDATE expenses SET approval_status='approved' WHERE approval_status IS NULL OR approval_status='' ");
          await database.execute("UPDATE expenses SET submitted_at=created_at WHERE submitted_at IS NULL AND status='posted'");
          await database.execute("CREATE INDEX IF NOT EXISTS idx_expenses_approval ON expenses(approval_status, status, spent_at)");
        }
        if (oldVersion < 12) {
          // V12 : rattachement explicite des échéances et paiements à une
          // année scolaire. Cela empêche les KPI, encaissements et rapports
          // de mélanger plusieurs exercices scolaires après quelques années.
          final dueColumns = await database.rawQuery('PRAGMA table_info(dues)');
          if (!dueColumns.any((c) => c['name'] == 'school_year_id')) {
            await database.execute('ALTER TABLE dues ADD COLUMN school_year_id TEXT');
          }
          final paymentColumns = await database.rawQuery('PRAGMA table_info(payments)');
          if (!paymentColumns.any((c) => c['name'] == 'school_year_id')) {
            await database.execute('ALTER TABLE payments ADD COLUMN school_year_id TEXT');
          }

          // Rattache les échéances historiques à l'année qui couvre leur date.
          await database.execute('''
            UPDATE dues
            SET school_year_id = (
              SELECT sy.id FROM school_years sy
              WHERE COALESCE(dues.due_date, dues.created_at) >= sy.start_date
                AND COALESCE(dues.due_date, dues.created_at) <= sy.end_date
              ORDER BY sy.start_date DESC LIMIT 1
            )
            WHERE school_year_id IS NULL
          ''');
          // En dernier recours, rattache les anciennes lignes sans date
          // exploitable à l'année active pour ne jamais les rendre orphelines.
          await database.execute('''
            UPDATE dues
            SET school_year_id = (SELECT id FROM school_years WHERE is_active = 1 LIMIT 1)
            WHERE school_year_id IS NULL
          ''');

          // Un paiement hérite d'abord de l'année de ses allocations.
          await database.execute('''
            UPDATE payments
            SET school_year_id = (
              SELECT d.school_year_id
              FROM payment_allocations pa
              JOIN dues d ON d.id = pa.due_id
              WHERE pa.payment_id = payments.id
                AND d.school_year_id IS NOT NULL
              ORDER BY d.due_date, d.created_at LIMIT 1
            )
            WHERE school_year_id IS NULL
          ''');
          // Les avances/paiements non alloués sont rattachés selon leur date.
          await database.execute('''
            UPDATE payments
            SET school_year_id = (
              SELECT sy.id FROM school_years sy
              WHERE payments.paid_at >= sy.start_date
                AND payments.paid_at <= sy.end_date
              ORDER BY sy.start_date DESC LIMIT 1
            )
            WHERE school_year_id IS NULL
          ''');
          await database.execute('''
            UPDATE payments
            SET school_year_id = (SELECT id FROM school_years WHERE is_active = 1 LIMIT 1)
            WHERE school_year_id IS NULL
          ''');

          await database.execute('CREATE INDEX IF NOT EXISTS idx_dues_school_year ON dues(school_year_id, status, due_date)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_payments_school_year ON payments(school_year_id, status, paid_at)');
        }
        if (oldVersion < 13) {
          // V13 : consommation traçable des avoirs sur de nouvelles échéances.
          await database.execute('''CREATE TABLE IF NOT EXISTS payer_credit_allocations(
            id TEXT PRIMARY KEY,
            credit_id TEXT NOT NULL,
            due_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            applied_at TEXT NOT NULL,
            operator_id TEXT,
            FOREIGN KEY(credit_id) REFERENCES payer_credits(id),
            FOREIGN KEY(due_id) REFERENCES dues(id)
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_credit_alloc_due ON payer_credit_allocations(due_id)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_credit_alloc_credit ON payer_credit_allocations(credit_id)');
        }
        if (oldVersion < 14) {
          // V14 : transferts internes entre caisses/comptes, sans créer de
          // fausse recette ni de fausse dépense.
          await database.execute('''CREATE TABLE IF NOT EXISTS cash_transfers(
            id TEXT PRIMARY KEY,
            from_account_id TEXT NOT NULL,
            to_account_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            transferred_at TEXT NOT NULL,
            reference TEXT,
            note TEXT,
            operator_id TEXT,
            status TEXT NOT NULL DEFAULT 'posted',
            created_at TEXT NOT NULL,
            FOREIGN KEY(from_account_id) REFERENCES cash_accounts(id),
            FOREIGN KEY(to_account_id) REFERENCES cash_accounts(id)
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_cash_transfers_date ON cash_transfers(transferred_at)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_cash_transfers_from ON cash_transfers(from_account_id, transferred_at)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_cash_transfers_to ON cash_transfers(to_account_id, transferred_at)');
        }
        if (oldVersion < 15) {
          // V15 : moyens de paiement configurables et liés explicitement au
          // type de compte compatible. Plus aucune règle métier ne dépend du
          // libellé français du moyen de paiement.
          final methodColumns = await database.rawQuery('PRAGMA table_info(payment_methods)');
          if (!methodColumns.any((c) => c['name'] == 'account_type')) {
            await database.execute('ALTER TABLE payment_methods ADD COLUMN account_type TEXT');
          }
          await database.execute("UPDATE payment_methods SET account_type='cash' WHERE account_type IS NULL AND lower(name) LIKE '%esp%'");
          await database.execute("UPDATE payment_methods SET account_type='mobile' WHERE account_type IS NULL AND lower(name) LIKE '%mobile%'");
          await database.execute("UPDATE payment_methods SET account_type='bank' WHERE account_type IS NULL AND (lower(name) LIKE '%virement%' OR lower(name) LIKE '%banque%' OR lower(name) LIKE '%chèque%' OR lower(name) LIKE '%cheque%')");
          await database.execute("UPDATE payment_methods SET account_type='cash' WHERE account_type IS NULL");
          await database.execute('CREATE INDEX IF NOT EXISTS idx_payment_methods_active ON payment_methods(active, name)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_cash_accounts_active ON cash_accounts(active, type, name)');
        }
        if (oldVersion < 16) {
          // V16 : lots de facturation. Chaque génération est désormais
          // simulable, identifiable et annulable tant qu'aucun règlement ne
          // l'a touchée.
          await database.execute('''CREATE TABLE IF NOT EXISTS billing_batches(
            id TEXT PRIMARY KEY,
            school_year_id TEXT NOT NULL,
            period_key TEXT NOT NULL,
            periodicity TEXT NOT NULL,
            reference_date TEXT NOT NULL,
            due_date TEXT NOT NULL,
            generated_count INTEGER NOT NULL DEFAULT 0,
            total_amount INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'posted',
            created_by TEXT,
            created_at TEXT NOT NULL,
            cancelled_at TEXT,
            FOREIGN KEY(school_year_id) REFERENCES school_years(id)
          )''');
          final dueColumns = await database.rawQuery('PRAGMA table_info(dues)');
          if (!dueColumns.any((c) => c['name'] == 'billing_batch_id')) {
            await database.execute('ALTER TABLE dues ADD COLUMN billing_batch_id TEXT');
          }
          await database.execute('CREATE INDEX IF NOT EXISTS idx_billing_batches_year ON billing_batches(school_year_id, created_at)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_dues_billing_batch ON dues(billing_batch_id)');
        }
        if (oldVersion < 17) {
          // V17 : suivi de recouvrement opérationnel. Les appels, messages,
          // promesses de paiement et prochaines relances sont historisés sans
          // modifier les écritures comptables.
          await database.execute('''CREATE TABLE IF NOT EXISTS recovery_actions(
            id TEXT PRIMARY KEY,
            due_id TEXT NOT NULL,
            action_type TEXT NOT NULL,
            channel TEXT,
            contact_name TEXT,
            outcome TEXT,
            promise_amount INTEGER,
            promise_date TEXT,
            next_follow_up_at TEXT,
            note TEXT,
            status TEXT NOT NULL DEFAULT 'open',
            operator_id TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(due_id) REFERENCES dues(id) ON DELETE CASCADE
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_recovery_due ON recovery_actions(due_id, created_at)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_recovery_followup ON recovery_actions(status, next_follow_up_at)');
        }
        if (oldVersion < 18) {
          // V18 : catalogue configurable des pièces obligatoires et suivi de
          // complétude des dossiers élèves.
          await database.execute('''CREATE TABLE IF NOT EXISTS document_requirements(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            description TEXT,
            required INTEGER NOT NULL DEFAULT 1,
            active INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_document_requirements_active ON document_requirements(active, sort_order, name)');
          final now = DateTime.now().toIso8601String();
          for (final item in const [
            ['Acte de naissance', 10],
            ['Photo d’identité', 20],
            ['Ancien bulletin', 30],
          ]) {
            await database.insert('document_requirements', {
              'id': const Uuid().v4(), 'name': item[0], 'required': 1,
              'active': 1, 'sort_order': item[1], 'created_at': now, 'updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 19) {
          // V19 : dérivation de PIN lente et versionnée. Les comptes existants
          // restent compatibles et seront renforcés au prochain login réussi.
          final userColumns = await database.rawQuery('PRAGMA table_info(app_users)');
          if (!userColumns.any((c) => c['name'] == 'pin_algorithm')) {
            await database.execute("ALTER TABLE app_users ADD COLUMN pin_algorithm TEXT NOT NULL DEFAULT 'sha256-legacy'");
          }
          if (!userColumns.any((c) => c['name'] == 'pin_iterations')) {
            await database.execute('ALTER TABLE app_users ADD COLUMN pin_iterations INTEGER NOT NULL DEFAULT 1');
          }
          if (!userColumns.any((c) => c['name'] == 'recovery_code_hash')) {
            await database.execute('ALTER TABLE app_users ADD COLUMN recovery_code_hash TEXT');
          }
          if (!userColumns.any((c) => c['name'] == 'recovery_code_salt')) {
            await database.execute('ALTER TABLE app_users ADD COLUMN recovery_code_salt TEXT');
          }
          await database.execute('CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity_type, action, created_at DESC)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_payments_receipt ON payments(receipt_number)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_expenses_number ON expenses(expense_number)');
        }
        if (oldVersion < 20) {
          // V20 : le remboursement devient un mouvement de trésorerie explicite.
          final refundColumns = await database.rawQuery('PRAGMA table_info(payment_refunds)');
          if (!refundColumns.any((c) => c['name'] == 'payment_method')) {
            await database.execute('ALTER TABLE payment_refunds ADD COLUMN payment_method TEXT');
          }
          if (!refundColumns.any((c) => c['name'] == 'cash_account_id')) {
            await database.execute('ALTER TABLE payment_refunds ADD COLUMN cash_account_id TEXT');
          }
          if (!refundColumns.any((c) => c['name'] == 'transaction_reference')) {
            await database.execute('ALTER TABLE payment_refunds ADD COLUMN transaction_reference TEXT');
          }
          // Les anciens remboursements sont rattachés au moyen/compte du paiement
          // d'origine afin qu'ils restent cohérents dans la trésorerie après migration.
          await database.execute('''
            UPDATE payment_refunds
            SET payment_method = (
              SELECT p.payment_method FROM payments p WHERE p.id = payment_refunds.payment_id
            )
            WHERE payment_method IS NULL
          ''');
          await database.execute('''
            UPDATE payment_refunds
            SET cash_account_id = (
              SELECT p.cash_account_id FROM payments p WHERE p.id = payment_refunds.payment_id
            )
            WHERE cash_account_id IS NULL
          ''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_payment_refunds_date ON payment_refunds(refunded_at)');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_payment_refunds_account ON payment_refunds(cash_account_id, refunded_at)');
        }
        if (oldVersion < 21) {
          // V21 : modèles de dépenses récurrentes. Ils préparent les écritures
          // attendues sans créer silencieusement une dépense comptabilisée.
          await database.execute('''CREATE TABLE IF NOT EXISTS recurring_expense_templates(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            beneficiary TEXT,
            description TEXT,
            payment_method TEXT,
            cash_account_id TEXT,
            frequency TEXT NOT NULL DEFAULT 'monthly',
            day_of_month INTEGER NOT NULL DEFAULT 1,
            next_due_at TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(category_id) REFERENCES expense_categories(id),
            FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_recurring_expense_due ON recurring_expense_templates(active, next_due_at)');
        }
        if (oldVersion < 22) {
          // V22 : historique intra-annuel des changements de classe.
          await database.execute('''CREATE TABLE IF NOT EXISTS student_class_movements(
            id TEXT PRIMARY KEY,
            student_id TEXT NOT NULL,
            school_year_id TEXT NOT NULL,
            from_classroom_id TEXT,
            to_classroom_id TEXT NOT NULL,
            effective_at TEXT NOT NULL,
            reason TEXT,
            operator_id TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE,
            FOREIGN KEY(school_year_id) REFERENCES school_years(id),
            FOREIGN KEY(from_classroom_id) REFERENCES classrooms(id),
            FOREIGN KEY(to_classroom_id) REFERENCES classrooms(id)
          )''');
          await database.execute('CREATE INDEX IF NOT EXISTS idx_student_class_movements_student ON student_class_movements(student_id,effective_at DESC)');
        }
        if (oldVersion < 23) {
          // V23 : domaine Ressources humaines complet (personnel, contrats,
          // présence, congés, paie, avances et documents RH).
          for (final statement in _hrSchema) {
            await database.execute(statement);
          }
          await _seedHrDefaults(database);
        }
        if (oldVersion < 24) {
          // V24 : gestion complète du patrimoine.
          for (final statement in _assetSchema) {
            await database.execute(statement);
          }
          await _seedAssetDefaults(database);
        }
        if (oldVersion < 25) {
          // V25 : socle comptable en partie double (plan simplifié,
          // livre-journal, grand-livre et balance générale).
          for (final statement in _accountingSchema) {
            await database.execute(statement);
          }
          await _seedAccountingDefaults(database);
        }
        if (oldVersion < 26) {
          // V26 : deuxième phase comptable. La comptabilité devient une
          // comptabilité d'engagement : créances scolaires à la facturation,
          // dettes fournisseurs, journaux manuels contrôlés et rapprochement.
          for (final statement in _accountingPhase2Schema) {
            await database.execute(statement);
          }
          await _seedAccountingDefaults(database);
          // Les écritures de V25 étaient entièrement dérivées des opérations
          // métier et constataient les produits au paiement. On les reconstruit
          // proprement selon la nouvelle règle d'engagement afin d'éviter tout
          // double produit lors de la création des créances.
          await database.delete('accounting_entry_lines');
          await database.delete('accounting_entries');
        }
        if (oldVersion < 27) {
          // V27 : finalisation V1. Chaque pièce du dossier élève reçoit une
          // référence publique vérifiable. Les anciennes pièces sont migrées
          // sans modifier leur fichier source.
          final documentColumns = await database.rawQuery('PRAGMA table_info(student_documents)');
          if (!documentColumns.any((c) => c['name'] == 'verification_code')) {
            await database.execute('ALTER TABLE student_documents ADD COLUMN verification_code TEXT');
          }
          if (!documentColumns.any((c) => c['name'] == 'verification_status')) {
            await database.execute("ALTER TABLE student_documents ADD COLUMN verification_status TEXT NOT NULL DEFAULT 'valid'");
          }
          if (!documentColumns.any((c) => c['name'] == 'revoked_at')) {
            await database.execute('ALTER TABLE student_documents ADD COLUMN revoked_at TEXT');
          }
          final documents = await database.query('student_documents', columns: ['id','verification_code']);
          for (final row in documents) {
            final current = (row['verification_code'] as String?)?.trim() ?? '';
            if (current.isNotEmpty) continue;
            final raw = (row['id'] as String).replaceAll('-', '').toUpperCase();
            final code = 'DOC-${raw.substring(0, raw.length >= 12 ? 12 : raw.length)}';
            await database.update('student_documents', {'verification_code': code}, where: 'id = ?', whereArgs: [row['id']]);
          }
          await database.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_student_documents_verification ON student_documents(verification_code)');
        }
        if (oldVersion < 28) {
          // V28 : identité cloud multitenant et état de synchronisation.
          await database.execute('''CREATE TABLE IF NOT EXISTS cloud_tenant_cache(
            organization_id TEXT PRIMARY KEY,
            organization_code TEXT NOT NULL,
            organization_name TEXT NOT NULL,
            cloud_user_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('admin','manager')),
            username TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            must_change_password INTEGER NOT NULL DEFAULT 0,
            backup_secret TEXT,
            updated_at TEXT NOT NULL
          )''');
          await database.execute('''CREATE TABLE IF NOT EXISTS cloud_sync_state(
            id TEXT PRIMARY KEY,
            local_revision INTEGER NOT NULL DEFAULT 0,
            last_uploaded_local_revision INTEGER NOT NULL DEFAULT 0,
            known_remote_revision INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'idle',
            last_error TEXT,
            last_synced_at TEXT,
            updated_at TEXT NOT NULL
          )''');
          await _ensureSyncInfrastructure(database);
        }
        if (oldVersion < 29) {
          // V29 : invariants financiers renforcés et cessions patrimoniales reliées à la trésorerie.
          final disposalColumns = await database.rawQuery('PRAGMA table_info(asset_disposals)');
          if (!disposalColumns.any((c) => c['name'] == 'cash_account_id')) {
            await database.execute('ALTER TABLE asset_disposals ADD COLUMN cash_account_id TEXT');
          }
          if (!disposalColumns.any((c) => c['name'] == 'reference')) {
            await database.execute('ALTER TABLE asset_disposals ADD COLUMN reference TEXT');
          }
          await database.execute("UPDATE assets SET status='out_of_service' WHERE status='retired'");
          await _seedAccountingDefaults(database);
          await _ensureFinancialInvariantTriggers(database);
        }
      },
      ),
    );
  }

  /// Ferme explicitement la connexion SQLite. Utilisé avant une sauvegarde
  /// ou une restauration afin de ne jamais copier/remplacer un fichier de
  /// base de données encore ouvert.
  Future<void> close() async {
    final current = _db;
    _db = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  Future<void> _ensureSyncInfrastructure(Database database) async {
    final now = DateTime.now().toIso8601String();
    await database.insert('cloud_sync_state', {
      'id': 'main',
      'local_revision': 0,
      'last_uploaded_local_revision': 0,
      'known_remote_revision': 0,
      'status': 'idle',
      'last_error': null,
      'last_synced_at': null,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    const excluded = {
      'cloud_sync_state',
      'cloud_tenant_cache',
      'app_users',
      'audit_log',
    };
    for (final row in tableRows) {
      final table = row['name']?.toString();
      if (table == null || excluded.contains(table) ||
          !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table)) continue;
      for (final operation in const ['INSERT', 'UPDATE', 'DELETE']) {
        final suffix = operation.toLowerCase();
        final trigger = 'trg_cloud_revision_${table}_$suffix';
        await database.execute('''
          CREATE TRIGGER IF NOT EXISTS $trigger
          AFTER $operation ON $table
          BEGIN
            UPDATE cloud_sync_state
            SET local_revision = local_revision + 1,
                updated_at = datetime('now')
            WHERE id = 'main';
          END
        ''');
      }
    }
  }

  Future<void> _ensureFinancialInvariantTriggers(Database database) async {
    final statements = <String>[
      '''CREATE TRIGGER IF NOT EXISTS trg_payments_amount_insert BEFORE INSERT ON payments WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'payment amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_payments_amount_update BEFORE UPDATE OF amount ON payments WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'payment amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_allocations_amount_insert BEFORE INSERT ON payment_allocations WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'allocation amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_allocations_amount_update BEFORE UPDATE OF amount ON payment_allocations WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'allocation amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_dues_amounts_insert BEFORE INSERT ON dues WHEN NEW.amount_due<0 OR NEW.amount_paid<0 OR NEW.amount_paid>NEW.amount_due BEGIN SELECT RAISE(ABORT,'invalid due amounts'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_dues_amounts_update BEFORE UPDATE OF amount_due,amount_paid ON dues WHEN NEW.amount_due<0 OR NEW.amount_paid<0 OR NEW.amount_paid>NEW.amount_due BEGIN SELECT RAISE(ABORT,'invalid due amounts'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_expenses_amount_insert BEFORE INSERT ON expenses WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'expense amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_expenses_amount_update BEFORE UPDATE OF amount ON expenses WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'expense amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_supplier_payments_amount_insert BEFORE INSERT ON supplier_payments WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'supplier payment amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_supplier_payments_amount_update BEFORE UPDATE OF amount ON supplier_payments WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'supplier payment amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_refunds_amount_insert BEFORE INSERT ON payment_refunds WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'refund amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_refunds_amount_update BEFORE UPDATE OF amount ON payment_refunds WHEN NEW.amount<=0 BEGIN SELECT RAISE(ABORT,'refund amount must be positive'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_asset_disposals_insert BEFORE INSERT ON asset_disposals WHEN NEW.sale_amount<0 OR (NEW.disposal_type='sale' AND (NEW.sale_amount<=0 OR NEW.cash_account_id IS NULL OR trim(NEW.cash_account_id)='')) BEGIN SELECT RAISE(ABORT,'invalid asset disposal sale'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_asset_disposals_update BEFORE UPDATE OF sale_amount,disposal_type,cash_account_id ON asset_disposals WHEN NEW.sale_amount<0 OR (NEW.disposal_type='sale' AND (NEW.sale_amount<=0 OR NEW.cash_account_id IS NULL OR trim(NEW.cash_account_id)='')) BEGIN SELECT RAISE(ABORT,'invalid asset disposal sale'); END''',
    ];
    for (final statement in statements) {
      await database.execute(statement);
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.transaction((txn) async {
      for (final statement in _schema) {
        await txn.execute(statement);
      }
    });
  }

  Future<void> _seedDefaults(Database db) async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    final cycleCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM cycles'),
        ) ??
        0;
    if (cycleCount == 0) {
      const names = [
        'Maternelle',
        'Préscolaire',
        'Primaire',
        'Collège',
        'Lycée Général',
        'Lycée Technique',
      ];
      for (var i = 0; i < names.length; i++) {
        await db.insert('cycles', {
          'id': uuid.v4(),
          'name': names[i],
          'sort_order': i,
          'active': 1,
        });
      }
    }

    final documentRequirementCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM document_requirements')) ?? 0;
    if (documentRequirementCount == 0) {
      for (final item in const [
        ['Acte de naissance', 10],
        ['Photo d’identité', 20],
        ['Ancien bulletin', 30],
      ]) {
        await db.insert('document_requirements', {
          'id': uuid.v4(), 'name': item[0], 'required': 1, 'active': 1,
          'sort_order': item[1], 'created_at': now, 'updated_at': now,
        });
      }
    }

    final expenseCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM expense_categories'),
        ) ??
        0;
    if (expenseCount == 0) {
      for (final name in const [
        'Salaires du personnel',
        'Fournitures',
        'Entretien',
        'Électricité / Eau',
        'Transport',
        'Imprévus',
      ]) {
        await db.insert('expense_categories', {
          'id': uuid.v4(),
          'name': name,
          'active': 1,
        });
      }
    }

    for (final m in const [
      ['cash','Espèces','0','cash'],
      ['mobile','Mobile Money','1','mobile'],
      ['transfer','Virement','1','bank'],
    ]) {
      await db.insert(
        'payment_methods',
        {
          'id': m[0],
          'name': m[1],
          'requires_reference': int.parse(m[2]),
          'account_type': m[3],
          'active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final a in const [
      ['main_cash','Caisse principale','cash'], ['mobile_money','Mobile Money','mobile'], ['bank','Compte bancaire','bank']
    ]) {
      await db.insert('cash_accounts', {'id':a[0], 'name':a[1], 'type':a[2], 'opening_balance':0, 'active':1, 'created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await db.insert(
      'app_settings',
      {'key': 'currency', 'value': 'XAF', 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _seedHrDefaults(db);
    await _seedAssetDefaults(db);
    await _seedAccountingDefaults(db);
  }

  Future<void> _seedAccountingDefaults(Database db) async {
    for (final account in const [
      ['401100','Fournisseurs — dettes','4','liability'],
      ['411100','Familles et élèves — créances','4','asset'],
      ['421100','Personnel — rémunérations dues','4','liability'],
      ['421200','Personnel — avances et acomptes','4','asset'],
      ['521000','Banques','5','asset'],
      ['531000','Mobile Money','5','asset'],
      ['571000','Caisse espèces','5','asset'],
      ['601000','Achats et fournitures','6','expense'],
      ['605000','Eau, électricité et énergie','6','expense'],
      ['624000','Entretien et réparations','6','expense'],
      ['625000','Transport et déplacements','6','expense'],
      ['628000','Autres services extérieurs','6','expense'],
      ['658000','Charges diverses de gestion','6','expense'],
      ['661000','Rémunérations du personnel','6','expense'],
      ['706100','Frais de scolarité et services scolaires','7','revenue'],
      ['775100','Produits de cession d’immobilisations','7','revenue'],
    ]) {
      await db.insert('accounting_accounts', {
        'code': account[0], 'name': account[1], 'account_class': int.parse(account[2]),
        'account_type': account[3], 'active': 1, 'is_system': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final now = DateTime.now().toIso8601String();
    for (final setting in const [
      ['student_receivable_account','411100'],
      ['school_revenue_account','706100'],
      ['supplier_payable_account','401100'],
      ['default_cash_account','571000'],
      ['default_bank_account','521000'],
      ['default_mobile_account','531000'],
    ]) {
      await db.insert('accounting_settings', {
        'key': setting[0], 'value': setting[1], 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _seedHrDefaults(Database db) async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();
    final departmentCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM hr_departments')) ?? 0;
    if (departmentCount == 0) {
      for (final name in const ['Administration', 'Enseignement', 'Comptabilité', 'Logistique', 'Sécurité']) {
        await db.insert('hr_departments', {'id': uuid.v4(), 'name': name, 'active': 1, 'created_at': now, 'updated_at': now});
      }
    }
    final positionCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM hr_positions')) ?? 0;
    if (positionCount == 0) {
      final departments = await db.query('hr_departments', columns: ['id','name']);
      final byName = {for (final row in departments) row['name'].toString(): row['id'].toString()};
      for (final item in const [
        ['Directeur / Responsable administratif','Administration'], ['Secrétaire','Administration'], ['Comptable','Comptabilité'],
        ['Enseignant','Enseignement'], ['Surveillant','Enseignement'], ['Agent d’entretien','Logistique'],
        ['Chauffeur','Logistique'], ['Gardien','Sécurité'],
      ]) {
        await db.insert('hr_positions', {'id': uuid.v4(), 'name': item[0], 'department_id': byName[item[1]], 'active': 1, 'created_at': now, 'updated_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    final leaveCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM leave_types')) ?? 0;
    if (leaveCount == 0) {
      for (final item in const [
        ['Congé annuel', 1, 1], ['Maladie', 1, 1], ['Maternité', 1, 1], ['Paternité', 1, 1],
        ['Permission exceptionnelle', 1, 1], ['Mission', 1, 1], ['Absence non justifiée', 0, 0],
      ]) {
        await db.insert('leave_types', {'id': uuid.v4(), 'name': item[0], 'paid': item[1], 'requires_proof': item[2], 'active': 1});
      }
    }
  }

  Future<void> _seedAssetDefaults(Database db) async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();
    final categoryCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM asset_categories')) ?? 0;
    if (categoryCount == 0) {
      for (final item in const [
        ['Informatique', 'Matériel informatique et numérique'],
        ['Mobilier', 'Tables, chaises, armoires et bureaux'],
        ['Matériel pédagogique', 'Équipements utilisés pour l’enseignement'],
        ['Électricité / Énergie', 'Groupes, onduleurs et équipements électriques'],
        ['Véhicules', 'Véhicules et moyens roulants'],
        ['Bâtiments / Immobilier', 'Biens immobiliers et aménagements'],
        ['Sécurité', 'Équipements de sûreté et de sécurité'],
      ]) {
        await db.insert('asset_categories', {
          'id': uuid.v4(), 'name': item[0], 'description': item[1],
          'active': 1, 'created_at': now, 'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    final locationCount = firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM asset_locations')) ?? 0;
    if (locationCount == 0) {
      await db.insert('asset_locations', {
        'id': uuid.v4(), 'name': 'Site principal', 'type': 'site',
        'parent_id': null, 'description': 'Localisation principale de l’établissement',
        'active': 1, 'created_at': now, 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static const _accountingSchema = <String>[
    '''CREATE TABLE IF NOT EXISTS accounting_accounts(
      code TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      account_class INTEGER NOT NULL,
      account_type TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      is_system INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE IF NOT EXISTS accounting_entries(
      id TEXT PRIMARY KEY,
      journal_code TEXT NOT NULL,
      entry_date TEXT NOT NULL,
      reference TEXT NOT NULL,
      description TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted',
      created_at TEXT NOT NULL,
      UNIQUE(source_type, source_id)
    )''',
    '''CREATE TABLE IF NOT EXISTS accounting_entry_lines(
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL,
      account_code TEXT NOT NULL,
      label TEXT,
      debit INTEGER NOT NULL DEFAULT 0,
      credit INTEGER NOT NULL DEFAULT 0,
      line_order INTEGER NOT NULL DEFAULT 0,
      CHECK(debit >= 0 AND credit >= 0 AND ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))),
      FOREIGN KEY(entry_id) REFERENCES accounting_entries(id) ON DELETE CASCADE,
      FOREIGN KEY(account_code) REFERENCES accounting_accounts(code)
    )''',
    '''CREATE INDEX IF NOT EXISTS idx_accounting_entries_date ON accounting_entries(entry_date, journal_code)''',
    '''CREATE INDEX IF NOT EXISTS idx_accounting_entries_source ON accounting_entries(source_type, source_id)''',
    '''CREATE INDEX IF NOT EXISTS idx_accounting_lines_account ON accounting_entry_lines(account_code, entry_id)''',
  ];

  static const _accountingPhase2Schema = <String>[
    '''CREATE TABLE IF NOT EXISTS accounting_settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS supplier_invoices(
      id TEXT PRIMARY KEY,
      invoice_number TEXT NOT NULL UNIQUE,
      supplier_name TEXT NOT NULL,
      invoice_date TEXT NOT NULL,
      due_date TEXT,
      description TEXT NOT NULL,
      expense_account_code TEXT NOT NULL,
      amount INTEGER NOT NULL,
      amount_paid INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(expense_account_code) REFERENCES accounting_accounts(code)
    )''',
    '''CREATE TABLE IF NOT EXISTS supplier_payments(
      id TEXT PRIMARY KEY,
      supplier_invoice_id TEXT NOT NULL,
      cash_account_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      paid_at TEXT NOT NULL,
      reference TEXT,
      note TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(supplier_invoice_id) REFERENCES supplier_invoices(id),
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS bank_reconciliations(
      id TEXT PRIMARY KEY,
      cash_account_id TEXT NOT NULL,
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      statement_balance INTEGER NOT NULL,
      book_balance INTEGER NOT NULL,
      difference INTEGER NOT NULL,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'draft',
      created_at TEXT NOT NULL,
      completed_at TEXT,
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS bank_reconciliation_items(
      id TEXT PRIMARY KEY,
      reconciliation_id TEXT NOT NULL,
      accounting_entry_id TEXT NOT NULL,
      cleared INTEGER NOT NULL DEFAULT 0,
      statement_reference TEXT,
      note TEXT,
      UNIQUE(reconciliation_id, accounting_entry_id),
      FOREIGN KEY(reconciliation_id) REFERENCES bank_reconciliations(id) ON DELETE CASCADE,
      FOREIGN KEY(accounting_entry_id) REFERENCES accounting_entries(id)
    )''',
    '''CREATE INDEX IF NOT EXISTS idx_supplier_invoices_due ON supplier_invoices(status,due_date)''',
    '''CREATE INDEX IF NOT EXISTS idx_supplier_payments_invoice ON supplier_payments(supplier_invoice_id,paid_at)''',
    '''CREATE INDEX IF NOT EXISTS idx_bank_reconciliations_account ON bank_reconciliations(cash_account_id,period_end)''',
  ];

  static const _assetSchema = <String>[
    '''CREATE TABLE IF NOT EXISTS asset_categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      description TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_locations(
      id TEXT PRIMARY KEY,
      parent_id TEXT,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'room',
      description TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(parent_id) REFERENCES asset_locations(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS assets(
      id TEXT PRIMARY KEY,
      asset_number TEXT NOT NULL UNIQUE,
      category_id TEXT NOT NULL,
      name TEXT NOT NULL,
      brand TEXT,
      model TEXT,
      serial_number TEXT,
      acquisition_date TEXT,
      acquisition_value INTEGER NOT NULL DEFAULT 0,
      acquisition_method TEXT NOT NULL DEFAULT 'purchase',
      supplier TEXT,
      current_location_id TEXT,
      current_employee_id TEXT,
      condition TEXT NOT NULL DEFAULT 'good',
      status TEXT NOT NULL DEFAULT 'in_service',
      warranty_end_date TEXT,
      photo_path TEXT,
      purchase_proof_path TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(category_id) REFERENCES asset_categories(id),
      FOREIGN KEY(current_location_id) REFERENCES asset_locations(id),
      FOREIGN KEY(current_employee_id) REFERENCES employees(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_assignments(
      id TEXT PRIMARY KEY,
      asset_id TEXT NOT NULL,
      employee_id TEXT,
      location_id TEXT,
      assigned_at TEXT NOT NULL,
      returned_at TEXT,
      condition_at_assignment TEXT,
      condition_at_return TEXT,
      notes TEXT,
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE,
      FOREIGN KEY(employee_id) REFERENCES employees(id),
      FOREIGN KEY(location_id) REFERENCES asset_locations(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_movements(
      id TEXT PRIMARY KEY,
      asset_id TEXT NOT NULL,
      movement_type TEXT NOT NULL,
      from_location_id TEXT,
      to_location_id TEXT,
      from_employee_id TEXT,
      to_employee_id TEXT,
      moved_at TEXT NOT NULL,
      reason TEXT,
      condition_after TEXT,
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE,
      FOREIGN KEY(from_location_id) REFERENCES asset_locations(id),
      FOREIGN KEY(to_location_id) REFERENCES asset_locations(id),
      FOREIGN KEY(from_employee_id) REFERENCES employees(id),
      FOREIGN KEY(to_employee_id) REFERENCES employees(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_maintenance(
      id TEXT PRIMARY KEY,
      asset_id TEXT NOT NULL,
      maintenance_type TEXT NOT NULL DEFAULT 'corrective',
      problem TEXT,
      diagnosis TEXT,
      provider TEXT,
      cost INTEGER NOT NULL DEFAULT 0,
      started_at TEXT NOT NULL,
      completed_at TEXT,
      next_maintenance_at TEXT,
      expense_id TEXT,
      proof_path TEXT,
      status TEXT NOT NULL DEFAULT 'planned',
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE,
      FOREIGN KEY(expense_id) REFERENCES expenses(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_inventory_sessions(
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      started_at TEXT NOT NULL,
      completed_at TEXT,
      location_id TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      notes TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(location_id) REFERENCES asset_locations(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_inventory_items(
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      asset_id TEXT NOT NULL,
      result TEXT NOT NULL DEFAULT 'not_checked',
      observed_location_id TEXT,
      observed_condition TEXT,
      note TEXT,
      checked_at TEXT,
      checked_by TEXT,
      UNIQUE(session_id, asset_id),
      FOREIGN KEY(session_id) REFERENCES asset_inventory_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE,
      FOREIGN KEY(observed_location_id) REFERENCES asset_locations(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_documents(
      id TEXT PRIMARY KEY,
      asset_id TEXT NOT NULL,
      document_type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      added_at TEXT NOT NULL,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS asset_disposals(
      id TEXT PRIMARY KEY,
      asset_id TEXT NOT NULL UNIQUE,
      disposal_type TEXT NOT NULL,
      disposal_date TEXT NOT NULL,
      sale_amount INTEGER NOT NULL DEFAULT 0,
      cash_account_id TEXT,
      reference TEXT,
      reason TEXT,
      document_path TEXT,
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE,
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE INDEX IF NOT EXISTS idx_assets_category ON assets(category_id, status)''',
    '''CREATE INDEX IF NOT EXISTS idx_assets_location ON assets(current_location_id, status)''',
    '''CREATE INDEX IF NOT EXISTS idx_assets_employee ON assets(current_employee_id, status)''',
    '''CREATE INDEX IF NOT EXISTS idx_asset_maintenance_next ON asset_maintenance(status, next_maintenance_at)''',
    '''CREATE INDEX IF NOT EXISTS idx_asset_movements_asset ON asset_movements(asset_id, moved_at DESC)''',
    '''CREATE INDEX IF NOT EXISTS idx_asset_inventory_session ON asset_inventory_items(session_id, result)''',
  ];

  static const _hrSchema = <String>[
    '''CREATE TABLE IF NOT EXISTS hr_departments(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      description TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS hr_positions(
      id TEXT PRIMARY KEY,
      department_id TEXT,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      description TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(department_id) REFERENCES hr_departments(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS employees(
      id TEXT PRIMARY KEY,
      employee_number TEXT NOT NULL UNIQUE,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      gender TEXT,
      birth_date TEXT,
      birth_place TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      photo_path TEXT,
      id_number TEXT,
      social_security_number TEXT,
      emergency_contact_name TEXT,
      emergency_contact_phone TEXT,
      hire_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS employee_status_history(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      old_status TEXT,
      new_status TEXT NOT NULL,
      effective_at TEXT NOT NULL,
      reason TEXT,
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS employee_assignments(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      position_id TEXT NOT NULL,
      school_year_id TEXT,
      start_date TEXT NOT NULL,
      end_date TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY(position_id) REFERENCES hr_positions(id),
      FOREIGN KEY(school_year_id) REFERENCES school_years(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS employment_contracts(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      contract_type TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT,
      base_salary INTEGER NOT NULL DEFAULT 0,
      position_id TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      document_path TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY(position_id) REFERENCES hr_positions(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS attendance_records(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      attendance_date TEXT NOT NULL,
      status TEXT NOT NULL,
      arrival_time TEXT,
      departure_time TEXT,
      late_minutes INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(employee_id, attendance_date),
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS leave_types(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      paid INTEGER NOT NULL DEFAULT 1,
      requires_proof INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS leave_requests(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      leave_type_id TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      days INTEGER NOT NULL,
      reason TEXT,
      proof_path TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      requested_at TEXT NOT NULL,
      decided_by TEXT,
      decided_at TEXT,
      decision_note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY(leave_type_id) REFERENCES leave_types(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS salary_components(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      kind TEXT NOT NULL,
      calculation_type TEXT NOT NULL DEFAULT 'fixed',
      value INTEGER NOT NULL DEFAULT 0,
      taxable INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS employee_salary_components(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      component_id TEXT NOT NULL,
      value INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY(component_id) REFERENCES salary_components(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS payroll_periods(
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      created_by TEXT,
      validated_by TEXT,
      validated_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS payroll_entries(
      id TEXT PRIMARY KEY,
      period_id TEXT NOT NULL,
      employee_id TEXT NOT NULL,
      base_salary INTEGER NOT NULL DEFAULT 0,
      gross_salary INTEGER NOT NULL DEFAULT 0,
      total_deductions INTEGER NOT NULL DEFAULT 0,
      net_salary INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'draft',
      payment_method TEXT,
      cash_account_id TEXT,
      payment_reference TEXT,
      paid_at TEXT,
      expense_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(period_id, employee_id),
      FOREIGN KEY(period_id) REFERENCES payroll_periods(id) ON DELETE CASCADE,
      FOREIGN KEY(employee_id) REFERENCES employees(id),
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id),
      FOREIGN KEY(expense_id) REFERENCES expenses(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS payroll_items(
      id TEXT PRIMARY KEY,
      payroll_entry_id TEXT NOT NULL,
      label TEXT NOT NULL,
      kind TEXT NOT NULL,
      amount INTEGER NOT NULL,
      source TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(payroll_entry_id) REFERENCES payroll_entries(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS salary_advances(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      balance INTEGER NOT NULL,
      granted_at TEXT NOT NULL,
      payment_method TEXT,
      cash_account_id TEXT,
      reference TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      note TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id),
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS salary_advance_repayments(
      id TEXT PRIMARY KEY,
      advance_id TEXT NOT NULL,
      payroll_entry_id TEXT,
      amount INTEGER NOT NULL,
      repaid_at TEXT NOT NULL,
      FOREIGN KEY(advance_id) REFERENCES salary_advances(id) ON DELETE CASCADE,
      FOREIGN KEY(payroll_entry_id) REFERENCES payroll_entries(id)
    )''',
    '''CREATE TABLE IF NOT EXISTS employee_documents(
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      document_type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      document_number TEXT,
      issued_at TEXT,
      expires_at TEXT,
      added_at TEXT NOT NULL,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE CASCADE
    )''',
    '''CREATE INDEX IF NOT EXISTS idx_employees_status ON employees(status,last_name,first_name)''',
    '''CREATE INDEX IF NOT EXISTS idx_assignments_employee ON employee_assignments(employee_id,start_date DESC)''',
    '''CREATE INDEX IF NOT EXISTS idx_contracts_employee ON employment_contracts(employee_id,start_date DESC)''',
    '''CREATE INDEX IF NOT EXISTS idx_contracts_expiry ON employment_contracts(status,end_date)''',
    '''CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance_records(attendance_date,status)''',
    '''CREATE INDEX IF NOT EXISTS idx_leave_dates ON leave_requests(status,start_date,end_date)''',
    '''CREATE INDEX IF NOT EXISTS idx_payroll_period ON payroll_entries(period_id,status)''',
    '''CREATE INDEX IF NOT EXISTS idx_employee_documents ON employee_documents(employee_id,document_type)''',
    '''CREATE INDEX IF NOT EXISTS idx_salary_advances ON salary_advances(employee_id,status,balance)''',
  ];

  static const _schema = <String>[
    '''CREATE TABLE establishments(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      logo_path TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      approval_number TEXT,
      currency TEXT NOT NULL DEFAULT 'XAF',
      school_year_label TEXT NOT NULL,
      school_year_start TEXT NOT NULL,
      school_year_end TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE cycles(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE classrooms(
      id TEXT PRIMARY KEY,
      cycle_id TEXT NOT NULL,
      name TEXT NOT NULL,
      capacity INTEGER,
      active INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY(cycle_id) REFERENCES cycles(id)
    )''',
    '''CREATE TABLE families(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      primary_phone TEXT,
      secondary_phone TEXT,
      address TEXT,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE students(
      id TEXT PRIMARY KEY,
      family_id TEXT,
      classroom_id TEXT NOT NULL,
      registration_number TEXT UNIQUE,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      gender TEXT,
      birth_date TEXT,
      birth_place TEXT,
      guardian_name TEXT,
      guardian_phone TEXT,
      photo_path TEXT,
      nationality TEXT,
      address TEXT,
      origin_school TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      enrollment_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(family_id) REFERENCES families(id),
      FOREIGN KEY(classroom_id) REFERENCES classrooms(id)
    )''',
    '''CREATE TABLE student_status_history(
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      old_status TEXT,
      new_status TEXT NOT NULL,
      changed_at TEXT NOT NULL,
      note TEXT,
      FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE student_documents(
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      document_type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      is_required INTEGER NOT NULL DEFAULT 0,
      verification_code TEXT UNIQUE,
      verification_status TEXT NOT NULL DEFAULT 'valid',
      revoked_at TEXT,
      added_at TEXT NOT NULL,
      FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE fee_categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      periodicity TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE fee_targets(
      fee_id TEXT NOT NULL,
      cycle_id TEXT,
      classroom_id TEXT,
      PRIMARY KEY(fee_id, cycle_id, classroom_id),
      FOREIGN KEY(fee_id) REFERENCES fee_categories(id) ON DELETE CASCADE,
      FOREIGN KEY(cycle_id) REFERENCES cycles(id),
      FOREIGN KEY(classroom_id) REFERENCES classrooms(id)
    )''',
    '''CREATE TABLE fee_grid(
      id TEXT PRIMARY KEY,
      fee_id TEXT NOT NULL,
      cycle_id TEXT,
      classroom_id TEXT,
      amount INTEGER NOT NULL,
      valid_from TEXT NOT NULL,
      valid_to TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(fee_id) REFERENCES fee_categories(id),
      FOREIGN KEY(cycle_id) REFERENCES cycles(id),
      FOREIGN KEY(classroom_id) REFERENCES classrooms(id)
    )''',
    '''CREATE TABLE packages(
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      family_id TEXT,
      student_id TEXT,
      fee_id TEXT,
      amount INTEGER NOT NULL,
      reason TEXT,
      valid_from TEXT NOT NULL,
      valid_to TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      FOREIGN KEY(family_id) REFERENCES families(id),
      FOREIGN KEY(student_id) REFERENCES students(id),
      FOREIGN KEY(fee_id) REFERENCES fee_categories(id)
    )''',
    '''CREATE TABLE dues(
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      family_id TEXT,
      fee_id TEXT NOT NULL,
      package_id TEXT,
      school_year_id TEXT,
      billing_batch_id TEXT,
      period_key TEXT NOT NULL,
      amount_due INTEGER NOT NULL,
      amount_paid INTEGER NOT NULL DEFAULT 0,
      due_date TEXT,
      status TEXT NOT NULL DEFAULT 'unpaid',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(student_id, fee_id, period_key),
      FOREIGN KEY(student_id) REFERENCES students(id),
      FOREIGN KEY(family_id) REFERENCES families(id),
      FOREIGN KEY(fee_id) REFERENCES fee_categories(id),
      FOREIGN KEY(package_id) REFERENCES packages(id),
      FOREIGN KEY(school_year_id) REFERENCES school_years(id)
    )''',
    '''CREATE TABLE payments(
      id TEXT PRIMARY KEY,
      receipt_number TEXT NOT NULL UNIQUE,
      student_id TEXT,
      family_id TEXT,
      school_year_id TEXT,
      amount INTEGER NOT NULL,
      payment_method TEXT NOT NULL,
      paid_at TEXT NOT NULL,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'posted',
      cancel_reason TEXT,
      cancelled_at TEXT,
      cash_account_id TEXT,
      transaction_reference TEXT,
      payer_phone TEXT,
      payment_operator TEXT,
      credit_amount INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY(student_id) REFERENCES students(id),
      FOREIGN KEY(family_id) REFERENCES families(id),
      FOREIGN KEY(school_year_id) REFERENCES school_years(id)
    )''',
    '''CREATE TABLE payment_allocations(
      payment_id TEXT NOT NULL,
      due_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      PRIMARY KEY(payment_id, due_id),
      FOREIGN KEY(payment_id) REFERENCES payments(id),
      FOREIGN KEY(due_id) REFERENCES dues(id)
    )''',
    '''CREATE TABLE expense_categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE expenses(
      id TEXT PRIMARY KEY,
      category_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      spent_at TEXT NOT NULL,
      description TEXT,
      proof_path TEXT,
      expense_number TEXT,
      beneficiary TEXT,
      payment_method TEXT,
      cash_account_id TEXT,
      external_reference TEXT,
      approval_status TEXT NOT NULL DEFAULT 'approved',
      submitted_by TEXT,
      submitted_at TEXT,
      reviewed_by TEXT,
      reviewed_at TEXT,
      approval_note TEXT,
      status TEXT NOT NULL DEFAULT 'posted',
      created_at TEXT NOT NULL,
      FOREIGN KEY(category_id) REFERENCES expense_categories(id)
    )''',
    '''CREATE INDEX idx_expenses_approval ON expenses(approval_status, status, spent_at)''',
    '''CREATE TABLE recurring_expense_templates(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      beneficiary TEXT,
      description TEXT,
      payment_method TEXT,
      cash_account_id TEXT,
      frequency TEXT NOT NULL DEFAULT 'monthly',
      day_of_month INTEGER NOT NULL DEFAULT 1,
      next_due_at TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(category_id) REFERENCES expense_categories(id),
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE INDEX idx_recurring_expense_due ON recurring_expense_templates(active, next_due_at)''',
    '''CREATE TABLE school_years(
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE UNIQUE INDEX idx_school_year_active ON school_years(is_active) WHERE is_active = 1''',
    '''CREATE TABLE student_enrollments(
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      school_year_id TEXT NOT NULL,
      classroom_id TEXT NOT NULL,
      enrollment_type TEXT NOT NULL DEFAULT 'new',
      status TEXT NOT NULL DEFAULT 'active',
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      origin_establishment TEXT,
      observations TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(student_id, school_year_id),
      FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE,
      FOREIGN KEY(school_year_id) REFERENCES school_years(id),
      FOREIGN KEY(classroom_id) REFERENCES classrooms(id)
    )''',
    '''CREATE INDEX idx_enrollments_year ON student_enrollments(school_year_id)''',
    '''CREATE INDEX idx_enrollments_student ON student_enrollments(student_id)''',
    '''CREATE INDEX idx_enrollments_classroom ON student_enrollments(classroom_id)''',
    '''CREATE TABLE student_class_movements(
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      school_year_id TEXT NOT NULL,
      from_classroom_id TEXT,
      to_classroom_id TEXT NOT NULL,
      effective_at TEXT NOT NULL,
      reason TEXT,
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE,
      FOREIGN KEY(school_year_id) REFERENCES school_years(id),
      FOREIGN KEY(from_classroom_id) REFERENCES classrooms(id),
      FOREIGN KEY(to_classroom_id) REFERENCES classrooms(id)
    )''',
    '''CREATE INDEX idx_student_class_movements_student ON student_class_movements(student_id,effective_at DESC)''',
    '''CREATE TABLE app_users(
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL COLLATE NOCASE UNIQUE,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      pin_salt TEXT NOT NULL,
      pin_algorithm TEXT NOT NULL DEFAULT 'pbkdf2-sha256',
      pin_iterations INTEGER NOT NULL DEFAULT 120000,
      recovery_code_hash TEXT,
      recovery_code_salt TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      failed_attempts INTEGER NOT NULL DEFAULT 0,
      locked_until TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE INDEX idx_app_users_active ON app_users(active)''',
    '''CREATE TABLE cloud_tenant_cache(
      organization_id TEXT PRIMARY KEY,
      organization_code TEXT NOT NULL,
      organization_name TEXT NOT NULL,
      cloud_user_id TEXT NOT NULL,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('admin','manager')),
      username TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      must_change_password INTEGER NOT NULL DEFAULT 0,
      backup_secret TEXT,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE cloud_sync_state(
      id TEXT PRIMARY KEY,
      local_revision INTEGER NOT NULL DEFAULT 0,
      last_uploaded_local_revision INTEGER NOT NULL DEFAULT 0,
      known_remote_revision INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'idle',
      last_error TEXT,
      last_synced_at TEXT,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE payment_methods(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, requires_reference INTEGER NOT NULL DEFAULT 0, account_type TEXT NOT NULL DEFAULT 'cash', active INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE cash_accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, type TEXT NOT NULL, opening_balance INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)''',
    '''CREATE INDEX idx_payment_methods_active ON payment_methods(active, name)''',
    '''CREATE INDEX idx_cash_accounts_active ON cash_accounts(active, type, name)''',
    '''CREATE TABLE payment_refunds(
      id TEXT PRIMARY KEY,
      payment_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      reason TEXT NOT NULL,
      refunded_at TEXT NOT NULL,
      operator_id TEXT,
      payment_method TEXT,
      cash_account_id TEXT,
      transaction_reference TEXT,
      FOREIGN KEY(payment_id) REFERENCES payments(id),
      FOREIGN KEY(cash_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE TABLE payer_credits(id TEXT PRIMARY KEY, student_id TEXT, family_id TEXT, amount INTEGER NOT NULL, source_payment_id TEXT, status TEXT NOT NULL DEFAULT 'available', created_at TEXT NOT NULL)''',
    '''CREATE TABLE payer_credit_allocations(
      id TEXT PRIMARY KEY,
      credit_id TEXT NOT NULL,
      due_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      applied_at TEXT NOT NULL,
      operator_id TEXT,
      FOREIGN KEY(credit_id) REFERENCES payer_credits(id),
      FOREIGN KEY(due_id) REFERENCES dues(id)
    )''',
    '''CREATE TABLE cash_sessions(id TEXT PRIMARY KEY, cash_account_id TEXT NOT NULL, opened_by TEXT, opened_at TEXT NOT NULL, opening_amount INTEGER NOT NULL DEFAULT 0, closed_by TEXT, closed_at TEXT, theoretical_amount INTEGER, physical_amount INTEGER, variance INTEGER, status TEXT NOT NULL DEFAULT 'open')''',
    '''CREATE TABLE cash_transfers(
      id TEXT PRIMARY KEY,
      from_account_id TEXT NOT NULL,
      to_account_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      transferred_at TEXT NOT NULL,
      reference TEXT,
      note TEXT,
      operator_id TEXT,
      status TEXT NOT NULL DEFAULT 'posted',
      created_at TEXT NOT NULL,
      FOREIGN KEY(from_account_id) REFERENCES cash_accounts(id),
      FOREIGN KEY(to_account_id) REFERENCES cash_accounts(id)
    )''',
    '''CREATE TABLE billing_batches(
      id TEXT PRIMARY KEY,
      school_year_id TEXT NOT NULL,
      period_key TEXT NOT NULL,
      periodicity TEXT NOT NULL,
      reference_date TEXT NOT NULL,
      due_date TEXT NOT NULL,
      generated_count INTEGER NOT NULL DEFAULT 0,
      total_amount INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL,
      cancelled_at TEXT,
      FOREIGN KEY(school_year_id) REFERENCES school_years(id)
    )''',
    '''CREATE INDEX idx_billing_batches_year ON billing_batches(school_year_id, created_at)''',
    '''CREATE INDEX idx_dues_billing_batch ON dues(billing_batch_id)''',
    '''CREATE TABLE recovery_actions(
      id TEXT PRIMARY KEY,
      due_id TEXT NOT NULL,
      action_type TEXT NOT NULL,
      channel TEXT,
      contact_name TEXT,
      outcome TEXT,
      promise_amount INTEGER,
      promise_date TEXT,
      next_follow_up_at TEXT,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      operator_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(due_id) REFERENCES dues(id) ON DELETE CASCADE
    )''',
    '''CREATE INDEX idx_recovery_due ON recovery_actions(due_id, created_at)''',
    '''CREATE INDEX idx_recovery_followup ON recovery_actions(status, next_follow_up_at)''',
    '''CREATE TABLE document_requirements(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      description TEXT,
      required INTEGER NOT NULL DEFAULT 1,
      active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE INDEX idx_document_requirements_active ON document_requirements(active, sort_order, name)''',
    '''CREATE TABLE student_guardians(id TEXT PRIMARY KEY, student_id TEXT NOT NULL, name TEXT NOT NULL, phone TEXT, relationship TEXT NOT NULL DEFAULT 'tuteur', is_primary INTEGER NOT NULL DEFAULT 0, is_financial INTEGER NOT NULL DEFAULT 0, is_emergency INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE)''',
    ..._hrSchema,
    ..._assetSchema,
    ..._accountingSchema,
    ..._accountingPhase2Schema,
    '''CREATE TABLE alerts(
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      target_type TEXT,
      target_id TEXT,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      due_at TEXT,
      is_read INTEGER NOT NULL DEFAULT 0,
      severity TEXT NOT NULL DEFAULT 'warning',
      status TEXT NOT NULL DEFAULT 'new',
      notification_sent INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE audit_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      action TEXT NOT NULL,
      old_value TEXT,
      new_value TEXT,
      operator_name TEXT,
      operator_id TEXT,
      operator_role TEXT,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE app_settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE INDEX idx_students_classroom ON students(classroom_id)''',
    '''CREATE INDEX idx_students_family ON students(family_id)''',
    '''CREATE INDEX idx_students_status ON students(status)''',
    '''CREATE INDEX idx_dues_status ON dues(status)''',
    '''CREATE INDEX idx_dues_school_year ON dues(school_year_id, status, due_date)''',
    '''CREATE INDEX idx_packages_fee ON packages(fee_id)''',
    '''CREATE INDEX idx_dues_student ON dues(student_id)''',
    '''CREATE INDEX idx_payments_date ON payments(paid_at)''',
    '''CREATE INDEX idx_payments_school_year ON payments(school_year_id, status, paid_at)''',
    '''CREATE INDEX idx_expenses_date ON expenses(spent_at)''',
    '''CREATE INDEX idx_credit_alloc_due ON payer_credit_allocations(due_id)''',
    '''CREATE INDEX idx_credit_alloc_credit ON payer_credit_allocations(credit_id)''',
    '''CREATE INDEX idx_cash_transfers_date ON cash_transfers(transferred_at)''',
    '''CREATE INDEX idx_cash_transfers_from ON cash_transfers(from_account_id, transferred_at)''',
    '''CREATE INDEX idx_cash_transfers_to ON cash_transfers(to_account_id, transferred_at)''',
    '''CREATE INDEX idx_audit_created ON audit_log(created_at DESC)''',
    '''CREATE INDEX idx_audit_entity ON audit_log(entity_type, action, created_at DESC)''',
    '''CREATE INDEX idx_payments_receipt ON payments(receipt_number)''',
    '''CREATE INDEX idx_expenses_number ON expenses(expense_number)''',
    '''CREATE INDEX idx_payment_refunds_date ON payment_refunds(refunded_at)''',
    '''CREATE INDEX idx_payment_refunds_account ON payment_refunds(cash_account_id, refunded_at)''',
  ];
}
