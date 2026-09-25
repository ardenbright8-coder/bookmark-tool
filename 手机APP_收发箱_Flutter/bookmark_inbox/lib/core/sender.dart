// ---
// 这是啥: 发送编排——落库→发送→状态机（待发→已发→失败回待发），含待发自动重发
// 谁看: 界面（记一笔/下拉重发）、main（启动时自动补发）
// 什么时候用: 每次发送与重试
// 改之前必看: 先落库后发送是「消息永不丢」的根基，顺序别倒；网络异常一律记 lastError 不抛
// ---
import 'dart:convert';
import 'dart:math';

import 'ledger.dart';
import 'models.dart';
import 'ntfy_client.dart';
import 'config.dart';

class Sender {
  Sender({required this.store, required this.client, required this.configLoader});

  final LedgerStore store;
  final NtfyClient client;
  final Future<ChannelConfig> Function() configLoader;

  /// 组一条新记录并发送。返回账本 id。
  /// [attachments] 只收文件名；图不进 JSON、不走邮局。
  Future<int> composeAndSend({
    MsgType type = MsgType.note,
    required String content,
    String assignee = '',
    List<String> attachments = const [],
  }) async {
    final entry = LedgerEntry(
      type: type,
      content: content,
      assignee: assignee,
      ts: DateTime.now().millisecondsSinceEpoch,
      dedupeKey: _newDedupeKey(),
      attachments: attachments,
    );
    final id = await store.insertPending(entry);
    await _attempt(id);
    return id;
  }

  /// 把所有待发（含失败回退的）按时间序重发一遍。返回尝试条数。
  Future<int> retryPending() async {
    final pending = await store.pendingEntries();
    for (final e in pending) {
      await _attempt(e.id!);
    }
    return pending.length;
  }

  Future<void> _attempt(int id) async {
    final entry = await store.byId(id);
    if (entry == null) return;
    final cfg = await configLoader();
    if (!cfg.isConfigured) {
      await store.markFailed(id, '邮局未配置（设置里填服务器地址）');
      return;
    }
    final r = await client.publish(
      server: cfg.server,
      topic: cfg.upTopic,
      user: cfg.user.isEmpty ? null : cfg.user,
      pass: cfg.pass.isEmpty ? null : cfg.pass,
      title: entry.assignee.isEmpty ? '记一笔' : '给 ${entry.assignee}',
      message: entry.encodePayload(),
      tags: const ['bookmark_tabs'],
    );
    if (r.ok) {
      await store.markSent(id);
    } else {
      await store.markFailed(id, r.error ?? '未知错误');
    }
  }

  /// 手机上挪组 / 删条（设定19）：发一条 type=op 的命令到上行主题，电脑收信时照做。
  /// [assignee] 空＝挪回待定。命令不进本地账本（看板以电脑为准，下一份整板就能看到结果）；发不出去返回 false，不抛。
  Future<bool> sendOp({required String op, required String id, String assignee = ''}) async {
    final cfg = await configLoader();
    if (!cfg.isConfigured) return false;
    final r = await client.publish(
      server: cfg.server,
      topic: cfg.upTopic,
      user: cfg.user.isEmpty ? null : cfg.user,
      pass: cfg.pass.isEmpty ? null : cfg.pass,
      title: op == 'delete' ? '删一条' : '挪一条',
      message: jsonEncode({
        'v': 1,
        'type': 'op',
        'op': op,
        'id': id,
        'assignee': assignee,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'dedupeKey': _newDedupeKey(),
      }),
      tags: const ['bookmark_tabs'],
    );
    return r.ok;
  }

  static String _newDedupeKey() {
    final r = Random();
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = List.generate(8, (_) => r.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0')).join();
    return '$ms-$rand';
  }
}
