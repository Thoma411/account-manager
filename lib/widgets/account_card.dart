/*
 * @Author: Thoma4
 * @Date: 2026-06-24 22:26:04
 * @LastEditTime: 2026-06-25 23:17:42
 * @Description: 账户卡片
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/account.dart';
import '../services/icon_service.dart';
import '../services/settings_service.dart';
import 'account_ui_utils.dart';

class AccountCard extends StatefulWidget {
  final Account account;
  final bool isSelected;
  final bool isPasswordVisible;
  final String iconDirPath;
  final VoidCallback onTap;
  final VoidCallback onTogglePassword; // 点击眼睛图标回调
  final VoidCallback onCopyPassword;
  final bool isMobile;

  const AccountCard({
    super.key,
    required this.account,
    required this.isSelected,
    required this.isPasswordVisible,
    required this.iconDirPath,
    required this.onTap,
    required this.onTogglePassword,
    required this.onCopyPassword,
    this.isMobile = false, // 默认不是手机模式
  });

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  // 构建卡片左侧的平台小图标/占位符
  Widget _buildSmallLogo(Account acc, Color color) {
    final String iconPath = p.join(widget.iconDirPath, "${acc.id}.png");
    final File iconFile = File(iconPath);
    // 本地文件已存在，直接渲染图片
    if (iconFile.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          iconFile,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              AccountUiUtils.buildPlaceholder(acc.platform, color, 40, 18, 8),
        ),
      );
    }
    final bool isAutoFetchEnabled =
        SettingsService().get('auto_fetch_icons') == 'true';
    // 用户允许抓取时，有网址&本地不存在&并非正在被删除，发起后台静默抓取
    if (isAutoFetchEnabled && acc.url.isNotEmpty) {
      IconService().fetchAndCacheIcon(acc.id, acc.url).then((_) {
        if (mounted) setState(() {}); // 抓取成功后刷新UI
      });
    }
    // 抓取期间/无网址时显示首字母占位符
    return AccountUiUtils.buildPlaceholder(acc.platform, color, 40, 18, 8);
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.account;
    final bool isSelected = widget.isSelected;
    final bool isPasswordVisible = widget.isPasswordVisible;
    Color statusColor = AccountUiUtils.getStatusColor(acc.status);
    // c1-副标题: 昵称/ID
    String firstColSub = acc.name.isNotEmpty
        ? acc.name
        : (acc.userId.isNotEmpty ? acc.userId : "-");
    // c2-内容: 邮箱/手机
    IconData secondColIcon = Icons.alternate_email;
    String secondColText = "-";
    Color secondColColor = Theme.of(context).colorScheme.onSurfaceVariant;
    // 决定第1/2列显示什么属性
    if (acc.email.isNotEmpty) {
      secondColIcon = Icons.email_outlined;
      secondColText = acc.email;
    } else if (acc.phone.isNotEmpty) {
      secondColIcon = Icons.phone_android_rounded; // 补全手机图标
      secondColText = acc.phone;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60, // 单个条目行高
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Row(
              children: widget.isMobile
                  ? [
                      Container(width: 5, color: statusColor), // 状态指示线
                      const SizedBox(width: 12),
                      _buildSmallLogo(acc, statusColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          acc.platform,
                          style: const TextStyle(
                            fontSize: 15.5, // 平台名字号
                            fontWeight: FontWeight.bold, // 粗体
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                    ]
                  : [
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
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                secondColText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: secondColColor,
                                ),
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondaryContainer
                                              .withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          t,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSecondaryContainer,
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
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.5),
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
                              onPressed: widget.onTogglePassword,
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: acc.pswd),
                                );
                                widget.onCopyPassword();
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
}
