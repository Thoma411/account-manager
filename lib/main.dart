/*
 * @Author: Thoma4
 * @Date: 2026-02-09 23:51:46
 * @LastEditTime: 2026-04-08 21:00:07
 * @Description: main
 */

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'pages/shell_page.dart';
import 'services/storage_service.dart';

void main() async {
  // 1. 确保 Flutter 引擎绑定
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 必须：先初始化 SQLite FFI 引擎，否则第 4 步会报错
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 3. 初始化窗口管理器
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    minimumSize: Size(800, 600),
    center: true,
    title: "Vault Keeper",
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  // 这里不用 await，让它异步执行显示过程
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 4. 探测本地数据库是否存在
  // 注意：这里调用的是我们即将在 StorageService 中添加的方法
  final bool oldUser = await StorageService().isDatabaseExists();

  // 5. 运行应用并传递状态
  runApp(VaultApp(isOldUser: oldUser));
}

class VaultApp extends StatelessWidget {
  final bool isOldUser;
  const VaultApp({super.key, required this.isOldUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),

        fontFamily: 'Segoe UI', //设置主字体
        // 遇到中文字符时按顺序寻找以下字体
        fontFamilyFallback: const [
          'Microsoft YaHei', // Windows 默认中文
          'PingFang SC', // iOS/macOS 默认中文
          'Hiragino Sans GB',
          'sans-serif',
        ],
        // 增强文本渲染清晰度（针对 Windows）
        typography: Typography.material2021(platform: TargetPlatform.windows),
        textTheme: const TextTheme(
          // 详情页的标签（如“平台名称”）使用较小、浅色的样式
          labelSmall: TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
          // 主要正文（如账号内容）
          bodyMedium: TextStyle(
            fontSize: 14,
            letterSpacing: 0.2,
            color: Colors.black87,
          ),
        ),

        dataTableTheme: DataTableThemeData(
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.black87,
            fontSize: 15,
          ),
          dataRowColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            // 当行被选中时
            if (states.contains(WidgetState.selected)) {
              return Colors.blue.withValues(alpha: 0.1);
            }
            // 当鼠标悬停在行上时
            if (states.contains(WidgetState.hovered)) {
              return Colors.grey.withValues(alpha: 0.05);
            }
            return null; // 默认颜色
          }),
        ),

        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // 统一输入框风格，让它看起来更现代
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
        ),
      ),

      // 根据是否为老用户进入不同的界面
      home: isOldUser ? const UnlockPage() : const ShellPage(),
    );
  }
}
