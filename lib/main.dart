/*
 * @Author: Thoma4
 * @Date: 2026-02-09 23:51:46
 * @LastEditTime: 2026-02-19 18:02:30
 * @Description: 
 */

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:uuid/uuid.dart';

import 'pages/account_list_page.dart';
import 'models/account.dart';
import 'services/storage_service.dart';
import 'services/csv_service.dart';

void main() async {
  // 1. 确保初始化
  WidgetsFlutterBinding.ensureInitialized();
  // 2. 初始化窗口管理器
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600), // 默认启动大小
    minimumSize: Size(800, 600), // 限制最小尺寸，防止UI崩坏
    center: true, // 启动时居中
    title: "Vault Keeper", // 窗口标题
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const VaultApp());
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0; // 当前选中的页面索引

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 1. 左侧导航栏
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index; // 切换页面
              });
            },
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Icon(Icons.shield, size: 40, color: Colors.blue), // 应用Logo
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
            // 侧边栏底部的“添加”按钮
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: FloatingActionButton(
                    onPressed: () {
                      _showAddAccountDialog();
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
          ),

          const VerticalDivider(thickness: 1, width: 1),

          // 2. 右侧主体区
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                AccountListPage(), // 账户列表页
                SyncPage(), // 同步页
                MigrationPage(), // 导入导出页
                TrashPage(), // 回收站页
                SettingsPage(), // 设置页
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 弹出新增账户对话框
  void _showAddAccountDialog() {
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

// --- 以下是各页面的简单占位符 ---

// class AccountListPage extends StatelessWidget {
//   const AccountListPage({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         // 顶部搜索框
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: TextField(
//             decoration: InputDecoration(
//               hintText: "搜索账户 (Ctrl + F)",
//               prefixIcon: const Icon(Icons.search),
//               border: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//             ),
//           ),
//         ),
//         // 下面是模拟的表格列表
//         Expanded(child: Center(child: Text("这里将放置 Edge 风格的账户表格"))),
//       ],
//     );
//   }
// }

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("同步与历史记录"));
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
              // 1. 调用导入服务
              int count = await CsvService().pickAndImportCsv();
              // 2. 弹窗提示结果
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("应用设置"));
  }
}
