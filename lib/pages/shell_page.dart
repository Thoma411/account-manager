/*
 * @Author: Thoma4
 * @Date: 2026-03-21 18:50:58
 * @LastEditTime: 2026-06-03 21:26:40
 * @Description: 主框架
 */

import 'dart:io';
import 'dart:convert';
import 'package:accountmanager/pages/login_page.dart';
import 'package:accountmanager/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'account_list_page.dart';
import '../models/account.dart';
import '../services/storage_service.dart';
import '../services/security_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import '../services/csv_service.dart';
import '../utils/utils.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;

  final GlobalKey<SyncPageState> _syncPageKey = GlobalKey<SyncPageState>();
  final GlobalKey<SettingsPageState> _settingsPageKey =
      GlobalKey<SettingsPageState>();
  late List<Widget> _pages;

  // 页面列表
  @override
  void initState() {
    super.initState();
    _pages = [
      const AccountListPage(),
      SyncPage(key: _syncPageKey),
      const MigrationPage(),
      const Center(child: Text("回收站 (开发中)")),
      SettingsPage(key: _settingsPageKey),
    ];
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
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Icon(Icons.shield, size: 40, color: Colors.blue),
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
                    icon: Icon(Icons.file_download),
                    label: Text('导入导出'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.delete_outline),
                    label: Text('回收站'),
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
            child: FloatingActionButton(
              heroTag: "add_account_fab",
              onPressed: _showAddAccountDialog,
              child: const Icon(Icons.add),
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

    // 情况1: 未建库 只允许留在主页
    if (!hasDb && index != 0 && index != 4) {
      _showGuardDialog("访问受限", "请先在主页创建新数据库");
      return;
    }
    // 情况2: 未配WebDAV 进入云同步页
    if (!hasWebDav && index == 1) {
      _showGuardDialog("访问受限", "请先在设置中配置并连接 WebDAV 云盘");
      return;
    }
    setState(() => _selectedIndex = index);
    if (index == 4) {
      _settingsPageKey.currentState?.checkDbStatus(); // 刷新设置界面配置webdav选项
    }
    if (index == 1) {
      _syncPageKey.currentState?.refreshStatus(); // 刷新云同步界面
    }
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
        pfType = '',
        pfRemark = '',
        name = '',
        userId = '',
        email = '',
        pswd = '',
        phone = '',
        birth = '',
        infoRemark = '',
        signupDate = DateTime.now().toString().split(' ')[0],
        tagsStr = '';
    bool realName = false;

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
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: "平台名称 (必填) *",
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? "请输入平台名称" : null,
                          onChanged: (v) => platform = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: "用户昵称 (必填) *",
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? "请输入用户昵称" : null,
                          onChanged: (v) => name = v,
                        ),
                        const Divider(height: 32),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "平台类型"),
                          onChanged: (v) => pfType = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "平台备注"),
                          onChanged: (v) => pfRemark = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "用户ID"),
                          onChanged: (v) => userId = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "密码"),
                          onChanged: (v) => pswd = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "绑定手机"),
                          onChanged: (v) => phone = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "绑定邮箱"),
                          onChanged: (v) => email = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "预留生日"),
                          onChanged: (v) => birth = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: "标签 (逗号分隔)",
                          ),
                          onChanged: (v) => tagsStr = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "账户备注"),
                          onChanged: (v) => infoRemark = v,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: "注册时间"),
                          onChanged: (v) => signupDate = v,
                        ),
                        // 实名勾选框，使用 setDialogState 刷新
                        CheckboxListTile(
                          title: const Text("是否已实名"),
                          value: realName,
                          onChanged: (v) {
                            setDialogState(() {
                              realName = v ?? false;
                            });
                          },
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
                      final newAccount = Account(
                        id: const Uuid().v4(),
                        platform: platform,
                        pfType: pfType,
                        pfRemark: pfRemark,
                        name: name,
                        userId: userId,
                        email: email,
                        pswd: pswd,
                        phone: phone,
                        birth: birth,
                        infoRemark: infoRemark,
                        signupDate: signupDate,
                        realName: realName,
                        tags: tagsStr.isEmpty ? [] : tagsStr.split(','),
                        lastModified: DateTime.now().toIso8601String(),
                      );

                      await StorageService().insertAccount(newAccount);

                      if (!context.mounted) return;

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("账户添加成功！请刷新列表")),
                      );
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
}

