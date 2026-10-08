import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _databaseKeyStorageKey = 'gesapp.database.sqlcipher.key.v1';
const _secureStorage = FlutterSecureStorage();
String? _releaseDatabaseKey;

bool get _encryptWindowsDatabase => Platform.isWindows && kReleaseMode;

void configurePlatformDatabase() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    mobile.databaseFactory = databaseFactoryFfi;
  }
}

DatabaseFactory get platformDatabaseFactory {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return mobile.databaseFactory;
}

Future<String> platformDatabasePath() async {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    final root = await databaseFactoryFfi.getDatabasesPath();
    return p.join(root, 'gesapp.db');
  }
  final root = await mobile.getDatabasesPath();
  return p.join(root, 'gesapp.db');
}

/// Chiffrement au repos Windows.
///
/// L'ancienne base en clair est convertie une seule fois avec
/// sqlcipher_export() dans un fichier temporaire. Le remplacement n'a lieu
/// qu'après vérification de l'intégrité du fichier chiffré.
Future<void> preparePlatformDatabase(String path) async {
  if (!_encryptWindowsDatabase) return;

  sqfliteFfiInit();
  final key = _releaseDatabaseKey ??= await _loadOrCreateDatabaseKey();
  _assertSqlCipherRuntime();

  final source = File(path);
  if (!await source.exists() || await source.length() == 0) return;

  await _migratePlaintextDatabaseIfNeeded(path, key);
}

Future<void> configurePlatformDatabaseConnection(Database database) async {
  if (!_encryptWindowsDatabase) return;

  final key = _releaseDatabaseKey ??= await _loadOrCreateDatabaseKey();
  await database.execute("PRAGMA key = \"x'$key'\";");
  final cipher = await database.rawQuery('PRAGMA cipher_version');
  if (cipher.isEmpty ||
      cipher.first.values.every(
        (value) => value == null || value.toString().trim().isEmpty,
      )) {
    throw StateError(
      'SQLCipher n’est pas disponible. GesApp refuse d’ouvrir la base locale en clair.',
    );
  }

  // Force une lecture de la première page : une clé incorrecte doit arrêter
  // immédiatement le démarrage au lieu de produire une nouvelle base vide.
  await database.rawQuery('SELECT count(*) AS n FROM sqlite_master');
}

Future<String> _loadOrCreateDatabaseKey() async {
  final existing = await _secureStorage.read(key: _databaseKeyStorageKey);
  if (existing != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(existing)) {
    return existing.toLowerCase();
  }

  final random = Random.secure();
  final key = List<int>.generate(32, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  await _secureStorage.write(key: _databaseKeyStorageKey, value: key);
  return key;
}

void _assertSqlCipherRuntime() {
  final db = sqlite.sqlite3.openInMemory();
  try {
    final cipher = db.select('PRAGMA cipher_version;');
    if (cipher.isEmpty ||
        cipher.first.values.every(
          (value) => value == null || value.toString().trim().isEmpty,
        )) {
      throw StateError(
        'Le runtime SQLite chargé n’est pas SQLCipher. '
        'La production Windows ne peut pas démarrer sans chiffrement.',
      );
    }
  } finally {
    db.close();
  }
}

Future<void> _migratePlaintextDatabaseIfNeeded(
  String path,
  String key,
) async {
  final probe = sqlite.sqlite3.open(path);
  var probeClosed = false;
  try {
    final cipher = probe.select('PRAGMA cipher_version;');
    if (cipher.isEmpty) {
      throw StateError('SQLCipher indisponible pendant la migration locale.');
    }

    var plaintext = false;
    try {
      probe.select('SELECT count(*) FROM sqlite_master;');
      plaintext = true;
    } on Object {
      plaintext = false;
    }

    if (!plaintext) {
      probe.close();
      probeClosed = true;
      await _verifyEncryptedDatabase(path, key);
      return;
    }

    try {
      probe.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } on Object {
      // Une base en journal DELETE/TRUNCATE n'a rien à checkpoint.
    }

    final userVersionRows = probe.select('PRAGMA user_version;');
    final userVersion = userVersionRows.isEmpty
        ? 0
        : (userVersionRows.first.values.first as num?)?.toInt() ?? 0;

    final encryptedPath = '$path.sqlcipher-migration';
    final encryptedFile = File(encryptedPath);
    if (await encryptedFile.exists()) await encryptedFile.delete();

    final escapedPath = encryptedPath.replaceAll("'", "''");
    probe.execute(
      "ATTACH DATABASE '$escapedPath' AS encrypted KEY \"x'$key'\";",
    );
    try {
      probe.execute("SELECT sqlcipher_export('encrypted');");
      probe.execute('PRAGMA encrypted.user_version = $userVersion;');
    } finally {
      probe.execute('DETACH DATABASE encrypted;');
    }

    probe.close();
    probeClosed = true;
    await _verifyEncryptedDatabase(encryptedPath, key);

    final source = File(path);
    final safety = File('$path.before-sqlcipher');
    if (await safety.exists()) await safety.delete();

    await source.rename(safety.path);
    try {
      await encryptedFile.rename(path);
      await _verifyEncryptedDatabase(path, key);
      if (await safety.exists()) await safety.delete();

      // Les journaux d'une ancienne base claire ne doivent pas rester sur le
      // disque après une migration réussie.
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$path$suffix');
        if (await sidecar.exists()) {
          try {
            await sidecar.delete();
          } on Object {
            // Non bloquant : la base principale est déjà chiffrée et vérifiée.
          }
        }
      }
    } catch (_) {
      final current = File(path);
      if (await current.exists()) await current.delete();
      if (await safety.exists()) await safety.rename(path);
      rethrow;
    }
  } finally {
    if (!probeClosed) probe.close();
  }
}

