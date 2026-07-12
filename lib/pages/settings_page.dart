/*
 * @Author: Thoma4
 * @Date: 2026-06-24 00:17:53
 * @LastEditTime: 2026-07-12 21:48:59
 * @Description: 设置页
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/security_service.dart';
import '../services/icon_service.dart';
import '../services/webdav_service.dart';
import '../services/csv_service.dart';
import '../widgets/account_ui_utils.dart';
import '../utils/utils.dart';
import 'login_page.dart';
import '../main.dart';

// 设置界面
class SettingsPage extends StatefulWidget {
  final VoidCallback? onDataChanged;
  const SettingsPage({super.key, this.onDataChanged});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

// 设置界面
class SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService();
  bool _isDarkMode = false; // 深色模式
  bool _hasDb = false; // 控制WebDAV按钮
  bool _autoFetchIcons = false; // 自动抓取图标
  bool _autoSyncEnabled = false; // 静默同步

  static const String currentVersion = "v0.9.0-beta.3";

  @override
  void initState() {
    super.initState();
    // 从已经loadSettings加载好的缓存中获取值
    _isDarkMode = _settings.get('dark_mode') == 'true';
    _autoFetchIcons = _settings.get('auto_fetch_icons') == 'true';
    _autoSyncEnabled = _settings.get('auto_sync_enabled') == 'true';
    checkDbStatus();
  }

  // 切换深色模式
  void _toggleDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    await _settings.set('dark_mode', value.toString()); // 异步存入数据库
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
  }

  // 切换自动抓取图标
  void _toggleAutoFetch(bool value) async {
    setState(() => _autoFetchIcons = value);
    await _settings.set('auto_fetch_icons', value.toString());
  }

  // 清除缓存图标
  void _handleClearIcons() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清除图标缓存"),
        content: const Text("这将删除本地存储的全部网站的图标。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await IconService().clearAllIcons();
                if (!context.mounted) return;
                Navigator.pop(context);
                MessageUtil.show(context, "缓存已清空");
              } catch (e) {
                MessageUtil.show(context, "清除失败: $e");
              }
            },
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  // 检查数据库状态 决定是否允许配置WebDAV
  void checkDbStatus() async {
    bool exists = await StorageService().isDatabaseExists();
    if (!mounted) return;
    setState(() => _hasDb = exists);
  }

  // 在用户确认连接及冲突处理后正式将WebDAV凭据持久化到加密数据库中
  Future<void> _finalizeWebDavSave(String url, String user, String pwd) async {
    await _settings.set('webdav_url', url);
    await _settings.set('webdav_user', user);
    await _settings.set('webdav_pwd', pwd, isEncrypted: true);
    checkDbStatus(); // 刷新本页的 hasDb 状态，解除按钮禁用
  }

  // 弹出WebDAV配置对话框
  void _showWebDavDialog() {
    final urlController = TextEditingController(
      text: _settings.get('webdav_url'),
    );
    final userController = TextEditingController(
      text: _settings.get('webdav_user'),
    );
    final pwdController = TextEditingController(
      text: _settings.get('webdav_pwd'),
    );
    final webdav = WebDavService();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("配置WebDAV云同步"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "建议使用坚果云等支持WebDAV的网盘。同步数据将以加密形式上传。",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: "服务器地址 (如: https://dav.jianguoyun.com/dav/)",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: "账号 (邮箱)"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwdController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "应用密码"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              // 1. 临时初始化客户端进行测试
              webdav.initCustomClient(
                urlController.text,
                userController.text,
                pwdController.text,
              );
              // 2. 显示进度提示
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("正在测试连接...")));
              bool isOk = await webdav.ping();
              if (!isOk) {
                if (!context.mounted) return;
                MessageUtil.show(context, "连接失败，请检查配置");
                return;
              }
              // 验证通过直接保存凭据，冲突处理在云同步界面执行
              await _finalizeWebDavSave(
                urlController.text,
                userController.text,
                pwdController.text,
              );
              WebDavService().reset();
              if (!context.mounted) return;
              Navigator.pop(context); // 关闭输入框
              MessageUtil.show(context, "WebDAV 配置已保存，请前往云同步界面管理数据");
            },
            child: const Text("保存配置"),
          ),
        ],
      ),
    );
  }

  // 导出警告对话框
  void _handleExport() {
    final outerContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("导出安全警告"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
          children: [
            Text(
              "导出操作会将您的所有账户密码以【明文】形式保存为 CSV 文件。",
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text("任何人打开此文件均可见您的敏感信息，请在安全的环境下操作，并在使用后妥善保管或销毁该文件。"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // 先关警告框
              try {
                final count = await CsvService().exportToCsv();
                if (count != null && context.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        "成功导出账户 $count 条",
                        textAlign: TextAlign.center,
                      ),
                      duration: const Duration(seconds: 3),
                      width: 200,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        "导出失败：${e.toString().replaceAll('Exception: ', '')}",
                        textAlign: TextAlign.center,
                      ),
                      duration: const Duration(seconds: 3),
                      width: 320,
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Theme.of(outerContext).colorScheme.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text("确认导出"),
          ),
        ],
      ),
    );
  }

  // 弹出展示RK对话框
  void _showViewRKDialog() async {
    final sec = SecurityService();
    final storage = StorageService();
    // 获取解密钥匙(内存中的DK)
    final dk = sec.currentDataKey;
    if (dk == null) {
      MessageUtil.show(context, "错误：加密环境未就绪");
      return;
    }
    // 从数据库读取加密的恢复密钥(erk)
    String? erk = await storage.getMetadata('erk');
    if (erk == null) {
      if (!mounted) return;
      MessageUtil.show(context, "未找到恢复密钥记录");
      return;
    }
    try {
      final String rk = sec.decrypt(erk, dk); // 执行解密
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("您的恢复密钥 (RK)"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "这是您找回数据的唯一凭证，请勿泄露给他人。",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              SelectableText(
                rk,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Microsoft YaHei'],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("关闭"),
            ),
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rk));
                MessageUtil.show(context, "密钥已复制到剪切板");
              },
              child: const Text("复制"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) MessageUtil.show(context, "解密失败：$e");
    }
  }

  // 弹出手动重置RK的确认对话框
  void _handleManualRotateRK() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重置恢复密钥"),
        content: const Text("确认重置将生成新恢复密钥，原恢复密钥会立即失效。仅在你认为恢复密钥泄露时重置。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // 执行轮转逻辑
                final String newRk = await SecurityService()
                    .rotateRecoveryKey();
                if (!context.mounted) return;
                Navigator.pop(context); // 关闭确认弹窗
                _showNewRKDisplay(newRk); // 弹出展示新密钥的对话框
              } catch (e) {
                if (mounted) MessageUtil.show(context, "重置失败：$e");
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text("确认重置"),
          ),
        ],
      ),
    );
  }

  // 重置RK后新RK的展示框
  void _showNewRKDisplay(String rk) {
    showDialog(
      context: context,
      barrierDismissible: false, // 强制用户点击确认
      builder: (context) => AlertDialog(
        title: const Text("新恢复密钥已生成"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "原恢复密钥已丢弃，请妥善保存新恢复密钥：",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SelectableText(
              rk,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: ['Microsoft YaHei'],
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: rk));
              if (!context.mounted) return;
              Navigator.pop(context);
              MessageUtil.show(context, "恢复密钥已复制至剪切板，请妥善保存");
            },
            child: const Text("复制恢复密钥"),
          ),
        ],
      ),
    );
  }

  // 弹出修改主密码MP对话框
  void _showChangePasswordDialog() {
    final oldPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("修改主密码"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "修改主密码后将强制退出，请使用新主密码重新登录。",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: oldPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "当前主密码"),
              ),
              const Divider(height: 32),
              TextField(
                controller: newPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "新主密码 (至少6位)"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "确认新主密码"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              String newPw = newPwController.text;
              if (newPw != confirmPwController.text || newPw.length < 6) {
                MessageUtil.show(context, "密码不一致或长度不足6位");
                return;
              }
              final auth = AuthService();
              final sec = SecurityService();
              final storage = StorageService();
              // 验证旧主密码
              bool isOldValid = await auth.verifyPassword(oldPwController.text);
              if (!isOldValid) {
                if (!context.mounted) return;
                MessageUtil.show(context, "当前主密码错误，验证失败");
                return;
              }
              final dk = sec.currentDataKey;
              if (dk == null) {
                if (!context.mounted) return;
                MessageUtil.show(context, "错误：加密环境未就绪");
                return;
              }
              try {
                // 1. 生成新盐值并派生新MK
                final newSalt = sec.generateRandomBytes(32);
                final newMk = sec.deriveMasterKey(newPw, newSalt);
                // 2. 用新MK重新包装现有的DK(dk.bytes是原始32字节)
                final dkBase64 = base64.encode(dk.bytes);
                final newEdkM = sec.encrypt(dkBase64, newMk);
                // 3. 持久化更新
                await storage.saveMetadata(
                  'master_salt',
                  base64.encode(newSalt),
                );
                await storage.saveMetadata('edk_m', newEdkM);
                if (!context.mounted) return;
                Navigator.pop(context); // 关闭对话框
                MessageUtil.show(context, "主密码修改成功，请重新登录");
                sec.clearKeys(); // 清理内存密钥
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const UnlockPage()),
                  (route) => false,
                ); // 强制退回登入界面
              } catch (e) {
                if (!context.mounted) return;
                MessageUtil.show(context, "修改失败：$e");
              }
            },
            child: const Text("确认修改并重新登录"),
          ),
        ],
      ),
    );
  }

  // 异步检查更新
  Future<void> _checkForUpdates() async {
    final bool isMobile = AccountUiUtils.isMobile(context);
    // 1. 弹出轻量提示正在检查
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("正在检查更新...", textAlign: TextAlign.center),
        duration: Duration(seconds: 1),
        width: 150,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // 电脑端交由autoUpdater更新
    if (!isMobile) {
      await autoUpdater.checkForUpdates();
      return;
    }
    try {
      final url = Uri.parse(
        "https://api.github.com/repos/Thoma411/account-manager/releases",
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> releases = jsonDecode(response.body);
        if (releases.isEmpty) {
          _showUpdateResultDialog("已是最新版本", "云端暂无任何版本记录。");
          return;
        }
        // 获取云端最新的发布版
        final latestRelease = releases.first;
        final String remoteVersion = latestRelease['tag_name'] ?? "";
        final String downloadUrl = latestRelease['html_url'] ?? "";
        final String releaseNotes = latestRelease['body'] ?? "暂无更新说明。";

        if (remoteVersion != currentVersion && remoteVersion.isNotEmpty) {
          _showNewVersionDialog(remoteVersion, releaseNotes, downloadUrl);
        } else {
          _showUpdateResultDialog("已是最新版本", "当前版本 $currentVersion 已是最新。");
        }
      } else {
        throw Exception("HTTP 状态码 ${response.statusCode}");
      }
    } catch (e) {
      _showUpdateResultDialog(
        "检查失败",
        "无法连接到 GitHub 检查更新: ${e.toString().replaceAll('Exception: ', '')}",
      );
    }
  }

  // 弹出普通状态更新提示框
  void _showUpdateResultDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  // 弹出新版本升级引导框
  void _showNewVersionDialog(String version, String notes, String downloadUrl) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.system_update_alt_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text("发现新版本 $version"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "更新日志：",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(notes, style: const TextStyle(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("暂不更新"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await launchUrl(
                Uri.parse(downloadUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text("下载"),
          ),
        ],
      ),
    );
  }

  // 登出保险箱
  void _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("退出登录"),
        content: const Text("确认退出保险箱吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () async {
              if (_settings.get('auto_sync_enabled') == 'true') {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("正在同步...")));
                await WebDavService().uploadIfSafe();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                }
              }
              WebDavService().reset();
              SecurityService().clearKeys(); // 清空内存中的DK
              await StorageService().closeDatabase(); // 关闭db连接并重置句柄
              if (!context.mounted) return;
              Navigator.pop(context);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const UnlockPage()),
                (route) => false, // 不允许返回
              ); // 踢回解锁页并销毁当前所有UI栈
              MessageUtil.show(context, "保险箱已锁定");
            },
            child: Text(
              "确认退出",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = _hasDb && SecurityService().currentDataKey != null;
    final colorScheme = Theme.of(context).colorScheme;
    // 桌面模式相关判定
    final bool isDesktopDevice =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final bool isTabletDevice =
        (Platform.isAndroid || Platform.isIOS) &&
        MediaQuery.of(context).size.shortestSide >= 600;
    final bool forceDesktopSetting =
        _settings.get('force_desktop_mode') == 'true';
    final bool showAsEnabled = isDesktopDevice || forceDesktopSetting;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          "通用",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          title: const Text("深色模式"),
          // subtitle: const Text("测试配置持久化架构"),
          value: _isDarkMode,
          onChanged: _toggleDarkMode,
          secondary: const Icon(Icons.brightness_6),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text("桌面模式"),
          subtitle: const Text("以电脑端宽屏布局展示 UI（仅平板有效）"),
          secondary: const Icon(Icons.computer_outlined),
          value: showAsEnabled,
          onChanged: isTabletDevice
              ? (val) async {
                  await _settings.set('force_desktop_mode', val.toString());
                  widget.onDataChanged?.call(); // 通知大框架重构
                }
              : null,
        ),
        const Divider(),
        SwitchListTile(
          title: const Text("自动抓取图标"),
          subtitle: const Text("根据网址自动获取平台 Logo（需联网）"),
          value: _autoFetchIcons,
          onChanged: _toggleAutoFetch,
          secondary: const Icon(Icons.image_search),
        ),
        const Divider(),
        ListTile(
          title: const Text("清除图标缓存"),
          subtitle: const Text("删除已下载的所有本地图标文件"),
          leading: const Icon(Icons.delete_sweep_outlined),
          onTap: _handleClearIcons,
        ),
        const Divider(),

        const Text(
          "数据管理",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListTile(
          title: const Text("云端 WebDAV 配置"),
          subtitle: Text(_hasDb ? "已解锁，可配置云备份凭据" : "请先初始化数据库"),
          leading: const Icon(Icons.cloud_queue),
          enabled: _hasDb,
          onTap: _hasDb ? _showWebDavDialog : null,
        ),
        const Divider(),
        SwitchListTile(
          title: const Text("静默同步"),
          subtitle: const Text("开启后，应用将会在登录和退出时自动执行同步"),
          secondary: const Icon(Icons.sync_rounded),
          value: _autoSyncEnabled,
          onChanged: _hasDb
              ? (val) async {
                  setState(() => _autoSyncEnabled = val);
                  await _settings.set('auto_sync_enabled', val.toString());
                }
              : null,
        ),
        const Divider(),
        ListTile(
          title: const Text("从 CSV 导入账户"),
          subtitle: const Text("支持 13 字段标准格式的批量数据导入"),
          leading: const Icon(Icons.upload_file),
          enabled: _hasDb, // 必须建库后才能导入
          onTap: () async {
            final (success, skipped) = await CsvService().pickAndImportCsv();
            if (!context.mounted) return;
            if (success > 0 || skipped > 0) {
              widget.onDataChanged?.call();
              MessageUtil.show(context, "成功导入账户 $success 条，跳过 $skipped 条");
            }
          },
        ),
        const Divider(),
        ListTile(
          title: const Text("导出为 CSV"),
          subtitle: const Text("将所有账户信息以明文形式导出"),
          leading: const Icon(Icons.file_download),
          enabled: _hasDb,
          onTap: _handleExport,
        ),
        const Divider(),

        const Text(
          "安全",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListTile(
          title: const Text("查看恢复密钥"),
          subtitle: const Text("主密码遗失时，凭此密钥可重置密码并找回数据"),
          leading: const Icon(Icons.key_outlined),
          enabled: _hasDb, // 仅在有库时可用
          onTap: _showViewRKDialog,
        ),
        const Divider(),
        ListTile(
          title: const Text("重置恢复密钥"),
          subtitle: const Text("丢弃旧密钥并生成全新的恢复凭据"),
          leading: const Icon(Icons.refresh_outlined),
          enabled: _hasDb, // 仅在有库时可用
          onTap: _handleManualRotateRK,
        ),
        const Divider(),
        ListTile(
          title: const Text("修改主密码"),
          subtitle: const Text("更换登入应用时使用的密码"),
          leading: const Icon(Icons.password_outlined),
          enabled: _hasDb,
          onTap: _showChangePasswordDialog,
        ),
        const Divider(),

        const Text(
          "其他",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListTile(
          title: const Text("检查更新"),
          leading: const Icon(Icons.update_rounded),
          onTap: _checkForUpdates,
        ),
        const Divider(),
        const ListTile(
          title: Text("关于项目"),
          subtitle: Text("accountManager $currentVersion"),
          leading: Icon(Icons.info_outline),
        ),

        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 350,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isLoggedIn ? _handleLogout : null,
              icon: Icon(
                Icons.logout_rounded,
                color: isLoggedIn
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                size: 20,
              ),
              label: Text(
                "退出登录并锁定保险箱",
                style: TextStyle(
                  color: isLoggedIn
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: isLoggedIn
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                  width: 1.5,
                ),
                foregroundColor: colorScheme.error,
              ),
            ),
          ),
          // const SizedBox(height: 40),
        ),
      ],
    );
  }
}
