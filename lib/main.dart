/*
 * @Author: Thoma4
 * @Date: 2026-02-09 23:51:46
 * @LastEditTime: 2026-06-23 00:22:41
 * @Description: main
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'pages/shell_page.dart';
import 'services/storage_service.dart';
import 'services/settings_service.dart';

// 控制主题的变量
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 确保Flutter引擎绑定
  // 沉浸式状态栏
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }
  // 电脑端初始化
  if (Platform.isWindows) {
    sqfliteFfiInit(); // 初始化SQLite FFI引擎
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized(); // 初始化窗口管理器
    WindowOptions windowOptions = const WindowOptions(
      size: Size(800, 600),
      minimumSize: Size(800, 600),
      center: true,
      title: "Vault Keeper",
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  await SettingsService().init(); // 加载本地配置

  // 探测本地数据库是否存在
  final bool oldUser = await StorageService().isDatabaseExists();

  // 从配置中读取初始主题状态
  final settings = SettingsService();
  final isDark = settings.get('dark_mode') == 'true';
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(VaultApp(isOldUser: oldUser)); // 运行应用并传递状态
}

class VaultApp extends StatelessWidget {
  final bool isOldUser;
  const VaultApp({super.key, required this.isOldUser});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildLightTheme(), // 浅色主题
          darkTheme: _buildDarkTheme(), // 深色主题
          // 根据是否为老用户进入不同的界面
          home: isOldUser ? const UnlockPage() : const ShellPage(),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ).copyWith(
          primary: Colors.blue, // 主题色
          onSurfaceVariant: const Color.fromARGB(255, 81, 84, 90), // 副文字
          outlineVariant: const Color(0xFFC4C6D0), // 边框
          error: Colors.red,
        );
    return _buildBaseTheme(colorScheme);
  }

  ThemeData _buildDarkTheme() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF82B1FF), // 主题色
          onSurfaceVariant: const Color(0xFF8E9199), // 副文字
          // surfaceContainer: Color.fromARGB(255, 47, 47, 49),
        );
    return _buildBaseTheme(colorScheme);
  }

  ThemeData _buildBaseTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Segoe UI', //设置主字体
      // 遇到中文字符时按顺序寻找以下字体
      fontFamilyFallback: const [
        'Microsoft YaHei', // Windows 默认中文
        'PingFang SC', // iOS/macOS 默认中文
        'Hiragino Sans GB',
        'sans-serif',
      ],
      // 增强文本渲染清晰度（针对Windows）
      typography: Typography.material2021(platform: TargetPlatform.windows),
      textTheme: TextTheme(
        // 详情页的标签(如平台名称)使用较小、浅色的样式
        labelSmall: TextStyle(
          fontSize: 11,
          letterSpacing: 0.5,
          color: Colors.grey,
          fontWeight: FontWeight.w500,
        ),
        // 主要正文(如账号内容)
        bodyMedium: TextStyle(
          fontSize: 14,
          letterSpacing: 0.2,
          color: colorScheme.onSurface,
        ),
      ),

      // 反馈消息(悬浮圆角)
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        width: 400,
        backgroundColor: const Color.fromARGB(255, 32, 32, 32),
        contentTextStyle: const TextStyle(
          color: Colors.white, // 强制白色文字
          fontFamily: 'Segoe UI',
          fontFamilyFallback: ['Microsoft YaHei'],
        ),
      ),
      // 卡片配置
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // 统一输入框风格
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}
