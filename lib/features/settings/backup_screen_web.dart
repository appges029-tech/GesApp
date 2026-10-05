import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/session/business_write_guard.dart';
import '../../services/json_schema.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _message;

  Future<List<String>> _portableTables() async {
    final db = AppDatabase.instance.db;
    final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final existing = rows.map((r) => r['name']?.toString()).whereType<String>().toSet();
    return gesAppPortableTables.where(existing.contains).toList(growable: false);
  }

  Future<Map<String, Object?>> _exportData() async {
    final db = AppDatabase.instance.db;
    final names = await _portableTables();
    final tables = <String, Object?>{};
    for (final name in names) {
      tables[name] = await db.query(name);
    }
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final schemaVersion = versionRows.isEmpty
        ? 0
        : (versionRows.first.values.first as num?)?.toInt() ?? 0;
    final core = <String, Object?>{
      'format': 'gesapp-json',
      'format_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'database_schema_version': schemaVersion,
      'complete_export': true,
      'table_manifest': names,
      'tables': tables,
      'media': const <Object?>[],
      'warnings': const <String, Object?>{'missing_referenced_files': 0},
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(core))).toString();
    return <String, Object?>{...core, 'checksum_sha256': checksum};
  }

  Future<void> _backup() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('export sauvegarde Web');
    setState(() => _busy = true);
    try {
      final data = await _exportData();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      final name = 'gesapp-web-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      await downloadBytes(bytes: bytes, fileName: name, mimeType: 'application/json');
      if (mounted) setState(() => _message = 'Sauvegarde Web téléchargée : $name');
    } catch (error) {
      if (mounted) setState(() => _message = 'Erreur : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _verifyChecksum(Map<String, dynamic> document) {
    final supplied = document['checksum_sha256']?.toString();
    if (supplied == null || supplied.length != 64) {
      throw const FormatException('Signature SHA-256 absente.');
    }
    final core = Map<String, dynamic>.from(document)..remove('checksum_sha256');
    final expected = sha256.convert(utf8.encode(jsonEncode(core))).toString();
    if (expected != supplied) throw const FormatException('Le JSON a été modifié ou endommagé.');
  }

  String _mimeForRelativePath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<void> _restorePortableMedia(Map<String, dynamic> decoded) async {
    final media = decoded['media'];
    if (media is! List || media.isEmpty) return;
    final db = AppDatabase.instance.db;
    for (final raw in media) {
      if (raw is! Map) continue;
      final table = raw['table']?.toString();
      final idColumn = raw['id_column']?.toString();
      final rowId = raw['row_id']?.toString();
      final column = raw['column']?.toString();
      final relative = raw['relative_path']?.toString() ?? '';
      final data = raw['data']?.toString();
      if (table == null || idColumn == null || rowId == null || column == null || data == null) continue;
      if (!gesAppPortableTables.contains(table)) continue;
      final mime = _mimeForRelativePath(relative);
      final dataUrl = 'data:$mime;base64,$data';
      await db.update(table, {column: dataUrl}, where: '$idColumn = ?', whereArgs: [rowId]);
    }
  }

  Future<void> _backfillSchoolYears() async {
    final db = AppDatabase.instance.db;
    final dueColumns = await db.rawQuery('PRAGMA table_info(dues)');
    if (dueColumns.any((c) => c['name'] == 'school_year_id')) {
      await db.execute('''
        UPDATE dues SET school_year_id=(
          SELECT sy.id FROM school_years sy
          WHERE COALESCE(dues.due_date,dues.created_at)>=sy.start_date
            AND COALESCE(dues.due_date,dues.created_at)<=sy.end_date
          ORDER BY sy.start_date DESC LIMIT 1
        ) WHERE school_year_id IS NULL
      ''');
      await db.execute("UPDATE dues SET school_year_id=(SELECT id FROM school_years WHERE is_active=1 LIMIT 1) WHERE school_year_id IS NULL");
    }
    final paymentColumns = await db.rawQuery('PRAGMA table_info(payments)');
    if (paymentColumns.any((c) => c['name'] == 'school_year_id')) {
      await db.execute('''
        UPDATE payments SET school_year_id=(
          SELECT d.school_year_id FROM payment_allocations pa
          JOIN dues d ON d.id=pa.due_id
          WHERE pa.payment_id=payments.id AND d.school_year_id IS NOT NULL
          ORDER BY d.due_date,d.created_at LIMIT 1
        ) WHERE school_year_id IS NULL
      ''');
      await db.execute('''
        UPDATE payments SET school_year_id=(
          SELECT sy.id FROM school_years sy
          WHERE payments.paid_at>=sy.start_date AND payments.paid_at<=sy.end_date
          ORDER BY sy.start_date DESC LIMIT 1
        ) WHERE school_year_id IS NULL
      ''');
      await db.execute("UPDATE payments SET school_year_id=(SELECT id FROM school_years WHERE is_active=1 LIMIT 1) WHERE school_year_id IS NULL");
    }
  }

  Future<bool> _confirmRestore() async {
    final value = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: const Text('Les données actuelles seront remplacées. GesApp conservera un snapshot mémoire et le restaurera automatiquement si une validation échoue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurer')),
        ],
      ),
    );
    return value == true;
  }

  Future<void> _restoreSnapshot(Map<String, List<Map<String, Object?>>> snapshot) async {
    final db = AppDatabase.instance.db;
    final names = snapshot.keys.toList(growable: false);
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final name in names.reversed) {
          await txn.delete(name);
        }
        for (final name in names) {
          for (final row in snapshot[name] ?? const <Map<String, Object?>>[]) {
            await txn.insert(name, row);
          }
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _restore() async {
    BusinessWriteGuard.ensureSensitiveDataAccess('restauration sauvegarde Web');
    if (!await _confirmRestore()) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    setState(() => _busy = true);
    try {
      final decoded = jsonDecode(utf8.decode(result.files.single.bytes!));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'gesapp-json' ||
          decoded['format_version'] != 1 ||
          decoded['complete_export'] != true ||
          decoded['tables'] is! Map) {
        throw const FormatException('Fichier GesApp JSON invalide.');
      }
      _verifyChecksum(decoded);
      final tables = (decoded['tables'] as Map).cast<String, dynamic>();

      final db = AppDatabase.instance.db;
      final currentNames = await _portableTables();
      final missingLocalSchema = gesAppPortableTables.where((table) => !currentNames.contains(table)).toList();
      if (missingLocalSchema.isNotEmpty) {
        throw FormatException(
          'La base GesApp Web est incomplète : ${missingLocalSchema.join(', ')}.',
        );
      }
      final versionRows = await db.rawQuery('PRAGMA user_version');
      final currentSchemaVersion = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as num?)?.toInt() ?? 0;
      final sourceSchemaVersion = (decoded['database_schema_version'] as num?)?.toInt() ?? 0;
      validateCompletePortableExport(
        sourceSchemaVersion: sourceSchemaVersion,
        currentSchemaVersion: currentSchemaVersion,
        currentPortableTables: gesAppPortableTables,
        sourceTables: tables,
        tableManifest: decoded['table_manifest'],
      );
      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final name in currentNames) {
        snapshot[name] = (await db.query(name)).map((row) => Map<String, Object?>.from(row)).toList(growable: false);
      }
      var databaseMutated = false;
      try {
        await db.execute('PRAGMA foreign_keys = OFF');
        try {
          await db.transaction((txn) async {
            for (final name in currentNames.reversed) {
              await txn.delete(name);
            }
            for (final name in currentNames) {
              final rows = tables[name] ?? const <Object?>[];
              if (rows is! List) throw FormatException('Table JSON invalide : $name');
              for (final raw in rows) {
                if (raw is Map) {
                  await txn.insert(name, Map<String, Object?>.from(raw));
                }
              }
            }
            final fkInside = await txn.rawQuery('PRAGMA foreign_key_check');
            if (fkInside.isNotEmpty) {
              throw FormatException('${fkInside.length} référence(s) incohérente(s) dans le JSON.');
            }
          });
          databaseMutated = true;
        } finally {
          await db.execute('PRAGMA foreign_keys = ON');
        }
        await _backfillSchoolYears();
        await _restorePortableMedia(decoded);
        final integrity = await db.rawQuery('PRAGMA integrity_check');
        final ok = integrity.expand((r) => r.values).any((v) => v.toString().toLowerCase() == 'ok');
        if (!ok) throw const FormatException('Contrôle SQLite après import en échec.');
        final fk = await db.rawQuery('PRAGMA foreign_key_check');
        if (fk.isNotEmpty) throw FormatException('${fk.length} référence(s) incohérente(s) après import.');
      } catch (error) {
        if (databaseMutated) {
          await _restoreSnapshot(snapshot);
        }
        rethrow;
      }

      _invalidate();
      if (mounted) setState(() => _message = 'Restauration Web terminée.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Erreur de restauration : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate() {
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sauvegarde Web')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Sur le Web, SQLite est persisté dans IndexedDB. L’export JSON utilise uniquement les tables métier GesApp : les tables techniques Android/Web ne sont jamais exigées.',
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _backup,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Télécharger une sauvegarde JSON'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Restaurer une sauvegarde JSON'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
            ],
          ],
        ),
      );
}
