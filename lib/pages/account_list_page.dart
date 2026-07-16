/*
 * @Author: Thoma4
 * @Date: 2026-02-12 22:00:56
 * @LastEditTime: 2026-07-16 16:14:19
 * @Description: 账户信息页(查看页)
 */

import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webdav_client/webdav_client.dart' as dav;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../widgets/account_ui_utils.dart';
import '../widgets/alphabet_indexer.dart';
import '../widgets/account_card.dart';
import '../widgets/account_detail_view.dart';
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

  String _iconDirPath = ""; // 缓存路径字符串

  // 排序依据
  String _sortBy = 'platform'; // platform/last_modified
  bool _isAscending = true; // 默认升序
  // 字母索引导航栏
  final Map<String, int> _alphabetIndexMap = {}; // 存储{字母:Index}
  final ScrollController _scrollController = ScrollController(); // 控制跳转

  // 增加初始化逻辑，进入页面即拉取数据库
  @override
  void initState() {
    super.initState();
    // 排序依据
    _sortBy = _settings.get('sort_by', defaultValue: 'platform')!;
    _isAscending =
        _settings.get('sort_ascending', defaultValue: 'true') == 'true';
    _prepareIconPath();
    _checkDbStatus();
    refreshAccountList();
  }

  // 释放资源防止内存泄露
  @override
  void dispose() {
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

  // 目录路径预取
  Future<void> _prepareIconPath() async {
    final directory = await getApplicationSupportDirectory();
    setState(() {
      _iconDirPath = p.join(directory.path, 'vault_icons');
    });
  }

  // 搜索栏过滤逻辑
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
          cmp = a.platformPinyin.compareTo(b.platformPinyin); // 比较拼音字符串
          // 拼音完全一样则比较原始字符串
          if (cmp == 0) cmp = a.platform.compareTo(b.platform);
        } else {
          cmp = a.lastModified.compareTo(b.lastModified);
        }
        return _isAscending ? cmp : -cmp;
      });
      // 字母索引导航栏
      _alphabetIndexMap.clear();
      for (int i = 0; i < results.length; i++) {
        String char = results[i].firstLetter;
        // 记录该字母首次出现的位置
        if (!_alphabetIndexMap.containsKey(char)) _alphabetIndexMap[char] = i;
      }
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

  // 点击账户卡片时触发
  void _onAccountSelected(int index) {
    final acc = _displayAccounts[index];
    // 动态感知屏幕宽度
    final bool isMobile = AccountUiUtils.isMobile(context);

    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: AccountDetailView(
                account: acc,
                iconDirPath: _iconDirPath,
                globalTags: _globalTags,
                onClose: () => Navigator.of(context).pop(), // 返回: Pop路由
                onSaveSuccess: () => refreshAccountList(),
                onDeleteSuccess: () {
                  refreshAccountList();
                  Navigator.of(context).pop();
                },
                onTagClicked: (tag) {
                  _searchController.text = tag;
                  _filterAccounts(tag);
                  Navigator.of(context).pop(); // 返回列表页检索
                },
              ),
            ),
          ),
        ),
      );
    } else {
      setState(() {
        _selectedAccountId = acc.id; // 记录被选中的账户ID
        _isPanelOpen = true; // 展开右侧面板
      });
    }
  }

  // 收起右侧详情页
  void _closePanel() {
    setState(() {
      _isPanelOpen = false;
    });
  }

  // 弹出新增账户对话框
  void showAddAccountDialog() async {
    if (_allAccounts.length >= 4096) {
      _showGuardDialog("这么能存？", "账户数量已达上限。");
      return;
    }
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
                      refreshAccountList();
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

  // 字母索引导航栏跳转逻辑
  void _jumpToSection(String char) {
    // 检查控制器是否已绑定到活跃的ScrollView
    if (!_scrollController.hasClients) {
      debugPrint("ScrollController 尚未绑定到 ListView");
      return;
    }
    final int? index = _alphabetIndexMap[char];
    if (index != null) {
      final double targetOffset = index * 68.0; // 计算位置(假设itemExtent为68.0)
      // 3检查目标位置是否合法(不超出最大滚动范围)
      final maxScroll = _scrollController.position.maxScrollExtent;
      final finalOffset = targetOffset > maxScroll ? maxScroll : targetOffset;
      _scrollController.jumpTo(finalOffset);
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
        content: SingleChildScrollView(
          child: Column(
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
        content: SingleChildScrollView(
          child: Column(
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

                String newEtag = await webdav.downloadVault(); // 下载并获取云端etag
                await _settings.set('last_synced_etag', newEtag); // 立即保存etag
                await _settings.set('need_revision_alignment', 'true'); // 设置哨兵

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
            Expanded(child: Text("请保存您的恢复密钥")),
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

  // 构建空库UI界面
  Widget _buildEmptyStateUI(bool isMobile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            "欢迎使用 Vault Keeper",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _isDbCreated ? "空空如也？请前往设置导入或点击'+'号添加账户" : "尚未初始化数据库，请选择操作以开始使用",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),

          // 本地无库显示两个按钮
          if (!_isDbCreated)
            isMobile
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showSetupMasterPasswordDialog,
                        icon: const Icon(Icons.add_moderator),
                        label: const Text("创建新数据库"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(200, 50),
                        ),
                      ),
                      const SizedBox(height: 16), // 垂直间距
                      OutlinedButton.icon(
                        onPressed: _showRestoreFromCloudDialog,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text("从云端恢复备份"),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(200, 50),
                        ),
                      ),
                    ],
                  )
                : Row(
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
        textAlignVertical: TextAlignVertical.center,
        onChanged: (value) => _filterAccounts(value), // 输入变化时即时过滤
        onSubmitted: (value) => _pageFocusNode.requestFocus(), // 将焦点归还页面
        decoration: InputDecoration(
          hintText: "搜索账户",
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
      icon: Icon(
        Icons.sort_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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

  @override
  Widget build(BuildContext context) {
    // 动态感知屏幕宽度
    final bool isMobile = AccountUiUtils.isMobile(context);

    const double panelWidth = 400; // 定义详情页宽度
    const double headerHeight = 70.0; // 搜索框高度
    const double listTopGap = 3.0; // 搜索框与卡片列表的间距

    // 字母索引导航栏
    final Widget indexerWidget = Padding(
      padding: const EdgeInsets.only(top: listTopGap),
      child: AlphabetIndexer(
        alphabetIndexMap: _alphabetIndexMap,
        onLetterSelected: _jumpToSection,
        alignRight: false,
      ),
    );
    // 账户卡片列表
    final Widget listWidget = Expanded(
      child: RefreshIndicator(
        onRefresh: refreshAccountList, // 下拉刷新回调
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: listTopGap, bottom: 8),
          itemCount: _displayAccounts.length,
          itemExtent: 68.0, // Container高度60 + 上下边距4*2
          itemBuilder: (context, index) {
            final acc = _displayAccounts[index];
            return AccountCard(
              account: acc,
              isSelected: _selectedAccountId == acc.id,
              isPasswordVisible: _visiblePasswordIds.contains(acc.id),
              iconDirPath: _iconDirPath,
              onTap: () => _onAccountSelected(index),
              onTogglePassword: () {
                setState(() {
                  _visiblePasswordIds.contains(acc.id)
                      ? _visiblePasswordIds.remove(acc.id)
                      : _visiblePasswordIds.add(acc.id);
                });
              },
              onCopyPassword: () {
                MessageUtil.show(context, "密码已复制");
              },
              isMobile: isMobile,
            );
          },
        ),
      ),
    );

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
                Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const SizedBox(height: headerHeight),
                          Expanded(
                            child: (!_isDbCreated || _allAccounts.isEmpty)
                                ? _buildEmptyStateUI(isMobile) // 未建库/内容为空时显示引导
                                : Row(
                                    children: isMobile
                                        ? [listWidget, indexerWidget]
                                        : [indexerWidget, listWidget],
                                  ), // 手机端字母索引在右侧
                          ),
                          // 底栏
                          Container(
                            height: 25,
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border(
                                top: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                  width: 0.6,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "共计 ${_displayAccounts.length} 条账户",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 20), // 右边距
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 搜索栏区域
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: headerHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface, // 设置背景色
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              offset: const Offset(0, 3), // 阴影偏移
                              blurRadius: 8, // 模糊半径
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildSearchBox()),
                            if (isMobile)
                              IconButton(
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: "新增账户",
                                onPressed: showAddAccountDialog,
                              ),
                            _buildSortButton(), // 排序依据按钮
                            const SizedBox(width: 16),
                          ],
                        ),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.2),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(-5, 0),
                          ),
                        ],
                      ),
                      // 未选中任何行则面板内容显示为空，防止报错
                      child: (_isPanelOpen && _selectedAccountId != null)
                          ? (() {
                              if (_allAccounts.isEmpty) {
                                return const SizedBox.shrink();
                              } // 全列表为空，安全返回空
                              // 在当前显示的列表中找相应ID匹配的账户对象
                              final account = _allAccounts.firstWhere(
                                (acc) => acc.id == _selectedAccountId,
                                orElse: () =>
                                    _allAccounts.first, // 没找到则回退到全库第一条
                              );
                              return AccountDetailView(
                                account: account,
                                iconDirPath: _iconDirPath,
                                globalTags: _globalTags,
                                onClose: _closePanel,
                                onSaveSuccess: () async {
                                  // 就地编辑保存成功后仅刷新列表
                                  await refreshAccountList();
                                },
                                onDeleteSuccess: () async {
                                  // 删除成功后，关闭面板、重置状态、刷新列表
                                  setState(() {
                                    _selectedAccountId = null;
                                    _isPanelOpen = false;
                                  });
                                  await refreshAccountList();
                                },
                                onTagClicked: (tag) {
                                  //点击tag后，在搜索栏中填充tag、执行搜索过滤、关闭详情页
                                  _searchController.text = tag;
                                  _filterAccounts(tag);
                                  _closePanel();
                                },
                              );
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
}
