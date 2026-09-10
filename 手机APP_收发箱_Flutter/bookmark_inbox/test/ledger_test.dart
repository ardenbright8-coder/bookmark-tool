// ---
// 这是啥: 账本存储测试——真 SQLite（ffi），CRUD/去重/状态机/确认幂等
// 谁看: 改 ledger.dart 的人
// 改之前必看: sqflite 在纯 dart 测试里跑不了，靠 sqflite_common_ffi 提供真 SQLite
// ---
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookmark_inbox/core/ledger.dart';
import 'package:bookmark_inbox/core/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LedgerStore store;

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('ledger_test');
    store = LedgerStore(factory: databaseFactory);
    await store.open(tmp.path);
  });

  tearDown(() async => store.close());

  LedgerEntry entry(String key, {String content = '内容', MsgType type = MsgType.note}) =>
      LedgerEntry(
        type: type,
        content: content,
        assignee: 'Pi',
        ts: DateTime.now().millisecondsSinceEpoch,
        dedupeKey: key,
      );

  test('插入+读取：最新在前', () async {
    await store.insertPending(entry('k1', content: '第一条'));
    await Future.delayed(const Duration(milliseconds: 5));
    await store.insertPending(entry('k2', content: '第二条'));
    final all = await store.entries();
    expect(all.length, 2);
    expect(all.first.content, '第二条');
  });

  test('dedupeKey 撞车不重复插，返回已存在 id', () async {
    final id1 = await store.insertPending(entry('dup'));
    final id2 = await store.insertPending(entry('dup'));
    expect(id1, id2);
    expect((await store.entries()).length, 1);
  });

  test('状态机：pending→sent→confirmed', () async {
    final id = await store.insertPending(entry('flow'));
    await store.markSent(id);
    expect((await store.byId(id))!.status, SendStatus.sent);
    final n = await store.markConfirmed('flow');
    expect(n, 1);
    expect((await store.byId(id))!.status, SendStatus.confirmed);
  });

  test('markConfirmed 幂等且未命中为 0', () async {
    await store.insertPending(entry('hit'));
    expect(await store.markConfirmed('hit'), 1);
    expect(await store.markConfirmed('hit'), 1); // 幂等：再确认一次也 ok
    expect(await store.markConfirmed('没有这条'), 0);
  });

  test('markFailed 记错误并累加次数，条目留在 pending', () async {
    final id = await store.insertPending(entry('f1'));
    await store.markFailed(id, '断网');
    await store.markFailed(id, '还是断网');
    final e = (await store.byId(id))!;
    expect(e.status, SendStatus.pending);
    expect(e.attempts, 2);
    expect(e.lastError, '还是断网');
    expect((await store.pendingEntries()).length, 1);
  });

  test('删除', () async {
    final id = await store.insertPending(entry('del'));
    await store.deleteEntry(id);
    expect(await store.byId(id), isNull);
  });
}
