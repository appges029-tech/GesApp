import 'package:shared_preferences/shared_preferences.dart';

class AutomaticBackupService {
  static const _enabled='gesapp.auto_backup.enabled';
  static const _intervalDays='gesapp.auto_backup.interval_days';
  static const _last='gesapp.auto_backup.last_success';

  static Future<bool> runIfDue() async => false;

  static Future<void> configure({required bool enabled,required int intervalDays}) async {
    final p=await SharedPreferences.getInstance();
    await p.setBool(_enabled,enabled);
    await p.setInt(_intervalDays,intervalDays.clamp(1,30));
  }

  static Future<Map<String,Object?>> settings() async {
    final p=await SharedPreferences.getInstance();
    return {'enabled':p.getBool(_enabled)??true,'interval_days':p.getInt(_intervalDays)??3,'last_success':p.getString(_last)};
  }
}
