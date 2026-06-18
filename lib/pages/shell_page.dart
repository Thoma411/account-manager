/*
 * @Author: Thoma4
 * @Date: 2026-03-21 18:50:58
 * @LastEditTime: 2026-06-18 00:23:29
 * @Description: 主框架
 */

import 'dart:io';
import 'dart:convert';
import 'package:accountmanager/pages/login_page.dart';
import 'package:accountmanager/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart';
import 'account_list_page.dart';
import '../models/account.dart';
import '../services/storage_service.dart';
import '../services/security_service.dart';
import '../services/settings_service.dart';
import '../services/icon_service.dart';
import '../services/webdav_service.dart';
import '../services/csv_service.dart';
import '../utils/utils.dart';

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
    windowManager.addListener(this); // 注册窗口监听
    windowManager.setPreventClose(true); // 接管关闭按钮
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
    windowManager.removeListener(this); // 销毁监听
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
    return Scaffold(
      body: Stack(
        children: [
          // 左右布局(导航栏+内容区)
          Row(
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
                child: IndexedStack(index: _selectedIndex, children: _pages),
              ),
            ],
          ),
          // 固定新增按钮
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
                      _accountListPageKey.currentState?.refreshAccountList();
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
                  onPressed: _showAddAccountDialog,
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

  // 弹出新增账户对话框
  void _showAddAccountDialog() async {
    bool hasDb = await StorageService().isDatabaseExists(); // 检测数据库是否存在
    if (!mounted) return;
    if (!hasDb) {
      _showGuardDialog("操作受阻", "请先在主界面“创建新数据库”并设置主密码，然后再添加账户条目。");
      return; // 拦截后续的新增逻辑
    }

    final formKey = GlobalKey<FormState>();

    // 临时变量，用于存储弹窗内的输入
    String platform = '',
        url = '',
        name = '',
        userId = '',
        email = '',
        pswd = '',
        phone = '',
        notes = '',
        tagsStr = '';
    int status = 1; // 默认使用中
    bool realName = false;

    final birthController = TextEditingController();
    final signupController = TextEditingController();

    bool isExpanded = false; // 默认折叠
    double devideH = 6;
    showDialog(
      context: context,
      builder: (context) {
        // 使用 StatefulBuilder 处理弹窗内的复选框刷新
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("新增账户条目"),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // 紧凑布局
                      children: [
                        // 关键信息
                        SizedBox(height: devideH / 2),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "平台名称*"),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? "请输入平台名称" : null,
                          onChanged: (v) => platform = v,
                        ),
                        const Divider(),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "用户昵称*"),
                          onChanged: (v) => name = v,
                        ),
                        SizedBox(height: devideH),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "用户ID*"),
                          onChanged: (v) => userId = v,
                        ),
                        SizedBox(height: devideH),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "密码*"),
                          onChanged: (v) => pswd = v,
                        ),
                        SizedBox(height: devideH),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "绑定邮箱*"),
                          onChanged: (v) => email = v,
                        ),
                        SizedBox(height: devideH),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "绑定手机*"),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          onChanged: (v) => phone = v,
                        ),
                        SizedBox(height: devideH),
                        // 附加信息
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300), // 动画时长
                          curve: Curves.easeInOut,
                          child: SizedBox(
                            width: double.infinity,
                            child: isExpanded
                                ? Column(
                                    children: [
                                      TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: "网址",
                                        ),
                                        onChanged: (v) => url = v,
                                      ),
                                      SizedBox(height: devideH),
                                      TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: "标签 (逗号分隔)",
                                        ),
                                        onChanged: (v) => tagsStr = v,
                                      ),
                                      SizedBox(height: devideH),
                                      DropdownButtonFormField<int>(
                                        initialValue: status,
                                        decoration: const InputDecoration(
                                          labelText: "账户状态",
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 1,
                                            child: Text("使用中"),
                                          ),
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text("未注册"),
                                          ),
                                          DropdownMenuItem(
                                            value: 2,
                                            child: Text("已注销"),
                                          ),
                                          DropdownMenuItem(
                                            value: 3,
                                            child: Text("无法使用"),
                                          ),
                                        ],
                                        onChanged: (v) => setDialogState(
                                          () => status = v ?? 1,
                                        ),
                                      ),
                                      SizedBox(height: devideH),
                                      TextFormField(
                                        controller: birthController,
                                        decoration: InputDecoration(
                                          labelText: "生日",
                                          suffixIcon: IconButton(
                                            icon: const Icon(
                                              Icons.calendar_today,
                                              size: 16,
                                            ),
                                            onPressed: () async {
                                              final date = await showDatePicker(
                                                context: context,
                                                initialDate: DateTime.now(),
                                                firstDate: DateTime(1900),
                                                lastDate: DateTime(2100),
                                              );
                                              if (date != null) {
                                                birthController.text =
                                                    DateFormat(
                                                      'yyyy-MM-dd',
                                                    ).format(date);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: devideH),
                                      TextFormField(
                                        controller: signupController,
                                        decoration: InputDecoration(
                                          labelText: "注册日期",
                                          suffixIcon: IconButton(
                                            icon: const Icon(
                                              Icons.calendar_today,
                                              size: 16,
                                            ),
                                            onPressed: () async {
                                              final date = await showDatePicker(
                                                context: context,
                                                initialDate: DateTime.now(),
                                                firstDate: DateTime(1900),
                                                lastDate: DateTime(2100),
                                              );
                                              if (date != null) {
                                                signupController.text =
                                                    DateFormat(
                                                      'yyyy-MM-dd',
                                                    ).format(date);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: devideH),
                                      CheckboxListTile(
                                        title: const Text("是否已实名"),
                                        value: realName,
                                        onChanged: (v) {
                                          setDialogState(() {
                                            realName = v ?? false;
                                          });
                                        },
                                      ),
                                      SizedBox(height: devideH),
                                      TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: "备注",
                                        ),
                                        onChanged: (v) => notes = v,
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              setDialogState(() => isExpanded = !isExpanded);
                            },
                            icon: Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            label: Text(isExpanded ? "收起附加信息" : "填写更多信息"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // 平台重名检测
                      final storage = StorageService();
                      bool isDuplicate = await storage.isPlatformNameExists(
                        platform,
                      );
                      if (isDuplicate) {
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("平台名冲突"),
                            content: Text("平台 '$platform' 已存在，请更换名称。"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("确认"),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      bool hasAnyCredential =
                          name.trim().isNotEmpty ||
                          userId.trim().isNotEmpty ||
                          pswd.trim().isNotEmpty ||
                          email.trim().isNotEmpty ||
                          phone.trim().isNotEmpty; // 检测是否充分填写信息
                      if (!hasAnyCredential) {
                        if (!context.mounted) return;
                        _showGuardDialog(
                          "信息不足",
                          "请至少填写一项关键信息：[昵称 | ID | 密码 | 邮箱 | 手机]",
                        );
                        return;
                      }
                      // 保存新账户
                      final newAccount = Account(
                        id: const Uuid().v4(),
                        platform: platform,
                        url: url,
                        status: status,
                        name: name,
                        userId: userId,
                        email: email,
                        pswd: pswd,
                        phone: phone,
                        birth: birthController.text.trim().isEmpty
                            ? null
                            : DateTime.tryParse(birthController.text),
                        notes: notes,
                        signupDate: signupController.text.trim().isEmpty
                            ? null
                            : DateTime.tryParse(signupController.text),
                        realName: realName,
                        tags: tagsStr
                            .split(RegExp(r'[,，]'))
                            .map((t) => t.trim())
                            .where((t) => t.isNotEmpty)
                            .take(8)
                            .toList(), // 标签最大数量: 8
                        lastModified: DateTime.now().toIso8601String(),
                      );
                      await StorageService().insertAccount(newAccount);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _accountListPageKey.currentState?.refreshAccountList();
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("账户添加成功")));
                    }
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );
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
        content: Column(
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // 先关警告框
              try {
                bool success = await CsvService().exportToCsv();
                if (success && context.mounted) {
                  MessageUtil.show(context, "数据已成功导出至本地");
                }
              } catch (e) {
                if (context.mounted) MessageUtil.show(context, "导出失败: $e");
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
        content: Column(
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
        const ListTile(
          title: Text("关于项目"),
          subtitle: Text("accountManager v1.0.0-Beta"),
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

  // 处理智能同步逻辑
  Future<void> _handleSmartSync() async {
    if (_isLoading) return;
    final decision = await _webdav.compareVersions();
    switch (decision) {
      case SyncDecision.localNewer:
      case SyncDecision.noRemote:
        await _executeSync(true); // 直接调用执行器上传
        break;
      case SyncDecision.remoteNewer:
        _showConflictDialog(
          onConfirmLocal: () => _executeSync(true),
          onConfirmRemote: () => _executeSync(false),
        );
        break;
      case SyncDecision.bothSynced:
        _addLog("智能同步", "无需操作：已是最新");
        break;
      default:
        _addLog("智能同步", "异常：无法获取状态");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "云同步仪表盘",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // 顶部对比卡片
          Row(
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
          ),
          const SizedBox(height: 32),
          // 下方: 左操作, 右日志
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧操作区 (Flex 2)
                Expanded(
                  flex: 2,
                  child: Column(
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
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 32),
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
                  ),
                ),
                const SizedBox(width: 40), // 左右间距
                // 右侧日志区 (Flex 3)
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 处理具体的物理同步动作
  Future<void> _executeSync(bool isUpload) async {
    final path = await _storage.getDatabasePath();
    final actionName = isUpload ? "上传" : "下载";

    try {
      setState(() => _isLoading = true);
      if (isUpload) {
        String newEtag = await _webdav.uploadVault(path);
        await _updateSyncMarkers(newEtag);
        _addLog(actionName, "成功：云端已更新");
      } else {
        await _storage.closeDatabase();
        String newEtag = await _webdav.downloadVault(path);
        await _settings.set('last_synced_etag', newEtag);
        _addLog(actionName, "成功：本地已拉取");

        if (!mounted) return;
        // 下载后的强制重定向
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
      case SyncDecision.noRemote:
        return "上传本地更新";
      case SyncDecision.remoteNewer:
        return "拉取云端更新";
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
}

// 回收站界面
class TrashPage extends StatelessWidget {
  const TrashPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("回收站"));
  }
}
