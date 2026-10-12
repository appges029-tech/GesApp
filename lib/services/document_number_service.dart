import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/db/app_database.dart';
import '../core/session/operator_session.dart';

/// Attribue des références documentaires stables en utilisant `app_settings`,
/// déjà présent dans GesApp. Aucun changement de schéma ni du protocole de
/// synchronisation Supabase n'est nécessaire.
class DocumentNumberService {
  DocumentNumberService([AppDatabase? database]) : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;

  Future<String> getOrCreate({
    required String type,
    required String entityId,
    DateTime? date,
  }) async {
    final normalizedType = type.trim().toUpperCase();
    final safeEntity = base64Url.encode(utf8.encode(entityId)).replaceAll('=', '');
    final mappingKey = 'document_ref:$normalizedType:$safeEntity';
    final existing = await _database.db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [mappingKey], limit: 1);
    if (existing.isNotEmpty) return '${existing.first['value']}';

    final now = date ?? DateTime.now();
    final year = now.year;
    final sequenceKey = 'document_sequence:$normalizedType:$year';
    return _database.db.transaction((txn) async {
      final mapped = await txn.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [mappingKey], limit: 1);
      if (mapped.isNotEmpty) return '${mapped.first['value']}';
      final seqRows = await txn.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [sequenceKey], limit: 1);
      final current = seqRows.isEmpty ? 0 : int.tryParse('${seqRows.first['value']}') ?? 0;
      final next = current + 1;
      final reference = '$normalizedType-$year-${next.toString().padLeft(6, '0')}';
      final timestamp = DateTime.now().toIso8601String();
      await txn.insert('app_settings', {'key': sequenceKey, 'value': '$next', 'updated_at': timestamp}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {'key': mappingKey, 'value': reference, 'updated_at': timestamp}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'document_meta:$reference',
        'value': jsonEncode({
          'type': normalizedType,
          'generated_at': timestamp,
          'generated_by': OperatorSession.current,
          'status': 'valid',
        }),
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return reference;
    });
  }

  /// Conserve la première empreinte historique et archive chaque version
  /// réellement générée (A5, POS et réimpressions) sans effacer les anciennes.
  Future<void> recordFingerprint({required String reference, required Uint8List bytes}) async {
    final digest = sha256.convert(bytes).toString();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'document_sha256:$reference',
        'value': digest,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('app_settings', {
        'key': 'document_sha256:$reference:$digest',
        'value': digest,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  /// Vérifie le contenu exact d'un fichier PDF sélectionné, et non seulement
  /// l'existence du numéro de reçu. Null = empreinte historique indisponible.
  /// Cette preuve est locale : elle ne remplace pas une signature externe.
  Future<bool?> verifyPdfFingerprint({
    required String reference,
    required Uint8List bytes,
  }) async {
    final normalized = reference.trim();
    if (normalized.isEmpty) return null;
    final variants = <String>[
      normalized, '$normalized:pos80', '$normalized:pos58',
    ];
    final digest = sha256.convert(bytes).toString();
    var hasRecordedFingerprint = false;
    for (final variant in variants) {
      final rows = await _database.db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ? OR key LIKE ?',
        whereArgs: ['document_sha256:$variant', 'document_sha256:$variant:%'],
      );
      if (rows.isNotEmpty) hasRecordedFingerprint = true;
      if (rows.any((row) => row['value'] == digest)) return true;
    }
    return hasRecordedFingerprint ? false : null;
  }

  Future<Map<String, String>?> referenceInfo(String reference) async {
    final rows = await _database.db.query(
      'app_settings',
      columns: ['key', 'value', 'updated_at'],
      where: "key LIKE 'document_ref:%' AND value = ?",
      whereArgs: [reference.trim().toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final normalizedReference = reference.trim().toUpperCase();
    final key = '${rows.first['key']}';
    final parts = key.split(':');
    final hash = await fingerprint(normalizedReference);
    final metaRows = await _database.db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: ['document_meta:$normalizedReference'], limit: 1);
    Map<String, dynamic> meta = const {};
    if (metaRows.isNotEmpty) {
      try {
        final decoded = jsonDecode('${metaRows.first['value']}');
        if (decoded is Map<String, dynamic>) meta = decoded;
      } catch (_) {}
    }
    return {
      'reference': '${rows.first['value']}',
      'type': '${meta['type'] ?? (parts.length > 1 ? parts[1] : 'DOC')}',
      'registered_at': '${meta['generated_at'] ?? rows.first['updated_at'] ?? ''}',
      'generated_by': '${meta['generated_by'] ?? ''}',
      'status': '${meta['status'] ?? 'valid'}',
      if (hash != null) 'sha256': hash,
    };
  }


  Future<void> revoke(String reference) async {
    final normalizedReference = reference.trim().toUpperCase();
    final rows = await _database.db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: ['document_meta:$normalizedReference'], limit: 1);
    if (rows.isEmpty) return;
    Map<String, dynamic> meta = {};
    try {
      final decoded = jsonDecode('${rows.first['value']}');
      if (decoded is Map<String, dynamic>) meta = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    meta['status'] = 'revoked';
    meta['revoked_at'] = DateTime.now().toIso8601String();
    await _database.db.insert('app_settings', {
      'key': 'document_meta:$normalizedReference',
      'value': jsonEncode(meta),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> fingerprint(String reference) async {
    final rows = await _database.db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: ['document_sha256:$reference'], limit: 1);
    return rows.isEmpty ? null : '${rows.first['value']}';
  }
}
