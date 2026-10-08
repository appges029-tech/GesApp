import 'package:sqflite_common/sqlite_api.dart';

DatabaseFactory get platformDatabaseFactory =>
    throw UnsupportedError('Plateforme SQLite non supportée.');
Future<String> platformDatabasePath() async => 'gesapp.db';
void configurePlatformDatabase() {}
Future<void> preparePlatformDatabase(String path) async {}
Future<void> configurePlatformDatabaseConnection(Database database) async {}
