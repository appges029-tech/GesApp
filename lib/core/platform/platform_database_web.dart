import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void configurePlatformDatabase() {}

DatabaseFactory get platformDatabaseFactory => databaseFactoryFfiWeb;

Future<String> platformDatabasePath() async => 'gesapp.db';
