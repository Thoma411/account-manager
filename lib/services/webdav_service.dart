/*
 * @Author: Thoma4
 * @Date: 2026-04-13 18:19:04
 * @LastEditTime: 2026-06-15 21:29:07
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
  Future<SyncDecision> compareVersions() async {
    try {
      final s = SettingsService();
      // 获取本地逻辑状态
      int localRev = int.parse(
        s.get('local_revision', defaultValue: '0')!,
      ); // 本地逻辑版本号
      int lastSyncedRev = int.parse(
        s.get('last_synced_revision', defaultValue: '0')!,
      ); // 上次同步版本号
      String lastSyncedETag = s.get(
        'last_synced_etag',
        defaultValue: '',
      )!; // 云端锚点

      // 获取云端最新状态
      final remoteFile = await getRemoteVaultInfo();
      if (remoteFile == null) return SyncDecision.noRemote;
      String currentRemoteETag = remoteFile.eTag?.replaceAll('"', '') ?? "";

      // 逻辑判定
      bool localChanged = localRev > lastSyncedRev;
      bool remoteChanged =
          (currentRemoteETag != lastSyncedETag && lastSyncedETag.isNotEmpty);

      debugPrint("Local: Rev($localRev), LastSyncedRev($lastSyncedRev)");
      debugPrint(
        "Remote: CurrentETag($currentRemoteETag), LastSyncedETag($lastSyncedETag)",
      );
      // 两端均无改动
      if (!localChanged && !remoteChanged) return SyncDecision.bothSynced;
      // 仅本地改动
      if (localChanged && !remoteChanged) return SyncDecision.localNewer;
      // 仅云端改动（其他设备同步）
      if (!localChanged && remoteChanged) return SyncDecision.remoteNewer;
      // 两端均有改动（冲突）
      return SyncDecision.remoteNewer; // 此处建议返回 remoteNewer 触发 UI 冲突对话框
    } catch (e) {
      return SyncDecision.error;
    }
  }

  // 3.核心传输接口(HTTP 协议层)
  // 上传至云端
  Future<String> uploadVault(String localPath) async {
    if (!_ensureClient()) throw Exception("客户端未就绪");
    // 预建目录
    try {
      await _client!.mkdir('/vault_keeper');
    } catch (_) {}
    final res = await _doHttpRequest(method: 'PUT', localPath: localPath);
    return res.headers['etag']?.replaceAll('"', '') ?? "";
  }

  // 下载至本地
  Future<String> downloadVault(String localPath) async {
    if (!_ensureClient()) throw Exception("客户端未就绪");
    final res = await _doHttpRequest(method: 'GET', localPath: localPath);
    return res.headers['etag']?.replaceAll('"', '') ?? "";
  }

  // 执行静默安全上传
  Future<bool> uploadIfSafe() async {
    try {
      final decision = await compareVersions();
      // 仅在本地较新或云端没备份时才自动上传
      if (decision == SyncDecision.localNewer ||
          decision == SyncDecision.noRemote) {
        final path = await StorageService().getDatabasePath();
        String etag = await uploadVault(path);
        // 同步成功后更新锚点
        final s = SettingsService();
        String? localRev = s.get('local_revision', defaultValue: '0');
        await s.set('last_synced_revision', localRev!);
        await s.set('last_synced_etag', etag);
        debugPrint("AutoSync: 退出前备份成功");
        return true;
      } else {
        debugPrint("AutoSync: $decision 放弃自动上传");
        return false;
      }
    } catch (e) {
      debugPrint("AutoSync: 退出时同步异常: $e");
      return false;
    }
  }

  // 执行静默安全下载
  Future<bool> downloadIfSafe() async {
    try {
      final decision = await compareVersions();
      if (decision == SyncDecision.remoteNewer) {
        final path = await StorageService().getDatabasePath();
        await StorageService().closeDatabase(); // *先关库
        String newEtag = await downloadVault(path);
        // 更新本地配置层的锚点
        final s = SettingsService();
        await s.set('last_synced_etag', newEtag);
        // last_synced_revision会在下次解锁时的AuthService补丁中对齐
        debugPrint("AutoSync: 已下载云端更新");
        return true;
      } else {
        debugPrint("AutoSync: $decision 终止自动下载");
        return false;
      }
    } catch (e) {
      debugPrint("AutoSync: 启动时同步异常: $e");
      return false;
    }
  }

  // 统一处理HTTP-PUT/GET逻辑
  Future<http.Response> _doHttpRequest({
    required String method,
    required String localPath,
  }) async {
    // _ensureClient已经执行过，此时_currentXXX必不为空
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
      return res;
    } else {
      final res = await http.get(targetUri, headers: {'Authorization': auth});
      if (res.statusCode == 200) {
        await File(localPath).writeAsBytes(res.bodyBytes);
      } else {
        throw Exception("下载失败: ${res.statusCode}");
      }
      return res;
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
