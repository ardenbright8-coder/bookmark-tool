// ---
// 这是啥: ntfy 邮局 HTTP 客户端——上行发布 + 回执补拉（poll JSON）
// 谁看: sender（发送）、receipt_sync（补拉回执）
// 什么时候用: 每次联网收发
// 改之前必看: publish 的 body 是 ntfy 的发布格式（topic/title/message/tags），
//   业务 JSON 字符串装在 message 字段里，别拆散；auth 为 Basic，公共服务器可留空
// ---
import 'dart:convert';

import 'package:http/http.dart' as http;

class PublishResult {
  PublishResult({required this.ok, this.error, this.serverId});
  final bool ok;
  final String? error;
  final String? serverId;
}

class NtfyClient {
  NtfyClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String? user, String? pass) => {
        'Content-Type': 'application/json',
        if (user != null && user.isNotEmpty && pass != null)
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };

  /// 发布一条消息（message 字段=业务 JSON 字符串）
  Future<PublishResult> publish({
    required String server,
    required String topic,
    String? user,
    String? pass,
    String? title,
    required String message,
    List<String> tags = const [],
  }) async {
    try {
      final uri = Uri.parse('$server/$topic');
      final res = await _client
          .post(
            uri,
            headers: _headers(user, pass),
            body: jsonEncode({
              'topic': topic,
              if (title != null && title.isNotEmpty) 'title': title,
              'message': message,
              if (tags.isNotEmpty) 'tags': tags,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        String? id;
        try {
          id = jsonDecode(res.body)['id'] as String?;
        } catch (_) {}
        return PublishResult(ok: true, serverId: id);
      }
      return PublishResult(ok: false, error: 'HTTP ${res.statusCode}');
    } catch (e) {
      return PublishResult(ok: false, error: e.toString());
    }
  }

  /// 补拉一个主题的缓存消息（回执同步用）。poll=1 立即返回不挂流。
  /// [since] 可为时长（如 168h）或某消息 id。只喂 event==='message' 的事件。
  Future<List<Map<String, Object?>>> pollJsonEvents({
    required String server,
    required String topic,
    String? user,
    String? pass,
    String since = '168h',
  }) async {
    try {
      final uri =
          Uri.parse('$server/$topic/json?poll=1&since=${Uri.encodeComponent(since)}');
      final res = await _client
          .get(uri, headers: _headers(user, pass))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return const [];
      final events = <Map<String, Object?>>[];
      for (final line in const LineSplitter().convert(utf8.decode(res.bodyBytes))) {
        if (line.trim().isEmpty) continue;
        try {
          final ev = jsonDecode(line);
          if (ev is Map && ev['event'] == 'message') {
            events.add(Map<String, Object?>.from(ev));
          }
        } catch (_) {/* 坏行跳过 */}
      }
      return events;
    } catch (_) {
      return const [];
    }
  }

  void close() => _client.close();
}
