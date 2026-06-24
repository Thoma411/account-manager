/*
 * @Author: Thoma4
 * @Date: 2026-06-24 22:13:52
 * @LastEditTime: 2026-06-24 22:27:25
 * @Description: 视觉样式&辅助组件工具类
 */

import 'package:flutter/material.dart';

class AccountUiUtils {
  AccountUiUtils._();

  // 将数字状态码转换为易读文字
  static String getStatusText(int status) {
    const map = {0: "未注册", 1: "使用中", 2: "已注销", 3: "无法使用"};
    return map[status] ?? "未知";
  }

  // 获取状态对应的颜色
  static Color getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.green.shade400; // 使用中
      case 0:
        return Colors.amber.shade400; // 未注册
      case 2:
        return Colors.grey.shade400; // 已注销
      case 3:
        return Colors.red.shade400; // 无法使用
      default:
        return Colors.blue.shade400;
    }
  }

  // 构建表格中的彩色状态标签
  static Widget buildStatusChip(int status) {
    Color color;
    switch (status) {
      case 1:
        color = Colors.green;
        break;
      case 2:
        color = Colors.grey;
        break;
      case 3:
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        getStatusText(status),
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }

  // 构建统一卡片图标的首字母占位符
  static Widget buildPlaceholder(
    String platform,
    Color statusColor,
    double size, // 方块边长
    double fontSize, // 字母大小
    double borderRadius,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: statusColor.withValues(alpha: 0.2), width: 1),
      ),
      child: Center(
        child: Text(
          platform.isNotEmpty ? platform[0].toUpperCase() : "?",
          style: TextStyle(
            color: statusColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
