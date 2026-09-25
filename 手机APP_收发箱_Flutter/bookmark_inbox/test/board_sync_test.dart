// ---
// 这是啥: 看板同步测试（设定19）——拉电脑发来的整板、断网看上一份、手机挪组删条的命令、哪些是自己发了还没进看板的
// 谁看: 改 board_sync.dart / sender.dart 发命令那段的人
// 改之前必看: 只测逻辑，不连真中转站；期望答案都手写，不拿被测函数算
// ---
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookmark_inbox/core/board_sync.dart';
import 'package:bookmark_inbox/core/config.dart';
import 'package:bookmark_inbox/core/ledger.dart';
import 'package:bookmark_inbox/core/models.dart';
import 'package:bookmark_inbox/core/ntfy_client.dart';
import 'package:bookmark_inbox/core/sender.dart';

final _cfg = ChannelConfig(
  server: 'https://mail.test',
  user: 'u',
  pass: 'p',
  upTopic: 'bookmark-up',
  receiptTopic: 'bookmark-receipt',
);

String _board(int ts, List<Map<String, Object?>> items, {String mode = 'day'}) => jsonEncode({
      'v': 1,
      'type': 'board',
      'ts': ts,
      'mode': mode,
      'agents': ['Claude', 'Antigravity', 'Hermes'],
      'items': items,
    });

Map<String, Object?> _item(String id, String text, {String? assignee, String? claimedBy, String? report, String? dedupeKey}) => {
      'id': id,
      'text': text,
      'assignee': assignee,
      'kind': 'note',
      'detail': null,
      'bundleId': null,
      'claimedBy': claimedBy,
      'report': report,
      'reportedBy': report == null ? null : 'Claude-7',
      'reportedAt': report == null ? null : '2026-09-24T03:00:00.000Z',
      'dedupeKey': dedupeKey,
      'url': null,
      'images': 0,
    };

