/*
 * @Author: Thoma4
 * @Date: 2026-02-22 19:47:45
 * @LastEditTime: 2026-06-04 18:11:58
 * @Description: 初始登入界面
 */

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../pages/shell_page.dart'; // 用于跳转到 MainShell
import '../services/auth_service.dart';
import '../services/security_service.dart';
import '../services/storage_service.dart';
import '../utils/utils.dart';

// 老用户解锁界面
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final TextEditingController _passwordController = TextEditingController();

  void _unlock() async {
    // 调用验证逻辑
    bool success = await AuthService().verifyPassword(_passwordController.text);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ShellPage()),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("密码错误，请重试")));
    }
  }

  // 弹出输入恢复密钥(RK)的对话框
  void _showForgotPasswordDialog() {
    final rkController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重置主密码"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "请输入您事先保存的恢复密钥 (RK)：",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: rkController,
              decoration: const InputDecoration(
                labelText: "恢复密钥",
                hintText: "一串 Base64 编码的字符",
              ),
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
              final rkInput = rkController.text.trim();
              if (rkInput.isEmpty) return;

              final sec = SecurityService();
              final storage = StorageService();
              try {
                // 读取EDK_R(用RK锁住的DK)
                String? edkR = await storage.getMetadata('edk_r');
                if (edkR == null) throw "数据损坏：未找到恢复原语";
                // 尝试用输入的RK作为Key去解密EDK_R还原出DK
                final rawRkBytes = base64.decode(rkInput);
                final dkString = sec.decrypt(edkR, enc.Key(rawRkBytes));
                final dk = enc.Key(base64.decode(dkString));
                // 验证通过，先将解开的DK放入内存，否则后续无法加密新密码
                sec.setDK(dk);
                if (!context.mounted) return;
                Navigator.pop(context); // 关闭RK输入框
                _showResetPasswordDialog(); // 弹出重置密码对话框
              } catch (e) {
                if (!context.mounted) return;
                MessageUtil.show(context, "密钥验证失败，请检查输入是否正确");
              }
            },
            child: const Text("验证密钥"),
          ),
        ],
      ),
    );
  }

  // 成功验证RK后的重置密码对话框
  void _showResetPasswordDialog() {
    final newPwController = TextEditingController();
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("设置新主密码"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("密钥验证成功！请立即设置新的主密码：", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: newPwController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "新主密码"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "确认新主密码"),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (newPwController.text != confirmController.text ||
                  newPwController.text.length < 6) {
                MessageUtil.show(context, "密码不一致或长度不足6位");
                return;
              }
              final sec = SecurityService();
              final storage = StorageService();
              final dk = sec.currentDataKey; // 此时内存中已有刚才解开的DK
              try {
                // 重新包装逻辑：生成新盐值->新MK->锁住旧DK
                final newSalt = sec.generateRandomBytes(32);
                final newMk = sec.deriveMasterKey(
                  newPwController.text,
                  newSalt,
                );
                final dkBase64 = base64.encode(dk!.bytes);
                final newEdkM = sec.encrypt(dkBase64, newMk);
                // 持久化覆盖
                await storage.saveMetadata(
                  'master_salt',
                  base64.encode(newSalt),
                );
                await storage.saveMetadata('edk_m', newEdkM);

                final newRk = await sec.rotateRecoveryKey(); // 重置RK

                if (!context.mounted) return;
                Navigator.pop(context);
                _showNewRKNotice(newRk); // 弹出新RK展示框
              } catch (e) {
                if (mounted) MessageUtil.show(context, "重置失败：$e");
              }
            },
            child: const Text("生成新的恢复密钥"),
          ),
        ],
      ),
    );
  }

  // 重置完密码后的新RK展示框
  void _showNewRKNotice(String newRk) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("请保存新的恢复密钥"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("如果您忘记了主密码，这是找回数据的唯一方法，请务必妥善保存。"),
            const SizedBox(height: 20),
            SelectableText(
              newRk,
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
              await Clipboard.setData(ClipboardData(text: newRk));
              if (!context.mounted) return;
              Navigator.pop(context); // 关闭展示框
              // 此时才正式进入主界面
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const ShellPage()),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("恢复密钥已复制至剪切板，保险箱已就绪")),
              );
            },
            child: const Text("复制恢复密钥"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                "身份验证",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text("请输入主密码以解锁数据库", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "主密码",
                  prefixIcon: Icon(Icons.password),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _unlock,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("解锁"),
              ),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: const Text(
                  "忘记主密码？",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