// 设置界面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

// 设置界面
class SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService();
  bool _isDarkMode = false; // 深色模式
  bool _hasDb = false; // 控制WebDAV按钮

  @override
  void initState() {
    super.initState();
    // 从已经loadSettings加载好的缓存中获取值
    _isDarkMode = _settings.get('dark_mode') == 'true';
    checkDbStatus();
  }

  void _toggleDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    // 异步存入数据库
    await _settings.set('dark_mode', value.toString());
  }

  // 检查数据库状态 决定是否允许配置WebDAV
  void checkDbStatus() async {
    bool exists = await StorageService().isDatabaseExists();
    if (!mounted) return;
    setState(() {
      _hasDb = exists;
    });
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
            const Text(
              "建议使用坚果云等支持WebDAV的网盘。同步数据将以加密形式上传。",
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
              const Text(
                "这是您找回数据的唯一凭证，请勿泄露给他人。",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SelectableText(
                rk,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontSize: 16,
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
            const Text(
              "修改主密码后将强制退出，请使用新主密码重新登录。",
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          "通用设置",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text("深色模式"),
          // subtitle: const Text("测试配置持久化架构"),
          value: _isDarkMode,
          onChanged: _toggleDarkMode,
          secondary: const Icon(Icons.brightness_6),
        ),
        const Divider(),
        const Text(
          "数据同步",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListTile(
          title: const Text("云端WebDAV配置"),
          subtitle: Text(_hasDb ? "已解锁，可配置云备份凭据" : "请先初始化数据库"),
          leading: const Icon(Icons.cloud_queue),
          enabled: _hasDb,
          onTap: _hasDb ? _showWebDavDialog : null,
        ),
        const Divider(),
        ListTile(
          title: const Text("查看恢复密钥"),
          subtitle: const Text("主密码遗失时，凭此密钥可重置密码并找回数据"),
          leading: const Icon(Icons.key_outlined),
          enabled: _hasDb, // 仅在有库时可用
          onTap: _showViewRKDialog,
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
        const ListTile(
          title: Text("关于项目"),
          subtitle: Text("accountManager v1.0.0-Beta"),
          leading: Icon(Icons.info_outline),
        ),
      ],
    );
  }
}

// 导入导出界面
class MigrationPage extends StatelessWidget {
  const MigrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.upload_file, size: 64, color: Colors.blue),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              // 1.检查本地是否有库
              bool hasDb = await StorageService().isDatabaseExists();
              if (!hasDb) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("错误：请先创建数据库并设置主密码")),
                );
                return;
              }
              // 2.调用导入服务
              int count = await CsvService().pickAndImportCsv();
              // 3.弹窗提示结果
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('成功导入 $count 条数据！')));
              }
            },
            child: const Text("导入账户 (CSV)"),
          ),
          const SizedBox(height: 10),
          const Text(
            "请确保 CSV 列顺序符合设计文档规范",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
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
    _addLog("连接测试", "正在连接...");
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
          _addLog("连接测试", "成功 (云端版本: ${remoteETag.substring(0, 5)}...)");
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
            child: const Text("保留本地 (上传)", style: TextStyle(color: Colors.red)),
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
    _addLog("智能同步", "正在对比...");

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
                Colors.blue,
              ),
              _buildSyncIndicator(),
              _buildStatusCard(
                "云端备份",
                Icons.cloud_done,
                _remoteTime,
                _remoteSize,
                Colors.blue,
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
                      const Text(
                        "系统将根据修改时间自动决定上传或下载",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
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
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 18, color: Colors.grey),
                              SizedBox(width: 8),
                              Text(
                                "同步日志",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
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
      _addLog(actionName, "执行中...");

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
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: isPrimary
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
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
      return const Center(
        child: Text("暂无历史记录", style: TextStyle(color: Colors.grey)),
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
            color: Colors.blueGrey,
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
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.2), width: 1),
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
                time != null ? DateUtil.format(time.toIso8601String()) : "无记录",
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (size != null)
                Text(
                  "${(size / 1024).toStringAsFixed(1)} KB",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
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
          : const Icon(Icons.arrow_forward, size: 24, color: Colors.blue),
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
