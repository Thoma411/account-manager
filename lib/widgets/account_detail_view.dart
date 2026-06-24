/*
 * @Author: Thoma4
 * @Date: 2026-06-24 23:04:48
 * @LastEditTime: 2026-06-25 00:38:53
 * @Description: 
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../services/storage_service.dart';
import '../utils/utils.dart';
import 'account_ui_utils.dart';

class AccountDetailView extends StatefulWidget {
  final Account account;
  final String iconDirPath;
  final Set<String> globalTags;
  final VoidCallback onClose;
  final VoidCallback onSaveSuccess; // 数据保存成功回调
  final VoidCallback onDeleteSuccess; // 数据删除成功回调
  final ValueChanged<String>? onTagClicked;

  const AccountDetailView({
    super.key,
    required this.account,
    required this.iconDirPath,
    required this.globalTags,
    required this.onClose,
    required this.onSaveSuccess,
    required this.onDeleteSuccess,
    required this.onTagClicked,
  });

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
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
  bool _isEditing = false; // 是否正在编辑

  int _currentStatus = 1;
  bool _currentRealName = false;
  bool _isPasswordVisible = false;

  List<String> _tempTags = []; // 临时标签集

  @override
  void initState() {
    super.initState();
    // 物理实例化
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
    // 监听标签输入
    _tagsController.addListener(() {
      if (_isEditing) setState(() {});
    });
    _initFields(widget.account);
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
    super.dispose();
  }

  // 电脑端切换卡片时重新刷入新账号数据
  @override
  void didUpdateWidget(covariant AccountDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果切换了不同的账户条目，重新刷入新表单控制器数据
    if (oldWidget.account.id != widget.account.id) {
      _initFields(widget.account);
    }
  }

  // 初始化控制器&变量
  void _initFields(Account acc) {
    _isEditing = false; // 切换或重载时重置为只读
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
    _currentStatus = acc.status;
    _currentRealName = acc.realName;
    _tempTags = List.from(acc.tags);
  }

  // 构建详情面板的顶部区域
  Widget _buildDetailHeader(Account account) {
    final Color statusColor = AccountUiUtils.getStatusColor(_currentStatus);
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
                  AccountUiUtils.buildStatusChip(_currentStatus),
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
              color: Theme.of(context).colorScheme.primary,
            ), // 编辑/保存切换按钮
            tooltip: _isEditing ? "保存修改" : "编辑信息",
          ),
          // 右侧关闭按钮
          IconButton(
            onPressed: widget.onClose, // 调用State类中的关闭方法
            icon: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: "关闭面板",
          ),
        ],
      ),
    );
  }

  // 构建详情面板顶部的平台大图标/占位符
  Widget _buildLargeLogo(Account account) {
    final Color color = AccountUiUtils.getStatusColor(account.status);
    final String iconPath = p.join(widget.iconDirPath, "${account.id}.png");
    final File iconFile = File(iconPath);
    // 本地文件已存在，直接渲染图片
    if (iconFile.existsSync()) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(
            iconFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                AccountUiUtils.buildPlaceholder(
                  account.platform,
                  color,
                  64,
                  28,
                  16,
                ),
          ),
        ),
      );
    }
    // 抓取期间/无网址时显示首字母占位符
    return AccountUiUtils.buildPlaceholder(account.platform, color, 64, 28, 16);
  }

  // 构建信息展示行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
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
    bool isDateField = false,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          if (!_isEditing) // 只读状态
            Container(
              height: 24, // 统一高度
              alignment: Alignment.centerLeft,
              child: Text(
                controller.text.isEmpty ? "-" : controller.text,
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero, // 彻底消除内边距
                  border: InputBorder.none, // 编辑时也隐藏下划线，保持清爽
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1,
                    ),
                  ), // 仅在聚焦时显示下划线
                  suffixIcon: isDateField
                      ? IconButton(
                          icon: Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
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
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          InkWell(
            onTap: url.isEmpty ? null : () => launchUrl(Uri.parse(url)),
            child: Text(
              url.isEmpty ? "-" : url,
              style: TextStyle(
                fontSize: 14,
                color: url.isEmpty
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.primary,
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
    bool isVisible = _isPasswordVisible;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "密码",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
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
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
              // 根据_isEditing状态切换组件
              if (!_isEditing) // 复制按钮仅在非编辑模式下显示
                IconButton(
                  icon: Icon(
                    Icons.copy_all_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  // 构建可编辑标签行
  Widget _buildEditableTagsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "标签 (回车切分)",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        // 标签展示与输入区
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isEditing
                ? Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isEditing
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                  )
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
                          widget.onTagClicked?.call(tag); // 只读模式下点击标签直接搜索
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

  // 显示标签智能建议
  Widget _buildTagSuggestions() {
    final suggestions = widget.globalTags
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onPressed: () => _addNewTag(s),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.05),
              ),
            )
            .toList(),
      ),
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
        final acc = widget.account;
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
        if (!mounted) return;
        widget.onSaveSuccess(); // 通知大列表重载数据
        MessageUtil.show(context, "修改已保存");
        setState(() => _isEditing = false);
      }
    } else {
      setState(() => _isEditing = true); // 切换到编辑状态
    }
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
                widget.onDeleteSuccess();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("条目已成功删除")));
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text("确定删除"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildDetailHeader(widget.account), // 头部
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
                _buildEditablePasswordRow(widget.account), // 密码行
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
                _buildInfoRow(
                  "最后修改于",
                  DateUtil.format(widget.account.lastModified),
                ),
                const SizedBox(height: 32),
                // 按钮操作区
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(widget.account),
                  icon: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    "删除此条目",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
}
