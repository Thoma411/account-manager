/*
 * @Author: Thoma4
 * @Date: 2026-08-07 00:33:58
 * @LastEditTime: 2026-08-07 00:49:47
 * @Description: 使用帮助页
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// 使用帮助页
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  late final Future<String> _contentFuture;

  @override
  void initState() {
    super.initState();
    // 读取assets/docs中的帮助文档
    _contentFuture = rootBundle.loadString('assets/docs/help.md');
  }

  // 处理文档内链接点击(跳转浏览)
  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href == null || href.isEmpty) return;
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("使用帮助"),
        centerTitle: false,
      ),
      body: FutureBuilder<String>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "帮助文档加载失败：\n${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          }
          return Markdown(
            data: snapshot.data!,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
            onTapLink: _onTapLink,
          );
        },
      ),
    );
  }
}
