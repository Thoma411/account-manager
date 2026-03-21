/*
 * @Author: Thoma4
 * @Date: 2026-03-21 17:27:11
 * @LastEditTime: 2026-03-21 18:48:55
 * @Description: 加解密方法
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart' as pc;

class SecurityService {
  Key? _currentDataKey; // DK 应用锁定或退出时应置为 null
  void setDK(Key key) => _currentDataKey = key;
  Key? get currentDataKey => _currentDataKey;
  void clearKeys() => _currentDataKey = null; // 清理内存

  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  // 生成真随机数 (用于 Salt, DK, RK)
  Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  // 密钥派生函数 (PBKDF2): 将 MP 转换为 MK
  Key deriveMasterKey(String password, Uint8List salt) {
    // 显式指定使用 SHA256 摘要和 HMAC 运算
    final pc.PBKDF2KeyDerivator derivator = pc.PBKDF2KeyDerivator(
      pc.HMac(pc.SHA256Digest(), 64), // 64 是 SHA256 的块大小 (Block Size)
    );
    // 设置参数：盐值、迭代次数、期望输出密钥长度（32字节=256位）
    derivator.init(pc.Pbkdf2Parameters(salt, 100000, 32));
    final keyBytes = derivator.process(
      Uint8List.fromList(utf8.encode(password)),
    );
    return Key(keyBytes);
  }

  // 核心加密方法 (AES-256-GCM) 返回格式：IV(12字节) + Ciphertext
  String encrypt(String plainText, Key key) {
    final iv = IV(generateRandomBytes(12)); // GCM 建议使用 12 字节 IV
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm, padding: null));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // 将 IV 和密文合并存储 (Base64编码)
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setRange(0, iv.bytes.length, iv.bytes);
    combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);
    return base64.encode(combined);
  }

  // 核心解密方法
  String decrypt(String encodedData, Key key) {
    final combined = base64.decode(encodedData);
    final iv = IV(combined.sublist(0, 12));
    final ciphertext = combined.sublist(12);

    final encrypter = Encrypter(AES(key, mode: AESMode.gcm, padding: null));
    return encrypter.decrypt(Encrypted(ciphertext), iv: iv);
  }
}
