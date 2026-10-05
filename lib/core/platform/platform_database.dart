import 'package:sqflite_common/sqlite_api.dart';

import 'platform_database_stub.dart'
    if (dart.library.io) 'platform_database_io.dart'
    if (dart.library.html) 'platform_database_web.dart' as impl;

DatabaseFactory get platformDatabaseFactory => impl.platformDatabaseFactory;
Future<String> platformDatabasePath() => impl.platformDatabasePath();
void configurePlatformDatabase() => impl.configurePlatformDatabase();
