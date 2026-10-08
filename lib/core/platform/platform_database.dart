import 'package:sqflite_common/sqlite_api.dart';

import 'platform_database_stub.dart'
    if (dart.library.io) 'platform_database_io.dart'
    if (dart.library.html) 'platform_database_web.dart' as impl;

DatabaseFactory get platformDatabaseFactory => impl.platformDatabaseFactory;
Future<String> platformDatabasePath() => impl.platformDatabasePath();
void configurePlatformDatabase() => impl.configurePlatformDatabase();

/// Prépare les protections du fichier local avant l'ouverture SQLite.
/// Sur Windows release, cette étape génère/récupère la clé et migre de façon
/// atomique une ancienne base en clair vers SQLCipher.
Future<void> preparePlatformDatabase(String path) =>
    impl.preparePlatformDatabase(path);

/// Applique les paramètres indispensables immédiatement après l'ouverture
/// native de la connexion, avant toute lecture de schéma.
Future<void> configurePlatformDatabaseConnection(Database database) =>
    impl.configurePlatformDatabaseConnection(database);

/// Retourne une image SQLite portable. Sur Windows chiffré, une copie
/// temporaire déchiffrée est créée uniquement en mémoire de travail/disque
/// temporaire puis immédiatement supprimée après lecture. Le conteneur .gesbk
/// chiffre ensuite ces octets avec le mot de passe de sauvegarde.
Future<List<int>> readPortableDatabaseBytes(String path) =>
    impl.readPortableDatabaseBytes(path);
