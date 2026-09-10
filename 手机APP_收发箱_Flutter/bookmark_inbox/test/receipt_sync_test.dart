// ---
// 这是啥: 回执同步测试——MockClient 伪造邮局回执流，验证按 dedupeKey 确认
// 谁看: 改 receipt_sync.dart 的人
// ---
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookmark_inbox/core/config.dart';
import 'package:bookmark_inbox/core/ledger.dart';
import 'package:bookmark_inbox/core/models.dart';
import 'package:bookmark_inbox/core/ntfy_client.dart';
import 'package:bookmark_inbox/core/receipt_sync.dart';
import 'package:bookmark_inbox/core/sender.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LedgerStore store;
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('receipt_test');
    store = LedgerStore(factory: databaseFactory);
    await store.open(tmp.path);
  });
  tearDown(() async => store.close());

  test('回执流里的 dedupeKey 命中即确认；非协议消息跳过；poll 请求参数正确', () async {
    final sender = Sender(
      store: store,
      client: NtfyClient(client: MockClient((req) async => http.Response('{"id":"m1"}', 200))),
      configLoader: () async => const _Cfg(),
    );
    final id = await sender.composeAndSend(content: '等我确认');
    final entry = (await store.byId(id))!;
    await store.markSent(id);

    // 伪造邮局回执：两行 JSON 事件——一条真回执（原消息原样回发），一条别人的闲聊
    final receiptLine = jsonEncode({
      'event': 'message', 'id': 'r1', 'title': '已收录',
      'message': entry.encodePayload(),
    });
    final noiseLine = jsonEncode({
      'event': 'message', 'id': 'r2', 'title': '闲聊', 'message': '今天天气不错',
    });
    Uri? polled;
    // Mock 响应必须用 UTF-8 字节：http.Response(String) 默认按 latin1 编码，含中文会抛错
    final client = MockClient((req) async {
      polled = req.url;
      return http.Response.bytes(utf8.encode('$receiptLine\n$noiseLine\n'), 200);
    });

    final n = await ReceiptSync(store: store, client: NtfyClient(client: client)).sync(const _Cfg());

    expect(n, 1);
    expect((await store.byId(id))!.status, SendStatus.confirmed);
    expect(polled!.host, 'mail.test');
    expect(polled!.path, '/bookmark-receipt/json');
    expect(polled!.queryParameters['poll'], '1');
  });

  test('邮局未配置：sync 直接 0，不发请求', () async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('', 200);
    });
    final n = await ReceiptSync(store: store, client: NtfyClient(client: client)).sync(const _CfgEmpty());
    expect(n, 0);
    expect(called, false);
  });
}

class _Cfg implements ChannelConfig {
  const _Cfg();
  @override
  String get server => 'https://mail.test';
  @override
  String get user => 'u';
  @override
  String get pass => 'p';
  @override
  String get upTopic => 'bookmark-up';
  @override
  String get receiptTopic => 'bookmark-receipt';
  @override
  bool get isConfigured => true;
}

class _CfgEmpty extends _Cfg {
  const _CfgEmpty();
  @override
  String get server => '';
  @override
  bool get isConfigured => false;
}
