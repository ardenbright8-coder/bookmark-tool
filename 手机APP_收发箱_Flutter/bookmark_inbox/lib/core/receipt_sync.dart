// ---
// 这是啥: 回执同步——从邮局补拉回执主题，按 dedupeKey 把账本项标「已确认」
// 谁看: main（启动补拉）、账本页（下拉刷新时顺带同步）
// 什么时候用: APP 前台期间对账；没有后台常驻，打开即对账
// 改之前必看: 电脑端回执 = 原业务 JSON 原样回发，靠 dedupeKey 匹配；解析失败的行直接跳过
// ---
import 'config.dart';
import 'ledger.dart';
import 'models.dart';
import 'ntfy_client.dart';

class ReceiptSync {
  ReceiptSync({required this.store, required this.client});

  final LedgerStore store;
  final NtfyClient client;

  /// 返回本轮确认条数。[since] 缺省拉邮局缓存全窗（7 天），confirm 幂等不怕重复。
  /// [onNewlyConfirmed]：本轮新变「已确认」的记录内容列表（用于弹本地通知），可为空。
  Future<int> sync(ChannelConfig cfg,
      {String since = '168h',
      void Function(List<String> contents)? onNewlyConfirmed}) async {
    if (!cfg.isConfigured) return 0;
    final events = await client.pollJsonEvents(
      server: cfg.server,
      topic: cfg.receiptTopic,
      user: cfg.user.isEmpty ? null : cfg.user,
      pass: cfg.pass.isEmpty ? null : cfg.pass,
      since: since,
    );
    var confirmed = 0;
    final freshContents = <String>[];
    for (final ev in events) {
      final msg = ev['message'];
      if (msg is! String) continue;
      final payload = LedgerEntry.tryDecodePayload(msg);
      if (payload == null) continue; // 别人发的非协议消息，跳过
      // 只把「这轮真的从非确认变确认」的记为新鲜，已确认的不重复弹通知
      final fresh = await store.unconfirmedByKey(payload['dedupeKey'] as String);
      if (fresh.isEmpty) continue;
      confirmed += await store.markConfirmed(payload['dedupeKey'] as String);
      freshContents.addAll(fresh.map((e) => e.content));
    }
    if (onNewlyConfirmed != null && freshContents.isNotEmpty) {
      onNewlyConfirmed(freshContents);
    }
    return confirmed;
  }
}
