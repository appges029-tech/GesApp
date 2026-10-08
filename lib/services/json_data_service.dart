import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/platform/platform_database.dart';

import '../core/session/business_write_guard.dart';
import 'json_schema.dart';

Future<Database> _openGesAppDatabase(
  String path, {
  bool readOnly = false,
}) =>
    platformDatabaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: readOnly,
        singleInstance: false,
        onConfigure: configurePlatformDatabaseConnection,
      ),
    );

class JsonExportResult {
  const JsonExportResult({
    required this.file,
    required this.tableCount,
    required this.rowCount,
    required this.mediaCount,
    required this.missingMediaCount,
  });

  final File file;
  final int tableCount;
  final int rowCount;
  final int mediaCount;
  final int missingMediaCount;
}

/// Import/export portable de toutes les données GesApp au format JSON.
///
/// Le fichier JSON est volontairement lisible en clair. Pour une sauvegarde
/// confidentielle, utiliser le format chiffré `.gesbk` de [BackupService].
class JsonDataService {
  static const formatName = 'gesapp-json';
  static const formatVersion = 1;

  Future<String> _exportsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(dir.path, 'backups', 'json'));
    await exports.create(recursive: true);
    return exports.path;
  }

  Future<JsonExportResult> exportAll(String databasePath, {bool trustedSystem = false}) async {
    if (!trustedSystem) BusinessWriteGuard.ensureSensitiveDataAccess('export JSON');
    Database? db;
    try {
      db = await _openGesAppDatabase(databasePath, readOnly: true);
      final tableNames = await _userTables(db);
      final tables = <String, Object?>{};
      var rowCount = 0;
      for (final table in tableNames) {
        final rows = await db.query(table);
        rowCount += rows.length;
        tables[table] = rows.map(_encodeRow).toList(growable: false);
      }

      final userVersionRows = await db.rawQuery('PRAGMA user_version');
      final schemaVersion = userVersionRows.isEmpty ? 0 : (userVersionRows.first.values.first as num?)?.toInt() ?? 0;
      final appDocs = await getApplicationDocumentsDirectory();
      final mediaResult = await _collectReferencedMedia(db, appDocs.path);

      final core = <String, Object?>{
        'format': formatName,
        'format_version': formatVersion,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'database_schema_version': schemaVersion,
        'complete_export': true,
        'table_manifest': tableNames,
        'tables': tables,
        'media': mediaResult.items,
        'warnings': <String, Object?>{
          'missing_referenced_files': mediaResult.missingCount,
        },
      };
      final checksum = sha256.convert(utf8.encode(jsonEncode(core))).toString();
      final document = <String, Object?>{
        ...core,
        'checksum_sha256': checksum,
      };

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final target = File(p.join(await _exportsDir(), 'gesapp-data-$stamp.json'));
      await target.writeAsString(const JsonEncoder.withIndent('  ').convert(document), flush: true);
      return JsonExportResult(
        file: target,
        tableCount: tableNames.length,
        rowCount: rowCount,
        mediaCount: mediaResult.items.length,
        missingMediaCount: mediaResult.missingCount,
      );
    } finally {
      await db?.close();
    }
  }

  Future<void> importAll({required String jsonPath, required String databasePath, bool trustedSystem = false}) async {
    if (!trustedSystem) BusinessWriteGuard.ensureSensitiveDataAccess('import JSON');
    final source = File(jsonPath);
    if (!await source.exists()) throw StateError('Fichier JSON introuvable.');

    Object? decoded;
    try {
      decoded = jsonDecode(await source.readAsString());
    } catch (_) {
      throw StateError('Le fichier sélectionné n’est pas un JSON valide.');
    }
    if (decoded is! Map<String, dynamic>) throw StateError('Structure JSON GesApp invalide.');
    if (decoded['format'] != formatName || decoded['format_version'] != formatVersion) {
      throw StateError('Format JSON non reconnu ou version non prise en charge.');
    }
    if (decoded['complete_export'] != true) throw StateError('Ce fichier n’est pas un export complet GesApp.');

    _verifyChecksum(decoded);
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) throw StateError('Le JSON ne contient pas les tables GesApp.');

    final current = File(databasePath);
    if (!await current.exists()) throw StateError('Base GesApp actuelle introuvable.');
    final temp = File('$databasePath.json-import-tmp');
    final safety = File('$databasePath.before-json-import');
    if (await temp.exists()) await temp.delete();
    await current.copy(temp.path);

    Database? candidate;
    try {
      candidate = await _openGesAppDatabase(temp.path);
      await candidate.execute('PRAGMA foreign_keys = OFF');
      final currentTables = await _userTables(candidate);
      final missingLocalSchema = gesAppPortableTables.where((table) => !currentTables.contains(table)).toList();
      if (missingLocalSchema.isNotEmpty) {
        throw StateError(
          'La base GesApp locale est incomplète : ${missingLocalSchema.join(', ')}. Réparez la base avant toute restauration JSON.',
        );
      }
      final preservedAppUsers = await _activeAppUsers(candidate);

      final currentVersionRows = await candidate.rawQuery('PRAGMA user_version');
      final currentVersion = currentVersionRows.isEmpty ? 0 : (currentVersionRows.first.values.first as num?)?.toInt() ?? 0;
      final sourceVersion = (decoded['database_schema_version'] as num?)?.toInt() ?? 0;
      validateCompletePortableExport(
        sourceSchemaVersion: sourceVersion,
        currentSchemaVersion: currentVersion,
        currentPortableTables: gesAppPortableTables,
        sourceTables: rawTables,
        tableManifest: decoded['table_manifest'],
      );

      await candidate.transaction((txn) async {
        // Les FK sont désactivées uniquement sur la base temporaire. Toutes les
        // relations sont vérifiées avant qu’elle remplace la base réelle.
        for (final table in currentTables.reversed) {
          await txn.delete(table);
        }
        for (final table in currentTables) {
          final rawRows = table == 'app_users' && preservedAppUsers.isNotEmpty
              ? preservedAppUsers
              : rawTables[table];
          if (rawRows is! List) throw StateError('Table JSON invalide : $table.');
          for (final rawRow in rawRows) {
            if (rawRow is! Map) throw StateError('Ligne JSON invalide dans $table.');
            await txn.insert(table, _decodeRow(rawRow), conflictAlgorithm: ConflictAlgorithm.abort);
          }
        }
      });
      if (currentVersion >= 12) {
        await _backfillSchoolYearLinks(candidate);
      }
      if (currentVersion >= 15 && sourceVersion < 15) {
        await _backfillLegacyPaymentMethodTypes(candidate);
      }
      await candidate.close();
      candidate = null;

      await _validateCandidate(temp.path);
      if (await safety.exists()) await safety.delete();
      await current.rename(safety.path);
      try {
        await temp.rename(databasePath);
      } catch (_) {
        if (!await current.exists() && await safety.exists()) await safety.rename(databasePath);
        rethrow;
      }

      try {
        await _restoreReferencedMedia(decoded['media'], databasePath);
        await _materializeInlineMedia(databasePath);
      } catch (error) {
        // Si la restauration des fichiers échoue, on remet la base précédente
        // pour éviter une restauration partielle silencieuse.
        final imported = File(databasePath);
        if (await imported.exists()) await imported.delete();
        if (await safety.exists()) await safety.rename(databasePath);
        rethrow;
      }
    } finally {
      await candidate?.close();
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _backfillLegacyPaymentMethodTypes(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(payment_methods)');
    if (!columns.any((c) => c['name'] == 'account_type')) return;
    await db.execute("UPDATE payment_methods SET account_type='mobile' WHERE lower(name) LIKE '%mobile%' OR lower(name) LIKE '%momo%'");
    await db.execute("UPDATE payment_methods SET account_type='bank' WHERE lower(name) LIKE '%virement%' OR lower(name) LIKE '%banque%' OR lower(name) LIKE '%bank%' OR lower(name) LIKE '%chèque%' OR lower(name) LIKE '%cheque%'");
    await db.execute("UPDATE payment_methods SET account_type='cash' WHERE account_type NOT IN ('cash','mobile','bank') OR account_type IS NULL OR trim(account_type)=''");
  }

  Future<void> _backfillSchoolYearLinks(Database db) async {
    final dueColumns = await db.rawQuery('PRAGMA table_info(dues)');
    if (dueColumns.any((c) => c['name'] == 'school_year_id')) {
      await db.execute('''
        UPDATE dues
        SET school_year_id = (
          SELECT sy.id FROM school_years sy
          WHERE COALESCE(dues.due_date, dues.created_at) >= sy.start_date
            AND COALESCE(dues.due_date, dues.created_at) <= sy.end_date
          ORDER BY sy.start_date DESC LIMIT 1
        )
        WHERE school_year_id IS NULL
      ''');
      await db.execute('''
        UPDATE dues
        SET school_year_id = (SELECT id FROM school_years WHERE is_active=1 LIMIT 1)
        WHERE school_year_id IS NULL
      ''');
    }

    final paymentColumns = await db.rawQuery('PRAGMA table_info(payments)');
    if (paymentColumns.any((c) => c['name'] == 'school_year_id')) {
      await db.execute('''
        UPDATE payments
        SET school_year_id = (
          SELECT d.school_year_id
          FROM payment_allocations pa
          JOIN dues d ON d.id=pa.due_id
          WHERE pa.payment_id=payments.id AND d.school_year_id IS NOT NULL
          ORDER BY d.due_date,d.created_at LIMIT 1
        )
        WHERE school_year_id IS NULL
      ''');
      await db.execute('''
        UPDATE payments
        SET school_year_id = (
          SELECT sy.id FROM school_years sy
          WHERE payments.paid_at >= sy.start_date AND payments.paid_at <= sy.end_date
          ORDER BY sy.start_date DESC LIMIT 1
        )
        WHERE school_year_id IS NULL
      ''');
      await db.execute('''
        UPDATE payments
        SET school_year_id = (SELECT id FROM school_years WHERE is_active=1 LIMIT 1)
        WHERE school_year_id IS NULL
      ''');
    }
  }

  void _verifyChecksum(Map<String, dynamic> document) {
    final supplied = document['checksum_sha256']?.toString();
    if (supplied == null || supplied.length != 64) throw StateError('Signature d’intégrité JSON absente.');
    final core = Map<String, dynamic>.from(document)..remove('checksum_sha256');
    final expected = sha256.convert(utf8.encode(jsonEncode(core))).toString();
    if (supplied != expected) throw StateError('Le fichier JSON a été modifié ou endommagé.');
  }

  Future<List<String>> _userTables(Database db) async {
    final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final existing = rows.map((r) => r['name']?.toString()).whereType<String>().toSet();
    return gesAppPortableTables.where(existing.contains).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _activeAppUsers(Database db) async {
    final tables = (await _userTables(db)).toSet();
    if (!tables.contains('app_users')) return const <Map<String, Object?>>[];
    final rows = await db.query('app_users', where: 'active = 1');
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }

  Map<String, Object?> _encodeRow(Map<String, Object?> row) {
    return row.map((key, value) {
      if (value is Uint8List || value is List<int>) {
        return MapEntry(key, <String, Object?>{'__gesapp_type': 'bytes', 'base64': base64Encode(value as List<int>)});
      }
      return MapEntry(key, value);
    });
  }

  Map<String, Object?> _decodeRow(Map raw) {
    final row = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && value['__gesapp_type'] == 'bytes' && value['base64'] is String) {
        row[key] = Uint8List.fromList(base64Decode(value['base64'] as String));
      } else {
        row[key] = value;
      }
    }
    return row;
  }

  Future<_MediaCollection> _collectReferencedMedia(Database db, String appDocsPath) async {
    final items = <Map<String, Object?>>[];
    var missing = 0;

    Future<void> add({
      required String table,
      required String idColumn,
      required String rowId,
      required String column,
      required String path,
      required String relativePath,
    }) async {
      if (path.trim().isEmpty) return;
      final file = File(path);
      if (!await file.exists()) {
        missing++;
        return;
      }
      items.add(<String, Object?>{
        'table': table,
        'id_column': idColumn,
        'row_id': rowId,
        'column': column,
        'relative_path': relativePath,
        'data': base64Encode(await file.readAsBytes()),
      });
    }

    final establishments = await db.query('establishments', columns: ['id', 'logo_path']);
    for (final row in establishments) {
      final path = row['logo_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      await add(
        table: 'establishments', idColumn: 'id', rowId: row['id'].toString(), column: 'logo_path', path: path,
        relativePath: p.join('establishment', row['id'].toString(), p.basename(path)),
      );
    }

    final students = await db.query('students', columns: ['id', 'photo_path']);
    for (final row in students) {
      final path = row['photo_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      await add(
        table: 'students', idColumn: 'id', rowId: row['id'].toString(), column: 'photo_path', path: path,
        relativePath: p.join('students', row['id'].toString(), 'photos', p.basename(path)),
      );
    }

    final documents = await db.query('student_documents', columns: ['id', 'student_id', 'file_path']);
    for (final row in documents) {
      final path = row['file_path']?.toString() ?? '';
      await add(
        table: 'student_documents', idColumn: 'id', rowId: row['id'].toString(), column: 'file_path', path: path,
        relativePath: p.join('students', row['student_id'].toString(), 'documents', p.basename(path)),
      );
    }

    final expenses = await db.query('expenses', columns: ['id', 'proof_path']);
    for (final row in expenses) {
      final path = row['proof_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      await add(
        table: 'expenses', idColumn: 'id', rowId: row['id'].toString(), column: 'proof_path', path: path,
        relativePath: p.join('expenses', row['id'].toString(), p.basename(path)),
      );
    }


    final employees = await db.query('employees', columns: ['id', 'photo_path']);
    for (final row in employees) {
      final path = row['photo_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      await add(table: 'employees', idColumn: 'id', rowId: row['id'].toString(), column: 'photo_path', path: path,
        relativePath: p.join('hr','employees',row['id'].toString(),'photos',p.basename(path)));
    }
    final employeeDocs = await db.query('employee_documents', columns: ['id','employee_id','file_path']);
    for (final row in employeeDocs) {
      final path=row['file_path']?.toString()??''; if(path.isEmpty)continue;
      await add(table:'employee_documents',idColumn:'id',rowId:row['id'].toString(),column:'file_path',path:path,
        relativePath:p.join('hr','employees',row['employee_id'].toString(),'documents',p.basename(path)));
    }
    final contracts = await db.query('employment_contracts', columns: ['id','employee_id','document_path']);
    for (final row in contracts) {
      final path=row['document_path']?.toString()??''; if(path.isEmpty)continue;
      await add(table:'employment_contracts',idColumn:'id',rowId:row['id'].toString(),column:'document_path',path:path,
        relativePath:p.join('hr','employees',row['employee_id'].toString(),'contracts',p.basename(path)));
    }
    final leaves = await db.query('leave_requests', columns: ['id','employee_id','proof_path']);
    for (final row in leaves) {
      final path=row['proof_path']?.toString()??''; if(path.isEmpty)continue;
      await add(table:'leave_requests',idColumn:'id',rowId:row['id'].toString(),column:'proof_path',path:path,
        relativePath:p.join('hr','employees',row['employee_id'].toString(),'leave_proofs',p.basename(path)));
    }

    final assets = await db.query('assets', columns: ['id','photo_path','purchase_proof_path']);
    for (final row in assets) {
      final photo=row['photo_path']?.toString()??'';
      if(photo.isNotEmpty) await add(table:'assets',idColumn:'id',rowId:row['id'].toString(),column:'photo_path',path:photo,relativePath:p.join('patrimoine',row['id'].toString(),'photos',p.basename(photo)));
      final proof=row['purchase_proof_path']?.toString()??'';
      if(proof.isNotEmpty) await add(table:'assets',idColumn:'id',rowId:row['id'].toString(),column:'purchase_proof_path',path:proof,relativePath:p.join('patrimoine',row['id'].toString(),'purchase',p.basename(proof)));
    }
    final assetDocs=await db.query('asset_documents',columns:['id','asset_id','file_path']);
    for(final row in assetDocs){final path=row['file_path']?.toString()??'';if(path.isEmpty)continue;await add(table:'asset_documents',idColumn:'id',rowId:row['id'].toString(),column:'file_path',path:path,relativePath:p.join('patrimoine',row['asset_id'].toString(),'documents',p.basename(path)));}
    final maintenance=await db.query('asset_maintenance',columns:['id','asset_id','proof_path']);
    for(final row in maintenance){final path=row['proof_path']?.toString()??'';if(path.isEmpty)continue;await add(table:'asset_maintenance',idColumn:'id',rowId:row['id'].toString(),column:'proof_path',path:path,relativePath:p.join('patrimoine',row['asset_id'].toString(),'maintenance',p.basename(path)));}
    final disposals=await db.query('asset_disposals',columns:['id','asset_id','document_path']);
    for(final row in disposals){final path=row['document_path']?.toString()??'';if(path.isEmpty)continue;await add(table:'asset_disposals',idColumn:'id',rowId:row['id'].toString(),column:'document_path',path:path,relativePath:p.join('patrimoine',row['asset_id'].toString(),'disposals',p.basename(path)));}

    return _MediaCollection(items: items, missingCount: missing);
  }

  Future<void> _restoreReferencedMedia(Object? mediaValue, String databasePath) async {
    if (mediaValue is! List) return;
    final appDocs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDocs.path, 'GesApp'));
    final importRoot = Directory('${root.path}.json-import');
    final safety = Directory('${root.path}.before-json-import');
    if (await importRoot.exists()) await importRoot.delete(recursive: true);
    await importRoot.create(recursive: true);

    Database? db;
    var swapped = false;
    try {
      db = await _openGesAppDatabase(databasePath);
      for (final raw in mediaValue) {
        if (raw is! Map) continue;
        final table = raw['table']?.toString();
        final idColumn = raw['id_column']?.toString();
        final rowId = raw['row_id']?.toString();
        final column = raw['column']?.toString();
        final relative = raw['relative_path']?.toString();
        final data = raw['data']?.toString();
        if ([table, idColumn, rowId, column, relative, data].any((v) => v == null || v.isEmpty)) continue;
        if (p.isAbsolute(relative!) || p.split(relative).contains('..')) throw StateError('Chemin média JSON non sûr.');
        final target = File(p.join(importRoot.path, relative));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(base64Decode(data!), flush: true);
        final finalPath = p.join(root.path, relative);
        await db.update(table!, {column!: finalPath}, where: '$idColumn = ?', whereArgs: [rowId]);
      }
      await db.close();
      db = null;

      if (await safety.exists()) await safety.delete(recursive: true);
      if (await root.exists()) await root.rename(safety.path);
      await importRoot.rename(root.path);
      swapped = true;
    } catch (_) {
      await db?.close();
      if (await importRoot.exists()) await importRoot.delete(recursive: true);
      if (swapped && await root.exists()) await root.delete(recursive: true);
      if (await safety.exists()) await safety.rename(root.path);
      rethrow;
    }
  }

  Future<void> _materializeInlineMedia(String databasePath) async {
    final appDocs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDocs.path, 'GesApp'));
    await root.create(recursive: true);
    Database? db;
    try {
      db = await _openGesAppDatabase(databasePath);

      Future<void> materialize({
        required String table,
        required String idColumn,
        required String column,
        required String relativeFolder,
      }) async {
        final rows = await db!.query(table, columns: [idColumn, column]);
        for (final row in rows) {
          final value = row[column]?.toString() ?? '';
          if (!value.startsWith('data:')) continue;
          final comma = value.indexOf(',');
          if (comma <= 5) continue;
          final header = value.substring(5, comma);
          final payload = value.substring(comma + 1);
          final mime = header.split(';').first;
          final extension = _extensionForMime(mime);
          final target = File(p.join(
            root.path,
            relativeFolder,
            row[idColumn].toString(),
            '$column$extension',
          ));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(base64Decode(payload), flush: true);
          await db!.update(
            table,
            {column: target.path},
            where: '$idColumn = ?',
            whereArgs: [row[idColumn]],
          );
        }
      }

      await materialize(table: 'establishments', idColumn: 'id', column: 'logo_path', relativeFolder: 'establishment');
      await materialize(table: 'students', idColumn: 'id', column: 'photo_path', relativeFolder: 'students');
      await materialize(table: 'student_documents', idColumn: 'id', column: 'file_path', relativeFolder: 'student_documents');
      await materialize(table: 'expenses', idColumn: 'id', column: 'proof_path', relativeFolder: 'expenses');
      await materialize(table: 'employees', idColumn: 'id', column: 'photo_path', relativeFolder: 'hr/employees');
      await materialize(table: 'employee_documents', idColumn: 'id', column: 'file_path', relativeFolder: 'hr/employee_documents');
      await materialize(table: 'employment_contracts', idColumn: 'id', column: 'document_path', relativeFolder: 'hr/employment_contracts');
      await materialize(table: 'leave_requests', idColumn: 'id', column: 'proof_path', relativeFolder: 'hr/leave_requests');
      await materialize(table: 'assets', idColumn: 'id', column: 'photo_path', relativeFolder: 'patrimoine/assets');
      await materialize(table: 'assets', idColumn: 'id', column: 'purchase_proof_path', relativeFolder: 'patrimoine/purchase');
      await materialize(table: 'asset_documents', idColumn: 'id', column: 'file_path', relativeFolder: 'patrimoine/documents');
      await materialize(table: 'asset_maintenance', idColumn: 'id', column: 'proof_path', relativeFolder: 'patrimoine/maintenance');
      await materialize(table: 'asset_disposals', idColumn: 'id', column: 'document_path', relativeFolder: 'patrimoine/disposals');
    } finally {
      await db?.close();
    }
  }

  String _extensionForMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'application/pdf':
        return '.pdf';
      default:
        return '.bin';
    }
  }

  Future<void> _validateCandidate(String path) async {
    Database? db;
    try {
      db = await _openGesAppDatabase(path, readOnly: true);
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final messages = integrity.expand((r) => r.values).map((v) => v.toString().toLowerCase()).toList();
      if (messages.length != 1 || messages.single != 'ok') throw StateError('La base reconstruite depuis le JSON est endommagée.');
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) throw StateError('Le JSON contient ${fk.length} référence(s) incohérente(s).');
      final required = {'students', 'payments', 'dues', 'expenses', 'establishments', 'app_users'};
      final tables = (await _userTables(db)).toSet();
      if (!tables.containsAll(required)) throw StateError('Le JSON n’a pas produit une base GesApp complète.');
    } finally {
      await db?.close();
    }
  }
}

class _MediaCollection {
  const _MediaCollection({required this.items, required this.missingCount});
  final List<Map<String, Object?>> items;
  final int missingCount;
}
