/*
 * @Author: Thoma4
 * @Date: 2026-02-22 14:30:59
 * @LastEditTime: 2026-02-22 14:39:20
 * @Description: 工具类
 */

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