Future<void> _verifyEncryptedDatabase(String path, String key) async {
  final db = sqlite.sqlite3.open(path);
  try {
    final cipher = db.select('PRAGMA cipher_version;');
    if (cipher.isEmpty) {
      throw StateError('SQLCipher indisponible pendant la vérification.');
    }
    db.execute("PRAGMA key = \"x'$key'\";");
    db.select('SELECT count(*) FROM sqlite_master;');
    final integrity = db.select('PRAGMA integrity_check;');
    if (integrity.length != 1 ||
        integrity.first.values.first.toString().toLowerCase() != 'ok') {
      throw StateError(
        'La base SQLCipher locale a échoué au contrôle d’intégrité.',
      );
    }
  } finally {
    db.close();
  }
}

Future<List<int>> readPortableDatabaseBytes(String path) async {
  if (!_encryptWindowsDatabase) {
    return File(path).readAsBytes();
  }

  final key = _releaseDatabaseKey ??= await _loadOrCreateDatabaseKey();
  _assertSqlCipherRuntime();

  final tempPath = '$path.portable-export';
  final tempFile = File(tempPath);
  if (await tempFile.exists()) await tempFile.delete();

  final db = sqlite.sqlite3.open(path);
  try {
    db.execute("PRAGMA key = \"x'$key'\";");
    db.select('SELECT count(*) FROM sqlite_master;');

    final escapedPath = tempPath.replaceAll("'", "''");
    db.execute("ATTACH DATABASE '$escapedPath' AS portable KEY '';");
    try {
      db.execute("SELECT sqlcipher_export('portable');");
      final userVersionRows = db.select('PRAGMA user_version;');
      final userVersion = userVersionRows.isEmpty
          ? 0
          : (userVersionRows.first.values.first as num?)?.toInt() ?? 0;
      db.execute('PRAGMA portable.user_version = $userVersion;');
    } finally {
      db.execute('DETACH DATABASE portable;');
    }
  } finally {
    db.close();
  }

  try {
    // Ouvre la copie sans clé pour garantir qu'elle est réellement portable.
    final check = sqlite.sqlite3.open(tempPath);
    try {
      check.select('SELECT count(*) FROM sqlite_master;');
      final integrity = check.select('PRAGMA integrity_check;');
      if (integrity.length != 1 ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError(
          'La copie SQLite portable a échoué au contrôle d’intégrité.',
        );
      }
    } finally {
      check.close();
    }
    return await tempFile.readAsBytes();
  } finally {
    if (await tempFile.exists()) await tempFile.delete();
  }
}
