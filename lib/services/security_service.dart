/*
 * @Author: Thoma4
 * @Date: 2026-03-21 17:27:11
 * @LastEditTime: 2026-06-04 17:40:45
 * @Description: 加解密方法
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart' as pc;

import 'storage_service.dart';

class SecurityService {
  Key? _currentDataKey; // DK应用锁定或退出时应置为null
  void setDK(Key key) => _currentDataKey = key;
  Key? get currentDataKey => _currentDataKey;
  void clearKeys() => _currentDataKey = null; // 清理内存

  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  // 生成真随机数(用于Salt, DK, RK)
  Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  // 密钥派生函数(PBKDF2): 将MP转换为MK
  Key deriveMasterKey(String password, Uint8List salt) {
    // 显式指定使用SHA256摘要和HMAC运算
    final pc.PBKDF2KeyDerivator derivator = pc.PBKDF2KeyDerivator(
      pc.HMac(pc.SHA256Digest(), 64), // 64是SHA256的块大小(Block Size)
    );
    // 设置参数：盐值、迭代次数、期望输出密钥长度(32字节=256位)
    derivator.init(pc.Pbkdf2Parameters(salt, 100000, 32));
    final keyBytes = derivator.process(
      Uint8List.fromList(utf8.encode(password)),
    );
    return Key(keyBytes);
  }

  // 核心加密方法 (AES-256-GCM) 返回格式：IV(12字节) + Ciphertext
  String encrypt(String plainText, Key key) {
    final iv = IV(generateRandomBytes(12)); // GCM建议使用12字节IV
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm, padding: null));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // 将IV和密文合并存储 (Base64编码)
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

  // 轮转恢复密钥RK(重置RK)
  Future<String> rotateRecoveryKey() async {
    final storage = StorageService();
    final dk = currentDataKey; // 此时内存中必须已经有DK(无论是解锁得来的还是找回得来的)
    if (dk == null) throw "加密环境未就绪";
    // 1. 生成全新随机RK
    final newRkBytes = generateRandomBytes(32);
    final newRkString = base64.encode(newRkBytes);
    final newRkKey = Key(newRkBytes);
    // 2. 重新包装EDK_R(用新RK锁住DK)
    final dkBase64 = base64.encode(dk.bytes);
    final newEdkR = encrypt(dkBase64, newRkKey);
    // 3. 重新包装ERK(用DK锁住新RK)
    final newErk = encrypt(newRkString, dk);
    // 4. 持久化到数据库
    await storage.saveMetadata('edk_r', newEdkR);
    await storage.saveMetadata('erk', newErk);
    return newRkString;
  }
}
