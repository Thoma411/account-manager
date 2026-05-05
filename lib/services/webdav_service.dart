/*
 * @Author: Thoma4
 * @Date: 2026-04-13 18:19:04
 * @LastEditTime: 2026-05-02 23:10:52
 * @Description: webdav
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webdav_client/webdav_client.dart' as dav;

import 'settings_service.dart';
import 'storage_service.dart';

class WebDavService {
  static final WebDavService _instance = WebDavService._internal();
  factory WebDavService() => _instance;
  WebDavService._internal();
  dav.Client? _client;
  // 统一存储当前生效的凭据（无论是临时的还是持久化的）
  String? _currentUrl, _currentUser, _currentPwd;

  // 1.初始化逻辑 (收口)
  // 手动初始化（用于登录前恢复或设置页测试）
  void initCustomClient(String url, String user, String password) {
    _currentUrl = url.endsWith('/') ? url : '$url/';
    _currentUser = user;
    _currentPwd = password;
    _client = dav.newClient(_currentUrl!, user: user, password: password);
    _client!.setConnectTimeout(8000);
  }

  // 自动初始化（从本地加密库读取）
  bool initFromSettings() {
    final settings = SettingsService();
    final url = settings.get('webdav_url');
    final user = settings.get('webdav_user');
    final pwd = settings.get('webdav_pwd');

    if (url == null || user == null || pwd == null) return false;
    initCustomClient(url, user, pwd);
    return true;
  }

  // 私有校验: 确保在执行任何网络操作前Client已就绪
  bool _ensureClient() {
    if (_client != null) return true;
    return initFromSettings();
  }

  // 2.业务查询接口(语义化封装)
  // 测试连通性: 仅用于验证凭据是否正确
  Future<bool> ping() async {
    if (!_ensureClient()) return false;
    try {
      // 尝试列出根目录, 若不报错则说明账号密码正确
      await _client!.readDir('/');
      return true;
    } catch (_) {
      return false;
    }
  }

  // 获取云端备份文件元数据(专供SyncPage对比使用)
  Future<dav.File?> getRemoteVaultInfo() async {
    try {
      final List<dav.File> files = await readDir('/vault_keeper');
      for (var f in files) {
        if (f.name == 'vault_keeper.db') return f;
      }
    } catch (e) {
      debugPrint("WebDAV: 无法定位远程文件: $e");
    }
    return null;
  }

  // 基础读取接口
  Future<List<dav.File>> readDir(String path) async {
    if (!_ensureClient()) throw Exception("WebDAV 客户端未初始化，请先配置云端信息");
    return await _client!.readDir(path);
  }

  // 本地云端版本比较
  Future<SyncDecision> compareVersions({int t = 1000}) async {
    try {
      final localPath = await StorageService().getDatabasePath();
      final localFile = File(localPath);
      if (!await localFile.exists()) return SyncDecision.error;

      final localMTime = (await localFile.stat()).modified;
      final remoteFile = await getRemoteVaultInfo();

      if (remoteFile == null) return SyncDecision.noRemote;

      // 为了防止毫秒级的微小差异, 可忽略t(ms)内的偏差
      final diff = localMTime.difference(remoteFile.mTime!).inMilliseconds;
      if (diff > t) return SyncDecision.localNewer;
      if (diff < -t) return SyncDecision.remoteNewer;
      return SyncDecision.bothSynced;
    } catch (e) {
      return SyncDecision.error;
    }
  }

  // 3.核心传输接口(HTTP 协议层)
  // 上传至云端
  Future<void> uploadVault(String localPath) async {
    if (!_ensureClient()) throw Exception("客户端未就绪");
    // 预建目录
    try {
      await _client!.mkdir('/vault_keeper');
    } catch (_) {}
    return _doHttpRequest(method: 'PUT', localPath: localPath);
  }

  // 下载至本地
  Future<void> downloadVault(String localPath) async {
    if (!_ensureClient()) throw Exception("客户端未就绪");
    return _doHttpRequest(method: 'GET', localPath: localPath);
  }

  // 统一处理 HTTP PUT/GET 逻辑
  Future<void> _doHttpRequest({
    required String method,
    required String localPath,
  }) async {
    // 此时 _currentXXX 必不为空，因为 _ensureClient 已经执行过
    final auth =
        'Basic ${base64.encode(utf8.encode('$_currentUser:$_currentPwd'))}';
    final targetUri = Uri.parse('${_currentUrl!}vault_keeper/vault_keeper.db');

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

enum SyncDecision {
  localNewer, // 本地较新 建议上传
  remoteNewer, // 云端较新 建议下载
  bothSynced, // 已同步
  noRemote, // 云端无备份
  error, // 检测出错
}
