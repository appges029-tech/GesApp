import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
