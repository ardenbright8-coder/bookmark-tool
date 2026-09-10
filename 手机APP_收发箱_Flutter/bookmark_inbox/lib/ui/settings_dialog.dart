// ---
// 这是啥: 邮局设置对话框——服务器/账号/上下行主题，SharedPreferences 持久化
// 谁看: 输入页右上角齿轮
// 什么时候用: 换邮局地址、填账号密码；测试期可填 https://ntfy.sh（账号留空）
// 改之前必看: 密码明文存本地（自用场景拍板接受），别截图外传
// ---
import 'package:flutter/material.dart';

import '../core/config.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _up = TextEditingController();
  final _receipt = TextEditingController();

  @override
  void initState() {
    super.initState();
    ChannelConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _server.text = c.server;
        _user.text = c.user;
        _pass.text = c.pass;
        _up.text = c.upTopic;
        _receipt.text = c.receiptTopic;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_server, _user, _pass, _up, _receipt]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ChannelConfig.save(
      server: _server.text,
      user: _user.text,
      pass: _pass.text,
      upTopic: _up.text,
      receiptTopic: _receipt.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('邮局设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _server,
              decoration: const InputDecoration(
                labelText: '邮局地址',
                hintText: 'https://ntfy.example.com（测试可填 https://ntfy.sh）',
              ),
            ),
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: '账号（可空）'),
            ),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码（可空）'),
            ),
            TextField(
              controller: _up,
              decoration: const InputDecoration(labelText: '上行主题'),
            ),
            TextField(
              controller: _receipt,
              decoration: const InputDecoration(labelText: '回执主题'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
