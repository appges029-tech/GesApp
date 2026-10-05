import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/db/app_database.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/session/business_write_guard.dart';
import '../../services/backup_service.dart';
import '../../services/automatic_backup_service.dart';
import '../../services/json_data_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _service = BackupService();
  final _jsonService = JsonDataService();
  bool _busy = false;
  String? _lastMessage;
  bool _autoBackupEnabled = true;
  int _autoBackupDays = 3;
  String? _autoBackupLast;

  @override
  void initState() {
    super.initState();
    _loadAutoBackup();
  }

  Future<void> _loadAutoBackup() async {
    final data = await AutomaticBackupService.settings();
    if (!mounted) return;
    setState(() {
      _autoBackupEnabled = data['enabled'] == true;
      _autoBackupDays = data['interval_days'] as int? ?? 3;
      _autoBackupLast = data['last_success'] as String?;
    });
  }

  Future<void> _saveAutoBackup() async {
    await AutomaticBackupService.configure(enabled: _autoBackupEnabled, intervalDays: _autoBackupDays);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planification de sauvegarde enregistrée.')));
  }

  Future<String?> _askPassword({required String title, bool confirm = false}) async {
    final pwd = TextEditingController();
    final pwd2 = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe', helperText: '8 caractères minimum'), autofocus: true),
            if (confirm) ...[
              const SizedBox(height: 10),
              TextField(controller: pwd2, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe')),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (pwd.text.length < 8) return;
              if (confirm && pwd.text != pwd2.text) return;
              Navigator.pop(context, pwd.text);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<String> _optionallyCopy(File file, {required String title}) async {
    final directory = await FilePicker.platform.getDirectoryPath(dialogTitle: title);
    if (directory == null) return file.path;
    final copy = File(p.join(directory, p.basename(file.path)));
    await file.copy(copy.path);
    return copy.path;
  }

  Future<void> _backup() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('sauvegarde chiffrée');
    final password = await _askPassword(title: 'Mot de passe de la sauvegarde', confirm: true);
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final dbPath = await AppDatabase.instance.databasePath;
      await AppDatabase.instance.close();
      final file = await _service.exportLocalDatabase(dbPath, password: password);
      await AppDatabase.instance.initialize();
      final finalPath = await _optionallyCopy(file, title: 'Copier la sauvegarde dans un autre dossier (optionnel)');
      setState(() => _lastMessage = 'Sauvegarde locale chiffrée créée :\n$finalPath\n\nElle contient la base et les médias pris en charge. Conservez le mot de passe : sans lui, le fichier .gesbk est illisible.');
    } catch (error) {
      setState(() => _lastMessage = 'Erreur lors de la sauvegarde : $error');
    } finally {
      await AppDatabase.instance.initialize();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('restauration de sauvegarde');
    final confirmed = await _confirmDestructiveImport(
      title: 'Restaurer une sauvegarde ?',
      message: 'La base actuelle sera remplacée par la sauvegarde choisie. Une copie de sécurité de la base actuelle est conservée automatiquement.',
    );
    if (!confirmed) return;

    final picked = await FilePicker.platform.pickFiles(dialogTitle: 'Choisir une sauvegarde GesApp (.gesbk)', type: FileType.any);
    if (picked == null || picked.files.single.path == null) return;
    final password = await _askPassword(title: 'Mot de passe de la sauvegarde');
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final dbPath = await AppDatabase.instance.databasePath;
      await AppDatabase.instance.close();
      await _service.restoreLocalDatabase(backupPath: picked.files.single.path!, databasePath: dbPath, password: password);
      await AppDatabase.instance.initialize();
      _invalidateRestoredData();
      setState(() => _lastMessage = 'Restauration .gesbk terminée. Fermez puis rouvrez GesApp afin de forcer une nouvelle authentification sur les comptes restaurés.');
    } catch (error) {
      setState(() => _lastMessage = 'Erreur lors de la restauration : $error');
    } finally {
      await AppDatabase.instance.initialize();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportJson() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('export JSON');
    setState(() => _busy = true);
    try {
      final dbPath = await AppDatabase.instance.databasePath;
      await AppDatabase.instance.close();
      final result = await _jsonService.exportAll(dbPath);
      await AppDatabase.instance.initialize();
      final finalPath = await _optionallyCopy(result.file, title: 'Copier le JSON dans un dossier (optionnel)');
      final warning = result.missingMediaCount == 0 ? '' : '\nAttention : ${result.missingMediaCount} fichier(s) référencé(s) étaient introuvables et n’ont pas pu être intégrés.';
      setState(() => _lastMessage = 'Export JSON complet créé :\n$finalPath\n\n${result.tableCount} tables · ${result.rowCount} lignes · ${result.mediaCount} fichiers intégrés.$warning\n\nLe JSON n’est PAS chiffré : toute personne qui possède ce fichier peut lire les données.');
    } catch (error) {
      setState(() => _lastMessage = 'Erreur lors de l’export JSON : $error');
    } finally {
      await AppDatabase.instance.initialize();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('import JSON');
    final confirmed = await _confirmDestructiveImport(
      title: 'Importer toutes les données JSON ?',
      message: 'Cette opération remplace les données métier actuelles (élèves, finances, paramètres, historique, etc.) par celles du fichier JSON. Vos gestionnaires/PIN actifs de cet appareil sont conservés pour éviter un verrouillage après import. Le fichier est contrôlé avant remplacement.',
    );
    if (!confirmed) return;

    final picked = await FilePicker.platform.pickFiles(dialogTitle: 'Choisir un export GesApp JSON', type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.json')) {
      setState(() => _lastMessage = 'Import refusé : sélectionnez un fichier .json créé par GesApp.');
      return;
    }

    setState(() => _busy = true);
    try {
      final dbPath = await AppDatabase.instance.databasePath;
      await AppDatabase.instance.close();
      await _jsonService.importAll(jsonPath: path, databasePath: dbPath);
      await AppDatabase.instance.initialize();
      _invalidateRestoredData();
      setState(() => _lastMessage = 'Import JSON terminé avec succès. Toutes les données et les fichiers intégrés au JSON ont été restaurés. Vos gestionnaires/PIN locaux actifs ont été conservés : reconnectez-vous avec le même compte qu’avant l’import.');
    } catch (error) {
      setState(() => _lastMessage = 'Import JSON annulé : $error\n\nLa base précédente a été conservée ou restaurée automatiquement.');
    } finally {
      await AppDatabase.instance.initialize();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDestructiveImport({required String title, required String message}) async {
    final value = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
        ],
      ),
    );
    return value == true;
  }

  void _invalidateRestoredData() {
    ref.invalidate(studentsProvider);
    ref.invalidate(classroomsProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(expenseCategoriesProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(establishmentProvider);
    ref.invalidate(cyclesProvider);
    ref.invalidate(feeCategoriesProvider);
    ref.invalidate(recentPaymentsProvider);
    ref.invalidate(cancelledPaymentsProvider);
    ref.invalidate(feeGridProvider);
    ref.invalidate(unpaidDuesProvider);
    ref.invalidate(packagesProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(familiesProvider);
    ref.invalidate(auditEntriesProvider);
    ref.invalidate(dataIntegrityReportProvider);
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde & transfert des données')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, 'Sauvegarde locale sécurisée', 'Format recommandé pour protéger une copie complète de GesApp sur l’appareil ou dans un dossier de votre choix.'),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Sauvegarde automatique'), subtitle: Text(_autoBackupLast == null ? 'Aucune sauvegarde automatique réussie.' : 'Dernière réussite : $_autoBackupLast'), value: _autoBackupEnabled, onChanged: (v) => setState(() => _autoBackupEnabled = v)),
            DropdownButtonFormField<int>(initialValue: _autoBackupDays, decoration: const InputDecoration(labelText: 'Fréquence'), items: const [1,3,7,14,30].map((d)=>DropdownMenuItem(value:d,child:Text(d==1?'Chaque jour':'Tous les $d jours'))).toList(), onChanged: _autoBackupEnabled ? (v)=>setState(()=>_autoBackupDays=v??3) : null),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: _saveAutoBackup, icon: const Icon(Icons.schedule), label: const Text('Enregistrer la planification'))),
          ]))),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _busy ? null : _backup, icon: const Icon(Icons.lock_outline), label: const Text('Créer une sauvegarde locale (.gesbk)')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore_outlined), label: const Text('Restaurer une sauvegarde .gesbk')),
          const SizedBox(height: 26),
          const Divider(),
          const SizedBox(height: 18),
          _sectionTitle(context, 'Import / export JSON complet', 'Le JSON contient toutes les tables de données et embarque les fichiers référencés disponibles. Il est portable et contrôlé par une empreinte SHA-256.'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Le fichier JSON est lisible en clair et peut contenir des données personnelles et financières. Ne le partagez qu’avec une personne autorisée.')),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(onPressed: _busy ? null : _exportJson, icon: const Icon(Icons.data_object), label: const Text('Exporter toutes les données en JSON')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _busy ? null : _importJson, icon: const Icon(Icons.file_download_outlined), label: const Text('Importer toutes les données depuis JSON')),
          if (_busy) ...[const SizedBox(height: 18), const LinearProgressIndicator()],
          if (_lastMessage != null) ...[
            const SizedBox(height: 20),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(_lastMessage!))),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Sauvegarde infonuagique', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('L’intégration automatique Google Drive reste reportée. Les fichiers .gesbk ou .json peuvent néanmoins être copiés manuellement dans le stockage cloud choisi.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
        ],
      ),
    );
  }
}
