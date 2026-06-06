/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:42:38
 * @LastEditTime: 2026-06-06 15:37:12
 * @Description: CSV处理
 */

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import 'storage_service.dart';

class CsvService {
  final StorageService _storageService = StorageService();

  /// 唤起文件选择并导入CSV数据
  Future<int> pickAndImportCsv() async {
    try {
      // 1. 选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) {
        return 0; // 用户取消
      }
      // 2. 读取文件
      final File file = File(result.files.single.path!);
      // 注意：Windows Excel默认导出的CSV往往是GBK编码
      // 如果读取时报错"Invalid UTF-8"，请尝试使用latin1或安装charset包处理GBK
      final String csvContent = await file.readAsString(encoding: utf8);
      // 3. 解析 CSV
      List<List<dynamic>> rows = const CsvToListConverter().convert(csvContent);
      if (rows.isEmpty) return 0;
      int successCount = 0;
      // 4. 遍历并存入数据库(假设第一行是表头，从第2行开始)
      for (int i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.length < 13) continue; // 检查列数是否足够（至少13列）
          Account acc = Account.fromCsv(row); // 调用 Account 模型的 factory 方法
          await _storageService.insertAccount(acc);
          successCount++;
        } catch (e) {
          debugPrint("导入第 $i 行失败: $e");
        }
      }
      return successCount;
    } catch (e) {
      debugPrint("CSV导入服务异常: $e");
      return 0;
    }
  }
}
