/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:00:56
 * @LastEditTime: 2026-06-14 22:27:21
 * @Description: 账户信息页(查看页)
 */

import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as dav;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../services/storage_service.dart';
import '../services/settings_service.dart';
import '../services/security_service.dart';
import '../services/webdav_service.dart';
import '../pages/login_page.dart';
import '../utils/utils.dart';

class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key});

  @override
  State<AccountListPage> createState() => AccountListPageState();
}

class AccountListPageState extends State<AccountListPage> {
  bool _isDbCreated = true; // 检测本地数据库是否存在
  final _settings = SettingsService();

  // 数据源由Map改为Account对象列表
  String? _selectedAccountId;
  bool _isPanelOpen = false;

  // 查找方法定义与数据结构
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // 用于顶部搜索栏聚焦
  final FocusNode _pageFocusNode = FocusNode();
  final Set<String> _visiblePasswordIds = {}; // 存储已开启可见性的账户ID

  List<Account> _allAccounts = []; // 完整的数据库副本
  List<Account> _displayAccounts = []; // 经过过滤后显示在界面上的列表

  Set<String> _globalTags = {}; // 用于自动补全提示
  List<String> _tempTags = []; // 临时标签集

  // 排序依据
  String _sortBy = 'platform'; // platform/last_modified
  bool _isAscending = true; // 默认升序

  bool _isEditing = false; // 是否正在编辑
  final _formKey = GlobalKey<FormState>();

  // 详情页字段控制器
  late TextEditingController _platformController,
      _nameController,
      _urlController,
      _userIdController,
      _emailController,
      _pswdController,
      _phoneController,
      _birthController,
      _notesController,
      _signupDateController,
      _tagsController;
  int _currentStatus = 1;
  bool _currentRealName = false;

  // 增加初始化逻辑，进入页面即拉取数据库
  @override
  void initState() {
    super.initState();
    // 控制器
    _platformController = TextEditingController();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _userIdController = TextEditingController();
    _emailController = TextEditingController();
    _pswdController = TextEditingController();
    _phoneController = TextEditingController();
    _birthController = TextEditingController();
    _notesController = TextEditingController();
    _signupDateController = TextEditingController();
    _tagsController = TextEditingController();
    // 监听标签输入，实时显示建议
    _tagsController.addListener(() {
      if (_isEditing) setState(() {}); // 输入时强制重绘
    });
    // 排序依据
    _sortBy = _settings.get('sort_by', defaultValue: 'platform')!;
    _isAscending =
        _settings.get('sort_ascending', defaultValue: 'true') == 'true';

    _checkDbStatus();
    refreshAccountList();
  }

