/*
 * @Author: Thoma4
 * @Date: 2026-04-13 18:19:04
 * @LastEditTime: 2026-04-15 21:16:59
 * @Description: webdav
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webdav_client/webdav_client.dart' as dav;

import 'settings_service.dart';

class WebDavService {
  static final WebDavService _instance = WebDavService._internal();
  factory WebDavService() => _instance;
  WebDavService._internal();

  dav.Client? _client;
  String? _tempUrl, _tempUser, _tempPwd; // 用于恢复流程的临时凭据缓存

  // 确保url以斜杠结尾
  String _normalizeUrl(String url) {
    return url.endsWith('/') ? url : '$url/';
  }

  // 初始化客户端 (通用)
  void initCustomClient(String url, String user, String password) {
    _tempUrl = url;
    _tempUser = user;
    _tempPwd = password;
    _client = dav.newClient(url, user: user, password: password);
    _client!.setConnectTimeout(8000);
  }

  /// 初始化客户端: 从SettingsService读取配置
  bool initFromSettings() {
    final settings = SettingsService();
    final url = settings.get('webdav_url');
    final user = settings.get('webdav_user');
    final pwd = settings.get('webdav_pwd');

    if (url == null || user == null || pwd == null) return false;
    initCustomClient(url, user, pwd);
    return true;
  }

  /// 测试连接
  Future<bool> ping() async {
    if (_client == null && !initFromSettings()) return false;
    try {
      // 尝试列出根目录, 若不报错则说明账号密码正确
      await _client!.readDir('/');
      return true;
    } catch (e) {
      return false;
    }
  }

  // 获取云端备份文件的元数据 (用于 SyncPage 对比时间)
  Future<dav.File?> getRemoteVaultInfo() async {
    try {
      final files = await readDir('/vault_keeper');
      for (var f in files) {
        if (f.name == 'vault_keeper.db') return f;
      }
    } catch (e) {
      debugPrint("WebDAV: 未找到远程备份文件或目录: $e");
    }
    return null;
  }

  // 读取云端目录
  Future<List<dav.File>> readDir(String path) async {
    if (_client == null && !initFromSettings()) {
      throw Exception("WebDAV客户端未初始化");
    }
    return await _client!.readDir(path);
  }

  // 上传至云端（使用SettingsService中的已存配置）
  Future<void> uploadVault(String localPath) async {
    if (_client == null) initFromSettings();
    try {
      await _client!.mkdir('/vault_keeper');
    } catch (_) {}

    final s = SettingsService();
    return _doHttpRequest(
      url: s.get('webdav_url')!,
      user: s.get('webdav_user')!,
      pwd: s.get('webdav_pwd')!,
      method: 'PUT',
      localPath: localPath,
    );
  }

  // 下载至本地（优先使用临时凭据, 若无则使用已存配置）
  Future<void> downloadVault(String localPath) async {
    final s = SettingsService();
    return _doHttpRequest(
      url: _tempUrl ?? s.get('webdav_url')!,
      user: _tempUser ?? s.get('webdav_user')!,
      pwd: _tempPwd ?? s.get('webdav_pwd')!,
      method: 'GET',
      localPath: localPath,
    );
  }

  // 统一低层HTTP处理
  Future<void> _doHttpRequest({
    required String url,
    required String user,
    required String pwd,
    required String method,
    required String localPath,
  }) async {
    final auth = 'Basic ${base64.encode(utf8.encode('$user:$pwd'))}';
    final targetUri = Uri.parse(
      '${_normalizeUrl(url)}vault_keeper/vault_keeper.db',
    );
    if (method == 'PUT') {
      final bytes = await File(localPath).readAsBytes();
      final res = await http.put(
        targetUri,
        headers: {
          'Authorization': auth,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("上传失败: ${res.statusCode}");
      }
    } else {
      final res = await http.get(targetUri, headers: {'Authorization': auth});
      if (res.statusCode == 200) {
        await File(localPath).writeAsBytes(res.bodyBytes);
      } else {
        throw Exception("下载失败: ${res.statusCode}");
      }
    }
  }
}
