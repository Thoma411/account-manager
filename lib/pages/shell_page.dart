/*
 * @Author: Thoma4
 * @Date: 2026-03-21 18:50:58
 * @LastEditTime: 2026-06-25 23:42:56
 * @Description: 主框架
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/storage_service.dart';
import '../services/security_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import '../utils/utils.dart';
import 'login_page.dart';
import 'account_list_page.dart';
import 'sync_page.dart';
import 'settings_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WindowListener {
  int _selectedIndex = 0;

  final GlobalKey<AccountListPageState> _accountListPageKey =
      GlobalKey<AccountListPageState>();
  final GlobalKey<SyncPageState> _syncPageKey = GlobalKey<SyncPageState>();
  final GlobalKey<SettingsPageState> _settingsPageKey =
      GlobalKey<SettingsPageState>();
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _handleStartupSync();
    if (Platform.isWindows) {
      windowManager.addListener(this); // 注册窗口监听
      windowManager.setPreventClose(true); // 接管关闭按钮
    }
    // 页面列表
    _pages = [
      AccountListPage(key: _accountListPageKey), // index0
      SyncPage(key: _syncPageKey), // index1
      SettingsPage(
        key: _settingsPageKey,
        onDataChanged: () =>
            _accountListPageKey.currentState?.refreshAccountList(),
      ), // index2
    ];
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this); // 销毁监听
    super.dispose();
  }

  // 处理启动拉取
  Future<void> _handleStartupSync() async {
    if (SettingsService().get('auto_sync_enabled') == 'true') {
      bool downloaded = await WebDavService().downloadIfSafe();
      if (downloaded && mounted) {
        _logoutDirectly("已同步云端更新，请重新登录");
      }
    }
  }

  // 重写关闭应用窗口
  @override
  void onWindowClose() async {
    await windowManager.hide(); // 先隐藏窗口
    // 在后台静默执行同步和清理
    final dk = SecurityService().currentDataKey;
    if (dk != null) {
      final s = SettingsService();
      if (s.get('auto_sync_enabled') == 'true') {
        await WebDavService().uploadIfSafe();
      }
    }
    await StorageService().closeDatabase();
    await windowManager.destroy(); // 销毁进程
  }

  @override
  Widget build(BuildContext context) {
    // 动态感知屏幕宽度
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    return Scaffold(
      // 手机模式: 启用标准底栏; 电脑模式: 设为null
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.list), label: '账户列表'),
                NavigationDestination(icon: Icon(Icons.sync), label: '云同步'),
                NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
              ],
            )
          : null,
      body: SafeArea(
        child: Stack(
          children: [
            isMobile
                ? IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ) // 手机模式直接满屏
                : Row(
                    // 左右布局(导航栏+内容区)
                    children: [
                      NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _onDestinationSelected,
                        labelType: NavigationRailLabelType.all,
                        leading: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Icon(
                            Icons.shield,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.list),
                            label: Text('账户列表'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.sync),
                            label: Text('云同步'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                      const VerticalDivider(thickness: 1, width: 1),
                      Expanded(
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: _pages,
                        ),
                      ),
                    ],
                  ),
            if (!isMobile)
              // 仅电脑模式下渲染显示按钮
              Positioned(
                left: 15, // 距离左边距离
                bottom: 25, // 距离底部距离
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 仅在主页显示刷新，或者全局显示用于强制重载所有数据
                    FloatingActionButton.small(
                      heroTag: "refresh_list_global",
                      elevation: 1, // 默认阴影
                      focusElevation: 0, // 聚焦阴影
                      hoverElevation: 0, // 鼠标悬停阴影
                      highlightElevation: 0, // 点击阴影
                      onPressed: () {
                        // 分别刷新对应的状态
                        if (_selectedIndex == 0) {
                          _accountListPageKey.currentState
                              ?.refreshAccountList();
                          MessageUtil.show(context, "刷新成功");
                        } else if (_selectedIndex == 1) {
                          _syncPageKey.currentState?.refreshStatus();
                        }
                      },
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainer,
                      child: Icon(
                        Icons.refresh,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: "add_account_fab",
                      elevation: 1,
                      focusElevation: 0,
                      hoverElevation: 0,
                      highlightElevation: 0,
                      onPressed: () {
                        _accountListPageKey.currentState
                            ?.showAddAccountDialog();
                      },
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 迁移导航守卫逻辑
  void _onDestinationSelected(int index) async {
    final s = SettingsService();
    bool hasWebDav = s.get('webdav_url') != null && s.get('webdav_pwd') != null;
    bool hasDb = await StorageService().isDatabaseExists();
    // 设置页无需拦截
    if (index == 2) {
      setState(() => _selectedIndex = index);
      _settingsPageKey.currentState?.checkDbStatus(); // 刷新设置界面配置webdav选项
      return;
    }
    // 情况1: 未建库仅允许在主页(0)
    if (!hasDb && index != 0) {
      _showGuardDialog("访问受限", "请先在主页创建新数据库");
      return;
    }
    // 情况2: 未配WebDAV进入云同步页(1)
    if (!hasWebDav && index == 1) {
      _showGuardDialog("访问受限", "请先在设置中配置并连接 WebDAV 云盘");
      return;
    }
    setState(() => _selectedIndex = index);
    if (index == 0) _accountListPageKey.currentState?.requestPageFocus();
    if (index == 1) _syncPageKey.currentState?.refreshStatus(); // 刷新云同步界面
  }

  // 弹出功能受限对话框
  void _showGuardDialog(String titleMsg, String contextMsg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleMsg),
        content: Text(contextMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  // 清理内存并直接退出登录
  void _logoutDirectly(String message) {
    WebDavService().reset(); // 重置webdav状态
    SecurityService().clearKeys();
    StorageService().closeDatabase();

    if (!mounted) return;
    MessageUtil.show(context, message);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const UnlockPage()),
      (route) => false,
    );
  }
}

// 回收站界面
class TrashPage extends StatelessWidget {
  const TrashPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("回收站"));
  }
}
