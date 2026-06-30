/*
 * @Author: Thoma4
 * @Date: 2026-06-24 00:24:18
 * @LastEditTime: 2026-07-01 00:15:17
 * @Description: 云同步页
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/security_service.dart';
import '../services/webdav_service.dart';
import '../utils/utils.dart';
import '../widgets/account_ui_utils.dart';

// 云同步界面
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => SyncPageState();
}

// 云同步界面
class SyncPageState extends State<SyncPage> {
  final _webdav = WebDavService();
  final _storage = StorageService();
  final _settings = SettingsService();

  bool _isLoading = false;
  DateTime? _localTime, _remoteTime;
  int? _localSize, _remoteSize;

  SyncDecision? _currentDecision; // 当前同步决策结果

  // 模拟/持久化日志列表
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadSyncLogs();
    refreshStatus();
  }

  // 从设置加载历史日志
  void _loadSyncLogs() {
    final logData = _settings.get('sync_history_json');
    if (logData != null) {
      try {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(jsonDecode(logData));
        });
      } catch (_) {}
    }
  }

  // 添加新日志
  void _addLog(String action, String status) {
    setState(() {
      _logs.insert(0, {
        'time': DateTime.now().toIso8601String(),
        'action': action,
        'status': status,
      });
      if (_logs.length > 15) _logs.removeLast(); // 保留最近15条
    });
    _settings.set('sync_history_json', jsonEncode(_logs));
  }

  // 清空日志列表
  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清空日志"),
        content: const Text("同步历史记录清空后将无法找回。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _logs.clear();
              });
              await _settings.set('sync_history_json', '[]'); // 置空列表
              if (!context.mounted) return;
              Navigator.pop(context);
              MessageUtil.show(context, "日志已清空");
            },
            child: Text(
              "确认",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> refreshStatus() async {
    setState(() => _isLoading = true);
    try {
      // 获取本地信息
      final localPath = await _storage.getDatabasePath();
      final localFile = File(localPath);
      if (await localFile.exists()) {
        final stat = await localFile.stat();
        _localTime = stat.modified;
        _localSize = stat.size;
      }
      // 获取远程信息
      final remoteFile = await _webdav.getRemoteVaultInfo();
      if (remoteFile != null) {
        _remoteTime = remoteFile.mTime;
        _remoteSize = remoteFile.size;
      }
      // 同步决策结果
      _currentDecision = await _webdav.compareVersions();
    } catch (e) {
      _currentDecision = SyncDecision.error;
      debugPrint("刷新状态失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 处理测试连接
  Future<void> _handlePing() async {
    setState(() => _isLoading = true);
    try {
      bool ok = await _webdav.ping();
      if (ok) {
        // 获取云端指纹
        final remoteInfo = await _webdav.getRemoteVaultInfo();
        if (remoteInfo != null) {
          String remoteETag = remoteInfo.eTag?.replaceAll('"', '') ?? "";
          // 如果本地指纹是空的，说明是新设备或刚迁移，自动补全它
          if (_settings.get('last_synced_etag', defaultValue: '')!.isEmpty) {
            await _settings.set('last_synced_etag', remoteETag);
          }
          final String tagDisplay = remoteETag.length > 5
              ? remoteETag.substring(0, 5)
              : remoteETag;
          _addLog("连接测试", "成功 (云端版本: $tagDisplay...)");
        } else {
          _addLog("连接测试", "成功 (云端暂无备份)");
        }
      } else {
        _addLog("连接测试", "失败：请检查地址或应用密码");
      }
    } catch (e) {
      _addLog("连接测试", "异常: $e");
    } finally {
      setState(() => _isLoading = false);
      refreshStatus(); // 刷新 UI 状态
    }
  }

  // 更新锚点的公共方法
  Future<void> _updateSyncMarkers(String etag) async {
    String? currentLocalRev = _settings.get(
      'local_revision',
      defaultValue: '0',
    ); // 存入SharedPrefs
    await _settings.set('last_synced_revision', currentLocalRev!);
    await _settings.set('last_synced_etag', etag);
  }

  // 冲突处理对话框
  void _showConflictDialog({
    required VoidCallback onConfirmLocal, // 本地覆盖云端
    required VoidCallback onConfirmRemote, // 云端覆盖本地
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("同步版本冲突"),
        content: const Text(
          "检测到本地与云端的数据库不一致。请选择保留哪个版本？\n\n注意：保留云端将强制重启应用以重新载入数据，这会永久覆盖另一端的数据。",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirmLocal();
            },
            child: Text(
              "保留本地 (上传)",
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirmRemote();
            },
            child: const Text("保留云端 (下载)"),
          ),
        ],
      ),
    );
  }

  // 用于智能同步下载确认的对话框
  void _showActionConfirmDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  // 处理智能同步逻辑
  Future<void> _handleSmartSync() async {
    if (_isLoading) return;
    final decision = await _webdav.compareVersions();
    switch (decision) {
      case SyncDecision.bothSynced:
        _addLog("智能同步", "无需操作：已是最新");
        break;
      case SyncDecision.localNewer:
      case SyncDecision.noRemote:
        await _executeSync(true); // 执行上传
        break;
      case SyncDecision.remoteNewer:
        _showActionConfirmDialog(
          title: "拉取云端更新",
          content: "将云端更新同步至本地？完成后需要重新登录。",
          onConfirm: () => _executeSync(false), // 执行下载
        );
        break;
      case SyncDecision.conflict:
        _showConflictDialog(
          onConfirmLocal: () => _executeSync(true),
          onConfirmRemote: () => _executeSync(false),
        );
        break;
      default:
        _addLog("智能同步", "异常：无法获取状态");
    }
  }

  // 处理具体的物理同步动作
  Future<void> _executeSync(bool isUpload) async {
    final actionName = isUpload ? "上传" : "下载";

    try {
      setState(() => _isLoading = true);
      if (isUpload) {
        String newEtag = await _webdav.uploadVault();
        await _updateSyncMarkers(newEtag);
        _addLog(actionName, "成功：云端已更新");
      } else {
        await _storage.closeDatabase();
        String newEtag = await _webdav.downloadVault();
        await _settings.set('last_synced_etag', newEtag);
        _addLog(actionName, "成功：本地已拉取");

        if (!mounted) return;
        // 下载后的强制重定向
        SecurityService().clearKeys();
        MessageUtil.show(context, "云端数据已同步，请重新解锁载入");
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const UnlockPage()),
          (route) => false,
        );
        return; // 终止后续代码
      }
    } catch (e) {
      _addLog(actionName, "失败: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        refreshStatus(); // 无论成败刷新状态
      }
    }
  }

  // 构建按钮
  Widget _buildActionButton({
    required String label,
    required IconData icon,
    VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: isPrimary
          ? FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                elevation: 1,
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onPrimaryContainer, // 与主按钮文字色对齐
                side: BorderSide(color: colorScheme.outlineVariant), // 同时淡化边框
              ),
              icon: Icon(icon, size: 16),
              label: Text(label, style: const TextStyle(fontSize: 13)),
            ),
    );
  }

  // 获取智能同步文字
  String _getSmartSyncLabel() {
    if (_isLoading) return "检测中...";
    switch (_currentDecision) {
      case SyncDecision.bothSynced:
        return "已是最新版本";
      case SyncDecision.localNewer:
        return "上传本地更新";
      case SyncDecision.remoteNewer:
        return "拉取云端更新";
      case SyncDecision.conflict:
        return "发现版本冲突";
      case SyncDecision.noRemote:
        return "上传首个备份";
      case SyncDecision.error:
        return "检测失败，点击刷新";
      default:
        return "一键同步";
    }
  }

  // 构建日志列表
  Widget _buildLogList() {
    if (_logs.isEmpty) {
      return Center(
        child: Text(
          "暂无历史记录",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return ListTile(
          dense: true,
          leading: Icon(
            _getLogIcon(log['action']),
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text("${log['action']} - ${log['status']}"),
          subtitle: Text(DateUtil.format(log['time'])),
        );
      },
    );
  }

  // 动态匹配图标
  IconData _getLogIcon(String action) {
    if (action.contains("上传")) return Icons.cloud_upload;
    if (action.contains("下载")) return Icons.cloud_download;
    return Icons.info_outline;
  }

  // Card构建方法
  Widget _buildStatusCard(
    String title,
    IconData icon,
    DateTime? time,
    int? size,
    Color color,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    String timeStr = time != null
        ? DateUtil.format(time.toIso8601String())
        : "无记录";
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (size != null)
                Text(
                  "${(size / 1024).toStringAsFixed(1)} KB",
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 箭头构建
  Widget _buildSyncIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.arrow_forward,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 动态感知屏幕宽度
    final bool isMobile = AccountUiUtils.isMobile(context);
    // 顶部对比卡片
    Widget statusSection = Row(
      children: [
        _buildStatusCard(
          "当前设备",
          Icons.computer,
          _localTime,
          _localSize,
          colorScheme.primary,
        ),
        _buildSyncIndicator(),
        _buildStatusCard(
          "云端备份",
          Icons.cloud_done,
          _remoteTime,
          _remoteSize,
          colorScheme.primary,
        ),
      ],
    );
    // 操作按钮组
    Widget actionSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionButton(
          label: _getSmartSyncLabel(),
          icon: Icons.sync,
          isPrimary: true,
          onPressed: _handleSmartSync,
        ),
        const SizedBox(height: 12),
        Text(
          "系统将根据修改时间自动决定上传或下载",
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        SizedBox(height: isMobile ? 12 : 32),
        _buildActionButton(
          label: "测试云端连接",
          icon: Icons.lan_outlined,
          onPressed: _handlePing,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                label: "强制上传",
                icon: Icons.upload,
                onPressed: () => _executeSync(true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildActionButton(
                label: "强制下载",
                icon: Icons.download,
                onPressed: () => _executeSync(false),
              ),
            ),
          ],
        ),
      ],
    );
    // 同步日志框
    Widget logSection = Container(
      height: isMobile ? 300 : double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "同步日志",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_logs.isNotEmpty) // 仅在有日志时显示清空按钮
                  IconButton(
                    onPressed: _clearLogs,
                    icon: Icon(
                      Icons.delete_sweep_outlined,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: "清空所有记录",
                    splashRadius: 20,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );

    Widget content = Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "云同步仪表盘",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          statusSection,
          const SizedBox(height: 32),
          isMobile
              ? Column(
                  // 手机端：上操作, 下日志
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    actionSection,
                    const SizedBox(height: 24),
                    logSection,
                  ],
                )
              : Expanded(
                  child: Row(
                    // 电脑端: 左操作, 右日志
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧操作区 (Flex 2)
                      Expanded(flex: 2, child: actionSection),
                      const SizedBox(width: 40), // 左右间距
                      // 右侧日志区 (Flex 3)
                      Expanded(flex: 3, child: logSection),
                    ],
                  ),
                ),
        ],
      ),
    );
    return isMobile ? SingleChildScrollView(child: content) : content;
  }
}
