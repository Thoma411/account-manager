/*
 * @Author: Thoma4
 * @Date: 2026-04-13 18:19:04
 * @LastEditTime: 2026-07-16 17:25:37
 * @Description: webdav
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webdav_client/webdav_client.dart' as dav;
import 'package:device_info_plus/device_info_plus.dart';

import 'settings_service.dart';
import 'storage_service.dart';

class WebDavService {
  static final WebDavService _instance = WebDavService._internal();
  factory WebDavService() => _instance;
  WebDavService._internal();
  dav.Client? _client;

  // 统一存储当前生效的凭据（无论是临时的还是持久化的）
  String? _currentUrl, _currentUser, _currentPwd;

  // 确保url以斜杠结尾
  String _normalizeUrl(String url) {
    return url.endsWith('/') ? url : '$url/';
  }

  // 1.初始化逻辑 (收口)
  // 手动初始化（用于登录前恢复或设置页测试）
  void initCustomClient(String url, String user, String password) {
    _currentUrl = _normalizeUrl(url);
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
    if (url == null ||
        url.isEmpty ||
        user == null ||
        user.isEmpty ||
        pwd == null ||
        pwd.isEmpty) {
      return false;
    }
    initCustomClient(url, user, pwd);
    return true;
  }

  // 私有校验: 确保在执行任何网络操作前Client已就绪
  bool _ensureClient() {
    if (_client != null) return true;
    return initFromSettings();
  }

  // 重置client状态
  void reset() {
    _currentUrl = null;
    _currentUser = null;
    _currentPwd = null;
    _client = null;
    debugPrint("WebDavService: 状态已重置");
  }

  // 2.业务查询接口(语义化封装)
  // 测试连通性: 仅用于验证凭据是否正确
  Future<bool> ping() async {
    try {
      await getRemoteVaultInfo();
      return true;
    } catch (_) {
      return false;
    }
  }

  // 获取云端备份文件元数据(专供SyncPage对比使用)
  Future<dav.File?> getRemoteVaultInfo() async {
    if (_currentUrl == null && !initFromSettings()) return null;
    try {
      final auth =
          'Basic ${base64.encode(utf8.encode('$_currentUser:$_currentPwd'))}';
      final targetUri = Uri.parse(
        '${_currentUrl!}vault_keeper/vault_keeper.db',
      );

      // 核心修改：使用 PROPFIND 替代 HEAD 以获取 ETag
      final request = http.Request('PROPFIND', targetUri)
        ..headers.addAll({
          'Authorization': auth,
          'Depth': '0',
          'Content-Type': 'application/xml',
        });

      final streamedResponse = await http.Client().send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 207) {
        final body = response.body;
        // 使用正则解析XML中的ETag&修改时间&长度
        final etagMatch = RegExp(
          r'<[a-z0-9:]*getetag>(.*?)</[a-z0-9:]*getetag>',
        ).firstMatch(body);
        final dateMatch = RegExp(
          r'<[a-z0-9:]*getlastmodified>(.*?)</[a-z0-9:]*getlastmodified>',
        ).firstMatch(body);
        final sizeMatch = RegExp(
          r'<[a-z0-9:]*getcontentlength>(.*?)</[a-z0-9:]*getcontentlength>',
        ).firstMatch(body);

        final etag = etagMatch?.group(1)?.replaceAll('"', '') ?? "";
        DateTime? mTime;
        if (dateMatch != null) {
          try {
            mTime = HttpDate.parse(dateMatch.group(1)!);
          } catch (_) {}
        }

        return dav.File(
          name: 'vault_keeper.db',
          path: '/vault_keeper/vault_keeper.db',
          size: int.tryParse(sizeMatch?.group(1) ?? '0') ?? 0,
          mTime: mTime,
          eTag: etag,
        );
      } else if (response.statusCode == 404) {
        return null;
      } else if (response.statusCode == 401) {
        throw Exception("Unauthorized");
      }
      return null;
    } catch (e) {
      debugPrint("WebDavService: 尝试获取元数据失败: $e");
      rethrow;
    }
  }

  // 读取云端目录
  Future<List<dav.File>> readDir(String path) async {
    if (!_ensureClient()) throw Exception("WebDAV客户端未初始化");
    return await _client!.readDir(path);
  }

  // 本地云端版本比较
  Future<SyncDecision> compareVersions() async {
    try {
      final s = SettingsService();

      // 1. 获取本地逻辑状态
      int localRev = int.parse(s.get('local_revision', defaultValue: '0')!);
      int lastSyncedRev = int.parse(
        s.get('last_synced_revision', defaultValue: '0')!,
      );
      String lastSyncedETag = s.get('last_synced_etag', defaultValue: '')!;

      // 2. 获取云端状态
      dav.File? remoteFile;
      try {
        remoteFile = await getRemoteVaultInfo();
      } catch (e) {
        if (e.toString().contains("Unauthorized")) {
          debugPrint("compareVersions: 认证失败");
        }
        return SyncDecision.error;
      }

      if (remoteFile == null) return SyncDecision.noRemote;
      String currentRemoteETag = remoteFile.eTag ?? "";

      debugPrint("Local: Rev($localRev), LastSyncedRev($lastSyncedRev)");
      debugPrint(
        "Remote: CurrentETag($currentRemoteETag), LastSyncedETag($lastSyncedETag)",
      );

      // 3. 逻辑判定
      bool localChanged = localRev > lastSyncedRev;
      bool remoteChanged = currentRemoteETag != lastSyncedETag;
      // 两端均无改动
      if (!localChanged && !remoteChanged) return SyncDecision.bothSynced;
      // 仅本地改动
      if (localChanged && !remoteChanged) return SyncDecision.localNewer;
      // 仅云端改动
      if (!localChanged && remoteChanged) return SyncDecision.remoteNewer;
      // 两端均有改动（冲突）
      return SyncDecision.conflict;
    } catch (e) {
      return SyncDecision.error;
    }
  }

  // 3.核心传输接口
  Future<void> _ensureRemoteDir() async {
    final auth =
        'Basic ${base64.encode(utf8.encode('$_currentUser:$_currentPwd'))}';
    final dirUri = Uri.parse('${_currentUrl!}vault_keeper/');
    await http.Client().send(
      http.Request('MKCOL', dirUri)..headers['Authorization'] = auth,
    );
  }

  // 上传
  Future<String> uploadVault() async {
    if (_currentUrl == null && !initFromSettings()) throw Exception("未配置");
    await _ensureRemoteDir();
    final res = await _doHttpRequest(
      method: 'PUT',
      localPath: await StorageService().getDatabasePath(),
    );
    String etag = (res.headers['etag'] ?? "").replaceAll('"', '');
    // 如果etag为空则需发起查询
    if (etag.isEmpty) {
      final remoteInfo = await getRemoteVaultInfo();
      etag = remoteInfo?.eTag ?? "";
    }
    debugPrint("WebDavService: etag: $etag");
    return etag;
  }

  // 下载
  Future<String> downloadVault() async {
    if (_currentUrl == null && !initFromSettings()) throw Exception("未配置");
    final res = await _doHttpRequest(
      method: 'GET',
      localPath: await StorageService().getDatabasePath(),
    );
    return (res.headers['etag'] ?? "").replaceAll('"', '');
  }

  // 执行静默安全上传
  Future<bool> uploadIfSafe() async {
    try {
      final decision = await compareVersions();
      if (decision == SyncDecision.localNewer ||
          decision == SyncDecision.noRemote) {
        String etag = await uploadVault();
        // 同步成功后更新锚点
        final s = SettingsService();
        String? localRev = s.get('local_revision', defaultValue: '0');
        await s.set('last_synced_revision', localRev!);
        await s.set('last_synced_etag', etag);
        await addSyncLog("静默同步-上传", "成功：本地库已同步");
        return true;
      }
      return false;
    } catch (e) {
      await addSyncLog(
        "静默同步-上传",
        "失败: ${e.toString().replaceAll('Exception: ', '')}",
      );
      return false;
    }
  }

  // 执行静默安全下载
  Future<bool> downloadIfSafe() async {
    try {
      final decision = await compareVersions();
      if (decision == SyncDecision.remoteNewer) {
        await StorageService().closeDatabase();
        String newEtag = await downloadVault();
        await SettingsService().set('last_synced_etag', newEtag);
        // 仅从云端下载新库后才标记解锁后需要对齐版本
        await SettingsService().set('need_revision_alignment', 'true');
        await addSyncLog("静默同步-下载", "成功：云端拉取完毕");
        return true;
      }
      return false;
    } catch (e) {
      await addSyncLog(
        "静默同步-下载",
        "失败: ${e.toString().replaceAll('Exception: ', '')}",
      );
      return false;
    }
  }

  // 添加云同步日志
  Future<void> addSyncLog(String action, String status) async {
    final s = SettingsService();
    List<Map<String, dynamic>> logs = [];
    // 读取现有的历史日志
    final logData = s.get('sync_history_json');
    if (logData != null) {
      try {
        logs = List<Map<String, dynamic>>.from(jsonDecode(logData));
      } catch (_) {}
    }
    // 获取设备特征码
    String deviceName = Platform.localHostname;
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = "${androidInfo.brand.toUpperCase()} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
      }
    } catch (e) {
      debugPrint("读取移动端设备型号失败: $e");
      deviceName = Platform.localHostname; // 异常时安全保底
    }
    // 拼装特征码
    final String deviceSignature =
        "${Platform.operatingSystem.toUpperCase()} ($deviceName)";
    // 注入设备特征码，写入新日志
    logs.insert(0, {
      'time': DateTime.now().toIso8601String(),
      'action': "[$deviceSignature] $action",
      'status': status,
    });
    // 仅保留最近15条并写回持久化配置
    if (logs.length > 15) logs.removeLast();
    await s.set('sync_history_json', jsonEncode(logs));
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
        final File file = File(localPath);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true); // 确保目录创建
        }
        await file.writeAsBytes(res.bodyBytes);
        return res;
      }
      throw Exception("下载失败: ${res.statusCode}");
    }
  }
}

enum SyncDecision {
  bothSynced, // 已同步
  localNewer, // 本地较新 建议上传
  remoteNewer, // 云端较新 建议下载
  conflict, // 双端冲突
  noRemote, // 云端无备份
  error, // 检测出错
}
