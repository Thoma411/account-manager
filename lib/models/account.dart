/*
 * @Author: Thoma4
 * @Date: 2026-02-12 21:55:09
 * @LastEditTime: 2026-06-16 20:42:55
 * @Description: 13字段实体定义
 */

import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:lpinyin/lpinyin.dart';

import '../services/security_service.dart';

class Account {
  final String id;
  // 明文字段
  String platform; // 1. 平台名
  late final String platformPinyin; // 拼音缓存(用于排序比较)
  String url; // 2. 网址
  int status; // 3. 状态: 0未注册, 1使用中, 2已注销, 3无法使用
  List<String> tags; // 4. 标签
  DateTime? signupDate; // 5. 注册日期
  bool realName; // 6. 实名标记
  String lastModified; // 7. 修改时间
  // 密文字段
  String name; // 8. 昵称
  String userId; // 9. 账号
  String email; // 10. 邮箱
  String pswd; // 11. 密码
  String phone; // 12. 手机
  DateTime? birth; // 13. 生日
  String? notes; // 14. 备注(合并自pf_remark&info_remark)

  Account({
    required this.id,
    required String platform,
    required String url,
    required this.status,
    this.tags = const [],
    required String name,
    required String userId,
    required String email,
    required this.pswd,
    required String phone,
    this.birth,
    this.notes,
    this.signupDate,
    required this.realName,
    required this.lastModified,
  }) : platform = platform.trim(),
       url = url.trim(),
       name = name.trim(),
       userId = userId.trim(),
       email = email.trim(),
       phone = phone.trim() {
    platformPinyin = PinyinHelper.getPinyinE(
      platform,
      separator: "",
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase(); // 中文->拼音
  }

  // 获取平台名的首字母
  String get firstLetter {
    if (platformPinyin.isEmpty) return "#";
    String char = platformPinyin[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(char) ? char : "#";
  }

  // 转换为数据库存储的Map
  Map<String, dynamic> toMap() {
    final sec = SecurityService();
    final dk = sec.currentDataKey;

    String enc(String val) =>
        (dk != null && val.isNotEmpty) ? sec.encrypt(val, dk) : val;

    return {
      'id': id,
      'platform': platform,
      'url': url,
      'status': status,
      'tags': jsonEncode(tags),
      // 敏感加密区
      'name': enc(name),
      'user_id': enc(userId),
      'email': enc(email),
      'pswd': enc(pswd),
      'phone': enc(phone),
      'birth': birth?.toIso8601String().split('T')[0],
      'notes': enc(notes ?? ""),
      // ---
      'signup_date': signupDate?.toIso8601String().split('T')[0],
      'real_name': realName ? 1 : 0,
      'last_modified': lastModified,
    };
  }

  // 从数据库Map还原
  factory Account.fromMap(Map<String, dynamic> map) {
    final sec = SecurityService();
    final dk = sec.currentDataKey;

    String dec(dynamic val) {
      if (val == null || val.toString().isEmpty) return "";
      try {
        return (dk != null) ? sec.decrypt(val.toString(), dk) : val.toString();
      } catch (_) {
        return "[解密失败]";
      }
    }

    return Account(
      id: map['id'],
      platform: map['platform'],
      url: map['url'] ?? "",
      status: map['status'] ?? 1,
      tags: List<String>.from(jsonDecode(map['tags'] ?? '[]')),
      name: dec(map['name']),
      userId: dec(map['user_id']),
      email: dec(map['email']),
      pswd: dec(map['pswd']),
      phone: dec(map['phone']),
      birth: (map['birth'] != null && map['birth'] != "")
          ? DateTime.tryParse(map['birth'])
          : null,
      notes: dec(map['notes']),
      signupDate: (map['signup_date'] != null && map['signup_date'] != "")
          ? DateTime.tryParse(map['signup_date'])
          : null,
      realName: map['real_name'] == 1,
      lastModified: map['last_modified'] ?? DateTime.now().toIso8601String(),
    );
  }

  // 从CSV行数据映射为对象
  factory Account.fromCsv(List<dynamic> row) {
    // 尝试解析常见日期格式
    DateTime? parseCsvDate(dynamic val) {
      if (val == null) return null;
      String dateStr = val.toString().trim();
      if (dateStr.isEmpty) return null; // 空串直接返回null
      String normalized = dateStr.replaceAll(RegExp(r'[/.]'), '-');
      return DateTime.tryParse(normalized); // 尝试解析，失败返回null
    }

    return Account(
      id: const Uuid().v4(),
      platform: row[0]?.toString() ?? "",
      name: row[1]?.toString() ?? "",
      userId: row[2]?.toString() ?? "",
      email: row[3]?.toString() ?? "",
      pswd: row[4]?.toString() ?? "",
      url: row[5]?.toString() ?? "",
      phone: row[6]?.toString() ?? "",
      birth: parseCsvDate(row[7]),
      notes: row[8]?.toString(),
      signupDate: parseCsvDate(row[9]),
      realName:
          row[10]?.toString() == '1' ||
          row[10]?.toString() == 'true' ||
          row[10]?.toString() == '是',
      tags: row[11] != null && row[11].toString().isNotEmpty
          ? row[11].toString().split(',')
          : [],
      status: int.tryParse(row[12]?.toString() ?? "1") ?? 1,
      lastModified: DateTime.now().toIso8601String(),
    );
  }

  // 转换为CSV行
  List<dynamic> toCsvRow() {
    String formatExportDate(DateTime? dt) {
      if (dt == null) return "";
      return DateFormat('yyyy-MM-dd').format(dt);
    }

    return [
      platform, // 0
      name, // 1
      userId, // 2
      email, // 3
      pswd, // 4
      url, // 5
      phone, // 6
      formatExportDate(birth), // 7
      notes, // 8
      formatExportDate(signupDate), // 9
      realName ? '1' : '0', // 10
      tags.join(','), // 11
      status, // 12
    ];
  }
}
