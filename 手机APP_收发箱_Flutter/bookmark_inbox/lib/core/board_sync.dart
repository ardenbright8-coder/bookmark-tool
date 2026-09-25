// ---
// 这是啥: 看板同步（设定19）——拉电脑发到中转站的整板（bookmark-board 主题，电脑只写、手机只读），断网时给上一份
// 谁看: 看板页（打开、下拉刷新时拉）
// 什么时候用: 每次要看电脑那边的看板
// 改之前必看: 中转站 ntfy 2.11 不支持「只要最新一条」，所以先拉 1 小时、没有再放宽到 1 天、7 天（缓存最多 7 天）；
//   电脑开着时每 6 小时补发一份，所以一般 1 小时或 1 天内就有。拉到的整板原样存进 SharedPreferences 当断网备份。
//   🚫 禁 import 任何 widget（core 层规矩）
// ---
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';
import 'ntfy_client.dart';

/// 看板上的一条（电脑 board-sync.ts 的 BoardItem 同形）
class BoardItem {
  BoardItem({
    required this.id,
    required this.text,
    this.assignee,
    this.kind = 'note',
    this.detail,
    this.bundleId,
    this.claimedBy,
    this.report,
    this.reportedBy,
    this.reportedAt,
    this.dedupeKey,
    this.url,
    this.images = 0,
  });

  final String id;
  final String text;
  final String? assignee;
  final String kind;
  final String? detail;
  final String? bundleId;
  final String? claimedBy;
  final String? report;
  final String? reportedBy;
  final String? reportedAt;
  final String? dedupeKey;
  final String? url;
  final int images;

  bool get isHandoff => kind == 'handoff';

  static String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;

  factory BoardItem.fromJson(Map<String, dynamic> m) => BoardItem(
        id: m['id'] as String,
        text: m['text'] is String ? m['text'] as String : '',
        assignee: _s(m['assignee']),
        kind: m['kind'] == 'handoff' ? 'handoff' : 'note',
        detail: _s(m['detail']),
        bundleId: _s(m['bundleId']),
        claimedBy: _s(m['claimedBy']),
        report: _s(m['report']),
        reportedBy: _s(m['reportedBy']),
        reportedAt: _s(m['reportedAt']),
        dedupeKey: _s(m['dedupeKey']),
        url: _s(m['url']),
        images: m['images'] is int ? m['images'] as int : 0,
      );
}

/// 电脑发来的一整板
class BoardSnapshot {
  BoardSnapshot({required this.ts, required this.sleep, required this.agents, required this.items});

  /// 电脑抄这一份的时间（毫秒）
  final int ts;

  /// 电脑现在是不是 🌙 睡觉档
  final bool sleep;
  final List<String> agents;

  /// 看板顺序（每组里从上到下）
  final List<BoardItem> items;

  /// 解析整板 JSON。不是整板、坏数据一律 null，不抛。
  static BoardSnapshot? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['type'] != 'board' || m['items'] is! List) return null;
      return BoardSnapshot(
        ts: m['ts'] is int ? m['ts'] as int : 0,
        sleep: m['mode'] == 'sleep',
        agents: (m['agents'] is List ? m['agents'] as List : const []).whereType<String>().toList(),
        items: (m['items'] as List)
            .whereType<Map>()
            .where((e) => e['id'] is String)
            .map((e) => BoardItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class BoardSync {
  BoardSync({required this.client});

  final NtfyClient client;
  static const _kCache = 'board.snapshot';
  static const _kSeen = 'board.seenKeys';

  /// 在电脑整板上出现过的 dedupeKey（手机发的条目进过看板）。进过看板、后来电脑上删了的，手机不能再列成「等电脑收」。
  static Future<Set<String>> seenKeys() async =>
      ((await SharedPreferences.getInstance()).getStringList(_kSeen) ?? const <String>[]).toSet();

  static Future<void> _remember(SharedPreferences prefs, BoardSnapshot snap) async {
    final keys = snap.items.map((i) => i.dedupeKey).whereType<String>();
    final all = <String>[...(prefs.getStringList(_kSeen) ?? const <String>[])];
    var changed = false;
    for (final k in keys) {
      if (!all.contains(k)) {
        all.add(k);
        changed = true;
      }
    }
    // 只留最近 2000 个，够用又不越攒越大
    if (changed) await prefs.setStringList(_kSeen, all.length > 2000 ? all.sublist(all.length - 2000) : all);
  }

  /// 拉最新一份整板：1 小时 → 1 天 → 7 天，哪个窗口里有就拿最后一份；都没有（断网）给上一份存下来的，从没拉到过给 null。
  Future<BoardSnapshot?> fetch(ChannelConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    if (cfg.isConfigured) {
      for (final since in const ['1h', '24h', '168h']) {
        final events = await client.pollJsonEvents(
          server: cfg.server,
          topic: cfg.boardTopic,
          user: cfg.user.isEmpty ? null : cfg.user,
          pass: cfg.pass.isEmpty ? null : cfg.pass,
          since: since,
        );
        for (final ev in events.reversed) {
          final msg = ev['message'];
          if (msg is! String) continue;
          final snap = BoardSnapshot.tryParse(msg);
          if (snap == null) continue;
          await prefs.setString(_kCache, msg);
          await _remember(prefs, snap);
          return snap;
        }
      }
    }
    final cached = prefs.getString(_kCache);
    return cached == null ? null : BoardSnapshot.tryParse(cached);
  }
}

/// 自己发的条目里，看板上还没有的（电脑还没收到、或收到了但还没抄下一份）。没整板就全算。
/// [seen]＝在以前的整板上出现过的：进过看板又被删了，不算「还没到」。
/// 电脑早就回执收到了、又比这份整板早 10 分钟以上发的，看板上没有也＝电脑上删了（老版本发的没记过 seen，靠这条兜）。
List<LedgerEntry> notOnBoardYet(List<LedgerEntry> mine, BoardSnapshot? snap, {Set<String> seen = const {}}) {
  if (snap == null) return mine;
  final onBoard = snap.items.map((i) => i.dedupeKey).whereType<String>().toSet();
  bool gone(LedgerEntry e) => e.status == SendStatus.confirmed && e.ts < snap.ts - 10 * 60 * 1000;
  return mine.where((e) => !onBoard.contains(e.dedupeKey) && !seen.contains(e.dedupeKey) && !gone(e)).toList();
}

/// 看板正文里的图片标记（电脑本机的图，不上传中转站）换成 🖼
String displayText(String text) => text.replaceAll(RegExp(r'\[图片:image-[a-zA-Z0-9-]+\.png\]'), '🖼');
