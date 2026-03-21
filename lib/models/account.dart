/*
 * @Author: Thoma4
 * @Date: 2026-02-12 21:55:09
 * @LastEditTime: 2026-03-21 20:43:27
 * @Description: 13字段实体定义
 */

import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../services/security_service.dart';

class Account {
  // 1. 系统主键
  final String id;

  // 2. 平台相关 (0-3)
  String platform; // 0: platform
  String pfType; // 1: pf_type
  String? pfRemark; // 2: pf_remark
  List<String> tags; // 3: tag (新增位置)

  // 3. 凭据相关 (4-8)
  String name; // 4: name
  String userId; // 5: USER_ID
  String email; // 6: EMAIL
  String pswd; // 7: PSWD
  String phone; // 8: PHONE

  // 4. 辅助信息 (9-12)
  String? birth; // 9: birth
  String? infoRemark; // 10: info_remark
  String signupDate; // 11: signup_date
  bool realName; // 12: real_name
  String lastModified; // 13: 最后修改时间

  Account({
    required this.id,
    required this.platform,
    required this.pfType,
    this.pfRemark,
    this.tags = const [],
    required this.name,
    required this.userId,
    required this.email,
    required this.pswd,
    required this.phone,
    this.birth,
    this.infoRemark,
    required this.signupDate,
    this.realName = false,
    required this.lastModified,
  });

  // 从 CSV 行数据映射为对象
  factory Account.fromCsv(List<dynamic> row) {
    // 假设 CSV 严格按照 0-12 的列顺序
    return Account(
      id: const Uuid().v4(),
      platform: row[0]?.toString() ?? "",
      pfType: row[1]?.toString() ?? "",
      pfRemark: row[2]?.toString(),
      // 字段 3 处理：假设 CSV 中 tags 以逗号分隔，如 "娱乐,工作"
      tags: row[3] != null && row[3].toString().isNotEmpty
          ? row[3].toString().split(',')
          : [],
      name: row[4]?.toString() ?? "",
      userId: row[5]?.toString() ?? "",
      email: row[6]?.toString() ?? "",
      pswd: row[7]?.toString() ?? "",
      phone: row[8]?.toString() ?? "",
      birth: row[9]?.toString(),
      infoRemark: row[10]?.toString(),
      signupDate: row[11]?.toString() ?? "",
      // 处理实名标记：如果是 'true' 或 '是' 则为 true
      realName:
          row[12]?.toString().toLowerCase() == 'true' ||
          row[12]?.toString() == '是',
      lastModified: DateTime.now().toIso8601String(),
    );
  }

  // 转换为数据库存储的 Map
  Map<String, dynamic> toMap() {
    final sec = SecurityService();
    final dk = sec.currentDataKey;

    // 辅助加密函数：如果有 DK 则加密，否则保持原样（防御性编程）
    String encryptIfPossible(String value) {
      if (dk != null && value.isNotEmpty) {
        return sec.encrypt(value, dk);
      }
      return value;
    }

    return {
      'id': id,
      'platform': platform,
      'pf_type': pfType,
      'pf_remark': pfRemark,
      'tags': jsonEncode(tags), // List 转 JSON 字符串

      'name': encryptIfPossible(name), // 加密昵称
      'user_id': encryptIfPossible(userId), // 加密ID
      'email': encryptIfPossible(email), // 加密邮箱
      'pswd': encryptIfPossible(pswd), // 加密密码
      'phone': encryptIfPossible(phone), // 加密手机号
      'birth': encryptIfPossible(birth ?? ""), // 加密生日
      'info_remark': encryptIfPossible(infoRemark ?? ""), //加密备注

      'signup_date': signupDate,
      'real_name': realName ? 1 : 0, // SQLite 不直接支持 bool
      'last_modified': lastModified,
    };
  }

  // 从数据库 Map 还原
  factory Account.fromMap(Map<String, dynamic> map) {
    final sec = SecurityService();
    final dk = sec.currentDataKey;

    // 辅助解密函数
    String decryptIfPossible(dynamic value) {
      if (value == null || value.toString().isEmpty) return "";
      if (dk != null) {
        try {
          return sec.decrypt(value.toString(), dk);
        } catch (e) {
          return "[解密失败]"; // 可能是因为旧数据是明文，或者钥匙不对
        }
      }
      return value.toString();
    }

    return Account(
      id: map['id'],
      platform: map['platform'],
      pfType: map['pf_type'],
      pfRemark: map['pf_remark'],
      tags: List<String>.from(jsonDecode(map['tags'] ?? '[]')),

      name: decryptIfPossible(map['name']), // 解密昵称
      userId: decryptIfPossible(map['user_id']), // 解密ID
      email: decryptIfPossible(map['email']), // 解密邮箱
      pswd: decryptIfPossible(map['pswd']), // 解密密码
      phone: decryptIfPossible(map['phone']), // 解密手机号
      birth: decryptIfPossible(map['birth']), // 解密生日
      infoRemark: decryptIfPossible(map['info_remark']), // 解密备注

      signupDate: map['signup_date'],
      realName: map['real_name'] == 1,
      lastModified: map['last_modified'] ?? DateTime.now().toIso8601String(),
    );
  }
}