String _events(List<String> messages) => messages
    .map((m) => jsonEncode({'event': 'message', 'id': 'e${m.hashCode}', 'message': m}))
    .join('\n');

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('BoardSnapshot.tryParse：字段齐全读得出；不是整板、坏 JSON 一律 null 不抛', () {
    final snap = BoardSnapshot.tryParse(_board(5, [_item('a', '甲', assignee: 'Claude', claimedBy: 'Claude-3')], mode: 'sleep'))!;
    expect(snap.ts, 5);
    expect(snap.sleep, isTrue);
    expect(snap.agents, ['Claude', 'Antigravity', 'Hermes']);
    expect(snap.items.single.id, 'a');
    expect(snap.items.single.assignee, 'Claude');
    expect(snap.items.single.claimedBy, 'Claude-3');
    expect(BoardSnapshot.tryParse('不是json'), isNull);
    expect(BoardSnapshot.tryParse('{"type":"note"}'), isNull);
    expect(BoardSnapshot.tryParse('[1,2]'), isNull);
  });

  test('fetch：先拉最近 1 小时，没有再放宽到 1 天、7 天；拿最后一份整板；认证头和主题对', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add(req.url.queryParameters['since'] ?? '');
      expect(req.url.path, '/bookmark-board/json');
      expect(req.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('u:p'))}');
      if (req.url.queryParameters['since'] == '1h') return http.Response.bytes(utf8.encode(''), 200);
      return http.Response.bytes(
          utf8.encode(_events([_board(1, [_item('old', '旧')]), '不是整板', _board(2, [_item('new', '新')])])), 200);
    });
    final snap = await BoardSync(client: NtfyClient(client: client)).fetch(_cfg);
    expect(asked, ['1h', '24h']);
    expect(snap!.items.single.id, 'new');
  });

  test('fetch：断网拉不到就给上一份存下来的；从来没拉到过给 null', () async {
    final ok = MockClient((req) async => http.Response.bytes(utf8.encode(_events([_board(9, [_item('a', '存着的')])])), 200));
    expect((await BoardSync(client: NtfyClient(client: ok)).fetch(_cfg))!.ts, 9);
    final down = MockClient((req) async => throw const SocketException('断网'));
    final cached = await BoardSync(client: NtfyClient(client: down)).fetch(_cfg);
    expect(cached!.ts, 9);
    expect(cached.items.single.text, '存着的');
    SharedPreferences.setMockInitialValues({});
    expect(await BoardSync(client: NtfyClient(client: down)).fetch(_cfg), isNull);
  });

  test('sendOp：挪组 / 删条发到上行主题，type=op、带目标 id 和 dedupeKey；空组名＝挪回待定', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      bodies.add(jsonDecode(jsonDecode(req.body)['message'] as String) as Map<String, dynamic>);
      expect(req.url.path, '/bookmark-up');
      return http.Response('{"id":"x"}', 200);
    });
    final tmp = await Directory.systemTemp.createTemp('op_test');
    final store = LedgerStore(factory: databaseFactory);
    await store.open(tmp.path);
    final sender = Sender(store: store, client: NtfyClient(client: client), configLoader: () async => _cfg);
    expect(await sender.sendOp(op: 'assign', id: 'a', assignee: 'Hermes'), isTrue);
    expect(await sender.sendOp(op: 'delete', id: 'b'), isTrue);
    expect(bodies[0]['type'], 'op');
    expect(bodies[0]['op'], 'assign');
    expect(bodies[0]['id'], 'a');
    expect(bodies[0]['assignee'], 'Hermes');
    expect((bodies[0]['dedupeKey'] as String).isNotEmpty, isTrue);
    expect(bodies[1]['op'], 'delete');
    expect(bodies[1]['id'], 'b');
    expect((await store.entries()).isEmpty, isTrue, reason: '命令不进本地账本');
    await store.close();
  });

  test('sendOp：发不出去返回 false 不抛', () async {
    final tmp = await Directory.systemTemp.createTemp('op_test2');
    final store = LedgerStore(factory: databaseFactory);
    await store.open(tmp.path);
    final down = MockClient((req) async => http.Response('nope', 500));
    final sender = Sender(store: store, client: NtfyClient(client: down), configLoader: () async => _cfg);
    expect(await sender.sendOp(op: 'delete', id: 'b'), isFalse);
    await store.close();
  });

  test('notOnBoardYet：自己发的条目，看板上已经有同 dedupeKey 的就不再单列；没整板时全列', () {
    LedgerEntry e(String key, String text) =>
        LedgerEntry(type: MsgType.note, content: text, ts: 1, dedupeKey: key);
    final mine = [e('k1', '已进看板'), e('k2', '还在路上')];
    final snap = BoardSnapshot.tryParse(_board(1, [_item('a', '已进看板', dedupeKey: 'k1')]))!;
    expect(notOnBoardYet(mine, snap).map((x) => x.content), ['还在路上']);
    expect(notOnBoardYet(mine, null).length, 2);
    // 在看板上出现过、后来电脑上删掉了：不能又冒出来说「等电脑收」
    final later = BoardSnapshot.tryParse(_board(2, []))!;
    expect(notOnBoardYet(mine, later, seen: {'k1'}).map((x) => x.content), ['还在路上']);
    // 老版本发的、电脑早就回执收到了、比这份整板早 10 分钟以上、看板上又没有＝电脑上删了，也不列
    final snapTs = DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;
    LedgerEntry sent(String key, int ts, SendStatus s) =>
        LedgerEntry(type: MsgType.note, content: key, ts: ts, dedupeKey: key, status: s);
    final old = [
      sent('老的已收', snapTs - 11 * 60000, SendStatus.confirmed),
      sent('刚收到', snapTs - 2 * 60000, SendStatus.confirmed),
      sent('老的没回执', snapTs - 60 * 60000, SendStatus.sent),
    ];
    final snap2 = BoardSnapshot.tryParse(_board(snapTs, []))!;
    expect(notOnBoardYet(old, snap2).map((x) => x.content), ['刚收到', '老的没回执']);
  });

  test('fetch：拉到的整板里出现过的 dedupeKey 都记下来（seenKeys），下次整板没有了也还记得', () async {
    final first = MockClient((req) async =>
        http.Response.bytes(utf8.encode(_events([_board(1, [_item('a', '甲', dedupeKey: 'k1')])])), 200));
    await BoardSync(client: NtfyClient(client: first)).fetch(_cfg);
    final second = MockClient((req) async => http.Response.bytes(utf8.encode(_events([_board(2, [])])), 200));
    await BoardSync(client: NtfyClient(client: second)).fetch(_cfg);
    expect(await BoardSync.seenKeys(), {'k1'});
  });

  test('displayText：图片标记换成 🖼，别的字不动', () {
    expect(displayText('看这里[图片:image-1a.png]和这[图片:image-2.png]'), '看这里🖼和这🖼');
    expect(displayText('没有图'), '没有图');
  });

  test('项目页：整板带 projects 就解析成一棵树；老电脑不带＝null；按路径找夹里有什么，夹没了给 null', () {
    final raw = jsonEncode({
      'type': 'board',
      'ts': 1,
      'items': [],
      'projects': [
        {
          'name': '中医',
          'path': '中医',
          'dir': true,
          'children': [
            {'name': '设计思路.md', 'path': '中医/设计思路.md', 'dir': false, 'content': '先看舌苔'},
            {'name': '方子', 'path': '中医/方子', 'dir': true, 'children': []},
          ],
        },
        {'name': '长.md', 'path': '长.md', 'dir': false, 'content': '前半截', 'truncated': true},
        {'name': '坏的'},
      ],
    });
    final snap = BoardSnapshot.tryParse(raw)!;
    final roots = snap.projects!;
    expect(roots.map((n) => n.name).toList(), ['中医', '长.md']);
    expect(roots[1].truncated, isTrue);
    expect(projectChildrenAt(roots, '')!.length, 2);
    expect(projectChildrenAt(roots, '中医')!.map((n) => n.name).toList(), ['设计思路.md', '方子']);
    expect(projectChildrenAt(roots, '中医')!.first.content, '先看舌苔');
    expect(projectChildrenAt(roots, '中医/方子'), isEmpty);
    expect(projectChildrenAt(roots, '中医/不在了'), isNull);
    expect(BoardSnapshot.tryParse(jsonEncode({'type': 'board', 'ts': 1, 'items': []}))!.projects, isNull);
  });
}
