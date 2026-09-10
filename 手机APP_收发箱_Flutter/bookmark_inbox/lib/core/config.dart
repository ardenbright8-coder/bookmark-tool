// ---
// 这是啥: 通道配置——邮局地址、账号、上下行主题，SharedPreferences 持久化
// 谁看: main（启动装载）、输入页（改配置入口将来挂这）、sender/receipt_sync
// 什么时候用: 每次发送/补拉回执前读一份
// 改之前必看: 默认 server 已填阿里云邮局占位（http://116.62.217.189，IP直连HTTP版）；
//   账号密码不在代码里——用户在设置页填一次（真值出处见 deploy\服务器信息（本地·不进git）.md，只读）；
//   测试期也可改成 https://ntfy.sh（公共服务器无账号，user/pass 留空）
// ---
import 'package:shared_preferences/shared_preferences.dart';

class ChannelConfig {
  ChannelConfig({
    required this.server,
    required this.user,
    required this.pass,
    required this.upTopic,
    required this.receiptTopic,
  });

  /// 默认邮局占位（部署实录见通道区）。换服务器/上HTTPS时改这里或设置页。
  static const defaultServer = 'http://116.62.217.189';

  /// 邮局基址，不带尾斜杠（如 https://ntfy.example.com）
  final String server;
  final String user;
  final String pass;
  final String upTopic;
  final String receiptTopic;

  bool get isConfigured => server.trim().isNotEmpty;

  static const _kServer = 'cfg.server';
  static const _kUser = 'cfg.user';
  static const _kPass = 'cfg.pass';
  static const _kUp = 'cfg.upTopic';
  static const _kReceipt = 'cfg.receiptTopic';

  static Future<ChannelConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return ChannelConfig(
      server: p.getString(_kServer) ?? defaultServer,
      user: p.getString(_kUser) ?? '',
      pass: p.getString(_kPass) ?? '',
      upTopic: p.getString(_kUp) ?? 'bookmark-up',
      receiptTopic: p.getString(_kReceipt) ?? 'bookmark-receipt',
    );
  }

  static Future<void> save({
    required String server,
    required String user,
    required String pass,
    required String upTopic,
    required String receiptTopic,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, server.trim().replaceAll(RegExp(r'/+$'), ''));
    await p.setString(_kUser, user.trim());
    await p.setString(_kPass, pass);
    await p.setString(_kUp, upTopic.trim());
    await p.setString(_kReceipt, receiptTopic.trim());
  }
}
