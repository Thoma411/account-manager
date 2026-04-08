/*
 * @Author: Thoma4
 * @Date: 2026-02-22 19:47:45
 * @LastEditTime: 2026-04-08 18:57:14
 * @Description: 初始登入界面
 */

import 'package:flutter/material.dart';

import '../pages/shell_page.dart'; // 用于跳转到 MainShell
import '../services/auth_service.dart';

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
