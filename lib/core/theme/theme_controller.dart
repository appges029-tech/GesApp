import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../db/app_database.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final instance = ThemeController._();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final rows = await AppDatabase.instance.db.query('app_settings', where: 'key = ?', whereArgs: ['theme_mode'], limit: 1);
    if (rows.isEmpty) return;
    _mode = _fromValue(rows.first['value'] as String?);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final now = DateTime.now().toIso8601String();
    await AppDatabase.instance.db.insert(
      'app_settings',
      {'key': 'theme_mode', 'value': _toValue(mode), 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  ThemeMode _fromValue(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  String _toValue(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}
