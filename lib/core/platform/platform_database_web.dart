import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void configurePlatformDatabase() {}

DatabaseFactory get platformDatabaseFactory => databaseFactoryFfiWeb;

Future<String> platformDatabasePath() async => 'gesapp.db';

/// Le navigateur isole son stockage dans son sandbox/origine. Le runtime Web
/// ne partage pas le fichier Windows gesapp.db.
Future<void> preparePlatformDatabase(String path) async {}

Future<void> configurePlatformDatabaseConnection(Database database) async {}
