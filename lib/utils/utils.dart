/*
 * @Author: Thoma4
 * @Date: 2026-02-22 14:30:59
 * @LastEditTime: 2026-04-13 18:31:42
 * @Description: 工具类
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateUtil {
  /// 将 ISO8601 字符串转换为 yyyy-MM-dd HH:mm 格式
  static String format(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "无记录";
    try {
      DateTime dt = DateTime.parse(isoString);
      // 使用 DateFormat，一行解决所有拼接问题
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (e) {
      return isoString;
    }
  }
}

class MessageUtil {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400, // 桌面端建议固定宽度居中
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
