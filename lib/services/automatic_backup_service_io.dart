import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/db/app_database.dart';
import 'backup_service.dart';

class AutomaticBackupService {
  static const _enabled='gesapp.auto_backup.enabled';
  static const _intervalDays='gesapp.auto_backup.interval_days';
  static const _secret='gesapp.auto_backup.secret';
  static const _last='gesapp.auto_backup.last_success';
  static const _secure = FlutterSecureStorage();

  static Future<bool> runIfDue() async {
    final prefs=await SharedPreferences.getInstance();
    if(!(prefs.getBool(_enabled)??true)) return false;
    final days=(prefs.getInt(_intervalDays)??3).clamp(1,30);
    final last=DateTime.tryParse(prefs.getString(_last)??'');
    if(last!=null && DateTime.now().difference(last)<Duration(days:days)) return false;
    var password=await _secure.read(key:_secret);
    // Migration unique depuis les anciennes versions qui utilisaient SharedPreferences.
    password ??= prefs.getString(_secret);
    if(password!=null){
      await _secure.write(key:_secret,value:password);
      await prefs.remove(_secret);
    }
    if(password==null){
      final r=Random.secure();
      password=List<int>.generate(32,(_)=>33+r.nextInt(90)).map(String.fromCharCode).join();
      await _secure.write(key:_secret,value:password);
    }
    final db=AppDatabase.instance;final path=await db.databasePath;
    try{
      await db.close();
      await BackupService().exportLocalDatabase(path,password:password,trustedSystem:true);
      await prefs.setString(_last,DateTime.now().toIso8601String());
      await _prune();
      return true;
    } finally {
      await db.initialize();
    }
  }

  static Future<void> _prune() async {
    final docs=await getApplicationDocumentsDirectory();final dir=Directory(p.join(docs.path,'backups'));if(!await dir.exists())return;
    final files=await dir.list().where((e)=>e is File&&e.path.endsWith('.gesbk')).cast<File>().toList();
    files.sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for(final f in files.skip(10)){try{await f.delete();}catch(_){}}
  }

  static Future<void> configure({required bool enabled,required int intervalDays}) async {final p=await SharedPreferences.getInstance();await p.setBool(_enabled,enabled);await p.setInt(_intervalDays,intervalDays.clamp(1,30));}
  static Future<Map<String,Object?>> settings() async {final p=await SharedPreferences.getInstance();return {'enabled':p.getBool(_enabled)??true,'interval_days':p.getInt(_intervalDays)??3,'last_success':p.getString(_last)};}
}
