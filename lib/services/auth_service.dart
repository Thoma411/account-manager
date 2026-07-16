/*
 * @Author: Thoma4
 * @Date: 2026-03-21 18:50:58
 * @LastEditTime: 2026-07-16 15:13:50
 * @Description: 解锁与认证
 */

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'security_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'webdav_service.dart';

class AuthService {
  final StorageService _storage = StorageService();
  final SecurityService _sec = SecurityService();

  // 验证主密码并解锁
  Future<bool> verifyPassword(String password) async {
    try {
      // 1. 从数据库读取解密所需的元数据
      final saltBase64 = await _storage.getMetadata('master_salt');
      final edkM = await _storage.getMetadata('edk_m');
      final evb = await _storage.getMetadata('evb');

      if (saltBase64 == null || edkM == null || evb == null) return false;

      // 2. 还原MK
      final Uint8List salt = base64.decode(saltBase64);
      final mk = _sec.deriveMasterKey(password, salt);

      // 3. 尝试用MK解开EDK_M得到DK
      final dkString = _sec.decrypt(edkM, mk); // 此时解出的是 Base64 格式的 DK
      final dk = enc.Key(base64.decode(dkString));

      // 4. 验证DK是否正确(通过解密EVB)
      final verifyResult = _sec.decrypt(evb, dk);

      if (verifyResult == "VAULT_READY") {
        // 5. 验证通过, 把DK存入内存供全应用使用
        _sec.setDK(dk);
        WebDavService().reset();
        await SettingsService().loadDbSettings();
        // 确保本地设备状态与数据库版本对齐
        final s = SettingsService();
        // 仅从云端下载新库重载后才对齐本地锚点
        if (s.get('need_revision_alignment') == 'true') {
          String? dbRev = s.get('local_revision');
          if (dbRev != null) {
            // 强制更新本地配置文件的快照
            await s.set('last_synced_revision', dbRev);
          }
          await s.set('need_revision_alignment', 'false');
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("解锁失败: $e"); // 可能是解密报错（密码错）
      return false;
    }
  }

  // 初始化新数据库逻辑已整合在 account_list_page 的对话框中，
  // 这里的 setupNewVault 暂时作为逻辑占位
  Future<void> setupNewVault(String password) async {
    await _storage.database;
  }
}
