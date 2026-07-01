/*
 * @Author: Thoma4
 * @Date: 2026-06-15 16:34:15
 * @LastEditTime: 2026-07-01 14:30:49
 * @Description: 抓取网页icon
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'storage_service.dart';

class IconService {
  static final IconService _instance = IconService._internal();
  factory IconService() => _instance;
  IconService._internal();

  final Set<String> _pendingFetches = {}; // 正在抓取的账户ID

  // 获取本地图标存储目录
  Future<Directory> get _iconDir async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'vault_icons'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // 获取特定账户图标的本地路径
  Future<String> getIconPath(String id) async {
    final dir = await _iconDir;
    return p.join(dir.path, '$id.png');
  }

  // 核心抓取逻辑：瀑布式请求
  Future<void> fetchAndCacheIcon(String id, String rawUrl) async {
    if (rawUrl.isEmpty) return;
    if (_pendingFetches.contains(id)) return; // 拦截重复请求
    if (!await StorageService().isAccountExists(id)) return;
    final domain = _extractDomain(rawUrl);
    if (domain.isEmpty) return;
    final filePath = await getIconPath(id);
    _pendingFetches.add(id); // 将当前ID加入正在请求队列

    try {
      // 抓取 API 列表 (按优先级排序)
      final List<String> apiPool = [
        "https://api.iowen.cn/libs/favicon/$domain.png", // Iowen CDN
        "https://favicon.im/$domain", // Favicon.im(备份)
        "https://www.google.com/s2/favicons?sz=64&domain=$domain", // Google(备用)
      ];
      for (String apiUrl in apiPool) {
        try {
          if (!await StorageService().isAccountExists(id)) return;
          final response = await http
              .get(
                Uri.parse(apiUrl),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64)   AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
              )
              .timeout(const Duration(seconds: 5));
          if (!await StorageService().isAccountExists(id)) return;
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            // 简单过滤太小的无效图
            await File(filePath).writeAsBytes(response.bodyBytes);
            debugPrint("IconService: 成功从 $apiUrl 抓取图标 ($id)");
            return; // 任何一个成功即退出循环
          }
        } catch (e) {
          debugPrint("IconService: 从 $apiUrl 抓取失败: $e");
        }
      }
    } finally {
      _pendingFetches.remove(id); // 移除锁
    }
  }

  // 删除本地缓存图标
  Future<void> deleteIcon(String id) async {
    try {
      final file = File(await getIconPath(id));
      if (await file.exists()) {
        await file.delete();
        debugPrint("IconService: 已清理账户 $id 的图标缓存");
      }
    } catch (e) {
      debugPrint("IconService: 清理图标失败: $e");
    }
  }

  // 删除全部图标(清理缓存图标)
  Future<void> clearAllIcons() async {
    try {
      final dir = await _iconDir;
      if (await dir.exists()) {
        // 获取目录下所有的文件实体
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (var entity in entities) {
          if (entity is File) {
            final String id = p.basenameWithoutExtension(entity.path);
            await deleteIcon(id);
          }
        }
        debugPrint("IconService: 已清理缓存图标");
      }
    } catch (e) {
      debugPrint("IconService: 批量清理失败: $e");
      rethrow;
    }
  }

  // 从URL提取域名
  String _extractDomain(String url) {
    try {
      url = url.trim().toLowerCase();
      if (!url.startsWith("http")) url = "http://$url";
      final uri = Uri.parse(url);
      String host = uri.host;
      if (host.startsWith("www.")) host = host.substring(4);
      return host;
    } catch (_) {
      return "";
    }
  }
}
