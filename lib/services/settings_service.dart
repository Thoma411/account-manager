/*
 * @Author: Thoma4
 * @Date: 2026-04-08 17:43:09
 * @LastEditTime: 2026-04-08 18:04:00
 * @Description: 设置
 */

import 'package:sqflite/sqflite.dart';

import 'security_service.dart';
import 'storage_service.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final StorageService _storage = StorageService();
  final SecurityService _sec = SecurityService();

  // 内存缓存: 所有配置项都存在这里
  final Map<String, String> _cache = {};

  // 1. 初始化: 从数据库全量加载到内存
  Future<void> loadSettings() async {
    final db = await _storage.database;
    final List<Map<String, dynamic>> maps = await db.query('app_settings');

    _cache.clear();
    for (var map in maps) {
      String key = map['key'];
      String value = map['value'];
      bool isEncrypted = map['is_encrypted'] == 1;

      // 如果是加密项, 则尝试解密
      if (isEncrypted) {
        final dk = _sec.currentDataKey;
        if (dk != null) {
          try {
            value = _sec.decrypt(value, dk);
          } catch (_) {}
        }
      }
      _cache[key] = value;
    }
  }

  // 2. 读取配置 (从内存读, 极快)
  String? get(String key, {String? defaultValue}) {
    return _cache[key] ?? defaultValue;
  }

  // 3. 写入配置 (内存先变, 异步写盘)
  Future<void> set(String key, String value, {bool isEncrypted = false}) async {
    // 更新缓存
    _cache[key] = value;

    // 准备持久化内容
    String valueToSave = value;
    if (isEncrypted) {
      final dk = _sec.currentDataKey;
      if (dk != null) {
        valueToSave = _sec.encrypt(value, dk);
      }
    }

    // 异步写入数据库, 不阻塞 UI
    final db = await _storage.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': valueToSave, 'is_encrypted': isEncrypted ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
