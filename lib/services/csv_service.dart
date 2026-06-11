/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:42:38
 * @LastEditTime: 2026-06-11 17:02:40
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

  // 唤起文件选择并导入CSV数据
  Future<(int success, int skipped)> pickAndImportCsv() async {
    try {
      // 1. 选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) {
        return (0, 0); // 用户取消
      }
      // 2. 读取文件
      final File file = File(result.files.single.path!);
      // 注意：Windows Excel默认导出的CSV往往是GBK编码
      // 如果读取时报错"Invalid UTF-8"，请尝试使用latin1或安装charset包处理GBK
      final String csvContent = await file.readAsString(encoding: utf8);
      // 3. 解析CSV
      List<List<dynamic>> rows = const CsvToListConverter().convert(csvContent);
      if (rows.isEmpty) return (0, 0);
      // 读取库中现存所有条目并获取其平台名
      final existingAccounts = await _storageService.getAllAccounts();
      final Set<String> existingNames = existingAccounts
          .map((a) => a.platform.toLowerCase().trim())
          .toSet();
      int successCount = 0, duplicateCount = 0;
      // 4. 遍历并存入数据库(假设第一行是表头 从第2行开始)
      for (int i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.length < 13) continue; // 检查列数是否足够(>=13列)
          // 查重
          String platformName = row[0]?.toString().trim() ?? "";
          if (platformName.isEmpty) continue;
          if (existingNames.contains(platformName.toLowerCase())) {
            duplicateCount++;
            debugPrint("skip: $platformName");
            continue;
          }
          Account acc = Account.fromCsv(row); // 调用Account模型的factory方法
          await _storageService.insertAccount(acc);
          existingNames.add(platformName.toLowerCase()); // 更新存在(重名)列表
          successCount++;
        } catch (e) {
          debugPrint("导入第 $i 行失败: $e");
        }
      }
      return (successCount, duplicateCount);
    } catch (e) {
      debugPrint("CSV导入服务异常: $e");
      return (0, 0);
    }
  }

  // 导出为CSV
  Future<bool> exportToCsv() async {
    try {
      // 1. 获取全量数据
      final accounts = await _storageService.getAllAccounts();
      if (accounts.isEmpty) throw Exception("数据库中暂无数据可导出");
      // 2. 构建CSV二维列表
      List<List<dynamic>> csvData = [
        [
          "platform",
          "name",
          "USER_ID",
          "EMAIL",
          "PSWD",
          "url",
          "PHONE",
          "birth",
          "notes",
          "signup_date",
          "real_name",
          "tag",
          "status",
        ],
      ]; // 表头
      csvData.addAll(accounts.map((acc) => acc.toCsvRow())); // 填充内容
      // 3. 转换为CSV字符串
      String csvString = const ListToCsvConverter().convert(csvData);
      // 4. 调用保存对话框
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择导出路径',
        fileName: 'vault_export_${DateTime.now().millisecondsSinceEpoch}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (outputFile == null) return false; // 用户取消
      // 5. 写入文件
      // 让Windows Excel自动识别为UTF-8编码，防止中文乱码
      final List<int> bom = [0xEF, 0xBB, 0xBF]; // 添加UTF-8 BOM头
      final List<int> content = utf8.encode(csvString);
      final File file = File(outputFile);
      await file.writeAsBytes(bom + content);
      return true;
    } catch (e) {
      debugPrint("导出失败: $e");
      rethrow;
    }
  }
}
