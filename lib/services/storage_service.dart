/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:00:56
 * @LastEditTime: 2026-02-22 14:21:15
 * @Description: 与SQLite交互的方法
 */

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

import '../models/account.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  static Database? _database;

  factory StorageService() => _instance;
  StorageService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // Windows 端初始化数据库引擎
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'vault_keeper.db');
    debugPrint("db real path: $path");

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY,
              platform TEXT, pf_type TEXT, pf_remark TEXT, tags TEXT,
              name TEXT, user_id TEXT, email TEXT, pswd TEXT, phone TEXT, birth TEXT,
              info_remark TEXT, signup_date TEXT, real_name INTEGER, last_modified TEXT
            )
          ''');
        },
      ),
    );
  }

  // 插入数据
  Future<void> insertAccount(Account account) async {
    final db = await database;
    await db.insert(
      'accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(
      'accounts',
      where: 'id = ?', // 根据唯一 ID 删除
      whereArgs: [id],
    );
  }

  // 获取所有数据
  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    return List.generate(maps.length, (i) => Account.fromMap(maps[i]));
  }
}
