/*
 * @Author: Thoma4
 * @Date: 2026-03-21 18:50:58
 * @LastEditTime: 2026-04-08 21:23:02
 * @Description: 主框架
 */

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'account_list_page.dart';
import '../models/account.dart';
import '../services/storage_service.dart';
import '../services/settings_service.dart';
import '../services/csv_service.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;

  // 页面列表
  final List<Widget> _pages = [
    const AccountListPage(),
    const Center(child: Text("云同步 (开发中)")),
    const MigrationPage(),
    const Center(child: Text("回收站 (开发中)")),
    const SettingsPage(),
  ];

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
    bool hasDb = await StorageService().isDatabaseExists();
    if (!hasDb && index != 0) {
      // !暂时限制未建库用户进入设置页
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("功能受限"),
          content: const Text("请先在主页创建新数据库"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("确认"),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _selectedIndex = index);
  }

  // 弹出新增账户对话框
  void _showAddAccountDialog() async {
    bool hasDb = await StorageService().isDatabaseExists(); // 检测数据库是否存在
    if (!mounted) return;
    if (!hasDb) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("操作受阻"),
          content: const Text("请先在主界面“创建新数据库”并设置主密码，然后再添加账户条目。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("确认"),
            ),
          ],
        ),
      );
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
}

// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService();
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    // 从已经 loadSettings 加载好的缓存中获取值
    _isDarkMode = _settings.get('dark_mode') == 'true';
  }

  void _toggleDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    // 异步存入数据库
    await _settings.set('dark_mode', value.toString());
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
          subtitle: const Text("测试配置持久化架构"),
          value: _isDarkMode,
          onChanged: _toggleDarkMode,
          secondary: const Icon(Icons.brightness_6),
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

class TrashPage extends StatelessWidget {
  const TrashPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("回收站"));
  }
}