  // 释放资源防止内存泄露
  @override
  void dispose() {
    _platformController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _userIdController.dispose();
    _emailController.dispose();
    _pswdController.dispose();
    _phoneController.dispose();
    _birthController.dispose();
    _notesController.dispose();
    _signupDateController.dispose();
    _tagsController.dispose();

    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  // 检查数据库状态
  Future<void> _checkDbStatus() async {
    bool exists = await StorageService().isDatabaseExists();
    setState(() {
      _isDbCreated = exists;
    });
  }

  // 刷新列表
  Future<void> refreshAccountList() async {
    // 先判断库是否存在，不存在直接返回空列表
    bool exists = await StorageService().isDatabaseExists();
    if (!exists) {
      setState(() {
        _allAccounts = [];
        _displayAccounts = [];
        _globalTags = {};
      });
      return;
    }
    final data = await StorageService().getAllAccounts();
    setState(() {
      _allAccounts = data;
      _globalTags = data.expand((acc) => acc.tags).toSet(); // tags列表展开并去重
      // 刷新时根据当前搜索框内容过滤
      _filterAccounts(_searchController.text);
    });
  }

  // 核心过滤逻辑
  void _filterAccounts(String query) {
    setState(() {
      List<Account> results = [];
      if (query.trim().isEmpty) {
        results = List.from(_allAccounts);
      } else {
        final keywords = query
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((k) => k.isNotEmpty)
            .toList();
        results = _allAccounts.where((acc) {
          // 检查条目是否满足所有关键词
          return keywords.every((keyword) {
            final platformMatch = acc.platform.toLowerCase().contains(keyword);
            final nameMatch = acc.name.toLowerCase().contains(keyword);
            final userIdMatch = acc.userId.toLowerCase().contains(keyword);
            final notesMatch = (acc.notes ?? "").toLowerCase().contains(
              keyword,
            );
            final urlMatch = acc.url.toLowerCase().contains(keyword);
            final tagsMatch = acc.tags.any(
              (tag) => tag.toLowerCase().contains(keyword),
            );
            return platformMatch ||
                nameMatch ||
                userIdMatch ||
                notesMatch ||
                urlMatch ||
                tagsMatch;
          });
        }).toList();
      }
      // 排序
      results.sort((a, b) {
        int cmp;
        if (_sortBy == 'platform') {
          cmp = a.platform.toLowerCase().compareTo(b.platform.toLowerCase());
        } else {
          cmp = a.lastModified.compareTo(b.lastModified); // 按最后修改时间排序
        }
        return _isAscending ? cmp : -cmp;
      });
      _displayAccounts = results;
    });
  }

  // 强制令页面保底节点获取焦点以防止页面切换失焦
  void requestPageFocus() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_pageFocusNode);
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
                  _selectedAccountId = null;
                  _isPanelOpen = false; // 关闭面板
                });
                refreshAccountList(); // 刷新列表
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

  // 点击账户卡片时触发
  void _onAccountSelected(int index) {
    final acc = _displayAccounts[index];
    setState(() {
      _selectedAccountId = acc.id;
      _isPanelOpen = true;
      _isEditing = false; // 切换条目时默认设为只读

      // 填充控制器
      _platformController.text = acc.platform;
      _nameController.text = acc.name;
      _urlController.text = acc.url;
      _userIdController.text = acc.userId;
      _emailController.text = acc.email;
      _pswdController.text = acc.pswd;
      _phoneController.text = acc.phone;
      _birthController.text = acc.birth != null
          ? DateFormat('yyyy-MM-dd').format(acc.birth!)
          : "";
      _notesController.text = acc.notes ?? "";
      _signupDateController.text = acc.signupDate != null
          ? DateFormat('yyyy-MM-dd').format(acc.signupDate!)
          : "";
      _tagsController.text = acc.tags.join(',');
      _currentStatus = acc.status;
      _currentRealName = acc.realName;

      _tagsController.clear(); // 清空标签输入框
      _tempTags = List.from(acc.tags); // 拷贝一份标签
    });
  }

  // 收起右侧详情页
  void _closePanel() {
    setState(() {
      _isPanelOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const double panelWidth = 400; // 定义侧栏宽度
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (!_isPanelOpen) _searchFocusNode.requestFocus();
        }, // Ctrl+F聚焦搜索框
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isPanelOpen) {
            _closePanel();
          } else {
            _pageFocusNode.requestFocus();
          }
        }, // Esc"退出"搜索框
      },
      child: Focus(
        focusNode: _pageFocusNode,
        autofocus: true,
        canRequestFocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent, // 确保不拦截子组件的点击
          onTap: () {
            if (_isPanelOpen) _closePanel();
            _pageFocusNode.requestFocus();
          },
          child: Scaffold(
            body: Stack(
              children: [
                // 底层列表
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildSearchBox()),
                        _buildSortButton(), // 新增排序按钮函数
                        const SizedBox(width: 16),
                      ],
                    ),
                    Expanded(
                      child: (!_isDbCreated || _allAccounts.isEmpty)
                          ? _buildEmptyStateUI() // 当且仅当未建库/内容为空时显示引导
                          : ListView.builder(
                              itemCount: _displayAccounts.length,
                              itemBuilder: (context, index) {
                                final acc = _displayAccounts[index];
                                return _buildAccountCard(acc, index);
                              },
                            ),
                    ),
                  ],
                ),
                // 动画遮罩层 使用IgnorePointer确保遮罩消失时不会拦截点击事件
                IgnorePointer(
                  ignoring: !_isPanelOpen,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _isPanelOpen ? 1.0 : 0.0,
                    child: GestureDetector(
                      onTap: _closePanel,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                // 动画滑动面板
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.fastOutSlowIn,
                  right: _isPanelOpen ? 0 : -panelWidth, // 展开时在右边缘，关闭时藏在屏幕外
                  top: 0,
                  bottom: 0,
                  width: panelWidth,
                  child: GestureDetector(
                    onTap: () {}, // 捕获点击防止意外详情页关闭
                    behavior: HitTestBehavior.opaque,
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
                      // 未选中任何行则面板内容显示为空，防止报错
                      child: (_isPanelOpen && _selectedAccountId != null)
                          ? (() {
                              // 在当前显示的列表中找相应ID匹配的账户对象
                              final account = _displayAccounts.firstWhere(
                                (acc) => acc.id == _selectedAccountId,
                                orElse: () =>
                                    _displayAccounts.first, // 万一没找到则回退到第一条
                              );
                              return _buildDetailPanel(account);
                            })()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建空库UI界面
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
            _isDbCreated ? "空空如也？请前往设置导入或点击'+'号添加账户" : "尚未初始化数据库，请选择操作以开始使用",
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

  // 构建搜索栏
  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController, // 绑定控制器
        focusNode: _searchFocusNode, // 绑定焦点
        onChanged: (value) => _filterAccounts(value), // 输入变化时即时过滤
        onSubmitted: (value) => _pageFocusNode.requestFocus(), // 将焦点归还页面
        decoration: InputDecoration(
          hintText: "搜索账户 (Ctrl+F)",
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

  // 构建排序选择按钮
  Widget _buildSortButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.sort_rounded, color: Colors.blueGrey),
      tooltip: "排序依据",
      onSelected: (value) async {
        setState(() {
          if (value == 'toggle_order') {
            _isAscending = !_isAscending;
          } else {
            _sortBy = value;
          }
        });
        // 持久化保存偏好
        await _settings.set('sort_by', _sortBy);
        await _settings.set('sort_ascending', _isAscending.toString());
        _filterAccounts(_searchController.text);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'platform',
          checked: _sortBy == 'platform',
          child: const Text("按平台名称"),
        ),
        CheckedPopupMenuItem(
          value: 'last_modified',
          checked: _sortBy == 'last_modified',
          child: const Text("按修改时间"),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle_order',
          child: Row(
            children: [
              Icon(
                _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(_isAscending ? "当前：升序" : "当前：降序"),
            ],
          ),
        ),
      ],
    );
  }

  // 构建标题栏(条目属性)
  // Widget _buildAccountTable() {
  //   return LayoutBuilder(
  //     builder: (context, constraints) {
  //       final double availableWidth =
  //           constraints.maxWidth - 48; // 减去 DataTable 的 24*2 边距
  //       final double col1 = availableWidth * 0.2;
  //       final double col2 = availableWidth * 0.1;
  //       final double col3 = availableWidth * 0.3;
  //       final double col4 = availableWidth * 0.4; // 标签列可以稍微宽一点
  //       return Column(
  //         children: [
  //           // 固定表头
  //           Container(
  //             height: 56,
  //             decoration: BoxDecoration(
  //               color: Theme.of(context).colorScheme.surface,
  //               border: Border(
  //                 bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
  //               ),
  //             ),
  //             child: Row(
  //               children: [
  //                 const SizedBox(
  //                   width: 24,
  //                 ), // 关键：匹配 DataTable 的 horizontalMargin
  //                 SizedBox(
  //                   width: col1,
  //                   child: const Text(
  //                     '平台',
  //                     style: TextStyle(fontWeight: FontWeight.w500),
  //                   ),
  //                 ),
  //                 SizedBox(
  //                   width: col2,
  //                   child: const Text(
  //                     '状态',
  //                     style: TextStyle(fontWeight: FontWeight.w500),
  //                   ),
  //                 ),
  //                 SizedBox(
  //                   width: col3,
  //                   child: const Text(
  //                     '用户昵称',
  //                     style: TextStyle(fontWeight: FontWeight.w500),
  //                   ),
  //                 ),
  //                 SizedBox(
  //                   width: col4,
  //                   child: const Text(
  //                     '标签',
  //                     style: TextStyle(fontWeight: FontWeight.w500),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 24), // 尾部边距对齐
  //               ],
  //             ),
  //           ),
  //           // 滚动内容
  //           Expanded(
  //             child: SingleChildScrollView(
  //               child: ConstrainedBox(
  //                 constraints: BoxConstraints(minWidth: constraints.maxWidth),
  //                 child: DataTable(
  //                   horizontalMargin: 24, // 显式设定边距为 24
  //                   headingRowHeight: 0,
  //                   showCheckboxColumn: false,
  //                   columnSpacing: 0, // 将列间距设为0，完全依靠 SizedBox 控制宽度
  //                   columns: [
  //                     DataColumn(label: SizedBox(width: col1)),
  //                     DataColumn(label: SizedBox(width: col2)),
  //                     DataColumn(label: SizedBox(width: col3)),
  //                     DataColumn(label: SizedBox(width: col4)),
  //                   ],
  //                   rows: List<DataRow>.generate(_displayAccounts.length, (
  //                     index,
  //                   ) {
  //                     final acc = _displayAccounts[index];
  //                     return DataRow(
  //                       selected: _selectedRowIndex == index,
  //                       onSelectChanged: (selected) =>
  //                           _onAccountSelected(index),
  //                       cells: [
  //                         DataCell(
  //                           SizedBox(width: col1, child: Text(acc.platform)),
  //                         ),
  //                         DataCell(
  //                           SizedBox(
  //                             width: col2,
  //                             child: _buildStatusChip(acc.status),
  //                           ),
  //                         ),
  //                         DataCell(
  //                           SizedBox(width: col3, child: Text(acc.name)),
  //                         ),
  //                         DataCell(
  //                           SizedBox(
  //                             width: col4,
  //                             child: Text(
  //                               acc.tags.isEmpty ? "-" : acc.tags.join(", "),
  //                             ),
  //                           ),
  //                         ),
  //                       ],
  //                     );
  //                   }),
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  // 构建详情面板的顶部区域
  Widget _buildDetailHeader(Account account) {
    final Color statusColor = _getStatusColor(_currentStatus);
    return Container(
      padding: const EdgeInsets.all(24),
      // 背景采用极淡的状态色，增强氛围感
      color: statusColor.withValues(alpha: 0.05),
      child: Row(
        children: [
          _buildLargeLogo(account), // 左侧大图标
          const SizedBox(width: 20),
          // 中间标题与状态标签
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEditing) ...[
                  // 只读模式：显示标题文字
                  Text(
                    account.platform,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildStatusChip(_currentStatus),
                ] else ...[
                  // 编辑模式：标题变输入框
                  TextFormField(
                    controller: _platformController,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: "平台名称",
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none, // 去掉下划线，看起来更像“就地”编辑
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 状态变下拉框
                  SizedBox(
                    height: 35,
                    child: DropdownButton<int>(
                      value: _currentStatus,
                      isDense: true,
                      underline: const SizedBox(), // 隐藏下划线
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text("使用中", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 0,
                          child: Text("未注册", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text("已注销", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text("无法使用", style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _currentStatus = v ?? 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _toggleEditMode,
            icon: Icon(
              _isEditing ? Icons.check_circle_outline : Icons.edit_note,
              color: _isEditing ? Colors.blue : Colors.blue,
            ), // 编辑/保存切换按钮
            tooltip: _isEditing ? "保存修改" : "编辑信息",
          ),
          // 右侧关闭按钮
          IconButton(
            onPressed: _closePanel, // 调用State类中的关闭方法
            icon: const Icon(Icons.close, color: Colors.grey),
            tooltip: "关闭面板",
          ),
        ],
      ),
    );
  }

  // 切换状态(只读/编辑)
  void _toggleEditMode() async {
    if (_isEditing) {
      // 去除首尾空格
      _platformController.text = _platformController.text.trim();
      _nameController.text = _nameController.text.trim();
      _urlController.text = _urlController.text.trim();
      _userIdController.text = _userIdController.text.trim();
      _emailController.text = _emailController.text.trim();
      _phoneController.text = _phoneController.text.trim();
      // 自动保存标签输入框中未回车的内容
      if (_tagsController.text.trim().isNotEmpty) {
        _addNewTag(_tagsController.text);
      }
      // 执行保存逻辑
      if (_formKey.currentState!.validate()) {
        // 获取编辑对象
        final acc = _allAccounts.firstWhere((a) => a.id == _selectedAccountId);
        final newName = _platformController.text.trim();
        // 重名检查
        if (newName.toLowerCase() != acc.platform.toLowerCase()) {
          bool exists = await StorageService().isPlatformNameExists(newName);
          if (exists) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("平台名冲突"),
                content: Text("修改失败：平台 '$newName' 已存在，请更换名称。"),
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
        }
        // 信息充分性检查
        bool hasAnyCredential =
            _nameController.text.trim().isNotEmpty ||
            _userIdController.text.trim().isNotEmpty ||
            _pswdController.text.trim().isNotEmpty ||
            _emailController.text.trim().isNotEmpty ||
            _phoneController.text.trim().isNotEmpty;
        if (!hasAnyCredential) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("保存失败"),
              content: const Text("请至少填写一项关键信息：[ 昵称 | ID | 密码 | 邮箱 | 手机 ]"),
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
        // 脏检查
        bool hasChanged =
            _platformController.text != acc.platform ||
            _nameController.text != acc.name ||
            _urlController.text != acc.url ||
            _userIdController.text != acc.userId ||
            _emailController.text != acc.email ||
            _pswdController.text != acc.pswd ||
            _phoneController.text != acc.phone ||
            _birthController.text !=
                (acc.birth == null
                    ? ""
                    : DateFormat('yyyy-MM-dd').format(acc.birth!)) ||
            _notesController.text != (acc.notes ?? "") ||
            _signupDateController.text !=
                (acc.signupDate == null
                    ? ""
                    : DateFormat('yyyy-MM-dd').format(acc.signupDate!)) ||
            _currentStatus != acc.status ||
            _currentRealName != acc.realName ||
            !listEquals(_tempTags, acc.tags);
        if (!hasChanged) {
          setState(() => _isEditing = false);
          debugPrint("account changed flag: $hasChanged");
          return;
        }
        // 有变动 执行更新
        final updated = Account(
          id: acc.id, // 保持ID
          platform: _platformController.text,
          name: _nameController.text,
          url: _urlController.text,
          status: _currentStatus,
          userId: _userIdController.text,
          email: _emailController.text,
          pswd: _pswdController.text,
          phone: _phoneController.text,
          birth: _birthController.text.isEmpty
              ? null
              : DateTime.tryParse(_birthController.text),
          notes: _notesController.text,
          signupDate: _signupDateController.text.isEmpty
              ? null
              : DateTime.tryParse(_signupDateController.text),
          realName: _currentRealName,
          tags: _tempTags,
          lastModified: DateTime.now().toIso8601String(),
        );
        await StorageService().insertAccount(updated);
        await refreshAccountList();
        if (!mounted) return;
        MessageUtil.show(context, "修改已保存");
        setState(() => _isEditing = false);
      }
    } else {
      setState(() => _isEditing = true); // 切换到编辑状态
    }
  }

  // 构建详情面板顶部的平台大图标/占位符
  Widget _buildLargeLogo(Account account) {
    final Color color = _getStatusColor(account.status);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        // 背景色采用状态色的极浅透明版本
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Center(
        child: Text(
          account.platform.isNotEmpty ? account.platform[0].toUpperCase() : "?",
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // 构建卡片左侧的平台小图标/占位符
  Widget _buildSmallLogo(Account acc, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          acc.platform[0].toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // 构建账户卡片组件
  Widget _buildAccountCard(Account acc, int index) {
    bool isSelected = _selectedAccountId == acc.id;
    bool isPasswordVisible = _visiblePasswordIds.contains(acc.id);
    Color statusColor = _getStatusColor(acc.status);
    // c1-副标题: 昵称/ID
    String firstColSub = acc.name.isNotEmpty
        ? acc.name
        : (acc.userId.isNotEmpty ? acc.userId : "-");
    // c2-内容: 邮箱/手机
    IconData secondColIcon = Icons.alternate_email;
    String secondColText = "-";
    Color secondColColor = Colors.grey[300]!;
    // 决定第1/2列显示什么属性
    if (acc.email.isNotEmpty) {
      secondColIcon = Icons.email_outlined;
      secondColText = acc.email;
      secondColColor = Colors.black54;
    } else if (acc.phone.isNotEmpty) {
      secondColIcon = Icons.phone_android_rounded; // 补全手机图标
      secondColText = acc.phone;
      secondColColor = Colors.black54;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _onAccountSelected(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60, // 单个条目行高
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.blue.withValues(alpha: 0.5)
                  : Colors.black12,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Row(
              children: [
                // 状态线
                Container(width: 5, color: statusColor),
                const SizedBox(width: 12),
                // 平台Logo
                _buildSmallLogo(acc, statusColor),
                const SizedBox(width: 16),
                // c1: 平台与昵称(固定比例)
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acc.platform,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        firstColSub,
                        style: TextStyle(
                          fontSize: 11,
                          color: firstColSub == "-"
                              ? Colors.grey[300]
                              : Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // c2: 账号/邮箱(固定比例，始终存在)
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Icon(
                        secondColIcon,
                        size: 14,
                        color: secondColText == "-"
                            ? Colors.transparent
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          secondColText,
                          style: TextStyle(fontSize: 13, color: secondColColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // c3: 标签区(固定宽度140，始终存在)
                SizedBox(
                  width: 105,
                  child: acc.tags.isEmpty
                      ? const SizedBox.shrink()
                      : Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: acc.tags
                              .take(2)
                              .map(
                                (t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    t,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                // c4: 密码与快捷操作
                SizedBox(
                  width: 180, // 固定右侧操作区宽度
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          isPasswordVisible ? acc.pswd : "••••••••",
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis, // 超出长度省略
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            color: isPasswordVisible
                                ? Colors.blue
                                : Colors.grey[400],
                            fontSize: 14,
                            letterSpacing: isPasswordVisible ? 0.5 : 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => setState(() {
                          isPasswordVisible
                              ? _visiblePasswordIds.remove(acc.id)
                              : _visiblePasswordIds.add(acc.id);
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: acc.pswd));
                          MessageUtil.show(context, "密码已复制");
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建详情页面板
  Widget _buildDetailPanel(Account account) {
    return Column(
      children: [
        _buildDetailHeader(account), // 头部
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey, // 用于保存时的必填校验
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 分组1: 核心凭据
                _buildEditableInfoRow("用户昵称", _nameController),
                _buildEditableInfoRow("登录账号", _userIdController),
                _buildEditableInfoRow("绑定邮箱", _emailController),
                _buildEditableInfoRow(
                  "绑定手机",
                  _phoneController,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                _buildEditablePasswordRow(account), // 密码行
                const Divider(),
                // 分组2: 平台与标记
                _buildEditableUrlRow(), // 网址展示/编辑
                _buildEditableTagsRow(), // 标签编辑器
                const Divider(),
                // 分组3: 辅助信息
                _buildEditableInfoRow(
                  "生日",
                  _birthController,
                  isDateField: true,
                ),
                _buildEditableRealNameRow(), // 实名勾选/展示
                _buildEditableInfoRow(
                  "注册日期",
                  _signupDateController,
                  isDateField: true,
                ),
                _buildEditableInfoRow("备注", _notesController, maxLines: 5),
                _buildInfoRow("最后修改于", DateUtil.format(account.lastModified)),
                const SizedBox(height: 32),
                // 按钮操作区
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(account),
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    "删除此条目",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 构建信息展示行
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

  // 构建可编辑信息展示行
  Widget _buildEditableInfoRow(
    String label,
    TextEditingController controller, {
    bool isPassword = false,
    bool isDateField = false,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final bool isMasked =
        isPassword && !_visiblePasswordIds.contains(_selectedAccountId!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          if (!_isEditing) // 只读状态
            Container(
              height: 24, // 统一高度
              alignment: Alignment.centerLeft,
              child: Text(
                isMasked
                    ? "••••••••"
                    : (controller.text.isEmpty ? "-" : controller.text),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            SizedBox(
              height: 24, // 保持与只读模式高度绝对一致
              child: TextFormField(
                controller: controller,
                maxLines: 1, // 备注字段如果需要多行，单独处理
                inputFormatters: inputFormatters,
                obscureText: isMasked,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero, // 彻底消除内边距
                  border: InputBorder.none, // 编辑时也隐藏下划线，保持清爽
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 1),
                  ), // 仅在聚焦时显示下划线
                  suffixIcon: isDateField
                      ? IconButton(
                          icon: Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.blue,
                          ),
                          onPressed: () => _pickDate(context, controller),
                          padding: EdgeInsets.zero,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 构建带跳转功能的展示行
  Widget _buildInfoRowWithLink(String label, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          InkWell(
            onTap: url.isEmpty ? null : () => launchUrl(Uri.parse(url)),
            child: Text(
              url.isEmpty ? "未填写" : url,
              style: TextStyle(
                fontSize: 14,
                color: url.isEmpty ? Colors.black87 : Colors.blue,
                decoration: url.isEmpty ? null : TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建密码切换行
  Widget _buildEditablePasswordRow(Account acc) {
    bool isVisible = _visiblePasswordIds.contains(acc.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("密码", style: TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _isEditing
                    ? TextFormField(
                        controller: _pswdController,
                        // 当眼睛闭着时，输入框也应该是遮蔽状态
                        obscureText: !isVisible,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'Consolas',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      )
                    : Text(
                        isVisible ? _pswdController.text : "••••••••",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Consolas',
                        ),
                      ),
              ),
              // 眼睛图标无论是否处于编辑模式都应允许切换可见性
              IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    if (isVisible) {
                      _visiblePasswordIds.remove(acc.id);
                    } else {
                      _visiblePasswordIds.add(acc.id);
                    }
                  });
                },
              ),
              // 根据_isEditing状态切换组件
              if (!_isEditing) // 复制按钮仅在非编辑模式下显示
                IconButton(
                  icon: const Icon(
                    Icons.copy_all_rounded,
                    size: 18,
                    color: Colors.blueGrey,
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _pswdController.text),
                    );
                    MessageUtil.show(context, "密码已复制");
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 构建可编辑url展示行
  Widget _buildEditableUrlRow() {
    return _isEditing
        ? _buildEditableInfoRow("网址", _urlController)
        : _buildInfoRowWithLink("网址", _urlController.text);
  }

  // 构建可编辑标签行
  Widget _buildEditableTagsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "标签 (回车切分)",
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
        const SizedBox(height: 8),
        // 标签展示与输入区
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isEditing
                ? Colors.grey.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isEditing
                ? Border.all(color: Colors.blue.withValues(alpha: 0.3))
                : null,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 已有的标签Chip
              ..._tempTags.map(
                (tag) => InputChip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  shape: const StadiumBorder(),
                  onDeleted: _isEditing
                      ? () => setState(() => _tempTags.remove(tag))
                      : null,
                  onPressed: !_isEditing
                      ? () {
                          // 只读模式：点击标签直接搜索
                          _searchController.text = tag;
                          _filterAccounts(tag);
                          _closePanel();
                        }
                      : null,
                  deleteIcon: const Icon(Icons.cancel, size: 14),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              // 编辑模式下的实时输入框
              if (_isEditing)
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _tagsController,
                    autofocus: false,
                    decoration: const InputDecoration(
                      hintText: "新标签...",
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: const TextStyle(fontSize: 13),
                    // 回车或输入逗号/空格时触发切分
                    onSubmitted: (val) => _addNewTag(val),
                    onChanged: (val) {
                      // 这里可以实现即时的下拉建议 UI
                    },
                  ),
                ),
            ],
          ),
        ),
        // 编辑模式下的智能建议区
        if (_isEditing && _tagsController.text.isNotEmpty)
          _buildTagSuggestions(),
      ],
    );
  }

  // 添加新标签并查重
  void _addNewTag(String val, {int maxChars = 6}) {
    final cleanTag = val.trim();
    if (cleanTag.length > maxChars) {
      MessageUtil.show(context, "标签长度不能超过 $maxChars 个字");
      return;
    }
    if (cleanTag.isNotEmpty && !_tempTags.contains(cleanTag)) {
      setState(() {
        _tempTags.add(cleanTag);
        _tagsController.clear();
      });
    }
  }

  // 辅助组件：显示智能建议
  Widget _buildTagSuggestions() {
    final suggestions = _globalTags
        .where(
          (t) =>
              t.toLowerCase().contains(_tagsController.text.toLowerCase()) &&
              !_tempTags.contains(t),
        )
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: suggestions
            .take(5)
            .map(
              (s) => ActionChip(
                label: Text(
                  s,
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                ),
                onPressed: () => _addNewTag(s),
                backgroundColor: Colors.blue.withValues(alpha: 0.05),
              ),
            )
            .toList(),
      ),
    );
  }

  // 构建实名标记行
  Widget _buildEditableRealNameRow() {
    if (!_isEditing) {
      return _buildInfoRow("实名标记", _currentRealName ? "已实名" : "未实名");
    }
    return CheckboxListTile(
      title: const Text("实名标记", style: TextStyle(fontSize: 14)),
      value: _currentRealName,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) => setState(() => _currentRealName = v ?? false),
    );
  }

  // 构建表格中的彩色状态标签
  Widget _buildStatusChip(int status) {
    Color color;
    switch (status) {
      case 1:
        color = Colors.green;
        break;
      case 2:
        color = Colors.grey;
        break;
      case 3:
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _getStatusText(status),
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }

  // 将数字状态码转换为易读文字
  String _getStatusText(int status) {
    const map = {0: "未注册", 1: "使用中", 2: "已注销", 3: "无法使用"};
    return map[status] ?? "未知";
  }

  // 获取状态对应的颜色
  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.green.shade400; // 使用中
      case 0:
        return Colors.amber.shade400; // 未注册
      case 2:
        return Colors.grey.shade400; // 已注销
      case 3:
        return Colors.red.shade400; // 无法使用
      default:
        return Colors.blue.shade400;
    }
  }

  // 日历选择器
  Future<void> _pickDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    // 日历初始的选中日期
    DateTime initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
    // 调用官方日期选择器
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900), // 最早可选
      lastDate: DateTime(2100), // 最晚可选
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    // 如果用户选了日期且组件还挂载着
    if (picked != null && mounted) {
      setState(() {
        // 格式化为yyyy-MM-dd
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
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
            const Text("如果您忘记了主密码，这是找回数据的唯一方法，请务必妥善保存。"),
            const SizedBox(height: 20),
            SelectableText(
              rk,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: ['Microsoft YaHei'],
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
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
              // 成功后刷新状态
              await _checkDbStatus();
              await refreshAccountList();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("恢复密钥已复制至剪切板，保险箱已就绪")),
                );
              }
            },
            child: const Text("复制恢复密钥"),
          ),
        ],
      ),
    );
  }
}
