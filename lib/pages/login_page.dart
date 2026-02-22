/*
 * @Author: Thoma4
 * @Date: 2026-02-22 19:47:45
 * @LastEditTime: 2026-02-22 20:28:40
 * @Description: 初始登入界面
 */

import 'package:flutter/material.dart';

import '../main.dart'; // 用于跳转到 MainShell

// 情况 A：老用户解锁界面
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final TextEditingController _passwordController = TextEditingController();

  void _unlock() {
    // TODO: 调用加密模块验证密码
    // 目前暂时直接通过
    if (_passwordController.text.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainShell()),
      );
    }
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
            ],
          ),
        ),
      ),
    );
  }
}

// 情况 B：新用户欢迎界面
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              "欢迎使用 Vault Keeper",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // TODO: 跳转到创建主密码页面
              },
              style: ElevatedButton.styleFrom(fixedSize: const Size(200, 50)),
              child: const Text("创建新数据库"),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                // TODO: 跳转到云端恢复页面 (WebDAV)
              },
              style: OutlinedButton.styleFrom(fixedSize: const Size(200, 50)),
              child: const Text("从云端恢复备份"),
            ),
          ],
        ),
      ),
    );
  }
}
