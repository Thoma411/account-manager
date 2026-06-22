/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:00:56
 * @LastEditTime: 2026-06-20 21:54:01
 * @Description: 与SQLite交互的方法
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/account.dart';
import 'settings_service.dart';
import 'icon_service.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  static Database? _database;

  factory StorageService() => _instance;
  StorageService._internal();

  Future<Database> get database async {
    if (_database != null) {
      if (!await isDatabaseExists()) {
        _database = null;
        throw Exception("数据库文件丢失，请重启应用");
      }
      return _database!;
    }
    _database = await _initDB();
    return _database!;
  }

  // 关闭数据库连接并释放文件句柄
  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null; // 必须置空，以便下次调用 database 属性时触发 _initDB
      debugPrint("数据库连接已安全关闭");
    }
  }

  // 获取数据库的完整物理路径
  Future<String> getDatabasePath() async {
    if (Platform.isWindows) {
      sqfliteFfiInit(); // 仅Windows需要
      final dbPath = await databaseFactoryFfi.getDatabasesPath();
      return join(dbPath, 'vault_keeper.db');
    } else {
      // Android路径获取
      final directory = await getApplicationDocumentsDirectory();
      return join(directory.path, 'vault_keeper.db');
    }
  }

  // 判断数据库是否存在
  Future<bool> isDatabaseExists() async {
    try {
      return await File(await getDatabasePath()).exists();
    } catch (e) {
      debugPrint("探测数据库失败: $e");
      return false;
    }
  }

  // 初始化数据库
  Future<Database> _initDB() async {
    String path;
    if (Platform.isWindows) {
      sqfliteFfiInit();
      final dbFactory = databaseFactoryFfi;
      final dbPath = await dbFactory.getDatabasesPath();
      path = join(dbPath, 'vault_keeper.db');
    } else {
      // Android/iOS
      final directory = await getApplicationDocumentsDirectory();
      path = join(directory.path, 'vault_keeper.db');
    }
    debugPrint("db real path: $path");

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 创建账户条目表
        await db.execute('''
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY, platform TEXT, url TEXT,
              status INTEGER, tags TEXT,
              name TEXT, user_id TEXT, email TEXT, pswd TEXT,
              phone TEXT, birth TEXT,
              notes TEXT, signup_date TEXT, real_name INTEGER,
              last_modified TEXT
            )
          ''');
        // 创建系统元数据表
        await db.execute('''
            CREATE TABLE system_metadata (
              key TEXT PRIMARY KEY, value TEXT
            )
          ''');
        // 创建设置表
        await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY, value TEXT,
              is_encrypted INTEGER DEFAULT 0
            )
          ''');
      },
    );
  }

  // 更新逻辑版本号
  Future<void> _incrementRevision() async {
    final s = SettingsService();
    // 读取当前版本号 默认为'0'
    int currentRev = int.parse(s.get('local_revision', defaultValue: '0')!);
    // 版本号+1并保存
    await s.set('local_revision', (currentRev + 1).toString());
    debugPrint("logicalVersion upd: ${currentRev + 1}");
  }

  // 插入数据
  Future<void> insertAccount(Account account) async {
    final db = await database;
    await db.insert(
      'accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _incrementRevision();
  }

  // 删除数据
  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(
      'accounts',
      where: 'id = ?', // 根据唯一ID删除
      whereArgs: [id],
    );
    await IconService().deleteIcon(id); // 删除对应图标(若有)
    await _incrementRevision();
  }

  // 获取所有数据
  Future<List<Account>> getAllAccounts() async {
    // 文件不存在时直接返回空列表 不触发数据库初始化
    bool exists = await isDatabaseExists();
    if (!exists) return [];

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      orderBy: 'platform COLLATE NOCASE ASC',
    );
    return List.generate(maps.length, (i) => Account.fromMap(maps[i]));
  }

  // 存储元数据
  Future<void> saveMetadata(String key, String value) async {
    final db = await database;
    await db.insert('system_metadata', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 取元数据
  Future<String?> getMetadata(String key) async {
    final db = await database;
    final results = await db.query(
      'system_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isNotEmpty) return results.first['value'] as String;
    return null;
  }

  // 检查指定平台名是否存在
  Future<bool> isPlatformNameExists(
    String platformName, {
    String? excludeId,
  }) async {
    final db = await database;
    // 如果提供了excludeId(修改场景)则排除掉该ID对应的记录
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: excludeId == null
          ? 'LOWER(platform) = ?'
          : 'LOWER(platform) = ? AND id != ?',
      whereArgs: excludeId == null
          ? [platformName.toLowerCase().trim()]
          : [platformName.toLowerCase().trim(), excludeId],
    ); // 不区分大小写
    return maps.isNotEmpty;
  }

  // 检查指定账户是否存在
  Future<bool> isAccountExists(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return res.isNotEmpty;
  }
}
