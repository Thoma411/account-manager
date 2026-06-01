/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:00:56
 * @LastEditTime: 2026-06-01 23:42:52
 * @Description: 账户信息页(查看页)
 */

import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webdav_client/webdav_client.dart' as dav;

import '../models/account.dart'; // 导入模型
import '../services/storage_service.dart'; // 导入存储服务
import '../services/security_service.dart'; // 导入安全服务
import '../services/webdav_service.dart';
import '../pages/login_page.dart';
import '../utils/utils.dart';

class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key});

  @override
  State<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<AccountListPage> {
  bool _isDbCreated = true; // 检测本地数据库是否存在

  // 数据源由 Map 改为 Account 对象列表
  int? _selectedRowIndex;
  bool _isPanelOpen = false;

  // 查找方法定义与数据结构
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // 用于 Ctrl+F 聚焦

  List<Account> _allAccounts = []; // 完整的数据库副本
  List<Account> _displayAccounts = []; // 经过过滤后显示在界面上的列表

  // 增加初始化逻辑，进入页面即拉取数据库
  @override
  void initState() {
    super.initState();
    _checkDbStatus();
    _refreshAccountList();
  }

  // 检查数据库库状态
  Future<void> _checkDbStatus() async {
    bool exists = await StorageService().isDatabaseExists();
    setState(() {
      _isDbCreated = exists;
    });
  }

  // 刷新列表
  Future<void> _refreshAccountList() async {
    // 先判断库是否存在，不存在直接返回空列表
    bool exists = await StorageService().isDatabaseExists();
    if (!exists) {
      setState(() {
        _allAccounts = [];
        _displayAccounts = [];
      });
      return;
    }

    final data = await StorageService().getAllAccounts();
    setState(() {
      _allAccounts = data;
      // 刷新时根据当前搜索框内容过滤
      _filterAccounts(_searchController.text);
    });
  }

  // 核心过滤逻辑
  void _filterAccounts(String query) {
    setState(() {
      if (query.isEmpty) {
        _displayAccounts = _allAccounts; // 如果搜索框为空,显示全部
      } else {
        final lowercaseQuery = query.toLowerCase(); // 提前转小写,优化性能

        _displayAccounts = _allAccounts.where((acc) {
          // 1. 基础必填字段匹配
          final platformMatch = acc.platform.toLowerCase().contains(
            lowercaseQuery,
          );
          final nameMatch = acc.name.toLowerCase().contains(lowercaseQuery);
          final userIdMatch = acc.userId.toLowerCase().contains(lowercaseQuery);

          // 2. 备注类字段匹配（使用 ?? '' 处理 null 值）
          final pfRemarkMatch = (acc.pfRemark ?? "").toLowerCase().contains(
            lowercaseQuery,
          );
          final infoRemarkMatch = (acc.infoRemark ?? "").toLowerCase().contains(
            lowercaseQuery,
          );

          // 3. 标签匹配
          final tagsMatch = acc.tags.any(
            (tag) => tag.toLowerCase().contains(lowercaseQuery),
          );

          // 返回以上任一条件满足的结果
          return platformMatch ||
              nameMatch ||
              userIdMatch ||
              pfRemarkMatch ||
              infoRemarkMatch ||
              tagsMatch;
        }).toList();
      }
    });
  }

  // 弹出删除确认对话框
  void _confirmDelete(Account account) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("确认删除"),
          content: Text("确定要删除 ${account.platform} 的账户信息吗？此操作不可撤销。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // 关闭弹窗
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () async {
                await StorageService().deleteAccount(account.id); // 执行删除
                if (!context.mounted) return;

                Navigator.of(context).pop(); // 关闭弹窗
                setState(() {
                  _selectedRowIndex = null; // 删除后立即清空选中索引
                  _isPanelOpen = false; // 关闭面板
                });
                _refreshAccountList(); // 刷新列表
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("条目已成功删除")));
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("确定删除"),
            ),
          ],
        );
      },
    );
  }

  void _onAccountSelected(int index) {
    setState(() {
      _selectedRowIndex = index;
      _isPanelOpen = true;
    });
  }

  void _closePanel() {
    setState(() {
      _isPanelOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 定义侧栏宽度
    const double panelWidth = 400;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          mini: true,
          heroTag: "refresh_list_fab",
          onPressed: _refreshAccountList,
          child: const Icon(Icons.refresh),
        ),
        body: Stack(
          children: [
            // 1. 底层列表（永远可见）
            Column(
              children: [
                _buildSearchBox(),
                Expanded(
                  child: _allAccounts.isEmpty
                      ? _buildEmptyStateUI() // 调用新的空状态 UI
                      : _buildAccountTable(),
                ),
              ],
            ),

            // 2. 动画遮罩层
            // 使用 IgnorePointer 确保遮罩消失时不会拦截点击事件
            IgnorePointer(
              ignoring: !_isPanelOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isPanelOpen ? 1.0 : 0.0,
                child: GestureDetector(
                  onTap: _closePanel,
                  child: Container(color: Colors.black.withValues(alpha: 0.3)),
                ),
              ),
            ),

            // 3. 动画滑动面板
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn, // 使用 M3 标准的强调曲线，更有质感
              right: _isPanelOpen ? 0 : -panelWidth, // 展开时在右边缘，关闭时藏在屏幕外
              top: 0,
              bottom: 0,
              width: panelWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(-5, 0),
                    ),
                  ],
                ),
                // 关键：如果没选中任何行，面板内容显示为空，防止报错
                child:
                    (_isPanelOpen &&
                        _selectedRowIndex != null &&
                        _selectedRowIndex! < _displayAccounts.length) // 确保索引没越界
                    ? _buildDetailPanel(_displayAccounts[_selectedRowIndex!])
                    : const SizedBox.shrink(), // 如果越界或没选中则渲染一个空盒子
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            "欢迎使用 Vault Keeper",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _isDbCreated ? "空空如也？请点击侧栏导入或点击'+'号添加账户" : "尚未初始化数据库，请选择操作以开始使用",
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          // 如果数据库不存在，显示两个核心按钮
          if (!_isDbCreated)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _showSetupMasterPasswordDialog();
                  },
                  icon: const Icon(Icons.add_moderator),
                  label: const Text("创建新数据库"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(180, 50),
                  ),
                ),
                const SizedBox(width: 20),
                OutlinedButton.icon(
                  onPressed: () {
                    _showRestoreFromCloudDialog();
                  },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text("从云端恢复备份"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(180, 50),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController, // 绑定控制器
        focusNode: _searchFocusNode, // 绑定焦点
        onChanged: (value) => _filterAccounts(value), // 输入变化时即时过滤
        decoration: InputDecoration(
          hintText: "搜索账户 (Ctrl + F)",
          prefixIcon: const Icon(Icons.search),
          // 增加清除按钮
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterAccounts("");
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildAccountTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth =
            constraints.maxWidth - 48; // 减去 DataTable 的 24*2 边距
        final double col1 = availableWidth * 0.2;
        final double col2 = availableWidth * 0.1;
        final double col3 = availableWidth * 0.3;
        final double col4 = availableWidth * 0.4; // 标签列可以稍微宽一点

        return Column(
          children: [
            // 固定表头
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 24,
                  ), // 关键：匹配 DataTable 的 horizontalMargin
                  SizedBox(
                    width: col1,
                    child: const Text(
                      '平台',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  SizedBox(
                    width: col2,
                    child: const Text(
                      '类型',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  SizedBox(
                    width: col3,
                    child: const Text(
                      '用户昵称',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  SizedBox(
                    width: col4,
                    child: const Text(
                      '标签',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 24), // 尾部边距对齐
                ],
              ),
            ),

            // 滚动内容
            Expanded(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    horizontalMargin: 24, // 显式设定边距为 24
                    headingRowHeight: 0,
                    showCheckboxColumn: false,
                    columnSpacing: 0, // 将列间距设为0，完全依靠 SizedBox 控制宽度
                    columns: [
                      DataColumn(label: SizedBox(width: col1)),
                      DataColumn(label: SizedBox(width: col2)),
                      DataColumn(label: SizedBox(width: col3)),
                      DataColumn(label: SizedBox(width: col4)),
                    ],
                    rows: List<DataRow>.generate(_displayAccounts.length, (
                      index,
                    ) {
                      final acc = _displayAccounts[index];
                      return DataRow(
                        selected: _selectedRowIndex == index,
                        onSelectChanged: (selected) =>
                            _onAccountSelected(index),
                        cells: [
                          DataCell(
                            SizedBox(width: col1, child: Text(acc.platform)),
                          ),
                          DataCell(
                            SizedBox(width: col2, child: Text(acc.pfType)),
                          ),
                          DataCell(
                            SizedBox(width: col3, child: Text(acc.name)),
                          ),
                          DataCell(
                            SizedBox(
                              width: col4,
                              child: Text(
                                acc.tags.isEmpty ? "-" : acc.tags.join(", "),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 改动点 5: 详情面板接收 Account 对象而非 Map ---
  Widget _buildDetailPanel(Account account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "账户详情",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(onPressed: _closePanel, icon: const Icon(Icons.close)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildInfoRow("平台名称", account.platform),
              _buildInfoRow("用户昵称", account.name),
              _buildInfoRow("平台类型", account.pfType),
              _buildInfoRow("备注(平台)", account.pfRemark ?? "无"),
              _buildInfoRow("标签", account.tags.join(", ")),
              _buildInfoRow("用户ID", account.userId),
              _buildInfoRow("绑定邮箱", account.email),
              _buildInfoRow("绑定手机", account.phone),
              _buildInfoRow("密码", account.pswd),
              _buildInfoRow("预留生日", account.birth ?? "未填写"),
              _buildInfoRow("注册日期", account.signupDate),
              _buildInfoRow("实名标记", account.realName ? "是" : "否"),
              _buildInfoRow("备注(账户)", account.infoRemark ?? "无"),
              _buildInfoRow("最后修改于", DateUtil.format(account.lastModified)),
              const SizedBox(height: 20),
              //*修改条目按钮
              ElevatedButton.icon(
                onPressed: () => _showEditAccountDialog(account),
                icon: const Icon(Icons.edit),
                label: const Text("修改此条目"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),
              //*删除条目按钮
              OutlinedButton.icon(
                onPressed: () => _confirmDelete(account), // 触发确认弹窗
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text("删除此条目", style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 45),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // 创建主密码对话框
  void _showSetupMasterPasswordDialog() {
    final pwController = TextEditingController();
    final confirmController = TextEditingController();
    final sec = SecurityService();
    final storage = StorageService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("初始化安全保险箱"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("设置主密码后，我们将为您生成唯一的加密环境。"),
            const SizedBox(height: 20),
            TextField(
              controller: pwController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "输入主密码 (不少于6位)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "确认主密码"),
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
              String pw = pwController.text;
              if (pw != confirmController.text || pw.length < 6) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("密码不一致或长度不足6位")));
                return;
              }

              // 开始核心加密初始化
              try {
                // 1. 触发建库
                await storage.database;

                // 2. 生成随机原语
                final salt = sec.generateRandomBytes(32); // 32字节盐
                final dkBytes = sec.generateRandomBytes(32); // 32字节数据密钥 (DK)
                final rkBytes = sec.generateRandomBytes(32); // 32字节恢复密钥 (RK)

                final dk = enc.Key(dkBytes);
                final rk = enc.Key(rkBytes);
                final rkString = base64.encode(rkBytes); // 用户的救命稻草

                // 3. 派生主密钥 (MK)
                final mk = sec.deriveMasterKey(pw, salt);

                // 4. 执行"信封包装"加密
                final edkM = sec.encrypt(base64.encode(dkBytes), mk); // MK锁DK
                final edkR = sec.encrypt(base64.encode(dkBytes), rk); // RK锁DK
                final evb = sec.encrypt("VAULT_READY", dk); // DK锁验证块
                final erk = sec.encrypt(rkString, dk); // DK锁RK(供日后查看)

                // 5. 持久化到 system_metadata
                await storage.saveMetadata('master_salt', base64.encode(salt));
                await storage.saveMetadata('edk_m', edkM);
                await storage.saveMetadata('edk_r', edkR);
                await storage.saveMetadata('evb', evb);
                await storage.saveMetadata('erk', erk);

                sec.setDK(dk); // 初始化成功后立即激活内存钥匙
                if (!context.mounted) return;
                Navigator.pop(context); // 关闭输入框

                // 6. 展示恢复密钥 (RK)
                _showRecoveryKeyDialog(rkString);
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("初始化失败: $e")));
              }
            },
            child: const Text("开始创建"),
          ),
        ],
      ),
    );
  }

  // 创建云端同步对话框
  void _showRestoreFromCloudDialog() {
    final urlController = TextEditingController();
    final userController = TextEditingController();
    final pwdController = TextEditingController();
    final webdav = WebDavService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("从云端拉取备份"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("请输入您的WebDAV配置信息以连接云盘。"),
            const SizedBox(height: 20),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: "服务器地址"),
            ),
            TextField(
              controller: userController,
              decoration: const InputDecoration(labelText: "账号"),
            ),
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
              try {
                // 尝试连接
                webdav.initCustomClient(
                  urlController.text,
                  userController.text,
                  pwdController.text,
                );
                List<dav.File> files;
                try {
                  files = await webdav.readDir('/vault_keeper');
                } catch (e) {
                  throw Exception("无法访问云端目录/vault_keeper，请确认目录已手动创建或执行过备份。");
                }
                // 检查文件是否存在
                bool fileExists = files.any((f) => f.name == 'vault_keeper.db');
                if (!fileExists) throw Exception("云端目录中未找到vault_keeper.db");
                final localPath = await StorageService()
                    .getDatabasePath(); // 获取本地存放路径
                await webdav.downloadVault(localPath); // 下载
                if (!context.mounted) return;
                Navigator.pop(context); // 关闭配置弹窗
                // 下载成功后，由于本地有了.db，自动引导至解锁流程
                MessageUtil.show(context, "备份已下载，重新解锁以载入数据");
                // 强制跳转到解锁界面，并清空之前的路由栈（防止用户通过返回键回到未解密的界面）
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const UnlockPage()),
                  (route) => false, // 这会销毁当前的ShellPage
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("恢复失败: $e")));
                }
              }
            },
            child: const Text("开始恢复"),
          ),
        ],
      ),
    );
  }

  // 展示恢复密钥对话框
  void _showRecoveryKeyDialog(String rk) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text("请保存您的恢复密钥"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("如果您忘记了主密码，这是找回数据的唯一方法。请务必将其复制并妥善保存。"),
            const SizedBox(height: 20),
            SelectableText(
              rk,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
                fontFamily: 'monospace', // 使用等宽字体
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // 成功后刷新状态
              await _checkDbStatus();
              await _refreshAccountList();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("保险箱已就绪")));
              }
            },
            child: const Text("我已保存恢复密钥"),
          ),
        ],
      ),
    );
  }

  // 弹出修改账户对话框
  void _showEditAccountDialog(Account account) {
    final formKey = GlobalKey<FormState>();

    // 使用现有账户的数据初始化变量
    String platform = account.platform;
    String pfType = account.pfType;
    String pfRemark = account.pfRemark ?? '';
    String name = account.name;
    String userId = account.userId;
    String email = account.email;
    String pswd = account.pswd;
    String phone = account.phone;
    String birth = account.birth ?? '';
    String infoRemark = account.infoRemark ?? '';
    String signupDate = account.signupDate;
    String tagsStr = account.tags.join(',');
    bool realName = account.realName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("修改账户: ${account.platform}"),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: platform, // 设置初始值
                      decoration: const InputDecoration(
                        labelText: "平台名称 (必填) *",
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? "请输入平台名称" : null,
                      onChanged: (v) => platform = v,
                    ),
                    TextFormField(
                      initialValue: name, // 设置初始值
                      decoration: const InputDecoration(
                        labelText: "用户昵称 (必填) *",
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? "请输入用户昵称" : null,
                      onChanged: (v) => name = v,
                    ),
                    const Divider(height: 32),
                    TextFormField(
                      initialValue: pfType,
                      decoration: const InputDecoration(labelText: "平台类型"),
                      onChanged: (v) => pfType = v,
                    ),
                    TextFormField(
                      initialValue: pfRemark,
                      decoration: const InputDecoration(labelText: "平台备注"),
                      onChanged: (v) => pfRemark = v,
                    ),
                    TextFormField(
                      initialValue: userId,
                      decoration: const InputDecoration(labelText: "用户ID"),
                      onChanged: (v) => userId = v,
                    ),
                    TextFormField(
                      initialValue: pswd,
                      decoration: const InputDecoration(labelText: "密码"),
                      onChanged: (v) => pswd = v,
                    ),
                    TextFormField(
                      initialValue: phone,
                      decoration: const InputDecoration(labelText: "绑定手机"),
                      onChanged: (v) => phone = v,
                    ),
                    TextFormField(
                      initialValue: email,
                      decoration: const InputDecoration(labelText: "绑定邮箱"),
                      onChanged: (v) => email = v,
                    ),
                    TextFormField(
                      initialValue: birth,
                      decoration: const InputDecoration(labelText: "预留生日"),
                      onChanged: (v) => birth = v,
                    ),
                    TextFormField(
                      initialValue: tagsStr,
                      decoration: const InputDecoration(labelText: "标签 (逗号分隔)"),
                      onChanged: (v) => tagsStr = v,
                    ),
                    TextFormField(
                      initialValue: infoRemark,
                      decoration: const InputDecoration(labelText: "账户备注"),
                      onChanged: (v) => infoRemark = v,
                    ),
                    TextFormField(
                      initialValue: signupDate,
                      decoration: const InputDecoration(labelText: "注册时间"),
                      onChanged: (v) => signupDate = v,
                    ),
                    CheckboxListTile(
                      title: const Text("是否已实名"),
                      value: realName,
                      onChanged: (v) =>
                          setDialogState(() => realName = v ?? false),
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
                  // 构造更新后的 Account 对象 (保持 ID 不变)
                  final updatedAccount = Account(
                    id: account.id, // 关键：使用原有的 ID
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

                  // 存入数据库 (由于 ID 相同，insertAccount 里的 replace 逻辑会覆盖旧数据)
                  await StorageService().insertAccount(updatedAccount);

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _refreshAccountList(); // 刷新列表
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("修改成功！")));
                }
              },
              child: const Text("保存修改"),
            ),
          ],
        ),
      ),
    );
  }
}
