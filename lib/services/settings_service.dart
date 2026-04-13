/*
 * @Author: Thoma4
 * @Date: 2026-04-08 17:43:09
 * @LastEditTime: 2026-04-13 17:09:21
 * @Description: 设置
 */

import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security_service.dart';
import 'storage_service.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;
  final Map<String, String> _dbCache = {}; // 内存缓存数据库项

  // 定义哪些 Key 属于本地配置（不进数据库）
  final Set<String> _localKeys = {'dark_mode', 'language', 'window_size'};

  // 1. 初始化：应用启动即调用
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 2. 加载数据库项：仅在解锁成功后调用
  Future<void> loadDbSettings() async {
    if (!await StorageService().isDatabaseExists()) return;

    final db = await StorageService().database;
    final List<Map<String, dynamic>> maps = await db.query('app_settings');

    _dbCache.clear();
    final sec = SecurityService();
    final dk = sec.currentDataKey;

    for (var map in maps) {
      String key = map['key'];
      String value = map['value'];
      // 处理加密项
      if (map['is_encrypted'] == 1 && dk != null) {
        try {
          value = sec.decrypt(value, dk);
        } catch (_) {}
      }
      _dbCache[key] = value;
    }
  }

  // 3. 统一读取
  String? get(String key, {String? defaultValue}) {
    if (_localKeys.contains(key)) {
      return _prefs?.getString(key) ?? defaultValue;
    }
    return _dbCache[key] ?? defaultValue;
  }

  // 4. 统一写入
  Future<void> set(String key, String value, {bool isEncrypted = false}) async {
    // 路径 A: 本地配置项
    if (_localKeys.contains(key)) {
      await _prefs?.setString(key, value);
      return;
    }

    // 路径 B: 数据库配置项
    // 检查：如果数据库还没创建，拦截写入，防止非法建库
    if (!await StorageService().isDatabaseExists()) {
      throw Exception("请先初始化保险箱，再修改同步类设置项");
    }

    _dbCache[key] = value;
    String valueToSave = value;
    if (isEncrypted) {
      final dk = SecurityService().currentDataKey;
      if (dk != null) {
        valueToSave = SecurityService().encrypt(value, dk);
      }
    }

    final db = await StorageService().database;
    await db.insert('app_settings', {
      'key': key,
      'value': valueToSave,
      'is_encrypted': isEncrypted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
