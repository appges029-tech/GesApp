import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:cryptography/cryptography.dart' as strong_crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/platform/platform_database.dart';
import '../core/session/business_write_guard.dart';

Future<Database> _openProtectedDatabase(
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

/// Sauvegarde GesApp V5.
///
/// V5 utilise PBKDF2-HMAC-SHA256 + AES-256-GCM. V4 protège la base SQLite et tous les médias gérés/référencés par GesApp
/// avec AES-256-GCM. Les sauvegardes V1/V2/V3 restent restaurables.
class BackupService {
  static const _magicV5 = 'GESAPPBK5';
  static const _magicV4 = 'GESAPPBK4';
  static const _magicV3 = 'GESAPPBK3';
  static const _magicV2 = 'GESAPPBK2';
  static const _magicV1 = 'GESAPPBK1';
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _legacyTagLength = 32;
  static const _legacyKdfRounds = 20000;
  static const _pbkdf2Rounds = 120000;

  final _aes = AesGcm.with256bits();

  Future<String> _backupsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final backups = Directory(p.join(dir.path, 'backups'));
    await backups.create(recursive: true);
    return backups.path;
  }

  Future<File> exportLocalDatabase(String databasePath, {required String password, bool trustedSystem = false}) async {
    if (!trustedSystem) BusinessWriteGuard.ensureSensitiveDataAccess('sauvegarde chiffrée');
    if (password.length < 8) {
      throw ArgumentError('Le mot de passe de sauvegarde doit contenir au moins 8 caractères.');
    }
    final appDocs = await getApplicationDocumentsDirectory();
    final payload = <String, Object?>{
      'format': 5,
      'created_at': DateTime.now().toIso8601String(),
      'database': base64Encode(await File(databasePath).readAsBytes()),
      'media': await _collectAllMedia(appDocs.path, databasePath),
      'attachments': await _collectReferencedFiles(databasePath),
    };
    final raw = utf8.encode(jsonEncode(payload));
    final salt = _randomBytes(_saltLength);
    final keyBytes = await _deriveStrongKey(password, salt);
    final nonce = _randomBytes(_nonceLength);
    final box = await _aes.encrypt(raw, secretKey: SecretKey(keyBytes), nonce: nonce);

    final backupsDir = await _backupsDir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final target = File(p.join(backupsDir, 'gesapp-backup-$stamp.gesbk'));
    await target.writeAsBytes([
      ...utf8.encode(_magicV5),
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ], flush: true);
    return target;
  }


  Future<List<Map<String, String>>> _collectReferencedFiles(String databasePath) async {
    Database? db;
    try {
      db = await _openProtectedDatabase(databasePath, readOnly: true);
      final tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final items = <Map<String, String>>[];
      for (final tableRow in tableRows) {
        final table = tableRow['name']?.toString();
        if (table == null || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table)) continue;
        final info = await db.rawQuery('PRAGMA table_info("$table")');
        final columns = info.map((row) => row['name']?.toString()).whereType<String>().toSet();
        if (!columns.contains('id')) continue;
        final pathColumns = columns.where((name) => name.endsWith('_path')).toList();
        if (pathColumns.isEmpty) continue;
        final rows = await db.query(table, columns: ['id', ...pathColumns]);
        for (final row in rows) {
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          for (final column in pathColumns) {
            final path = row[column]?.toString();
            if (path == null || path.trim().isEmpty) continue;
            final file = File(path);
            if (!await file.exists()) continue;
            items.add({
              'table': table,
              'row_id': id,
              'column': column,
              'name': p.basename(file.path),
              'data': base64Encode(await file.readAsBytes()),
            });
          }
        }
      }
      return items;
    } finally {
      await db?.close();
    }
  }

  Future<void> _restoreReferencedFiles(Object? value, String databasePath, {bool onlyIfMissing = false}) async {
    if (value is! List || value.isEmpty) return;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'GesApp', 'restored_assets'));
    await root.create(recursive: true);
    Database? db;
    try {
      db = await _openProtectedDatabase(databasePath);
      for (final raw in value) {
        if (raw is! Map) continue;
        final table = raw['table']?.toString();
        final rowId = raw['row_id']?.toString();
        final column = raw['column']?.toString();
        final name = raw['name']?.toString();
        final data = raw['data']?.toString();
        if ([table, rowId, column, name, data].any((v) => v == null || v.isEmpty)) {
          continue;
        }
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table!) ||
            !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(column!) ||
            !column.endsWith('_path') ||
            p.isAbsolute(name!) ||
            name.contains('..')) {
          continue;
        }
        final info = await db.rawQuery('PRAGMA table_info("$table")');
        final columns = info.map((row) => row['name']?.toString()).whereType<String>().toSet();
        if (!columns.contains('id') || !columns.contains(column)) continue;
        if (onlyIfMissing) {
          final currentRows = await db.query(
            table,
            columns: [column],
            where: 'id = ?',
            whereArgs: [rowId],
            limit: 1,
          );
          final currentPath = currentRows.isEmpty ? null : currentRows.first[column]?.toString();
          if (currentPath != null && currentPath.isNotEmpty && await File(currentPath).exists()) {
            continue;
          }
        }
        final target = File(p.join(root.path, table, rowId!, name));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(base64Decode(data!), flush: true);
        await db.update(table, {column: target.path}, where: 'id = ?', whereArgs: [rowId]);
      }
    } finally {
      await db?.close();
    }
  }
  Future<List<Map<String, String>>> _collectAllMedia(String appDocsPath, String databasePath) async {
    final root = Directory(p.join(appDocsPath, 'GesApp'));
    final items = <Map<String, String>>[];
    final seen = <String>{};

    Future<void> addFile(File file, String relative) async {
      if (!await file.exists()) return;
      final safe = p.normalize(relative).replaceAll('\\', '/');
      if (p.isAbsolute(safe) || p.split(safe).contains('..') || !seen.add(safe)) return;
      items.add({'path': safe, 'data': base64Encode(await file.readAsBytes())});
    }

    if (await root.exists()) {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        await addFile(entity, p.relative(entity.path, from: root.path));
      }
    }

    Database? db;
    try {
      db = await _openProtectedDatabase(databasePath, readOnly: true);
      final establishments = await db.query('establishments', columns: ['id', 'logo_path']);
      for (final row in establishments) {
        final path = row['logo_path']?.toString() ?? '';
        if (path.isNotEmpty) await addFile(File(path), p.join('establishment', row['id'].toString(), p.basename(path)));
      }
      final expenses = await db.query('expenses', columns: ['id', 'proof_path']);
      for (final row in expenses) {
        final path = row['proof_path']?.toString() ?? '';
        if (path.isNotEmpty) await addFile(File(path), p.join('expenses', row['id'].toString(), p.basename(path)));
      }
      final students = await db.query('students', columns: ['id', 'photo_path']);
      for (final row in students) {
        final path = row['photo_path']?.toString() ?? '';
        if (path.isNotEmpty) await addFile(File(path), p.join('students', row['id'].toString(), 'photos', p.basename(path)));
      }
      final docs = await db.query('student_documents', columns: ['id', 'student_id', 'file_path']);
      for (final row in docs) {
        final path = row['file_path']?.toString() ?? '';
        if (path.isNotEmpty) await addFile(File(path), p.join('students', row['student_id'].toString(), 'documents', p.basename(path)));
      }
    } finally {
      await db?.close();
    }
    return items;
  }

  Future<void> restoreLocalDatabase({required String backupPath, required String databasePath, required String password}) async {
    BusinessWriteGuard.ensureSensitiveDataAccess('restauration de sauvegarde');
    final source = File(backupPath);
    if (!await source.exists()) throw StateError('Sauvegarde introuvable');
    final content = await source.readAsBytes();

    if (_startsWith(content, utf8.encode(_magicV5))) {
      await _restoreV5(content, databasePath, password);
      return;
    }
    if (_startsWith(content, utf8.encode(_magicV4))) {
      await _restoreV4(content, databasePath, password);
      return;
    }
    if (_startsWith(content, utf8.encode(_magicV3))) {
      await _restoreV3(content, databasePath, password);
      return;
    }

    final decrypted = _decodeLegacyBackup(content, password);
    if (!_looksLikeSqlite(decrypted)) throw StateError('Mot de passe incorrect ou sauvegarde corrompue.');
    await _replaceDatabase(decrypted, databasePath);
  }

  Future<void> _restoreV5(List<int> content, String databasePath, String password) async {
    final header = utf8.encode(_magicV5);
    final min = header.length + _saltLength + _nonceLength + _tagLength + 1;
    if (content.length < min) throw StateError('Sauvegarde V5 incomplète.');
    final saltStart = header.length;
    final nonceStart = saltStart + _saltLength;
    final cipherStart = nonceStart + _nonceLength;
    final tagStart = content.length - _tagLength;
    final salt = content.sublist(saltStart, nonceStart);
    final nonce = content.sublist(nonceStart, cipherStart);
    final cipher = content.sublist(cipherStart, tagStart);
    final mac = Mac(content.sublist(tagStart));
    final keyBytes = await _deriveStrongKey(password, salt);
    List<int> clear;
    try {
      clear = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    } catch (_) {
      throw StateError('Mot de passe incorrect ou sauvegarde altérée.');
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic> || decoded['format'] != 5) throw StateError('Contenu de sauvegarde GesApp invalide.');
    final dbBytes = base64Decode(decoded['database'] as String);
    await _replaceDatabase(dbBytes, databasePath);
    await _restoreAllMedia(decoded['media'], databasePath);
    await _restoreReferencedFiles(decoded['attachments'], databasePath, onlyIfMissing: true);
  }

  Future<void> _restoreV4(List<int> content, String databasePath, String password) async {
    final header = utf8.encode(_magicV4);
    final min = header.length + _saltLength + _nonceLength + _tagLength + 1;
    if (content.length < min) throw StateError('Sauvegarde V4 incomplète.');
    final saltStart = header.length;
    final nonceStart = saltStart + _saltLength;
    final cipherStart = nonceStart + _nonceLength;
    final tagStart = content.length - _tagLength;
    final salt = content.sublist(saltStart, nonceStart);
    final nonce = content.sublist(nonceStart, cipherStart);
    final cipher = content.sublist(cipherStart, tagStart);
    final mac = Mac(content.sublist(tagStart));
    final keyBytes = _deriveLegacyV34Key(password, salt);
    List<int> clear;
    try {
      clear = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    } catch (_) {
      throw StateError('Mot de passe incorrect ou sauvegarde altérée.');
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic> || decoded['format'] != 4) throw StateError('Contenu de sauvegarde GesApp invalide.');
    final dbBytes = base64Decode(decoded['database'] as String);
    await _replaceDatabase(dbBytes, databasePath);
    await _restoreAllMedia(decoded['media'], databasePath);
    await _restoreReferencedFiles(decoded['attachments'], databasePath, onlyIfMissing: true);
  }

  Future<void> _restoreV3(List<int> content, String databasePath, String password) async {
    final header = utf8.encode(_magicV3);
    final min = header.length + _saltLength + _nonceLength + _tagLength + 1;
    if (content.length < min) throw StateError('Sauvegarde V3 incomplète.');
    final saltStart = header.length;
    final nonceStart = saltStart + _saltLength;
    final cipherStart = nonceStart + _nonceLength;
    final tagStart = content.length - _tagLength;
    final salt = content.sublist(saltStart, nonceStart);
    final nonce = content.sublist(nonceStart, cipherStart);
    final cipher = content.sublist(cipherStart, tagStart);
    final mac = Mac(content.sublist(tagStart));
    final keyBytes = _deriveLegacyV34Key(password, salt);
    List<int> clear;
    try {
      clear = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    } catch (_) {
      throw StateError('Mot de passe incorrect ou sauvegarde altérée.');
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic> || decoded['format'] != 3) throw StateError('Contenu de sauvegarde GesApp invalide.');
    final dbBytes = base64Decode(decoded['database'] as String);
    await _replaceDatabase(dbBytes, databasePath);
    await _restoreMedia(decoded['media'], databasePath);
    await _restoreReferencedFiles(decoded['attachments'], databasePath);
  }

  Future<void> _restoreAllMedia(Object? mediaValue, String databasePath) async {
    if (mediaValue is! List) return;
    final appDocs = await getApplicationDocumentsDirectory();
    final mediaRoot = Directory(p.join(appDocs.path, 'GesApp'));
    final restoreRoot = Directory('${mediaRoot.path}.restore-v4');
    final safety = Directory('${mediaRoot.path}.before-restore');
    if (await restoreRoot.exists()) await restoreRoot.delete(recursive: true);
    await restoreRoot.create(recursive: true);
    var swapped = false;
    try {
      for (final raw in mediaValue) {
        if (raw is! Map) continue;
        final relative = raw['path']?.toString();
        final data = raw['data']?.toString();
        if (relative == null || data == null || p.isAbsolute(relative) || p.split(relative).contains('..')) continue;
        final target = File(p.join(restoreRoot.path, relative));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(base64Decode(data), flush: true);
      }
      if (await safety.exists()) await safety.delete(recursive: true);
      if (await mediaRoot.exists()) await mediaRoot.rename(safety.path);
      await restoreRoot.rename(mediaRoot.path);
      swapped = true;
      await _relinkAllMediaPaths(databasePath, appDocs.path);
    } catch (_) {
      if (await restoreRoot.exists()) await restoreRoot.delete(recursive: true);
      if (swapped && await mediaRoot.exists()) await mediaRoot.delete(recursive: true);
      if (await safety.exists()) await safety.rename(mediaRoot.path);
      rethrow;
    }
  }

  Future<void> _relinkAllMediaPaths(String databasePath, String appDocsPath) async {
    await _relinkMediaPaths(databasePath, appDocsPath);
    Database? db;
    try {
      db = await _openProtectedDatabase(databasePath);
      final establishments = await db.query('establishments', columns: ['id', 'logo_path']);
      for (final row in establishments) {
        final old = row['logo_path']?.toString() ?? '';
        if (old.isEmpty) continue;
        final path = p.join(appDocsPath, 'GesApp', 'establishment', row['id'].toString(), p.basename(old));
        if (await File(path).exists()) await db.update('establishments', {'logo_path': path}, where: 'id = ?', whereArgs: [row['id']]);
      }
      final expenses = await db.query('expenses', columns: ['id', 'proof_path']);
      for (final row in expenses) {
        final old = row['proof_path']?.toString() ?? '';
        if (old.isEmpty) continue;
        final path = p.join(appDocsPath, 'GesApp', 'expenses', row['id'].toString(), p.basename(old));
        if (await File(path).exists()) await db.update('expenses', {'proof_path': path}, where: 'id = ?', whereArgs: [row['id']]);
      }
      final employees = await db.query('employees', columns: ['id', 'photo_path']);
      for (final row in employees) {
        final old=row['photo_path']?.toString()??''; if(old.isEmpty)continue;
        final path=p.join(appDocsPath,'GesApp','hr','employees',row['id'].toString(),'photos',p.basename(old));
        if(await File(path).exists()) await db.update('employees',{'photo_path':path},where:'id=?',whereArgs:[row['id']]);
      }
      final employeeDocs = await db.query('employee_documents', columns:['id','employee_id','file_path']);
      for(final row in employeeDocs){final old=row['file_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','hr','employees',row['employee_id'].toString(),'documents',p.basename(old));if(await File(path).exists())await db.update('employee_documents',{'file_path':path},where:'id=?',whereArgs:[row['id']]);}
      final contracts = await db.query('employment_contracts', columns:['id','employee_id','document_path']);
      for(final row in contracts){final old=row['document_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','hr','employees',row['employee_id'].toString(),'contracts',p.basename(old));if(await File(path).exists())await db.update('employment_contracts',{'document_path':path},where:'id=?',whereArgs:[row['id']]);}
      final leaves = await db.query('leave_requests', columns:['id','employee_id','proof_path']);
      for(final row in leaves){final old=row['proof_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','hr','employees',row['employee_id'].toString(),'leave_proofs',p.basename(old));if(await File(path).exists())await db.update('leave_requests',{'proof_path':path},where:'id=?',whereArgs:[row['id']]);}
      final assets = await db.query('assets', columns:['id','photo_path','purchase_proof_path']);
      for(final row in assets){
        final photo=row['photo_path']?.toString()??'';if(photo.isNotEmpty){final path=p.join(appDocsPath,'GesApp','patrimoine',row['id'].toString(),'photos',p.basename(photo));if(await File(path).exists())await db.update('assets',{'photo_path':path},where:'id=?',whereArgs:[row['id']]);}
        final proof=row['purchase_proof_path']?.toString()??'';if(proof.isNotEmpty){final path=p.join(appDocsPath,'GesApp','patrimoine',row['id'].toString(),'purchase',p.basename(proof));if(await File(path).exists())await db.update('assets',{'purchase_proof_path':path},where:'id=?',whereArgs:[row['id']]);}
      }
      final assetDocs=await db.query('asset_documents',columns:['id','asset_id','file_path']);
      for(final row in assetDocs){final old=row['file_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','patrimoine',row['asset_id'].toString(),'documents',p.basename(old));if(await File(path).exists())await db.update('asset_documents',{'file_path':path},where:'id=?',whereArgs:[row['id']]);}
      final assetMaintenance=await db.query('asset_maintenance',columns:['id','asset_id','proof_path']);
      for(final row in assetMaintenance){final old=row['proof_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','patrimoine',row['asset_id'].toString(),'maintenance',p.basename(old));if(await File(path).exists())await db.update('asset_maintenance',{'proof_path':path},where:'id=?',whereArgs:[row['id']]);}
      final assetDisposals=await db.query('asset_disposals',columns:['id','asset_id','document_path']);
      for(final row in assetDisposals){final old=row['document_path']?.toString()??'';if(old.isEmpty)continue;final path=p.join(appDocsPath,'GesApp','patrimoine',row['asset_id'].toString(),'disposals',p.basename(old));if(await File(path).exists())await db.update('asset_disposals',{'document_path':path},where:'id=?',whereArgs:[row['id']]);}
    } finally {
      await db?.close();
    }
  }

  Future<void> _restoreMedia(Object? mediaValue, String databasePath) async {
    if (mediaValue is! List) return;
    final appDocs = await getApplicationDocumentsDirectory();
    final mediaRoot = Directory(p.join(appDocs.path, 'GesApp', 'students'));
    final safety = Directory('${mediaRoot.path}.before-restore');
    if (await safety.exists()) await safety.delete(recursive: true);
    if (await mediaRoot.exists()) await mediaRoot.rename(safety.path);
    try {
      await mediaRoot.create(recursive: true);
      for (final raw in mediaValue) {
        if (raw is! Map) continue;
        final relative = raw['path']?.toString();
        final data = raw['data']?.toString();
        if (relative == null || data == null || p.isAbsolute(relative) || relative.contains('..')) continue;
        final target = File(p.join(mediaRoot.path, relative));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(base64Decode(data), flush: true);
      }
      await _relinkMediaPaths(databasePath, appDocs.path);
    } catch (_) {
      if (await mediaRoot.exists()) await mediaRoot.delete(recursive: true);
      if (await safety.exists()) await safety.rename(mediaRoot.path);
      rethrow;
    }
  }

  Future<void> _relinkMediaPaths(String databasePath, String appDocsPath) async {
    Database? db;
    try {
      db = await _openProtectedDatabase(databasePath);
      final students = await db.query('students', columns: ['id', 'photo_path']);
      for (final row in students) {
        final studentId = row['id'] as String;
        final old = row['photo_path'] as String?;
        if (old == null || old.isEmpty) continue;
        final name = p.basename(old);
        final newPath = p.join(appDocsPath, 'GesApp', 'students', studentId, 'photos', name);
        if (await File(newPath).exists()) await db.update('students', {'photo_path': newPath}, where: 'id = ?', whereArgs: [studentId]);
      }
      final docs = await db.query('student_documents', columns: ['id', 'student_id', 'file_path']);
      for (final row in docs) {
        final id = row['id'] as String;
        final studentId = row['student_id'] as String;
        final old = row['file_path'] as String;
        final newPath = p.join(appDocsPath, 'GesApp', 'students', studentId, 'documents', p.basename(old));
        if (await File(newPath).exists()) await db.update('student_documents', {'file_path': newPath}, where: 'id = ?', whereArgs: [id]);
      }
    } finally {
      await db?.close();
    }
  }

  Future<void> _replaceDatabase(List<int> bytes, String databasePath) async {
    final db = File(databasePath);
    final safety = File('$databasePath.before-restore');
    final temp = File('$databasePath.restore-tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await _validateSqliteDatabase(temp.path);
    if (await safety.exists()) await safety.delete();

    var movedCurrent = false;
    try {
      if (await db.exists()) {
        await db.rename(safety.path);
        movedCurrent = true;
      }
      await temp.rename(databasePath);

      // Une sauvegarde historique peut contenir une base SQLite en clair.
      // Sur Windows release elle est convertie immédiatement avant toute
      // réouverture métier.
      await preparePlatformDatabase(databasePath);

      if (await safety.exists()) await safety.delete();
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (await db.exists()) await db.delete();
      if (movedCurrent && await safety.exists()) {
        await safety.rename(databasePath);
      }
      rethrow;
    }
  }

  Uint8List _decodeLegacyBackup(List<int> content, String password) {
    final v2Header = utf8.encode(_magicV2);
    final v1Header = utf8.encode(_magicV1);
    if (_startsWith(content, v2Header)) {
      final saltStart = v2Header.length;
      final cipherStart = saltStart + 16;
      final tagStart = content.length - _legacyTagLength;
      if (tagStart <= cipherStart) throw StateError('Fichier V2 incomplet.');
      final salt = content.sublist(saltStart, cipherStart);
      final encrypted = content.sublist(cipherStart, tagStart);
      final suppliedTag = content.sublist(tagStart);
      final key = _deriveLegacyKey(password, salt);
      final expectedTag = Hmac(sha256, key).convert([...salt, ...encrypted]).bytes;
      if (!_constantTimeEquals(suppliedTag, expectedTag)) throw StateError('Mot de passe incorrect ou sauvegarde altérée.');
      return _cryptWithKey(encrypted, key);
    }
    if (_startsWith(content, v1Header)) {
      final decrypted = _legacyCrypt(content.sublist(v1Header.length), password);
      if (!_looksLikeSqlite(decrypted)) throw StateError('Mot de passe incorrect ou sauvegarde V1 corrompue.');
      return decrypted;
    }
    throw StateError('Format de sauvegarde GesApp non reconnu.');
  }

  Future<void> _validateSqliteDatabase(String path) async {
    Future<void> validate(Database candidate) async {
      final integrityRows = await candidate.rawQuery('PRAGMA integrity_check');
      final messages = integrityRows
          .expand((row) => row.values)
          .map((value) => value.toString().toLowerCase())
          .toList();
      if (messages.length != 1 || messages.single != 'ok') {
        throw StateError('La sauvegarde contient une base SQLite endommagée.');
      }
      if ((await candidate.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw StateError('La sauvegarde contient des références incohérentes.');
      }
      final expectedTables = await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('students','payments','dues','expenses','establishments')",
      );
      if (expectedTables.length < 5) {
        throw StateError('Le fichier SQLite n’est pas une sauvegarde GesApp complète.');
      }
    }

    Database? candidate;
    Object? plaintextError;
    try {
      // Compatibilité sauvegardes historiques : tente d'abord une SQLite
      // standard. Une sauvegarde créée après durcissement Windows nécessitera
      // la clé SQLCipher et sera retentée juste après.
      candidate = await platformDatabaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await validate(candidate);
      return;
    } catch (error) {
      plaintextError = error;
    } finally {
      await candidate?.close();
      candidate = null;
    }

    try {
      candidate = await _openProtectedDatabase(path, readOnly: true);
      await validate(candidate);
    } catch (_) {
      throw StateError(
        'La sauvegarde ne peut être validée ni comme SQLite historique '
        'ni avec la clé SQLCipher de ce poste. Détail initial: $plaintextError',
      );
    } finally {
      await candidate?.close();
    }
  }

  bool _looksLikeSqlite(List<int> bytes) {
    const signature = 'SQLite format 3\u0000';
    return bytes.length >= signature.length && utf8.decode(bytes.sublist(0, signature.length), allowMalformed: true) == signature;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Future<List<int>> _deriveStrongKey(String password, List<int> salt) async {
    final algorithm = strong_crypto.Pbkdf2(
      macAlgorithm: strong_crypto.Hmac.sha256(),
      iterations: _pbkdf2Rounds,
      bits: 256,
    );
    final key = await algorithm.deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  }

  List<int> _deriveLegacyV34Key(String password, List<int> salt) {
    var value = sha256.convert([...utf8.encode(password), ...salt]).bytes;
    for (var i = 0; i < _legacyKdfRounds; i++) {
      value = sha256.convert([...value, ...salt]).bytes;
    }
    return value;
  }

  List<int> _deriveLegacyKey(String password, List<int> salt) {
    var value = sha256.convert([...utf8.encode(password), ...salt]).bytes;
    for (var i = 0; i < 5000; i++) {
      value = sha256.convert([...value, ...salt]).bytes;
    }
    return value;
  }

  Uint8List _cryptWithKey(List<int> input, List<int> key) {
    final output = Uint8List(input.length);
    var blockIndex = 0;
    var offset = 0;
    while (offset < input.length) {
      final counter = ByteData(8)..setUint64(0, blockIndex);
      final block = sha256.convert([...key, ...counter.buffer.asUint8List()]).bytes;
      final length = (input.length - offset) < 32 ? input.length - offset : 32;
      for (var i = 0; i < length; i++) {
        output[offset + i] = input[offset + i] ^ block[i];
      }
      offset += length;
      blockIndex++;
    }
    return output;
  }

  Uint8List _legacyCrypt(List<int> input, String password) {
    final output = Uint8List(input.length);
    var blockIndex = 0;
    var offset = 0;
    while (offset < input.length) {
      final block = sha256.convert(utf8.encode('$password:$blockIndex')).bytes;
      final length = (input.length - offset) < 32 ? input.length - offset : 32;
      for (var i = 0; i < length; i++) {
        output[offset + i] = input[offset + i] ^ block[i];
      }
      offset += length;
      blockIndex++;
    }
    return output;
  }
  bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
