// ---
// 这是啥: 账本条目模型 + 业务消息 JSON 编解码（手机↔电脑唯一协议）
// 谁看: 通道核心各件与界面都经它
// 什么时候用: 构造/解析上行消息、读写账本行时
// 改之前必看: 电脑端收信模块把原消息原样回发当回执，dedupeKey 是两端匹配键，别改名；
//   attachments 只存文件名（不含路径），图不进 JSON、不上传邮局
// ---
import 'dart:convert';

/// 业务消息类型。cmd 为未来云 Agent 预留：收到只入库，绝不执行。
enum MsgType { note, bookmark, task, cmd }

MsgType msgTypeFrom(String? s) => MsgType.values
    .firstWhere((e) => e.name == s, orElse: () => MsgType.note);

/// 账本状态：0 待发 / 1 已发未确认 / 2 已确认
enum SendStatus { pending, sent, confirmed }

SendStatus statusFrom(int v) =>
    SendStatus.values.firstWhere((e) => e.index == v, orElse: () => SendStatus.pending);

/// 协议约定：附件只记文件名。剥掉路径/穿越，空或 `.`/`..` 丢弃。
String attachmentFileName(String raw) {
  var t = raw.trim().replaceAll('\\', '/');
  final i = t.lastIndexOf('/');
  if (i >= 0) t = t.substring(i + 1);
  if (t.isEmpty || t == '.' || t == '..') return '';
  return t;
}

/// 从 JSON 数组或账本 TEXT 列解析附件文件名列表。垃圾输入给空列表，不抛。
List<String> attachmentNamesFrom(Object? raw) {
  if (raw == null) return const [];
  Object? v = raw;
  if (v is String) {
    if (v.isEmpty) return const [];
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    if (e is! String) continue;
    final name = attachmentFileName(e);
    if (name.isNotEmpty) out.add(name);
  }
  return out;
}

/// 本地账本一行（一条上行记录）
class LedgerEntry {
  LedgerEntry({
    this.id,
    required this.type,
    required this.content,
    this.assignee = '',
    required this.ts,
    required this.dedupeKey,
    this.status = SendStatus.pending,
    this.attempts = 0,
    this.lastError = '',
    List<String> attachments = const [],
  }) : attachments = attachmentNamesFrom(attachments);

  final int? id;
  MsgType type;
  String content;
  String assignee;
  final int ts;
  final String dedupeKey;
  SendStatus status;
  int attempts;
  String lastError;
  List<String> attachments;

  /// 上行业务 JSON（放进 ntfy message 字段的载荷）
  String encodePayload() => jsonEncode({
        'v': 1,
        'type': type.name,
        'content': content,
        'assignee': assignee,
        'ts': ts,
        'dedupeKey': dedupeKey,
        'attachments': attachments,
      });

  /// 解析收到的业务 JSON（回执里用它取 dedupeKey）。垃圾数据返回 null，不抛。
  static Map<String, Object?>? tryDecodePayload(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['dedupeKey'] is! String || (m['dedupeKey'] as String).isEmpty) {
        return null;
      }
      return {
        'v': m['v'] is int ? m['v'] : 1,
        'type': msgTypeFrom(m['type'] as String?).name,
        'content': m['content'] is String ? m['content'] as String : '',
        'assignee': m['assignee'] is String ? m['assignee'] as String : '',
        'ts': m['ts'] is int ? m['ts'] as int : 0,
        'dedupeKey': m['dedupeKey'] as String,
        'attachments': attachmentNamesFrom(m['attachments']),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'type': type.name,
        'content': content,
        'assignee': assignee,
        'ts': ts,
        'dedupeKey': dedupeKey,
        'status': status.index,
        'attempts': attempts,
        'lastError': lastError,
        'attachments': jsonEncode(attachments),
      };

  factory LedgerEntry.fromRow(Map<String, Object?> row) => LedgerEntry(
        id: row['id'] as int?,
        type: msgTypeFrom(row['type'] as String?),
        content: row['content'] as String? ?? '',
        assignee: row['assignee'] as String? ?? '',
        ts: row['ts'] as int? ?? 0,
        dedupeKey: row['dedupeKey'] as String? ?? '',
        status: statusFrom(row['status'] as int? ?? 0),
        attempts: row['attempts'] as int? ?? 0,
        lastError: row['lastError'] as String? ?? '',
        attachments: attachmentNamesFrom(row['attachments']),
      );
}
